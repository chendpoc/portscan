import Darwin
import XCTest
@testable import PortMaster

/// 回归测试：proc_taskinfo 的 pti_total_user/system 单位是 Mach 绝对时间 tick
/// （Apple Silicon 24MHz），必须经 mach_timebase_info 换算纳秒。
/// 曾误当纳秒直接 ÷1e9，导致全部进程 CPU 被低估约 41.7 倍（2026-09 修复）。
final class ProcessCollectorTests: XCTestCase {
    /// 忙线程跑满一个核心，对照 getrusage（timeval，单位确定）验证采集速率。
    func testProcessCPUMatchesRusageGroundTruth() throws {
        let collector = ProcessCollector()
        let pid = UInt32(getpid())

        let running = LockedFlag()
        Thread.detachNewThread {
            var x = 0.0
            while running.value {
                x += 1
                if x > 1e15 { x = 0 }
            }
        }

        guard case .success = collector.sample(generation: 1) else {
            XCTFail("首次采样失败")
            running.value = false
            return
        }

        let r0 = Self.rusageSeconds()
        let t0 = Date()
        Thread.sleep(forTimeInterval: 1.5)
        let elapsed = Date().timeIntervalSince(t0)
        let r1 = Self.rusageSeconds()
        running.value = false

        guard case .success(let snapshot) = collector.sample(generation: 2) else {
            XCTFail("二次采样失败")
            return
        }
        let entry = snapshot.entries.first { $0.key.pid == pid }
        guard let measured = entry?.cpuPercent else {
            XCTFail("当前进程缺少 CPU 读数")
            return
        }

        let cores = Double(ProcessInfo.processInfo.processorCount)
        let expectedRate = (r1 - r0) / elapsed // core-secs/sec，≈1.0
        let measuredRate = measured / 100 * cores
        XCTAssertGreaterThan(expectedRate, 0.8, "忙线程基准异常：\(expectedRate)")
        XCTAssertEqual(
            measuredRate,
            expectedRate,
            accuracy: expectedRate * 0.12,
            "CPU 采集速率 \(measuredRate) 与 getrusage 基准 \(expectedRate) 偏差超过 12%",
        )
    }

    private static func rusageSeconds() -> Double {
        var ru = Darwin.rusage()
        getrusage(RUSAGE_SELF, &ru)
        let sec = Double(ru.ru_utime.tv_sec + ru.ru_stime.tv_sec)
        let usec = Double(ru.ru_utime.tv_usec + ru.ru_stime.tv_usec)
        return sec + usec / 1_000_000
    }

    /// 清单完整性：sysctl KERN_PROC_ALL 枚举应覆盖 proc_listpids 的几乎全部进程。
    /// 回归防护：曾用 proc_pidinfo 作枚举源，210/584（36%）进程被静默丢弃。
    func testInventoryCompleteness() throws {
        let collector = ProcessCollector()
        guard case .success(let snapshot) = collector.sample(generation: 1) else {
            XCTFail("采样失败")
            return
        }
        var byteSize = proc_listpids(UInt32(PROC_ALL_PIDS), 0, nil, 0)
        let capacity = Int(byteSize) / MemoryLayout<pid_t>.size
        var pids = [pid_t](repeating: 0, count: capacity)
        byteSize = proc_listpids(UInt32(PROC_ALL_PIDS), 0, &pids, Int32(capacity * MemoryLayout<pid_t>.size))
        let expected = pids.filter { $0 > 0 }.count
        // 允许进程进出抖动，但覆盖率不得低于 90%
        XCTAssertGreaterThan(
            Double(snapshot.entries.count),
            Double(expected) * 0.9,
            "清单覆盖不足：\(snapshot.entries.count) / \(expected)",
        )
        // 自身进程的线程数应可读（#TH 列数据源）
        let selfEntry = snapshot.entries.first { $0.key.pid == UInt32(getpid()) }
        XCTAssertGreaterThan(selfEntry?.threadCount ?? 0, 0, "线程数不可读")
    }
}

private final class LockedFlag {
    private var storage = true // 忙线程自旋条件：初始必须为 true
    private let lock = NSLock()

    var value: Bool {
        get {
            lock.lock()
            defer { lock.unlock() }
            return storage
        }
        set {
            lock.lock()
            defer { lock.unlock() }
            storage = newValue
        }
    }
}
