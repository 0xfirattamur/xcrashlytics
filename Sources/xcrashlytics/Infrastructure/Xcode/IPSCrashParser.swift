import Foundation

/// An `.ips` file is a JSON header line followed by a JSON body. Hang, jetsam and other
/// diagnostics have no `exception`/`threads`; they are reported as unsupported, not skipped.
struct IPSCrashParser: CrashReportParser {
    typealias JSON = [String: Any]

    func canParse(_ text: String) -> Bool {
        text.drop(while: \.isWhitespace).first == "{"
    }

    func parse(text: String, path: String) throws -> ParsedCrashReport {
        let (header, body) = try decode(text)
        let exception = try requireException(in: body, bugType: header?["bug_type"].flatMap(string))
        let images = (body["usedImages"] as? [JSON] ?? []).map(image)
        let crashedThread = findCrashedThread(in: body, threads: exception.threads, images: images)

        var warnings: [CommandWarning] = []
        if crashedThread.frames.isEmpty {
            let reason = crashedThread.index == nil ? "no triggered thread" : "the triggered thread has no frames"
            warnings.append(ParsedCrashReport.noThreadFramesWarning(reason: reason, path: path))
        }

        let incidentId = CrashReportIdentifiers.sanitizedIncidentId(string(body["incident"]))
            ?? CrashReportIdentifiers.sanitizedIncidentId(header?["incident_id"].flatMap(string))
            ?? CrashReportIdentifiers.stableFallbackId(for: text)
        let bundleInfo = body["bundleInfo"] as? JSON
        let timestamp = (string(body["captureTime"]) ?? header?["timestamp"].flatMap(string))
            .flatMap(CrashTimestamp.parse)

        let event = CrashEvent(
            id: "XC-\(incidentId)",
            providerId: incidentId,
            source: .xcode,
            bundleId: string(bundleInfo?["CFBundleIdentifier"]) ?? header?["bundleID"].flatMap(string),
            bundleVersion: bundleVersion(bundleInfo) ?? header?["app_version"].flatMap(string),
            osVersion: osVersion(body["osVersion"]) ?? header?["os_version"].flatMap(string),
            deviceModel: string(body["modelCode"]),
            crashedThreadIndex: crashedThread.index ?? crashedThread.faultingIndex ?? 0,
            exception: exception.descriptor,
            frames: crashedThread.frames,
            binaryImages: images,
            timestamp: timestamp,
            rawPath: path
        )
        return ParsedCrashReport(event: event, warnings: warnings)
    }

    // MARK: - Exception and crashed thread

    private struct ExceptionSection {
        var descriptor: ExceptionDescriptor
        var threads: [JSON]
    }

    private struct CrashedThread {
        /// The thread flagged `triggered`, or else the `faultingThread` when it is in range.
        var index: Int?
        var faultingIndex: Int?
        var frames: [StackFrame]
    }

    private func requireException(in body: JSON, bugType: String?) throws -> ExceptionSection {
        guard let exception = body["exception"] as? JSON,
              let type = string(exception["type"]),
              let threads = body["threads"] as? [JSON]
        else {
            let kind = bugType.map { "bug_type \($0)" } ?? "this .ips file"
            throw CrashReportParseError.unsupportedReport(
                "\(kind) is not a crash report (no exception or threads); only crash reports are supported")
        }
        let descriptor = ExceptionDescriptor(
            exceptionType: type,
            signal: string(exception["signal"]),
            subtype: string(exception["subtype"])
        )
        return ExceptionSection(descriptor: descriptor, threads: threads)
    }

    private func findCrashedThread(in body: JSON, threads: [JSON], images: [BinaryImage]) -> CrashedThread {
        let faultingIndex = (body["faultingThread"] as? NSNumber)?.intValue
        let triggeredIndex = threads.firstIndex { ($0["triggered"] as? Bool) == true }
        let faultingIndexInRange = faultingIndex.flatMap { threads.indices.contains($0) ? $0 : nil }
        guard let crashedIndex = triggeredIndex ?? faultingIndexInRange else {
            return CrashedThread(index: nil, faultingIndex: faultingIndex, frames: [])
        }
        let frameObjects = threads[crashedIndex]["frames"] as? [JSON] ?? []
        let frames = frameObjects.enumerated().map { position, json in
            frame(json, at: position, images: images)
        }
        return CrashedThread(index: crashedIndex, faultingIndex: faultingIndex, frames: frames)
    }

