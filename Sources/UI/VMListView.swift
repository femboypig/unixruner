import SwiftUI

public final class VMListViewModel: ObservableObject {
    @Published public var vms: [VMConfig] = []
    @Published public var state: VMState = .stopped
    @Published public var activeVM: VMConfig?
    @Published public var showConsole = false

    public let socketBridge = SerialSocketBridge()

    public init() {
        loadDefaultVM()
    }

    public func loadDefaultVM() {
        let kernel = AlpinePayload.shared.resolvedKernelPath() ?? ""
        let initrd = AlpinePayload.shared.resolvedInitrdPath() ?? ""
        let alpine = VMConfig.defaultAlpine(kernelPath: kernel, initrdPath: initrd)
        self.vms = [alpine]
    }

    public func start(vm: VMConfig) {
        guard !state.isRunning else { return }
        state = .starting
        activeVM = vm

        guard let kernel = AlpinePayload.shared.resolvedKernelPath(),
              let initrd = AlpinePayload.shared.resolvedInitrdPath() else {
            state = .error("Alpine kernel/initrd not found")
            return
        }

        var runningConfig = vm
        runningConfig.kernelPath = kernel
        runningConfig.initrdPath = initrd

        let args = QEMUArguments.build(for: runningConfig)

        do {
            try QEMURunner.shared.run(arguments: args, architecture: vm.architecture) { [weak self] in
                self?.state = .stopped
                self?.socketBridge.disconnect()
            }

            state = .running
            socketBridge.connect(port: runningConfig.serialPort)
            showConsole = true
        } catch {
            state = .error(error.localizedDescription)
        }
    }

    public func stop() {
        state = .stopping
        socketBridge.write(data: Data("poweroff\n".utf8))
        socketBridge.disconnect()
        state = .stopped
    }
}

public struct VMListView: View {
    @StateObject private var viewModel = VMListViewModel()
    @State private var showSettings = false

    public init() {}

    public var body: some View {
        NavigationView {
            ZStack {
                Theme.background.ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 16) {
                        ForEach(viewModel.vms) { vm in
                            vmCard(for: vm)
                        }
                    }
                    .padding(16)
                }
            }
            .navigationTitle("unixruner")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: { showSettings = true }) {
                        Image(systemName: "gearshape")
                            .foregroundColor(Theme.accent)
                    }
                }
            }
            .sheet(isPresented: $showSettings) {
                SettingsView()
            }
            .fullScreenCover(isPresented: $viewModel.showConsole) {
                consoleSheet
            }
        }
        .navigationViewStyle(.stack)
    }

    private func vmCard(for vm: VMConfig) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(vm.name)
                        .font(.headline)
                        .foregroundColor(.white)

                    HStack(spacing: 6) {
                        Image(systemName: vm.architecture.speedIcon)
                            .foregroundColor(vm.architecture == .arm64 ? Theme.runningGreen : .yellow)
                        Text("\(vm.architecture.displayName) • \(vm.architecture.speedLabel)")
                            .font(Theme.monoCaption)
                            .foregroundColor(.gray)
                    }
                }

                Spacer()

                statusBadge
            }

            Divider().background(Color.white.opacity(0.1))

            HStack {
                Label("\(vm.memoryMB) MB", systemImage: "memorychip")
                    .font(Theme.monoCaption)
                    .foregroundColor(.gray)

                Spacer()

                Label("\(vm.cpuCount) Core", systemImage: "cpu")
                    .font(Theme.monoCaption)
                    .foregroundColor(.gray)
            }

            HStack(spacing: 12) {
                if viewModel.state.isRunning {
                    Button(action: { viewModel.showConsole = true }) {
                        Label("Console", systemImage: "terminal")
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                            .background(Theme.accent)
                            .foregroundColor(.white)
                            .cornerRadius(8)
                    }

                    Button(action: { viewModel.stop() }) {
                        Label("Stop", systemImage: "stop.fill")
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                            .background(Color.red.opacity(0.8))
                            .foregroundColor(.white)
                            .cornerRadius(8)
                    }
                } else {
                    Button(action: { viewModel.start(vm: vm) }) {
                        Label("Start VM", systemImage: "play.fill")
                            .font(.system(.body, design: .rounded).weight(.semibold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .background(Theme.runningGreen)
                            .foregroundColor(.black)
                            .cornerRadius(8)
                    }
                }
            }
        }
        .padding(16)
        .background(Theme.cardBackground)
        .cornerRadius(12)
    }

    private var statusBadge: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(viewModel.state.isRunning ? Theme.runningGreen : Theme.stoppedGray)
                .frame(width: 8, height: 8)

            Text(viewModel.state.statusText)
                .font(Theme.monoCaption)
                .foregroundColor(viewModel.state.isRunning ? Theme.runningGreen : Theme.stoppedGray)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
        .background(Color.black.opacity(0.3))
        .cornerRadius(20)
    }

    private var consoleSheet: some View {
        ZStack {
            Theme.terminalBackground.ignoresSafeArea()

            VStack(spacing: 0) {
                HStack {
                    Text(viewModel.activeVM?.name ?? "Console")
                        .font(Theme.monoFont)
                        .foregroundColor(.white)

                    Spacer()

                    Button(action: { viewModel.showConsole = false }) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.title2)
                            .foregroundColor(.gray)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background(Color.black.opacity(0.6))

                ConsoleView(socketBridge: viewModel.socketBridge)

                TerminalAccessoryBar { seq in
                    viewModel.socketBridge.write(data: Data(seq.utf8))
                }
            }
        }
    }
}
