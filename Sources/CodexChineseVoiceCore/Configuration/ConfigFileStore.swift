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
        let fileManager = FileManager.default
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(
            atPath: fileURL.path,
            isDirectory: &isDirectory
        ) else {
            return nil
        }
        guard !isDirectory.boolValue else {
            throw ConfigurationError.unreadableFile
        }

        let data: Data
        do {
            data = try Data(contentsOf: fileURL)
        } catch {
            throw ConfigurationError.unreadableFile
        }

        guard let contents = String(data: data, encoding: .utf8) else {
            throw ConfigurationError.invalidFile
        }
        return try Self.parse(contents)
    }

    public func saveAPIKey(_ apiKey: String) throws {
        let fileManager = FileManager.default
        let directoryURL = fileURL.deletingLastPathComponent()

        do {
            try fileManager.createDirectory(
                at: directoryURL,
                withIntermediateDirectories: true,
                attributes: [.posixPermissions: 0o700]
            )
            try fileManager.setAttributes(
                [.posixPermissions: 0o700],
                ofItemAtPath: directoryURL.path
            )

            let encodedKey = try Self.encode(apiKey)
            let contents = "\(Self.key) = \(encodedKey)\n"
            try Data(contents.utf8).write(to: fileURL, options: .atomic)
            try fileManager.setAttributes(
                [.posixPermissions: 0o600],
                ofItemAtPath: fileURL.path
            )
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

            guard let data = encodedValue.data(using: .utf8) else {
                throw ConfigurationError.invalidFile
            }
            do {
                apiKey = try JSONDecoder().decode(String.self, from: data)
            } catch {
                throw ConfigurationError.invalidFile
            }
        }

        guard let apiKey else {
            throw ConfigurationError.invalidFile
        }
        return apiKey
    }

    static func encode(_ apiKey: String) throws -> String {
        do {
            let data = try JSONEncoder().encode(apiKey)
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
