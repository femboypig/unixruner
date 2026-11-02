import SwiftUI

public struct LogsView: View {
    @Environment(\.presentationMode) private var presentationMode
    @State private var logs: [Logger.Entry] = []

    public init() {}

    private func levelColor(_ level: Logger.Level) -> Color {
        switch level {
        case .info:
            return .gray
        case .warn:
            return .yellow
        case .error:
            return .red
        case .engine:
            return Theme.accent
        }
    }

    public var body: some View {
        NavigationView {
            ZStack {
                Theme.terminalBackground.ignoresSafeArea()

                if logs.isEmpty {
                    Text("No logs recorded")
                        .font(Theme.monoCaption)
                        .foregroundColor(.gray)
                } else {
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 6) {
                            ForEach(logs) { entry in
                                VStack(alignment: .leading, spacing: 2) {
                                    HStack(spacing: 6) {
                                        Text(entry.level.rawValue)
                                            .font(.system(size: 10, weight: .bold, design: .monospaced))
                                            .padding(.horizontal, 4)
                                            .padding(.vertical, 1)
                                            .background(levelColor(entry.level).opacity(0.2))
                                            .foregroundColor(levelColor(entry.level))
                                            .cornerRadius(3)

                                        Spacer()

                                        Text(entry.timestamp, style: .time)
                                            .font(.system(size: 10, design: .monospaced))
                                            .foregroundColor(.gray)
                                    }

                                    Text(entry.message)
                                        .font(.system(size: 11, design: .monospaced))
                                        .foregroundColor(Theme.terminalForeground)
                                        .textSelection(.enabled)
                                }
                                .padding(.vertical, 3)
                            }
                        }
                        .padding(12)
                    }
                }
            }
            .navigationTitle("Logs")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Clear") {
                        Logger.shared.clear()
                        logs = []
                    }
                    .font(Theme.monoCaption)
                    .foregroundColor(.red)
                }

                ToolbarItem(placement: .navigationBarTrailing) {
                    HStack(spacing: 12) {
                        Button(action: {
                            let text = logs.map { "[\($0.level.rawValue)] \($0.message)" }.joined(separator: "\n")
                            UIPasteboard.general.string = text
                        }) {
                            Image(systemName: "doc.on.doc")
                                .foregroundColor(Theme.accent)
                        }

                        Button("Close") {
                            presentationMode.wrappedValue.dismiss()
                        }
                        .font(Theme.monoCaption)
                        .foregroundColor(Theme.accent)
                    }
                }
            }
            .onAppear {
                logs = Logger.shared.snapshot()
            }
        }
        .navigationViewStyle(.stack)
    }
}
