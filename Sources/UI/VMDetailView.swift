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
            heroHeaderSection
            actionSection
            hardwareSection
            portForwardingSection
            bootSection
            dangerSection
        }
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .fullScreenCover(isPresented: $showingTerminal) {
            NavigationStack {
                TerminalContainerView()
                    .toolbar {
                        ToolbarItem(placement: .topBarLeading) {
                            Button("Close") {
                                showingTerminal = false
                            }
                        }
                    }
            }
        }
        .alert("Launch Failed", isPresented: $showingErrorAlert, presenting: launchErrorMessage) { _ in
            Button("OK", role: .cancel) {}
        } message: { msg in
            Text(msg)
        }
        .alert("Delete Machine?", isPresented: $showingDeleteAlert) {
            Button("Delete", role: .destructive) {
                deleteVM()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will permanently erase the disk and files for \(vm.name).")
        }
    }

    private var heroHeaderSection: some View {
        Section {
            VStack(spacing: 12) {
                DistroLogoView(imageName: vm.distroImageName, size: 56)

                Text(vm.name)
                    .font(.system(size: 22, weight: .bold))

                HStack(spacing: 6) {
                    Circle()
                        .fill(isRunning ? Color.green : Color.secondary.opacity(0.4))
                        .frame(width: 8, height: 8)

                    Text(isRunning ? "Running" : "Stopped")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(isRunning ? .green : .secondary)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(isRunning ? Color.green.opacity(0.12) : Color(.tertiarySystemFill))
                .cornerRadius(12)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
        }
        .listRowBackground(Color.clear)
        .listRowInsets(EdgeInsets())
    }

    private var actionSection: some View {
        Section {
            if isRunning {
                HStack(spacing: 12) {
                    Button {
                        showingTerminal = true
                    } label: {
                        Label("Terminal", systemImage: "terminal.fill")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .frame(height: 38)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.green)

                    Button(role: .destructive) {
                        processManager.stop()
                    } label: {
                        Label("Stop", systemImage: "stop.fill")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .frame(height: 38)
                    }
                    .buttonStyle(.bordered)
                }
            } else {
                Button {
                    launchVM()
                } label: {
                    Label("Start & Open Terminal", systemImage: "play.fill")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .frame(height: 38)
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .listRowBackground(Color.clear)
        .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 4, trailing: 16))
    }

    private var hardwareSection: some View {
        Section("Compute Allocation") {
            HStack {
                Text("Architecture")
                Spacer()
                Text(vm.architecture.displayName)
                    .foregroundColor(.secondary)
            }

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
                Text("\(ByteCountFormatter.string(fromByteCount: vm.diskSizeBytes, countStyle: .file)) (\(vm.diskFormat.displayName))")
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
                TextField("Label", text: $newPortName)
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
            launchErrorMessage = "Virtual disk missing: \(vm.diskRelativePath). Please reinstall."
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
