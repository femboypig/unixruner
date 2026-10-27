import Foundation

public struct QEMUArguments {
    public static func build(for config: VMConfig, biosDirectory: String? = nil) -> [String] {
        var args: [String] = []

        if let bios = biosDirectory, !bios.isEmpty {
            args += ["-L", bios]
        }

        switch config.architecture {
        case .arm64:
            args += [
                "-M", "virt",
                "-cpu", "cortex-a57",
                "-m", "\(config.memoryMB)M",
                "-smp", "\(config.cpuCount)"
            ]
        case .x86_64:
            args += [
                "-M", "pc",
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
                "-device", config.architecture == .arm64 ? "virtio-blk-device,drive=hd0" : "virtio-blk-pci,drive=hd0"
            ]
        }

        // Headless serial console via local TCP socket
        args += [
            "-nographic",
            "-chardev", "socket,id=term,host=127.0.0.1,port=\(config.serialPort),server=on,wait=off",
            "-serial", "chardev:term"
        ]

        // User-mode networking (slirp)
        args += [
            "-netdev", "user,id=net0",
            "-device", config.architecture == .arm64 ? "virtio-net-device,netdev=net0" : "virtio-net-pci,netdev=net0"
        ]

        return args
    }
}
