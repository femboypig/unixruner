import Foundation

public struct QEMUArguments {
    public static func build(for config: VMConfig, biosDirectory: String? = nil) -> [String] {
        var args: [String] = [config.architecture.binaryName]

        if let bios = biosDirectory {
            args += ["-L", bios]
        } else {
            let romDir = Bundle.main.bundleURL.appendingPathComponent("qemu").path
            if FileManager.default.fileExists(atPath: romDir) {
                args += ["-L", romDir]
            }
        }

        switch config.architecture {
        case .arm64:
            args += [
                "-M", "virt",
                "-accel", "tcg,split-wx=on",
                "-cpu", "cortex-a57",
                "-m", "\(config.memoryMB)M",
                "-smp", "\(config.cpuCount)"
            ]
        case .x86_64:
            args += [
                "-M", "pc",
                "-accel", "tcg,split-wx=on",
                "-cpu", "qemu64",
                "-m", "\(config.memoryMB)M",
                "-smp", "\(config.cpuCount)"
            ]
        }

        // Direct kernel boot
        if let kernel = config.kernelPath, !kernel.isEmpty {
            args += ["-kernel", kernel]
        }
        if let initrd = config.initrdPath, !initrd.isEmpty {
            args += ["-initrd", initrd]
        }
        if let cmdline = config.cmdline, !cmdline.isEmpty {
            args += ["-append", cmdline]
        }

        // Attached drive
        if let drive = config.drivePath, !drive.isEmpty {
            args += [
                "-drive", "file=\(drive),if=none,id=hd0,format=qcow2",
                "-device", "virtio-blk-pci,drive=hd0"
            ]
        }

        // Headless serial console via local TCP socket
        args += [
            "-nographic",
            "-chardev", "socket,id=term,host=127.0.0.1,port=\(config.serialPort),server=on,wait=off",
            "-serial", "chardev:term"
        ]

        return args
    }
}
