import Darwin
import Foundation

// MARK: - Socket path
//
// Live apply is a Unix-domain socket next to `state.json`, not a distributed notification.
// `DistributedNotificationCenter` delivers `NSDistributedNotificationPostToAllSessions` into
// other GUI sessions, and the observer cannot filter that. The socket's peer uid must equal
// `getuid()` before a frame is decoded.

public enum ControlSocket {
    public static let fileName = "control.sock"

    public static func url(directory: URL = ControlStateSnapshot.directoryURL()) -> URL {
        directory.appendingPathComponent(fileName)
    }

    /// `sockaddr_un.sun_path` holds 104 bytes, including the terminating NUL.
    public static func pathFits(_ path: String) -> Bool {
        path.utf8.count + 1 <= 104
    }
}

public enum ControlPeer {
    /// True only for this process's own uid. `allows(0)` is therefore false for a non-root app.
    public static func allows(_ uid: uid_t) -> Bool {
        uid == getuid()
    }
}

// MARK: - Frame
//
// 4-byte big-endian length, then one JSON `ControlMessage`. Length 0 or above
// `ControlMessage.maximumUserInfoPayloadBytes` is rejected. One frame per connection.

enum ControlFrame {
    static func encode(_ message: ControlMessage) -> Data? {
        guard let payload = try? JSONEncoder().encode(message),
              payload.count > 0,
              payload.count <= ControlMessage.maximumUserInfoPayloadBytes
        else { return nil }
        var framed = Data(capacity: 4 + payload.count)
        var length = UInt32(payload.count).bigEndian
        framed.append(Data(bytes: &length, count: 4))
        framed.append(payload)
        return framed
    }

    static func isCanonicalRequestID(_ raw: String) -> Bool {
        UUID(uuidString: raw)?.uuidString == raw
    }
}

// MARK: - Server

public final class ControlServer: @unchecked Sendable {
    private let directory: URL
    private let onMessage: @Sendable (ControlMessage) -> Void
    private let peerAllowed: @Sendable (uid_t) -> Bool
    private let lock = NSLock()
    private let queue = DispatchQueue(label: "app.abendrot.control-socket", qos: .utility)
    private var listenFD: Int32 = -1
    private var boundPath: String?

    public init(
        directory: URL = ControlStateSnapshot.directoryURL(),
        onMessage: @escaping @Sendable (ControlMessage) -> Void,
        peerAllowed: @escaping @Sendable (uid_t) -> Bool = { ControlPeer.allows($0) }
    ) {
        self.directory = directory
        self.onMessage = onMessage
        self.peerAllowed = peerAllowed
    }

    /// Bind and accept. False if the directory or socket path is a symlink, the directory
    /// cannot be locked down, or bind/listen fails. Does not chmod or unlink a symlink.
    @discardableResult
    public func start() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        if listenFD >= 0 { return true }
        guard prepareDirectory() else { return false }

        let path = ControlSocket.url(directory: directory).path
        guard ControlSocket.pathFits(path) else {
            fputs("abendrot: control socket path exceeds the system limit; live apply is unavailable\n", stderr)
            return false
        }
        if !prepareSocketPath(path) {
            return false
        }
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { return false }
        setCloseOnExec(fd)
        setNoSigPipe(fd)

        guard bindUnix(fd, path: path) else {
            close(fd)
            return false
        }
        if chmod(path, 0o600) != 0 {
            close(fd)
            unlink(path)
            return false
        }
        guard listen(fd, 16) == 0 else {
            close(fd)
            unlink(path)
            return false
        }

