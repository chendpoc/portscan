import Foundation

final class MonitorService {
    private let processCollector = ProcessCollector()
    private var generation: UInt64 = 1
    private var monitor = MonitorState()
    private var settings = RefreshSettings()

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
            monitor.sockets = SocketSnapshot(
                generation: currentGeneration,
                capturedAt: Date(),
                sockets: sockets.sorted { $0.localPort < $1.localPort },
                interfaces: [],
            )
            monitor.socketError = nil
            monitor.socketErrorGeneration = nil
        } catch {
            monitor.socketError = error.localizedDescription
            monitor.socketErrorGeneration = currentGeneration
        }
        return monitor
    }
}
