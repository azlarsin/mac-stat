import Foundation
import Darwin

enum SettingValue: Codable, Equatable {
    case bool(Bool)
    case items([String])
    case text(String)

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let value = try? container.decode(Bool.self) { self = .bool(value) }
        else if let value = try? container.decode([String].self) { self = .items(value) }
        else { self = .text(try container.decode(String.self)) }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .bool(let value): try container.encode(value)
        case .items(let value): try container.encode(value)
        case .text(let value): try container.encode(value)
        }
    }

    var display: String {
        switch self {
        case .bool(let value): return value ? "true" : "false"
        case .items(let value): return value.joined(separator: ",")
        case .text(let value): return value
        }
    }
}

struct SettingsRequest: Codable {
    let action: String
    var key: String?
    var value: String?
}

struct SettingsResponse: Codable {
    var settings: [String: SettingValue] = [:]
    var error: String?
}

struct ControlError: LocalizedError {
    let message: String
    var errorDescription: String? { message }
    init(_ message: String) { self.message = message }
}

/// A per-user local socket also works across the desktop and SSH sessions.
/// All setting access happens on the app's main queue, through AppSettings.
final class SettingsControlServer {
    static let directory = "/tmp/com.azlar.macstat-\(geteuid())"
    private let directory: String
    private let queue = DispatchQueue(label: "com.azlar.macstat.cli.accept")
    private var source: DispatchSourceRead?

    init(directory: String = SettingsControlServer.directory) { self.directory = directory }

    /// Returns false if another instance already owns the endpoint.
    func start(handler: @escaping (SettingsRequest) -> SettingsResponse) throws -> Bool {
        guard source == nil else { return true }
        if mkdir(directory, 0o700) != 0 && errno != EEXIST { throw SocketIO.failure("Create CLI directory") }
        var info = stat()
        guard lstat(directory, &info) == 0, info.st_uid == geteuid(),
              info.st_mode & S_IFMT == S_IFDIR, info.st_mode & 0o077 == 0 else {
            throw ControlError("CLI directory must be owned by this user with permissions 0700: \(directory)")
        }
        let lock = open(directory + "/lock", O_CREAT | O_RDWR | O_NOFOLLOW | O_CLOEXEC, 0o600)
        guard lock >= 0 else { throw SocketIO.failure("Open CLI lock") }
        guard flock(lock, LOCK_EX | LOCK_NB) == 0 else {
            let alreadyRunning = errno == EWOULDBLOCK
            close(lock)
            if alreadyRunning { return false }
            throw SocketIO.failure("Lock CLI endpoint")
        }
        do {
            let fd = try SocketIO.makeSocket()
            var ownedFD = fd
            defer { if ownedFD >= 0 { close(ownedFD) } }
            let path = directory + "/control.sock"
            // The lock prevents a second instance from removing a live socket.
            unlink(path)
            let bound = try SocketIO.withAddress(path) { address, length in Darwin.bind(fd, address, length) }
            guard bound == 0, chmod(path, 0o600) == 0, listen(fd, 16) == 0,
                  fcntl(fd, F_SETFL, O_NONBLOCK) == 0 else { throw SocketIO.failure("Listen for CLI commands") }
            let listener = DispatchSource.makeReadSource(fileDescriptor: fd, queue: queue)
            listener.setEventHandler {
                let client = accept(fd, nil, nil)
                guard client >= 0 else { return }
                DispatchQueue.global(qos: .userInitiated).async {
                    do {
                        try SocketIO.configure(client)
                        var uid: uid_t = 0
                        var gid: gid_t = 0
                        guard getpeereid(client, &uid, &gid) == 0, uid == geteuid() else {
                            throw ControlError("CLI peer must be the same user as MacStat.")
                        }
                        let request = try JSONDecoder().decode(SettingsRequest.self, from: SocketIO.readLine(client))
                        DispatchQueue.main.async {
                            let response = handler(request)
                            DispatchQueue.global(qos: .userInitiated).async {
                                defer { close(client) }
                                try? SocketIO.write(response, to: client)
                            }
                        }
                    } catch {
                        try? SocketIO.write(SettingsResponse(error: error.localizedDescription), to: client)
                        close(client)
                    }
                }
            }
            // Release the lock only after the listener has actually closed.
            listener.setCancelHandler {
                close(fd)
                unlink(path)
                close(lock)
            }
            source = listener
            ownedFD = -1
            listener.resume()
            return true
        } catch {
            close(lock)
            throw error
        }
    }

