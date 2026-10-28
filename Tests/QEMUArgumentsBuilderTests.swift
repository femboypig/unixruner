import XCTest
@testable import unixruner

final class QEMUArgumentsBuilderTests: XCTestCase {
    func testARM64ArgumentGeneration() {
        let config = VMConfig(
            id: UUID(),
            name: "Alpine Linux",
            architecture: .arm64,
            diskFormat: .qcow2,
            memoryMB: 1024,
            cpuCores: 2,
            diskSizeBytes: 8 * 1024 * 1024 * 1024,
            kernelRelativePath: "vmlinuz-alpine-arm64",
            initrdRelativePath: "initramfs-alpine-arm64",
            diskRelativePath: "rootfs.qcow2",
            extraBootArgs: "console=ttyAMA0 quiet",
            portMappings: [PortMapping(name: "SSH", hostPort: 2222, guestPort: 22, protocol: .tcp)],
            sharedFolderEnabled: true
        )

        let diskURL = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("test_rootfs.qcow2")
        FileManager.default.createFile(atPath: diskURL.path, contents: Data())
        defer { try? FileManager.default.removeItem(at: diskURL) }

        let kernelURL = URL(fileURLWithPath: "/tmp/vmlinuz")
        let initrdURL = URL(fileURLWithPath: "/tmp/initrd")
        let sharedURL = URL(fileURLWithPath: "/tmp/shared")

        let args = QEMUArgumentsBuilder.build(
            config: config,
            diskURL: diskURL,
            kernelURL: kernelURL,
            initrdURL: initrdURL,
            sharedFolderURL: sharedURL,
            socketPort: 54321
        )

        // Target binary
        XCTAssertEqual(args.first, "qemu-system-aarch64")

        // Microvm flags
        XCTAssertTrue(args.contains("-nographic"))
        XCTAssertTrue(args.contains("-nodefaults"))

        // Machine & CPU
        XCTAssertTrue(args.contains("virt,highmem=off"))
        XCTAssertTrue(args.contains("cortex-a57"))

        // TCG accelerator
        XCTAssertTrue(args.contains("tcg,tb-size=128,split-wx=on"))

        // Hardware sizing
        XCTAssertTrue(args.contains("1024M"))
        XCTAssertTrue(args.contains("2"))

        // Localhost serial socket chardev
        XCTAssertTrue(args.contains("-serial"))
        XCTAssertTrue(args.contains("chardev:term0"))
        XCTAssertTrue(args.contains("socket,id=term0,host=127.0.0.1,port=54321,server=on,wait=off"))

        // Compliant VirtIO block device
        XCTAssertTrue(args.contains("virtio-blk-pci,drive=drive0"))
        let driveArg = args.first(where: { $0.starts(with: "file=") })
        XCTAssertNotNil(driveArg)
        XCTAssertTrue(driveArg!.contains("if=none,id=drive0"))

        // Port forwarding
        let netdevArg = args.first(where: { $0.starts(with: "user,id=net0") })
        XCTAssertNotNil(netdevArg)
        XCTAssertTrue(netdevArg!.contains("hostfwd=tcp::2222-:22"))

        // Kernel args
        XCTAssertTrue(args.contains("console=ttyAMA0 quiet"))
    }

    func testAMD64ArgumentGeneration() {
        let config = VMConfig(
            name: "Debian AMD64",
            architecture: .amd64,
            memoryMB: 2048,
            cpuCores: 4
        )

        let diskURL = URL(fileURLWithPath: "/tmp/debian.raw")

        let args = QEMUArgumentsBuilder.build(
            config: config,
            diskURL: diskURL,
            kernelURL: nil,
            initrdURL: nil,
            sharedFolderURL: nil,
            socketPort: 12345
        )

        XCTAssertEqual(args.first, "qemu-system-x86_64")
        XCTAssertTrue(args.contains("q35"))
        XCTAssertTrue(args.contains("qemu64"))
        XCTAssertTrue(args.contains("2048M"))
        XCTAssertTrue(args.contains("4"))
    }

    func testFirmwareFallbackWhenKernelNil() {
        let config = VMConfig(
            name: "Debian ARM64",
            architecture: .arm64
        )
        let diskURL = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("test_vm_\(UUID().uuidString)/debian.qcow2")
        try? FileManager.default.createDirectory(at: diskURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: diskURL.deletingLastPathComponent()) }

        let args = QEMUArgumentsBuilder.build(
            config: config,
            diskURL: diskURL,
            kernelURL: nil,
            initrdURL: nil,
            sharedFolderURL: nil,
            socketPort: 12345
        )
        let hasPFlashOrBios = args.contains("-bios") || args.contains(where: { $0.contains("if=pflash") })
        XCTAssertTrue(hasPFlashOrBios)
        XCTAssertTrue(args.contains(where: { $0.contains("edk2-aarch64-code.fd") }))
    }

    func testEnsureEFIVarsCreation() throws {
        let tempVMDir = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("test_vm_vars_\(UUID().uuidString)")
        let tempROMDir = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("test_roms_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempVMDir, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: tempROMDir, withIntermediateDirectories: true)
        defer {
            try? FileManager.default.removeItem(at: tempVMDir)
            try? FileManager.default.removeItem(at: tempROMDir)
        }

        // Create dummy template vars
        let templateURL = tempROMDir.appendingPathComponent("edk2-arm-vars.fd")
        try Data(repeating: 0xFF, count: 1024).write(to: templateURL)

        let varsURL = QEMUArgumentsBuilder.ensureEFIVars(for: tempVMDir, romDir: tempROMDir, architecture: .arm64)
        XCTAssertNotNil(varsURL)
        XCTAssertTrue(FileManager.default.fileExists(atPath: varsURL!.path))

        let copiedData = try Data(contentsOf: varsURL!)
        XCTAssertEqual(copiedData.count, 1024)
        XCTAssertEqual(copiedData.first, 0xFF)
    }
}
