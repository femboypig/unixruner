import SwiftUI

public struct TerminalAccessoryBar: View {
    @Binding public var isCtrlActive: Bool
    @Binding public var isAltActive: Bool

    public var onKeyPress: (String) -> Void
    public var onSpecialKey: (SpecialKey) -> Void

    public enum SpecialKey {
        case escape
        case tab
        case upArrow
        case downArrow
        case leftArrow
        case rightArrow
    }

    public init(
        isCtrlActive: Binding<Bool>,
        isAltActive: Binding<Bool>,
        onKeyPress: @escaping (String) -> Void,
        onSpecialKey: @escaping (SpecialKey) -> Void
    ) {
        self._isCtrlActive = isCtrlActive
        self._isAltActive = isAltActive
        self.onKeyPress = onKeyPress
        self.onSpecialKey = onSpecialKey
    }

    public var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                // Modifiers
                modifierButton(title: "Ctrl", isActive: $isCtrlActive)
                modifierButton(title: "Alt", isActive: $isAltActive)

                Divider()
                    .frame(height: 20)

                // Key buttons
                keyButton("Esc") { onSpecialKey(.escape) }
                keyButton("Tab") { onSpecialKey(.tab) }
                keyButton("/") { onKeyPress("/") }
                keyButton("-") { onKeyPress("-") }
                keyButton("|") { onKeyPress("|") }
                keyButton("~") { onKeyPress("~") }

                Divider()
                    .frame(height: 20)

                // Navigation Arrows
                keyButton("↑") { onSpecialKey(.upArrow) }
                keyButton("↓") { onSpecialKey(.downArrow) }
                keyButton("←") { onSpecialKey(.leftArrow) }
                keyButton("→") { onSpecialKey(.rightArrow) }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
        }
        .background(Color(.secondarySystemBackground))
    }

    private func modifierButton(title: String, isActive: Binding<Bool>) -> some View {
        Button {
            isActive.wrappedValue.toggle()
        } label: {
            Text(title)
                .font(.system(size: 13, weight: .bold, design: .monospaced))
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(isActive.wrappedValue ? Color.blue : Color(.tertiarySystemBackground))
                .foregroundColor(isActive.wrappedValue ? .white : .primary)
                .cornerRadius(6)
        }
    }

    private func keyButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 14, weight: .medium, design: .monospaced))
                .frame(minWidth: 32)
                .padding(.vertical, 6)
                .background(Color(.tertiarySystemBackground))
                .foregroundColor(.primary)
                .cornerRadius(6)
        }
    }
}
