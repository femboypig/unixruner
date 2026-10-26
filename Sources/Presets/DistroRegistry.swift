import Foundation
public final class DistroRegistry {
    public static let shared = DistroRegistry()

    public private(set) var presets: [DistroPreset]

    public init() {
        self.presets = [
            DistroRegistry.alpinePreset,
            DistroRegistry.debianPreset,
            DistroRegistry.ubuntuPreset,
            DistroRegistry.archPreset,
            DistroRegistry.voidPreset
        ]
    }

    public func preset(for id: String) -> DistroPreset? {
        presets.first { $0.id == id }
    }

    // MARK: - Official Always-Fresh Presets

    public static let alpinePreset = DistroPreset(
        id: "alpine-standard",
        name: "Alpine Linux",
        tag: "Recommended • 8 MB",
        summary: "Ultra-lightweight security-oriented Linux. Instant boot, minimal memory footprint.",
        packageManager: "apk",
        defaultUser: "root",
        defaultPassword: nil,
        bootMethod: .directKernel,
        recommendedMemoryMB: 512,
        recommendedCores: 2,
        recommendedDiskBytes: 4 * 1024 * 1024 * 1024,
        specs: [
            .arm64: DistroArchitectureSpec(
                architecture: .arm64,
                kernelAsset: DistroAsset(
                    url: URL(string: "https://dl-cdn.alpinelinux.org/alpine/latest-stable/releases/aarch64/netboot/vmlinuz-virt")!,
                    filename: "vmlinuz-alpine-arm64"
                ),
                initrdAsset: DistroAsset(
                    url: URL(string: "https://dl-cdn.alpinelinux.org/alpine/latest-stable/releases/aarch64/netboot/initramfs-virt")!,
                    filename: "initramfs-alpine-arm64"
                ),
                diskAsset: DistroAsset(
                    url: URL(string: "https://dl-cdn.alpinelinux.org/alpine/latest-stable/releases/aarch64/alpine-minirootfs-latest-aarch64.tar.gz")!,
                    filename: "rootfs-alpine-arm64.tar.gz"
                ),
                defaultBootArgs: "console=ttyAMA0 modules=loop,squashfs,virtio_blk,virtio_net quiet"
            ),
            .amd64: DistroArchitectureSpec(
                architecture: .amd64,
                kernelAsset: DistroAsset(
                    url: URL(string: "https://dl-cdn.alpinelinux.org/alpine/latest-stable/releases/x86_64/netboot/vmlinuz-virt")!,
                    filename: "vmlinuz-alpine-amd64"
                ),
                initrdAsset: DistroAsset(
                    url: URL(string: "https://dl-cdn.alpinelinux.org/alpine/latest-stable/releases/x86_64/netboot/initramfs-virt")!,
                    filename: "initramfs-alpine-amd64"
                ),
                diskAsset: DistroAsset(
                    url: URL(string: "https://dl-cdn.alpinelinux.org/alpine/latest-stable/releases/x86_64/alpine-minirootfs-latest-x86_64.tar.gz")!,
                    filename: "rootfs-alpine-amd64.tar.gz"
                ),
                defaultBootArgs: "console=ttyS0 modules=loop,squashfs,virtio_blk,virtio_net quiet"
            )
        ]
    )

    public static let debianPreset = DistroPreset(
        id: "debian-cloud",
        name: "Debian 12 Bookworm",
        tag: "Stable • Standard",
        summary: "Universal operating system with broad package compatibility and robust APT repository.",
        packageManager: "apt",
        defaultUser: "debian",
        defaultPassword: nil,
        bootMethod: .cloudImage,
        recommendedMemoryMB: 1024,
        recommendedCores: 2,
        recommendedDiskBytes: 8 * 1024 * 1024 * 1024,
        specs: [
            .arm64: DistroArchitectureSpec(
                architecture: .arm64,
                diskAsset: DistroAsset(
                    url: URL(string: "https://cloud.debian.org/images/cloud/bookworm/latest/debian-12-genericcloud-arm64.raw")!,
                    filename: "debian-12-cloud-arm64.raw"
                ),
                defaultBootArgs: "console=ttyAMA0 root=/dev/vda1 rw quiet"
            ),
            .amd64: DistroArchitectureSpec(
                architecture: .amd64,
                diskAsset: DistroAsset(
                    url: URL(string: "https://cloud.debian.org/images/cloud/bookworm/latest/debian-12-genericcloud-amd64.raw")!,
                    filename: "debian-12-cloud-amd64.raw"
                ),
                defaultBootArgs: "console=ttyS0 root=/dev/vda1 rw quiet"
            )
        ]
    )

