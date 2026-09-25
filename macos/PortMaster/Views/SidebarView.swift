import SwiftUI

/// 侧栏：主导航 + 系统资源卡片（所有页面常驻，兼作 Performance 导航捷径）。
struct SidebarView: View {
    @Bindable var model: MonitorViewModel
    var compact: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(spacing: 2) {
                navItem(.performance, title: "Performance", icon: "chart.line.uptrend.xyaxis")
                navItem(.processes, title: "Processes", icon: "list.bullet")
                navItem(.ports, title: "Ports", icon: "target")
            }
            .padding(.horizontal, compact ? 6 : 8)
            .padding(.top, 10)

            if !compact {
                Text("系统资源")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Theme.text2)
                    .textCase(.uppercase)
                    .tracking(0.6)
                    .padding(.horizontal, 12)
                    .padding(.top, 10)
                    .padding(.bottom, 4)
            }
            VStack(spacing: 6) {
                resourceCard(.cpu, name: "CPU")
                resourceCard(.memory, name: "内存")
                resourceCard(.disk, name: "磁盘")
                resourceCard(.network, name: "网络")
            }
            .padding(.horizontal, compact ? 6 : 8)
            .padding(.top, compact ? 10 : 0)
            Spacer()
        }
        .frame(width: compact ? 58 : 212)
        .background(Theme.sidebar)
        .overlay(alignment: .trailing) { Theme.sep.frame(width: 1) }
    }

    // MARK: - 导航

    private func navItem(_ page: PrimaryView, title: String, icon: String) -> some View {
        let active = model.page == page
        return Button {
            model.page = page
        } label: {
            HStack(spacing: 8) {
                if compact {
                    Spacer(minLength: 0)
                    Image(systemName: icon)
                        .font(.system(size: 13))
                        .frame(width: 15)
                        .opacity(active ? 1 : 0.75)
                    Spacer(minLength: 0)
                } else {
                    Image(systemName: icon)
                        .font(.system(size: 13))
                        .frame(width: 15)
                        .opacity(active ? 1 : 0.75)
                    Text(title)
                        .font(.system(size: 13, weight: active ? .semibold : .regular))
                    Spacer(minLength: 0)
                }
            }
            .padding(.horizontal, compact ? 0 : 8)
            .frame(height: compact ? 34 : 26)
            .frame(maxWidth: .infinity)
            .background(active ? Theme.selected : .clear)
            .foregroundStyle(active ? Theme.accent : Color.primary)
            .clipShape(RoundedRectangle(cornerRadius: Theme.radiusS))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(title)
    }

    // MARK: - 资源卡片

    private func resourceCard(_ kind: ResourceKind, name: String) -> some View {
        let active = model.performance.resource == kind
        let status = model.performance.resourceStatus(kind, paused: model.settings.paused)
        return Button {
            // 卡片兼作导航捷径：任意页面点击后直达 Performance 对应资源
            model.performance.resource = kind
            model.page = .performance
        } label: {
            if compact {
                Text(name)
                    .font(.system(size: 10))
                    .foregroundStyle(Color.primary)
                    .frame(width: 44, height: 44)
            } else {
                VStack(alignment: .leading, spacing: 5) {
                    HStack(alignment: .firstTextBaseline) {
                        Text(name)
                            .font(.system(size: 12, weight: .semibold))
                        Spacer()
                        cardValue(kind)
                    }
                    cardSparkline(kind)
                    HStack(spacing: 5) {
                        StatusDot(kind: status.0)
                        Text(status.1)
                        Spacer()
                        cardSub(kind)
                    }
                    .font(.system(size: 10.5))
                    .foregroundStyle(Theme.text2)
                }
                .padding(.horizontal, 9)
                .padding(.vertical, 8)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .buttonStyle(.plain)
        .background(Theme.raised)
        .overlay(
            RoundedRectangle(cornerRadius: Theme.radiusM)
                .strokeBorder(active ? Theme.accent : Theme.sep, lineWidth: 1),
        )
        .clipShape(RoundedRectangle(cornerRadius: Theme.radiusM))
    }

    @ViewBuilder
    private func cardValue(_ kind: ResourceKind) -> some View {
        switch kind {
        case .cpu:
            Text(model.performance.history.last?.cpuTotal.map(Format.percent) ?? "—")
                .font(.system(size: 13, weight: .semibold))
                .monospacedDigit()
        case .memory:
            Text(model.performance.history.last.map { Format.bytes($0.memoryUsed) } ?? "—")
                .font(.system(size: 13, weight: .semibold))
                .monospacedDigit()
        case .network:
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text(model.performance.netHistory[model.performance.selectedInterface]?.last.map { Format.rate($0.rx) } ?? "—")
                    .font(.system(size: 13, weight: .semibold))
                    .monospacedDigit()
                Text("↓")
                    .font(.system(size: 10))
                    .foregroundStyle(Theme.text2)
            }
        case .disk:
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text(model.performance.diskHistory.last.map { Format.rate($0.read) } ?? "—")
                    .font(.system(size: 13, weight: .semibold))
                    .monospacedDigit()
                Text("读")
                    .font(.system(size: 10))
                    .foregroundStyle(Theme.text2)
            }
        }
    }

    @ViewBuilder
    private func cardSub(_ kind: ResourceKind) -> some View {
        switch kind {
        case .cpu:
            Text("\(ProcessInfo.processInfo.processorCount) 核").monospacedDigit()
        case .memory:
            if let last = model.performance.history.last {
                Text("共 \(Format.bytes(last.memoryTotal))").monospacedDigit()
            }
        case .network:
            if let last = model.performance.netHistory[model.performance.selectedInterface]?.last {
                Text("↑ \(Format.rate(last.tx))").monospacedDigit()
            }
        case .disk:
            if let last = model.performance.diskHistory.last {
                Text("写 \(Format.rate(last.write))").monospacedDigit()
            }
        }
    }

    @ViewBuilder
    private func cardSparkline(_ kind: ResourceKind) -> some View {
        switch kind {
        case .cpu:
            SparklineView(
                points: model.performance.history.suffix(60).compactMap { sample in
                    sample.cpuTotal.map { ChartPoint(t: sample.capturedAt, v: $0) }
                },
                color: Theme.cpu,
                yMax: 100,
            )
        case .memory:
            let ceiling = model.performance.history.last?.memoryTotal ?? 1
            SparklineView(
                points: model.performance.history.suffix(60).map { ChartPoint(t: $0.capturedAt, v: Double($0.memoryUsed)) },
                color: Theme.mem,
                yMax: Double(ceiling),
            )
        case .network:
            SparklineView(
                points: (model.performance.netHistory[model.performance.selectedInterface] ?? []).suffix(60).map {
                    ChartPoint(t: $0.t, v: $0.rx)
                },
                color: Theme.netDown,
            )
        case .disk:
            SparklineView(
                points: model.performance.diskHistory.suffix(60).map { ChartPoint(t: $0.t, v: $0.read + $0.write) },
                color: Theme.diskRead,
            )
        }
    }
}
