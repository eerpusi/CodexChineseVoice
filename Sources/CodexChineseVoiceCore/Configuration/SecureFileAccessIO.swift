import Foundation
import Darwin

enum SecureFileAccessIO {
    static func openParent(
        directoryComponents: [String],
        create: Bool
    ) throws -> Int32 {
        let rootFD = open(
            "/",
            O_RDONLY | O_DIRECTORY | O_CLOEXEC | O_NOFOLLOW
        )
        guard rootFD >= 0 else {
            throw SecureFileAccessError.unreadable
        }

        var currentFD = rootFD
        do {
            for component in directoryComponents {
                let nextFD = try openDirectory(
                    component,
                    relativeTo: currentFD,
                    create: create
                )
                close(currentFD)
                currentFD = nextFD
            }
            return currentFD
        } catch {
            close(currentFD)
            throw error
        }
    }

    static func openDirectory(
        _ name: String,
        relativeTo parentFD: Int32,
        create: Bool
    ) throws -> Int32 {
        let flags = O_RDONLY | O_DIRECTORY | O_CLOEXEC | O_NOFOLLOW
        let existingFD = name.withCString { openat(parentFD, $0, flags) }
        if existingFD >= 0 {
            return existingFD
        }

        let openError = errno
        guard create, openError == ENOENT else {
            throw openError == ENOENT
                ? SecureFileAccessError.missing
                : SecureFileAccessError.unreadable
        }

        let mkdirResult = name.withCString {
            mkdirat(parentFD, $0, mode_t(0o700))
        }
        let wasCreated: Bool
        if mkdirResult == 0 {
            wasCreated = true
        } else {
            let mkdirError = errno
            guard mkdirError == EEXIST else {
                throw SecureFileAccessError.unreadable
            }
            wasCreated = false
        }

        let directoryFD = name.withCString { openat(parentFD, $0, flags) }
        guard directoryFD >= 0 else {
            throw SecureFileAccessError.unreadable
        }
        if wasCreated, fchmod(directoryFD, mode_t(0o700)) != 0 {
            close(directoryFD)
            throw SecureFileAccessError.unreadable
        }
        return directoryFD
    }

    static func openFile(_ name: String, relativeTo parentFD: Int32) throws -> Int32 {
        let flags = O_RDONLY | O_CLOEXEC | O_NOFOLLOW
        let fileFD = name.withCString { openat(parentFD, $0, flags) }
        guard fileFD >= 0 else {
            throw errno == ENOENT
                ? SecureFileAccessError.missing
                : SecureFileAccessError.unreadable
        }
        return fileFD
    }

    static func openTemporaryFile(
        _ name: String,
        relativeTo parentFD: Int32
    ) throws -> Int32 {
        let flags = O_WRONLY | O_CREAT | O_EXCL | O_CLOEXEC | O_NOFOLLOW
        let fileFD = name.withCString {
            openat(parentFD, $0, flags, mode_t(0o600))
        }
        guard fileFD >= 0 else {
            throw SecureFileAccessError.unreadable
        }
        return fileFD
    }

    static func openLockFile(
        _ name: String,
        relativeTo parentFD: Int32
    ) throws -> Int32 {
        let flags = O_RDWR | O_CLOEXEC | O_NOFOLLOW
        var created = false
        var fileFD = name.withCString {
            openat(parentFD, $0, flags | O_CREAT | O_EXCL, mode_t(0o600))
        }
        if fileFD >= 0 {
            created = true
        } else {
            guard errno == EEXIST else {
                throw SecureFileAccessError.unreadable
            }
            fileFD = name.withCString { openat(parentFD, $0, flags) }
        }
        guard fileFD >= 0 else {
            throw SecureFileAccessError.unreadable
        }

        var info = stat()
        let valid = fstat(fileFD, &info) == 0
            && info.st_mode & mode_t(S_IFMT) == mode_t(S_IFREG)
        guard valid else {
            close(fileFD)
            throw SecureFileAccessError.unreadable
        }
        if created, fchmod(fileFD, mode_t(0o600)) != 0 {
            close(fileFD)
            throw SecureFileAccessError.unreadable
        }
        guard info.st_mode & 0o777 == 0o600 || created else {
            close(fileFD)
            throw SecureFileAccessError.unreadable
        }
        return fileFD
    }

    static func lockExclusive(_ fileFD: Int32) throws {
        while flock(fileFD, LOCK_EX) != 0 {
            if errno == EINTR { continue }
            throw SecureFileAccessError.unreadable
        }
    }

    static func unlock(_ fileFD: Int32) {
        while flock(fileFD, LOCK_UN) != 0 {
            if errno == EINTR { continue }
            return
        }
    }

    static func readAll(from fileFD: Int32) throws -> Data {
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 64 * 1024)

        while true {
            let count = buffer.withUnsafeMutableBytes { bytes -> Int in
                guard let baseAddress = bytes.baseAddress else { return 0 }
                return Darwin.read(fileFD, baseAddress, bytes.count)
            }
            if count == 0 {
                return data
            }
            if count < 0 {
                if errno == EINTR { continue }
                throw SecureFileAccessError.unreadable
            }
            data.append(contentsOf: buffer[0..<count])
        }
    }

    static func writeAll(_ data: Data, to fileFD: Int32) throws {
        try data.withUnsafeBytes { bytes in
            guard let baseAddress = bytes.baseAddress else { return }
            var offset = 0
            while offset < bytes.count {
                let count = Darwin.write(
                    fileFD,
                    baseAddress.advanced(by: offset),
                    bytes.count - offset
                )
                if count < 0 {
                    if errno == EINTR { continue }
                    throw SecureFileAccessError.unreadable
                }
                guard count > 0 else {
                    throw SecureFileAccessError.unreadable
                }
                offset += count
            }
        }
    }

    static func rejectExistingSymlink(
        _ name: String,
        relativeTo parentFD: Int32
    ) throws {
        var info = stat()
        let result = name.withCString {
            fstatat(parentFD, $0, &info, AT_SYMLINK_NOFOLLOW)
        }
        if result == 0 {
            if info.st_mode & mode_t(S_IFMT) == mode_t(S_IFLNK) {
                throw SecureFileAccessError.unreadable
            }
            return
        }
        guard errno == ENOENT else {
            throw SecureFileAccessError.unreadable
        }
    }

    @discardableResult
    static func rename(
        _ oldName: String,
        to newName: String,
        relativeTo parentFD: Int32
    ) -> Int32 {
        oldName.withCString { oldPointer in
            newName.withCString { newPointer in
                renameat(parentFD, oldPointer, parentFD, newPointer)
            }
        }
    }

    @discardableResult
    static func unlink(_ name: String, relativeTo parentFD: Int32) -> Int32 {
        name.withCString { unlinkat(parentFD, $0, 0) }
    }
}
