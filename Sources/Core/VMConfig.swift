import Foundation

public struct VMConfig: Codable, Identifiable, Equatable, Hashable {
    public var id: UUID
    public var name: String
    public var architecture: Architecture
    public var diskFormat: DiskFormat
    public var memoryMB: Int
    public var cpuCores: Int
    public var diskSizeBytes: Int64
    public var kernelRelativePath: String?
    public var initrdRelativePath: String?
    public var diskRelativePath: String
    public var extraBootArgs: String
    public var portMappings: [PortMapping]
    public var sharedFolderEnabled: Bool
    public var createdAt: Date
    public var updatedAt: Date

    public init(
        id: UUID = UUID(),
        name: String,
        architecture: Architecture = .arm64,
        diskFormat: DiskFormat = .qcow2,
        memoryMB: Int = 1024,
        cpuCores: Int = 2,
        diskSizeBytes: Int64 = 8 * 1024 * 1024 * 1024, // 8 GB
        kernelRelativePath: String? = nil,
        initrdRelativePath: String? = nil,
        diskRelativePath: String = "rootfs.qcow2",
        extraBootArgs: String = "console=ttyAMA0 root=/dev/vda rw",
        portMappings: [PortMapping] = [.defaultSSH],
        sharedFolderEnabled: Bool = true,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.architecture = architecture
        self.diskFormat = diskFormat
        self.memoryMB = memoryMB
        self.cpuCores = cpuCores
        self.diskSizeBytes = diskSizeBytes
        self.kernelRelativePath = kernelRelativePath
        self.initrdRelativePath = initrdRelativePath
        self.diskRelativePath = diskRelativePath
        self.extraBootArgs = extraBootArgs
        self.portMappings = portMappings
        self.sharedFolderEnabled = sharedFolderEnabled
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    public var distroIcon: String {
        let lower = name.lowercased()
        if lower.contains("alpine") {
            return "mountain.2.fill"
        } else if lower.contains("debian") {
            return "swirl.circle.righthalf.filled"
        } else if lower.contains("ubuntu") {
            return "circle.circle.fill"
        } else if lower.contains("arch") {
            return "arrowtriangle.up.fill"
        } else if lower.contains("void") {
            return "rhombus.fill"
        } else {
            return "terminal.fill"
        }
    }
}
