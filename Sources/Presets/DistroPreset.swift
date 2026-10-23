import Foundation
import Core

public enum BootMethod: String, Codable {
    case directKernel
    case cloudImage
}

public struct DistroAsset: Codable, Equatable {
    public let url: URL
    public let expectedChecksumSHA256: String?
    public let filename: String

    public init(url: URL, expectedChecksumSHA256: String? = nil, filename: String) {
        self.url = url
        self.expectedChecksumSHA256 = expectedChecksumSHA256
        self.filename = filename
    }
}

public struct DistroArchitectureSpec: Codable, Equatable {
    public let architecture: Architecture
    public let kernelAsset: DistroAsset?
    public let initrdAsset: DistroAsset?
    public let diskAsset: DistroAsset
    public let defaultBootArgs: String

    public init(
        architecture: Architecture,
        kernelAsset: DistroAsset? = nil,
        initrdAsset: DistroAsset? = nil,
        diskAsset: DistroAsset,
        defaultBootArgs: String
    ) {
        self.architecture = architecture
        self.kernelAsset = kernelAsset
        self.initrdAsset = initrdAsset
        self.diskAsset = diskAsset
        self.defaultBootArgs = defaultBootArgs
    }
}

public struct DistroPreset: Identifiable, Codable, Equatable {
    public let id: String
    public let name: String
    public let tag: String
    public let summary: String
    public let packageManager: String
    public let defaultUser: String
    public let defaultPassword: String?
    public let bootMethod: BootMethod
    public let recommendedMemoryMB: Int
    public let recommendedCores: Int
    public let recommendedDiskBytes: Int64
    public let specs: [Architecture: DistroArchitectureSpec]

    public init(
        id: String,
        name: String,
        tag: String,
        summary: String,
        packageManager: String,
        defaultUser: String,
        defaultPassword: String?,
        bootMethod: BootMethod,
        recommendedMemoryMB: Int,
        recommendedCores: Int,
        recommendedDiskBytes: Int64,
        specs: [Architecture: DistroArchitectureSpec]
    ) {
        self.id = id
        self.name = name
        self.tag = tag
        self.summary = summary
        self.packageManager = packageManager
        self.defaultUser = defaultUser
        self.defaultPassword = defaultPassword
        self.bootMethod = bootMethod
        self.recommendedMemoryMB = recommendedMemoryMB
        self.recommendedCores = recommendedCores
        self.recommendedDiskBytes = recommendedDiskBytes
        self.specs = specs
    }
}
