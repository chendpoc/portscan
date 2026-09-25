import AppKit
import Foundation
import Observation

struct ToastItem: Equatable {
    let id = UUID()
    var text: String
}

@MainActor
@Observable
final class MonitorViewModel {
    var monitor = MonitorState()
    var settings = RefreshSettings()
    var status: RenderStatus = .loading

    var page: PrimaryView = .performance
    var performance = PerformanceModel()
    var processes = ProcessesModel()
    var ports = PortsModel()

    /// 工具栏 / 表格共享搜索词。
    var query = ""

    // MARK: 选中与详情
    var selectedKey: ProcessKey?
    var selectedSnapshot: ProcessEntry?
    var selectedExited = false
    var detail: ProcessDetail?
    var detailError: String?
    var detailLoading = false

    var observed: [String: ObservedProcess] = [:]

    var settingsOpen = false
    var refreshing = false
    var toast: ToastItem?

    /// 首轮采集真实进度（0.1 起步 → 进程清单 0.6 → 端口 1.0），供品牌页进度条。
    var bootProgress: Double = 0.1

    private let service = MonitorService()
    private var loopTask: Task<Void, Never>?
    private var detailTask: Task<Void, Never>?
    private var toastTask: Task<Void, Never>?
    private let maxHistory = 960

    var now: Date { performance.now }

    func start() {
        settings = service.currentSettings()
        service.onBootPhase = { [weak self] value in
            Task { @MainActor in
                guard let self else { return }
                self.bootProgress = max(self.bootProgress, value)
            }
        }
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
        toastTask?.cancel()
    }

    private func tick() {
        guard !settings.paused else {
            status = .paused
            return
        }
        performance.sample(at: Date())
        let interval = TimeInterval(settings.intervalMs) / 1000
        let lastCapture = monitor.processes?.capturedAt ?? monitor.sockets?.capturedAt
        if lastCapture == nil || now.timeIntervalSince(lastCapture!) >= interval {
            refreshNow()
        } else {
            recomputeStatus()
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
                self.updateSelection()
                self.recordObservedSample()
                self.performance.refreshDiskCapacity()
            }
        }
    }

    func updateSettings(_ settings: RefreshSettings) {
        self.settings = settings
        service.updateSettings(settings)
        if settings.paused { status = .paused } else { recomputeStatus() }
    }

    // MARK: - 选中与观察

    func selectProcess(_ entry: ProcessEntry) {
        selectedKey = entry.key
        selectedSnapshot = entry
        selectedExited = false
        beginObserving(entry.key)
        loadDetail(for: entry.key)
    }

    func selectPort(_ entry: SocketEntry) {
        guard let key = entry.processKey else { return }
        if let process = (monitor.processes?.entries ?? []).first(where: { $0.key == key }) {
            selectProcess(process)
        } else {
            selectedKey = key
            beginObserving(key)
            loadDetail(for: key)
        }
    }

    func closeInspector() {
        selectedKey = nil
        selectedSnapshot = nil
        selectedExited = false
        detail = nil
        detailError = nil
        detailTask?.cancel()
    }

    private func beginObserving(_ key: ProcessKey) {
        let id = ProcessKeyFormatting.id(for: key)
        if observed[id] == nil {
            observed[id] = ObservedProcess(t0: Date(), samples: [])
        }
    }

    private func updateSelection() {
        guard let key = selectedKey else { return }
        let entries = monitor.processes?.entries ?? []
        if let live = entries.first(where: { $0.key == key }) {
            selectedSnapshot = live
            selectedExited = false
            loadDetail(for: key)
        } else if selectedSnapshot != nil {
            selectedExited = true
            detailTask?.cancel()
            detailLoading = false
        }
    }

    private func recordObservedSample() {
        guard let key = selectedKey, !selectedExited else { return }
        let id = ProcessKeyFormatting.id(for: key)
        guard var record = observed[id] else { return }
        let entries = monitor.processes?.entries ?? []
        guard let live = entries.first(where: { $0.key == key }) else { return }
        record.samples.append(ObservedSample(t: Date(), cpu: live.cpuPercent, rss: live.rssBytes))
        if record.samples.count > maxHistory {
            record.samples.removeFirst(record.samples.count - maxHistory)
        }
        observed[id] = record
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

    // MARK: - 操作

    func openTerminal() {
        guard let key = selectedKey else { return }
        do {
            try TerminalService.openTerminal(for: key)
            showToast("已在终端打开工作目录")
        } catch {
            detailError = error.localizedDescription
            showToast("无法打开终端：\(error.localizedDescription)")
        }
    }

    func revealInFinder() {
        guard !selectedExited else { showToast("进程已退出，无法定位"); return }
        guard let detail else { return }
        guard let path = detail.exe ?? detail.executable.path ?? detail.cwd.path else {
            showToast("路径不可用，无法在 Finder 中显示")
            return
        }
        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)])
    }

    func copyReport() {
        guard let key = selectedKey else { return }
        let process = selectedSnapshot ?? processes.visible(in: monitor, query: query).first { $0.key == key }
        let endpoints = ports.endpoints(for: key, in: monitor)
        let text = InspectorReport.build(process: process, detail: detail, key: key, endpoints: endpoints)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        showToast("已复制「进程信息」")
    }

    func copyText(_ text: String, label: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        showToast("已复制「\(label)」")
    }

    func investigate(port: UInt16) {
        page = .ports
        query = String(port)
        ports.resetFiltersForPortSearch()
    }

    func scopePorts(to key: ProcessKey) {
        ports.applyScope(to: key)
        query = ""
        page = .ports
    }

    func endpoints(for key: ProcessKey) -> [SocketEntry] {
        ports.endpoints(for: key, in: monitor)
    }

    func listenPorts(for key: ProcessKey) -> [Int] {
        ports.listenPorts(for: key, in: monitor)
    }

    func topProcesses(by kind: ResourceKind, limit: Int = 3) -> [ProcessEntry] {
        performance.topProcesses(from: monitor.processes?.entries ?? [], by: kind, limit: limit)
    }

    func showToast(_ text: String) {
        let item = ToastItem(text: text)
        toast = item
        toastTask?.cancel()
        toastTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 3_200_000_000)
            await MainActor.run {
                guard let self, self.toast == item else { return }
                self.toast = nil
            }
        }
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
