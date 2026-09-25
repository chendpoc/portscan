import Darwin
import Foundation

enum ProcessDetailService {
    static func load(key: ProcessKey) throws -> ProcessDetail {
        guard let expected = key.startUsec.map({ ProcessStart(seconds: key.startSec, microseconds: $0) }) else {
            throw TerminalError.message("Process identity is unavailable")
        }
        guard ProcessIdentity.processStart(pid: pid_t(key.pid)) == expected else {
            throw TerminalError.message("Process exited or changed")
        }

        let context = ProcessContextReader.read(key: key)
        let command = processArguments(pid: pid_t(key.pid))
        let exe = context.executable.path
        let appBundle = exe.flatMap { ProcessContextReader.appBundle(from: $0) }
        let ancestry = buildAncestry(startingAt: key)
        let startIso = ISO8601DateFormatter().string(from: Date(timeIntervalSince1970: TimeInterval(key.startSec)))

        return ProcessDetail(
            key: key,
            command: command,
            exe: exe,
            cwd: context.cwd,
            executable: context.executable,
            appBundle: appBundle,
            collectedAt: Date(),
            verifiedAt: Date(),
            ancestry: ancestry.nodes,
            ancestryIncomplete: ancestry.incomplete,
            startTimeIso: startIso,
        )
    }

    private static func processArguments(pid: pid_t) -> [String]? {
        var mib: [Int32] = [CTL_KERN, KERN_PROCARGS2, pid]
        var size: size_t = 0
        guard sysctl(&mib, 3, nil, &size, nil, 0) == 0, size > 0 else { return nil }
        var buffer = [UInt8](repeating: 0, count: size)
        guard sysctl(&mib, 3, &buffer, &size, nil, 0) == 0 else { return nil }
        guard size > MemoryLayout<Int32>.size else { return nil }
        let argc = buffer.withUnsafeBytes { $0.load(as: Int32.self) }
        guard argc > 0 else { return [] }
        var args: [String] = []
        var index = MemoryLayout<Int32>.size
        while index < buffer.count && args.count < argc {
            while index < buffer.count, buffer[index] == 0 { index += 1 }
            if index >= buffer.count { break }
            let start = index
            while index < buffer.count, buffer[index] != 0 { index += 1 }
            if start < index, let arg = String(bytes: buffer[start..<index], encoding: .utf8) {
                args.append(arg)
            }
        }
        return args
    }

    private static func buildAncestry(startingAt key: ProcessKey) -> (nodes: [AncestryNode], incomplete: Bool) {
        var nodes: [AncestryNode] = []
        var current = key
        var incomplete = false
        for _ in 0..<8 {
            guard let start = current.startUsec.map({ ProcessStart(seconds: current.startSec, microseconds: $0) }) else {
                incomplete = true
                break
            }
            guard ProcessIdentity.processStart(pid: pid_t(current.pid)) == start else {
                incomplete = true
                break
            }
            let name = processName(pid: pid_t(current.pid)) ?? "pid-\(current.pid)"
            nodes.append(AncestryNode(key: current, name: name, relationshipVerified: true))
            guard let parent = parentPID(pid: pid_t(current.pid)), parent > 0 else { break }
            guard let parentStart = ProcessIdentity.processStart(pid: parent) else {
                incomplete = true
                break
            }
            current = ProcessKey(pid: UInt32(parent), startSec: parentStart.seconds, startUsec: parentStart.microseconds)
        }
        return (nodes, incomplete)
    }

    private static func parentPID(pid: pid_t) -> pid_t? {
        var info = proc_bsdinfo()
        let size = Int32(MemoryLayout<proc_bsdinfo>.size)
        guard proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &info, size) == size else { return nil }
        return pid_t(info.pbi_ppid)
    }

    private static func processName(pid: pid_t) -> String? {
        var buffer = [CChar](repeating: 0, count: 1024)
        guard proc_name(pid, &buffer, UInt32(buffer.count)) > 0 else { return nil }
        return String(validatingUTF8: buffer)
    }
}
