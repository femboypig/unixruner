import Foundation

public enum DiskFormat: String, Codable, CaseIterable, Identifiable, Hashable {
    case qcow2 = "qcow2"
    case raw = "raw"

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .qcow2:
            return "QCOW2 (Dynamic)"
        case .raw:
            return "RAW (Preallocated)"
        }
    }

    public var subtitle: String {
        switch self {
        case .qcow2:
            return "Grows on demand, supports snapshots"
        case .raw:
            return "Fastest I/O, allocates full size immediately"
        }
    }

    public var fileExtension: String {
        switch self {
        case .qcow2:
            return "qcow2"
        case .raw:
            return "raw"
        }
    }

    public var qemuDriver: String {
        rawValue
    }
}
