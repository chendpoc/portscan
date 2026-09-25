import Darwin
import Foundation

final class ProcessCollector {
    private struct CPUSample {
        var user: UInt64
        var system: UInt64
    }

    /// sysctl KERN_PROC_ALL 的一行：身份字段全部可读（ps/top 同源），
    /// 不依赖 proc_pidinfo(PROC_PIDTBSDINFO)——后者对部分进程返回失败，
    /// 曾导致约 1/3 进程被静默丢弃。
    private struct ProcRow {
        var pid: pid_t
        var key: ProcessKey
        var comm: String
        var status: Int32
        var ppid: UInt32
    }

    private var previousKeys: [UInt32: ProcessKey] = [:]
    private var previousCPU: [UInt32: CPUSample] = [:]
    private var lastSampleAt: Date?
    private let minimumInterval: TimeInterval = 0.2

    /// pti_total_user/system 的单位是 Mach 绝对时间 tick，不是纳秒。
    /// Apple Silicon 上 1 tick = 125/3 ns（24MHz），必须经 mach_timebase_info 换算，
    /// 否则所有进程 CPU 会被低估约 41.7 倍。
    private let tickToNanoseconds: Double = {
        var info = mach_timebase_info_data_t()
        mach_timebase_info(&info)
        return Double(info.numer) / Double(info.denom)
    }()

    func sample(generation: UInt64) -> Result<ProcessSnapshot, CollectorError> {
        let sampleReady = lastSampleAt.map { Date().timeIntervalSince($0) >= minimumInterval } ?? false
        let rows = listAllProcesses()
        guard !rows.isEmpty else { return .failure(.process("Unable to list processes")) }
        var entries: [ProcessEntry] = []
        entries.reserveCapacity(rows.count)
        var currentKeys: [UInt32: ProcessKey] = [:]

        for row in rows {
            let key = row.key
            let name = processName(pid: row.pid) ?? row.comm
            let task = readTaskInfo(pid: row.pid)
            let cpu = cpuPercent(pid: UInt32(row.pid), key: key, sample: task, sampleReady: sampleReady)
            let context = ProcessContextReader.read(key: key)
            entries.append(
                ProcessEntry(
                    key: key,
                    name: name.isEmpty ? "pid-\(row.pid)" : name,
                    cpuPercent: cpu,
                    cpuTimeSeconds: task.map { Double($0.user &+ $0.system) * tickToNanoseconds / 1_000_000_000 },
                    threadCount: task?.threads,
                    rssBytes: task?.residentSize,
                    status: mapStatus(row.status),
                    parentPid: row.ppid,
                    cwd: context.cwd,
                    executable: context.executable,
                    contextDisplay: context.contextDisplay,
                    contextKind: context.contextKind,
                ),
            )
            currentKeys[UInt32(row.pid)] = key
        }

        previousKeys = currentKeys
        lastSampleAt = Date()
        return .success(ProcessSnapshot(generation: generation, capturedAt: Date(), entries: entries))
    }

    /// 主枚举源：sysctl KERN_PROC_ALL（kinfo_proc）。
    /// PID、启动时间（sec/usec）、状态、父进程、comm 名一次拿全。
    private func listAllProcesses() -> [ProcRow] {
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_ALL, 0]
        var byteCount = 0
        guard sysctl(&mib, 4, nil, &byteCount, nil, 0) == 0, byteCount > 0 else { return [] }
        var procs = [kinfo_proc](repeating: kinfo_proc(), count: byteCount / MemoryLayout<kinfo_proc>.stride)
        guard sysctl(&mib, 4, &procs, &byteCount, nil, 0) == 0 else { return [] }
        let count = byteCount / MemoryLayout<kinfo_proc>.stride

        var rows: [ProcRow] = []
        rows.reserveCapacity(count)
        for index in 0..<count {
            let proc = procs[index]
            let pid = proc.kp_proc.p_pid
            guard pid > 0 else { continue }
            let start = proc.kp_proc.p_starttime
            let key = ProcessKey(
                pid: UInt32(pid),
                startSec: UInt64(bitPattern: Int64(start.tv_sec)),
                startUsec: UInt64(bitPattern: Int64(start.tv_usec)),
            )
            let comm = withUnsafeBytes(of: proc.kp_proc.p_comm) { raw -> String in
                guard let base = raw.baseAddress else { return "" }
                return String(validatingUTF8: base.assumingMemoryBound(to: CChar.self)) ?? ""
            }
            rows.append(
                ProcRow(
                    pid: pid,
                    key: key,
                    comm: comm,
                    status: Int32(proc.kp_proc.p_stat),
                    ppid: UInt32(bitPattern: proc.kp_eproc.e_ppid),
                ),
            )
        }
        return rows
    }

    /// proc_name 可返回比 p_comm（16 字符截断）更完整的名字；失败时用 comm 兜底。
    private func processName(pid: pid_t) -> String? {
        var buffer = [CChar](repeating: 0, count: 1024)
        let result = proc_name(pid, &buffer, UInt32(buffer.count))
        guard result > 0 else { return nil }
        return String(validatingUTF8: buffer)
    }

    private struct TaskInfo {
        var residentSize: UInt64
        var user: UInt64
        var system: UInt64
        var threads: UInt32
    }

    /// CPU/RSS/线程数对其他用户的进程可能不可读——返回 nil，UI 显示「采样…」而非伪造。
    private func readTaskInfo(pid: pid_t) -> TaskInfo? {
        var info = proc_taskinfo()
        let size = Int32(MemoryLayout<proc_taskinfo>.size)
        guard proc_pidinfo(pid, PROC_PIDTASKINFO, 0, &info, size) == size else { return nil }
        return TaskInfo(
            residentSize: info.pti_resident_size,
            user: info.pti_total_user,
            system: info.pti_total_system,
            threads: UInt32(clamping: info.pti_threadnum),
        )
    }

    private func cpuPercent(pid: UInt32, key: ProcessKey, sample: TaskInfo?, sampleReady: Bool) -> Double? {
        guard let sample else { return nil }
        // 基线存储不受 sampleReady 门控：首个样本也存基线，
        // 否则要第三次采样才有值；仅计算时要求间隔 ≥ minimumInterval。
        guard sampleReady, previousKeys[pid] == key, let previous = previousCPU[pid] else {
            previousCPU[pid] = CPUSample(user: sample.user, system: sample.system)
            return nil
        }
        let deltaUser = sample.user &- previous.user
        let deltaSys = sample.system &- previous.system
        previousCPU[pid] = CPUSample(user: sample.user, system: sample.system)
        guard let lastSampleAt else { return nil }
        let elapsed = Date().timeIntervalSince(lastSampleAt)
        guard elapsed > 0 else { return nil }
        let total = Double(deltaUser + deltaSys) * tickToNanoseconds / 1_000_000_000
        let cores = max(1, ProcessInfo.processInfo.processorCount)
        let percent = (total / elapsed) * 100 / Double(cores)
        guard percent.isFinite else { return nil }
        return max(0, percent)
    }

    private func mapStatus(_ raw: Int32) -> ProcessStateKind {
        switch raw {
        case SIDL, SSTOP: return .stopped
        case SZOMB: return .zombie
        case SRUN: return .running
        case SSLEEP: return .sleeping
        default: return .unknown
        }
    }
}

enum CollectorError: LocalizedError {
    case process(String)
    case socket(String)
    var errorDescription: String? {
        switch self {
        case .process(let message), .socket(let message): return message
        }
    }
}
