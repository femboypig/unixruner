import SwiftUI

public struct TerminalAccessoryBar: View {
    public var onKeyPress: (String) -> Void

    public init(onKeyPress: @escaping (String) -> Void) {
        self.onKeyPress = onKeyPress
    }

    private let keys: [(label: String, seq: String)] = [
        ("ESC", "\u{1B}"),
        ("TAB", "\t"),
        ("CTRL+C", "\u{03}"),
        ("CTRL+D", "\u{04}"),
        ("▲", "\u{1B}[A"),
        ("▼", "\u{1B}[B"),
        ("◀", "\u{1B}[D"),
        ("▶", "\u{1B}[C")
    ]

    public var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(keys, id: \.label) { key in
                    Button(action: {
                        onKeyPress(key.seq)
                    }) {
                        Text(key.label)
                            .font(.system(size: 13, weight: .bold, design: .monospaced))
                            .foregroundColor(.white)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(Color.white.opacity(0.12))
                            .cornerRadius(6)
                    }
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
        }
        .background(Color.black.opacity(0.85))
    }
}
