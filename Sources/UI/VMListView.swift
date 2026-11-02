import SwiftUI

public final class VMListViewModel: ObservableObject {
    @Published public var state: VMState = .stopped
    public let socketBridge = SerialSocketBridge()

    public init() {}

    public func start() {
        guard !state.isRunning && state != .starting else { return }
        state = .starting

        guard let kernel = AlpinePayload.shared.resolvedKernelPath(),
              let initrd = AlpinePayload.shared.resolvedInitrdPath() else {
            state = .error("Alpine kernel/initrd not found")
            return
        }

        let config = VMConfig.defaultAlpine(kernelPath: kernel, initrdPath: initrd)
        let args = QEMUArguments.build(for: config)

        do {
            try QEMURunner.shared.run(arguments: args, architecture: config.architecture) { [weak self] in
                self?.state = .stopped
                self?.socketBridge.disconnect()
            }

            state = .running
            socketBridge.connect(port: config.serialPort)
        } catch {
            state = .error(error.localizedDescription)
        }
    }

    public func stop() {
        guard state.isRunning || state == .starting else { return }
        state = .stopping
        socketBridge.write(data: Data("poweroff\n".utf8))
        QEMURunner.shared.stop()

        DispatchQueue.main.asyncAfter(deadline: .now() + 4.0) { [weak self] in
            guard let self = self, self.state == .stopping else { return }
            self.socketBridge.disconnect()
            self.state = .stopped
        }
    }
}

public struct VMListView: View {
    @StateObject private var viewModel = VMListViewModel()
    @State private var showLogs = false

    public init() {}

    private var statusColor: Color {
        switch viewModel.state {
        case .stopped:
            return .secondary
        case .starting, .stopping:
            return .orange
        case .running:
            return .green
        case .error:
            return .red
        }
    }

    public var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                // Main terminal view
                ConsoleView(socketBridge: viewModel.socketBridge)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                // Native accessory bar
                TerminalAccessoryBar { seq in
                    viewModel.socketBridge.write(data: Data(seq.utf8))
                }
            }
            .navigationTitle("unixruner")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    HStack(spacing: 6) {
                        Circle()
                            .fill(statusColor)
                            .frame(width: 8, height: 8)

                        Text(viewModel.state.statusText)
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                }

                ToolbarItemGroup(placement: .navigationBarTrailing) {
                    Button {
                        showLogs = true
                    } label: {
                        Image(systemName: "list.bullet.rectangle")
                    }

                    if viewModel.state.isRunning {
                        Button {
                            viewModel.stop()
                        } label: {
                            Label("Stop", systemImage: "stop.fill")
                                .foregroundColor(.red)
                        }
                    } else {
                        Button {
                            viewModel.start()
                        } label: {
                            Label("Start", systemImage: "play.fill")
                                .foregroundColor(.green)
                        }
                        .disabled(viewModel.state == .starting)
                    }
                }
            }
            .sheet(isPresented: $showLogs) {
                LogsView()
            }
        }
        .navigationViewStyle(.stack)
    }
}
