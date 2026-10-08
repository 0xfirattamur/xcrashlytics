import Foundation

extension GoldenCases {
    static let help: [GoldenCase] = [
        .init("help-root", ["--help"]),
        .init("help-root-short", ["-h"]),
        .init("help-version", ["--version"]),
        .init("help-no-arguments", []),
        .init("help-unknown-subcommand", ["bogus"]),
        .init("help-init", ["init", "--help"]),
        .init("help-use", ["use", "--help"]),
        .init("help-issues", ["issues", "--help"]),
        .init("help-events", ["events", "--help"]),
        .init("help-show", ["show", "--help"]),
        .init("help-export", ["export", "--help"]),
        .init("help-open", ["open", "--help"]),
        .init("help-blame", ["blame", "--help"]),
        .init("help-groups", ["groups", "--help"]),
        .init("help-breakdown", ["breakdown", "--help"]),
        .init("help-subcommand-issues", ["help", "issues"]),
        .init("help-subcommand-unknown", ["help", "bogus"]),
        .init("help-ignores-json-format", ["issues", "--help", "--format", "json"]),
    ]
}
