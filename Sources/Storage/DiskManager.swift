import Foundation
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
            // Compliant QCOW2 v3 image structure (4 clusters = 256 KB):
            // Cluster 0: Header (104 bytes + zero padding to 64KB)
            // Cluster 1: Refcount Table (1 cluster, points to Cluster 2)
            // Cluster 2: Refcount Block 0 (records 4 allocated clusters: 0, 1, 2, 3)
            // Cluster 3: L1 Table (1 cluster, all zeroes for unallocated guest space)
            let clusterBits: UInt32 = 16
            let clusterSize = 1 << clusterBits // 65,536 bytes
            let l2EntriesPerTable = clusterSize / 8 // 8,192 entries
            let clusterCoverageBytes = Int64(l2EntriesPerTable) * Int64(clusterSize) // 512 MB per L2 table
            let l1Entries = UInt32((sizeBytes + clusterCoverageBytes - 1) / clusterCoverageBytes)

            var data = Data(count: 4 * clusterSize)
            data.withUnsafeMutableBytes { (rawPtr: UnsafeMutableRawBufferPointer) in
                guard let base = rawPtr.baseAddress else { return }

                func writeU32(_ val: UInt32, at offset: Int) {
                    var be = val.bigEndian
                    memcpy(base + offset, &be, 4)
                }
                func writeU64(_ val: UInt64, at offset: Int) {
                    var be = val.bigEndian
                    memcpy(base + offset, &be, 8)
                }

                writeU32(0x514649FB, at: 0) // Magic 'QFI\xfb'
                writeU32(3, at: 4)          // Version 3
                writeU64(0, at: 8)          // Backing file offset
                writeU32(0, at: 16)         // Backing file size
                writeU32(clusterBits, at: 20) // Cluster bits (16 = 64KB)
                writeU64(UInt64(sizeBytes), at: 24) // Virtual disk size
                writeU32(0, at: 32)         // Crypt method
                writeU32(l1Entries, at: 36) // L1 table entries
                writeU64(UInt64(3 * clusterSize), at: 40) // L1 table offset (Cluster 3)
                writeU64(UInt64(1 * clusterSize), at: 48) // Refcount table offset (Cluster 1)
                writeU32(1, at: 56)         // Refcount table clusters
                writeU32(0, at: 60)         // Number of snapshots
                writeU64(0, at: 64)         // Snapshots offset
                writeU64(0, at: 72)         // Incompatible features
                writeU64(0, at: 80)         // Compatible features
                writeU64(0, at: 88)         // Autoclear features
                writeU32(4, at: 96)         // Refcount order (2^4 = 16 bits)
                writeU32(104, at: 100)      // Header length

                // Cluster 1: Refcount Table entry 0 points to Cluster 2
                writeU64(UInt64(2 * clusterSize), at: clusterSize)

                // Cluster 2: Refcount Block 0 (clusters 0, 1, 2, 3 have refcount = 1)
                let refBlockOffset = 2 * clusterSize
                for i in 0..<4 {
                    var one: UInt16 = UInt16(1).bigEndian
                    memcpy(base + refBlockOffset + (i * 2), &one, 2)
                }
            }

            try data.write(to: url)
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
