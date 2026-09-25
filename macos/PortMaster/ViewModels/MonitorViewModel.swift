import AppKit
import Foundation
import Observation

@MainActor
@Observable
final class MonitorViewModel {
    var monitor = MonitorState()
    var settings = RefreshSettings()
    var status: RenderStatus = .loading
    var view: PrimaryView = .processes
    var query = ""
    var processSort: ProcessSort = .cpu
    var sortDescending = true
    var processFilter: ProcessFilter = .all
    var portsFilter: PortsFilter = .listeners
    var protocolFilter: ProtocolKind?
    var connectionState: SocketStateKind?
    var portScope: ProcessKey?
    var selectedKey: ProcessKey?
    var detail: ProcessDetail?
    var detailError: String?
    var detailLoading = false
    var settingsOpen = false
    var refreshing = false
    var now = Date()

    private let service = MonitorService()
    private var loopTask: Task<Void, Never>?
    private var detailTask: Task<Void, Never>?

    func start() {
        settings = service.currentSettings()
        refreshNow()
        loopTask?.cancel()
        loopTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                await MainActor.run { self?.tick() }
            }
        }
    }

    func stop() {
        loopTask?.cancel()
        loopTask = nil
        detailTask?.cancel()
    }

    private func tick() {
        now = Date()
        guard !settings.paused else {
            status = .paused
            return
        }
        let interval = TimeInterval(settings.intervalMs) / 1000
        if let last = monitor.processes?.capturedAt ?? monitor.sockets?.capturedAt {
            if Date().timeIntervalSince(last) >= interval {
                refreshNow()
            }
        }
    }

    func refreshNow() {
        refreshing = true
        Task.detached { [service] in
            let snapshot = service.refresh()
            await MainActor.run {
                self.monitor = snapshot
                self.settings = service.currentSettings()
                self.refreshing = false
                self.recomputeStatus()
                if let selected = self.selectedKey {
                    self.loadDetail(for: selected)
                }
            }
        }
    }

    func updateSettings(_ settings: RefreshSettings) {
        self.settings = settings
        service.updateSettings(settings)
        if settings.paused { status = .paused } else { recomputeStatus() }
    }

    func selectProcess(_ entry: ProcessEntry) {
        selectedKey = entry.key
        loadDetail(for: entry.key)
    }

    func selectPort(_ entry: SocketEntry) {
        guard let key = entry.processKey else { return }
        selectedKey = key
        loadDetail(for: key)
    }

    func closeInspector() {
        selectedKey = nil
        detail = nil
        detailError = nil
        detailTask?.cancel()
    }

    func loadDetail(for key: ProcessKey) {
        detailTask?.cancel()
        detailLoading = true
        detailError = nil
        detailTask = Task.detached {
            do {
                let loaded = try ProcessDetailService.load(key: key)
                await MainActor.run {
                    guard self.selectedKey == key else { return }
                    self.detail = loaded
                    self.detailLoading = false
                }
            } catch {
                await MainActor.run {
                    guard self.selectedKey == key else { return }
                    self.detailError = error.localizedDescription
                    self.detailLoading = false
                }
            }
        }
    }

    func openTerminal() {
        guard let key = selectedKey else { return }
        do {
            try TerminalService.openTerminal(for: key)
        } catch {
            detailError = error.localizedDescription
        }
    }

    func copyReport() {
        guard let key = selectedKey else { return }
        let process = visibleProcesses.first { $0.key == key }
        let endpoints = endpoints(for: key)
        let text = InspectorReport.build(process: process, detail: detail, key: key, endpoints: endpoints)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    var visibleProcesses: [ProcessEntry] {
        let listenSets = MonitorLogic.listenPortsByProcess(monitor.sockets?.sockets ?? [])
        return MonitorLogic.filterProcesses(
            monitor.processes?.entries ?? [],
            query: query,
            listenPortSets: listenSets,
            processFilter: processFilter,
            sort: processSort,
            descending: sortDescending,
        )
    }

    var visiblePorts: [SocketEntry] {
        let contextPaths = contextPathMap()
        return MonitorLogic.filterPorts(
            monitor.sockets?.sockets ?? [],
            query: query,
            contextPaths: contextPaths,
            portsFilter: portsFilter,
            protocolFilter: protocolFilter,
            connectionState: connectionState,
            portScope: portScope,
        )
    }

    func endpoints(for key: ProcessKey) -> [SocketEntry] {
        let id = ProcessKeyFormatting.id(for: key)
        return (monitor.sockets?.sockets ?? []).filter { entry in
            guard let processKey = entry.processKey else { return false }
            return ProcessKeyFormatting.id(for: processKey) == id
        }
    }

    func listenPorts(for key: ProcessKey) -> [Int] {
        let id = ProcessKeyFormatting.id(for: key)
        let set = MonitorLogic.listenPortsByProcess(monitor.sockets?.sockets ?? [])[id] ?? []
        return set.sorted()
    }

    private func contextPathMap() -> [String: String] {
        var map: [String: String] = [:]
        for entry in monitor.processes?.entries ?? [] {
            map[entry.id] = entry.contextDisplay ?? entry.cwd.path ?? entry.executable.path ?? ""
        }
        return map
    }

    private func recomputeStatus() {
        if monitor.processError != nil || monitor.socketError != nil {
            status = .error
            return
        }
        let processStale = MonitorLogic.isSnapshotStale(
            capturedAt: monitor.processes?.capturedAt,
            intervalMs: settings.intervalMs,
            sourceFailed: monitor.processError != nil,
            now: now,
        )
        let socketStale = MonitorLogic.isSnapshotStale(
            capturedAt: monitor.sockets?.capturedAt,
            intervalMs: settings.intervalMs,
            sourceFailed: monitor.socketError != nil,
            now: now,
        )
        if processStale || socketStale {
            status = .stale
        } else if settings.paused {
            status = .paused
        } else {
            status = .live
        }
    }
}
