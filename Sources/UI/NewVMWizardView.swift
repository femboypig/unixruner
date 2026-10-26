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
    @State private var isHUDVisible = false
    @State private var installationStatus = ""
    @State private var errorMessage: String?

    public init(onCreated: @escaping (VMConfig) -> Void) {
        self.onCreated = onCreated
    }

    public var body: some View {
        ZStack {
            NavigationStack {
                Form {
                    presetSection
                    configurationSection
                    hardwareSection
                    storageSection
                }
                .navigationTitle("New Machine")
                .navigationBarTitleDisplayMode(.inline)
                .disabled(isHUDVisible)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") { dismiss() }
                            .disabled(isHUDVisible)
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Install") { startInstallation() }
                            .disabled(isHUDVisible || vmName.isEmpty)
                    }
                }
            }

            if isHUDVisible {
                installationModalHUD
            }
        }
    }

    private var presetSection: some View {
        Section("Distribution") {
            Picker("Distribution", selection: $selectedPreset) {
                ForEach(DistroRegistry.shared.presets) { preset in
                    HStack {
                        DistroLogoView(imageName: preset.id.components(separatedBy: "-").first, size: 20)
                        Text(preset.name)
                    }
                    .tag(preset)
                }
            }
            .pickerStyle(.menu)
            .onChange(of: selectedPreset) { _, newPreset in
                vmName = newPreset.name
                memoryMB = Double(newPreset.recommendedMemoryMB)
                cpuCores = newPreset.recommendedCores
            }
        }
    }

    private var configurationSection: some View {
        Section("Instance") {
            TextField("Name", text: $vmName)

            Picker("Architecture", selection: $architecture) {
                ForEach(Architecture.allCases) { arch in
                    Label(arch.displayName, systemImage: arch.badgeIcon)
                        .tag(arch)
                }
            }
        }
    }

    private var hardwareSection: some View {
        Section("Compute") {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("Memory")
                    Spacer()
                    TextField("MB", value: $memoryMB, format: .number)
                        .keyboardType(.numberPad)
                        .multilineTextAlignment(.trailing)
                        .frame(width: 80)
                    Text("MB")
                        .foregroundColor(.secondary)
                }
                Slider(value: $memoryMB, in: 256...4096, step: 128)
            }

            Stepper("CPU Cores: \(cpuCores)", value: $cpuCores, in: 1...4)
        }
    }

    private var storageSection: some View {
        Section("Disk") {
            Picker("Format", selection: $diskFormat) {
                ForEach(DiskFormat.allCases) { format in
                    Text(format.displayName).tag(format)
                }
            }

            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("Disk Size")
                    Spacer()
                    TextField("GB", value: $diskSizeGB, format: .number)
                        .keyboardType(.numberPad)
                        .multilineTextAlignment(.trailing)
                        .frame(width: 60)
                    Text("GB")
                        .foregroundColor(.secondary)
                }
                Slider(value: $diskSizeGB, in: 2...64, step: 1)
            }
        }
    }

    private var installationModalHUD: some View {
        ZStack {
            Color.black.opacity(0.45)
                .ignoresSafeArea()

            VStack(spacing: 16) {
                if let error = errorMessage {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 36))
                        .foregroundColor(.red)

                    Text("Download Failed")
                        .font(.headline)

                    Text(error)
                        .font(.footnote)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)

                    HStack(spacing: 12) {
                        Button("Cancel") {
                            isHUDVisible = false
                            errorMessage = nil
                        }
                        .buttonStyle(.bordered)

                        Button("Retry") {
                            errorMessage = nil
                            startInstallation()
                        }
                        .buttonStyle(.borderedProminent)
                    }
                } else {
                    ProgressView()
                        .scaleEffect(1.4)

                    Text(installationStatus)
                        .font(.headline)
                        .multilineTextAlignment(.center)

                    if case .downloading(let progress, let bytesWritten, let totalBytes) = downloader.state {
                        ProgressView(value: progress)
                            .padding(.horizontal)

                        if totalBytes > 0 {
                            Text("\(Int(progress * 100))% • \(ByteCountFormatter.string(fromByteCount: bytesWritten, countStyle: .file)) / \(ByteCountFormatter.string(fromByteCount: totalBytes, countStyle: .file))")
                                .font(.caption.monospaced())
                                .foregroundColor(.secondary)
                        }
                    }

                    Button("Cancel") {
                        downloader.cancel()
                        isHUDVisible = false
                    }
                    .buttonStyle(.bordered)
                }
            }
            .padding(24)
            .frame(maxWidth: 320)
            .background(Color(.secondarySystemBackground))
            .cornerRadius(18)
            .shadow(radius: 24)
        }
    }

    private func startInstallation() {
        guard let spec = selectedPreset.specs[architecture] else {
            errorMessage = "Architecture not supported for \(selectedPreset.name)"
            isHUDVisible = true
            return
        }

        errorMessage = nil
        isHUDVisible = true
        let vmId = UUID()
        let diskFilename = "rootfs.\(diskFormat.fileExtension)"
        let targetDiskURL = DiskManager.shared.diskURL(for: vmId, filename: diskFilename)

        installationStatus = "Allocating virtual disk..."
        do {
            try DiskManager.shared.allocateEmptyDisk(
                at: targetDiskURL,
                sizeBytes: Int64(diskSizeGB * 1024 * 1024 * 1024),
                format: diskFormat
            )
        } catch {
            errorMessage = "Disk error: \(error.localizedDescription)"
            return
        }

        if let kernelAsset = spec.kernelAsset {
            installationStatus = "Downloading Linux kernel..."
            let kernelDest = DiskManager.shared.diskURL(for: vmId, filename: kernelAsset.filename)
            downloader.download(from: kernelAsset.url, to: kernelDest) { result in
                switch result {
                case .success:
                    if let initrdAsset = spec.initrdAsset {
                        self.installationStatus = "Downloading initramfs..."
                        let initrdDest = DiskManager.shared.diskURL(for: vmId, filename: initrdAsset.filename)
                        self.downloader.download(from: initrdAsset.url, to: initrdDest) { initrdResult in
                            switch initrdResult {
                            case .success:
                                self.finalizeVM(vmId: vmId, spec: spec, kernelFile: kernelAsset.filename, initrdFile: initrdAsset.filename)
                            case .failure(let err):
                                self.errorMessage = "Initramfs failed: \(err.localizedDescription)"
                            }
                        }
                    } else {
                        self.finalizeVM(vmId: vmId, spec: spec, kernelFile: kernelAsset.filename, initrdFile: nil)
                    }
                case .failure(let error):
                    self.errorMessage = "Kernel failed: \(error.localizedDescription)"
                }
            }
        } else {
            installationStatus = "Downloading disk image..."
            downloader.download(from: spec.diskAsset.url, to: targetDiskURL) { result in
                switch result {
                case .success:
                    self.finalizeVM(vmId: vmId, spec: spec, kernelFile: nil, initrdFile: nil)
                case .failure(let error):
                    self.errorMessage = "Image download failed: \(error.localizedDescription)"
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

        isHUDVisible = false
        onCreated(config)
        dismiss()
    }
}
