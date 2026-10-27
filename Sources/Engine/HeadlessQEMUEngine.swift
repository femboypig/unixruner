import Foundation

public final class HeadlessQEMUEngine: VMEngineProtocol {
    public weak var delegate: VMEngineDelegate?
    public private(set) var state: VMState = .stopped

    private let socketBridge = TerminalSocketBridge()
    private let qemuRunner = QEMUBinaryRunner()
    private var vmThread: Thread?
    private var isTerminating = false
    private static var hasExecutedInProcess = false

    public init() {}

    public func start(with config: VMConfig, diskURL: URL, kernelURL: URL?, initrdURL: URL?) throws {
        guard state == .stopped || state == .terminated(exitCode: 0) else { return }

        if Self.hasExecutedInProcess {
            let warnMsg = "\r\n\u{001B}[1;33m[unixruner]\u{001B}[0m iOS architecture requires restarting the app between VM runs to clear QEMU static memory state.\r\nPlease swipe up from App Switcher and relaunch unixruner to start the machine again.\r\n"
            AppLogger.shared.log("Attempted second QEMU launch in same process; blocked to prevent dirty static memory crash.", level: .warn)
            if let data = warnMsg.data(using: .utf8) {
                DispatchQueue.main.async {
                    self.delegate?.vmEngine(self, didReceiveOutput: data)
                }
            }
            updateState(.stopped)
            return
        }
        Self.hasExecutedInProcess = true

        Self.enableJITIfNeeded()

        AppLogger.shared.log("Starting VM '\(config.name)' (arch: \(config.architecture.displayName), memory: \(config.memoryMB)MB)...", level: .engine)
        AppLogger.shared.log("Disk path: \(diskURL.path)", level: .engine)
        var effectiveKernelURL: URL? = nil
        if let k = kernelURL {
            let prepared = KernelDecompressor.prepareKernelIfNeeded(at: k)
            effectiveKernelURL = prepared
            AppLogger.shared.log("Kernel path: \(prepared.path)", level: .engine)
        }
        if let i = initrdURL { AppLogger.shared.log("Initrd path: \(i.path)", level: .engine) }

        updateState(.starting)

        let consolePort = TerminalSocketBridge.findAvailablePort()
        AppLogger.shared.log("Selected console port: \(consolePort)", level: .engine)

        socketBridge.onOutput = { [weak self] data in
            guard let self = self else { return }
            self.delegate?.vmEngine(self, didReceiveOutput: data)
        }

        let sharedDir = DiskManager.shared.sharedFolderDirectory

        let args = QEMUArgumentsBuilder.build(
            config: config,
            diskURL: diskURL,
            kernelURL: effectiveKernelURL,
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
                AppLogger.shared.log("Socket bridge connected to QEMU on port \(consolePort)", level: .engine)
                self.updateState(.running)
                // Send Return character after connection so shell/login prompt is drawn
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in
                    self?.sendInput(Data([0x0D]))
                }
            } else {
                AppLogger.shared.log("Socket bridge timed out connecting to port \(consolePort)", level: .error)
                let msg = "\r\n\u{001B}[1;31m[unixruner]\u{001B}[0m Terminal socket connection timed out on port \(consolePort).\r\n"
                if let data = msg.data(using: .utf8) {
                    DispatchQueue.main.async {
                        self.delegate?.vmEngine(self, didReceiveOutput: data)
                    }
                }
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
            AppLogger.shared.log("QEMU launch failed: \(error.localizedDescription)", level: .error)
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

    private static func enableJITIfNeeded() {
        typealias PtraceFunc = @convention(c) (Int32, pid_t, UnsafeMutableRawPointer?, Int32) -> Int32
        if let sym = dlsym(UnsafeMutableRawPointer(bitPattern: -2), "ptrace") {
            let ptrace = unsafeBitCast(sym, to: PtraceFunc.self)
            let res = ptrace(0, 0, nil, 0)
            AppLogger.shared.log("JIT ptrace(PT_TRACE_ME) initialized (result: \(res))", level: .engine)
        }
    }
}
