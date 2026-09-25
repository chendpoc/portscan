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

    // MARK: 页面与导航
    var page: PrimaryView = .performance
    var resource: ResourceKind = .cpu
    var range: TimeInterval = 60 {
        didSet { netScaleMax = nil } // 切换时间范围后重算吞吐图量程
    }
    var cpuShowPerCore = false

    // MARK: 网络吞吐
    /// 各接口吞吐历史（B/s），最多保留约 16 分钟。
    var netHistory: [String: [NetSample]] = [:]
    var interfaceNames: [String] = []
    var interfaceDisplayNames = NetworkThroughputCollector.displayNames()
    var selectedInterface = "en0"
    /// 吞吐图纵轴量程（带迟滞）。
    var netScaleMax: Double?

    // MARK: 查询与筛选
    var query = ""
    var processSort: ProcessSort = .cpu
    var sortDescending = true
    var processFilter: ProcessFilter = .all
    var portsFilter: PortsFilter = .listeners
    var protocolFilter: ProtocolKind?
    var connectionState: SocketStateKind?
    var portScope: ProcessKey?

    // MARK: 选中与详情
    var selectedKey: ProcessKey?
    var selectedSnapshot: ProcessEntry?
    var selectedExited = false
    var detail: ProcessDetail?
    var detailError: String?
    var detailLoading = false

    // MARK: 采样历史
    /// 系统资源历史，最多保留约 16 分钟（960 秒）。
    var history: [SystemMetricsSample] = []
    /// 进程观察采样：仅从用户选中该进程起记录，不伪造更早历史。
    var observed: [String: ObservedProcess] = [:]

    var settingsOpen = false
    var refreshing = false
    var now = Date()
    var toast: ToastItem?

    private let service = MonitorService()
    private let systemCollector = SystemMetricsCollector()
    private let networkCollector = NetworkThroughputCollector()
    private var loopTask: Task<Void, Never>?
    private var detailTask: Task<Void, Never>?
    private var toastTask: Task<Void, Never>?
    private let maxHistory = 960
    private let tickSeconds: TimeInterval = 1

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
        toastTask?.cancel()
    }

    private func tick() {
        guard !settings.paused else {
            // 暂停时冻结时钟与采样：图表保留真实时间缺口
            status = .paused
            return
        }
        now = Date()
        appendSystemSample(systemCollector.sample())
        appendNetworkSamples(networkCollector.sample())
        updateNetScale()
        let interval = TimeInterval(settings.intervalMs) / 1000
        let lastCapture = monitor.processes?.capturedAt ?? monitor.sockets?.capturedAt
        if lastCapture == nil || now.timeIntervalSince(lastCapture!) >= interval {
            refreshNow()
        } else {
            recomputeStatus()
        }
    }

    private func appendSystemSample(_ sample: SystemMetricsSample) {
        history.append(sample)
        if history.count > maxHistory {
            history.removeFirst(history.count - maxHistory)
        }
    }

    private func appendNetworkSamples(_ throughput: [String: NetworkThroughputCollector.Throughput]) {
        var names = Set(interfaceNames)
        for (name, value) in throughput {
            names.insert(name)
            var samples = netHistory[name] ?? []
            samples.append(NetSample(t: now, rx: value.rxBytesPerSec, tx: value.txBytesPerSec))
            if samples.count > maxHistory {
                samples.removeFirst(samples.count - maxHistory)
            }
            netHistory[name] = samples
        }
        interfaceNames = names.sorted { lhs, rhs in
            let lhsEn = lhs.hasPrefix("en")
            let rhsEn = rhs.hasPrefix("en")
            if lhsEn != rhsEn { return lhsEn }
            return lhs.localizedStandardCompare(rhs) == .orderedAscending
        }
        if !names.contains(selectedInterface), let first = interfaceNames.first {
            selectedInterface = first
        }
    }

    private func updateNetScale() {
        let peak = netSamplesInWindow().map { max($0.rx, $0.tx) }.max() ?? 1
        netScaleMax = MonitorLogic.stableScale(current: netScaleMax, maxValue: max(1, peak))
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
            // 进程已退出：保留最后记录，标记「已退出」，不再刷新详情
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
        let process = selectedSnapshot ?? visibleProcesses.first { $0.key == key }
        let endpoints = endpoints(for: key)
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

    /// Inspector 端口 chip：跳转到 Ports 页并带入端口搜索。
    func investigate(port: UInt16) {
        page = .ports
        query = String(port)
        portsFilter = .listeners
        protocolFilter = nil
        connectionState = nil
        portScope = nil
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

    // MARK: - 派生数据

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

    /// 当前时间窗口（暂停时 now 已冻结，窗口随之冻结）。
    var chartWindow: ClosedRange<Date> {
        now.addingTimeInterval(-range)...now
    }

    var tickInterval: TimeInterval { tickSeconds }

    /// 资源卡片/性能页状态徽标。
    func resourceStatus(_ kind: ResourceKind) -> (StatusKind, String) {
        switch kind {
        case .disk:
            return (.mut, "后续阶段")
        case .network:
            if (netHistory[selectedInterface] ?? []).isEmpty { return (.warn, "等待首个样本") }
            if settings.paused { return (.mut, "已暂停") }
            if let last = netHistory[selectedInterface]?.last, now.timeIntervalSince(last.t) > 12 {
                return (.warn, "数据过期")
            }
            return (.ok, "实时")
        case .cpu, .memory:
            if history.isEmpty { return (.warn, "等待首个样本") }
            if settings.paused { return (.mut, "已暂停") }
            if let last = history.last, now.timeIntervalSince(last.capturedAt) > 12 {
                return (.warn, "数据过期")
            }
            return (.ok, "实时")
        }
    }

    /// 当前选中接口在窗口内的吞吐样本。
    func netSamplesInWindow() -> [NetSample] {
        let lower = chartWindow.lowerBound.addingTimeInterval(-tickSeconds)
        return (netHistory[selectedInterface] ?? []).filter { $0.t >= lower }
    }

    func interfaceDisplayName(_ name: String) -> String {
        interfaceDisplayNames[name] ?? name
    }

    /// 当前窗口内的系统样本。
    func samplesInWindow() -> [SystemMetricsSample] {
        let lower = chartWindow.lowerBound.addingTimeInterval(-tickSeconds)
        return history.filter { $0.capturedAt >= lower }
    }

    func windowStats(values: [Double]) -> (average: Double?, peak: Double?) {
        guard !values.isEmpty else { return (nil, nil) }
        return (values.reduce(0, +) / Double(values.count), values.max())
    }

    /// 排行：当前实时占用最高的进程（忽略搜索框）。
    func topProcesses(by kind: ResourceKind, limit: Int = 3) -> [ProcessEntry] {
        let entries = monitor.processes?.entries ?? []
        let sorted: [ProcessEntry]
        switch kind {
        case .cpu:
            sorted = entries.filter { $0.cpuPercent != nil }.sorted { ($0.cpuPercent ?? 0) > ($1.cpuPercent ?? 0) }
        default:
            sorted = entries.filter { $0.rssBytes != nil }.sorted { ($0.rssBytes ?? 0) > ($1.rssBytes ?? 0) }
        }
        return Array(sorted.prefix(limit))
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
