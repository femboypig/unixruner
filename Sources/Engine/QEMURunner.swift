import Foundation
import Darwin

public final class QEMURunner {
    public static let shared = QEMURunner()

    private let loader = QEMULoader()
    private var workerThread: Thread?
    private var isExecuting = false

    private init() {}

    public func run(arguments: [String], architecture: Architecture, onExit: @escaping () -> Void) throws {
        guard !isExecuting else {
            throw NSError(domain: "QEMURunner", code: 1, userInfo: [NSLocalizedDescriptionKey: "QEMU instance already running"])
        }

        try loader.load(architecture: architecture)
        guard let qemuInit = loader.qemuInit,
              let qemuMainLoop = loader.qemuMainLoop,
              let qemuCleanup = loader.qemuCleanup else {
            throw NSError(domain: "QEMURunner", code: 2, userInfo: [NSLocalizedDescriptionKey: "QEMU entry symbols unavailable"])
        }

        isExecuting = true
        Logger.shared.log("Starting QEMU worker thread with \(arguments.count) arguments", level: .engine)
        Logger.shared.log(arguments.joined(separator: " "), level: .engine)

        // Capture stderr in real time
        var pipeFDs = [Int32](repeating: 0, count: 2)
        let hasPipe = pipe(&pipeFDs) == 0
        let savedStderr = dup(STDERR_FILENO)

        var readSource: DispatchSourceRead?
        let pipeQueue = DispatchQueue(label: "org.unixruner.stderr")
        if hasPipe {
            _ = fcntl(pipeFDs[0], F_SETFL, fcntl(pipeFDs[0], F_GETFL, 0) | O_NONBLOCK)
            dup2(pipeFDs[1], STDERR_FILENO)
            close(pipeFDs[1])

            let source = DispatchSource.makeReadSource(fileDescriptor: pipeFDs[0], queue: pipeQueue)
            source.setEventHandler {
                var buf = [UInt8](repeating: 0, count: 2048)
                let count = read(pipeFDs[0], &buf, buf.count)
                if count > 0 {
                    let str = String(decoding: buf.prefix(count), as: UTF8.self)
                    let trimmed = str.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !trimmed.isEmpty {
                        for line in trimmed.components(separatedBy: .newlines) {
                            let clean = line.trimmingCharacters(in: .whitespacesAndNewlines)
                            if !clean.isEmpty {
                                Logger.shared.log(clean, level: .engine)
                            }
                        }
                    }
                }
            }
            readSource = source
            source.resume()
        }

        let thread = Thread { [weak self] in
            let cArgs = arguments.map { strdup($0)! }
            var argv: [UnsafePointer<CChar>?] = cArgs.map { UnsafePointer($0) }
            argv.append(nil)

            var envpList: [UnsafeMutablePointer<CChar>] = []
            for (k, v) in ProcessInfo.processInfo.environment {
                envpList.append(strdup("\(k)=\(v)")!)
            }
            if !ProcessInfo.processInfo.environment.keys.contains("QEMU_AUDIO_DRV") {
                envpList.append(strdup("QEMU_AUDIO_DRV=none")!)
            }
            var envp: [UnsafePointer<CChar>?] = envpList.map { UnsafePointer($0) }
            envp.append(nil)

            var stderrRestored = false
            func restoreStderr() {
                guard !stderrRestored else { return }
                stderrRestored = true
                if hasPipe {
                    Darwin.fflush(Darwin.stderr)
                    dup2(savedStderr, STDERR_FILENO)
                    close(savedStderr)
                    readSource?.cancel()
                    readSource?.setEventHandler(handler: nil)

                    pipeQueue.sync {
                        var buf = [UInt8](repeating: 0, count: 2048)
                        while true {
                            let count = read(pipeFDs[0], &buf, buf.count)
                            if count > 0 {
                                let str = String(decoding: buf.prefix(count), as: UTF8.self)
                                let trimmed = str.trimmingCharacters(in: .whitespacesAndNewlines)
                                if !trimmed.isEmpty {
                                    for line in trimmed.components(separatedBy: .newlines) {
                                        let clean = line.trimmingCharacters(in: .whitespacesAndNewlines)
                                        if !clean.isEmpty {
                                            Logger.shared.log(clean, level: .engine)
                                        }
                                    }
                                }
                            } else {
                                break
                            }
                        }
                        close(pipeFDs[0])
                    }
                }
            }

            var cleanedUp = false
            func cleanupAllocations() {
                guard !cleanedUp else { return }
                cleanedUp = true
                for ptr in cArgs { free(ptr) }
                for ptr in envpList { free(ptr) }
            }

            var exitNotified = false
            func notifyExit() {
                guard !exitNotified else { return }
                exitNotified = true
                self?.isExecuting = false
                self?.loader.unload()
                DispatchQueue.main.async {
                    onExit()
                }
            }

            let currentThread = pthread_self()
            _ = atexit_b {
                if pthread_equal(pthread_self(), currentThread) != 0 {
                    restoreStderr()
                    Logger.shared.log("QEMU requested process exit; terminating worker thread safely.", level: .warn)
                    cleanupAllocations()
                    notifyExit()
                    pthread_exit(nil)
                }
            }

            let initStatus = argv.withUnsafeBufferPointer { argvBuf in
                envp.withUnsafeBufferPointer { envpBuf in
                    qemuInit(Int32(arguments.count), argvBuf.baseAddress, envpBuf.baseAddress)
                }
            }

            if initStatus != 0 {
                Logger.shared.log("QEMU initialization failed with status \(initStatus)", level: .error)
                restoreStderr()
                cleanupAllocations()
                notifyExit()
                return
            }

            Logger.shared.log("QEMU initialized; entering main loop.", level: .engine)
            qemuMainLoop()
            Logger.shared.log("QEMU main loop finished; cleaning up.", level: .engine)
            qemuCleanup()

            cleanupAllocations()
            restoreStderr()
            notifyExit()
        }

        self.workerThread = thread
        thread.qualityOfService = .userInteractive
        thread.start()
    }

    public func stop() {
        guard isExecuting else { return }
        Logger.shared.log("Requesting QEMU engine shutdown", level: .engine)
        if let shutdown = loader.qemuShutdownRequest {
            shutdown(1)
        }
    }
}
