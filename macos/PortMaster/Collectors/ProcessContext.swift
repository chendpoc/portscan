import Darwin
import Foundation

struct ProcessContextSnapshot: Equatable {
    var cwd: PathEvidence
    var executable: PathEvidence
    var contextDisplay: String?
    var contextKind: String?
}

enum ProcessContextReader {
    static func read(key: ProcessKey) -> ProcessContextSnapshot {
        guard let expected = key.startUsec.map({ ProcessStart(seconds: key.startSec, microseconds: $0) }) else {
            return emptyContext(state: .unavailable, message: "Process identity is unavailable")
        }
        guard ProcessIdentity.processStart(pid: pid_t(key.pid)) == expected else {
            return emptyContext(state: .unavailable, message: "Process exited or changed")
        }

        let cwd = readCwd(pid: pid_t(key.pid))
        let executable = readExecutable(pid: pid_t(key.pid))

        if ProcessIdentity.processStart(pid: pid_t(key.pid)) != expected {
            return ProcessContextSnapshot(
                cwd: .unavailable("Process exited during context read"),
                executable: .unavailable("Process exited during context read"),
                contextDisplay: nil,
                contextKind: nil,
            )
        }

        let (display, kind) = displayContext(cwd: cwd, executable: executable)
        return ProcessContextSnapshot(cwd: cwd, executable: executable, contextDisplay: display, contextKind: kind)
    }

    static func verifiedCwdForTerminal(key: ProcessKey) throws -> String {
        guard let expected = key.startUsec.map({ ProcessStart(seconds: key.startSec, microseconds: $0) }) else {
            throw TerminalError.message("Process identity is unavailable")
        }
        guard ProcessIdentity.processStart(pid: pid_t(key.pid)) == expected else {
            throw TerminalError.message("Process exited or changed")
        }
        let cwd = readCwd(pid: pid_t(key.pid))
        guard ProcessIdentity.processStart(pid: pid_t(key.pid)) == expected else {
            throw TerminalError.message("Process exited during working-directory verification")
        }
        switch cwd.state {
        case .available:
            guard let path = cwd.path else { throw TerminalError.message("Working directory path missing") }
            var isDir: ObjCBool = false
            guard FileManager.default.fileExists(atPath: path, isDirectory: &isDir), isDir.boolValue else {
                throw TerminalError.message("Working directory is not an existing directory")
            }
            return path
        case .restricted:
            throw TerminalError.message(cwd.message ?? "Working directory is restricted by macOS")
        case .unavailable:
            throw TerminalError.message(cwd.message ?? "Working directory is unavailable")
        }
    }

    private static func emptyContext(state: EvidenceState, message: String) -> ProcessContextSnapshot {
        let evidence = PathEvidence(state: state, path: nil, message: message)
        return ProcessContextSnapshot(cwd: evidence, executable: evidence, contextDisplay: nil, contextKind: nil)
    }

    private static func readCwd(pid: pid_t) -> PathEvidence {
        var info = proc_vnodepathinfo()
        let size = Int32(MemoryLayout<proc_vnodepathinfo>.size)
        let written = proc_pidinfo(pid, PROC_PIDVNODEPATHINFO, 0, &info, size)
        if written <= 0 { return cwdError() }
        if written != size { return .unavailable("Incomplete working-directory response from macOS") }
        guard let path = flattenVipPath(info) else {
            return .unavailable("Working directory path unavailable from macOS")
        }
        return .available(path)
    }

    private static func readExecutable(pid: pid_t) -> PathEvidence {
        var buffer = [CChar](repeating: 0, count: 1024)
        let written = proc_pidpath(pid, &buffer, UInt32(buffer.count))
        if written <= 0 { return exeError() }
        guard let path = String(validatingUTF8: buffer), !path.isEmpty else {
            return .unavailable("Executable path unavailable from macOS")
        }
        return .available(path)
    }

    private static func cwdError() -> PathEvidence {
        switch errno {
        case EPERM, EACCES: return .restricted("macOS denied working-directory access")
        case ESRCH: return .unavailable("Process exited")
        default: return .unavailable("Working directory unavailable from macOS")
        }
    }

    private static func exeError() -> PathEvidence {
        switch errno {
        case EPERM, EACCES: return .restricted("macOS denied executable path access")
        case ESRCH: return .unavailable("Process exited")
        default: return .unavailable("Executable path unavailable from macOS")
        }
    }

    private static func flattenVipPath(_ info: proc_vnodepathinfo) -> String? {
        withUnsafeBytes(of: info.pvi_cdir.vip_path) { raw in
            guard let base = raw.baseAddress?.assumingMemoryBound(to: CChar.self) else { return nil }
            return String(validatingUTF8: base)
        }
    }

    private static func displayContext(cwd: PathEvidence, executable: PathEvidence) -> (String?, String?) {
        if cwd.state == .available, let path = cwd.path {
            return (abbreviateHome(path), "cwd")
        }
        if executable.state == .available, let path = executable.path {
            if let bundle = appBundle(from: path) {
                return ("App: \(abbreviateHome(bundle))", "app")
            }
            return ("Executable: \(abbreviateHome(path))", "executable")
        }
        return (nil, nil)
    }

    static func abbreviateHome(_ path: String) -> String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        if path == home { return "~" }
        let prefix = home + "/"
        if path.hasPrefix(prefix) {
            return "~" + String(path.dropFirst(home.count))
        }
        return path
    }

    static func appBundle(from executable: String) -> String? {
        var url = URL(fileURLWithPath: executable)
        while url.path != "/" {
            if url.pathExtension == "app" { return url.path }
            url.deleteLastPathComponent()
        }
        return nil
    }
}

enum TerminalError: LocalizedError {
    case message(String)
    var errorDescription: String? {
        switch self {
        case .message(let text): return text
        }
    }
}
