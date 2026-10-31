import XCTest
@testable import unixruner

final class QEMUArgumentsTests: XCTestCase {
    func testARM64ArgumentGeneration() {
        let config = VMConfig(
            name: "Alpine Test",
            architecture: .arm64,
            memoryMB: 512,
            cpuCount: 1,
            kernelPath: "/path/to/vmlinuz-virt",
            initrdPath: "/path/to/initramfs-virt",
            cmdline: "console=ttyAMA0 earlycon",
            serialPort: 4444
        )

        let args = QEMUArguments.build(for: config)

        XCTAssertTrue(args.contains("-M"))
        XCTAssertEqual(args[args.firstIndex(of: "-M")! + 1], "virt")
        XCTAssertTrue(args.contains("-cpu"))
        XCTAssertEqual(args[args.firstIndex(of: "-cpu")! + 1], "cortex-a57")
        XCTAssertTrue(args.contains("-m"))
        XCTAssertEqual(args[args.firstIndex(of: "-m")! + 1], "512M")
        XCTAssertTrue(args.contains("-kernel"))
        XCTAssertEqual(args[args.firstIndex(of: "-kernel")! + 1], "/path/to/vmlinuz-virt")
        XCTAssertTrue(args.contains("-initrd"))
        XCTAssertEqual(args[args.firstIndex(of: "-initrd")! + 1], "/path/to/initramfs-virt")
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
            cmdline: "console=ttyS0",
            serialPort: 5555
        )

        let args = QEMUArguments.build(for: config, biosDirectory: "/opt/qemu/roms")

        XCTAssertTrue(args.contains("-L"))
        XCTAssertEqual(args[args.firstIndex(of: "-L")! + 1], "/opt/qemu/roms")
        XCTAssertTrue(args.contains("-M"))
        XCTAssertEqual(args[args.firstIndex(of: "-M")! + 1], "pc")
        XCTAssertTrue(args.contains("-cpu"))
        XCTAssertEqual(args[args.firstIndex(of: "-cpu")! + 1], "qemu64")
        XCTAssertTrue(args.contains("-m"))
        XCTAssertEqual(args[args.firstIndex(of: "-m")! + 1], "1024M")
        XCTAssertFalse(args.contains("-initrd"))
    }
}
