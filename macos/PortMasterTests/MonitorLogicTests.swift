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

    func testNameSort() {
        func entry(_ name: String, _ pid: UInt32) -> ProcessEntry {
            ProcessEntry(
                key: ProcessKey(pid: pid, startSec: 10, startUsec: 1),
                name: name,
                cpuPercent: nil,
                rssBytes: nil,
                status: .running,
                parentPid: 1,
                cwd: .unavailable("x"),
                executable: .unavailable("x"),
                contextDisplay: nil,
                contextKind: nil,
            )
        }
        XCTAssertTrue(MonitorLogic.compareProcess(entry("alpha", 2), entry("beta", 1), by: .name, descending: false))
        XCTAssertTrue(MonitorLogic.compareProcess(entry("beta", 1), entry("alpha", 2), by: .name, descending: true))
        // 名称相同按 PID 稳定排序
        XCTAssertTrue(MonitorLogic.compareProcess(entry("node", 1), entry("node", 2), by: .name, descending: false))
        XCTAssertTrue(MonitorLogic.compareProcess(entry("node", 1), entry("node", 2), by: .name, descending: true))
    }

    func testTimeSort() {
        func entry(_ seconds: Double?, _ pid: UInt32) -> ProcessEntry {
            ProcessEntry(
                key: ProcessKey(pid: pid, startSec: 10, startUsec: 1),
                name: "p\(pid)",
                cpuPercent: nil,
                cpuTimeSeconds: seconds,
                rssBytes: nil,
                status: .running,
                parentPid: 1,
                cwd: .unavailable("x"),
                executable: .unavailable("x"),
                contextDisplay: nil,
                contextKind: nil,
            )
        }
        XCTAssertTrue(MonitorLogic.compareProcess(entry(100, 1), entry(50, 2), by: .time, descending: true))
        XCTAssertTrue(MonitorLogic.compareProcess(entry(50, 2), entry(100, 1), by: .time, descending: false))
        // 无 TIME 读数的排在最后（降序时）
        XCTAssertTrue(MonitorLogic.compareProcess(entry(50, 2), entry(nil, 3), by: .time, descending: true))
    }

    func testSamplingGapDetection() {
        let t0 = Date()
        XCTAssertFalse(MonitorLogic.hasSamplingGap(previous: t0, current: t0.addingTimeInterval(1), tickSeconds: 1))
        XCTAssertTrue(MonitorLogic.hasSamplingGap(previous: t0, current: t0.addingTimeInterval(8), tickSeconds: 1))
    }

    func testStableScaleHysteresis() {
        // 初始：nice(峰值×1.15) = nice(920) = 1000
        XCTAssertEqual(MonitorLogic.stableScale(current: nil, maxValue: 800), 1000)
        // 新峰值在当前量程内且未收缩到 45% 以下 → 保持
        XCTAssertEqual(MonitorLogic.stableScale(current: 1000, maxValue: 700), 1000)
        // 新峰值超出当前量程 → 上调至 nice(2300) = 5000
        XCTAssertEqual(MonitorLogic.stableScale(current: 1000, maxValue: 2000), 5000)
        // 新峰值明显低于当前量程 45% → 下调至 nice(115) = 200
        XCTAssertEqual(MonitorLogic.stableScale(current: 1000, maxValue: 100), 200)
    }

    func testDedupeSockets() {
        func socket(_ pid: UInt32, _ proto: ProtocolKind, _ address: String, _ port: UInt16) -> SocketEntry {
            SocketEntry(
                pid: pid,
                processKey: ProcessKey(pid: pid, startSec: 1, startUsec: 1),
                processName: "p\(pid)",
                protocolKind: proto,
                state: proto == .udp ? .none : .listen,
                localAddress: address,
                localPort: port,
                remoteAddress: nil,
                remotePort: nil,
            )
        }
        let rows = [
            socket(100, .udp, "0.0.0.0", 5353),
            socket(100, .udp, "0.0.0.0", 5353),   // SO_REUSEPORT 重复 → 合并
            socket(100, .udp, "0.0.0.0", 5353),   // SO_REUSEPORT 重复 → 合并
            socket(100, .udp, "::", 5353),        // IPv4/IPv6 变体 → 保留
            socket(100, .tcp, "0.0.0.0", 5353),   // 协议变体 → 保留
            socket(200, .udp, "0.0.0.0", 5353),   // 不同进程 → 保留
        ]
        let result = MonitorLogic.dedupeSockets(rows)
        XCTAssertEqual(result.count, 4)
        XCTAssertEqual(Set(result.map(\.id)).count, 4)
    }

    func testTrendChartYMaxForRSSBytes() {
        let peak = 100 * 1024 * 1024
        let yMax = MonitorLogic.trendChartYMax(values: [Double(peak)])
        XCTAssertEqual(yMax, Double(peak) * 1.2, accuracy: 1)
        XCTAssertGreaterThan(yMax, 1_000_000)
    }
}
