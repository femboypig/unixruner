import Foundation
import UIKit

public enum LogLevel: String {
    case info = "INFO"
    case warn = "WARN"
    case error = "ERROR"
    case qemu = "QEMU"
    case engine = "ENGINE"
    case crash = "CRASH"
}

public final class AppLogger {
    public static let shared = AppLogger()

    private let fileQueue = DispatchQueue(label: "org.unixruner.logger.file", qos: .utility)
    private let dateFormatter: DateFormatter
    private var logFileHandle: FileHandle?
    private let logURL: URL

    public var logFileURL: URL {
        logURL
    }

    private init() {
        dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"

        let paths = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)
        let logDir = paths[0].appendingPathComponent("logs", isDirectory: true)
        try? FileManager.default.createDirectory(at: logDir, withIntermediateDirectories: true)
        logURL = logDir.appendingPathComponent("unixruner.log")

        if !FileManager.default.fileExists(atPath: logURL.path) {
            FileManager.default.createFile(atPath: logURL.path, contents: Data())
        }

        logFileHandle = try? FileHandle(forWritingTo: logURL)
        logFileHandle?.seekToEndOfFile()

        logSystemInfo()
        installCrashHandlers()
    }

    public func log(_ message: String, level: LogLevel = .info, file: String = #file, line: Int = #line) {
        let timestamp = dateFormatter.string(from: Date())
        let fileName = (file as NSString).lastPathComponent
        let formatted = "[\(timestamp)] [\(level.rawValue)] [\(fileName):\(line)] \(message)\n"

        print(formatted, terminator: "")

        fileQueue.async { [weak self] in
            guard let self = self, let handle = self.logFileHandle, let data = formatted.data(using: .utf8) else { return }
            handle.write(data)
        }
    }

    public func readRecentLogs(maxLines: Int = 300) -> String {
        guard let data = try? Data(contentsOf: logURL),
              let content = String(data: data, encoding: .utf8) else {
            return "No logs recorded yet."
        }
        let lines = content.components(separatedBy: .newlines)
        let recent = lines.suffix(maxLines)
        return recent.joined(separator: "\n")
    }

    public func clear() {
        fileQueue.async { [weak self] in
            guard let self = self else { return }
            try? "".write(to: self.logURL, atomically: true, encoding: .utf8)
            self.logFileHandle = try? FileHandle(forWritingTo: self.logURL)
        }
    }

    private func logSystemInfo() {
        let device = UIDevice.current
        let systemVersion = device.systemVersion
        let model = device.model
        let processInfo = ProcessInfo.processInfo
        let ramGB = Double(processInfo.physicalMemory) / (1024 * 1024 * 1024)

        log("--- unixruner session started ---", level: .info)
        log("Device: \(model), iOS: \(systemVersion), RAM: \(String(format: "%.2f", ramGB)) GB, Cores: \(processInfo.processorCount)", level: .info)
    }

    private func installCrashHandlers() {
        NSSetUncaughtExceptionHandler { exception in
            let symbols = exception.callStackSymbols.joined(separator: "\n")
            AppLogger.shared.log("UNCAUGHT EXCEPTION: \(exception.name): \(exception.reason ?? "")\nStack:\n\(symbols)", level: .crash)
        }

        let signals: [Int32] = [SIGABRT, SIGSEGV, SIGBUS, SIGILL, SIGFPE]
        for sig in signals {
            signal(sig) { signum in
                let symbols = Thread.callStackSymbols.joined(separator: "\n")
                AppLogger.shared.log("FATAL SIGNAL \(signum)\nStack:\n\(symbols)", level: .crash)
                signal(signum, SIG_DFL)
                raise(signum)
            }
        }
    }
}
