import Foundation

public final class Logger {
    public static let shared = Logger()

    public enum Level: String {
        case info = "INFO"
        case warn = "WARN"
        case error = "ERROR"
        case engine = "ENGINE"
    }

    public struct Entry: Identifiable {
        public let id = UUID()
        public let timestamp: Date
        public let level: Level
        public let message: String
    }

    private let queue = DispatchQueue(label: "org.unixruner.logger", qos: .utility)
    private var entries: [Entry] = []
    private let maxEntries = 500

    private init() {}

    public func log(_ message: String, level: Level = .info) {
        let entry = Entry(timestamp: Date(), level: level, message: message)
        queue.async {
            self.entries.append(entry)
            if self.entries.count > self.maxEntries {
                self.entries.removeFirst(self.entries.count - self.maxEntries)
            }
        }
        #if DEBUG
        print("[\(level.rawValue)] \(message)")
        #endif
    }

    public func snapshot() -> [Entry] {
        queue.sync { entries }
    }

    public func clear() {
        queue.async {
            self.entries.removeAll()
        }
    }
}
