//
//  CrashLogParser.swift
//  xcrashlytics
//
//  Created by FIRAT TAMUR on 4.06.2026.
//

import Foundation
import CryptoKit

/// Parses Apple's plain-text `.crash` reports into `CrashRecord`.
///
/// This is the format Xcode Organizer stores inside `.xccrashpoint` bundles,
/// so it is the live format this tool ingests. Reports arrive already
/// symbolicated: frames carry symbol names and `(File.swift:line)` source
/// locations, no local dSYM work needed.
///
/// Layout (simplified):
/// ```
/// Identifier:          com.example.MyApp
/// Version:             1 (1.0)
/// OS Version:          iPhone OS 17.0 (...)
/// Exception Type:      EXC_BAD_ACCESS (SIGSEGV)
/// Triggered by Thread: 0
///
/// Thread 0 Crashed:
/// 0   MyApp    0x0000000100001000  -[VC method] + 24
/// 1   ...
///
/// Binary Images:
/// 0x100000000 - 0x1000fffff MyApp arm64  <uuid> /path/to/MyApp
/// ```
struct CrashLogParser: Sendable {
    private let fs: FileSystem

    init(fs: FileSystem) {
        self.fs = fs
    }

    /// Reads `path` and parses it.
    func parse(path: String) throws -> CrashEvent {
        let data = try fs.read(at: path)
        guard let text = String(data: data, encoding: .utf8) else {
            throw CrashParsingError.ioError("not utf8: \(path)")
        }
        return try parse(text: text, path: path)
    }

    /// Parses raw text (useful in tests).
    func parse(text: String, path: String) throws -> CrashEvent {
        let lines = text.components(separatedBy: "\n")
        let header = parseHeader(lines)

        guard let exceptionType = header["Exception Type"] else {
            throw CrashParsingError.malformedHeader("missing Exception Type in \(path)")
        }
        let (excType, signal) = splitExceptionLine(exceptionType)
        let subtype = header["Exception Subtype"]

        let crashedThreadIndex: Int = {
            guard let raw = header["Triggered by Thread"], let v = Int(raw.trimmingCharacters(in: .whitespaces)) else {
                return 0
            }
            return v
        }()

        let images = parseImages(lines)
        let frames = parseCrashedThreadFrames(lines, images: images)

        let id = header["Incident Identifier"] ?? Self.stableFallbackId(for: text)
        let bundleId = header["Identifier"]
        let bundleVersion = header["Version"]
        let osVersion = header["OS Version"]
        let deviceModel = header["Hardware Model"]
        let timestamp = (header["Date/Time"]).flatMap(Self.parseTimestamp)

        return CrashEvent(
            id: "XC-\(id)",
            providerId: id,
            source: .xcode,
            bundleId: bundleId,
            bundleVersion: bundleVersion,
            osVersion: osVersion,
            deviceModel: deviceModel,
            crashedThreadIndex: crashedThreadIndex,
            exception: ExceptionInfo(
                exceptionType: excType,
                signal: signal,
                subtype: subtype,
                description: nil
            ),
            frames: frames,
            binaryImages: images,
            timestamp: timestamp,
            rawPath: path
        )
    }

    // MARK: - Helpers

    private func parseHeader(_ lines: [String]) -> [String: String] {
        var out: [String: String] = [:]
        for raw in lines {
            if raw.contains("Thread ") && raw.contains("Crashed") { break }
            if raw.hasPrefix("Binary Images:") { break }
            guard let colon = raw.firstIndex(of: ":") else { continue }
            let key = String(raw[..<colon]).trimmingCharacters(in: .whitespaces)
            let value = String(raw[raw.index(after: colon)...]).trimmingCharacters(in: .whitespaces)
            if !key.isEmpty, !value.isEmpty {
                out[key] = value
            }
        }
        return out
    }

    private func splitExceptionLine(_ raw: String) -> (String, String?) {
        // Form: "EXC_BAD_ACCESS (SIGSEGV)"
        if let openIdx = raw.firstIndex(of: "("),
           let closeIdx = raw.lastIndex(of: ")"),
           openIdx < closeIdx {
            let type = raw[..<openIdx].trimmingCharacters(in: .whitespaces)
            let signal = raw[raw.index(after: openIdx)..<closeIdx].trimmingCharacters(in: .whitespaces)
            return (type, signal.isEmpty ? nil : signal)
        }
        return (raw.trimmingCharacters(in: .whitespaces), nil)
    }

    private func parseImages(_ lines: [String]) -> [BinaryImage] {
        guard let start = lines.firstIndex(where: { $0.hasPrefix("Binary Images:") }) else { return [] }
        var out: [BinaryImage] = []
        for raw in lines.dropFirst(start + 1) {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.isEmpty { continue }
            guard let img = Self.parseImageLine(line) else { continue }
            out.append(img)
        }
        return out
    }

