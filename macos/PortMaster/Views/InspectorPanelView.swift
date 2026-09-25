import SwiftUI

struct InspectorPanelView: View {
    @Bindable var model: MonitorViewModel
    var compact: Bool
    var onBack: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                if compact {
                    Button("Back", action: onBack)
                }
                Text(processTitle)
                    .font(.headline)
                Spacer()
                Button("×", action: onBack)
            }
            if model.detailLoading {
                ProgressView()
            } else if let error = model.detailError {
                Text(error).foregroundStyle(.red)
            } else if let detail = model.detail {
                Group {
                    labeled("CWD", detail.cwd.path ?? detail.cwd.message ?? "Unavailable")
                    labeled("Command", detail.command?.joined(separator: " ") ?? "Unavailable")
                    labeled("CPU", model.visibleProcesses.first { $0.key == detail.key }?.cpuPercent.map { String(format: "%.1f%%", $0) } ?? "—")
                    labeled("RSS", model.visibleProcesses.first { $0.key == detail.key }?.rssBytes.map { ByteCountFormatter.string(fromByteCount: Int64($0), countStyle: .memory) } ?? "—")
                }
                Divider()
                Text("Endpoints").font(.caption.weight(.semibold))
                ForEach(model.endpoints(for: detail.key), id: \.id) { endpoint in
                    Text("\(endpoint.localAddress):\(endpoint.localPort) \(endpoint.protocolKind.rawValue)")
                        .font(.system(.caption, design: .monospaced))
                }
            }
            HStack {
                Button("Open Terminal", action: model.openTerminal)
                Button("Copy Report", action: model.copyReport)
            }
            Spacer()
        }
        .padding(12)
        .background(Color(nsColor: .controlBackgroundColor))
        .overlay(alignment: .leading) { Divider() }
    }

    private var processTitle: String {
        guard let key = model.selectedKey else { return "Inspector" }
        let name = model.visibleProcesses.first { $0.key == key }?.name ?? "Process"
        return "\(name) · PID \(key.pid)"
    }

    private func labeled(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            Text(value).font(.system(.caption, design: .monospaced))
                .textSelection(.enabled)
        }
    }
}
