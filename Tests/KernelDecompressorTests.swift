import XCTest
import zlib
@testable import unixruner

final class KernelDecompressorTests: XCTestCase {
    func testRawARM64ImageIsNotModified() throws {
        let tempURL = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("test_raw_kernel_\(UUID().uuidString)")
        var data = Data(repeating: 0, count: 128)
        // Put ARM\x64 magic at offset 0x38
        data[0x38] = 0x41
        data[0x39] = 0x52
        data[0x3A] = 0x4D
        data[0x3B] = 0x64
        try data.write(to: tempURL)
        defer { try? FileManager.default.removeItem(at: tempURL) }

        let resultURL = KernelDecompressor.prepareKernelIfNeeded(at: tempURL)
        XCTAssertEqual(resultURL.path, tempURL.path)
    }

    func testZbootKernelDecompression() throws {
        let tempURL = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("vmlinuz_zboot_\(UUID().uuidString)")
        defer {
            try? FileManager.default.removeItem(at: tempURL)
            let rawURL = tempURL.deletingPathExtension().appendingPathExtension("raw-kernel")
            try? FileManager.default.removeItem(at: rawURL)
        }

        // Create an uncompressed dummy ARM64 kernel
        var rawKernel = Data(repeating: 0x90, count: 256)
        rawKernel[0x38] = 0x41
        rawKernel[0x39] = 0x52
        rawKernel[0x3A] = 0x4D
        rawKernel[0x3B] = 0x64

        // Compress rawKernel with gzip
        guard let gzippedPayload = gzipCompress(rawKernel) else {
            XCTFail("Failed to gzip compress test kernel")
            return
        }

        // Build EFI zboot header
        var zbootFile = Data()
        // 0..3: MZ\0\0
        zbootFile.append(contentsOf: [0x4D, 0x5A, 0x00, 0x00])
        // 4..7: zimg
        zbootFile.append(contentsOf: [0x7A, 0x69, 0x6D, 0x67])
        // 8..11: payload offset
        var payloadOffset: UInt32 = 64
        zbootFile.append(Data(bytes: &payloadOffset, count: 4))
        // 12..15: payload size
        var payloadSize: UInt32 = UInt32(gzippedPayload.count)
        zbootFile.append(Data(bytes: &payloadSize, count: 4))
        // 16..19: "gzip"
        zbootFile.append(contentsOf: [0x67, 0x7A, 0x69, 0x70])
        // Pad to offset 64
        zbootFile.append(Data(repeating: 0, count: 64 - zbootFile.count))
        // Append gzipped payload
        zbootFile.append(gzippedPayload)

        try zbootFile.write(to: tempURL)

        let resultURL = KernelDecompressor.prepareKernelIfNeeded(at: tempURL)
        XCTAssertNotEqual(resultURL.path, tempURL.path)
        XCTAssertTrue(FileManager.default.fileExists(atPath: resultURL.path))

        let decompressedData = try Data(contentsOf: resultURL)
        XCTAssertEqual(decompressedData.count, rawKernel.count)
        XCTAssertEqual(decompressedData[0x38], 0x41)
        XCTAssertEqual(decompressedData[0x39], 0x52)
        XCTAssertEqual(decompressedData[0x3A], 0x4D)
        XCTAssertEqual(decompressedData[0x3B], 0x64)
    }

    private func gzipCompress(_ data: Data) -> Data? {
        var stream = z_stream()
        guard deflateInit2_(&stream, Z_DEFAULT_COMPRESSION, Z_DEFLATED, 31, 8, Z_DEFAULT_STRATEGY, zlibVersion(), Int32(MemoryLayout<z_stream>.size)) == Z_OK else {
            return nil
        }
        defer { deflateEnd(&stream) }

        var compressed = Data()
        let bufferSize = 16384
        var buffer = [UInt8](repeating: 0, count: bufferSize)

        data.withUnsafeBytes { rawBuffer in
            guard let baseAddress = rawBuffer.bindMemory(to: UInt8.self).baseAddress else { return }
            stream.next_in = UnsafeMutablePointer<UInt8>(mutating: baseAddress)
            stream.avail_in = uInt(data.count)

            while stream.avail_in > 0 || stream.avail_out == 0 {
                buffer.withUnsafeMutableBufferPointer { chunkBuffer in
                    stream.next_out = chunkBuffer.baseAddress
                    stream.avail_out = uInt(bufferSize)

                    _ = deflate(&stream, Z_FINISH)
                    let written = bufferSize - Int(stream.avail_out)
                    if written > 0, let outBase = chunkBuffer.baseAddress {
                        compressed.append(outBase, count: written)
                    }
                }
            }
        }
        return compressed
    }
}
