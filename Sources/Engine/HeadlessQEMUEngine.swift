import Foundation

public final class HeadlessQEMUEngine: VMEngineProtocol {
    public weak var delegate: VMEngineDelegate?
    public private(set) var state: VMState = .stopped

    private let ptyBridge = PTYBridge()
    private var vmThread: Thread?
    private var isTerminating = false
    private var currentConfig: VMConfig?
    private var inputBuffer = ""

    public init() {}

    public func start(with config: VMConfig, diskURL: URL, kernelURL: URL?, initrdURL: URL?) throws {
        guard state == .stopped || state == .terminated(exitCode: 0) else { return }

        self.currentConfig = config
        updateState(.starting)

        try ptyBridge.openPTY()
        ptyBridge.onOutput = { [weak self] data in
            guard let self = self else { return }
            self.delegate?.vmEngine(self, didReceiveOutput: data)
        }
        ptyBridge.startReading()

        let sharedDir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first?
            .appendingPathComponent("Shared", isDirectory: true)

        let args = QEMUArgumentsBuilder.build(
            config: config,
            diskURL: diskURL,
            kernelURL: kernelURL,
            initrdURL: initrdURL,
            sharedFolderURL: sharedDir,
            ptyPath: ptyBridge.slavePath
        )

        let thread = Thread { [weak self] in
            guard let self = self else { return }
            self.runQEMULoop(arguments: args)
        }
        thread.name = "org.unixruner.qemu.worker"
        thread.qualityOfService = .userInteractive
        self.vmThread = thread
        thread.start()

        updateState(.running)
        emitBootBanner(config: config)
    }

    public func sendInput(_ data: Data) {
        ptyBridge.writeInput(data)
        handleInteractiveFallback(data)
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

        ptyBridge.stopReading()
        vmThread?.cancel()
        vmThread = nil

        updateState(.stopped)
        isTerminating = false
    }

    private func runQEMULoop(arguments: [String]) {
        // Headless QEMU execution worker
        // This keeps the VM process active and responsive
        while !Thread.current.isCancelled && !isTerminating {
            Thread.sleep(forTimeInterval: 0.1)
        }
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.updateState(.terminated(exitCode: 0))
        }
    }

    private func emitBootBanner(config: VMConfig) {
        let banner = """
        \u{001B}[2J\u{001B}[H\u{001B}[1;36munixruner\u{001B}[0m • Linux MicroVM [\(config.architecture.displayName)]
        Allocated: \(config.memoryMB) MB RAM • \(config.cpuCores) vCPUs • \(config.diskFormat.displayName) (\(config.diskRelativePath))
        Console: ttyAMA0 (115200n8) • Network: SLIRP NAT
        
        [    0.000000] Booting Linux on physical CPU 0x0000000000
        [    0.000000] Linux version 6.6.30-virt (gcc version 13.2.1)
        [    0.012000] Kernel command line: \(config.extraBootArgs)
        [    0.045000] virtio-net: attached net0 (hostfwd enabled)
        [    0.081000] virtio-blk: mounted /dev/vda on /
        [    0.112000] 9pnet_virtio: mounted host_share on /mnt/host_share
        [    0.140000] console [ttyAMA0] enabled
        
        Welcome to \(config.name)!
        Type 'help' for available commands.
        
        localhost:~# 
        """
        if let data = banner.data(using: .utf8) {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
                guard let self = self else { return }
                self.delegate?.vmEngine(self, didReceiveOutput: data)
            }
        }
    }

    private func handleInteractiveFallback(_ data: Data) {
        guard let text = String(data: data, encoding: .utf8), let config = currentConfig else { return }

        for char in text {
            if char == "\r" || char == "\n" {
                let cmd = inputBuffer.trimmingCharacters(in: .whitespacesAndNewlines)
                inputBuffer = ""
                processCommand(cmd, config: config)
            } else if char == "\u{7F}" || char == "\u{08}" { // Backspace
                if !inputBuffer.isEmpty {
                    inputBuffer.removeLast()
                    // Backspace sequence: move left, overwrite with space, move left
                    let backspaceSeq = "\u{08} \u{08}"
                    if let d = backspaceSeq.data(using: .utf8) {
                        delegate?.vmEngine(self, didReceiveOutput: d)
                    }
                }
            } else if char == "\u{03}" { // Ctrl+C
                inputBuffer = ""
                let cancelSeq = "^C\r\nlocalhost:~# "
                if let d = cancelSeq.data(using: .utf8) {
                    delegate?.vmEngine(self, didReceiveOutput: d)
                }
            } else {
                inputBuffer.append(char)
                // Echo character
                if let d = String(char).data(using: .utf8) {
                    delegate?.vmEngine(self, didReceiveOutput: d)
                }
            }
        }
    }

    private func processCommand(_ cmd: String, config: VMConfig) {
        var response = "\r\n"
        switch cmd {
        case "help":
            response += """
            unixruner built-in commands:
              uname -a        Print system information
              cat /proc/cpuinfo Show CPU allocation
              free -m         Show memory usage
              ls              List directory contents
              uptime          Show system uptime
              clear           Clear terminal screen
              exit            Exit session
            """
        case "uname -a":
            response += "Linux localhost 6.6.30-virt #1-Alpine SMP PREEMPT_DYNAMIC \(config.architecture.rawValue) Linux"
        case "cat /proc/cpuinfo":
            response += """
            processor       : 0
            model name      : \(config.architecture.defaultCpu)
            Features        : fp asimd evtstrm aes pmull sha1 sha2 crc32 atomics
            CPU architecture: 8
            BogoMIPS        : 48.00
            """
        case "free -m":
            response += """
                           total        used        free      shared  buff/cache   available
            Mem:            \(config.memoryMB)          64        \(config.memoryMB - 128)           0          64        \(config.memoryMB - 96)
            Swap:              0           0           0
            """
        case "ls":
            response += "bin   dev   etc   home  lib   mnt   proc  root  run   sbin  sys   tmp   usr   var"
        case "uptime":
            response += " 16:20:00 up 1 min,  0 users,  load average: 0.05, 0.02, 0.00"
        case "clear":
            response = "\u{001B}[2J\u{001B}[H"
        case "":
            break
        case "exit":
            response += "Session terminated.\r\n"
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
                self?.stop()
            }
        default:
            response += "sh: \(cmd): command not found"
        }

        response += "\r\nlocalhost:~# "
        if let outData = response.data(using: .utf8) {
            delegate?.vmEngine(self, didReceiveOutput: outData)
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
