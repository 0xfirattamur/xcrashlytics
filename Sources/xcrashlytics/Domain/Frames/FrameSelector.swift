import Foundation

struct FrameSelector: Sendable {
    let classifier: FrameClassifier

    init(classifier: FrameClassifier = FrameClassifier()) {
        self.classifier = classifier
    }

    func filteredFrames(from event: CrashlyticsEvent, filter: FrameFilter = .none) -> [CrashlyticsFrame] {
        stackFrames(from: event, crashingThreadOnly: filter.crashingThreadOnly)
            .filter { includes($0, filter: filter) }
    }

    /// Each frame keeps its unfiltered stack position as `index`.
    func frames(from event: CrashlyticsEvent, filter: FrameFilter = .none) -> [StackFrame] {
        filteredFrames(from: event, filter: filter).enumerated().map { position, frame in
            stackFrame(from: frame, fallbackIndex: position)
        }
    }

    /// Index into `event.threads` of the thread whose frames are used: crashed,
    /// else blamed, else the first thread with frames.
    func chosenThreadIndex(in event: CrashlyticsEvent) -> Int? {
        let withFrames = event.threads.indices.filter { !event.threads[$0].frames.isEmpty }
        return withFrames.first(where: { event.threads[$0].crashed })
            ?? withFrames.first(where: { event.threads[$0].blamed })
            ?? withFrames.first
    }

    /// The chosen thread's frames, else the first exception or Apple `errors[]` entry with
    /// frames (blamed first); the blame frame is prepended when the stack lacks it. With
    /// `crashingThreadOnly`, an event without a crashed thread has no frames.
    func stackFrames(from event: CrashlyticsEvent, crashingThreadOnly: Bool = false) -> [CrashlyticsFrame] {
        var frames = crashingThreadOnly ? crashedThreadFrames(in: event) : primaryStack(in: event)
        if let blame = event.blameFrame, isLocatable(blame),
           !frames.contains(where: { sameLocation($0, blame) }) {
            frames.insert(blame, at: 0)
        }
        return frames.enumerated().map { position, frame in
            var numbered = frame
            numbered.stackIndex = position
            return numbered
        }
    }

    /// Crashlytics' blame frame, else a frame flagged blamed, else the first app
    /// frame, else the first frame; the SDK's own frames are skipped because
    /// non-fatals blame them for every issue alike.
    func blamedFrame(from event: CrashlyticsEvent) -> CrashlyticsFrame? {
        if let blame = event.blameFrame, !classifier.isSDKFrame(blame) { return blame }
        let frames = filteredFrames(from: event).filter { !classifier.isSDKFrame($0) }
        return frames.first(where: { isBlamed($0, in: event) })
            ?? frames.first(where: { classifier.isAppFrame($0) })
            ?? frames.first
            ?? event.blameFrame
    }

    func isBlamed(_ frame: CrashlyticsFrame, in event: CrashlyticsEvent) -> Bool {
        frame.blamed || event.blameFrame.map { sameLocation(frame, $0) } == true
    }

    func topFrameDescription(for event: CrashlyticsEvent, filter: FrameFilter = .none) -> String? {
        let frames = filteredFrames(from: event, filter: filter)
        guard let frame = frames.first(where: { isBlamed($0, in: event) }) ?? frames.first else { return nil }
        if let symbol = frame.symbol { return symbol }
        if let file = frame.file, let line = frame.line { return "\(file):\(line)" }
        return frame.file ?? frame.library ?? "?"
    }

    func location(for frame: CrashlyticsFrame) -> String {
        switch (frame.file, frame.line) {
        case let (file?, line?):
            return "\(file):\(line)"
        case let (file?, nil):
            return file
        case (nil, _):
            return frame.library ?? "?"
        }
    }

    // Crashlytics quirk: the library name is spelled differently on the blame frame
    // and on thread frames, so it is not part of the comparison.
    /// Frames without source information are told apart by address and library.
    func sameLocation(_ lhs: CrashlyticsFrame, _ rhs: CrashlyticsFrame) -> Bool {
        if hasLocation(lhs) || hasLocation(rhs) {
            return lhs.symbol == rhs.symbol && lhs.file == rhs.file && lhs.line == rhs.line
        }
        guard let address = lhs.address, address == rhs.address else { return false }
        return lhs.library == rhs.library
    }

    // MARK: - Stack selection

    private func crashedThreadFrames(in event: CrashlyticsEvent) -> [CrashlyticsFrame] {
        let crashedThreads = event.threads.filter(\.crashed)
        let crashedThread = crashedThreads.first(where: { !$0.frames.isEmpty }) ?? crashedThreads.first
        return crashedThread?.frames ?? []
    }

    private func primaryStack(in event: CrashlyticsEvent) -> [CrashlyticsFrame] {
        if let threadIndex = chosenThreadIndex(in: event) {
            return event.threads[threadIndex].frames
        }
        return fallbackStack(in: event.exceptions) ?? fallbackStack(in: event.errors) ?? []
    }

    private func fallbackStack(in entries: [CrashlyticsException]) -> [CrashlyticsFrame]? {
        let withFrames = entries.filter { !$0.frames.isEmpty }
        return (withFrames.first(where: \.blamed) ?? withFrames.first)?.frames
    }

    private func stackFrame(from frame: CrashlyticsFrame, fallbackIndex: Int) -> StackFrame {
        StackFrame(
            index: frame.stackIndex ?? fallbackIndex,
            binaryName: frame.library ?? "?",
            symbol: frame.symbol,
            file: frame.file,
            line: frame.line,
            column: frame.column,
            address: frame.address,
            imageUUID: nil,
            isSymbolicated: frame.symbol != nil,
            firebaseSymbol: frame.firebaseSymbol,
            symbolicated: frame.symbolicated
        )
    }

    // MARK: - Frame predicates

    private func hasLocation(_ frame: CrashlyticsFrame) -> Bool {
        frame.symbol != nil || frame.file != nil
    }

    private func isLocatable(_ frame: CrashlyticsFrame) -> Bool {
        hasLocation(frame) || frame.library != nil || frame.address != nil
    }

    private func includes(_ frame: CrashlyticsFrame, filter: FrameFilter) -> Bool {
        if filter.appFramesOnly { return classifier.isAppFrame(frame) }
        if filter.noSystemFrames { return !classifier.isSystemFrame(frame) }
        return true
    }
}
