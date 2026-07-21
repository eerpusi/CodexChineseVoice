import Foundation
import Darwin

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
        try Self.rejectSymbolicLinks(in: fileURL)

        let data: Data
        do {
            data = try Data(contentsOf: fileURL)
        } catch {
            if Self.isMissingFileError(error) {
                return nil
            }
            throw ConfigurationError.unreadableFile
        }

        guard let contents = String(data: data, encoding: .utf8) else {
            throw ConfigurationError.invalidFile
        }
        return try Self.parse(contents)
    }

    public func saveAPIKey(_ apiKey: String) throws {
        let fileManager = FileManager.default

        do {
            let directoryURL = fileURL.deletingLastPathComponent()
            try Self.rejectSymbolicLinks(in: fileURL)
            let directoryWasCreated = try Self.prepareDirectory(at: directoryURL)
            try Self.rejectSymbolicLinks(in: fileURL)
            if directoryWasCreated {
                try fileManager.setAttributes(
                    [.posixPermissions: 0o700],
                    ofItemAtPath: directoryURL.path
                )
            }

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
    static func prepareDirectory(at url: URL) throws -> Bool {
        let path = url.absoluteURL.standardizedFileURL
        var current = URL(fileURLWithPath: "/")
        var targetWasCreated = false

        for component in path.pathComponents.dropFirst() {
            current.appendPathComponent(component)
            var info = stat()
            if lstat(current.path, &info) == 0 {
                try validateExistingDirectory(info, at: current)
                continue
            }

            let errorNumber = errno
            guard errorNumber == ENOENT else {
                throw ConfigurationError.unreadableFile
            }
            guard mkdir(current.path, mode_t(0o700)) == 0 else {
                if errno != EEXIST {
                    throw ConfigurationError.unreadableFile
                }
                var racedInfo = stat()
                guard lstat(current.path, &racedInfo) == 0 else {
                    throw ConfigurationError.unreadableFile
                }
                try validateExistingDirectory(racedInfo, at: current)
                continue
            }

            targetWasCreated = current.path == path.path
            guard chmod(current.path, mode_t(0o700)) == 0 else {
                throw ConfigurationError.unreadableFile
            }
        }
        return targetWasCreated
    }

    static func rejectSymbolicLinks(in url: URL) throws {
        let path = url.absoluteURL.standardizedFileURL
        var current = URL(fileURLWithPath: "/")

        for component in path.pathComponents.dropFirst() {
            current.appendPathComponent(component)
            var info = stat()
            if lstat(current.path, &info) == 0 {
                try rejectCustomSymbolicLink(info, at: current)
                continue
            }

            let errorNumber = errno
            if errorNumber != ENOENT {
                throw ConfigurationError.unreadableFile
            }
        }
    }

    static func validateExistingDirectory(_ info: stat, at url: URL) throws {
        let mode = info.st_mode & mode_t(S_IFMT)
        if mode == mode_t(S_IFLNK) {
            guard isAllowedSystemAlias(at: url) else {
                throw ConfigurationError.unreadableFile
            }
            return
        }
        guard mode == mode_t(S_IFDIR) else {
            throw ConfigurationError.unreadableFile
        }
    }

    static func rejectCustomSymbolicLink(_ info: stat, at url: URL) throws {
        let mode = info.st_mode & mode_t(S_IFMT)
        if mode == mode_t(S_IFLNK), !isAllowedSystemAlias(at: url) {
            throw ConfigurationError.unreadableFile
        }
    }

    static func isAllowedSystemAlias(at url: URL) -> Bool {
        let expectedDestinations: [String: Set<String>] = [
            "/var": ["private/var", "/private/var"],
            "/tmp": ["private/tmp", "/private/tmp"],
            "/etc": ["private/etc", "/private/etc"],
        ]
        guard let destination = try? FileManager.default
            .destinationOfSymbolicLink(atPath: url.path) else {
            return false
        }
        return expectedDestinations[url.path]?.contains(destination) == true
    }

    static func isMissingFileError(_ error: Error) -> Bool {
        let nsError = error as NSError
        if nsError.domain == NSCocoaErrorDomain {
            return nsError.code == NSFileReadNoSuchFileError
                || nsError.code == NSFileNoSuchFileError
        }
        return nsError.domain == NSPOSIXErrorDomain && nsError.code == ENOENT
    }

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
