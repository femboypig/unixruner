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
                            vmCard(for: vm)
                        }
                        .listRowSeparator(.hidden)
                        .listRowBackground(Color.clear)
                        .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
                    }
                    .onDelete(perform: deleteVM)
                }
            }
            .listStyle(.plain)
            .navigationTitle("unixruner")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showingWizard = true
                    } label: {
                        Image(systemName: "plus")
                            .font(.system(size: 16, weight: .bold))
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
        VStack(spacing: 14) {
            Image(systemName: "terminal")
                .font(.system(size: 42))
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
            .padding(.top, 4)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
        .listRowSeparator(.hidden)
        .listRowBackground(Color.clear)
    }

    private func vmCard(for vm: VMConfig) -> some View {
        let isRunning = processManager.activeVMConfig?.id == vm.id && processManager.currentState == .running

        return HStack(spacing: 14) {
            DistroLogoView(imageName: vm.distroImageName, size: 42)

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 8) {
                    Text(vm.name)
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundColor(.primary)

                    Circle()
                        .fill(isRunning ? Color.green : Color.secondary.opacity(0.4))
                        .frame(width: 8, height: 8)
                }

                HStack(spacing: 6) {
                    Text(vm.architecture.displayName)
                    Text("•")
                    Text("\(vm.memoryMB) MB")
                    Text("•")
                    Text(vm.diskFormat.displayName)
                }
                .font(.system(size: 13, weight: .regular))
                .foregroundColor(.secondary)
            }

            Spacer()

            if isRunning {
                Image(systemName: "waveform")
                    .foregroundColor(.green)
                    .font(.system(size: 14))
            }
        }
        .padding(14)
        .background(Color(.secondarySystemGroupedBackground))
        .cornerRadius(14)
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(isRunning ? Color.green.opacity(0.3) : Color(.separator).opacity(0.2), lineWidth: 1)
        )
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
