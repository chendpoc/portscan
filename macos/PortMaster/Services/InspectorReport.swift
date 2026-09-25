import Foundation

enum InspectorReport {
    static func build(
        process: ProcessEntry?,
        detail: ProcessDetail?,
        key: ProcessKey,
        endpoints: [SocketEntry],
    ) -> String {
        var lines: [String] = []
        lines.append("PortMaster Inspector Report")
        lines.append("Process: \(process?.name ?? "unknown")")
        lines.append("PID: \(key.pid)")
        lines.append("Identity: \(ProcessKeyFormatting.id(for: key))")
        if let detail {
            lines.append("Command: \(detail.command?.joined(separator: " ") ?? "unavailable")")
            lines.append("CWD: \(detail.cwd.path ?? detail.cwd.message ?? "unavailable")")
            lines.append("Executable: \(detail.exe ?? detail.executable.path ?? "unavailable")")
        }
        lines.append("Endpoints:")
        if endpoints.isEmpty {
            lines.append("  (none)")
        } else {
            for endpoint in endpoints {
                lines.append("  \(endpoint.protocolKind.rawValue.uppercased()) \(endpoint.localAddress):\(endpoint.localPort) \(endpoint.state.rawValue)")
            }
        }
        return lines.joined(separator: "\n")
    }
}
