import SwiftUI

struct StatusFooterView: View {
    @Bindable var model: MonitorViewModel

    var body: some View {
        HStack {
            Text(summary)
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
            Menu {
                Picker("Interval", selection: Binding(
                    get: { model.settings.intervalMs },
                    set: { model.updateSettings(RefreshSettings(intervalMs: $0, paused: model.settings.paused, includeUdp: model.settings.includeUdp, includeIpv6: model.settings.includeIpv6)) },
                )) {
                    Text("1 sec").tag(UInt64(1000))
                    Text("2 sec").tag(UInt64(2000))
                    Text("5 sec").tag(UInt64(5000))
                }
                Toggle("Include UDP", isOn: Binding(
                    get: { model.settings.includeUdp },
                    set: { model.updateSettings(RefreshSettings(intervalMs: model.settings.intervalMs, paused: model.settings.paused, includeUdp: $0, includeIpv6: model.settings.includeIpv6)) },
                ))
                Toggle("Include IPv6", isOn: Binding(
                    get: { model.settings.includeIpv6 },
                    set: { model.updateSettings(RefreshSettings(intervalMs: model.settings.intervalMs, paused: model.settings.paused, includeUdp: model.settings.includeUdp, includeIpv6: $0)) },
                ))
                Toggle("Pause", isOn: Binding(
                    get: { model.settings.paused },
                    set: { model.updateSettings(RefreshSettings(intervalMs: model.settings.intervalMs, paused: $0, includeUdp: model.settings.includeUdp, includeIpv6: model.settings.includeIpv6)) },
                ))
                if model.view == .ports {
                    Picker("Ports filter", selection: $model.portsFilter) {
                        Text("Listeners").tag(PortsFilter.listeners)
                        Text("All sockets").tag(PortsFilter.all)
                    }
                }
            } label: {
                Label("Settings", systemImage: "slider.horizontal.3")
            }
            .menuStyle(.borderlessButton)
        }
        .padding(.horizontal, 10)
        .frame(height: 28)
        .background(Color(nsColor: .windowBackgroundColor))
        .overlay(alignment: .top) { Divider() }
    }

    private var summary: String {
        let status = model.status
        let interval = model.settings.intervalMs / 1000
        if model.view == .processes {
            return "\(model.visibleProcesses.count) processes · \(status) · \(interval)s"
        }
        return "\(model.visiblePorts.count) ports · \(status) · \(interval)s"
    }
}
