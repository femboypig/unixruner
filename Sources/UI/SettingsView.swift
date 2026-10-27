import SwiftUI
import UIKit

public struct SettingsView: View {
    @State private var availableBytes: Int64 = 0
    @State private var usedBytes: Int64 = 0
    @State private var showingCacheCleanedAlert = false
    @State private var showingLogsSheet = false
    @State private var showingLogsClearedAlert = false
    @State private var logContent = ""

    @AppStorage("defaultArchitecture") private var defaultArchRaw: String = "arm64"
    @AppStorage("defaultMemoryMB") private var defaultMemoryMB: Int = 1024
    @AppStorage("terminalFontSize") private var terminalFontSize: Double = 13.0

    public init() {}

    public var body: some View {
        NavigationStack {
            Form {
                storageSection
                filesystemSection
                defaultsSection
                terminalSection
                diagnosticsSection
            }
            .navigationTitle("Settings")
            .onAppear(perform: calculateSpace)
            .sheet(isPresented: $showingLogsSheet) {
                logsSheetView
            }
            .alert("Cache Cleared", isPresented: $showingCacheCleanedAlert) {
                Button("OK", role: .cancel) {}
            } message: {
                Text("Temporary download cache has been cleaned.")
            }
            .alert("Logs Cleared", isPresented: $showingLogsClearedAlert) {
                Button("OK", role: .cancel) {}
            } message: {
                Text("Developer diagnostic log file has been cleared.")
            }
        }
    }

    private var storageSection: some View {
        Section("Storage") {
            HStack {
                Text("Available on Device")
                Spacer()
                Text(ByteCountFormatter.string(fromByteCount: availableBytes, countStyle: .file))
                    .foregroundColor(.secondary)
            }

            HStack {
                Text("Used by Virtual Machines")
                Spacer()
                Text(ByteCountFormatter.string(fromByteCount: usedBytes, countStyle: .file))
                    .foregroundColor(.secondary)
            }

            Button("Clean Temporary Cache") {
                clearTempCache()
            }
        }
    }

    private var filesystemSection: some View {
        Section("File Sharing") {
            Button {
                openSharedFolder()
            } label: {
                Label("Open Shared Folder in Files", systemImage: "folder")
            }

            Text("Shared path: Files.app → On My iPhone → unixruner → Shared")
                .font(.caption2)
                .foregroundColor(.secondary)
        }
    }

    private var defaultsSection: some View {
        Section("VM Defaults") {
            Picker("Default Architecture", selection: $defaultArchRaw) {
                Text("ARM64").tag("arm64")
                Text("AMD64").tag("x86_64")
            }

            Stepper("Default RAM: \(defaultMemoryMB) MB", value: $defaultMemoryMB, in: 512...3072, step: 256)
        }
    }

    private var terminalSection: some View {
        Section("Terminal") {
            Picker("Font Size", selection: $terminalFontSize) {
                Text("Small (11pt)").tag(11.0)
                Text("Medium (13pt)").tag(13.0)
                Text("Large (15pt)").tag(15.0)
                Text("Extra Large (17pt)").tag(17.0)
            }
        }
    }

    private var diagnosticsSection: some View {
        Section("Diagnostics & Developer Logs") {
            Button {
                logContent = AppLogger.shared.readRecentLogs()
                showingLogsSheet = true
            } label: {
                Label("View Developer Logs", systemImage: "doc.text.magnifyingglass")
            }

            ShareLink(item: AppLogger.shared.logFileURL) {
                Label("Export Developer Logs", systemImage: "square.and.arrow.up")
            }

            Button(role: .destructive) {
                AppLogger.shared.clear()
                showingLogsClearedAlert = true
            } label: {
                Label("Clear Logs", systemImage: "trash")
            }
        }
    }

    private var logsSheetView: some View {
        NavigationStack {
            ScrollView {
                Text(logContent)
                    .font(.system(size: 11, design: .monospaced))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding()
            }
            .navigationTitle("Developer Logs")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Close") {
                        showingLogsSheet = false
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    ShareLink(item: AppLogger.shared.logFileURL) {
                        Image(systemName: "square.and.arrow.up")
                    }
                }
            }
        }
    }

    private func calculateSpace() {
        availableBytes = DiskManager.shared.availableDeviceDiskSpaceBytes()

        let baseDir = DiskManager.shared.baseVMDirectory
        let resourceKeys: [URLResourceKey] = [.fileSizeKey]
        guard let enumerator = FileManager.default.enumerator(
            at: baseDir,
            includingPropertiesForKeys: resourceKeys,
            options: [.skipsHiddenFiles]
        ) else { return }

        var total: Int64 = 0
        for case let fileURL as URL in enumerator {
            guard let values = try? fileURL.resourceValues(forKeys: [.fileSizeKey]),
                  let size = values.fileSize else { continue }
            total += Int64(size)
        }
        usedBytes = total
    }

    private func clearTempCache() {
        let tempDir = FileManager.default.temporaryDirectory
        try? FileManager.default.removeItem(at: tempDir)
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        calculateSpace()
        showingCacheCleanedAlert = true
    }

    private func openSharedFolder() {
        let sharedURL = DiskManager.shared.sharedFolderDirectory
        if let filesURL = URL(string: "shareddocuments://\(sharedURL.path)"),
           UIApplication.shared.canOpenURL(filesURL) {
            UIApplication.shared.open(filesURL)
        } else {
            // Fallback to documents URL
            UIApplication.shared.open(sharedURL)
        }
    }
}
