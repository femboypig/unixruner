import Foundation

public enum TransportProtocol: String, Codable, CaseIterable {
    case tcp
    case udp
}

public struct PortMapping: Codable, Identifiable, Equatable {
    public var id: UUID
    public var name: String
    public var hostPort: UInt16
    public var guestPort: UInt16
    public var `protocol`: TransportProtocol

    public init(
        id: UUID = UUID(),
        name: String,
        hostPort: UInt16,
        guestPort: UInt16,
        `protocol`: TransportProtocol = .tcp
    ) {
        self.id = id
        self.name = name
        self.hostPort = hostPort
        self.guestPort = guestPort
        self.protocol = `protocol`
    }

    public var qemuHostfwdRule: String {
        "\(`protocol`.rawValue)::\(hostPort)-:\(guestPort)"
    }

    public static var defaultSSH: PortMapping {
        PortMapping(name: "SSH", hostPort: 2222, guestPort: 22, protocol: .tcp)
    }
}
