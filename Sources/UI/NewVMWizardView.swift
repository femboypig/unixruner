import SwiftUI
public struct NewVMWizardView: View {
    @Environment(\.dismiss) private var dismiss

    public var onCreated: (VMConfig) -> Void

    @State private var selectedPreset: DistroPreset = DistroRegistry.alpinePreset
    @State private var vmName: String = "Alpine Linux"
    @State private var architecture: Architecture = .arm64
    @State private var diskFormat: DiskFormat = .qcow2
    @State private var memoryMB: Double = 1024
    @State private var cpuCores: Int = 2
    @State private var diskSizeGB: Double = 8

    @StateObject private var downloader = AssetDownloader()
    @State private var isInstalling = false
    @State private var installationStatus = ""

    public init(onCreated: @escaping (VMConfig) -> Void) {
        self.onCreated = onCreated
    }

    public var body: some View {
        NavigationStack {
            Form {
                presetSection
                configurationSection
                hardwareSection
                storageSection

                if isInstalling {
                    installationProgressSection
                }
            }
            .navigationTitle("New Linux Machine")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .disabled(isInstalling)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Install") { startInstallation() }
                        .disabled(isInstalling || vmName.isEmpty)
                }
            }
        }
    }

    private var presetSection: some View {
        Section("Choose Distribution") {
            Picker("Distribution", selection: $selectedPreset) {
                ForEach(DistroRegistry.shared.presets) { preset in
                    Text(preset.name).tag(preset)
                }
            }
            .pickerStyle(.menu)
            .onChange(of: selectedPreset) { _, newPreset in
                vmName = newPreset.name
                memoryMB = Double(newPreset.recommendedMemoryMB)
                cpuCores = newPreset.recommendedCores
            }

            Text(selectedPreset.summary)
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }

    private var configurationSection: some View {
        Section("Instance Name & Target") {
            TextField("Name", text: $vmName)

            Picker("Architecture", selection: $architecture) {
                ForEach(Architecture.allCases) { arch in
                    Label(arch.displayName, systemImage: arch.badgeIcon)
                        .tag(arch)
                }
            }

            Text(architecture.performanceNote)
                .font(.caption2)
                .foregroundColor(architecture == .arm64 ? .green : .orange)
        }
    }

    private var hardwareSection: some View {
        Section("Compute Allocation") {
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("Memory")
                    Spacer()
                    Text("\(Int(memoryMB)) MB")
                        .font(.subheadline.monospaced())
                }
                Slider(value: $memoryMB, in: 256...3072, step: 256)

                if memoryMB > 2048 {
                    Text("Warning: Allocations over 2GB may trigger iOS Jetsam termination on devices without increased-memory entitlement.")
                        .font(.caption2)
                        .foregroundColor(.orange)
                }
            }

            Stepper("CPU Cores: \(cpuCores)", value: $cpuCores, in: 1...4)
        }
    }

    private var storageSection: some View {
        Section("Virtual Disk") {
            Picker("Format", selection: $diskFormat) {
                ForEach(DiskFormat.allCases) { format in
                    Text(format.displayName).tag(format)
                }
            }
            Text(diskFormat.subtitle)
                .font(.caption2)
                .foregroundColor(.secondary)

            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("Virtual Size")
                    Spacer()
                    Text("\(Int(diskSizeGB)) GB")
                        .font(.subheadline.monospaced())
                }
                Slider(value: $diskSizeGB, in: 2...32, step: 2)
            }
        }
    }

    private var installationProgressSection: some View {
        Section("Installation Progress") {
            VStack(alignment: .leading, spacing: 8) {
                Text(installationStatus)
                    .font(.footnote)

                switch downloader.state {
                case .downloading(let progress, _, _):
                    ProgressView(value: progress)
                case .completed:
                    Label("Download Complete", systemImage: "checkmark.circle.fill")
                        .foregroundColor(.green)
                case .failed(let err):
                    Text("Failed: \(err)")
                        .foregroundColor(.red)
                case .idle:
                    ProgressView()
                }
            }
        }
    }

    private func startInstallation() {
        guard let spec = selectedPreset.specs[architecture] else {
            installationStatus = "Selected architecture not available for this distro"
            return
        }

        isInstalling = true
        let vmId = UUID()
        let diskFilename = "rootfs.\(diskFormat.fileExtension)"
        let targetDiskURL = DiskManager.shared.diskURL(for: vmId, filename: diskFilename)

        installationStatus = "Allocating virtual disk (\(diskFormat.rawValue))..."
        do {
            try DiskManager.shared.allocateEmptyDisk(
                at: targetDiskURL,
                sizeBytes: Int64(diskSizeGB * 1024 * 1024 * 1024),
                format: diskFormat
            )
        } catch {
            installationStatus = "Disk error: \(error.localizedDescription)"
            isInstalling = false
            return
        }

        // If direct kernel boot, download kernel & initrd
        if let kernelAsset = spec.kernelAsset {
            installationStatus = "Fetching Linux kernel..."
            let kernelDest = DiskManager.shared.diskURL(for: vmId, filename: kernelAsset.filename)
            downloader.download(from: kernelAsset.url, to: kernelDest) { result in
                switch result {
                case .success:
                    if let initrdAsset = spec.initrdAsset {
                        self.installationStatus = "Fetching initramfs..."
                        let initrdDest = DiskManager.shared.diskURL(for: vmId, filename: initrdAsset.filename)
                        self.downloader.download(from: initrdAsset.url, to: initrdDest) { initrdResult in
                            if case .success = initrdResult {
                                self.finalizeVM(vmId: vmId, spec: spec, kernelFile: kernelAsset.filename, initrdFile: initrdAsset.filename)
                            }
                        }
                    } else {
                        self.finalizeVM(vmId: vmId, spec: spec, kernelFile: kernelAsset.filename, initrdFile: nil)
                    }
                case .failure(let error):
                    self.installationStatus = "Kernel download failed: \(error.localizedDescription)"
                    self.isInstalling = false
                }
            }
        } else {
            // Cloud image boot: download image directly
            installationStatus = "Fetching cloud disk image..."
            downloader.download(from: spec.diskAsset.url, to: targetDiskURL) { result in
                switch result {
                case .success:
                    self.finalizeVM(vmId: vmId, spec: spec, kernelFile: nil, initrdFile: nil)
                case .failure(let error):
                    self.installationStatus = "Image download failed: \(error.localizedDescription)"
                    self.isInstalling = false
                }
            }
        }
    }

    private func finalizeVM(vmId: UUID, spec: DistroArchitectureSpec, kernelFile: String?, initrdFile: String?) {
        let config = VMConfig(
            id: vmId,
            name: vmName,
            architecture: architecture,
            diskFormat: diskFormat,
            memoryMB: Int(memoryMB),
            cpuCores: cpuCores,
            diskSizeBytes: Int64(diskSizeGB * 1024 * 1024 * 1024),
            kernelRelativePath: kernelFile,
            initrdRelativePath: initrdFile,
            diskRelativePath: "rootfs.\(diskFormat.fileExtension)",
            extraBootArgs: spec.defaultBootArgs
        )

        // Save VM to storage
        var vms: [VMConfig] = []
        let listURL = DiskManager.shared.baseVMDirectory.appendingPathComponent("vms.json")
        if let data = try? Data(contentsOf: listURL),
           let existing = try? JSONDecoder().decode([VMConfig].self, from: data) {
            vms = existing
        }
        vms.append(config)
        if let encoded = try? JSONEncoder().encode(vms) {
            try? encoded.write(to: listURL)
        }

        onCreated(config)
        dismiss()
    }
}
