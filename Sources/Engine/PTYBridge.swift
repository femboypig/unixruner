import Foundation

public final class PTYBridge {
    public private(set) var masterFD: Int32 = -1
    public private(set) var slaveFD: Int32 = -1
    public private(set) var slavePath: String = ""

    private let readQueue = DispatchQueue(label: "org.unixruner.pty.read", qos: .userInteractive)
    private var readSource: DispatchSourceRead?
    private var isRunning = false

    public var onOutput: ((Data) -> Void)?

    public init() {}

    deinit {
        closeDescriptors()
    }

    public func openPTY() throws {
        var master: Int32 = 0
        var slave: Int32 = 0
        var nameBuffer = [CChar](repeating: 0, count: 128)

        if openpty(&master, &slave, &nameBuffer, nil, nil) == 0 {
            self.masterFD = master
            self.slaveFD = slave
            self.slavePath = String(cString: nameBuffer)
            return
        }

        // Sandbox fallback: pipe pair
        var fds = [Int32](repeating: 0, count: 2)
        if pipe(&fds) == 0 {
            self.masterFD = fds[0]
            self.slaveFD = fds[1]
            self.slavePath = "/dev/fd/\(fds[1])"
            return
        }

        throw NSError(domain: "PTYBridge", code: Int(errno), userInfo: [NSLocalizedDescriptionKey: "Failed to open POSIX PTY or pipe"])
    }

    public func startReading() {
        guard masterFD >= 0, !isRunning else { return }
        isRunning = true

        let source = DispatchSource.makeReadSource(fileDescriptor: masterFD, queue: readQueue)
        source.setEventHandler { [weak self] in
            guard let self = self else { return }
            var buffer = [UInt8](repeating: 0, count: 4096)
            let bytesRead = read(self.masterFD, &buffer, buffer.count)
            if bytesRead > 0 {
                let data = Data(buffer.prefix(bytesRead))
                DispatchQueue.main.async {
                    self.onOutput?(data)
                }
            } else if bytesRead == 0 {
                // EOF
                self.stopReading()
            }
        }

        source.setCancelHandler { [weak self] in
            self?.closeDescriptors()
        }

        self.readSource = source
        source.resume()
    }

    public func writeInput(_ data: Data) {
        guard masterFD >= 0 else { return }
        data.withUnsafeBytes { rawBuffer in
            guard let baseAddress = rawBuffer.baseAddress else { return }
            _ = write(self.masterFD, baseAddress, data.count)
        }
    }

    public func stopReading() {
        guard isRunning else { return }
        isRunning = false
        readSource?.cancel()
        readSource = nil
    }

    private func closeDescriptors() {
        if masterFD >= 0 {
            close(masterFD)
            masterFD = -1
        }
        if slaveFD >= 0 {
            close(slaveFD)
            slaveFD = -1
        }
    }
}
