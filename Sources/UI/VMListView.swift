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
            return Theme.stoppedGray
        case .starting, .stopping:
            return .orange
        case .running:
            return Theme.runningGreen
        case .error:
            return .red
        }
    }

    public var body: some View {
        ZStack {
            Theme.terminalBackground.ignoresSafeArea()

            VStack(spacing: 0) {
                // Minimal top status header
                HStack(spacing: 10) {
                    HStack(spacing: 6) {
                        Circle()
                            .fill(statusColor)
                            .frame(width: 8, height: 8)

                        Text(viewModel.state.statusText)
                            .font(.system(size: 13, weight: .semibold, design: .monospaced))
                            .foregroundColor(.white)
                            .lineLimit(1)
                    }

                    Spacer()

                    Button(action: { viewModel.start() }) {
                        Text("Start")
                            .font(.system(size: 12, weight: .bold, design: .monospaced))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(viewModel.state.isRunning || viewModel.state == .starting ? Color.white.opacity(0.1) : Theme.runningGreen)
                            .foregroundColor(viewModel.state.isRunning || viewModel.state == .starting ? .gray : .black)
                            .cornerRadius(5)
                    }
                    .disabled(viewModel.state.isRunning || viewModel.state == .starting)

                    Button(action: { viewModel.stop() }) {
                        Text("Stop")
                            .font(.system(size: 12, weight: .bold, design: .monospaced))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(viewModel.state.isRunning ? Color.red.opacity(0.8) : Color.white.opacity(0.1))
                            .foregroundColor(viewModel.state.isRunning ? .white : .gray)
                            .cornerRadius(5)
                    }
                    .disabled(!viewModel.state.isRunning && viewModel.state != .starting)

                    Button(action: { showLogs = true }) {
                        Text("Logs")
                            .font(.system(size: 12, weight: .bold, design: .monospaced))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(Color.white.opacity(0.15))
                            .foregroundColor(.white)
                            .cornerRadius(5)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Color.black.opacity(0.85))

                // Screen body: Pure SwiftTerm ConsoleView directly filling the screen
                ConsoleView(socketBridge: viewModel.socketBridge)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                // Bottom: TerminalAccessoryBar
                TerminalAccessoryBar { seq in
                    viewModel.socketBridge.write(data: Data(seq.utf8))
                }
            }
        }
        .sheet(isPresented: $showLogs) {
            LogsView()
        }
    }
}
