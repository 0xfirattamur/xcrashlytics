//
//  Groups.swift
//  xcrashlytics
//
//  Created by FIRAT TAMUR on 8.06.2026.
//

import ArgumentParser
import Foundation
import XCrashlyticsCore

struct GroupsCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "groups",
        abstract: "Show related Firebase issues and optional Xcode crashes."
    )

    @Option(name: .long, help: "Output format: text (default) or json.")
    var format: OutputFormat = .text

    @Option(name: .long, help: "Maximum number of Firebase issues to fetch.")
    var firebaseLimit: Int = 100

    @Argument(help: "Optional Firebase issue id, for example FB-ISSUE_ID.")
    var issue: String?

    @Option(name: .long, help: "Limit to N groups.")
    var limit: Int?

    @Flag(name: .long, help: "Include local crash reports downloaded by the Xcode Organizer.")
    var xcode: Bool = false

    @Option(name: .customLong("crash-directory"), help: "Xcode crash directory to scan. Repeatable.")
    var crashDirectories: [String] = []

    func validate() throws {
        guard format != .ndjson else {
            throw ValidationError("--format ndjson is not supported by this command.")
        }
    }

    func run() async throws {
        try await reportingFailures(jsonOutput: format.isJSON) {
            try await runWithContext(.live())
        }
    }

    @discardableResult
    func runWithContext(
        _ ctx: CommandContext,
        crashDirectories overrideDirectories: [String]? = nil
    ) async throws -> String {
        let firebase = try ctx.firebaseClient()
        let firebaseIssues = try await firebase.listIssues(maxIssues: firebaseLimit)
            .filter(matchesIssueFilter)
        let xcodeLoad = try loadXcodeCrashes(ctx: ctx, overrideDirectories: overrideDirectories)
        let xcodeCrashes = xcodeLoad.crashes
        let groups = CrashGrouper().group(local: xcodeCrashes, firebase: firebaseIssues)

        let output: String
        switch format {
        case .text:
            let limited = limit.map { Array(groups.prefix($0)) } ?? groups
            output = PlainTextRenderer().renderGroups(limited)
        case .json:
            output = try JSONRenderer().renderGroups(groups, limit: limit, warnings: xcodeLoad.warnings)
        case .ndjson:
            throw ValidationError("--format ndjson is not supported by this command.")
        }
        ctx.report(xcodeLoad.warnings, format: format)
        ctx.console.output(output)
        return output
    }

    private func matchesIssueFilter(_ candidate: CrashIssue) -> Bool {
        guard let issue else { return true }
        return candidate.id == FirebaseIdentifiers.canonicalIssueId(issue)
    }

    private func loadXcodeCrashes(
        ctx: CommandContext,
        overrideDirectories: [String]?
    ) throws -> (crashes: [XcodeCrash], warnings: [CLIWarning]) {
        guard xcode else { return ([], []) }
        let directories = try overrideDirectories ?? (
            crashDirectories.isEmpty ? ctx.xcodeCrashDirectories() : crashDirectories
        )
        return ctx.loadXcodeCrashes(directories: directories)
    }
}
