import SwiftUI
import Combine

public struct LogsView: View {
    @Environment(\.presentationMode) private var presentationMode
    @State private var logs: [Logger.Entry] = []
    @State private var copied: Bool = false

    private let timer = Timer.publish(every: 0.5, on: .main, in: .common).autoconnect()

    public init() {}

    private func levelColor(_ level: Logger.Level) -> Color {
        switch level {
        case .info:
            return .secondary
        case .warn:
            return .orange
        case .error:
            return .red
        case .engine:
            return .blue
        }
    }

    public var body: some View {
        NavigationView {
            Group {
                if logs.isEmpty {
                    Text("No logs recorded")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                } else {
                    ScrollViewReader { proxy in
                        ScrollView {
                            VStack(alignment: .leading, spacing: 6) {
                                HStack {
                                    Text("JIT Status:")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                    Text(JITManager.statusDescription)
                                        .font(.caption)
                                        .fontWeight(.bold)
                                        .foregroundColor(JITManager.isJITEnabled ? .green : .orange)

                                    Spacer()

                                    Text("Arch: ARM64")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                                .background(Color(UIColor.secondarySystemBackground))
                                .cornerRadius(8)
                                .padding(.horizontal, 12)
                                .padding(.top, 4)

                                LazyVStack(alignment: .leading, spacing: 8) {
                                ForEach(logs) { entry in
                                    VStack(alignment: .leading, spacing: 3) {
                                        HStack(spacing: 6) {
                                            Text(entry.level.rawValue)
                                                .font(.caption2)
                                                .fontWeight(.bold)
                                                .padding(.horizontal, 6)
                                                .padding(.vertical, 2)
                                                .background(levelColor(entry.level).opacity(0.15))
                                                .foregroundColor(levelColor(entry.level))
                                                .cornerRadius(4)

                                            Spacer()

                                            Text(entry.timestamp, style: .time)
                                                .font(.caption2)
                                                .foregroundColor(.secondary)
                                        }

                                        Text(entry.message)
                                            .font(.system(size: 11, design: .monospaced))
                                            .foregroundColor(.primary)
                                            .textSelection(.enabled)
                                    }
                                    .id(entry.id)
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 4)
                                }
                            }
                            .padding(.vertical, 8)
                        }
                        .onAppear {
                            if let last = logs.last {
                                proxy.scrollTo(last.id, anchor: .bottom)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Diagnostic Logs")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button(role: .destructive) {
                        Logger.shared.clear()
                        logs = []
                    } label: {
                        Text("Clear")
                    }
                }

                ToolbarItemGroup(placement: .navigationBarTrailing) {
                    Button {
                        let text = logs.map { "[\($0.level.rawValue)] \($0.message)" }.joined(separator: "\n")
                        UIPasteboard.general.string = text
                        copied = true
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                            copied = false
                        }
                    } label: {
                        Image(systemName: copied ? "checkmark" : "doc.on.doc")
                    }

                    Button {
                        presentationMode.wrappedValue.dismiss()
                    } label: {
                        Text("Done")
                            .fontWeight(.semibold)
                    }
                }
            }
            .onAppear {
                logs = Logger.shared.snapshot()
            }
            .onReceive(timer) { _ in
                logs = Logger.shared.snapshot()
            }
        }
        .navigationViewStyle(.stack)
    }
}
