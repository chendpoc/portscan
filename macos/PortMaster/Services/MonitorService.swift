import Foundation

final class MonitorService {
    private let processCollector = ProcessCollector()
    private var generation: UInt64 = 1
    private var monitor = MonitorState()
    private var settings = RefreshSettings()

    /// 首轮采集的阶段进度回调（仅 generation 1 触发）：
    /// 进程清单完成 0.6 → 端口扫描完成 1.0。供启动进度条展示真实进度，不伪造。
    var onBootPhase: (@Sendable (Double) -> Void)?

    func snapshot() -> MonitorState { monitor }
    func currentSettings() -> RefreshSettings { settings }

    func updateSettings(_ settings: RefreshSettings) {
        self.settings = RefreshSettings(
            intervalMs: min(max(settings.intervalMs, 500), 30_000),
            paused: settings.paused,
            includeUdp: settings.includeUdp,
            includeIpv6: settings.includeIpv6,
        )
    }

    func refresh() -> MonitorState {
        let currentGeneration = generation
        generation += 1

        switch processCollector.sample(generation: currentGeneration) {
        case .success(let snapshot):
            monitor.processes = snapshot
            monitor.processError = nil
            monitor.processErrorGeneration = nil
            if currentGeneration == 1 { onBootPhase?(0.6) }
        case .failure(let error):
            monitor.processError = error.localizedDescription
            monitor.processErrorGeneration = currentGeneration
        }

        let known = monitor.processes?.entries ?? []
        do {
            let sockets = try SocketCollector.collect(
                includeUDP: settings.includeUdp,
                includeIPv6: settings.includeIpv6,
                processes: known,
            )
            // 渲染前去重：SO_REUSEPORT 下同进程同地址同端口的重复绑定合并为一行
            let deduped = MonitorLogic.dedupeSockets(sockets)
            monitor.sockets = SocketSnapshot(
                generation: currentGeneration,
                capturedAt: Date(),
                sockets: deduped.sorted { $0.localPort < $1.localPort },
                interfaces: [],
            )
            monitor.socketError = nil
            monitor.socketErrorGeneration = nil
            if currentGeneration == 1 { onBootPhase?(1.0) }
        } catch {
            monitor.socketError = error.localizedDescription
            monitor.socketErrorGeneration = currentGeneration
        }
        return monitor
    }
}
