import Foundation
public enum VMState: Equatable {
    case stopped
    case starting
    case running
    case paused
    case terminated(exitCode: Int32)
    case failed(reason: String)

    public var isActive: Bool {
        switch self {
        case .starting, .running, .paused:
            return true
        case .stopped, .terminated, .failed:
            return false
        }
    }
}

public protocol VMEngineDelegate: AnyObject {
    func vmEngine(_ engine: VMEngineProtocol, didChangeState state: VMState)
    func vmEngine(_ engine: VMEngineProtocol, didReceiveOutput data: Data)
}

public protocol VMEngineProtocol: AnyObject {
    var state: VMState { get }
    var delegate: VMEngineDelegate? { get set }

    func start(with config: VMConfig, diskURL: URL, kernelURL: URL?, initrdURL: URL?) throws
    func sendInput(_ data: Data)
    func pause()
    func resume()
    func stop()
}
