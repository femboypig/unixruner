import Foundation

public enum Architecture: String, CaseIterable, Codable, Identifiable {
    case arm64 = "arm64"
    case x86_64 = "x86_64"

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .arm64:
            return "ARM64"
        case .x86_64:
            return "x86_64"
        }
    }

    public var speedIcon: String {
        switch self {
        case .arm64:
            return "hare.fill"
        case .x86_64:
            return "tortoise.fill"
        }
    }

    public var speedEmoji: String {
        switch self {
        case .arm64:
            return "🐇"
        case .x86_64:
            return "🐢"
        }
    }

    public var speedLabel: String {
        switch self {
        case .arm64:
            return "Fast"
        case .x86_64:
            return "Slow (Emulated)"
        }
    }

    public var qemuFrameworkName: String {
        switch self {
        case .arm64:
            return "qemu-aarch64-softmmu"
        case .x86_64:
            return "qemu-x86_64-softmmu"
        }
    }

    public var binaryName: String {
        switch self {
        case .arm64:
            return "qemu-system-aarch64"
        case .x86_64:
            return "qemu-system-x86_64"
        }
    }

    public var defaultMachine: String {
        switch self {
        case .arm64:
            return "virt"
        case .x86_64:
            return "pc"
        }
    }

    public var defaultCPU: String {
        switch self {
        case .arm64:
            return "cortex-a57"
        case .x86_64:
            return "qemu64"
        }
    }

    public var defaultConsole: String {
        switch self {
        case .arm64:
            return "console=ttyAMA0 earlycon panic=1"
        case .x86_64:
            return "console=ttyS0 panic=1"
        }
    }
}
