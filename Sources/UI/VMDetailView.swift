import SwiftUI
public struct VMDetailView: View {
    @ObservedObject var processManager = VMProcessManager.shared
    @State var vm: VMConfig
    public var onUpdated: ((VMConfig) -> Void)?
    public var onDeleted: (() -> Void)?

    @Environment(\.dismiss) private var dismiss
    @State private var showingTerminal = false
    @State private var showingDeleteAlert = false
    @State private var launchErrorMessage: String?
    @State private var showingErrorAlert = false

    // New port forward state
    @State private var newPortName = ""
    @State private var newHostPort = ""
    @State private var newGuestPort = ""

    public init(vm: VMConfig, onUpdated: ((VMConfig) -> Void)? = nil, onDeleted: (() -> Void)? = nil) {
        self._vm = State(initialValue: vm)
        self.onUpdated = onUpdated
        self.onDeleted = onDeleted
    }

    private var isRunning: Bool {
        processManager.activeVMConfig?.id == vm.id && processManager.currentState == .running
    }

    public var body: some View {
        Form {
            headerSection
            actionSection
            hardwareSection
            portForwardingSection
            bootSection
            dangerSection
        }
        .navigationTitle(vm.name)
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(isPresented: $showingTerminal) {
            TerminalContainerView()
        }
        .alert("Launch Failed", isPresented: $showingErrorAlert, presenting: launchErrorMessage) { _ in
            Button("OK", role: .cancel) {}
        } message: { msg in
            Text(msg)
        }
        .alert("Delete Virtual Machine?", isPresented: $showingDeleteAlert) {
            Button("Delete", role: .destructive) {
                deleteVM()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will permanently delete the disk image and all installed packages.")
        }
    }

    private var headerSection: some View {
        Section {
            HStack(spacing: 16) {
                Image(systemName: vm.distroIcon)
                    .font(.system(size: 38))
                    .foregroundColor(.accentColor)
                    .frame(width: 48, height: 48)

                VStack(alignment: .leading, spacing: 4) {
                    Text(vm.name)
                        .font(.title3.bold())

                    HStack(spacing: 8) {
                        Label(vm.architecture.displayName, systemImage: vm.architecture.badgeIcon)
                            .font(.caption2)
                            .foregroundColor(vm.architecture == .arm64 ? .green : .orange)

                        Text(vm.diskFormat.displayName)
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }

                Spacer()

                Circle()
                    .fill(isRunning ? Color.green : Color.secondary.opacity(0.3))
                    .frame(width: 10, height: 10)
            }
            .padding(.vertical, 4)
        }
    }

    private var actionSection: some View {
        Section {
            if isRunning {
                Button {
                    showingTerminal = true
                } label: {
                    Label("Open Terminal", systemImage: "terminal.fill")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(.green)

                Button(role: .destructive) {
                    processManager.stop()
                } label: {
                    Label("Stop Machine", systemImage: "stop.fill")
                        .frame(maxWidth: .infinity)
                }
            } else {
                Button {
                    launchVM()
                } label: {
                    Label("Start Machine", systemImage: "play.fill")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
            }
        }
    }

    private var hardwareSection: some View {
        Section("Hardware") {
            HStack {
                Text("Memory")
                Spacer()
                TextField("MB", value: $vm.memoryMB, format: .number)
                    .keyboardType(.numberPad)
                    .multilineTextAlignment(.trailing)
                    .frame(width: 70)
                Text("MB")
                    .foregroundColor(.secondary)
            }
            .onChange(of: vm.memoryMB) { _, _ in saveChanges() }

            Stepper("CPU Cores: \(vm.cpuCores)", value: $vm.cpuCores, in: 1...4)
                .onChange(of: vm.cpuCores) { _, _ in saveChanges() }

            HStack {
                Text("Virtual Disk")
                Spacer()
                Text(ByteCountFormatter.string(fromByteCount: vm.diskSizeBytes, countStyle: .file))
                    .foregroundColor(.secondary)
            }
        }
    }

    private var portForwardingSection: some View {
        Section("Port Forwarding (SLIRP)") {
            ForEach(vm.portMappings) { mapping in
                HStack {
                    Text(mapping.name)
                    Spacer()
                    Text(":\(mapping.hostPort) → :\(mapping.guestPort)")
                        .font(.caption.monospaced())
                        .foregroundColor(.secondary)
                }
            }
            .onDelete { offsets in
                vm.portMappings.remove(atOffsets: offsets)
                saveChanges()
            }

            HStack {
                TextField("Name", text: $newPortName)
                TextField("Host", text: $newHostPort)
                    .keyboardType(.numberPad)
                    .frame(width: 60)
                Text("→")
                TextField("Guest", text: $newGuestPort)
                    .keyboardType(.numberPad)
                    .frame(width: 60)
                Button("Add") {
                    addPortMapping()
                }
                .disabled(newPortName.isEmpty || newHostPort.isEmpty || newGuestPort.isEmpty)
            }
        }
    }

    private var bootSection: some View {
        Section("Boot Arguments") {
            TextField("kernel args", text: $vm.extraBootArgs)
                .font(.caption.monospaced())
                .onChange(of: vm.extraBootArgs) { _, _ in saveChanges() }
        }
    }

    private var dangerSection: some View {
        Section {
            Button(role: .destructive) {
                showingDeleteAlert = true
            } label: {
                Label("Delete Virtual Machine", systemImage: "trash")
                    .foregroundColor(.red)
            }
        }
    }

    private func addPortMapping() {
        guard let host = UInt16(newHostPort), let guest = UInt16(newGuestPort) else { return }
        let mapping = PortMapping(name: newPortName, hostPort: host, guestPort: guest, protocol: .tcp)
        vm.portMappings.append(mapping)
        newPortName = ""
        newHostPort = ""
        newGuestPort = ""
        saveChanges()
    }

    private func launchVM() {
        let diskURL = DiskManager.shared.diskURL(for: vm.id, filename: vm.diskRelativePath)
        let kernelURL = vm.kernelRelativePath.map { DiskManager.shared.diskURL(for: vm.id, filename: $0) }
        let initrdURL = vm.initrdRelativePath.map { DiskManager.shared.diskURL(for: vm.id, filename: $0) }

        guard FileManager.default.fileExists(atPath: diskURL.path) else {
            launchErrorMessage = "Virtual disk file missing: \(vm.diskRelativePath)"
            showingErrorAlert = true
            return
        }

        do {
            let engine = HeadlessQEMUEngine()
            try processManager.launch(
                config: vm,
                engine: engine,
                diskURL: diskURL,
                kernelURL: kernelURL,
                initrdURL: initrdURL
            )
            showingTerminal = true
        } catch {
            launchErrorMessage = error.localizedDescription
            showingErrorAlert = true
        }
    }

    private func saveChanges() {
        vm.updatedAt = Date()
        onUpdated?(vm)
        persistVM()
    }

    private func persistVM() {
        let listURL = DiskManager.shared.baseVMDirectory.appendingPathComponent("vms.json")
        guard let data = try? Data(contentsOf: listURL),
              var existing = try? JSONDecoder().decode([VMConfig].self, from: data) else {
            return
        }
        if let idx = existing.firstIndex(where: { $0.id == vm.id }) {
            existing[idx] = vm
            if let encoded = try? JSONEncoder().encode(existing) {
                try? encoded.write(to: listURL)
            }
        }
    }

    private func deleteVM() {
        processManager.stop()
        try? DiskManager.shared.deleteVMData(for: vm.id)
        onDeleted?()
        dismiss()
    }
}
