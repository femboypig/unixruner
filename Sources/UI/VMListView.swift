import SwiftUI
public struct VMListView: View {
    @ObservedObject var processManager = VMProcessManager.shared
    @State private var vms: [VMConfig] = []
    @State private var showingWizard = false
    @State private var selectedVMForTerminal: VMConfig?

    public init() {}

    public var body: some View {
        NavigationStack {
            List {
                if vms.isEmpty {
                    emptyStateSection
                } else {
                    ForEach(vms) { vm in
                        vmRow(for: vm)
                    }
                    .onDelete(perform: deleteVM)
                }
            }
            .navigationTitle("unixruner")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showingWizard = true
                    } label: {
                        Image(systemName: "plus")
                    }
                }
            }
            .sheet(isPresented: $showingWizard, onDismiss: reloadVMs) {
                NewVMWizardView(onCreated: { newVM in
                    vms.append(newVM)
                })
            }
            .navigationDestination(item: $selectedVMForTerminal) { _ in
                TerminalContainerView()
            }
            .onAppear(perform: reloadVMs)
        }
    }

    private var emptyStateSection: some View {
        Section {
            VStack(spacing: 12) {
                Image(systemName: "terminal")
                    .font(.system(size: 40))
                    .foregroundColor(.secondary)
                Text("No Virtual Machines")
                    .font(.headline)
                Text("Install a minimal Alpine Linux or Debian instance to start executing CLI commands directly on your iPhone.")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                Button("Create First VM") {
                    showingWizard = true
                }
                .buttonStyle(.borderedProminent)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 24)
        }
    }

    private func vmRow(for vm: VMConfig) -> some View {
        let isCurrentRunning = processManager.activeVMConfig?.id == vm.id && processManager.currentState == .running

        return HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(vm.name)
                        .font(.headline)
                    Image(systemName: vm.architecture.badgeIcon)
                        .foregroundColor(vm.architecture == .arm64 ? .green : .orange)
                        .font(.caption)
                }

                HStack(spacing: 8) {
                    Text(vm.architecture.displayName)
                        .font(.caption2)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color(.tertiarySystemFill))
                        .cornerRadius(4)

                    Text(vm.diskFormat.displayName)
                        .font(.caption2)
                        .foregroundColor(.secondary)

                    Text("\(vm.memoryMB) MB RAM")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }

            Spacer()

            if isCurrentRunning {
                Button {
                    selectedVMForTerminal = vm
                } label: {
                    Text("Open")
                        .font(.subheadline.bold())
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(Color.green)
                        .foregroundColor(.white)
                        .cornerRadius(8)
                }
            } else {
                Button {
                    startVM(vm)
                } label: {
                    Image(systemName: "play.fill")
                        .font(.headline)
                        .foregroundColor(.blue)
                }
            }
        }
        .padding(.vertical, 4)
    }

    private func startVM(_ vm: VMConfig) {
        let diskURL = DiskManager.shared.diskURL(for: vm.id, filename: vm.diskRelativePath)
        let kernelURL = vm.kernelRelativePath.map { DiskManager.shared.diskURL(for: vm.id, filename: $0) }
        let initrdURL = vm.initrdRelativePath.map { DiskManager.shared.diskURL(for: vm.id, filename: $0) }

        do {
            let engine = HeadlessQEMUEngine()
            try processManager.launch(
                config: vm,
                engine: engine,
                diskURL: diskURL,
                kernelURL: kernelURL,
                initrdURL: initrdURL
            )
            selectedVMForTerminal = vm
        } catch {
            print("Failed to launch VM: \(error.localizedDescription)")
        }
    }

    private func deleteVM(at offsets: IndexSet) {
        for index in offsets {
            let vm = vms[index]
            try? DiskManager.shared.deleteVMData(for: vm.id)
        }
        vms.remove(atOffsets: offsets)
        saveVMList()
    }

    private func reloadVMs() {
        let url = DiskManager.shared.baseVMDirectory.appendingPathComponent("vms.json")
        guard let data = try? Data(contentsOf: url),
              let decoded = try? JSONDecoder().decode([VMConfig].self, from: data) else {
            return
        }
        self.vms = decoded
    }

    private func saveVMList() {
        let url = DiskManager.shared.baseVMDirectory.appendingPathComponent("vms.json")
        if let data = try? JSONEncoder().encode(vms) {
            try? data.write(to: url)
        }
    }
}
