import Foundation
import Testing
@testable import xcrashlytics

/// `events` / `show`: app-frame accuracy, the no-frames explanation, NSException
/// details, always-present `customKeys`/`logs`, library attribution, and `--dsym`.
@Suite("frame accuracy")
struct FrameAccuracyTests {
    private let appId = "1:1234567890:ios:abcdef"
    private let userId = "uid-secret-1"
    private let dwarfDirectory = "/dsyms/KeyboardKit.framework.dSYM/Contents/Resources/DWARF"

    /// An NSException crash whose crashed thread is the Crashlytics SDK's own queue: the
    /// blame frame is a symbol-less CoreFoundation frame, and the SDK is linked into `KeyboardCore`.
    private var exceptionEvent: String {
        #"""
        {"eventId":"E1","eventTime":"2026-06-07T12:00:00Z","user":{"id":"\#(userId)"},
         "blameFrame":{"address":"620768","library":"CoreFoundation","owner":"PLATFORM","blamed":true},
         "exceptions":[{"type":"CALayerInvalidGeometry",
           "exceptionMessage":"CALayer bounds contains NaN (user \#(userId))",
           "title":"Fatal Exception: CALayerInvalidGeometry","blamed":true,
           "frames":[{"address":"620768","library":"CoreFoundation","owner":"PLATFORM"}]}],
         "threads":[{"crashed":true,"title":"Crashed: queue","signal":"SIGABRT","frames":[
           {"symbol":"FIRCLSProcessRecordAllThreads","library":"KeyboardCore","owner":"THIRD_PARTY","address":"100"},
           {"symbol":"__FIRCLSExceptionRecord_block_invoke","library":"KeyboardCore","owner":"DEVELOPER","address":"200"},
           {"symbol":"<redacted>","library":"libdispatch.dylib","owner":"PLATFORM"},
           {"symbol":"FIRCLSTerminateHandler()","library":"KeyboardCore","owner":"THIRD_PARTY","address":"300"},
           {"address":"6846248376","owner":"DEVELOPER"}
         ]}]}
        """#
    }

    private func context(
        events: [String], profileLibraries: [String]? = nil, process: StubSubprocessExecutor = StubSubprocessExecutor(),
        fileStore: InMemoryFileStore = InMemoryFileStore()
    ) throws -> (Platform, FakeHTTPClient) {
        let config = profileLibraries.map {
            Config(activeProfile: "kb", profiles: ["kb": AppProfile(appId: appId, appLibraries: $0)])
        } ?? Config(appId: appId)
        try FileConfigRepository(fileStore: fileStore).save(config)
        let httpClient = FakeHTTPClient { request in
            let url = request.url!
            if url.path.hasSuffix("/events") {
                return FakeHTTPClient.response(url, status: 200, body: Data(#"{"events":[\#(events.joined(separator: ","))]}"#.utf8))
            }
            return FakeHTTPClient.response(
                url, status: 200, body: Data(#"{"id":"I1","title":"[kb] crash","errorType":"FATAL","subtitle":"s"}"#.utf8))
        }
        let platform = Platform.testing(fileStore: fileStore, subprocessExecutor: process, dateProvider: FixedDateProvider()).withFirebaseHTTP(httpClient)
        return (platform, httpClient)
    }

    // MARK: - No app frames

    @Test("--app-frames-only on an event without app code says so, in JSON and text, and keeps the blame library")
    func noAppFrames() async throws {
        let (platform, httpClient) = try context(events: [exceptionEvent])
        let json = try await EventsCommand.parse(["FB-I1", "--latest", "--app-frames-only", "--format", "json"]).execute(platform.container)

        let event = try #require(try Envelope(json).data["events"]?[0])
        #expect(event["frames"]?.array?.isEmpty == true)
        #expect(event["appFramesAbsent"]?.bool == true)
        #expect(event["noFramesReason"]?.string == "no_app_frames")
        #expect(event["crashedLibrary"]?.string == "CoreFoundation")
        #expect(event["blamedFrame"]?["binaryName"]?.string == "CoreFoundation")
        #expect(event["blamedFrame"]?["isBlamed"]?.bool == true)
        let request = try #require(httpClient.requests.compactMap(\.url).first { $0.path.hasSuffix("/events") })
        #expect(request.issuesQueryItem(named: "filter.issue.id") == "I1")
        #expect(request.issuesQueryItem(named: "page_size") == "1")

        let text = try await EventsCommand.parse(["FB-I1", "--latest", "--app-frames-only"]).execute(platform.container)
        #expect(text.contains("(no app frames in this event; crashed in CoreFoundation)"))
        #expect(!text.contains("* 0 ? ?"))
    }

    @Test("no SDK frame and no library-less frame is ever an app frame, so the unfiltered stack keeps them apart")
    func sdkAndUnknownFramesAreNotApp() async throws {
        let (platform, _) = try context(events: [exceptionEvent])
        let json = try await EventsCommand.parse(["FB-I1", "--latest", "--format", "json"]).execute(platform.container)
        let frames = try #require(try Envelope(json).data["events"]?[0]?["frames"]?.array)

        #expect(frames.first?["binaryName"]?.string == "CoreFoundation")
        #expect(frames.first?["isBlamed"]?.bool == true)
        // Only the blame frame is blamed: the library-less frame must not collide with it.
        #expect(frames.filter { $0["isBlamed"]?.bool == true }.count == 1)
        #expect(frames.last?["binaryName"]?.string == "?")
        #expect(frames.last?["isBlamed"]?.bool == false)
        #expect(frames.first { $0["binaryName"]?.string == "?" } != nil)

        let noSystem = try await EventsCommand.parse(["FB-I1", "--latest", "--no-system-frames", "--format", "json"])
            .execute(platform.container)
        let kept = try #require(try Envelope(noSystem).data["events"]?[0]?["frames"]?.array)
        #expect(kept.compactMap { $0["symbol"]?.string }.allSatisfy { !$0.contains("FIRCLS") })
    }

    @Test("profile appLibraries make that library's non-SDK frames app frames")
    func appLibrariesFromProfile() async throws {
        let bare = #"""
        {"eventId":"E1","threads":[{"crashed":true,"frames":[
          {"symbol":"Engine.run()","library":"KeyboardCore","owner":"THIRD_PARTY"},
          {"symbol":"Pod.go()","library":"KeyboardKit","owner":"THIRD_PARTY"}
        ]}]}
        """#
        let plain = try await EventsCommand.parse(["FB-I1", "--latest", "--app-frames-only", "--format", "json"])
            .execute(context(events: [bare]).0.container)
        #expect(try Envelope(plain).data["events"]?[0]?["appFramesAbsent"]?.bool == true)

        let configured = try await EventsCommand.parse(["FB-I1", "--latest", "--app-frames-only", "--format", "json"])
            .execute(context(events: [bare], profileLibraries: ["KeyboardCore"]).0.container)
        let data = try Envelope(configured).data
        #expect(data["events"]?[0]?["frames"]?.array?.compactMap { $0["symbol"]?.string } == ["Engine.run()"])
        #expect(data["events"]?[0]?["appFramesAbsent"] == nil)
        #expect(data["events"]?[0]?["noFramesReason"] == nil)
    }

    // MARK: - Exception, custom keys, logs

    @Test("NSException type and message are decoded, redacted, and become the crash message")
    func exceptionDetail() async throws {
        let (platform, _) = try context(events: [exceptionEvent])
        let json = try await EventsCommand.parse(["FB-I1", "--latest", "--format", "json"]).execute(platform.container)
        let event = try #require(try Envelope(json).data["events"]?[0])

        #expect(event["exception"]?["type"]?.string == "CALayerInvalidGeometry")
        #expect(event["exception"]?["message"]?.string == "CALayer bounds contains NaN (user [redacted])")
        #expect(event["crashMessage"]?.string == "CALayerInvalidGeometry: CALayer bounds contains NaN (user [redacted])")
        #expect(!json.contains(userId))

        let compact = try await EventsCommand.parse(["FB-I1", "--latest", "--app-frames-only", "--format", "json"])
            .execute(platform.container)
        #expect(try Envelope(compact).data["events"]?[0]?["exception"]?["type"]?.string == "CALayerInvalidGeometry")

        let text = try await EventsCommand.parse(["FB-I1", "--latest"]).execute(platform.container)
        #expect(text.contains("crash: CALayerInvalidGeometry: CALayer bounds contains NaN (user [redacted])"))
    }

    @Test("crash_info_entry wins over the exception for the crash message; the exception is still reported")
    func crashInfoBeatsException() async throws {
        let event = #"""
        {"eventId":"E1","customKeys":{"crash_info_entry_0":"Foo.swift:7: Fatal error: boom"},
         "exceptions":[{"type":"NSInvalidArgumentException","exceptionMessage":"bad"}],
         "threads":[{"crashed":true,"frames":[{"symbol":"a","library":"MyApp"}]}]}
        """#
        let json = try await EventsCommand.parse(["FB-I1", "--latest", "--format", "json"])
            .execute(context(events: [event]).0.container)
        let parsed = try #require(try Envelope(json).data["events"]?[0])
        #expect(parsed["crashMessage"]?.string == "Foo.swift:7: Fatal error: boom")
        #expect(parsed["exception"]?["type"]?.string == "NSInvalidArgumentException")
    }

    @Test("customKeys is always an object and logs always an array in full detail; compact output omits both")
    func emptyCustomKeysAndLogs() async throws {
        let (platform, _) = try context(events: [#"{"eventId":"E1","threads":[{"crashed":true,"frames":[{"symbol":"a","library":"MyApp"}]}]}"#])
        let json = try await EventsCommand.parse(["FB-I1", "--latest", "--format", "json"]).execute(platform.container)
        let event = try #require(try Envelope(json).data["events"]?[0])
        #expect(event["customKeys"]?.object?.isEmpty == true)
        #expect(event["logs"]?.array?.isEmpty == true)
        #expect(json.contains(#""customKeys" : {"#))
        #expect(event["exception"] == nil)

        let compact = try await EventsCommand.parse(["FB-I1", "--latest", "--frames-only", "--format", "json"]).execute(platform.container)
        let compactEvent = try #require(try Envelope(compact).data["events"]?[0])
        #expect(compactEvent["customKeys"] == nil)
        #expect(compactEvent["logs"] == nil)
    }

    // MARK: - show

    private var keyboardKitEvents: [String] {
        (1...4).map { index in
            let blamedLibrary = index == 4 ? "KeyboardKitPro" : "KeyboardKit"
            return #"""
            {"eventId":"E\#(index)","user":{"id":"u\#(index)"},
             "blameFrame":{"symbol":"objectdestroyTm","library":"\#(blamedLibrary)","owner":"THIRD_PARTY","address":"2092404"},
             "threads":[{"crashed":true,"frames":[
               {"symbol":"objc_retain","library":"libobjc.A.dylib","owner":"PLATFORM"},
               {"symbol":"FIRCLSHandler","library":"KeyboardCore","owner":"THIRD_PARTY"},
               {"symbol":"objectdestroyTm","library":"\#(blamedLibrary)","owner":"THIRD_PARTY","address":"2092404"},
               {"symbol":"Other.go()","library":"\#(index == 4 ? "Cerebro" : "KeyboardKit")","owner":"THIRD_PARTY"}
             ]}]}
            """#
        }
    }

    @Test("show lists the libraries on the sampled events' crashed threads and at their blame frames")
    func showAttribution() async throws {
        let (platform, _) = try context(events: keyboardKitEvents)
        let json = try await ShowCommand.parse(["FB-I1", "--format", "json"]).execute(platform.container)
        let data = try Envelope(json).data

        let dominant = try #require(data["dominantLibraries"]?.array)
        #expect(dominant.first?["library"]?.string == "KeyboardKit")
        #expect(dominant.first?["events"]?.int == 3)
        #expect(dominant.first?["share"]?.double == 0.75)
        #expect(dominant.first?["owner"]?.string == "THIRD_PARTY")
        // Each library once per event; system (libobjc) and SDK (FIRCLS) frames never count.
        let counts = Dictionary(uniqueKeysWithValues: dominant.compactMap { entry in
            entry["library"]?.string.flatMap { library in entry["events"]?.int.map { (library, $0) } }
        })
        #expect(counts == ["KeyboardKit": 3, "KeyboardKitPro": 1, "Cerebro": 1])
        let blame = try #require(data["blameLibraries"]?.array)
        #expect(blame.compactMap { $0["library"]?.string } == ["KeyboardKit", "KeyboardKitPro"])
        #expect(blame.first?["events"]?.int == 3)
        #expect(!json.contains("\"u1\""))

        let text = try await ShowCommand.parse(["FB-I1"]).execute(platform.container)
        #expect(text.contains("Libraries: KeyboardKit ×3 (75%)"))
        #expect(text.contains("Blamed in: KeyboardKit ×3 (75%), KeyboardKitPro ×1 (25%)"))
    }

    @Test("show keeps exceptionType and adds the NSException type and message to `exception`")
    func showException() async throws {
        let (platform, _) = try context(events: [exceptionEvent])
        let json = try await ShowCommand.parse(["FB-I1", "--format", "json"]).execute(platform.container)
        let exception = try #require(try Envelope(json).data["exception"])
        #expect(exception["exceptionType"]?.string == "FATAL")
        #expect(exception["type"]?.string == "CALayerInvalidGeometry")
        #expect(exception["message"]?.string == "CALayer bounds contains NaN (user [redacted])")
        #expect(try Envelope(json).data["crashMessage"]?.string?.hasPrefix("CALayerInvalidGeometry: ") == true)
    }

    @Test("show --app-frames-only explains an empty stack")
    func showNoAppFrames() async throws {
        let (platform, _) = try context(events: [exceptionEvent])
        let json = try await ShowCommand.parse(["FB-I1", "--app-frames-only", "--format", "json"]).execute(platform.container)
        let data = try Envelope(json).data
        #expect(data["frames"]?.array?.isEmpty == true)
        #expect(data["noFramesReason"]?.string == "no_app_frames")
        #expect(data["appFramesAbsent"]?.bool == true)
        #expect(data["crashedLibrary"]?.string == "CoreFoundation")

        let text = try await ShowCommand.parse(["FB-I1", "--app-frames-only"]).execute(platform.container)
        #expect(text.contains("(no app frames in this event; crashed in CoreFoundation)"))
    }

    // MARK: - dSYM

    private var otoolOutput: String {
        """
        Load command 0
             cmd LC_UUID
         cmdsize 24
            uuid B0B2532E-E644-3C37-BC05-42B715648E19
        Load command 1
              cmd LC_SEGMENT_64
          cmdsize 72
          segname __PAGEZERO
           vmaddr 0x0000000000000000
           vmsize 0x0000000100000000
        Load command 2
              cmd LC_SEGMENT_64
          cmdsize 2072
          segname __TEXT
           vmaddr 0x0000000100000000
           vmsize 0x00000000003a4000
        Section
          sectname __text
           segname __TEXT
              addr 0x0000000100004000
        """
    }

    private let atosResolved = "LocalAutocompleteEngine.autocompleteGuesses(for:) (in KeyboardKit) (LocalAutocompleteEngine+iOS.swift:112)"

    private func dsymFileStore() -> InMemoryFileStore {
        let fileStore = InMemoryFileStore()
        fileStore.seed("\(dwarfDirectory)/KeyboardKit", data: Data([0]))
        // Zip archives carry an AppleDouble copy; it must not be mistaken for the real dSYM.
        fileStore.seed("/dsyms/__MACOSX/KeyboardKit.framework.dSYM/Contents/Resources/DWARF/KeyboardKit", data: Data([0]))
        return fileStore
    }

    private let blameEvent = #"""
    {"eventId":"E1",
     "blameFrame":{"symbol":"objectdestroyTm","offset":"32256","address":"2092404","library":"KeyboardKit","owner":"THIRD_PARTY","blamed":true},
     "threads":[{"crashed":true,"frames":[
       {"symbol":"objc_retain","library":"libobjc.A.dylib","owner":"PLATFORM","address":"5000"},
       {"symbol":"objectdestroyTm","offset":"32256","address":"2092404","library":"KeyboardKit","owner":"THIRD_PARTY"},
       {"symbol":"keypath_get.1Tm","address":"2100000","library":"KeyboardKit","owner":"THIRD_PARTY"}
     ]}]}
    """#

    private func atosExecutor(failAtos: Bool = false) -> StubSubprocessExecutor {
        let resolved = atosResolved
        let otool = otoolOutput
        return StubSubprocessExecutor { _, args in
            switch args.first {
            case "otool": return SubprocessResult(exitCode: 0, standardOutput: otool, standardError: "")
            case "atos" where failAtos: return SubprocessResult(exitCode: 1, standardOutput: "", standardError: "atos: cannot load symbols")
            case "atos":
                // One line per address: the blame address resolves, the other echoes back unresolved.
                let lines = args.drop { $0 != "-l" }.dropFirst(2).map {
                    $0 == "0x1001fed74" ? resolved : $0
                }
                return SubprocessResult(exitCode: 0, standardOutput: lines.joined(separator: "\n") + "\n", standardError: "")
            default: return nil
            }
        }
    }

    @Test("--dsym symbolicates frames of the dSYM's library through one atos call and keeps Crashlytics' symbol")
    func dsymSymbolicates() async throws {
        let process = atosExecutor()
        let (platform, _) = try context(events: [blameEvent], process: process, fileStore: dsymFileStore())
        let json = try await EventsCommand.parse(["FB-I1", "--latest", "--format", "json", "--dsym", "/dsyms"]).execute(platform.container)

        let env = try Envelope(json)
        let frames = try #require(env.data["events"]?[0]?["frames"]?.array)
        let blamed = try #require(frames.first { $0["isBlamed"]?.bool == true })
        #expect(blamed["symbol"]?.string == "LocalAutocompleteEngine.autocompleteGuesses(for:)")
        #expect(blamed["file"]?.string == "LocalAutocompleteEngine+iOS.swift")
        #expect(blamed["line"]?.int == 112)
        #expect(blamed["firebaseSymbol"]?.string == "objectdestroyTm")
        #expect(blamed["symbolicated"]?.string == "dsym")
        // Frames of other libraries, and addresses atos could not resolve, keep Crashlytics' data.
        let other = try #require(frames.first { $0["symbol"]?.string == "keypath_get.1Tm" })
        #expect(other["symbolicated"] == nil)
        #expect(frames.first { $0["binaryName"]?.string == "libobjc.A.dylib" }?["symbolicated"] == nil)

        let atosCalls = process.calls.filter { $0.1.first == "atos" }
        #expect(atosCalls.count == 1)
        #expect(atosCalls.first?.0 == "/usr/bin/xcrun")
        #expect(atosCalls.first?.1 == [
            "atos", "-arch", "arm64", "-o", "\(dwarfDirectory)/KeyboardKit", "-l", "0x100000000",
            "0x1001fed74", "0x100200b20",
        ])
        #expect(process.calls.filter { $0.1.first == "otool" }.count == 1)

        #expect(env.warningCodes == ["DSYM_UNVERIFIED"])
        let warning = try #require(env.warnings.first)
        #expect(warning["message"]?.string?.contains("B0B2532E-E644-3C37-BC05-42B715648E19") == true)
        #expect(warning["message"]?.string?.contains("no binary image UUIDs") == true)
        #expect(warning["path"]?.string == "/dsyms/KeyboardKit.framework.dSYM")
    }

    @Test("--dsym text marks symbolicated frames")
    func dsymText() async throws {
        let (platform, _) = try context(events: [blameEvent], process: atosExecutor(), fileStore: dsymFileStore())
        let text = try await EventsCommand.parse(["FB-I1", "--latest", "--frames-only", "--dsym", "/dsyms"]).execute(platform.container)
        #expect(text.contains("LocalAutocompleteEngine+iOS.swift:112 LocalAutocompleteEngine.autocompleteGuesses(for:) [dsym]"))
    }

    @Test("a failing atos is DSYM_FAILED with the dSYM path, and Crashlytics' frames stay")
    func dsymAtosFails() async throws {
        let (platform, _) = try context(events: [blameEvent], process: atosExecutor(failAtos: true), fileStore: dsymFileStore())
        let json = try await EventsCommand.parse(["FB-I1", "--latest", "--format", "json", "--dsym", "/dsyms"]).execute(platform.container)

        let env = try Envelope(json)
        #expect(env.warningCodes == ["DSYM_FAILED"])
        #expect(env.warnings.first?["path"]?.string == "/dsyms/KeyboardKit.framework.dSYM")
        #expect(env.warnings.first?["message"]?.string?.contains("atos: cannot load symbols") == true)
        let frames = try #require(env.data["events"]?[0]?["frames"]?.array)
        #expect(frames.contains { $0["symbol"]?.string == "objectdestroyTm" })
        #expect(frames.allSatisfy { $0["symbolicated"] == nil })
    }

    @Test("a missing xcrun is DSYM_FAILED, not a crash")
    func dsymToolsMissing() async throws {
        let (platform, _) = try context(events: [blameEvent], process: StubSubprocessExecutor(), fileStore: dsymFileStore())
        let json = try await EventsCommand.parse(["FB-I1", "--latest", "--format", "json", "--dsym", "/dsyms"]).execute(platform.container)
        #expect(try Envelope(json).warningCodes == ["DSYM_FAILED"])
    }

    @Test("a --dsym path without a dSYM is DSYM_FAILED naming the path; __MACOSX copies do not count")
    func dsymNotFound() async throws {
        let fileStore = InMemoryFileStore()
        fileStore.seed("/zip/__MACOSX/KeyboardKit.framework.dSYM/Contents/Resources/DWARF/KeyboardKit", data: Data([0]))
        let (platform, _) = try context(events: [blameEvent], process: atosExecutor(), fileStore: fileStore)
        let json = try await EventsCommand.parse(["FB-I1", "--latest", "--format", "json", "--dsym", "/zip"]).execute(platform.container)

        let env = try Envelope(json)
        #expect(env.warningCodes == ["DSYM_FAILED"])
        #expect(env.warnings.first?["path"]?.string == "/zip")
    }

    @Test("show --dsym symbolicates the overview's frames")
    func showDsym() async throws {
        let (platform, _) = try context(events: [blameEvent], process: atosExecutor(), fileStore: dsymFileStore())
        let json = try await ShowCommand.parse(["FB-I1", "--format", "json", "--dsym", "/dsyms"]).execute(platform.container)

        let env = try Envelope(json)
        let frames = try #require(env.data["frames"]?.array)
        let symbolicated = try #require(frames.first { $0["symbolicated"]?.string == "dsym" })
        #expect(symbolicated["symbol"]?.string == "LocalAutocompleteEngine.autocompleteGuesses(for:)")
        #expect(symbolicated["file"]?.string == "LocalAutocompleteEngine+iOS.swift")
        #expect(symbolicated["firebaseSymbol"]?.string == "objectdestroyTm")
        #expect(env.warningCodes == ["DSYM_UNVERIFIED"])
    }

    @Test("otool and atos output parsing")
    func toolOutputParsing() {
        #expect(DSYMSymbolicator.textVMAddr(in: otoolOutput) == 0x1_0000_0000)
        #expect(DSYMSymbolicator.uuid(in: otoolOutput) == "B0B2532E-E644-3C37-BC05-42B715648E19")
        #expect(DSYMSymbolicator.textVMAddr(in: "  segname __DATA\n   vmaddr 0x10\n") == nil)

        let located = AtosLocation(line: atosResolved)
        #expect(located == AtosLocation(symbol: "LocalAutocompleteEngine.autocompleteGuesses(for:)",
                                        file: "LocalAutocompleteEngine+iOS.swift", line: 112))
        #expect(AtosLocation(line: "0x1001fed74") == nil)
        let noLine = AtosLocation(line: "KeyboardLayout.totalHeight.getter (in KeyboardKit) (<stdin>:0)")
        #expect(noLine == AtosLocation(symbol: "KeyboardLayout.totalHeight.getter", file: nil, line: nil))
        let offset = AtosLocation(line: "swift_retain (in libswiftCore.dylib) + 28")
        #expect(offset == AtosLocation(symbol: "swift_retain", file: nil, line: nil))
    }
}
