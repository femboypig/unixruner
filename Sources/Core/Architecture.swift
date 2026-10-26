import Foundation

public enum Architecture: String, Codable, CaseIterable, Identifiable, Hashable {
    case arm64 = "arm64"
    case amd64 = "x86_64"

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .arm64:
            return "ARM64"
        case .amd64:
            return "AMD64 (x86_64)"
        }
    }

    public var badgeIcon: String {
        switch self {
        case .arm64:
            return "hare.fill"
        case .amd64:
            return "tortoise.fill"
        }
    }

    public var performanceNote: String {
        switch self {
        case .arm64:
            return "Native JIT translation • Fast"
        case .amd64:
            return "Cross-architecture emulation • Slow"
        }
    }

    public var qemuTarget: String {
        switch self {
        case .arm64:
            return "qemu-system-aarch64"
        case .amd64:
            return "qemu-system-x86_64"
        }
    }

    public var defaultMachine: String {
        switch self {
        case .arm64:
            return "virt"
        case .amd64:
            return "q35"
        }
    }

    public var defaultCpu: String {
        switch self {
        case .arm64:
            return "cortex-a57"
        case .amd64:
            return "qemu64"
        }
    }
}
