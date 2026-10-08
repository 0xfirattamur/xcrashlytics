import Foundation

// Crashlytics quirk: v1alpha sends int64s as numbers or strings, so each type accepts every shape
// seen and degrades to nil/empty instead of failing the page.
extension CrashlyticsDTO {
    struct FlexibleInt: Decodable, Sendable, Equatable {
        let intValue: Int?

        init(_ value: Int?) {
            self.intValue = value
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.singleValueContainer()
            if let value = try? container.decode(Int.self) {
                self.intValue = value
            } else if let value = try? container.decode(String.self) {
                self.intValue = Int(value.trimmingCharacters(in: .whitespaces))
            } else if let value = try? container.decode(Double.self), let exact = Int(exactly: value) {
                self.intValue = exact
            } else {
                self.intValue = nil
            }
        }
    }

    // Addresses arrive as a number, a decimal string, or a `0x` hex string.
    struct FlexibleAddress: Decodable, Sendable, Equatable {
        let value: UInt64?

        init(from decoder: Decoder) throws {
            let container = try decoder.singleValueContainer()
            if let number = try? container.decode(UInt64.self) {
                self.value = number
            } else if let text = try? container.decode(String.self) {
                let trimmed = text.trimmingCharacters(in: .whitespaces)
                if trimmed.lowercased().hasPrefix("0x") {
                    self.value = UInt64(trimmed.dropFirst(2), radix: 16)
                } else {
                    self.value = UInt64(trimmed)
                }
            } else {
                self.value = nil
            }
        }
    }

    struct FlexibleString: Decodable, Sendable, Equatable {
        let value: String?

        init(_ value: String?) {
            self.value = value
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.singleValueContainer()
            if let text = try? container.decode(String.self) {
                value = text
            } else if let number = try? container.decode(Int.self) {
                value = String(number)
            } else if let number = try? container.decode(Double.self) {
                value = String(number)
            } else if let flag = try? container.decode(Bool.self) {
                value = String(flag)
            } else {
                value = nil
            }
        }
    }

    // `customKeys` and breadcrumb `params` may be a map or a `[{key, value}]` list; anything else is empty.
    struct StringMap: Decodable, Sendable, Equatable {
        var values: [String: String]

        init(from decoder: Decoder) throws {
            if let map = try? decoder.singleValueContainer().decode([String: FlexibleString].self) {
                values = map.compactMapValues(\.value)
            } else if let pairs = try? decoder.singleValueContainer().decode([KeyValue].self) {
                values = Dictionary(pairs.compactMap { pair in
                    pair.key.map { ($0, pair.value?.value ?? "") }
                }, uniquingKeysWith: { first, _ in first })
            } else {
                values = [:]
            }
        }

        private struct KeyValue: Decodable {
            var key: String?
            var value: FlexibleString?
        }
    }

    @propertyWrapper
    struct LossyList<Element: Decodable & Sendable & Equatable>: Decodable, Sendable, Equatable {
        var wrappedValue: [Element]

        init(wrappedValue: [Element] = []) {
            self.wrappedValue = wrappedValue
        }

        init(from decoder: Decoder) throws {
            var elements: [Element] = []
            if var container = try? decoder.unkeyedContainer() {
                while !container.isAtEnd {
                    if let element = try? container.decode(Element.self) {
                        elements.append(element)
                    } else {
                        // A failed decode does not advance the container; consume the element.
                        _ = try? container.decode(Skipped.self)
                    }
                }
            }
            self.wrappedValue = elements
        }

        private struct Skipped: Decodable {}
    }
}

extension KeyedDecodingContainer {
    func decode<Element>(
        _ type: CrashlyticsDTO.LossyList<Element>.Type, forKey key: Key
    ) throws -> CrashlyticsDTO.LossyList<Element> {
        try decodeIfPresent(type, forKey: key) ?? CrashlyticsDTO.LossyList()
    }
}
