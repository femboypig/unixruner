import SwiftUI
import UIKit
import SwiftTerm
public struct TerminalContainerView: View {
    @ObservedObject var processManager = VMProcessManager.shared
    @State private var isCtrlActive = false
    @State private var isAltActive = false

    private let terminalView = SwiftTerm.TerminalView()

    public init() {}

    public var body: some View {
        VStack(spacing: 0) {
            SwiftTermRepresentable(terminalView: terminalView, onSendInput: { data in
                processManager.sendInput(data)
            })
            .onAppear {
                processManager.onOutputReceived = { data in
                    let bytes = [UInt8](data)
                    terminalView.feed(byteArray: bytes[...])
                }
            }

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

public struct SwiftTermRepresentable: UIViewRepresentable {
    public let terminalView: SwiftTerm.TerminalView
    public let onSendInput: (Data) -> Void

    public func makeUIView(context: Context) -> SwiftTerm.TerminalView {
        terminalView.terminalDelegate = context.coordinator
        terminalView.backgroundColor = .black
        terminalView.font = UIFont.monospacedSystemFont(ofSize: 13, weight: .regular)
        return terminalView
    }

    public func updateUIView(_ uiView: SwiftTerm.TerminalView, context: Context) {}

    public func makeCoordinator() -> Coordinator {
        Coordinator(onSendInput: onSendInput)
    }

    public class Coordinator: NSObject, TerminalViewDelegate {
        let onSendInput: (Data) -> Void

        init(onSendInput: @escaping (Data) -> Void) {
            self.onSendInput = onSendInput
        }

        public func send(source: TerminalView, data: ArraySlice<UInt8>) {
            onSendInput(Data(data))
        }

        public func scrolled(source: TerminalView, position: Double) {}
        public func setTerminalTitle(source: TerminalView, title: String) {}
        public func sizeChanged(source: TerminalView) {}
        public func clipboardCopy(source: TerminalView, content: Data) {}
        public func rangeChanged(source: TerminalView, start: Position, end: Position) {}
        public func hostCurrentDirectoryUpdate(source: TerminalView, directory: String?) {}
        public func requestOpenLink(source: TerminalView, link: String, params: [String : String]) {}
        public func bell(source: TerminalView) {}
    }
}
