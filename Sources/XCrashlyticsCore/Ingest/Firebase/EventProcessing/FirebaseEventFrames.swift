//
//  FirebaseEventFrames.swift
//  xcrashlytics
//
//  Created by FIRAT TAMUR on 8.06.2026.
//

public struct FirebaseFrameFilterOptions: Sendable, Equatable {
    public var appFramesOnly: Bool
    public var noSystemFrames: Bool
    public var crashingThreadOnly: Bool

    public init(
        appFramesOnly: Bool = false,
        noSystemFrames: Bool = false,
        crashingThreadOnly: Bool = false
    ) {
        self.appFramesOnly = appFramesOnly
        self.noSystemFrames = noSystemFrames
        self.crashingThreadOnly = crashingThreadOnly
    }
}

public enum FirebaseEventFrames {
    public static func frameDTOs(
        from event: FirebaseEvent,
        options: FirebaseFrameFilterOptions = FirebaseFrameFilterOptions()
    ) -> [FirebaseFrame] {
        let frames = selectedFrameDTOs(from: event, crashingThreadOnly: options.crashingThreadOnly)
        return frames.filter { includes($0, options: options) }
    }

    public static func frames(
        from event: FirebaseEvent,
        options: FirebaseFrameFilterOptions = FirebaseFrameFilterOptions()
    ) -> [Frame] {
        frameDTOs(from: event, options: options).enumerated().map { index, frame in
            Frame(
                index: index,
                binaryName: frame.library ?? "?",
                symbol: frame.symbol,
                file: frame.file,
                line: frame.line,
                column: nil,
                address: nil,
                imageUUID: nil,
                isSymbolicated: frame.symbol != nil
            )
        }
    }

    public static func selectedFrameDTOs(
        from event: FirebaseEvent,
        crashingThreadOnly: Bool = false
    ) -> [FirebaseFrame] {
        let frames = event.threads.first(where: \.crashed)?.frames.nilIfEmpty
            ?? event.threads.first?.frames.nilIfEmpty
            ?? event.exceptions.first?.frames.nilIfEmpty
            ?? []
        guard let blameFrame = event.blameFrame else {
            return frames
        }
        return frames.contains(where: { matches($0, blameFrame) }) ? frames : [blameFrame] + frames
    }

    public static func blamedFrame(from event: FirebaseEvent) -> FirebaseFrame? {
        event.blameFrame
            ?? frameDTOs(from: event).first(where: { isBlamed($0, in: event) })
            ?? frameDTOs(from: event).first
    }

    public static func isBlamed(_ frame: FirebaseFrame, in event: FirebaseEvent) -> Bool {
        frame.blamed == true || event.blameFrame.map { matches(frame, $0) } == true
    }

    public static func topFrameDescription(
        for event: FirebaseEvent,
        options: FirebaseFrameFilterOptions = FirebaseFrameFilterOptions()
    ) -> String? {
        let frames = frameDTOs(from: event, options: options)
        let frame = frames.first(where: { isBlamed($0, in: event) }) ?? frames.first
        guard let frame else { return nil }
        if let symbol = frame.symbol {
            return symbol
        }
        if let file = frame.file, let line = frame.line {
            return "\(file):\(line)"
        }
        return frame.file ?? frame.library ?? "?"
    }

    public static func location(for frame: FirebaseFrame) -> String {
        switch (frame.file, frame.line) {
        case let (file?, line?):
            return "\(file):\(line)"
        case let (file?, nil):
            return file
        case (nil, _):
            return frame.library ?? "?"
        }
    }

    public static func matches(_ lhs: FirebaseFrame, _ rhs: FirebaseFrame) -> Bool {
        lhs.symbol == rhs.symbol
            && lhs.file == rhs.file
            && lhs.line == rhs.line
            && lhs.library == rhs.library
    }

    private static func includes(
        _ frame: FirebaseFrame,
        options: FirebaseFrameFilterOptions
    ) -> Bool {
        if options.appFramesOnly {
            return isAppFrame(frame)
        }
        if options.noSystemFrames {
            return !isSystemFrame(frame)
        }
        return true
    }

    private static func isAppFrame(_ frame: FirebaseFrame) -> Bool {
        if isRedactedOrDeduplicated(frame) || isKnownSdkNoise(frame) {
            return false
        }
        if let owner = normalizedOwner(frame), appOwners.contains(owner) {
            return true
        }
        if let owner = normalizedOwner(frame), systemOwners.contains(owner) {
            return false
        }
        if isKnownSystemLibrary(frame.library) {
            return false
        }
        if frame.blamed == true {
            return true
        }
        return frame.file.map(isLikelySourceFile) ?? false
    }

    private static func isSystemFrame(_ frame: FirebaseFrame) -> Bool {
        if isRedactedOrDeduplicated(frame) || isKnownSdkNoise(frame) {
            return true
        }
        if let owner = normalizedOwner(frame), systemOwners.contains(owner) {
            return true
        }
        if let owner = normalizedOwner(frame), appOwners.contains(owner) {
            return false
        }
        return isKnownSystemLibrary(frame.library)
    }

    private static func normalizedOwner(_ frame: FirebaseFrame) -> String? {
        frame.owner?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private static var appOwners: Set<String> {
        ["app", "application", "developer", "customer", "user"]
    }

    private static var systemOwners: Set<String> {
        ["system", "platform", "runtime", "library", "sdk"]
    }

    private static func isRedactedOrDeduplicated(_ frame: FirebaseFrame) -> Bool {
        guard let symbol = frame.symbol?.lowercased() else { return false }
        return symbol == "<redacted>" || symbol == "<deduplicated_symbol>"
    }

    private static func isKnownSdkNoise(_ frame: FirebaseFrame) -> Bool {
        guard let symbol = frame.symbol?.lowercased() else { return false }
        return symbol.hasPrefix("fircls")
            || symbol.hasPrefix("firebasecrashlytics")
            || symbol.contains("crashlytics")
    }

    private static func isKnownSystemLibrary(_ library: String?) -> Bool {
        guard let library = library?.lowercased() else { return false }
        return library.hasPrefix("libsystem")
            || library.hasPrefix("libdispatch")
            || library.hasPrefix("libobjc")
            || library.hasPrefix("libswift")
            || library == "uikit"
            || library == "uikitcore"
            || library == "foundation"
            || library == "corefoundation"
            || library == "swiftui"
            || library == "quartzcore"
            || library == "graphicsservices"
            || library == "dyld"
    }

    private static func isLikelySourceFile(_ file: String) -> Bool {
        let lowercased = file.lowercased()
        return lowercased.hasSuffix(".swift")
            || lowercased.hasSuffix(".m")
            || lowercased.hasSuffix(".mm")
            || lowercased.hasSuffix(".c")
            || lowercased.hasSuffix(".cc")
            || lowercased.hasSuffix(".cpp")
            || lowercased.hasSuffix(".kt")
            || lowercased.hasSuffix(".kts")
            || lowercased.hasSuffix(".java")
    }
}