        listenFD = fd
        boundPath = path
        queue.async { [weak self] in
            self?.acceptLoop(fd)
        }
        return true
    }

    public func stop() {
        lock.lock()
        let fd = listenFD
        let path = boundPath
        listenFD = -1
        boundPath = nil
        lock.unlock()
        if fd >= 0 {
            close(fd)
        }
        if let path {
            unlink(path)
        }
    }

    /// Create the directory at mode 0700. A symlink is refused before `chmod`, so a link
    /// cannot be followed into another user's directory.
    private func prepareDirectory() -> Bool {
        let dirPath = directory.path
        var info = stat()
        if lstat(dirPath, &info) == 0 {
            if (info.st_mode & S_IFMT) == S_IFLNK {
                return false
            }
        } else if errno != ENOENT {
            return false
        }
        if mkdir(dirPath, 0o700) != 0 && errno != EEXIST {
            return false
        }
        if lstat(dirPath, &info) != 0 || (info.st_mode & S_IFMT) == S_IFLNK {
            return false
        }
        return chmod(dirPath, 0o700) == 0
    }

    private func prepareSocketPath(_ path: String) -> Bool {
        var info = stat()
        if lstat(path, &info) != 0 {
            return errno == ENOENT
        }
        if (info.st_mode & S_IFMT) == S_IFLNK {
            return false
        }
        if (info.st_mode & S_IFMT) == S_IFSOCK {
            return unlink(path) == 0
        }
        return false
    }

    private func acceptLoop(_ fd: Int32) {
        while true {
            let client = accept(fd, nil, nil)
            if client < 0 {
                if errno == EINTR { continue }
                break
            }
            setCloseOnExec(client)
            setNoSigPipe(client)
            setReceiveTimeout(client, seconds: 2)
            handle(client)
            close(client)
        }
    }

    private func handle(_ client: Int32) {
        var uid: uid_t = 0
        var gid: gid_t = 0
        if getpeereid(client, &uid, &gid) != 0 || !peerAllowed(uid) {
            return
        }
        guard let header = readExact(client, count: 4), header.count == 4 else { return }
        let bytes = [UInt8](header)
        let length = (UInt32(bytes[0]) << 24) | (UInt32(bytes[1]) << 16) | (UInt32(bytes[2]) << 8) | UInt32(bytes[3])
        guard length > 0, length <= UInt32(ControlMessage.maximumUserInfoPayloadBytes) else {
            return
        }
        guard let payload = readExact(client, count: Int(length)),
              let message = try? JSONDecoder().decode(ControlMessage.self, from: payload),
              message.schemaVersion == AbendrotControl.schemaVersion,
              ControlFrame.isCanonicalRequestID(message.requestID)
        else { return }
        onMessage(message)
    }
}

// MARK: - Client

public enum ControlClient {
    /// Write one frame and close. False if connect or write fails. Never throws.
    public static func send(
        _ message: ControlMessage,
        directory: URL = ControlStateSnapshot.directoryURL()
    ) -> Bool {
        guard let framed = ControlFrame.encode(message) else { return false }
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { return false }
        defer { close(fd) }
        setCloseOnExec(fd)
        setNoSigPipe(fd)
        let path = ControlSocket.url(directory: directory).path
        guard connectUnix(fd, path: path) else { return false }
        return writeAll(fd, framed)
    }
}

// MARK: - POSIX helpers

private func setCloseOnExec(_ fd: Int32) {
    _ = fcntl(fd, F_SETFD, FD_CLOEXEC)
}

private func setNoSigPipe(_ fd: Int32) {
    var one: Int32 = 1
    _ = setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &one, socklen_t(MemoryLayout<Int32>.size))
}

private func setReceiveTimeout(_ fd: Int32, seconds: Int) {
    var timeout = timeval(tv_sec: seconds, tv_usec: 0)
    _ = setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))
}

private func bindUnix(_ fd: Int32, path: String) -> Bool {
    unixAddress(path).map { addr in
        var addr = addr
        return withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                Darwin.bind(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size)) == 0
            }
        }
    } ?? false
}

private func connectUnix(_ fd: Int32, path: String) -> Bool {
    unixAddress(path).map { addr in
        var addr = addr
        return withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                Darwin.connect(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size)) == 0
            }
        }
    } ?? false
}

private func unixAddress(_ path: String) -> sockaddr_un? {
    var addr = sockaddr_un()
    addr.sun_family = sa_family_t(AF_UNIX)
    let bytes = Array(path.utf8) + [0]
    guard bytes.count <= MemoryLayout.size(ofValue: addr.sun_path) else { return nil }
    withUnsafeMutableBytes(of: &addr.sun_path) { dest in
        bytes.withUnsafeBytes { src in
            dest.copyMemory(from: src)
        }
    }
    return addr
}

private func readExact(_ fd: Int32, count: Int) -> Data? {
    var data = Data(count: count)
    var got = 0
    while got < count {
        let n = data.withUnsafeMutableBytes { buf -> ssize_t in
            guard let base = buf.baseAddress else { return -1 }
            return Darwin.read(fd, base.advanced(by: got), count - got)
        }
        if n == 0 { return nil }
        if n < 0 {
            if errno == EINTR { continue }
            return nil
        }
        got += n
    }
    return data
}

private func writeAll(_ fd: Int32, _ data: Data) -> Bool {
    var sent = 0
    let total = data.count
    while sent < total {
        let n = data.withUnsafeBytes { buf -> ssize_t in
            guard let base = buf.baseAddress else { return -1 }
            return Darwin.write(fd, base.advanced(by: sent), total - sent)
        }
        if n < 0 {
            if errno == EINTR { continue }
            return false
        }
        if n == 0 { return false }
        sent += n
    }
    return true
}
