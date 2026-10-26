import Foundation

public struct QEMUArgumentsBuilder {
    public static func build(
        config: VMConfig,
        diskURL: URL,
        kernelURL: URL?,
        initrdURL: URL?,
        sharedFolderURL: URL?,
        socketPort: UInt16
    ) -> [String] {
        var args: [String] = []

        // QEMU binary name
        args.append(config.architecture.qemuTarget)

        // Machine & CPU
        switch config.architecture {
        case .arm64:
            // highmem=off is crucial on iOS to avoid allocating beyond the 36-bit address space
            args.append(contentsOf: ["-M", "virt,highmem=off"])
            args.append(contentsOf: ["-cpu", "cortex-a57"])
        case .amd64:
            args.append(contentsOf: ["-M", "q35"])
            args.append(contentsOf: ["-cpu", "qemu64"])
        }

        // TCG JIT Accelerator tuning
        // Setting tb-size to 128MB keeps JIT cache lean and prevents Jetsam memory kills on iOS
        args.append(contentsOf: ["-accel", "tcg,tb-size=128"])

        // Hardware allocation
        args.append(contentsOf: ["-smp", "\(config.cpuCores)"])
        args.append(contentsOf: ["-m", "\(config.memoryMB)M"])

        // Headless microvm flags: no VGA, no sound, no ACPI bloat
        args.append("-nographic")
        args.append("-nodefaults")

        // ROM / BIOS resource search directory
        if let romDir = Bundle.main.resourceURL?.appendingPathComponent("qemu"),
           FileManager.default.fileExists(atPath: romDir.path) {
            args.append(contentsOf: ["-L", romDir.path])
        }

        // Serial chardev attached to TCP localhost socket for SwiftTerm streaming
        args.append(contentsOf: ["-chardev", "socket,id=term0,host=127.0.0.1,port=\(socketPort),server=on,wait=off"])
        args.append(contentsOf: ["-serial", "chardev:term0"])

        // Storage Drive
        if FileManager.default.fileExists(atPath: diskURL.path) {
            let driveArg = "file=\(diskURL.path),format=\(config.diskFormat.qemuDriver),if=virtio,cache=writethrough,id=drive0"
            args.append(contentsOf: ["-drive", driveArg])
        }

        // User-mode networking (SLIRP) with port forwarding
        var netdevUser = "user,id=net0"
        for mapping in config.portMappings {
            netdevUser += ",hostfwd=\(mapping.qemuHostfwdRule)"
        }
        args.append(contentsOf: ["-netdev", netdevUser])
        args.append(contentsOf: ["-device", "virtio-net-pci,netdev=net0"])

        // 9P Shared folder for native iOS Files integration
        if config.sharedFolderEnabled, let sharedURL = sharedFolderURL {
            let fsdevArg = "local,id=shared0,path=\(sharedURL.path),security_model=none"
            args.append(contentsOf: ["-fsdev", fsdevArg])
            args.append(contentsOf: ["-device", "virtio-9p-pci,fsdev=shared0,mount_tag=host_share"])
        }

        // Direct Kernel Boot (bypasses UEFI, cold boot in 1-2 sec)
        if let kernel = kernelURL, FileManager.default.fileExists(atPath: kernel.path) {
            args.append(contentsOf: ["-kernel", kernel.path])
        }
        if let initrd = initrdURL, FileManager.default.fileExists(atPath: initrd.path) {
            args.append(contentsOf: ["-initrd", initrd.path])
        }
        if !config.extraBootArgs.isEmpty {
            args.append(contentsOf: ["-append", config.extraBootArgs])
        }

        return args
    }
}
