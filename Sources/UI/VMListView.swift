import SwiftUI
public struct VMListView: View {
    @ObservedObject var processManager = VMProcessManager.shared
    @State private var vms: [VMConfig] = []
    @State private var showingWizard = false

    public init() {}

    public var body: some View {
        NavigationStack {
            List {
                if vms.isEmpty {
                    emptyStateSection
                } else {
                    ForEach(vms) { vm in
                        NavigationLink(destination: VMDetailView(vm: vm, onUpdated: { updatedVM in
                            if let idx = vms.firstIndex(where: { $0.id == updatedVM.id }) {
                                vms[idx] = updatedVM
                            }
                        }, onDeleted: reloadVMs)) {
                            vmRow(for: vm)
                        }
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
                Text("Create an instance to start executing CLI commands directly on your iPhone.")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                Button("Create Machine") {
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

        return HStack(spacing: 14) {
            // Distro Icon Badge
            ZStack {
                Circle()
                    .fill(Color.accentColor.opacity(0.12))
                    .frame(width: 44, height: 44)
                Image(systemName: vm.distroIcon)
                    .font(.system(size: 22))
                    .foregroundColor(.accentColor)
            }

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(vm.name)
                        .font(.headline)
                    Image(systemName: vm.architecture.badgeIcon)
                        .foregroundColor(vm.architecture == .arm64 ? .green : .orange)
                        .font(.caption2)
                }

                HStack(spacing: 6) {
                    Text(vm.architecture.displayName)
                        .font(.caption2)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(Color(.tertiarySystemFill))
                        .cornerRadius(4)

                    Text(vm.diskFormat.displayName)
                        .font(.caption2)
                        .foregroundColor(.secondary)

                    Text("•")
                        .font(.caption2)
                        .foregroundColor(.secondary)

                    Text("\(vm.memoryMB) MB")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }

            Spacer()

            if isCurrentRunning {
                Text("RUNNING")
                    .font(.caption2.bold())
                    .foregroundColor(.green)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.green.opacity(0.15))
                    .cornerRadius(4)
            }
        }
        .padding(.vertical, 4)
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
