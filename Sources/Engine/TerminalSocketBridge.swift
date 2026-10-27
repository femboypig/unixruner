import Foundation
import Darwin

public final class TerminalSocketBridge {
    private var clientSocket: Int32 = -1
    private let readQueue = DispatchQueue(label: "org.unixruner.socket.read", qos: .userInteractive)
    private var readSource: DispatchSourceRead?
    private var isConnected = false
    private var isCancelled = false

    public var onOutput: ((Data) -> Void)?

    public init() {}

    deinit {
        disconnect()
    }

    public static func findAvailablePort() -> UInt16 {
        let sock = socket(AF_INET, SOCK_STREAM, 0)
        guard sock >= 0 else { return 4444 }
        defer { close(sock) }

        var addr = sockaddr_in()
        addr.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_port = 0
        addr.sin_addr.s_addr = inet_addr("127.0.0.1")

        let bindResult = withUnsafePointer(to: &addr) { ptr in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { saPtr in
                bind(sock, saPtr, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }

        if bindResult == 0 {
            var len = socklen_t(MemoryLayout<sockaddr_in>.size)
            if getsockname(sock, withUnsafeMutablePointer(to: &addr, { ptr in
                ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { $0 }
            }), &len) == 0 {
                let port = UInt16(bigEndian: addr.sin_port)
                if port > 1024 {
                    return port
                }
            }
        }
        return 4444
    }

    public func connect(port: UInt16, maxAttempts: Int = 300, intervalSeconds: TimeInterval = 0.05, completion: @escaping (Bool) -> Void) {
        isCancelled = false
        DispatchQueue.global(qos: .userInteractive).async { [weak self] in
            guard let self = self else { return }

            var sock: Int32 = -1
            for _ in 0..<maxAttempts {
                if self.isCancelled { break }

                sock = socket(AF_INET, SOCK_STREAM, 0)
                if sock >= 0 {
                    var addr = sockaddr_in()
                    addr.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
                    addr.sin_family = sa_family_t(AF_INET)
                    addr.sin_port = port.bigEndian
                    addr.sin_addr.s_addr = inet_addr("127.0.0.1")

                    let res = withUnsafePointer(to: &addr) { ptr in
                        ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { saPtr in
                            Darwin.connect(sock, saPtr, socklen_t(MemoryLayout<sockaddr_in>.size))
                        }
                    }

                    if res == 0 {
                        // Connection established with QEMU serial socket
                        self.clientSocket = sock
                        self.isConnected = true
                        self.startReading(from: sock)
                        DispatchQueue.main.async { completion(true) }
                        return
                    }

                    close(sock)
                    sock = -1
                }

                Thread.sleep(forTimeInterval: intervalSeconds)
            }

            DispatchQueue.main.async { completion(false) }
        }
    }

    public func writeInput(_ data: Data) {
        guard clientSocket >= 0, isConnected else { return }
        data.withUnsafeBytes { raw in
            guard let base = raw.baseAddress else { return }
            _ = send(clientSocket, base, data.count, 0)
        }
    }

    public func disconnect() {
        isCancelled = true
        isConnected = false

        if let source = readSource {
            source.cancel()
            readSource = nil
        } else if clientSocket >= 0 {
            close(clientSocket)
            clientSocket = -1
        }
    }

    private func startReading(from socket: Int32) {
        let source = DispatchSource.makeReadSource(fileDescriptor: socket, queue: readQueue)
        source.setEventHandler { [weak self] in
            guard let self = self else { return }
            var buffer = [UInt8](repeating: 0, count: 4096)
            let bytesRead = recv(socket, &buffer, buffer.count, 0)
            if bytesRead > 0 {
                let data = Data(buffer.prefix(bytesRead))
                DispatchQueue.main.async {
                    self.onOutput?(data)
                }
            } else if bytesRead == 0 {
                // Connection closed by peer
                self.disconnect()
            }
        }

        source.setCancelHandler { [weak self] in
            close(socket)
            self?.clientSocket = -1
        }

        self.readSource = source
        source.resume()
    }
}
