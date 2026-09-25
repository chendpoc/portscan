import Foundation
import Observation

/// Performance 页与侧栏资源卡片：系统/网络/磁盘采样、历史与图表量程。
@MainActor
@Observable
final class PerformanceModel {
    var resource: ResourceKind = .cpu
    var range: TimeInterval = 60 {
        didSet {
            netScaleMax = nil
            diskScaleMax = nil
        }
    }
    var cpuShowPerCore = false

    var netHistory: [String: [NetSample]] = [:]
    var interfaceNames: [String] = []
    var interfaceDisplayNames = NetworkThroughputCollector.displayNames()
    var selectedInterface = "en0"
    var netScaleMax: Double?

    var diskHistory: [DiskSample] = []
    var diskScaleMax: Double?
    var diskCapacity: (used: UInt64, total: UInt64)?

    var history: [SystemMetricsSample] = []

    private(set) var now = Date()

    private let systemCollector = SystemMetricsCollector()
    private let networkCollector = NetworkThroughputCollector()
    private let diskCollector = DiskThroughputCollector()
    private let maxHistory = 960
    let tickInterval: TimeInterval = 1

    /// 每秒调用一次（暂停时不调用）。
    func sample(at date: Date) {
        now = date
        appendSystemSample(systemCollector.sample())
        appendNetworkSamples(networkCollector.sample())
        appendDiskSample(diskCollector.sample())
        updateNetScale()
        updateDiskScale()
    }

    func refreshDiskCapacity() {
        let root = URL(fileURLWithPath: "/")
        guard let values = try? root.resourceValues(forKeys: [
            .volumeTotalCapacityKey,
            .volumeAvailableCapacityForImportantUsageKey,
        ]),
            let total = values.volumeTotalCapacity,
            let available = values.volumeAvailableCapacityForImportantUsage else { return }
        diskCapacity = (UInt64(max(0, Int64(total) - available)), UInt64(total))
    }

    var chartWindow: ClosedRange<Date> {
        now.addingTimeInterval(-range)...now
    }

    func resourceStatus(_ kind: ResourceKind, paused: Bool) -> (StatusKind, String) {
        switch kind {
        case .network:
            if (netHistory[selectedInterface] ?? []).isEmpty { return (.warn, "等待首个样本") }
            if paused { return (.mut, "已暂停") }
            if let last = netHistory[selectedInterface]?.last, now.timeIntervalSince(last.t) > 12 {
                return (.warn, "数据过期")
            }
            return (.ok, "实时")
        case .disk:
            if diskHistory.isEmpty { return (.warn, "等待首个样本") }
            if paused { return (.mut, "已暂停") }
            if let last = diskHistory.last, now.timeIntervalSince(last.t) > 12 {
                return (.warn, "数据过期")
            }
            return (.ok, "实时")
        case .cpu, .memory:
            if history.isEmpty { return (.warn, "等待首个样本") }
            if paused { return (.mut, "已暂停") }
            if let last = history.last, now.timeIntervalSince(last.capturedAt) > 12 {
                return (.warn, "数据过期")
            }
            return (.ok, "实时")
        }
    }

    func netSamplesInWindow() -> [NetSample] {
        let lower = chartWindow.lowerBound.addingTimeInterval(-tickInterval)
        return (netHistory[selectedInterface] ?? []).filter { $0.t >= lower }
    }

    func diskSamplesInWindow() -> [DiskSample] {
        let lower = chartWindow.lowerBound.addingTimeInterval(-tickInterval)
        return diskHistory.filter { $0.t >= lower }
    }

    func samplesInWindow() -> [SystemMetricsSample] {
        let lower = chartWindow.lowerBound.addingTimeInterval(-tickInterval)
        return history.filter { $0.capturedAt >= lower }
    }

    func interfaceDisplayName(_ name: String) -> String {
        interfaceDisplayNames[name] ?? name
    }

    func windowStats(values: [Double]) -> (average: Double?, peak: Double?) {
        guard !values.isEmpty else { return (nil, nil) }
        return (values.reduce(0, +) / Double(values.count), values.max())
    }

    func topProcesses(from entries: [ProcessEntry], by kind: ResourceKind, limit: Int = 3) -> [ProcessEntry] {
        let sorted: [ProcessEntry]
        switch kind {
        case .cpu:
            sorted = entries.filter { $0.cpuPercent != nil }.sorted { ($0.cpuPercent ?? 0) > ($1.cpuPercent ?? 0) }
        default:
            sorted = entries.filter { $0.rssBytes != nil }.sorted { ($0.rssBytes ?? 0) > ($1.rssBytes ?? 0) }
        }
        return Array(sorted.prefix(limit))
    }

    // MARK: - Private

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

    private func appendDiskSample(_ throughput: DiskThroughputCollector.Throughput?) {
        guard let throughput else { return }
        diskHistory.append(DiskSample(t: now, read: throughput.readBytesPerSec, write: throughput.writeBytesPerSec))
        if diskHistory.count > maxHistory {
            diskHistory.removeFirst(diskHistory.count - maxHistory)
        }
    }

    private func updateDiskScale() {
        let peak = diskSamplesInWindow().map { max($0.read, $0.write) }.max() ?? 1
        diskScaleMax = MonitorLogic.stableScale(current: diskScaleMax, maxValue: max(1, peak))
    }
}
