import Foundation
import Observation

/// Ports 页：套接字筛选、进程作用域与可见列表派生。
@MainActor
@Observable
final class PortsModel {
    var filter: PortsFilter = .listeners
    var protocolFilter: ProtocolKind?
    var connectionState: SocketStateKind?
    var portScope: ProcessKey?

    func resetFiltersForPortSearch() {
        filter = .listeners
        protocolFilter = nil
        connectionState = nil
        portScope = nil
    }

    func applyScope(to key: ProcessKey) {
        portScope = key
        filter = .listeners
        protocolFilter = nil
        connectionState = nil
    }

    func clearScope() {
        portScope = nil
    }

    func visible(in monitor: MonitorState, query: String) -> [SocketEntry] {
        MonitorLogic.filterPorts(
            monitor.sockets?.sockets ?? [],
            query: query,
            contextPaths: contextPathMap(from: monitor),
            portsFilter: filter,
            protocolFilter: protocolFilter,
            connectionState: connectionState,
            portScope: portScope,
        )
    }

    func scopedProcessName(in monitor: MonitorState) -> String? {
        guard let portScope else { return nil }
        return (monitor.processes?.entries ?? []).first { $0.key == portScope }?.name
            ?? "PID \(portScope.pid)"
    }

    func endpoints(for key: ProcessKey, in monitor: MonitorState) -> [SocketEntry] {
        let id = ProcessKeyFormatting.id(for: key)
        return (monitor.sockets?.sockets ?? []).filter { entry in
            guard let processKey = entry.processKey else { return false }
            return ProcessKeyFormatting.id(for: processKey) == id
        }
    }

    func listenPorts(for key: ProcessKey, in monitor: MonitorState) -> [Int] {
        let id = ProcessKeyFormatting.id(for: key)
        let set = MonitorLogic.listenPortsByProcess(monitor.sockets?.sockets ?? [])[id] ?? []
        return set.sorted()
    }

    private func contextPathMap(from monitor: MonitorState) -> [String: String] {
        var map: [String: String] = [:]
        for entry in monitor.processes?.entries ?? [] {
            map[entry.id] = entry.contextDisplay ?? entry.cwd.path ?? entry.executable.path ?? ""
        }
        return map
    }
}
