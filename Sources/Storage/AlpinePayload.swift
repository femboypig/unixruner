import Foundation

public final class AlpinePayload {
    public static let shared = AlpinePayload()

    public static let defaultKernelName = "Image"
    public static let defaultInitrdName = "initramfs.cpio.gz"

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
        if let bundled = bundledKernelURL, fileManager.fileExists(atPath: bundled.path) {
            return bundled.path
        }
        return nil
    }

    public func resolvedInitrdPath() -> String? {
        if let bundled = bundledInitrdURL, fileManager.fileExists(atPath: bundled.path) {
            return bundled.path
        }
        return nil
    }

    public func preparePayload() throws {
        // Direct bundle boot: bypass Application Support caching to prevent stale cache lockouts
    }
}
