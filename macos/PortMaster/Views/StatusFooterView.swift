import SwiftUI

/// 状态栏：全局采样状态 + 计数 + 时钟 + 设置。
struct StatusFooterView: View {
    @Bindable var model: MonitorViewModel

    var body: some View {
        HStack(spacing: 8) {
            StatusDot(kind: dotKind)
            Text(statusText)
                .font(.system(size: 11))
                .foregroundStyle(Theme.text2)
            Spacer()
            Text(countText)
                .font(.system(size: 11))
                .foregroundStyle(Theme.text2)
                .monospacedDigit()
            Text(Format.time(model.now))
                .font(.system(size: 11))
                .foregroundStyle(Theme.text2)
                .monospacedDigit()
            Menu {
                Picker("采样间隔", selection: Binding(
                    get: { model.settings.intervalMs },
                    set: { value in
                        var settings = model.settings
                        settings.intervalMs = value
                        model.updateSettings(settings)
                    },
                )) {
                    Text("1 秒").tag(UInt64(1000))
                    Text("2 秒").tag(UInt64(2000))
                    Text("5 秒").tag(UInt64(5000))
                }
                Toggle("包含 UDP", isOn: Binding(
                    get: { model.settings.includeUdp },
                    set: { value in
                        var settings = model.settings
                        settings.includeUdp = value
                        model.updateSettings(settings)
                    },
                ))
                Toggle("包含 IPv6", isOn: Binding(
                    get: { model.settings.includeIpv6 },
                    set: { value in
                        var settings = model.settings
                        settings.includeIpv6 = value
                        model.updateSettings(settings)
                    },
                ))
                if model.page == .ports {
                    Picker("端口筛选", selection: $model.ports.filter) {
                        Text("仅监听").tag(PortsFilter.listeners)
                        Text("全部套接字").tag(PortsFilter.all)
                    }
                }
            } label: {
                Image(systemName: "slider.horizontal.3")
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.text2)
            }
            .menuStyle(.borderlessButton)
            .frame(width: 24)
        }
        .padding(.horizontal, 12)
        .frame(height: 26)
        .background(Theme.sidebar)
        .overlay(alignment: .top) { Theme.sep.frame(height: 1) }
    }

    private var dotKind: StatusKind {
        switch model.status {
        case .live: .ok
        case .paused, .loading: .warn
        case .error: .err
        case .stale: .warn
        }
    }

    private var statusText: String {
        let interval = model.settings.intervalMs / 1000
        switch model.status {
        case .loading: return "正在采集首个样本…"
        case .live: return "实时 · 每 \(interval) 秒采样"
        case .paused: return "已暂停 — 采样停止，已有图表与表格保留；恢复后不回填缺口"
        case .error: return "采集失败 — 保留上一份成功数据"
        case .stale: return "数据过期 — 最新采样超过新鲜度阈值"
        }
    }

    private var countText: String {
        switch model.page {
        case .processes: "\(model.processes.visible(in: model.monitor, query: model.query).count) 个进程"
        case .ports: "\(model.ports.visible(in: model.monitor, query: model.query).count) 个端口"
        case .performance: "\(model.monitor.processes?.entries.count ?? 0) 个进程"
        }
    }
}
