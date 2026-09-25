import XCTest
@testable import PortMaster

final class MonitorLogicTests: XCTestCase {
    func testStaleThreshold() {
        XCTAssertEqual(MonitorLogic.staleThresholdMs(intervalMs: 1000), 5000)
        XCTAssertEqual(MonitorLogic.staleThresholdMs(intervalMs: 2000), 6000)
    }

    func testStaleDetection() {
        let now = Date()
        let old = now.addingTimeInterval(-7)
        XCTAssertTrue(MonitorLogic.isSnapshotStale(capturedAt: old, intervalMs: 2000, sourceFailed: false, now: now))
        let fresh = now.addingTimeInterval(-1)
        XCTAssertFalse(MonitorLogic.isSnapshotStale(capturedAt: fresh, intervalMs: 2000, sourceFailed: false, now: now))
        XCTAssertTrue(MonitorLogic.isSnapshotStale(capturedAt: now, intervalMs: 2000, sourceFailed: true, now: now))
    }

    func testNumericPortOwnership() {
        let ownerKey = ProcessKey(pid: 8787, startSec: 10, startUsec: 1)
        let owner = ProcessEntry(
            key: ownerKey,
            name: "node",
            cpuPercent: 1,
            rssBytes: 100,
            status: .running,
            parentPid: 1,
            cwd: .available("/tmp"),
            executable: .available("/bin/node"),
            contextDisplay: nil,
            contextKind: nil,
        )
        let ports: Set<Int> = [8787]
        XCTAssertTrue(MonitorLogic.matchesProcessSearch(owner, query: "8787", listenPorts: ports))
        let other = ProcessEntry(
            key: ProcessKey(pid: 2, startSec: 10, startUsec: 1),
            name: "python",
            cpuPercent: nil,
            rssBytes: nil,
            status: .running,
            parentPid: 1,
            cwd: .unavailable("x"),
            executable: .unavailable("x"),
            contextDisplay: nil,
            contextKind: nil,
        )
        XCTAssertFalse(MonitorLogic.matchesProcessSearch(other, query: "8787", listenPorts: []))
    }

    func testListenerFilter() {
        let listen = SocketEntry(
            pid: 1,
            processKey: ProcessKey(pid: 1, startSec: 1, startUsec: 1),
            processName: "node",
            protocolKind: .tcp,
            state: .listen,
            localAddress: "127.0.0.1",
            localPort: 3000,
            remoteAddress: nil,
            remotePort: nil,
        )
        XCTAssertTrue(MonitorLogic.listenerPortFilter(listen))
        var udp = listen
        udp.protocolKind = .udp
        udp.state = .none
        XCTAssertTrue(MonitorLogic.listenerPortFilter(udp))
    }
}
