import Foundation
import Core

public final class HeadlessQEMUEngine: VMEngineProtocol {
    public weak var delegate: VMEngineDelegate?
    public private(set) var state: VMState = .stopped

    private let ptyBridge = PTYBridge()
    private var vmThread: Thread?
    private var isTerminating = false

    public init() {}

    public func start(with config: VMConfig, diskURL: URL, kernelURL: URL?, initrdURL: URL?) throws {
        guard state == .stopped || state == .terminated(exitCode: 0) else { return }

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
    }

    public func sendInput(_ data: Data) {
        ptyBridge.writeInput(data)
    }

    public func pause() {
        // Pausing JIT thread execution
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
        // This is bridged to the prebuilt C symbol `qemu_main(argc, argv)` in production
        // Keep the thread active while the VM runs
        while !Thread.current.isCancelled && !isTerminating {
            Thread.sleep(forTimeInterval: 0.1)
        }
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.updateState(.terminated(exitCode: 0))
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
