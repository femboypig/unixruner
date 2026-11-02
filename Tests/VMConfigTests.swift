import XCTest
@testable import unixruner

final class VMConfigTests: XCTestCase {
    func testDefaultAlpineConfig() {
        let config = VMConfig.defaultAlpine(kernelPath: "/alpine/Image", initrdPath: "/alpine/initramfs.cpio.gz")
        XCTAssertEqual(config.name, "Alpine Linux")
        XCTAssertEqual(config.architecture, .arm64)
        XCTAssertEqual(config.memoryMB, 512)
        XCTAssertEqual(config.cpuCount, 1)
        XCTAssertEqual(config.kernelPath, "/alpine/Image")
        XCTAssertEqual(config.initrdPath, "/alpine/initramfs.cpio.gz")
        XCTAssertEqual(config.cmdline, "console=ttyAMA0 earlycon panic=1")
        XCTAssertEqual(config.serialPort, 4444)
    }

    func testCodableSerialization() throws {
        let original = VMConfig(
            name: "Custom",
            architecture: .x86_64,
            memoryMB: 256,
            cpuCount: 1,
            kernelPath: "/boot/vmlinuz",
            initrdPath: nil,
            cmdline: "quiet",
            serialPort: 1234
        )

        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(VMConfig.self, from: data)

        XCTAssertEqual(original.id, decoded.id)
        XCTAssertEqual(original.name, decoded.name)
        XCTAssertEqual(original.architecture, decoded.architecture)
        XCTAssertEqual(original.memoryMB, decoded.memoryMB)
        XCTAssertEqual(original.cpuCount, decoded.cpuCount)
        XCTAssertEqual(original.kernelPath, decoded.kernelPath)
        XCTAssertEqual(original.initrdPath, decoded.initrdPath)
        XCTAssertEqual(original.cmdline, decoded.cmdline)
        XCTAssertEqual(original.serialPort, decoded.serialPort)
    }
}
