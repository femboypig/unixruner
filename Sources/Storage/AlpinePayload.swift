import Foundation

public final class AlpinePayload {
    public static let shared = AlpinePayload()

    public static let defaultKernelName = "vmlinuz-virt"
    public static let defaultInitrdName = "initramfs-virt"

    private let fileManager = FileManager.default

    private init() {}

    public var storageDirectory: URL {
        let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = appSupport.appendingPathComponent("alpine", isDirectory: true)
        if !fileManager.fileExists(atPath: dir.path) {
            try? fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        return dir
    }

    public var bundledKernelURL: URL? {
        let direct = Bundle.main.bundleURL.appendingPathComponent("alpine/\(Self.defaultKernelName)")
        if fileManager.fileExists(atPath: direct.path) {
            return direct
        }
        if let url = Bundle.main.url(forResource: Self.defaultKernelName, withExtension: nil, subdirectory: "alpine") {
            return url
        }
        return Bundle.main.url(forResource: Self.defaultKernelName, withExtension: nil)
    }

    public var bundledInitrdURL: URL? {
        let direct = Bundle.main.bundleURL.appendingPathComponent("alpine/\(Self.defaultInitrdName)")
        if fileManager.fileExists(atPath: direct.path) {
            return direct
        }
        if let url = Bundle.main.url(forResource: Self.defaultInitrdName, withExtension: nil, subdirectory: "alpine") {
            return url
        }
        return Bundle.main.url(forResource: Self.defaultInitrdName, withExtension: nil)
    }

    public var localKernelURL: URL {
        storageDirectory.appendingPathComponent(Self.defaultKernelName)
    }

    public var localInitrdURL: URL {
        storageDirectory.appendingPathComponent(Self.defaultInitrdName)
    }

    public var isAvailable: Bool {
        if let k = resolvedKernelPath(), let i = resolvedInitrdPath() {
            return fileManager.fileExists(atPath: k) && fileManager.fileExists(atPath: i)
        }
        return false
    }

    public func resolvedKernelPath() -> String? {
        if fileManager.fileExists(atPath: localKernelURL.path) {
            return localKernelURL.path
        }
        if let bundled = bundledKernelURL, fileManager.fileExists(atPath: bundled.path) {
            return bundled.path
        }
        return nil
    }

    public func resolvedInitrdPath() -> String? {
        if fileManager.fileExists(atPath: localInitrdURL.path) {
            return localInitrdURL.path
        }
        if let bundled = bundledInitrdURL, fileManager.fileExists(atPath: bundled.path) {
            return bundled.path
        }
        return nil
    }

    public func preparePayload() throws {
        // If bundled into app, copy or link to local directory for quick access
        if !fileManager.fileExists(atPath: localKernelURL.path), let bundled = bundledKernelURL {
            try fileManager.copyItem(at: bundled, to: localKernelURL)
        }
        if !fileManager.fileExists(atPath: localInitrdURL.path), let bundled = bundledInitrdURL {
            try fileManager.copyItem(at: bundled, to: localInitrdURL)
        }
    }
}
