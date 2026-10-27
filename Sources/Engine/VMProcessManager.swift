import UIKit
public final class VMProcessManager: ObservableObject, VMEngineDelegate {
    public static let shared = VMProcessManager()

    @Published public private(set) var activeVMConfig: VMConfig?
    @Published public private(set) var currentState: VMState = .stopped
    @Published public private(set) var memoryWarningReceived = false

    public var onOutputReceived: ((Data) -> Void)?
    public private(set) var outputHistory = Data()

    private var currentEngine: VMEngineProtocol?
    private var backgroundTaskIdentifier: UIBackgroundTaskIdentifier = .invalid
    private var memoryPressureSource: DispatchSourceMemoryPressure?

    public init() {
        setupMemoryPressureObserver()
    }

    deinit {
        memoryPressureSource?.cancel()
    }

    public func launch(
        config: VMConfig,
        engine: VMEngineProtocol,
        diskURL: URL,
        kernelURL: URL?,
        initrdURL: URL?
    ) throws {
        stop()
        self.outputHistory.removeAll()

        self.activeVMConfig = config
        self.currentEngine = engine
        engine.delegate = self

        startBackgroundTask()
        try engine.start(with: config, diskURL: diskURL, kernelURL: kernelURL, initrdURL: initrdURL)
    }

    public func sendInput(_ data: Data) {
        currentEngine?.sendInput(data)
    }

    public func stop() {
        currentEngine?.stop()
        currentEngine = nil
        activeVMConfig = nil
        currentState = .stopped
        endBackgroundTask()
    }

    // MARK: - VMEngineDelegate

    public func vmEngine(_ engine: VMEngineProtocol, didChangeState state: VMState) {
        DispatchQueue.main.async {
            self.currentState = state
            if !state.isActive {
                self.endBackgroundTask()
            }
        }
    }

    public func vmEngine(_ engine: VMEngineProtocol, didReceiveOutput data: Data) {
        DispatchQueue.main.async {
            self.outputHistory.append(data)
            if self.outputHistory.count > 256 * 1024 {
                self.outputHistory = self.outputHistory.suffix(128 * 1024)
            }
            self.onOutputReceived?(data)
        }
    }

    // MARK: - Background Task Lifecycle

    private func startBackgroundTask() {
        endBackgroundTask()
        backgroundTaskIdentifier = UIApplication.shared.beginBackgroundTask(withName: "org.unixruner.vm.execution") { [weak self] in
            // Clean shutdown when iOS budget expires
            self?.stop()
        }
    }

    private func endBackgroundTask() {
        if backgroundTaskIdentifier != .invalid {
            UIApplication.shared.endBackgroundTask(backgroundTaskIdentifier)
            backgroundTaskIdentifier = .invalid
        }
    }

    // MARK: - Memory Pressure (Jetsam Guard)

    private func setupMemoryPressureObserver() {
        let source = DispatchSource.makeMemoryPressureSource(eventMask: [.warning, .critical], queue: .main)
        source.setEventHandler { [weak self] in
            guard let self = self else { return }
            let event = source.data
            if event.contains(.critical) {
                self.memoryWarningReceived = true
                // In critical pressure, pause VM execution to prevent iOS kill
                self.currentEngine?.pause()
            } else if event.contains(.warning) {
                self.memoryWarningReceived = true
            }
        }
        self.memoryPressureSource = source
        source.resume()
    }
}
