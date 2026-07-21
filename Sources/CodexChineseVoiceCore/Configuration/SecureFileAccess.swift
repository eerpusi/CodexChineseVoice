import Foundation
import Darwin

enum SecureFileAccessError: Error {
    case missing
    case unreadable
}

enum SecureFileAccess {
    static func read(from url: URL) throws -> Data? {
        let path = try SecurePath(url: url)
        let parentFD = try SecureFileAccessIO.openParent(
            directoryComponents: path.directoryComponents,
            create: false
        )
        defer { close(parentFD) }

        let fileFD: Int32
        do {
            fileFD = try SecureFileAccessIO.openFile(
                path.fileName,
                relativeTo: parentFD
            )
        } catch SecureFileAccessError.missing {
            return nil
        }
        defer { close(fileFD) }

        var info = stat()
        guard fstat(fileFD, &info) == 0 else {
            throw SecureFileAccessError.unreadable
        }
        guard info.st_mode & mode_t(S_IFMT) == mode_t(S_IFREG) else {
            throw SecureFileAccessError.unreadable
        }
        let permissions = info.st_mode & 0o777
        guard permissions & 0o077 == 0, permissions & 0o400 != 0 else {
            throw SecureFileAccessError.unreadable
        }
        return try SecureFileAccessIO.readAll(from: fileFD)
    }

    static func write(_ data: Data, to url: URL) throws {
        let path = try SecurePath(url: url)
        let parentFD = try SecureFileAccessIO.openParent(
            directoryComponents: path.directoryComponents,
            create: true
        )
        defer { close(parentFD) }

        let temporaryName = ".\(path.fileName).\(UUID().uuidString).tmp"
        let temporaryFD = try SecureFileAccessIO.openTemporaryFile(
            temporaryName,
            relativeTo: parentFD
        )
        var committed = false
        defer {
            close(temporaryFD)
            if !committed {
                SecureFileAccessIO.unlink(temporaryName, relativeTo: parentFD)
            }
        }

        try SecureFileAccessIO.writeAll(data, to: temporaryFD)
        guard fchmod(temporaryFD, mode_t(0o600)) == 0,
              fsync(temporaryFD) == 0 else {
            throw SecureFileAccessError.unreadable
        }
        try SecureFileAccessIO.rejectExistingSymlink(
            path.fileName,
            relativeTo: parentFD
        )
        guard SecureFileAccessIO.rename(
            temporaryName,
            to: path.fileName,
            relativeTo: parentFD
        ) == 0 else {
            throw SecureFileAccessError.unreadable
        }
        committed = true
    }
}

private extension SecureFileAccess {
    struct SecurePath {
        let directoryComponents: [String]
        let fileName: String

        init(url: URL) throws {
            let path = url.absoluteURL.standardizedFileURL.path
            guard path.hasPrefix("/") else {
                throw SecureFileAccessError.unreadable
            }
            var components = path.split(separator: "/").map(String.init)
            guard let fileName = components.popLast(), !fileName.isEmpty else {
                throw SecureFileAccessError.unreadable
            }
            if components.first == "var" {
                components.replaceSubrange(0..<1, with: ["private", "var"])
            } else if components.first == "tmp" {
                components.replaceSubrange(0..<1, with: ["private", "tmp"])
            } else if components.first == "etc" {
                components.replaceSubrange(0..<1, with: ["private", "etc"])
            }
            self.directoryComponents = components
            self.fileName = fileName
        }
    }

}
