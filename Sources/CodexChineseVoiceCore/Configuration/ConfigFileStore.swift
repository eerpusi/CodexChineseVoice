import Foundation

public struct ConfigFileStore: ConfigStoring, Sendable {
    private static let key = "ark_plan_api_key"

    public static let `default` = ConfigFileStore(
        fileURL: FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".config")
            .appendingPathComponent("codex-chinese-voice")
            .appendingPathComponent("config.toml")
    )

    public let fileURL: URL

    public init(fileURL: URL) {
        self.fileURL = fileURL
    }

    public func loadAPIKey() throws -> String? {
        do {
            guard let data = try SecureFileAccess.read(from: fileURL) else {
                return nil
            }
            guard let contents = String(data: data, encoding: .utf8) else {
                throw ConfigurationError.invalidFile
            }
            return try Self.parse(contents)
        } catch let error as ConfigurationError {
            throw error
        } catch SecureFileAccessError.missing {
            return nil
        } catch {
            throw ConfigurationError.unreadableFile
        }
    }

    public func saveAPIKey(_ apiKey: String) throws {
        let encodedKey = try Self.encode(apiKey)
        let contents = "\(Self.key) = \(encodedKey)\n"
        do {
            try SecureFileAccess.write(Data(contents.utf8), to: fileURL)
        } catch let error as ConfigurationError {
            throw error
        } catch {
            throw ConfigurationError.unreadableFile
        }
    }
}

private extension ConfigFileStore {
    static func parse(_ contents: String) throws -> String {
        var apiKey: String?

        for rawLine in contents.split(
            separator: "\n",
            omittingEmptySubsequences: false
        ) {
            let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            if line.isEmpty || line.hasPrefix("#") {
                continue
            }

            guard let separator = line.firstIndex(of: "=") else {
                throw ConfigurationError.invalidFile
            }
            let name = line[..<separator]
                .trimmingCharacters(in: .whitespaces)
            let encodedValue = line[line.index(after: separator)...]
                .trimmingCharacters(in: .whitespaces)
            guard name == key, apiKey == nil, !encodedValue.isEmpty else {
                throw ConfigurationError.invalidFile
            }
            guard isValidTOMLBasicString(encodedValue) else {
                throw ConfigurationError.invalidFile
            }
            apiKey = try decodeTOMLBasicString(encodedValue)
        }

        guard let apiKey else {
            throw ConfigurationError.invalidFile
        }
        return apiKey
    }

    static func isValidTOMLBasicString(_ value: String) -> Bool {
        let bytes = Array(value.utf8)
        guard bytes.count >= 2, bytes.first == 0x22, bytes.last == 0x22 else {
            return false
        }

        var index = 1
        let end = bytes.count - 1
        while index < end {
            guard bytes[index] != 0x22 else { return false }
            guard bytes[index] != 0x00, bytes[index] >= 0x20 else {
                return false
            }
            if bytes[index] != 0x5C {
                index += 1
                continue
            }

            index += 1
            guard index < end else { return false }
            switch bytes[index] {
            case 0x22, 0x5C, 0x62, 0x66, 0x6E, 0x72, 0x74:
                index += 1
            case 0x75:
                guard index + 4 < end else { return false }
                for offset in 1...4 where !isHex(bytes[index + offset]) {
                    return false
                }
                index += 5
            case 0x55:
                guard index + 8 < end else { return false }
                for offset in 1...8 where !isHex(bytes[index + offset]) {
                    return false
                }
                index += 9
            default:
                return false
            }
        }
        return true
    }

    static func decodeTOMLBasicString(_ value: String) throws -> String {
        let bytes = Array(value.utf8)
        var normalized = [UInt8]()
        normalized.reserveCapacity(bytes.count)
        var index = 0

        while index < bytes.count {
            if bytes[index] == 0x5C,
               index + 1 < bytes.count,
               bytes[index + 1] == 0x55 {
                let digitsStart = index + 2
                let digitsEnd = digitsStart + 8
                guard digitsEnd <= bytes.count else {
                    throw ConfigurationError.invalidFile
                }

                var scalarValue: UInt32 = 0
                for digitIndex in digitsStart..<digitsEnd {
                    guard let digit = hexValue(bytes[digitIndex]) else {
                        throw ConfigurationError.invalidFile
                    }
                    scalarValue = scalarValue * 16 + digit
                }
                guard scalarValue <= 0x10FFFF,
                      !(0xD800...0xDFFF).contains(scalarValue) else {
                    throw ConfigurationError.invalidFile
                }
                appendJSONUnicodeEscapes(scalarValue, to: &normalized)
                index = digitsEnd
                continue
            }

            normalized.append(bytes[index])
            if bytes[index] == 0x5C, index + 1 < bytes.count {
                normalized.append(bytes[index + 1])
                index += 2
            } else {
                index += 1
            }
        }

        do {
            return try JSONDecoder().decode(
                String.self,
                from: Data(normalized)
            )
        } catch {
            throw ConfigurationError.invalidFile
        }
    }

    static func appendJSONUnicodeEscapes(
        _ value: UInt32,
        to output: inout [UInt8]
    ) {
        if value <= 0xFFFF {
            appendJSONUnicodeEscape(UInt16(value), to: &output)
            return
        }

        let adjusted = value - 0x10000
        let high = UInt16(0xD800 + (adjusted >> 10))
        let low = UInt16(0xDC00 + (adjusted & 0x3FF))
        appendJSONUnicodeEscape(high, to: &output)
        appendJSONUnicodeEscape(low, to: &output)
    }

    static func appendJSONUnicodeEscape(
        _ value: UInt16,
        to output: inout [UInt8]
    ) {
        output.append(contentsOf: [0x5C, 0x75])
        for shift in stride(from: 12, through: 0, by: -4) {
            let nibble = Int((value >> UInt16(shift)) & 0xF)
            output.append(hexDigits[nibble])
        }
    }

    static let hexDigits = Array("0123456789ABCDEF".utf8)

    static func hexValue(_ byte: UInt8) -> UInt32? {
        switch byte {
        case 0x30...0x39:
            return UInt32(byte - 0x30)
        case 0x41...0x46:
            return UInt32(byte - 0x41 + 10)
        case 0x61...0x66:
            return UInt32(byte - 0x61 + 10)
        default:
            return nil
        }
    }

    static func isHex(_ byte: UInt8) -> Bool {
        hexValue(byte) != nil
    }

    static func encode(_ apiKey: String) throws -> String {
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.withoutEscapingSlashes]
            let data = try encoder.encode(apiKey)
            guard let encoded = String(data: data, encoding: .utf8) else {
                throw ConfigurationError.invalidFile
            }
            return encoded
        } catch let error as ConfigurationError {
            throw error
        } catch {
            throw ConfigurationError.invalidFile
        }
    }
}