    public static let ubuntuPreset = DistroPreset(
        id: "ubuntu-minimal",
        name: "Ubuntu 24.04 LTS",
        tag: "Developer Favorite",
        summary: "Canonical official minimal cloud release with modern toolchains and Canonical APT repos.",
        packageManager: "apt",
        defaultUser: "ubuntu",
        defaultPassword: nil,
        bootMethod: .cloudImage,
        recommendedMemoryMB: 1536,
        recommendedCores: 2,
        recommendedDiskBytes: 10 * 1024 * 1024 * 1024,
        specs: [
            .arm64: DistroArchitectureSpec(
                architecture: .arm64,
                diskAsset: DistroAsset(
                    url: URL(string: "https://cloud-images.ubuntu.com/minimal/releases/noble/release/ubuntu-24.04-minimal-cloudimg-arm64.img")!,
                    filename: "ubuntu-24.04-minimal-arm64.img"
                ),
                defaultBootArgs: "console=ttyAMA0 root=/dev/vda1 rw quiet"
            ),
            .amd64: DistroArchitectureSpec(
                architecture: .amd64,
                diskAsset: DistroAsset(
                    url: URL(string: "https://cloud-images.ubuntu.com/minimal/releases/noble/release/ubuntu-24.04-minimal-cloudimg-amd64.img")!,
                    filename: "ubuntu-24.04-minimal-amd64.img"
                ),
                defaultBootArgs: "console=ttyS0 root=/dev/vda1 rw quiet"
            )
        ]
    )

    public static let archPreset = DistroPreset(
        id: "arch-linux",
        name: "Arch Linux",
        tag: "Bleeding Edge",
        summary: "Rolling-release Linux distribution offering the latest software packages via pacman.",
        packageManager: "pacman",
        defaultUser: "alarm",
        defaultPassword: "alarm",
        bootMethod: .cloudImage,
        recommendedMemoryMB: 1024,
        recommendedCores: 2,
        recommendedDiskBytes: 8 * 1024 * 1024 * 1024,
        specs: [
            .arm64: DistroArchitectureSpec(
                architecture: .arm64,
                diskAsset: DistroAsset(
                    url: URL(string: "http://os.archlinuxarm.org/os/ArchLinuxARM-aarch64-latest.tar.gz")!,
                    filename: "archlinuxarm-aarch64-latest.tar.gz"
                ),
                defaultBootArgs: "console=ttyAMA0 root=/dev/vda rw quiet"
            )
        ]
    )

    public static let voidPreset = DistroPreset(
        id: "void-linux",
        name: "Void Linux (musl)",
        tag: "Zero Systemd • Lightweight",
        summary: "Independent distribution with runit init and XBPS package manager.",
        packageManager: "xbps",
        defaultUser: "root",
        defaultPassword: "voidlinux",
        bootMethod: .cloudImage,
        recommendedMemoryMB: 768,
        recommendedCores: 2,
        recommendedDiskBytes: 6 * 1024 * 1024 * 1024,
        specs: [
            .arm64: DistroArchitectureSpec(
                architecture: .arm64,
                diskAsset: DistroAsset(
                    url: URL(string: "https://repo-default.voidlinux.org/live/current/void-aarch64-musl-ROOTFS.tar.xz")!,
                    filename: "void-aarch64-musl-ROOTFS.tar.xz"
                ),
                defaultBootArgs: "console=ttyAMA0 root=/dev/vda rw quiet"
            )
        ]
    )
}
