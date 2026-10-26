import XCTest
import Darwin
@testable import unixruner

final class TerminalSocketBridgeTests: XCTestCase {
    func testFindAvailablePortReturnsValidPort() {
        let port = TerminalSocketBridge.findAvailablePort()
        XCTAssertGreaterThan(port, 1024, "Ephemeral port must be in unprivileged user range > 1024")
    }

    func testSocketLoopbackCommunication() throws {
        let bridge = TerminalSocketBridge()
        let port = TerminalSocketBridge.findAvailablePort()

        // Create a local TCP listening server
        let serverSock = socket(AF_INET, SOCK_STREAM, 0)
        XCTAssertGreaterThanOrEqual(serverSock, 0)
        defer { close(serverSock) }

        var reuse: Int32 = 1
        setsockopt(serverSock, SOL_SOCKET, SO_REUSEADDR, &reuse, socklen_t(MemoryLayout<Int32>.size))

        var addr = sockaddr_in()
        addr.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_port = port.bigEndian
        addr.sin_addr.s_addr = inet_addr("127.0.0.1")

        let bindRes = withUnsafePointer(to: &addr) { ptr in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { saPtr in
                bind(serverSock, saPtr, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        XCTAssertEqual(bindRes, 0, "Server bind failed")
        listen(serverSock, 1)

        let connectExpectation = expectation(description: "Bridge connects to server socket")
        let outputExpectation = expectation(description: "Bridge receives data from server")

        var acceptedClient: Int32 = -1
        let serverThread = Thread {
            acceptedClient = accept(serverSock, nil, nil)
            if acceptedClient >= 0 {
                // Send hello message to client
                let msg = "Welcome to Alpine Linux!\r\nlocalhost:~# "
                msg.withCString { ptr in
                    _ = send(acceptedClient, ptr, strlen(ptr), 0)
                }
            }
        }
        serverThread.start()

        bridge.onOutput = { data in
            if let str = String(data: data, encoding: .utf8), str.contains("Welcome to Alpine Linux!") {
                outputExpectation.fulfill()
            }
        }

        bridge.connect(port: port, maxAttempts: 50, intervalSeconds: 0.05) { success in
            XCTAssertTrue(success, "Bridge connect should succeed")
            connectExpectation.fulfill()
        }

        wait(for: [connectExpectation, outputExpectation], timeout: 5.0)

        bridge.disconnect()
        if acceptedClient >= 0 {
            close(acceptedClient)
        }
    }
}
