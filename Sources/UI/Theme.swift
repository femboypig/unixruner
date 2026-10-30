import SwiftUI

public enum Theme {
    public static let background = Color(red: 0.08, green: 0.08, blue: 0.10)
    public static let cardBackground = Color(red: 0.13, green: 0.13, blue: 0.16)
    public static let accent = Color(red: 0.20, green: 0.60, blue: 1.00)
    public static let runningGreen = Color(red: 0.25, green: 0.82, blue: 0.45)
    public static let stoppedGray = Color(red: 0.55, green: 0.55, blue: 0.60)
    public static let terminalBackground = Color(red: 0.05, green: 0.05, blue: 0.07)
    public static let terminalForeground = Color(red: 0.90, green: 0.92, blue: 0.95)

    public static let monoFont = Font.system(.body, design: .monospaced)
    public static let monoCaption = Font.system(.caption, design: .monospaced)
}
