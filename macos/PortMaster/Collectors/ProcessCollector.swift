import Darwin
import Foundation

final class ProcessCollector {
    private struct CPUSample {
        var user: UInt64
        var system: UInt64
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
        let pids: [pid_t]
        switch listPIDs() {
        case .success(let value): pids = value
        case .failure(let error): return .failure(error)
        }
        var entries: [ProcessEntry] = []
        var currentKeys: [UInt32: ProcessKey] = [:]

        for pid in pids where pid > 0 {
            guard let start = ProcessIdentity.processStart(pid: pid) else { continue }
            let key = ProcessKey(pid: UInt32(pid), startSec: start.seconds, startUsec: start.microseconds)
            let name = processName(pid: pid) ?? "pid-\(pid)"
            let task = readTaskInfo(pid: pid)
            let cpu = cpuPercent(pid: UInt32(pid), key: key, sample: task, sampleReady: sampleReady)
            let context = ProcessContextReader.read(key: key)
            let bsd = readBSDInfo(pid: pid)
            entries.append(
                ProcessEntry(
                    key: key,
                    name: name,
                    cpuPercent: cpu,
                    rssBytes: task?.residentSize,
                    status: mapStatus(bsd?.status),
                    parentPid: bsd?.ppid,
                    cwd: context.cwd,
                    executable: context.executable,
                    contextDisplay: context.contextDisplay,
                    contextKind: context.contextKind,
                ),
            )
            currentKeys[UInt32(pid)] = key
        }

        previousKeys = currentKeys
        lastSampleAt = Date()
        return .success(ProcessSnapshot(generation: generation, capturedAt: Date(), entries: entries))
    }

    private func listPIDs() -> Result<[pid_t], CollectorError> {
        var bufferSize = proc_listpids(UInt32(PROC_ALL_PIDS), UInt32(0), nil, Int32(0))
        if bufferSize <= 0 { return .failure(.process("Unable to list processes")) }
        let count = Int(bufferSize) / MemoryLayout<pid_t>.size
        var pids = [pid_t](repeating: 0, count: count)
        bufferSize = proc_listpids(UInt32(PROC_ALL_PIDS), UInt32(0), &pids, Int32(count * MemoryLayout<pid_t>.size))
        if bufferSize <= 0 { return .failure(.process("Unable to list processes")) }
        return .success(pids.filter { $0 > 0 })
    }

    private func processName(pid: pid_t) -> String? {
        var buffer = [CChar](repeating: 0, count: 1024)
        let result = proc_name(pid, &buffer, UInt32(buffer.count))
        guard result > 0 else { return nil }
        return String(validatingUTF8: buffer)
    }

    private struct BSDInfo {
        var status: Int32
        var ppid: UInt32?
    }

    private func readBSDInfo(pid: pid_t) -> BSDInfo? {
        var info = proc_bsdinfo()
        let size = Int32(MemoryLayout<proc_bsdinfo>.size)
        guard proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &info, size) == size else { return nil }
        return BSDInfo(status: Int32(info.pbi_status), ppid: UInt32(info.pbi_ppid))
    }

    private struct TaskInfo {
        var residentSize: UInt64
        var user: UInt64
        var system: UInt64
    }

    private func readTaskInfo(pid: pid_t) -> TaskInfo? {
        var info = proc_taskinfo()
        let size = Int32(MemoryLayout<proc_taskinfo>.size)
        guard proc_pidinfo(pid, PROC_PIDTASKINFO, 0, &info, size) == size else { return nil }
        return TaskInfo(
            residentSize: info.pti_resident_size,
            user: info.pti_total_user,
            system: info.pti_total_system,
        )
    }

    private func cpuPercent(pid: UInt32, key: ProcessKey, sample: TaskInfo?, sampleReady: Bool) -> Double? {
        guard sampleReady, let sample else { return nil }
        guard previousKeys[pid] == key else {
            previousCPU[pid] = CPUSample(user: sample.user, system: sample.system)
            return nil
        }
        guard let previous = previousCPU[pid] else {
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

    private func mapStatus(_ raw: Int32?) -> ProcessStateKind {
        guard let raw else { return .unknown }
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
