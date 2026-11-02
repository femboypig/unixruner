import XCTest
@testable import unixruner

final class QEMUArgumentsTests: XCTestCase {
    func testARM64ArgumentGeneration() {
        let config = VMConfig(
            name: "Alpine Test",
            architecture: .arm64,
            memoryMB: 512,
            cpuCount: 1,
            kernelPath: "/path/to/Image",
            initrdPath: "/path/to/initramfs.cpio.gz",
            cmdline: "console=ttyAMA0 earlycon panic=1",
            drivePath: "/path/to/disk.qcow2",
            serialPort: 4444
        )

        let args = QEMUArguments.build(for: config)

        XCTAssertEqual(args.first, "qemu-system-aarch64")
        XCTAssertTrue(args.contains("-M"))
        XCTAssertEqual(args[args.firstIndex(of: "-M")! + 1], "virt,highmem=off")
        XCTAssertTrue(args.contains("-accel"))
        XCTAssertEqual(args[args.firstIndex(of: "-accel")! + 1], "tcg,tb-size=128")
        XCTAssertTrue(args.contains("-cpu"))
        XCTAssertEqual(args[args.firstIndex(of: "-cpu")! + 1], "cortex-a57")
        XCTAssertTrue(args.contains("-m"))
        XCTAssertEqual(args[args.firstIndex(of: "-m")! + 1], "512M")
        XCTAssertTrue(args.contains("-smp"))
        XCTAssertEqual(args[args.firstIndex(of: "-smp")! + 1], "1")
        XCTAssertTrue(args.contains("-kernel"))
        XCTAssertEqual(args[args.firstIndex(of: "-kernel")! + 1], "/path/to/Image")
        XCTAssertTrue(args.contains("-initrd"))
        XCTAssertEqual(args[args.firstIndex(of: "-initrd")! + 1], "/path/to/initramfs.cpio.gz")
        XCTAssertTrue(args.contains("-append"))
        XCTAssertEqual(args[args.firstIndex(of: "-append")! + 1], "console=ttyAMA0 earlycon panic=1")
        XCTAssertTrue(args.contains("virtio-blk-pci,drive=hd0"))
        XCTAssertTrue(args.contains("virtio-net-pci,netdev=net0"))
        XCTAssertFalse(args.contains("virtio-blk-device,drive=hd0"))
        XCTAssertFalse(args.contains("virtio-net-device,netdev=net0"))
        XCTAssertTrue(args.contains("-nographic"))
        XCTAssertTrue(args.contains("socket,id=term,host=127.0.0.1,port=4444,server=on,wait=off"))
    }

    func testX86ArgumentGeneration() {
        let config = VMConfig(
            name: "x86 Test",
            architecture: .x86_64,
            memoryMB: 1024,
            cpuCount: 2,
            kernelPath: "/path/to/vmlinuz-x86",
            initrdPath: nil,
            cmdline: "console=ttyS0 panic=1",
            drivePath: "/path/to/disk.qcow2",
            serialPort: 5555
        )

        let args = QEMUArguments.build(for: config, biosDirectory: "/opt/qemu/roms")

        XCTAssertEqual(args.first, "qemu-system-x86_64")
        XCTAssertTrue(args.contains("-L"))
        XCTAssertEqual(args[args.firstIndex(of: "-L")! + 1], "/opt/qemu/roms")
        XCTAssertTrue(args.contains("-M"))
        XCTAssertEqual(args[args.firstIndex(of: "-M")! + 1], "pc")
        XCTAssertTrue(args.contains("-accel"))
        XCTAssertEqual(args[args.firstIndex(of: "-accel")! + 1], "tcg,tb-size=128")
        XCTAssertTrue(args.contains("-cpu"))
        XCTAssertEqual(args[args.firstIndex(of: "-cpu")! + 1], "qemu64")
        XCTAssertTrue(args.contains("-m"))
        XCTAssertEqual(args[args.firstIndex(of: "-m")! + 1], "1024M")
        XCTAssertTrue(args.contains("virtio-blk-pci,drive=hd0"))
        XCTAssertTrue(args.contains("virtio-net-pci,netdev=net0"))
        XCTAssertFalse(args.contains("-initrd"))
    }
}
