import ArgumentParser
import Foundation
import Testing
@testable import xcrashlytics

@Suite("xcrashlytics open")
struct OpenCommandTests {
    private let appId = "1:1234567890:ios:abcdef"
    private var cwd: String { FileManager.default.currentDirectoryPath }

    private func loadFixture(_ name: String) throws -> String {
        let url = Bundle.module.url(forResource: name, withExtension: nil, subdirectory: "Fixtures")!
        return try String(contentsOf: url, encoding: .utf8)
    }

    private func makeConfig() throws -> InMemoryFileStore {
        let fileStore = InMemoryFileStore()
        try FileConfigRepository(fileStore: fileStore).save(Config(appId: appId))
        return fileStore
    }

    /// Events payload whose newest event blames BlurDetectionService.swift:42.
    private func eventsHTTP() -> FakeHTTPClient {
        FakeHTTPClient { request in
            #expect(request.url?.path.hasSuffix("/events") == true)
            #expect(request.url?.query?.contains("filter.issue.id=I1") == true)
            return FakeHTTPClient.response(request.url!, status: 200, body: Data(#"""
            {"events":[
              {"eventId":"E1","threads":[{"crashed":true,"frames":[
                {"symbol":"<redacted>","library":"libsystem_kernel.dylib"},
                {"symbol":"BlurDetectionService.classifyWithML(_:)","library":"Core","file":"BlurDetectionService.swift","line":"42","blamed":true}
              ]}]},
              {"eventId":"E2","threads":[{"crashed":true,"frames":[
                {"symbol":"BlurDetectionService.classifyWithML(_:)","library":"Core","file":"BlurDetectionService.swift","line":"7","blamed":true}
              ]}]}
            ]}
            """#.utf8))
        }
    }

    @Test("FB id opens the newest event's top app frame in Xcode via xed")
    func firebaseOpensTopFrameInXcode() async throws {
        let fileStore = try makeConfig()
        fileStore.seed("\(cwd)/Sources/Core/BlurDetectionService.swift", text: "// source")
        let subprocessExecutor = StubSubprocessExecutor { executable, arguments in
            #expect(executable == "/usr/bin/env")
            #expect(arguments == ["xed", "--line", "42", "\(cwd)/Sources/Core/BlurDetectionService.swift"])
            return SubprocessResult(exitCode: 0, standardOutput: "", standardError: "")
        }
        let ctx = Platform.testing(
            fileStore: fileStore,
            subprocessExecutor: subprocessExecutor,
            dateProvider: FixedDateProvider()
        )
        let cmd = try OpenCommand.parse(["FB-I1"])

        let output = try await cmd.execute(ctx.withFirebaseHTTP(eventsHTTP()).container)

        #expect(output.contains("Opened \(cwd)/Sources/Core/BlurDetectionService.swift:42 in Xcode."))
        #expect(subprocessExecutor.calls.count == 1)
    }

    @Test("FB event ref opens that specific event's frame")
    func firebaseEventRefOpensThatEvent() async throws {
        let fileStore = try makeConfig()
        fileStore.seed("\(cwd)/Sources/Core/BlurDetectionService.swift", text: "// source")
        let subprocessExecutor = StubSubprocessExecutor { _, arguments in
            #expect(arguments == ["xed", "--line", "7", "\(cwd)/Sources/Core/BlurDetectionService.swift"])
            return SubprocessResult(exitCode: 0, standardOutput: "", standardError: "")
        }
        let ctx = Platform.testing(
            fileStore: fileStore,
            subprocessExecutor: subprocessExecutor,
            dateProvider: FixedDateProvider()
        )
        let cmd = try OpenCommand.parse(["FB-I1/events/E2"])

        let output = try await cmd.execute(ctx.withFirebaseHTTP(eventsHTTP()).container)

        #expect(output.contains(":7 in Xcode."))
        #expect(subprocessExecutor.calls.count == 1)
    }

    @Test("FB id errors when no frame carries a source location")
    func firebaseErrorsWithoutSourceLocation() async throws {
        let fileStore = try makeConfig()
        let httpClient = FakeHTTPClient { request in
            FakeHTTPClient.response(request.url!, status: 200, body: Data(#"""
            {"events":[{"eventId":"E1","threads":[{"crashed":true,"frames":[
              {"symbol":"<redacted>","library":"libsystem_kernel.dylib"}
            ]}]}]}
            """#.utf8))
        }
        let subprocessExecutor = StubSubprocessExecutor()
        let ctx = Platform.testing(
            fileStore: fileStore,
            subprocessExecutor: subprocessExecutor,
            dateProvider: FixedDateProvider()
        )
        let cmd = try OpenCommand.parse(["FB-I1"])

        await #expect(throws: InvalidInputError.self) {
            _ = try await cmd.execute(ctx.withFirebaseHTTP(httpClient).container)
        }
        #expect(subprocessExecutor.calls.isEmpty)
    }

    @Test("FB id errors when the frame's file name is ambiguous in the working directory")
    func firebaseErrorsOnAmbiguousFile() async throws {
        let fileStore = try makeConfig()
        fileStore.seed("\(cwd)/Sources/Core/BlurDetectionService.swift", text: "// a")
        fileStore.seed("\(cwd)/Sources/Legacy/BlurDetectionService.swift", text: "// b")
        let subprocessExecutor = StubSubprocessExecutor()
        let ctx = Platform.testing(
            fileStore: fileStore,
            subprocessExecutor: subprocessExecutor,
            dateProvider: FixedDateProvider()
        )
        let cmd = try OpenCommand.parse(["FB-I1"])

        await #expect(throws: InvalidInputError.self) {
            _ = try await cmd.execute(ctx.withFirebaseHTTP(eventsHTTP()).container)
        }
        #expect(subprocessExecutor.calls.isEmpty)
    }

    @Test("XC id opens the parsed source location via xed")
    func xcodeOpensParsedSourceLocation() async throws {
        let fileStore = InMemoryFileStore()
        fileStore.seed(
            "\(cwd)/.xcrashlytics.json",
            text: #"{"activeProfile":"dev","profiles":{"dev":{"appId":"1:1234567890:ios:abc","bundleId":"com.example.app"}}}"#
        )
        let crashDir = OrganizerCrashRepository.organizerDirectories(bundleId: "com.example.app")[0]
        fileStore.seed("\(crashDir)/A.crash", text: try loadFixture("sample-symbolicated.crash"))
        fileStore.seed("\(cwd)/Sources/App/ExampleViewController.swift", text: "// source")
        let subprocessExecutor = StubSubprocessExecutor { executable, arguments in
            #expect(executable == "/usr/bin/env")
            #expect(arguments == ["xed", "--line", "42", "\(cwd)/Sources/App/ExampleViewController.swift"])
            return SubprocessResult(exitCode: 0, standardOutput: "", standardError: "")
        }
        let ctx = Platform.testing(
            fileStore: fileStore,
            subprocessExecutor: subprocessExecutor,
            dateProvider: SystemDateProvider()
        )
        let cmd = try OpenCommand.parse(["XC-AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE"])

        let output = try await cmd.execute(ctx.container)

        #expect(output.contains("Opened \(cwd)/Sources/App/ExampleViewController.swift:42 in Xcode."))
        #expect(subprocessExecutor.calls.count == 1)
    }

    @Test("XC scanning is scoped to the configured bundle id")
    func xcodeScanningScopedToBundleId() async throws {
        let fileStore = InMemoryFileStore()
        try FileConfigRepository(fileStore: fileStore).save(Config(
            activeProfile: "release",
            profiles: ["release": AppProfile(appId: appId, bundleId: "com.example.app")]
        ))
        let products = (OrganizerCrashRepository.organizerDirectories(bundleId: "com.example.app")[0] as NSString)
            .deletingLastPathComponent
        // Same crash id exists under another app's store — must not be seen.
        fileStore.seed("\(products)/com.other.app/Crashes/A.crash", text: try loadFixture("sample-symbolicated.crash"))
        let ctx = Platform.testing(
            fileStore: fileStore,
            subprocessExecutor: StubSubprocessExecutor(),
            dateProvider: SystemDateProvider()
        )
        let cmd = try OpenCommand.parse(["XC-AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE"])

        await #expect(throws: InvalidInputError.self) {
            _ = try await cmd.execute(ctx.container)
        }

        // Under the configured bundle id it is found.
        fileStore.seed("\(products)/com.example.app/Crashes/A.crash", text: try loadFixture("sample-symbolicated.crash"))
        fileStore.seed("\(cwd)/Sources/App/ExampleViewController.swift", text: "// source")
        let opening = Platform.testing(
            fileStore: fileStore,
            subprocessExecutor: StubSubprocessExecutor { _, _ in SubprocessResult(exitCode: 0, standardOutput: "", standardError: "") },
            dateProvider: SystemDateProvider()
        )
        let output = try await cmd.execute(opening.container)
        #expect(output.contains("in Xcode."))
    }

    @Test("XC id without a source location falls back to the raw report")
    func xcodeFallsBackToRawReport() async throws {
        let fileStore = InMemoryFileStore()
        fileStore.seed(
            "\(cwd)/.xcrashlytics.json",
            text: #"{"activeProfile":"dev","profiles":{"dev":{"appId":"1:1234567890:ios:abc","bundleId":"com.example.app"}}}"#
        )
        let crashDir = OrganizerCrashRepository.organizerDirectories(bundleId: "com.example.app")[0]
        fileStore.seed("\(crashDir)/A.crash", text: try loadFixture("sample.crash"))
        let subprocessExecutor = StubSubprocessExecutor { executable, arguments in
            #expect(executable == "/usr/bin/open")
            #expect(arguments == ["\(crashDir)/A.crash"])
            return SubprocessResult(exitCode: 0, standardOutput: "", standardError: "")
        }
        let ctx = Platform.testing(
            fileStore: fileStore,
            subprocessExecutor: subprocessExecutor,
            dateProvider: SystemDateProvider()
        )
        let cmd = try OpenCommand.parse(["XC-AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE"])

        let output = try await cmd.execute(ctx.container)

        #expect(output.contains("Opened raw report at \(crashDir)/A.crash (no source location in report)."))
        #expect(subprocessExecutor.calls.count == 1)
    }

    @Test("XC skips an upper frame whose file isn't in the checkout and opens the first one that is")
    func xcodeRepoAwareSkipsUnresolvableUpperFrame() async throws {
        let fileStore = InMemoryFileStore()
        fileStore.seed(
            "\(cwd)/.xcrashlytics.json",
            text: #"{"activeProfile":"dev","profiles":{"dev":{"appId":"1:1234567890:ios:abc","bundleId":"com.example.app"}}}"#
        )
        let crashDir = OrganizerCrashRepository.organizerDirectories(bundleId: "com.example.app")[0]
        // frame 0 = system semaphore.c (NOT seeded), frame 1 = app ExampleViewController.swift (seeded).
        fileStore.seed("\(crashDir)/A.crash", text: try loadFixture("system-frame-first.crash"))
        fileStore.seed("\(cwd)/Sources/App/ExampleViewController.swift", text: "// source")
        let subprocessExecutor = StubSubprocessExecutor { executable, arguments in
            #expect(executable == "/usr/bin/env")
            #expect(arguments == ["xed", "--line", "42", "\(cwd)/Sources/App/ExampleViewController.swift"])
            return SubprocessResult(exitCode: 0, standardOutput: "", standardError: "")
        }
        let ctx = Platform.testing(
            fileStore: fileStore,
            subprocessExecutor: subprocessExecutor,
            dateProvider: SystemDateProvider()
        )
        let cmd = try OpenCommand.parse(["XC-CCCCCCCC-BBBB-CCCC-DDDD-EEEEEEEEEEEE"])

        let output = try await cmd.execute(ctx.container)

        #expect(output.contains("ExampleViewController.swift:42 in Xcode."))
        #expect(subprocessExecutor.calls.count == 1)
    }

    @Test("XC with no frame resolvable in the checkout falls back to the raw report, honestly")
    func xcodeRepoAwareNoResolvableFrameFallsBack() async throws {
        let fileStore = InMemoryFileStore()
        fileStore.seed(
            "\(cwd)/.xcrashlytics.json",
            text: #"{"activeProfile":"dev","profiles":{"dev":{"appId":"1:1234567890:ios:abc","bundleId":"com.example.app"}}}"#
        )
        let crashDir = OrganizerCrashRepository.organizerDirectories(bundleId: "com.example.app")[0]
        // No source files seeded — neither semaphore.c nor ExampleViewController.swift resolves.
        fileStore.seed("\(crashDir)/A.crash", text: try loadFixture("system-frame-first.crash"))
        let subprocessExecutor = StubSubprocessExecutor { executable, _ in
            #expect(executable == "/usr/bin/open")
            return SubprocessResult(exitCode: 0, standardOutput: "", standardError: "")
        }
        let ctx = Platform.testing(
            fileStore: fileStore,
            subprocessExecutor: subprocessExecutor,
            dateProvider: SystemDateProvider()
        )
        let cmd = try OpenCommand.parse(["XC-CCCCCCCC-BBBB-CCCC-DDDD-EEEEEEEEEEEE"])

        let output = try await cmd.execute(ctx.container)

        #expect(output.contains("Opened raw report at"))
        #expect(output.contains("found no file named 'semaphore.c'"))
        #expect(!output.contains("no source location"))
    }

    @Test("XC falls back to a located system frame when no app frame has a location")
    func xcodeFallsBackToSystemFrameLocation() async throws {
        let fileStore = InMemoryFileStore()
        fileStore.seed(
            "\(cwd)/.xcrashlytics.json",
            text: #"{"activeProfile":"dev","profiles":{"dev":{"appId":"1:1234567890:ios:abc","bundleId":"com.example.app"}}}"#
        )
        let crashDir = OrganizerCrashRepository.organizerDirectories(bundleId: "com.example.app")[0]
        // Strip the app frame's source location so only the system frame has one.
        fileStore.seed(
            "\(crashDir)/A.crash",
            text: try loadFixture("system-frame-first.crash")
                .replacingOccurrences(of: " (ExampleViewController.swift:42)", with: "")
        )
        fileStore.seed("\(cwd)/Vendor/semaphore.c", text: "// system copy")
        let subprocessExecutor = StubSubprocessExecutor { _, arguments in
            #expect(arguments == ["xed", "--line", "279", "\(cwd)/Vendor/semaphore.c"])
            return SubprocessResult(exitCode: 0, standardOutput: "", standardError: "")
        }
        let ctx = Platform.testing(
            fileStore: fileStore,
            subprocessExecutor: subprocessExecutor,
            dateProvider: SystemDateProvider()
        )
        let cmd = try OpenCommand.parse(["XC-CCCCCCCC-BBBB-CCCC-DDDD-EEEEEEEEEEEE"])

        let output = try await cmd.execute(ctx.container)

        #expect(output.contains("semaphore.c:279 in Xcode."))
    }

    /// Events payload whose newest event lists an SDK frame (with file) above the app frame.
    private func sdkFrameFirstHTTP() -> FakeHTTPClient {
        FakeHTTPClient { request in
            FakeHTTPClient.response(request.url!, status: 200, body: Data(#"""
            {"events":[
              {"eventId":"E1","threads":[{"crashed":true,"frames":[
                {"symbol":"FIRCLSUserLoggingRecordKeyValue","library":"FirebaseCrashlytics","file":"FIRCLSUserLogging.m","line":"402"},
                {"symbol":"BlurDetectionService.classifyWithML(_:)","library":"Core","file":"BlurDetectionService.swift","line":"42"}
              ]}]}
            ]}
            """#.utf8))
        }
    }

    @Test("FB prefers an app frame over an SDK frame that also carries a file")
    func firebasePrefersAppFrameOverSdkFrame() async throws {
        let fileStore = try makeConfig()
        fileStore.seed("\(cwd)/Vendor/FIRCLSUserLogging.m", text: "// sdk copy")
        fileStore.seed("\(cwd)/Sources/Core/BlurDetectionService.swift", text: "// source")
        let subprocessExecutor = StubSubprocessExecutor { _, arguments in
            #expect(arguments == ["xed", "--line", "42", "\(cwd)/Sources/Core/BlurDetectionService.swift"])
            return SubprocessResult(exitCode: 0, standardOutput: "", standardError: "")
        }
        let ctx = Platform.testing(
            fileStore: fileStore,
            subprocessExecutor: subprocessExecutor,
            dateProvider: FixedDateProvider()
        )
        let cmd = try OpenCommand.parse(["FB-I1"])

        let output = try await cmd.execute(ctx.withFirebaseHTTP(sdkFrameFirstHTTP()).container)

        #expect(output.contains("BlurDetectionService.swift:42 in Xcode."))
        #expect(subprocessExecutor.calls.count == 1)
    }

    @Test("FB falls back to a non-app frame's location when no app frame has one")
    func firebaseFallsBackToNonAppFrame() async throws {
        let fileStore = try makeConfig()
        fileStore.seed("\(cwd)/Vendor/FIRCLSUserLogging.m", text: "// sdk copy")
        let httpClient = FakeHTTPClient { request in
            FakeHTTPClient.response(request.url!, status: 200, body: Data(#"""
            {"events":[{"eventId":"E1","threads":[{"crashed":true,"frames":[
              {"symbol":"FIRCLSUserLoggingRecordKeyValue","library":"FirebaseCrashlytics","file":"FIRCLSUserLogging.m","line":"402"}
            ]}]}]}
            """#.utf8))
        }
        let subprocessExecutor = StubSubprocessExecutor { _, arguments in
            #expect(arguments == ["xed", "--line", "402", "\(cwd)/Vendor/FIRCLSUserLogging.m"])
            return SubprocessResult(exitCode: 0, standardOutput: "", standardError: "")
        }
        let ctx = Platform.testing(
            fileStore: fileStore,
            subprocessExecutor: subprocessExecutor,
            dateProvider: FixedDateProvider()
        )
        let cmd = try OpenCommand.parse(["FB-I1"])

        let output = try await cmd.execute(ctx.withFirebaseHTTP(httpClient).container)

        #expect(output.contains("FIRCLSUserLogging.m:402 in Xcode."))
    }

    @Test("build-dir copies are ignored when resolving a frame's file")
    func buildDirCopiesIgnored() async throws {
        let fileStore = try makeConfig()
        // Without exclusion these three would make the name ambiguous.
        fileStore.seed("\(cwd)/.build/checkouts/firebase-ios-sdk/BlurDetectionService.swift", text: "// checkout")
        fileStore.seed("\(cwd)/build/DerivedSources/BlurDetectionService.swift", text: "// derived")
        fileStore.seed("\(cwd)/Sources/Core/BlurDetectionService.swift", text: "// source")
        let subprocessExecutor = StubSubprocessExecutor { _, arguments in
            #expect(arguments == ["xed", "--line", "42", "\(cwd)/Sources/Core/BlurDetectionService.swift"])
            return SubprocessResult(exitCode: 0, standardOutput: "", standardError: "")
        }
        let ctx = Platform.testing(
            fileStore: fileStore,
            subprocessExecutor: subprocessExecutor,
            dateProvider: FixedDateProvider()
        )
        let cmd = try OpenCommand.parse(["FB-I1"])

        let output = try await cmd.execute(ctx.withFirebaseHTTP(eventsHTTP()).container)

        #expect(output.contains("Opened \(cwd)/Sources/Core/BlurDetectionService.swift:42 in Xcode."))
    }

    @Test("only build-dir matches produce an honest error, not a build-dir open")
    func onlyBuildDirMatchesError() async throws {
        let fileStore = try makeConfig()
        fileStore.seed("\(cwd)/DerivedData/Checkouts/BlurDetectionService.swift", text: "// checkout")
        let subprocessExecutor = StubSubprocessExecutor()
        let ctx = Platform.testing(
            fileStore: fileStore,
            subprocessExecutor: subprocessExecutor,
            dateProvider: FixedDateProvider()
        )
        let cmd = try OpenCommand.parse(["FB-I1"])

        do {
            _ = try await cmd.execute(ctx.withFirebaseHTTP(eventsHTTP()).container)
            Issue.record("expected InvalidInputError")
        } catch let error as InvalidInputError {
            #expect(error.message.contains("build directories"))
        }
        #expect(subprocessExecutor.calls.isEmpty)
    }

    @Test("XC location that resolves to no local file falls back with the resolution error as reason")
    func xcodeFallsBackWithResolutionReason() async throws {
        let fileStore = InMemoryFileStore()
        fileStore.seed(
            "\(cwd)/.xcrashlytics.json",
            text: #"{"activeProfile":"dev","profiles":{"dev":{"appId":"1:1234567890:ios:abc","bundleId":"com.example.app"}}}"#
        )
        let crashDir = OrganizerCrashRepository.organizerDirectories(bundleId: "com.example.app")[0]
        fileStore.seed("\(crashDir)/A.crash", text: try loadFixture("sample-symbolicated.crash"))
        // No ExampleViewController.swift seeded anywhere under cwd.
        let subprocessExecutor = StubSubprocessExecutor { executable, arguments in
            #expect(executable == "/usr/bin/open")
            #expect(arguments == ["\(crashDir)/A.crash"])
            return SubprocessResult(exitCode: 0, standardOutput: "", standardError: "")
        }
        let ctx = Platform.testing(
            fileStore: fileStore,
            subprocessExecutor: subprocessExecutor,
            dateProvider: SystemDateProvider()
        )
        let cmd = try OpenCommand.parse(["XC-AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE"])

        let output = try await cmd.execute(ctx.container)

        #expect(output.contains("Opened raw report at \(crashDir)/A.crash"))
        #expect(output.contains("found no file named 'ExampleViewController.swift'"))
        #expect(!output.contains("no source location"))
    }
}
