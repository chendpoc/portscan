import Foundation
import Observation

/// Processes 页：排序、筛选与可见列表派生。
@MainActor
@Observable
final class ProcessesModel {
    var sort: ProcessSort = .cpu
    var sortDescending = true
    var filter: ProcessFilter = .all

    func visible(in monitor: MonitorState, query: String) -> [ProcessEntry] {
        let listenSets = MonitorLogic.listenPortsByProcess(monitor.sockets?.sockets ?? [])
        return MonitorLogic.filterProcesses(
            monitor.processes?.entries ?? [],
            query: query,
            listenPortSets: listenSets,
            processFilter: filter,
            sort: sort,
            descending: sortDescending,
        )
    }

    func filterCounts(in monitor: MonitorState) -> (all: Int, running: Int, withListeners: Int) {
        let entries = monitor.processes?.entries ?? []
        let listenSets = MonitorLogic.listenPortsByProcess(monitor.sockets?.sockets ?? [])
        let running = entries.filter { $0.status == .running }.count
        let withListeners = entries.filter { !(listenSets[$0.id] ?? []).isEmpty }.count
        return (entries.count, running, withListeners)
    }
}
