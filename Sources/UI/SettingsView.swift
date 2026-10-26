import SwiftUI
public struct SettingsView: View {
    @State private var availableBytes: Int64 = 0

    public init() {}

    public var body: some View {
        NavigationStack {
            Form {
                storageSection
                filesystemSection
                systemSection
            }
            .navigationTitle("Settings")
            .onAppear(perform: updateStats)
        }
    }

    private var storageSection: some View {
        Section("Device Storage") {
            HStack {
                Text("Available Space")
                Spacer()
                Text(ByteCountFormatter.string(fromByteCount: availableBytes, countStyle: .file))
                    .foregroundColor(.secondary)
            }
        }
    }

    private var filesystemSection: some View {
        Section("Host-Guest Sharing") {
            VStack(alignment: .leading, spacing: 6) {
                Text("iOS Files Integration")
                    .font(.headline)
                Text("Files placed in 'On My iPhone/unixruner/Shared' are automatically mounted inside the Linux guest at `/mnt/host_share` via virtio-9p.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding(.vertical, 4)
        }
    }

    private var systemSection: some View {
        Section("Runtime & Entitlements") {
            HStack {
                Text("JIT Acceleration")
                Spacer()
                Text("Dynamic Codesigning")
                    .font(.caption)
                    .foregroundColor(.green)
            }

            HStack {
                Text("Memory Cap")
                Spacer()
                Text("Extended (Jetsam Guarded)")
                    .font(.caption)
                    .foregroundColor(.blue)
            }
        }
    }

    private func updateStats() {
        availableBytes = DiskManager.shared.availableDeviceDiskSpaceBytes()
    }
}
