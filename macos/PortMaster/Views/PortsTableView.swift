import SwiftUI

struct PortsTableView: View {
    @Bindable var model: MonitorViewModel

    var body: some View {
        Table(model.visiblePorts) {
            TableColumn("Process") { entry in
                Button {
                    model.selectPort(entry)
                } label: {
                    Text(entry.processName ?? "—")
                }
                .buttonStyle(.plain)
            }
            TableColumn("PID") { entry in
                Text(entry.pid.map(String.init) ?? "—")
                    .font(.system(.body, design: .monospaced))
            }
            TableColumn("Local") { entry in
                Text("\(entry.localAddress):\(entry.localPort)")
                    .font(.system(.caption, design: .monospaced))
            }
            TableColumn("Proto") { entry in
                Text(entry.protocolKind.rawValue.uppercased())
            }
            TableColumn("State") { entry in
                Text(portStateLabel(entry))
            }
        }
        .onTapGesture(count: 1) { }
    }

    private func portStateLabel(_ entry: SocketEntry) -> String {
        if entry.protocolKind == .udp, entry.state == .none { return "UDP BOUND" }
        return "\(entry.protocolKind.rawValue.uppercased()) \(entry.state.rawValue)"
    }
}
