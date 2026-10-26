import Foundation

public enum VMState: Equatable {
    case stopped
    case starting
    case running
    case stopping
    case error(String)

    public var isRunning: Bool {
        if case .running = self { return true }
        return false
    }

    public var statusText: String {
        switch self {
        case .stopped:
            return "Stopped"
        case .starting:
            return "Starting..."
        case .running:
            return "Running"
        case .stopping:
            return "Stopping..."
        case .error(let message):
            return "Error: \(message)"
        }
    }
}
