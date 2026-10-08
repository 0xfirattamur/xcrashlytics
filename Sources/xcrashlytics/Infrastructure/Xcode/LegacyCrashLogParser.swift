import Foundation

struct LegacyCrashLogParser: CrashReportParser {
    func canParse(_ text: String) -> Bool { true }

    func parse(text: String, path: String) throws -> ParsedCrashReport {
        // `isNewline` treats "\r\n" as one character, so CRLF files split cleanly.
        let lines = text.split(omittingEmptySubsequences: false, whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        let header = Self.parseHeader(lines)
        let exceptionType = try Self.requireExceptionType(in: header)
        let images = LegacyCrashFrameParser.images(in: lines)
        let crashedThread = Self.findCrashedThread(in: lines, header: header, images: images)

        var warnings: [CommandWarning] = []
        if crashedThread.frames.isEmpty {
            warnings.append(ParsedCrashReport.noThreadFramesWarning(
                reason: crashedThread.missingFramesReason, path: path))
        }

        let incidentId = CrashReportIdentifiers.sanitizedIncidentId(header["Incident Identifier"])
            ?? CrashReportIdentifiers.stableFallbackId(for: text)
        let event = CrashEvent(
            id: "XC-\(incidentId)",
            providerId: incidentId,
            source: .xcode,
            bundleId: header["Identifier"],
            bundleVersion: header["Version"],
            osVersion: header["OS Version"],
            deviceModel: header["Hardware Model"],
            crashedThreadIndex: crashedThread.index,
            exception: Self.exceptionDescriptor(from: exceptionType, header: header),
            frames: crashedThread.frames,
            binaryImages: images,
            timestamp: header["Date/Time"].flatMap(CrashTimestamp.parse),
            rawPath: path
        )
        return ParsedCrashReport(event: event, warnings: warnings)
    }

    // MARK: - Header

    private static func requireExceptionType(in header: [String: String]) throws -> String {
        if let exceptionType = header["Exception Type"] { return exceptionType }
        if let event = header["Event"] {
            throw CrashReportParseError.unsupportedReport(
                "this is a '\(event)' diagnostic report, not a crash report (no Exception Type)")
        }
        throw CrashReportParseError.malformedHeader("missing Exception Type; this does not look like a crash report")
    }

    private static func exceptionDescriptor(
        from exceptionType: String, header: [String: String]
    ) -> ExceptionDescriptor {
        let (name, signal) = splitExceptionLine(exceptionType)
        return ExceptionDescriptor(
            exceptionType: name,
            signal: signal,
            subtype: header["Exception Subtype"],
            description: nil
        )
    }

    // MARK: - Crashed thread

    private struct CrashedThread {
        var index: Int
        var frames: [StackFrame]
        var missingFramesReason: String
    }

    private static func findCrashedThread(
        in lines: [String], header: [String: String], images: [BinaryImage]
    ) -> CrashedThread {
        let headerThread = (header["Triggered by Thread"] ?? header["Crashed Thread"])
            .flatMap { Int($0.prefix(while: \.isNumber)) }
        let sections = threadSections(lines)
        let crashedSection = headerThread.flatMap { index in sections.first { $0.index == index } }
            ?? sections.first { $0.isCrashed }

        guard let crashedSection else {
            let alternative = headerThread.map { " or 'Thread \($0):' section" } ?? ""
            return CrashedThread(
                index: headerThread ?? 0,
                frames: [],
                missingFramesReason: "no 'Thread N Crashed:' section" + alternative
            )
        }
        let frames = LegacyCrashFrameParser.frames(in: lines[crashedSection.bodyRange], images: images)
        return CrashedThread(
            index: crashedSection.index,
            frames: frames,
            missingFramesReason: "the crashed thread has no frames"
        )
    }

    /// The first occurrence of a key wins.
    private static func parseHeader(_ lines: [String]) -> [String: String] {
        var fields: [String: String] = [:]
        for line in lines {
            if threadHeader(line) != nil || line.hasPrefix("Binary Images:") { break }
            guard let colon = line.firstIndex(of: ":") else { continue }
            let key = String(line[..<colon]).trimmingCharacters(in: .whitespaces)
            let value = String(line[line.index(after: colon)...]).trimmingCharacters(in: .whitespaces)
            if !key.isEmpty, !value.isEmpty, fields[key] == nil {
                fields[key] = value
            }
        }
        return fields
    }

    private static func splitExceptionLine(_ raw: String) -> (String, String?) {
        if let openIndex = raw.firstIndex(of: "("),
           let closeIndex = raw.lastIndex(of: ")"),
           openIndex < closeIndex {
            let type = raw[..<openIndex].trimmingCharacters(in: .whitespaces)
            let signal = raw[raw.index(after: openIndex)..<closeIndex].trimmingCharacters(in: .whitespaces)
            return (type, signal.isEmpty ? nil : signal)
        }
        return (raw.trimmingCharacters(in: .whitespaces), nil)
    }

    // MARK: - Thread sections

    private struct ThreadSection {
        var index: Int
        var isCrashed: Bool
        var bodyRange: Range<Int>
    }

    // `Thread 3 name:  CrashedWorker` is a label inside a newer report's header block, not a stack section.
    private static func threadHeader(_ line: String) -> (index: Int, isCrashed: Bool)? {
        guard line.hasPrefix("Thread ") else { return nil }
        let rest = line.dropFirst("Thread ".count)
        let digits = rest.prefix(while: \.isNumber)
        guard let index = Int(digits) else { return nil }
        let tail = rest.dropFirst(digits.count)
        if tail.hasPrefix(":") { return (index, false) }
        if tail.hasPrefix(" Crashed:") { return (index, true) }
        return nil
    }

    // `Thread 3 name:` follows a thread header inside its block; it never starts or ends a frame list.
    private static func isThreadLabel(_ line: String) -> Bool {
        line.hasPrefix("Thread ") && line.dropFirst(7).drop(while: \.isNumber).hasPrefix(" name:")
    }

    private static func threadSections(_ lines: [String]) -> [ThreadSection] {
        var sections: [ThreadSection] = []
        var lineIndex = 0
        while lineIndex < lines.count {
            let line = lines[lineIndex]
            if line.hasPrefix("Binary Images:") { break }
            guard let thread = threadHeader(line) else {
                lineIndex += 1
                continue
            }
            let bodyStart = lineIndex + 1
            let bodyEnd = endOfThreadBody(startingAt: bodyStart, in: lines)
            sections.append(ThreadSection(
                index: thread.index, isCrashed: thread.isCrashed, bodyRange: bodyStart..<bodyEnd))
            lineIndex = bodyEnd
        }
        return sections
    }

    private static func endOfThreadBody(startingAt start: Int, in lines: [String]) -> Int {
        var end = start
        while end < lines.count, !isEndOfThreadBody(lines[end]) {
            end += 1
        }
        return end
    }

    private static func isEndOfThreadBody(_ line: String) -> Bool {
        line.isEmpty || line.hasPrefix("Binary Images:") || threadHeader(line) != nil || isThreadLabel(line)
    }
}
