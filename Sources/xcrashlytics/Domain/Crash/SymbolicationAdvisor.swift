import Foundation

enum SymbolicationAdvisor {
    /// Nil when no crashed-thread frame in app-owned code is unsymbolicated: a fully
    /// symbolicated report never triggers the hint.
    static func hint(for crashes: [XcodeCrash]) -> String? {
        var missingUUIDs: Set<String> = []
        var crashIds: Set<String> = []
        for crash in crashes {
            let missing = missingImages(in: crash.event)
            guard !missing.isEmpty else { continue }
            crashIds.insert(crash.event.id)
            missingUUIDs.formUnion(missing.map(\.uuid))
        }
        guard !missingUUIDs.isEmpty else { return nil }
        return "\(missingUUIDs.count) app dSYM UUID(s) may be needed for \(crashIds.count) Xcode crash(es)."
    }

    private static func missingImages(in event: CrashEvent) -> [BinaryImage] {
        event.frames.filter { !$0.isSymbolicated }.compactMap { frame in
            guard let image = image(for: frame, in: event.binaryImages), isAppOwned(image) else { return nil }
            return image
        }
    }

    static func image(for frame: StackFrame, in images: [BinaryImage]) -> BinaryImage? {
        if let uuid = frame.imageUUID, let match = images.first(where: { $0.uuid == uuid }) { return match }
        return images.first { $0.name == frame.binaryName }
    }

    /// Prefixes/fragments of paths that hold OS code even when they contain `.app/`
    /// (e.g. simulator runtimes live inside `Xcode.app`).
    private static let systemMarkers = [
        "/System/", "/usr/lib/", "/usr/libexec/", "/Library/Apple/",
        "/private/preboot/Cryptexes/", "/Cryptexes/", "/RuntimeRoot/", "/Applications/Xcode"
    ]

    /// Images inside the app bundle (app binary, embedded frameworks, extensions); OS images
    /// and anything outside a `.app`/`.appex` are not the developer's to symbolicate.
    static func isAppOwned(_ image: BinaryImage) -> Bool {
        let path = image.path
        guard !systemMarkers.contains(where: { path.hasPrefix($0) || path.contains($0) }) else { return false }
        return path.contains(".app/") || path.contains(".appex/")
    }
}
