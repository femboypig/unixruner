import XCTest
@testable import unixruner

final class DiskManagerTests: XCTestCase {
    var tempDirectory: URL!

    override func setUp() {
        super.setUp()
        tempDirectory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try? FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempDirectory)
        super.tearDown()
    }

    func testQCOW2AllocationProducesValidCompliantHeader() throws {
        let diskURL = tempDirectory.appendingPathComponent("test.qcow2")
        let virtualSizeBytes: Int64 = 8 * 1024 * 1024 * 1024 // 8 GB

        try DiskManager.shared.allocateEmptyDisk(at: diskURL, sizeBytes: virtualSizeBytes, format: .qcow2)

        XCTAssertTrue(FileManager.default.fileExists(atPath: diskURL.path))
        let data = try Data(contentsOf: diskURL)

        // Must be exactly 4 clusters = 262,144 bytes
        XCTAssertEqual(data.count, 262144, "QCOW2 image must have exactly 4 clusters allocated")

        data.withUnsafeBytes { raw in
            guard let base = raw.baseAddress else {
                XCTFail("Missing base address")
                return
            }

            // Magic 'QFI\xfb'
            let magic = base.load(as: UInt32.self).bigEndian
            XCTAssertEqual(magic, 0x514649FB, "Magic must be QFI\\xfb")

            // Version 3
            let version = base.load(fromByteOffset: 4, as: UInt32.self).bigEndian
            XCTAssertEqual(version, 3, "Version must be 3")

            // Cluster bits (16 = 64KB)
            let clusterBits = base.load(fromByteOffset: 20, as: UInt32.self).bigEndian
            XCTAssertEqual(clusterBits, 16)

            // Virtual disk size
            let size = base.load(fromByteOffset: 24, as: UInt64.self).bigEndian
            XCTAssertEqual(Int64(size), virtualSizeBytes)

            // L1 table offset (Cluster 3 = 196608)
            let l1Offset = base.load(fromByteOffset: 40, as: UInt64.self).bigEndian
            XCTAssertEqual(l1Offset, 196608)

            // Refcount table offset (Cluster 1 = 65536)
            let refOffset = base.load(fromByteOffset: 48, as: UInt64.self).bigEndian
            XCTAssertEqual(refOffset, 65536)

            // Refcount table clusters
            let refClusters = base.load(fromByteOffset: 56, as: UInt32.self).bigEndian
            XCTAssertEqual(refClusters, 1)

            // Header length
            let headerLen = base.load(fromByteOffset: 100, as: UInt32.self).bigEndian
            XCTAssertEqual(headerLen, 104)

            // Refcount table entry 0 points to Cluster 2 (131072)
            let refBlock0 = base.load(fromByteOffset: 65536, as: UInt64.self).bigEndian
            XCTAssertEqual(refBlock0, 131072)

            // First 4 clusters must have refcount = 1
            for i in 0..<4 {
                let ref = base.load(fromByteOffset: 131072 + (i * 2), as: UInt16.self).bigEndian
                XCTAssertEqual(ref, 1, "Cluster \(i) must have refcount 1")
            }
        }
    }

    func testRawAllocationProducesSparseFile() throws {
        let diskURL = tempDirectory.appendingPathComponent("test.raw")
        let virtualSizeBytes: Int64 = 4 * 1024 * 1024 * 1024 // 4 GB

        try DiskManager.shared.allocateEmptyDisk(at: diskURL, sizeBytes: virtualSizeBytes, format: .raw)

        XCTAssertTrue(FileManager.default.fileExists(atPath: diskURL.path))
        let attrs = try FileManager.default.attributesOfItem(atPath: diskURL.path)
        let fileSize = attrs[.size] as? Int64
        XCTAssertEqual(fileSize, virtualSizeBytes)
    }
}
