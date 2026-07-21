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
        let encodedKey = try TOMLBasicStringCodec.encode(apiKey)
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
            apiKey = try TOMLBasicStringCodec.decode(encodedValue)
        }

        guard let apiKey else {
            throw ConfigurationError.invalidFile
        }
        return apiKey
    }
}
