import SwiftUI
import UIKit
import SwiftTerm

public struct TerminalContainerView: View {
    @ObservedObject var processManager = VMProcessManager.shared
    @State private var isCtrlActive = false
    @State private var isAltActive = false

    public init() {}

    public var body: some View {
        VStack(spacing: 0) {
            SwiftTermRepresentable(onSendInput: { data in
                processManager.sendInput(data)
            })

            TerminalAccessoryBar(
                isCtrlActive: $isCtrlActive,
                isAltActive: $isAltActive,
                onKeyPress: { char in
                    handleKeyPress(char)
                },
                onSpecialKey: { key in
                    handleSpecialKey(key)
                }
            )
        }
        .navigationTitle(processManager.activeVMConfig?.name ?? "Terminal")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    processManager.sendInput(Data([0x0D])) // '\r'
                } label: {
                    Label("Send Enter", systemImage: "return")
                }
            }
        }
        .toolbar(.hidden, for: .tabBar)
    }

    private func handleKeyPress(_ key: String) {
        guard let first = key.first else { return }
        if isCtrlActive {
            // Transform to ASCII control character
            if let ascii = first.asciiValue, ascii >= 64, ascii <= 127 {
                let ctrlByte = ascii & 0x1F
                processManager.sendInput(Data([ctrlByte]))
                isCtrlActive = false
                return
            }
        }
        if let data = key.data(using: .utf8) {
            processManager.sendInput(data)
        }
    }

    private func handleSpecialKey(_ key: TerminalAccessoryBar.SpecialKey) {
        let sequence: [UInt8]
        switch key {
        case .escape:
            sequence = [0x1B]
        case .tab:
            sequence = [0x09]
        case .upArrow:
            sequence = [0x1B, 0x5B, 0x41]
        case .downArrow:
            sequence = [0x1B, 0x5B, 0x42]
        case .rightArrow:
            sequence = [0x1B, 0x5B, 0x43]
        case .leftArrow:
            sequence = [0x1B, 0x5B, 0x44]
        }
        processManager.sendInput(Data(sequence))
    }
}

public final class TerminalHostView: UIView {
    public let terminalView = SwiftTerm.TerminalView()
    private var hasFedInitialHistory = false

    override init(frame: CGRect) {
        super.init(frame: frame)
        setup()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }

    private func setup() {
        backgroundColor = .black
        terminalView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(terminalView)
        NSLayoutConstraint.activate([
            terminalView.topAnchor.constraint(equalTo: topAnchor),
            terminalView.bottomAnchor.constraint(equalTo: bottomAnchor),
            terminalView.leadingAnchor.constraint(equalTo: leadingAnchor),
            terminalView.trailingAnchor.constraint(equalTo: trailingAnchor)
        ])
        terminalView.backgroundColor = .black
        terminalView.font = UIFont.monospacedSystemFont(ofSize: 13, weight: .regular)
    }

    override public func layoutSubviews() {
        super.layoutSubviews()
        if bounds.width > 0 && bounds.height > 0 && !hasFedInitialHistory {
            hasFedInitialHistory = true
            feedHistoryNow()
        }
    }

    public func feedHistoryNow() {
        let history = VMProcessManager.shared.outputHistory
        if !history.isEmpty {
            let bytes = [UInt8](history)
            terminalView.feed(byteArray: bytes[...])
            AppLogger.shared.log("Fed \(bytes.count) bytes history to laid-out terminal (\(terminalView.getTerminal().cols)x\(terminalView.getTerminal().rows))", level: .engine)
        }
    }

    public func feedData(_ data: Data) {
        let bytes = [UInt8](data)
        terminalView.feed(byteArray: bytes[...])
    }
}

public struct SwiftTermRepresentable: UIViewRepresentable {
    public let onSendInput: (Data) -> Void

    public func makeUIView(context: Context) -> TerminalHostView {
        let host = TerminalHostView()
        host.terminalView.terminalDelegate = context.coordinator
        context.coordinator.hostView = host

        VMProcessManager.shared.onOutputReceived = { [weak host] data in
            DispatchQueue.main.async {
                host?.feedData(data)
            }
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            host.terminalView.becomeFirstResponder()
        }

        return host
    }

    public func updateUIView(_ uiView: TerminalHostView, context: Context) {}

    public func makeCoordinator() -> Coordinator {
        Coordinator(onSendInput: onSendInput)
    }

    public class Coordinator: NSObject, TerminalViewDelegate {
        weak var hostView: TerminalHostView?
        let onSendInput: (Data) -> Void

        init(onSendInput: @escaping (Data) -> Void) {
            self.onSendInput = onSendInput
        }

        public func send(source: TerminalView, data: ArraySlice<UInt8>) {
            AppLogger.shared.log("TerminalView key sent \(data.count) bytes", level: .engine)
            onSendInput(Data(data))
        }

        public func scrolled(source: TerminalView, position: Double) {}
        public func setTerminalTitle(source: TerminalView, title: String) {}
        public func sizeChanged(source: TerminalView, newCols: Int, newRows: Int) {
            AppLogger.shared.log("Terminal size changed: \(newCols)x\(newRows)", level: .engine)
        }
        public func clipboardCopy(source: TerminalView, content: Data) {}
        public func rangeChanged(source: TerminalView, startY: Int, endY: Int) {}
        public func hostCurrentDirectoryUpdate(source: TerminalView, directory: String?) {}
        public func requestOpenLink(source: TerminalView, link: String, params: [String : String]) {}
        public func bell(source: TerminalView) {}
    }
}
