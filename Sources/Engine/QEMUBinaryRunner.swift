import Foundation
import Darwin

public final class QEMUBinaryRunner {
    private typealias QemuInitFunc = @convention(c) (Int32, UnsafePointer<UnsafePointer<CChar>?>?, UnsafePointer<UnsafePointer<CChar>?>?) -> Void
    private typealias QemuMainLoopFunc = @convention(c) () -> Void
    private typealias QemuCleanupFunc = @convention(c) () -> Void

    private var handle: UnsafeMutableRawPointer?
    private var supportingHandles: [UnsafeMutableRawPointer] = []
    private var qemu_init: QemuInitFunc?
    private var qemu_main_loop: QemuMainLoopFunc?
    private var qemu_cleanup: QemuCleanupFunc?

    private var allocatedArgs: [UnsafeMutablePointer<CChar>] = []
    private var allocatedEnv: [UnsafeMutablePointer<CChar>] = []

    public init() {}

    deinit {
        unload()
    }

    public func load(for architecture: Architecture) throws {
        guard let frameworksURL = Bundle.main.privateFrameworksURL else {
            let msg = "Bundle Frameworks directory not found"
            AppLogger.shared.log(msg, level: .error)
            throw NSError(domain: "QEMUBinaryRunner", code: 1, userInfo: [NSLocalizedDescriptionKey: msg])
        }

        AppLogger.shared.log("Loading QEMU runtime for \(architecture.displayName)...", level: .engine)

        // Preload core supporting frameworks with RTLD_LOCAL so dependencies resolve cleanly
        let preloads = [
            "ffi.8", "intl.8", "iconv.2",
            "glib-2.0.0", "gmodule-2.0.0", "gobject-2.0.0", "gthread-2.0.0", "gio-2.0.0",
            "pixman-1.0", "jpeg.62", "png16.16", "zstd.1", "slirp.0"
        ]

        for name in preloads {
            let fwPath = frameworksURL.appendingPathComponent("\(name).framework/\(name)").path
            if FileManager.default.fileExists(atPath: fwPath) {
                if let h = dlopen(fwPath, RTLD_LOCAL | RTLD_LAZY) {
                    supportingHandles.append(h)
                } else {
                    let err = dlerror().map { String(cString: $0) } ?? "unknown"
                    AppLogger.shared.log("Optional preload \(name) skipped: \(err)", level: .warn)
                }
            }
        }

        let frameworkName = (architecture == .arm64) ? "qemu-aarch64-softmmu" : "qemu-x86_64-softmmu"
        let frameworkURL = frameworksURL.appendingPathComponent("\(frameworkName).framework/\(frameworkName)")

        guard FileManager.default.fileExists(atPath: frameworkURL.path) else {
            let msg = "QEMU binary framework missing at \(frameworkURL.path)"
            AppLogger.shared.log(msg, level: .error)
            throw NSError(domain: "QEMUBinaryRunner", code: 2, userInfo: [NSLocalizedDescriptionKey: msg])
        }

        guard let handle = dlopen(frameworkURL.path, RTLD_LOCAL | RTLD_LAZY | RTLD_FIRST) else {
            let err = dlerror().map { String(cString: $0) } ?? "unknown error"
            let msg = "dlopen failed for \(frameworkName): \(err)"
            AppLogger.shared.log(msg, level: .error)
            throw NSError(domain: "QEMUBinaryRunner", code: 3, userInfo: [NSLocalizedDescriptionKey: msg])
        }
        self.handle = handle

        guard let initSym = dlsym(handle, "qemu_init"),
              let loopSym = dlsym(handle, "qemu_main_loop"),
              let cleanSym = dlsym(handle, "qemu_cleanup") else {
            let err = dlerror().map { String(cString: $0) } ?? "missing entry symbols"
            let msg = "dlsym failed: \(err)"
            AppLogger.shared.log(msg, level: .error)
            throw NSError(domain: "QEMUBinaryRunner", code: 4, userInfo: [NSLocalizedDescriptionKey: msg])
        }

        self.qemu_init = unsafeBitCast(initSym, to: QemuInitFunc.self)
        self.qemu_main_loop = unsafeBitCast(loopSym, to: QemuMainLoopFunc.self)
        self.qemu_cleanup = unsafeBitCast(cleanSym, to: QemuCleanupFunc.self)

        AppLogger.shared.log("QEMU entry symbols resolved successfully.", level: .engine)
    }

