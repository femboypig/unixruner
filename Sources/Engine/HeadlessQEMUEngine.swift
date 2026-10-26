import Foundation

public final class HeadlessQEMUEngine: VMEngineProtocol {
    public weak var delegate: VMEngineDelegate?
    public private(set) var state: VMState = .stopped

    private let socketBridge = TerminalSocketBridge()
    private let qemuRunner = QEMUBinaryRunner()
    private var vmThread: Thread?
    private var isTerminating = false

    public init() {}

    public func start(with config: VMConfig, diskURL: URL, kernelURL: URL?, initrdURL: URL?) throws {
        guard state == .stopped || state == .terminated(exitCode: 0) else { return }

        updateState(.starting)

        let consolePort = TerminalSocketBridge.findAvailablePort()

        socketBridge.onOutput = { [weak self] data in
            guard let self = self else { return }
            self.delegate?.vmEngine(self, didReceiveOutput: data)
        }

        let sharedDir = DiskManager.shared.sharedFolderDirectory

        let args = QEMUArgumentsBuilder.build(
            config: config,
            diskURL: diskURL,
            kernelURL: kernelURL,
            initrdURL: initrdURL,
            sharedFolderURL: sharedDir,
            socketPort: consolePort
        )

        let thread = Thread { [weak self] in
            guard let self = self else { return }
            self.runQEMUProcess(config: config, arguments: args)
        }
        thread.name = "org.unixruner.qemu.worker"
        thread.qualityOfService = .userInteractive
        self.vmThread = thread
        thread.start()

        // Connect socket bridge to QEMU serial socket on localhost
        socketBridge.connect(port: consolePort) { [weak self] success in
            guard let self = self else { return }
            if success {
                self.updateState(.running)
            }
        }
    }

    public func sendInput(_ data: Data) {
        socketBridge.writeInput(data)
    }

    public func pause() {
        updateState(.paused)
    }

    public func resume() {
        updateState(.running)
    }

    public func stop() {
        guard !isTerminating else { return }
        isTerminating = true

        socketBridge.disconnect()
        qemuRunner.unload()
        vmThread?.cancel()
        vmThread = nil

        updateState(.stopped)
        isTerminating = false
    }

    private func runQEMUProcess(config: VMConfig, arguments: [String]) {
        do {
            try qemuRunner.load(for: config.architecture)
            try qemuRunner.run(arguments: arguments) { [weak self] stdErrOutput in
                guard let self = self, !stdErrOutput.isEmpty else { return }
                if let data = "\r\n[qemu] \(stdErrOutput)\r\n".data(using: .utf8) {
                    DispatchQueue.main.async {
                        self.delegate?.vmEngine(self, didReceiveOutput: data)
                    }
                }
            }
            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                self.updateState(.terminated(exitCode: 0))
            }
        } catch {
            let errorMsg = """
            \r\n\u{001B}[1;31m[unixruner error]\u{001B}[0m QEMU engine launch failed:
            \(error.localizedDescription)
            \r\nTarget: \(config.architecture.displayName) (\(config.architecture.qemuTarget))\r\n
            """
            if let data = errorMsg.data(using: .utf8) {
                DispatchQueue.main.async { [weak self] in
                    guard let self = self else { return }
                    self.delegate?.vmEngine(self, didReceiveOutput: data)
                    self.updateState(.failed(reason: error.localizedDescription))
                }
            }
        }
    }

    private func updateState(_ newState: VMState) {
        self.state = newState
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.delegate?.vmEngine(self, didChangeState: newState)
        }
    }
}