    func stop() {
        source?.cancel()
        source = nil
    }

    deinit { stop() }
}

enum SettingsControlClient {
    static func send(_ request: SettingsRequest,
                     directory: String = SettingsControlServer.directory) throws -> SettingsResponse {
        let fd = try SocketIO.makeSocket()
        defer { close(fd) }
        let connected = try SocketIO.withAddress(directory + "/control.sock") {
            address, length in Darwin.connect(fd, address, length)
        }
        guard connected == 0 else {
            throw ControlError("Cannot connect to MacStat. Start a version with CLI support in your desktop session, then retry (open -a MacStat). Run the command as the same user, without sudo.")
        }
        var uid: uid_t = 0
        var gid: gid_t = 0
        guard getpeereid(fd, &uid, &gid) == 0, uid == geteuid() else {
            throw ControlError("MacStat must run as the same user as this command.")
        }
        try SocketIO.write(request, to: fd)
        return try JSONDecoder().decode(SettingsResponse.self, from: SocketIO.readLine(fd))
    }
}

private enum SocketIO {
    static let maximumMessageSize = 65_536

    static func failure(_ operation: String) -> ControlError {
        ControlError("\(operation): \(String(cString: strerror(errno)))")
    }

    static func makeSocket() throws -> Int32 {
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { throw failure("Create CLI socket") }
        do { try configure(fd) }
        catch { close(fd); throw error }
        return fd
    }

    static func configure(_ fd: Int32) throws {
        var yes: Int32 = 1
        var timeout = timeval(tv_sec: 5, tv_usec: 0)
        let flags = fcntl(fd, F_GETFL)
        guard flags >= 0, fcntl(fd, F_SETFL, flags & ~O_NONBLOCK) == 0,
              fcntl(fd, F_SETFD, FD_CLOEXEC) == 0,
              setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &yes, socklen_t(MemoryLayout.size(ofValue: yes))) == 0,
              setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &timeout, socklen_t(MemoryLayout.size(ofValue: timeout))) == 0,
              setsockopt(fd, SOL_SOCKET, SO_SNDTIMEO, &timeout, socklen_t(MemoryLayout.size(ofValue: timeout))) == 0
        else { throw failure("Configure CLI socket") }
    }

    static func withAddress<T>(_ path: String, _ body: (UnsafePointer<sockaddr>, socklen_t) -> T) throws -> T {
        var address = sockaddr_un()
        let bytes = Array(path.utf8CString)
        guard bytes.count <= MemoryLayout.size(ofValue: address.sun_path) else {
            throw ControlError("CLI socket path is too long.")
        }
        address.sun_family = sa_family_t(AF_UNIX)
        address.sun_len = UInt8(MemoryLayout<sockaddr_un>.size)
        withUnsafeMutableBytes(of: &address.sun_path) { target in
            target.copyBytes(from: bytes.map { UInt8(bitPattern: $0) })
        }
        return withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                body($0, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
    }

    static func readLine(_ fd: Int32) throws -> Data {
        var result = Data()
        var buffer = [UInt8](repeating: 0, count: 4096)
        while true {
            let count = Darwin.read(fd, &buffer, buffer.count)
            if count < 0 {
                if errno == EINTR { continue }
                throw failure("Read CLI message (5 second timeout)")
            }
            guard count > 0 else { throw ControlError("MacStat closed the CLI connection before replying.") }
            let chunk = buffer.prefix(count)
            if let end = chunk.firstIndex(of: 10) {
                result.append(contentsOf: chunk[..<end])
                guard result.count <= maximumMessageSize else { throw ControlError("CLI message is too large.") }
                return result
            }
            result.append(contentsOf: chunk)
            guard result.count <= maximumMessageSize else { throw ControlError("CLI message is too large.") }
        }
    }

    static func write<T: Encodable>(_ value: T, to fd: Int32) throws {
        var data = try JSONEncoder().encode(value)
        guard data.count <= maximumMessageSize else { throw ControlError("CLI message is too large.") }
        data.append(10)
        try data.withUnsafeBytes { bytes in
            var offset = 0
            while offset < bytes.count {
                let count = Darwin.write(fd, bytes.baseAddress!.advanced(by: offset), bytes.count - offset)
                if count < 0 {
                    if errno == EINTR { continue }
                    throw failure("Write CLI message (5 second timeout)")
                }
                guard count > 0 else { throw ControlError("CLI connection stopped accepting data.") }
                offset += count
            }
        }
    }
}
