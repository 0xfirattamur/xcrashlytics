import Foundation

struct FrameSummary: Encodable, Sendable {
    var index: Int
    var binaryName: String
    var symbol: String?
    var file: String?
    var line: Int?
    var isBlamed: Bool
    var firebaseSymbol: String?
    var symbolicated: String?

    init(index: Int, frame: CrashlyticsFrame, isBlamed: Bool? = nil) {
        self.index = index
        self.binaryName = frame.library ?? "?"
        self.symbol = frame.symbol
        self.file = frame.file
        self.line = frame.line
        self.isBlamed = isBlamed ?? frame.blamed
        self.firebaseSymbol = frame.firebaseSymbol
        self.symbolicated = frame.symbolicated
    }

    static func frames(of event: CrashlyticsEvent, filter: FrameFilter, selector: FrameSelector) -> [FrameSummary] {
        selector.filteredFrames(from: event, filter: filter).enumerated().map { position, frame in
            FrameSummary(
                index: frame.stackIndex ?? position, frame: frame, isBlamed: selector.isBlamed(frame, in: event))
        }
    }

    static func unfilteredBlamedFrame(
        of event: CrashlyticsEvent, filter: FrameFilter, selector: FrameSelector
    ) -> FrameSummary? {
        let stack = selector.stackFrames(from: event, crashingThreadOnly: filter.crashingThreadOnly)
        guard let position = stack.firstIndex(where: { selector.isBlamed($0, in: event) }) else { return nil }
        return FrameSummary(index: stack[position].stackIndex ?? position, frame: stack[position], isBlamed: true)
    }
}