    private static func parseImageLine(_ line: String) -> BinaryImage? {
        // Form: "0x100000000 - 0x1000fffff My App arm64  <uuid32> /path/My App"
        // Name can contain spaces: it spans from after the end address up to
        // the arch token, which sits immediately before the <uuid>.
        let parts = line.split(whereSeparator: { $0 == " " }).map(String.init)
        guard parts.count >= 6, let base = UInt64(parts[0].dropFirst(2), radix: 16) else { return nil }
        guard
            let uuidIdx = parts.firstIndex(where: { $0.hasPrefix("<") && $0.hasSuffix(">") }),
            uuidIdx >= 5, uuidIdx < parts.count - 1
        else { return nil }
        // [0..2] are "addr - addr"; name spans [3] up to the arch at [uuidIdx - 1].
        let name = parts[3..<(uuidIdx - 1)].joined(separator: " ")
        guard !name.isEmpty else { return nil }
        let arch = parts[uuidIdx - 1]
        let uuid = String(parts[uuidIdx].dropFirst().dropLast())
        let path = parts[(uuidIdx + 1)...].joined(separator: " ")
        return BinaryImage(
            name: name,
            uuid: Self.normaliseUUID(uuid),
            loadAddress: base,
            arch: arch,
            path: path
        )
    }

    private static func normaliseUUID(_ raw: String) -> String {
        // Legacy reports use 32-char hex with no dashes; convert to canonical
        // 8-4-4-4-12 form so it matches atos output.
        let hex = raw.replacingOccurrences(of: "-", with: "").uppercased()
        guard hex.count == 32 else { return raw.uppercased() }
        let s = Array(hex)
        return "\(String(s[0..<8]))-\(String(s[8..<12]))-\(String(s[12..<16]))-\(String(s[16..<20]))-\(String(s[20..<32]))"
    }

    /// Frames of the first "Thread N Crashed:" section. Other thread sections
    /// are skipped — `CrashRecord` only carries the crashed thread.
    private func parseCrashedThreadFrames(_ lines: [String], images: [BinaryImage]) -> [Frame] {
        var frames: [Frame] = []
        var inThread = false
        for raw in lines {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if !inThread {
                if line.hasPrefix("Thread ") && line.contains("Crashed") { inThread = true }
                continue
            }
            if line.isEmpty || line.hasPrefix("Binary Images:") { break }
            if let frame = Self.parseFrameLine(line, images: images) {
                frames.append(frame)
            }
        }
        return frames
    }

    private static func parseFrameLine(_ line: String, images: [BinaryImage]) -> Frame? {
        // Form: "0   My App    0x0000000100001000 -[VC method] + 24 (File.swift:42)"
        // Binary names can contain spaces, so locate the first address-shaped
        // token and treat everything between the index and it as the name.
        let parts = line.split(whereSeparator: { $0 == " " || $0 == "\t" }).map(String.init).filter { !$0.isEmpty }
        guard parts.count >= 3, let index = Int(parts[0]) else { return nil }
        // Search starts at [2]: [0] is the frame index, [1] the name's first token.
        guard
            let addrIdx = parts[2...].firstIndex(where: { $0.hasPrefix("0x") && UInt64($0.dropFirst(2), radix: 16) != nil }),
            let address = UInt64(parts[addrIdx].dropFirst(2), radix: 16)
        else { return nil }
        let binaryName = parts[1..<addrIdx].joined(separator: " ")
        let rest = parts[(addrIdx + 1)...].joined(separator: " ")
        let (symbolText, file, line) = Self.splitSourceLocation(from: rest)
        let symbol: String? = symbolText.isEmpty ? nil : Self.stripPlusOffset(symbolText)
        let matchingImage = images.first(where: { $0.name == binaryName })
        return Frame(
            index: index,
            binaryName: binaryName,
            symbol: symbol,
            file: file,
            line: line,
            column: nil,
            address: address,
            imageUUID: matchingImage?.uuid,
            isSymbolicated: symbol != nil && !(symbol?.contains("0x") ?? false)
        )
    }

    /// Splits the trailing "(File.swift:42)" Apple appends to symbolicated
    /// frames off the symbol text. "(:-1)" and "(file.c:0)" mark frames
    /// without usable source info — stripped from the symbol, but yield no
    /// file/line. A trailing ")" that is part of a Swift signature (no
    /// integer after the last colon) is left untouched.
    private static func splitSourceLocation(from s: String) -> (symbolText: String, file: String?, line: Int?) {
        guard
            s.hasSuffix(")"), let openIdx = s.lastIndex(of: "("),
            let colonIdx = s[openIdx...].lastIndex(of: ":"),
            let line = Int(s[s.index(after: colonIdx)..<s.index(before: s.endIndex)])
        else { return (s, nil, nil) }
        let symbolText = String(s[..<openIdx]).trimmingCharacters(in: .whitespaces)
        let file = String(s[s.index(after: openIdx)..<colonIdx])
        guard !file.isEmpty, line > 0 else { return (symbolText, nil, nil) }
        return (symbolText, file, line)
    }

    private static func stripPlusOffset(_ s: String) -> String {
        // Strip the trailing " + 24" byte offset from a symbol — keeps just the demangled name.
        if let range = s.range(of: " + ", options: .backwards) {
            return String(s[..<range.lowerBound])
        }
        return s
    }

    /// Deterministic id for reports missing an Incident Identifier — the same
    /// file must map to the same id across rescans or grouping breaks.
    private static func stableFallbackId(for text: String) -> String {
        SHA256.hash(data: Data(text.utf8)).prefix(16).map { String(format: "%02X", $0) }.joined()
    }

    private static func parseTimestamp(_ s: String) -> Date? {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        // Organizer reports carry 4 fractional digits; older reports 3 or none.
        for format in [
            "yyyy-MM-dd HH:mm:ss.SSSS Z",
            "yyyy-MM-dd HH:mm:ss.SSS Z",
            "yyyy-MM-dd HH:mm:ss Z",
        ] {
            f.dateFormat = format
            if let d = f.date(from: s) { return d }
        }
        return nil
    }
}
