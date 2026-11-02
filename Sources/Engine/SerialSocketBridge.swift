import Foundation
import Darwin

public final class SerialSocketBridge {
    private var socketFD: Int32 = -1
    private var readSource: DispatchSourceRead?
    private let queue = DispatchQueue(label: "org.unixruner.socketbridge", qos: .userInteractive)
    private var earlyBuffer = Data()
    private static let maxBufferSize = 512 * 1024

    public var onDataReceived: ((Data) -> Void)? {
        didSet {
            guard let handler = onDataReceived, !earlyBuffer.isEmpty else { return }
            let pending = earlyBuffer
            earlyBuffer.removeAll()
            handler(pending)
        }
    }
    public var onConnected: (() -> Void)?
    public var onDisconnected: (() -> Void)?

    public init() {}

    deinit {
        disconnect()
    }

    public func connect(port: Int, maxAttempts: Int = 30, retryInterval: TimeInterval = 0.2) {
        DispatchQueue.main.async {
            self.earlyBuffer.removeAll()
        }

        queue.async { [weak self] in
            guard let self = self else { return }

            for _ in 0..<maxAttempts {
                let fd = socket(AF_INET, SOCK_STREAM, 0)
                if fd < 0 {
                    Thread.sleep(forTimeInterval: retryInterval)
                    continue
                }

                var addr = sockaddr_in()
                addr.sin_family = sa_family_t(AF_INET)
                addr.sin_port = in_port_t(UInt16(port).bigEndian)
                addr.sin_addr.s_addr = inet_addr("127.0.0.1")

                let connectRes = withUnsafePointer(to: &addr) { ptr in
                    ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sa in
                        Darwin.connect(fd, sa, socklen_t(MemoryLayout<sockaddr_in>.size))
                    }
                }

                if connectRes == 0 {
                    let flags = fcntl(fd, F_GETFL, 0)
                    _ = fcntl(fd, F_SETFL, flags | O_NONBLOCK)
                    self.socketFD = fd
                    self.startReading()
                    DispatchQueue.main.async {
                        self.onConnected?()
                    }
                    return
                }

                close(fd)
                Thread.sleep(forTimeInterval: retryInterval)
            }
        }
    }

    private func startReading() {
        guard socketFD >= 0 else { return }

        let source = DispatchSource.makeReadSource(fileDescriptor: socketFD, queue: queue)
        source.setEventHandler { [weak self] in
            guard let self = self, self.socketFD >= 0 else { return }
            var buffer = [UInt8](repeating: 0, count: 4096)
            let bytesRead = read(self.socketFD, &buffer, buffer.count)
            if bytesRead > 0 {
                let data = Data(buffer.prefix(bytesRead))
                DispatchQueue.main.async {
                    if let handler = self.onDataReceived {
                        if !self.earlyBuffer.isEmpty {
                            let pending = self.earlyBuffer
                            self.earlyBuffer.removeAll()
                            handler(pending)
                        }
                        handler(data)
                    } else {
                        self.earlyBuffer.append(data)
                        if self.earlyBuffer.count > Self.maxBufferSize {
                            self.earlyBuffer.removeFirst(self.earlyBuffer.count - Self.maxBufferSize)
                        }
                    }
                }
            } else if bytesRead == 0 {
                self.disconnect()
            }
        }
        source.setCancelHandler { [weak self] in
            if let fd = self?.socketFD, fd >= 0 {
                close(fd)
                self?.socketFD = -1
            }
        }
        self.readSource = source
        source.resume()
    }

    public func write(data: Data) {
        queue.async { [weak self] in
            guard let self = self, self.socketFD >= 0 else { return }
            data.withUnsafeBytes { rawBuffer in
                guard let base = rawBuffer.baseAddress else { return }
                var totalWritten = 0
                while totalWritten < data.count {
                    let written = Darwin.write(self.socketFD, base + totalWritten, data.count - totalWritten)
                    if written <= 0 { break }
                    totalWritten += written
                }
            }
        }
    }

    public func disconnect() {
        queue.async { [weak self] in
            guard let self = self else { return }
            self.readSource?.cancel()
            self.readSource = nil
            if self.socketFD >= 0 {
                close(self.socketFD)
                self.socketFD = -1
            }
            DispatchQueue.main.async {
                self.earlyBuffer.removeAll()
                self.onDisconnected?()
            }
        }
    }
}