    public func run(arguments: [String], onStdErr: ((String) -> Void)? = nil) throws {
        guard let qemu_init = qemu_init,
              let qemu_main_loop = qemu_main_loop,
              let qemu_cleanup = qemu_cleanup else {
            let msg = "QEMU runner not loaded"
            AppLogger.shared.log(msg, level: .error)
            throw NSError(domain: "QEMUBinaryRunner", code: 5, userInfo: [NSLocalizedDescriptionKey: msg])
        }

        AppLogger.shared.log("QEMU arguments:\n\(arguments.joined(separator: " "))", level: .engine)

        // Set up real-time concurrent stderr pipe capture
        var pipeFDs = [Int32](repeating: 0, count: 2)
        let hasPipe = pipe(&pipeFDs) == 0
        let savedStderr = dup(STDERR_FILENO)

        var readSource: DispatchSourceRead?
        if hasPipe {
            let flags = fcntl(pipeFDs[0], F_GETFL, 0)
            _ = fcntl(pipeFDs[0], F_SETFL, flags | O_NONBLOCK)
            dup2(pipeFDs[1], STDERR_FILENO)
            close(pipeFDs[1])

            let source = DispatchSource.makeReadSource(fileDescriptor: pipeFDs[0], queue: DispatchQueue.global(qos: .userInteractive))
            source.setEventHandler {
                var buf = [UInt8](repeating: 0, count: 4096)
                let n = read(pipeFDs[0], &buf, buf.count - 1)
                if n > 0 {
                    buf[n] = 0
                    let str = String(cString: buf)
                    AppLogger.shared.log(str, level: .qemu)
                    onStdErr?(str)
                }
            }
            readSource = source
            source.resume()
        }

        // Clean any leftover strings from previous runs
        cleanAllocatedStrings()

        // Build valid argv that remains in memory for the lifetime of QEMU execution
        let cArgs = arguments.map { strdup($0)! }
        allocatedArgs = cArgs
        var argv: [UnsafePointer<CChar>?] = cArgs.map { UnsafePointer($0) }
        argv.append(nil)

        // Build valid, non-null envp that remains in memory for the lifetime of QEMU execution
        var envEntries: [String] = []
        for (k, v) in ProcessInfo.processInfo.environment {
            envEntries.append("\(k)=\(v)")
        }
        if !envEntries.contains(where: { $0.hasPrefix("QEMU_AUDIO_DRV=") }) {
            envEntries.append("QEMU_AUDIO_DRV=none")
        }
        let cEnv = envEntries.map { strdup($0)! }
        allocatedEnv = cEnv
        var envp: [UnsafePointer<CChar>?] = cEnv.map { UnsafePointer($0) }
        envp.append(nil)

        let argc = Int32(arguments.count)

        AppLogger.shared.log("Starting QEMU execution on worker thread...", level: .engine)

        // Guard against QEMU calling exit() so the host app does not terminate
        let qemuThread = pthread_self()
        _ = atexit_b {
            if pthread_equal(pthread_self(), qemuThread) != 0 {
                AppLogger.shared.log("QEMU requested process exit; terminating worker thread safely.", level: .warn)
                pthread_exit(nil)
            }
        }

        argv.withUnsafeBufferPointer { argvBuf in
            envp.withUnsafeBufferPointer { envpBuf in
                qemu_init(argc, argvBuf.baseAddress, envpBuf.baseAddress)
            }
        }
        AppLogger.shared.log("QEMU initialized; entering main loop.", level: .engine)
        qemu_main_loop()
        AppLogger.shared.log("QEMU main loop finished; cleaning up.", level: .engine)
        qemu_cleanup()

        if hasPipe {
            dup2(savedStderr, STDERR_FILENO)
            close(savedStderr)

            readSource?.cancel()
            close(pipeFDs[0])
        }

        cleanAllocatedStrings()
    }

    public func unload() {
        cleanAllocatedStrings()

        if let h = handle {
            dlclose(h)
            handle = nil
        }
        for h in supportingHandles {
            dlclose(h)
        }
        supportingHandles.removeAll()

        qemu_init = nil
        qemu_main_loop = nil
        qemu_cleanup = nil
    }

    private func cleanAllocatedStrings() {
        for ptr in allocatedArgs { free(ptr) }
        allocatedArgs.removeAll()
        for ptr in allocatedEnv { free(ptr) }
        allocatedEnv.removeAll()
    }
}
