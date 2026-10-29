import Foundation

public final class DiskManager {
    public static let shared = DiskManager()
    private let fileManager = FileManager.default

    private init() {}

    public var rootDirectory: URL {
        let docs = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first!
        let vmsDir = docs.appendingPathComponent("VMs", isDirectory: true)
        if !fileManager.fileExists(atPath: vmsDir.path) {
            try? fileManager.createDirectory(at: vmsDir, withIntermediateDirectories: true)
        }
        return vmsDir
    }

    public func directory(for vmId: UUID) -> URL {
        let dir = rootDirectory.appendingPathComponent(vmId.uuidString, isDirectory: true)
        if !fileManager.fileExists(atPath: dir.path) {
            try? fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        return dir
    }

    public func diskPath(for vmId: UUID, name: String = "disk.qcow2") -> String {
        directory(for: vmId).appendingPathComponent(name).path
    }

    public func deleteVMData(for vmId: UUID) {
        let dir = directory(for: vmId)
        try? fileManager.removeItem(at: dir)
    }
}
