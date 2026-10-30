import SwiftUI
import UIKit
import SwiftTerm

public struct ConsoleView: UIViewRepresentable {
    public let socketBridge: SerialSocketBridge

    public init(socketBridge: SerialSocketBridge) {
        self.socketBridge = socketBridge
    }

    public func makeCoordinator() -> Coordinator {
        Coordinator(socketBridge: socketBridge)
    }

    public func makeUIView(context: Context) -> TerminalView {
        let terminal = TerminalView()
        terminal.backgroundColor = UIColor(Theme.terminalBackground)
        terminal.terminalDelegate = context.coordinator
        context.coordinator.terminalView = terminal

        socketBridge.onDataReceived = { data in
            terminal.feed(byteArray: [UInt8](data)[...])
        }

        terminal.becomeFirstResponder()
        return terminal
    }

    public func updateUIView(_ uiView: TerminalView, context: Context) {}

    public final class Coordinator: NSObject, TerminalViewDelegate {
        public let socketBridge: SerialSocketBridge
        public weak var terminalView: TerminalView?

        public init(socketBridge: SerialSocketBridge) {
            self.socketBridge = socketBridge
        }

        public func send(source: TerminalView, data: ArraySlice<UInt8>) {
            socketBridge.write(data: Data(data))
        }

        public func scrolled(source: TerminalView, position: Double) {}

        public func setTerminalTitle(source: TerminalView, title: String) {}

        public func sizeChanged(source: TerminalView, newCols: Int, newRows: Int) {}

        public func clipboardCopy(source: TerminalView, content: Data) {
            if let str = String(data: content, encoding: .utf8) {
                UIPasteboard.general.string = str
            }
        }

        public func rangeChanged(source: TerminalView, startY: Int, endY: Int) {}

        public func hostCurrentDirectoryUpdate(source: TerminalView, directory: String?) {}

        public func requestOpenLink(source: TerminalView, link: String, params: [String: String]) {}

        public func bell(source: TerminalView) {}
    }
}
