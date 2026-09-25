import SwiftUI

struct ProcessTableView: View {
    @Bindable var model: MonitorViewModel

    var body: some View {
        Table(model.visibleProcesses) {
            TableColumn("Process") { entry in
                Button {
                    model.selectProcess(entry)
                } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(entry.name).fontWeight(.semibold)
                        Text(entry.contextDisplay ?? "—").font(.caption).foregroundStyle(.secondary)
                    }
                }
                .buttonStyle(.plain)
            }
            TableColumn("PID") { entry in
                Text("\(entry.key.pid)")
                    .font(.system(.body, design: .monospaced))
            }
            TableColumn("CPU") { entry in
                Text(entry.cpuPercent.map { String(format: "%.1f%%", $0) } ?? "—")
            }
            TableColumn("Memory") { entry in
                Text(entry.rssBytes.map(formatBytes) ?? "—")
            }
            TableColumn("Ports") { entry in
                Text(model.listenPorts(for: entry.key).map(String.init).joined(separator: ", "))
                    .font(.caption)
            }
        }
    }

    private func formatBytes(_ value: UInt64) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(value), countStyle: .memory)
    }
}