    // MARK: - Decoding

    // Some files hold a single JSON object: just a body, no header line.
    private func decode(_ text: String) throws -> (header: JSON?, body: JSON) {
        let trimmed = text.drop(while: \.isWhitespace)
        let newline = trimmed.firstIndex(where: \.isNewline)
        let firstLine = newline.map { trimmed[..<$0] } ?? trimmed
        let rest = newline.map { trimmed[$0...] } ?? ""
        if let header = object(String(firstLine)), rest.contains(where: { !$0.isWhitespace }) {
            guard let body = object(String(rest)) else {
                throw CrashReportParseError.malformedBody("the .ips body after the header line is not valid JSON")
            }
            return (header, body)
        }
        if let single = object(String(trimmed)) { return (nil, single) }
        throw CrashReportParseError.malformedHeader("the .ips file is not valid JSON")
    }

    private func object(_ text: String) -> JSON? {
        (try? JSONSerialization.jsonObject(with: Data(text.utf8))) as? JSON
    }

    // MARK: - Field mapping

    private func image(_ json: JSON) -> BinaryImage {
        let path = string(json["path"]) ?? ""
        let name = string(json["name"]) ?? path.split(separator: "/").last.map(String.init) ?? "???"
        return BinaryImage(
            name: name,
            uuid: CrashReportIdentifiers.normalisedUUID(string(json["uuid"]) ?? ""),
            loadAddress: (json["base"] as? NSNumber)?.uint64Value ?? 0,
            arch: string(json["arch"]) ?? "",
            path: path
        )
    }

    private func frame(_ json: JSON, at index: Int, images: [BinaryImage]) -> StackFrame {
        let imageIndex = (json["imageIndex"] as? NSNumber)?.intValue
        let image = imageIndex.flatMap { images.indices.contains($0) ? images[$0] : nil }
        let offset = (json["imageOffset"] as? NSNumber)?.uint64Value
        let symbol = string(json["symbol"]).flatMap { $0.isEmpty ? nil : $0 }
        let file = string(json["sourceFile"]).flatMap { $0.isEmpty ? nil : $0 }
        let sourceLine = (json["sourceLine"] as? NSNumber)?.intValue
        let positiveLine = sourceLine.flatMap { $0 > 0 ? $0 : nil }
        let address = image.flatMap { image in offset.map { image.loadAddress &+ $0 } }
        let imageUUID = image.flatMap { $0.uuid.isEmpty ? nil : $0.uuid }
        let isSymbolicated = symbol.map { !FrameNormalizer.isAddressOnly($0) } ?? false
        return StackFrame(
            index: index,
            binaryName: image?.name ?? "???",
            symbol: symbol,
            file: file,
            line: file == nil ? nil : positiveLine,
            address: address,
            imageUUID: imageUUID,
            isSymbolicated: isSymbolicated
        )
    }

    private func bundleVersion(_ info: JSON?) -> String? {
        guard let short = string(info?["CFBundleShortVersionString"]) else { return string(info?["CFBundleVersion"]) }
        guard let build = string(info?["CFBundleVersion"]) else { return short }
        return "\(short) (\(build))"
    }

    private func osVersion(_ value: Any?) -> String? {
        guard let json = value as? JSON, let train = string(json["train"]) else { return string(value) }
        guard let build = string(json["build"]) else { return train }
        return "\(train) (\(build))"
    }

    private func string(_ value: Any?) -> String? {
        switch value {
        case let text as String: return text.isEmpty ? nil : text
        case let number as NSNumber: return number.stringValue
        default: return nil
        }
    }
}
