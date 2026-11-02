import Foundation

public struct VMConfig: Codable, Identifiable, Equatable {
    public var id: UUID
    public var name: String
    public var architecture: Architecture
    public var memoryMB: Int
    public var cpuCount: Int
    public var kernelPath: String?
    public var initrdPath: String?
    public var cmdline: String?
    public var drivePath: String?
    public var serialPort: Int

    public init(
        id: UUID = UUID(),
        name: String,
        architecture: Architecture = .arm64,
        memoryMB: Int = 512,
        cpuCount: Int = 1,
        kernelPath: String? = nil,
        initrdPath: String? = nil,
        cmdline: String? = nil,
        drivePath: String? = nil,
        serialPort: Int = 4444
    ) {
        self.id = id
        self.name = name
        self.architecture = architecture
        self.memoryMB = memoryMB
        self.cpuCount = cpuCount
        self.kernelPath = kernelPath
        self.initrdPath = initrdPath
        self.cmdline = cmdline
        self.drivePath = drivePath
        self.serialPort = serialPort
    }

    public static func defaultAlpine(kernelPath: String, initrdPath: String) -> VMConfig {
        VMConfig(
            id: UUID(),
            name: "Alpine Linux",
            architecture: .arm64,
            memoryMB: 512,
            cpuCount: 1,
            kernelPath: kernelPath,
            initrdPath: initrdPath,
            cmdline: Architecture.arm64.defaultConsole,
            drivePath: nil,
            serialPort: 4444
        )
    }
}
