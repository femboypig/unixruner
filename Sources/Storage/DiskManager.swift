import Foundation
import Core

public final class DiskManager {
    public static let shared = DiskManager()

    private let fileManager = FileManager.default

    public var baseVMDirectory: URL {
        let paths = fileManager.urls(for: .documentDirectory, in: .userDomainMask)
        let dir = paths[0].appendingPathComponent("VMs", isDirectory: true)
        if !fileManager.fileExists(atPath: dir.path) {
            try? fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        return dir
    }

    public var sharedFolderDirectory: URL {
        let paths = fileManager.urls(for: .documentDirectory, in: .userDomainMask)
        let dir = paths[0].appendingPathComponent("Shared", isDirectory: true)
        if !fileManager.fileExists(atPath: dir.path) {
            try? fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        return dir
    }

    public func directory(for vmId: UUID) -> URL {
        let dir = baseVMDirectory.appendingPathComponent(vmId.uuidString, isDirectory: true)
        if !fileManager.fileExists(atPath: dir.path) {
            try? fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        return dir
    }

    public func diskURL(for vmId: UUID, filename: String) -> URL {
        directory(for: vmId).appendingPathComponent(filename)
    }

    public func allocateEmptyDisk(at url: URL, sizeBytes: Int64, format: DiskFormat) throws {
        if fileManager.fileExists(atPath: url.path) {
            try fileManager.removeItem(at: url)
        }

        switch format {
        case .raw:
            // Sparse raw file creation
            let fileDescriptor = open(url.path, O_RDWR | O_CREAT | O_TRUNC, 0o644)
            guard fileDescriptor >= 0 else {
                throw NSError(domain: "DiskManager", code: Int(errno), userInfo: [NSLocalizedDescriptionKey: "Failed to open raw disk file descriptor"])
            }
            defer { close(fileDescriptor) }

            // Seek to size - 1 and write a single zero byte to make it sparse
            if lseek(fileDescriptor, off_t(sizeBytes - 1), SEEK_SET) == -1 {
                throw NSError(domain: "DiskManager", code: Int(errno), userInfo: [NSLocalizedDescriptionKey: "Failed to lseek sparse raw disk"])
            }
            var zero: UInt8 = 0
            write(fileDescriptor, &zero, 1)

        case .qcow2:
            // Minimal initial QCOW2 header (Magic: QFI\xfb, Version: 3)
            var header = Data()
            header.append(contentsOf: [0x51, 0x46, 0x49, 0xfb]) // Magic
            header.append(contentsOf: [0x00, 0x00, 0x00, 0x03]) // Version 3
            header.append(contentsOf: [0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00]) // Backing file offset
            header.append(contentsOf: [0x00, 0x00, 0x00, 0x00]) // Backing file size
            header.append(contentsOf: [0x00, 0x00, 0x00, 0x10]) // Cluster bits (64 KB clusters, 16 bits)
            // Virtual disk size (big endian 64-bit)
            var bigEndianSize = sizeBytes.bigEndian
            withUnsafeBytes(of: &bigEndianSize) { header.append(contentsOf: $0) }
            // Pad out minimal header
            header.count = 512
            try header.write(to: url)
        }
    }

    public func deleteVMData(for vmId: UUID) throws {
        let dir = directory(for: vmId)
        if fileManager.fileExists(atPath: dir.path) {
            try fileManager.removeItem(at: dir)
        }
    }

    public func availableDeviceDiskSpaceBytes() -> Int64 {
        let values = try? baseVMDirectory.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
        return values?.volumeAvailableCapacityForImportantUsage ?? 0
    }
}
