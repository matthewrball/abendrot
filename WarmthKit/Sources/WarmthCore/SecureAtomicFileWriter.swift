import Darwin
import Foundation

public enum SecureAtomicFileWriter {
    public static let maxSnapshotBytes = 1_048_576

    public static func readRegularFileIfExists(from url: URL) throws -> Data? {
        let directory = url.deletingLastPathComponent()
        let fileName = url.lastPathComponent
        guard !fileName.isEmpty, fileName == (fileName as NSString).lastPathComponent else {
            throw POSIXError(.EINVAL)
        }

        var dirInfo = stat()
        if lstat(directory.path, &dirInfo) != 0 {
            if errno == ENOENT { return nil }
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
        }

        let dirFD = open(directory.path, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
        guard dirFD >= 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
        defer { close(dirFD) }

        let fd = openat(dirFD, fileName, O_RDONLY | O_NOFOLLOW | O_CLOEXEC)
        guard fd >= 0 else {
            if errno == ENOENT { return nil }
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
        }
        defer { close(fd) }

        var fileInfo = stat()
        guard fstat(fd, &fileInfo) == 0 else {
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
        }
        guard (fileInfo.st_mode & S_IFMT) == S_IFREG else { throw POSIXError(.EFTYPE) }
        guard fileInfo.st_size <= maxSnapshotBytes else { throw POSIXError(.EFBIG) }

        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 16 * 1024)
        while true {
            let count = Darwin.read(fd, &buffer, buffer.count)
            if count > 0 {
                guard data.count + count <= maxSnapshotBytes else { throw POSIXError(.EFBIG) }
                data.append(buffer, count: count)
            } else if count == 0 {
                return data
            } else if errno == EINTR {
                continue
            } else {
                throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
            }
        }
    }

    public static func write(_ data: Data, to url: URL) throws {
        guard data.count <= maxSnapshotBytes else { throw POSIXError(.EFBIG) }
        let directory = url.deletingLastPathComponent()
        let fileName = url.lastPathComponent
        guard !fileName.isEmpty, fileName == (fileName as NSString).lastPathComponent else {
            throw POSIXError(.EINVAL)
        }

        try ensureDirectoryExists(directory)

        let dirFD = open(directory.path, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
        guard dirFD >= 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
        defer { close(dirFD) }

        var dirStat = stat()
        guard fstat(dirFD, &dirStat) == 0 else {
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
        }
        guard (dirStat.st_mode & S_IFMT) == S_IFDIR else { throw POSIXError(.ENOTDIR) }
        guard fchmod(dirFD, 0o700) == 0 else {
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
        }

        try rejectUnsafeExistingTarget(fileName, dirFD: dirFD)

        let tempName = ".\(fileName).\(UUID().uuidString).tmp"
        let tempFD = openat(dirFD, tempName, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC, 0o600)
        guard tempFD >= 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
        var tempOpen = true
        defer {
            if tempOpen { close(tempFD) }
            unlinkat(dirFD, tempName, 0)
        }

        do {
            guard fchmod(tempFD, 0o600) == 0 else {
                throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
            }
            try writeAll(data, to: tempFD)
            guard fsync(tempFD) == 0 else {
                throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
            }
            guard close(tempFD) == 0 else {
                tempOpen = false
                throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
            }
            tempOpen = false

            try rejectUnsafeExistingTarget(fileName, dirFD: dirFD)
            guard renameat(dirFD, tempName, dirFD, fileName) == 0 else {
                throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
            }
            guard fsync(dirFD) == 0 else {
                throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
            }
        } catch {
            throw error
        }
    }

    private static func ensureDirectoryExists(_ directory: URL) throws {
        var info = stat()
        if lstat(directory.path, &info) == 0 {
            guard (info.st_mode & S_IFMT) == S_IFDIR else { throw POSIXError(.ENOTDIR) }
            return
        }
        guard errno == ENOENT else {
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
        }
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
    }

    private static func rejectUnsafeExistingTarget(_ fileName: String, dirFD: Int32) throws {
        var info = stat()
        if fstatat(dirFD, fileName, &info, AT_SYMLINK_NOFOLLOW) == 0 {
            guard (info.st_mode & S_IFMT) == S_IFREG else { throw POSIXError(.EFTYPE) }
            return
        }
        guard errno == ENOENT else {
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
        }
    }

    private static func writeAll(_ data: Data, to fd: Int32) throws {
        try data.withUnsafeBytes { buffer in
            guard let base = buffer.baseAddress else { return }
            var offset = 0
            while offset < buffer.count {
                let written = Darwin.write(fd, base.advanced(by: offset), buffer.count - offset)
                if written > 0 {
                    offset += written
                } else if written == -1, errno == EINTR {
                    continue
                } else {
                    throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
                }
            }
        }
    }
}
