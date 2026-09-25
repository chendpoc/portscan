import Foundation

enum TerminalService {
    static func openTerminal(for key: ProcessKey) throws {
        let cwd = try ProcessContextReader.verifiedCwdForTerminal(key: key)
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        process.arguments = ["-a", "Terminal", cwd]
        try process.run()
    }
}
