import Foundation
import JSONRPC

// MARK: - Unix Domain Socket DataChannel for ChimeHQ/JSONRPC

/// Creates a DataChannel that communicates over a Unix domain socket.
/// Frames raw byte stream into individual JSON objects so JSONRPC library
/// receives one complete message per Data chunk.
func makeUnixSocketDataChannel(path: String) throws -> DataChannel {
    let fd = socket(AF_UNIX, SOCK_STREAM, 0)
    guard fd >= 0 else {
        throw UnixSocketError.socketCreationFailed(errno: errno)
    }

    var addr = sockaddr_un()
    addr.sun_family = sa_family_t(AF_UNIX)
    let pathBytes = path.utf8CString
    guard pathBytes.count <= MemoryLayout.size(ofValue: addr.sun_path) else {
        close(fd)
        throw UnixSocketError.pathTooLong(path)
    }

    withUnsafeMutablePointer(to: &addr.sun_path) { ptr in
        ptr.withMemoryRebound(to: CChar.self, capacity: pathBytes.count) { dest in
            for i in 0..<pathBytes.count {
                dest[i] = pathBytes[i]
            }
        }
    }

    let connectResult = withUnsafePointer(to: &addr) { ptr in
        ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockaddrPtr in
            connect(fd, sockaddrPtr, socklen_t(MemoryLayout<sockaddr_un>.size))
        }
    }

    guard connectResult == 0 else {
        let err = errno
        close(fd)
        throw UnixSocketError.connectFailed(path: path, errno: err)
    }

    // Prevent SIGPIPE on broken socket — deliver EPIPE error instead of crashing
    var noSigPipe: Int32 = 1
    setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &noSigPipe, socklen_t(MemoryLayout<Int32>.size))

    // Set non-blocking for async reads
    let flags = fcntl(fd, F_GETFL)
    _ = fcntl(fd, F_SETFL, flags | O_NONBLOCK)

    let writeHandle = FileHandle(fileDescriptor: fd, closeOnDealloc: false)

    let dataSequence = AsyncStream<Data> { continuation in
        let framer = JSONFramer(continuation: continuation)

        let source = DispatchSource.makeReadSource(fileDescriptor: fd, queue: .global(qos: .userInitiated))
        source.setEventHandler {
            let available = source.data
            guard available > 0 else { return }
            var buf = [UInt8](repeating: 0, count: Int(available))
            let n = read(fd, &buf, buf.count)
            if n <= 0 {
                // n == 0: EOF (remote closed), n < 0: read error
                if n < 0 {
                    NSLog("[UnixSocket] read error: %@", String(cString: strerror(errno)))
                }
                continuation.finish()
                source.cancel()
            } else {
                framer.feed(Data(buf[0..<n]))
            }
        }
        source.setCancelHandler {
            close(fd)
        }
        continuation.onTermination = { @Sendable _ in
            source.cancel()
        }
        source.resume()
    }

    let writeHandler: DataChannel.WriteHandler = { @Sendable data in
        do {
            try writeHandle.write(contentsOf: data)
        } catch {
            NSLog("[UnixSocket] write error: %@", "\(error)")
            throw error
        }
    }

    return DataChannel(writeHandler: writeHandler, dataSequence: dataSequence)
}

// MARK: - JSON Object Framer

/// Buffers raw bytes and emits complete JSON objects by tracking brace depth.
/// Handles strings (including escaped quotes) to avoid counting braces inside strings.
private final class JSONFramer: @unchecked Sendable {
    private let continuation: AsyncStream<Data>.Continuation
    private var buffer = Data()
    private var depth = 0
    private var inString = false
    private var escaped = false
    private var objectStart = -1

    init(continuation: AsyncStream<Data>.Continuation) {
        self.continuation = continuation
    }

    func feed(_ data: Data) {
        buffer.append(data)
        extractObjects()
    }

    private func extractObjects() {
        var i = 0
        while i < buffer.count {
            let byte = buffer[buffer.startIndex + i]

            if escaped {
                escaped = false
                i += 1
                continue
            }

            if byte == UInt8(ascii: "\\") && inString {
                escaped = true
                i += 1
                continue
            }

            if byte == UInt8(ascii: "\"") {
                inString.toggle()
                i += 1
                continue
            }

            if !inString {
                if byte == UInt8(ascii: "{") {
                    if depth == 0 {
                        objectStart = i
                    }
                    depth += 1
                } else if byte == UInt8(ascii: "}") {
                    depth -= 1
                    if depth == 0 && objectStart >= 0 {
                        let start = buffer.startIndex + objectStart
                        let end = buffer.startIndex + i + 1
                        let jsonData = buffer[start..<end]
                        continuation.yield(Data(jsonData))
                        objectStart = -1
                    }
                }
            }

            i += 1
        }

        // Remove consumed bytes
        if objectStart < 0 {
            // All complete objects consumed, find start of next potential object
            buffer.removeAll(keepingCapacity: true)
            depth = 0
            inString = false
            escaped = false
        } else if objectStart > 0 {
            buffer.removeSubrange(buffer.startIndex..<(buffer.startIndex + objectStart))
            objectStart = 0
        }
    }
}

enum UnixSocketError: Error, LocalizedError {
    case socketCreationFailed(errno: Int32)
    case pathTooLong(String)
    case connectFailed(path: String, errno: Int32)

    var errorDescription: String? {
        switch self {
        case .socketCreationFailed(let e):
            return "Failed to create socket: \(String(cString: strerror(e)))"
        case .pathTooLong(let p):
            return "Socket path too long: \(p)"
        case .connectFailed(let p, let e):
            return "Failed to connect to \(p): \(String(cString: strerror(e)))"
        }
    }
}
