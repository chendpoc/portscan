import Darwin
import Foundation

struct ProcessStart: Equatable {
    var seconds: UInt64
    var microseconds: UInt64
}

enum ProcessIdentity {
    static func processStart(pid: pid_t) -> ProcessStart? {
        guard pid > 0 else { return nil }
        var info = proc_bsdinfo()
        let size = Int32(MemoryLayout<proc_bsdinfo>.size)
        let written = proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &info, size)
        guard written == size, info.pbi_pid == UInt32(pid) else { return nil }
        return ProcessStart(seconds: info.pbi_start_tvsec, microseconds: info.pbi_start_tvusec)
    }

    static func makeKey(pid: pid_t, start: ProcessStart?) -> ProcessKey {
        ProcessKey(pid: UInt32(pid), startSec: start?.seconds ?? 0, startUsec: start?.microseconds)
    }
}
