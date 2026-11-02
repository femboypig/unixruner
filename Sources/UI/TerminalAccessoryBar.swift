import SwiftUI

public struct TerminalAccessoryBar: View {
    public var onKeyPress: (String) -> Void

    public init(onKeyPress: @escaping (String) -> Void) {
        self.onKeyPress = onKeyPress
    }

    private struct KeyItem: Identifiable {
        let id: String
        let label: String
        let seq: String
        let systemImage: String?
    }

    private let keys: [KeyItem] = [
        KeyItem(id: "esc", label: "ESC", seq: "\u{1B}", systemImage: nil),
        KeyItem(id: "tab", label: "TAB", seq: "\t", systemImage: nil),
        KeyItem(id: "ctrlc", label: "Ctrl+C", seq: "\u{03}", systemImage: nil),
        KeyItem(id: "ctrld", label: "Ctrl+D", seq: "\u{04}", systemImage: nil),
        KeyItem(id: "up", label: "", seq: "\u{1B}[A", systemImage: "arrow.up"),
        KeyItem(id: "down", label: "", seq: "\u{1B}[B", systemImage: "arrow.down"),
        KeyItem(id: "left", label: "", seq: "\u{1B}[D", systemImage: "arrow.left"),
        KeyItem(id: "right", label: "", seq: "\u{1B}[C", systemImage: "arrow.right")
    ]

    public var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(keys) { key in
                    Button(action: {
                        onKeyPress(key.seq)
                    }) {
                        Group {
                            if let icon = key.systemImage {
                                Image(systemName: icon)
                                    .font(.system(size: 13, weight: .semibold))
                            } else {
                                Text(key.label)
                                    .font(.system(size: 12, weight: .semibold))
                            }
                        }
                        .foregroundColor(.primary)
                        .frame(minWidth: 42, minHeight: 34)
                        .background(Color(UIColor.tertiarySystemFill))
                        .cornerRadius(6)
                    }
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
        }
        .background(Color(UIColor.secondarySystemBackground))
    }
}
