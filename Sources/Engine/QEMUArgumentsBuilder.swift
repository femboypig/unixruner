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
        // Setting tb-size to 128MB keeps JIT cache lean and prevents Jetsam memory kills on iOS.
        // split-wx=on enables dual mirror mapping (RW + RX) via mach_vm_remap, bypassing iOS kernel W^X restrictions!
        args.append(contentsOf: ["-accel", "tcg,tb-size=128,split-wx=on"])

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
            let driveArg = "file=\(diskURL.path),if=none,id=drive0,format=\(config.diskFormat.qemuDriver),cache=writethrough"
            args.append(contentsOf: ["-drive", driveArg])
            args.append(contentsOf: ["-device", "virtio-blk-pci,drive=drive0"])
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

        // Direct Kernel Boot (bypasses UEFI, cold boot in 0.5 sec)
        if let kernel = kernelURL {
            args.append(contentsOf: ["-kernel", kernel.path])
            if let initrd = initrdURL {
                args.append(contentsOf: ["-initrd", initrd.path])
            }
            if !config.extraBootArgs.isEmpty {
                args.append(contentsOf: ["-append", config.extraBootArgs])
            }
        } else {
            // Firmware/BIOS boot for cloud disk images (Alpine Cloud, Debian, Ubuntu, etc.)
            let romDir = Bundle.main.resourceURL?.appendingPathComponent("qemu")
            let vmDir = diskURL.deletingLastPathComponent()

            if config.architecture == .arm64 {
                let codeFile = romDir?.appendingPathComponent("edk2-aarch64-code.fd")
                let varsFile = ensureEFIVars(for: vmDir, romDir: romDir, architecture: .arm64)

                if let code = codeFile, FileManager.default.fileExists(atPath: code.path),
                   let vars = varsFile, FileManager.default.fileExists(atPath: vars.path) {
                    // Standard QEMU / UTM PFlash mapping for EDK2 AArch64
                    args.append(contentsOf: ["-drive", "if=pflash,format=raw,unit=0,file=\(code.path),readonly=on"])
                    args.append(contentsOf: ["-drive", "if=pflash,format=raw,unit=1,file=\(vars.path)"])
                } else if let code = codeFile, FileManager.default.fileExists(atPath: code.path) {
                    args.append(contentsOf: ["-bios", code.path])
                } else {
                    args.append(contentsOf: ["-bios", "edk2-aarch64-code.fd"])
                }
            } else {
                // AMD64 / x86_64: SeaBIOS for BIOS boot
                let biosName = "bios-256k.bin"
                if let biosFile = romDir?.appendingPathComponent(biosName),
                   FileManager.default.fileExists(atPath: biosFile.path) {
                    args.append(contentsOf: ["-bios", biosFile.path])
                } else {
                    args.append(contentsOf: ["-bios", biosName])
                }
            }
        }

        return args
    }

    /// Prepares per-VM NVRAM variable storage for UEFI firmware
    public static func ensureEFIVars(for vmDirectory: URL, romDir: URL?, architecture: Architecture) -> URL? {
        let varsName = "efi_vars.fd"
        let destURL = vmDirectory.appendingPathComponent(varsName)
        if FileManager.default.fileExists(atPath: destURL.path) {
            return destURL
        }

        guard let romDir = romDir else { return nil }
        let templateName = (architecture == .arm64) ? "edk2-arm-vars.fd" : "edk2-i386-vars.fd"
        let templateURL = romDir.appendingPathComponent(templateName)
        guard FileManager.default.fileExists(atPath: templateURL.path) else {
            return nil
        }

        do {
            try FileManager.default.copyItem(at: templateURL, to: destURL)
            AppLogger.shared.log("Created per-VM EFI NVRAM variables from \(templateName)", level: .engine)
            return destURL
        } catch {
            AppLogger.shared.log("Failed to copy EFI NVRAM template: \(error.localizedDescription)", level: .error)
            return nil
        }
    }
}
