import Foundation

enum LegacyCrashFrameParser {
    static func images(in lines: [String]) -> [BinaryImage] {
        guard let start = lines.firstIndex(where: { $0.hasPrefix("Binary Images:") }) else { return [] }
        return lines.dropFirst(start + 1).compactMap { $0.isEmpty ? nil : imageLine($0) }
    }

    private static func imageLine(_ line: String) -> BinaryImage? {
        // "0x100000000 - 0x1000fffff My App arm64  <uuid32> /path/My App": the name may
        // contain spaces, so it spans from after the end address to the arch before the <uuid>.
        let parts = line.split(whereSeparator: { $0 == " " }).map(String.init)
        guard parts.count >= 6, parts[0].hasPrefix("0x"), let base = UInt64(parts[0].dropFirst(2), radix: 16) else {
            return nil
        }
        guard
            let uuidIndex = parts.firstIndex(where: { $0.hasPrefix("<") && $0.hasSuffix(">") }),
            uuidIndex >= 5, uuidIndex < parts.count - 1
        else { return nil }
        let name = cleanImageName(parts[3..<(uuidIndex - 1)].joined(separator: " "))
        guard !name.isEmpty else { return nil }
        let arch = parts[uuidIndex - 1]
        let uuid = String(parts[uuidIndex].dropFirst().dropLast())
        let path = parts[(uuidIndex + 1)...].joined(separator: " ")
        return BinaryImage(
            name: name,
            uuid: CrashReportIdentifiers.normalisedUUID(uuid),
            loadAddress: base,
            arch: arch,
            path: path
        )
    }

    // Pre-iOS-13 reports write app images as `+MyApp (1.0)`, while frames carry the bare name.
    private static func cleanImageName(_ raw: String) -> String {
        var name = raw
        if name.hasPrefix("+") { name.removeFirst() }
        if name.hasSuffix(")"), let open = name.lastIndex(of: "("),
           name[name.index(after: open)...].first?.isNumber == true, open > name.startIndex {
            name = String(name[..<open])
        }
        return name.trimmingCharacters(in: .whitespaces)
    }

    static func frames(in lines: ArraySlice<String>, images: [BinaryImage]) -> [StackFrame] {
        lines.compactMap { frame($0, images: images) }
    }

    private static func isHexAddress(_ token: String) -> Bool {
        token.hasPrefix("0x") && UInt64(token.dropFirst(2), radix: 16) != nil
    }

    private static func frame(_ text: String, images: [BinaryImage]) -> StackFrame? {
        // Binary names can contain spaces: the name is everything between the index and
        // the first address-shaped token.
        let parts = text.split(whereSeparator: { $0 == " " || $0 == "\t" }).map(String.init)
        guard parts.count >= 3, let index = Int(parts[0]) else { return nil }
        guard
            let addressIndex = parts[2...].firstIndex(where: isHexAddress),
            let address = UInt64(parts[addressIndex].dropFirst(2), radix: 16)
        else { return nil }
        let binaryName = parts[1..<addressIndex].joined(separator: " ")
        let rest = parts[(addressIndex + 1)...].joined(separator: " ")
        let (symbolText, file, line) = splitSourceLocation(from: rest)
        let symbol: String? = symbolText.isEmpty ? nil : stripPlusOffset(symbolText)
        let matchingImage = images.first(where: { $0.name == binaryName })
        return StackFrame(
            index: index,
            binaryName: binaryName,
            symbol: symbol,
            file: file,
            line: line,
            column: nil,
            address: address,
            imageUUID: matchingImage?.uuid,
            // Unsymbolicated frames print `0x<image base> + <offset>`, leaving the base address as the "symbol".
            isSymbolicated: symbol.map { !FrameNormalizer.isAddressOnly($0) } ?? false
        )
    }

    // "(:-1)" and "(file.c:0)" mark frames without source info: stripped, but yield no file/line.
    // A trailing ")" belonging to a Swift signature (no integer after the colon) stays.
    private static func splitSourceLocation(from text: String) -> (symbolText: String, file: String?, line: Int?) {
        guard
            text.hasSuffix(")"), let openIndex = text.lastIndex(of: "("),
            let colonIndex = text[openIndex...].lastIndex(of: ":"),
            let line = Int(text[text.index(after: colonIndex)..<text.index(before: text.endIndex)])
        else { return (text, nil, nil) }
        let symbolText = String(text[..<openIndex]).trimmingCharacters(in: .whitespaces)
        let file = String(text[text.index(after: openIndex)..<colonIndex])
        guard !file.isEmpty, line > 0 else { return (symbolText, nil, nil) }
        return (symbolText, file, line)
    }

    private static func stripPlusOffset(_ symbol: String) -> String {
        if let range = symbol.range(of: " + ", options: .backwards) {
            return String(symbol[..<range.lowerBound])
        }
        return symbol
    }
}
