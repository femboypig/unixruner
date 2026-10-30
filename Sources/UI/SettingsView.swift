import SwiftUI

public struct SettingsView: View {
    @Environment(\.presentationMode) var presentationMode
    @State private var logs: [Logger.Entry] = []
    @State private var timer: Timer?

    public init() {}

    private var jitEnabled: Bool {
        #if targetEnvironment(simulator)
        return true
        #else
        var info = mach_task_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size / 4)
        let kerr = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), $0, &count)
            }
        }
        return kerr == KERN_SUCCESS
        #endif
    }

    public var body: some View {
        NavigationView {
            ZStack {
                Theme.background.ignoresSafeArea()

                List {
                    Section(header: Text("ENVIRONMENT").font(Theme.monoCaption)) {
                        HStack {
                            Text("JIT Status")
                            Spacer()
                            Text(jitEnabled ? "Active" : "Restricted")
                                .font(Theme.monoCaption)
                                .foregroundColor(jitEnabled ? Theme.runningGreen : .red)
                        }

                        HStack {
                            Text("Target Architecture")
                            Spacer()
                            Text("ARM64 (Apple A10+)")
                                .font(Theme.monoCaption)
                                .foregroundColor(.gray)
                        }

                        HStack {
                            Text("Deployment")
                            Spacer()
                            Text("iOS 15.0+")
                                .font(Theme.monoCaption)
                                .foregroundColor(.gray)
                        }
                    }
                    .listRowBackground(Theme.cardBackground)

                    Section(header: Text("DIAGNOSTIC LOGS").font(Theme.monoCaption)) {
                        if logs.isEmpty {
                            Text("No logs recorded")
                                .font(Theme.monoCaption)
                                .foregroundColor(.gray)
                        } else {
                            ForEach(logs) { entry in
                                VStack(alignment: .leading, spacing: 2) {
                                    HStack {
                                        Text(entry.level.rawValue)
                                            .font(.system(size: 10, weight: .bold, design: .monospaced))
                                            .padding(.horizontal, 4)
                                            .padding(.vertical, 2)
                                            .background(Color.white.opacity(0.1))
                                            .cornerRadius(4)

                                        Spacer()

                                        Text(entry.timestamp, style: .time)
                                            .font(.system(size: 10, design: .monospaced))
                                            .foregroundColor(.gray)
                                    }

                                    Text(entry.message)
                                        .font(.system(size: 12, design: .monospaced))
                                        .foregroundColor(Theme.terminalForeground)
                                }
                                .padding(.vertical, 4)
                            }
                        }
                    }
                    .listRowBackground(Theme.cardBackground)
                }
                .listStyle(.insetGrouped)
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        presentationMode.wrappedValue.dismiss()
                    }
                    .foregroundColor(Theme.accent)
                }
            }
            .onAppear {
                refreshLogs()
            }
        }
        .navigationViewStyle(.stack)
    }

    private func refreshLogs() {
        logs = Logger.shared.snapshot()
    }
}
