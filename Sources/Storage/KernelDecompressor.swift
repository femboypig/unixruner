import Foundation
import zlib

public enum KernelDecompressor {
    /// Inspects the kernel file. If it is an EFI zboot container (e.g. Alpine netboot vmlinuz-virt),
    /// extracts and decompresses the embedded gzip payload to a raw ARM64 Linux Image.
    public static func prepareKernelIfNeeded(at url: URL) -> URL {
        guard FileManager.default.fileExists(atPath: url.path) else { return url }
        guard let handle = try? FileHandle(forReadingFrom: url) else { return url }
        defer { try? handle.close() }

        // Read first 64 bytes to inspect kernel header
        guard let headerData = try? handle.read(upToCount: 64), headerData.count >= 48 else {
            return url
        }

        // Check if file is already a raw ARM64 Linux kernel Image:
        // Offset 0x38 must contain magic "ARM\x64" (0x644d5241)
        if headerData.count >= 60 {
            let magic = headerData.subdata(in: 0x38..<0x3C)
            if magic == Data([0x41, 0x52, 0x4D, 0x64]) {
                AppLogger.shared.log("Kernel is already a raw ARM64 Image (magic found at 0x38)", level: .engine)
                return url
            }
        }

        // Check for Linux EFI zboot image header:
        // Offset 0..3: MZ\0\0 (0x4D, 0x5A, 0x00, 0x00)
        // Offset 4..7: "zimg" (0x7A, 0x69, 0x6D, 0x67)
        let mz = headerData.subdata(in: 0..<4)
        let zimg = headerData.subdata(in: 4..<8)
        guard mz == Data([0x4D, 0x5A, 0x00, 0x00]),
              zimg == Data([0x7A, 0x69, 0x6D, 0x67]) else {
            return url
        }

        // Little-endian payload offset & payload size
        let payloadOffset = headerData.subdata(in: 8..<12).withUnsafeBytes { $0.load(as: UInt32.self) }
        let payloadSize = headerData.subdata(in: 12..<16).withUnsafeBytes { $0.load(as: UInt32.self) }

        // Verify compression type starts with "gzip"
        let compTypeBytes = headerData.subdata(in: 16..<20)
        guard compTypeBytes == Data([0x67, 0x7A, 0x69, 0x70]) else {
            AppLogger.shared.log("Detected zboot container with unsupported compression type", level: .warn)
            return url
        }

        let rawURL = url.deletingPathExtension().appendingPathExtension("raw-kernel")
        if FileManager.default.fileExists(atPath: rawURL.path),
           let attrs = try? FileManager.default.attributesOfItem(atPath: rawURL.path),
           let size = attrs[.size] as? UInt64, size > 1_000_000 {
            AppLogger.shared.log("Using cached decompressed raw kernel: \(rawURL.lastPathComponent) (\(size) bytes)", level: .engine)
            return rawURL
        }

        AppLogger.shared.log("Decompressing Linux EFI zboot container (\(payloadSize) bytes gzip payload)...", level: .engine)

        do {
            try handle.seek(toOffset: UInt64(payloadOffset))
            guard let compressedData = try handle.read(upToCount: Int(payloadSize)) else {
                AppLogger.shared.log("Failed to read zboot gzip payload from offset \(payloadOffset)", level: .error)
                return url
            }

            guard let decompressed = decompressGzip(compressedData) else {
                AppLogger.shared.log("zlib decompression failed for zboot kernel payload", level: .error)
                return url
            }

            // Verify decompressed kernel has ARM64 magic
            if decompressed.count > 0x40 {
                let magic = decompressed.subdata(in: 0x38..<0x3C)
                if magic == Data([0x41, 0x52, 0x4D, 0x64]) {
                    AppLogger.shared.log("Verified decompressed kernel magic ARM64 at offset 0x38", level: .engine)
                }
            }

            try decompressed.write(to: rawURL, options: .atomic)
            AppLogger.shared.log("Wrote raw bootable ARM64 kernel to \(rawURL.path) (\(decompressed.count) bytes)", level: .engine)
            return rawURL
        } catch {
            AppLogger.shared.log("Error processing zboot kernel: \(error.localizedDescription)", level: .error)
            return url
        }
    }

    /// Decompresses RFC 1952 GZIP data using system zlib
    public static func decompressGzip(_ data: Data) -> Data? {
        guard !data.isEmpty else { return nil }

        var stream = z_stream()
        // 16 + MAX_WBITS (15) = 31 requests gzip stream decoding in zlib
        let initStatus = inflateInit2_(&stream, 31, zlibVersion(), Int32(MemoryLayout<z_stream>.size))
        guard initStatus == Z_OK else {
            return nil
        }
        defer { inflateEnd(&stream) }

        var decompressed = Data()
        let chunkSize = 64 * 1024
        var chunk = [UInt8](repeating: 0, count: chunkSize)

        data.withUnsafeBytes { rawBuffer in
            guard let baseAddress = rawBuffer.bindMemory(to: UInt8.self).baseAddress else { return }
            stream.next_in = UnsafeMutablePointer<UInt8>(mutating: baseAddress)
            stream.avail_in = uInt(data.count)

            while stream.avail_in > 0 {
                chunk.withUnsafeMutableBufferPointer { chunkBuffer in
                    stream.next_out = chunkBuffer.baseAddress
                    stream.avail_out = uInt(chunkSize)

                    let status = inflate(&stream, Z_NO_FLUSH)
                    let produced = chunkSize - Int(stream.avail_out)
                    if produced > 0, let outBase = chunkBuffer.baseAddress {
                        decompressed.append(outBase, count: produced)
                    }
                    if status == Z_STREAM_END {
                        stream.avail_in = 0
                    }
                }
            }
        }

        return decompressed.isEmpty ? nil : decompressed
    }
}
