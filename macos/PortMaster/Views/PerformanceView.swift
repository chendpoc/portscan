import SwiftUI

/// Performance 页：CPU / 内存 / 网络为真实采样；磁盘为后续阶段占位。
struct PerformanceView: View {
    @Bindable var model: MonitorViewModel
    var compact = false

    var body: some View {
        VStack(spacing: 0) {
            pageHead
            Theme.sep.frame(height: 1)
            switch model.resource {
            case .cpu, .memory, .network:
                chartBody
            case .disk:
                placeholderBody
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    // MARK: - 页头

    private var pageHead: some View {
        HStack(spacing: 12) {
            Text(title)
                .font(.system(size: 15, weight: .bold))
            switch model.resource {
            case .disk:
                PhaseTag(label: "后续阶段设计范围")
            case .cpu, .memory, .network:
                if !compact {
                    Text(model.resource == .network ? "" : "第一阶段核心体验")
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.text2)
                        .lineLimit(1)
                        .layoutPriority(-1) // 空间不足时优先截断说明文字，不压缩右侧控件
                }
            }
            Spacer()
            let status = model.resourceStatus(model.resource)
            StatusBadge(kind: status.0, label: status.1)
            if model.resource == .cpu {
                Picker("CPU 视图", selection: $model.cpuShowPerCore) {
                    Text("总体").tag(false)
                    Text("逐逻辑核心").tag(true)
                }
                .pickerStyle(.segmented)
                .fixedSize()
            }
            if model.resource == .network {
                Picker("网卡", selection: $model.selectedInterface) {
                    ForEach(model.interfaceNames, id: \.self) { name in
                        Text(model.interfaceDisplayName(name)).tag(name)
                    }
                }
                .fixedSize()
                .labelsHidden()
                .help("选择网卡")
            }
            Picker("时间范围", selection: $model.range) {
                Text("60 秒").tag(TimeInterval(60))
                Text("5 分钟").tag(TimeInterval(300))
                Text("15 分钟").tag(TimeInterval(900))
            }
            .pickerStyle(.segmented)
            .fixedSize()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    private var title: String {
        switch model.resource {
        case .cpu: "CPU"
        case .memory: "Memory（内存）"
        case .disk: "Disk（磁盘）"
        case .network: "Network（网络）"
        }
    }

    // MARK: - 图表主体

    private var chartBody: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                chartBox
                statRow
                rankBox
            }
            .padding(14)
        }
    }

    private var chartBox: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(chartTitle)
                    .font(.system(size: 12.5, weight: .semibold))
                    .lineLimit(1)
                if !compact {
                    Text(chartNote)
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.text2)
                        .lineLimit(1)
                        .layoutPriority(-1)
                }
                Spacer()
                legend
            }
            if waitingForFirstSample {
                ZStack {
                    Theme.inset
                    Text("正在采集首个样本，请稍候…")
                        .font(.system(size: 12.5))
                        .foregroundStyle(Theme.text3)
                }
                .frame(height: 220)
                .clipShape(RoundedRectangle(cornerRadius: Theme.radiusS))
            } else {
                MetricChartView(
                    series: chartSeries,
                    window: model.chartWindow,
                    yMin: 0,
                    yMax: chartYMax,
                    yLabel: yLabel,
                    tickSeconds: model.tickInterval,
                    height: 220,
//                    refLine: refLine,
                )
            }
        }
        .padding(.horizontal, 12)
        .padding(.top, 12)
        .padding(.bottom, 8)
        .background(Theme.raised)
        .overlay(RoundedRectangle(cornerRadius: Theme.radiusM).strokeBorder(Theme.sep, lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: Theme.radiusM))
    }

    private var waitingForFirstSample: Bool {
        switch model.resource {
        case .network:
            return (model.netHistory[model.selectedInterface] ?? []).isEmpty
        default:
            return model.history.isEmpty
        }
    }

    private var chartTitle: String {
        switch model.resource {
        case .cpu:
            return model.cpuShowPerCore
                ? "逐逻辑核心（\(ProcessInfo.processInfo.processorCount) 核）"
                : "整机 CPU 使用率"
        case .memory: return "内存使用"
        case .network: return "收发速率 · \(model.interfaceDisplayName(model.selectedInterface))"
        default: return ""
        }
    }

    private var chartNote: String {
        switch model.resource {
        case .cpu: "纵轴固定 0–100%（整机口径）"
        case .memory: "以物理总量为参照；已使用 = 活动 + 联动 + 压缩"
        case .network: "收发速率（纵轴自适应、带迟滞）；不依据连接数或端口数推算"
        default: ""
        }
    }

    @ViewBuilder
    private var legend: some View {
        HStack(spacing: 14) {
            switch model.resource {
            case .cpu:
                legendSwatch(Theme.cpu, model.cpuShowPerCore ? "整机" : "整机使用率")
                if model.cpuShowPerCore {
                    legendSwatch(Color(nsColor: .systemGray), "各逻辑核心（\(ProcessInfo.processInfo.processorCount)）")
                }
            case .memory:
                legendSwatch(Theme.mem, "已使用")
                if let total = model.history.last?.memoryTotal {
                    Text("物理总量 \(Format.bytes(total))")
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.text2)
                        .overlay(alignment: .bottom) {
                            Rectangle()
                                .fill(Theme.text3)
                                .frame(height: 1)
                                .offset(y: 1)
                        }
                }
            case .network:
                legendSwatch(Theme.netDown, "下载")
                legendSwatch(Theme.netUp, "上传")
            default:
                EmptyView()
            }
        }
    }

    private func legendSwatch(_ color: Color, _ label: String) -> some View {
        HStack(spacing: 5) {
            RoundedRectangle(cornerRadius: 2).fill(color).frame(width: 8, height: 8)
            Text(label)
        }
        .font(.system(size: 11))
        .foregroundStyle(Theme.text2)
    }

    private var chartSeries: [ChartSeries] {
        let samples = model.samplesInWindow()
        switch model.resource {
        case .cpu:
            var result = [
                ChartSeries(
                    color: Theme.cpu,
                    points: samples.map { sample in sample.cpuTotal.map { ChartPoint(t: sample.capturedAt, v: $0) } },
                    fill: !model.cpuShowPerCore,
                    width: model.cpuShowPerCore ? 2.2 : 1.6,
                    label: "整机",
                    format: Format.percent,
                ),
            ]
            if model.cpuShowPerCore, let coreCount = samples.last?.cpuPerCore.count {
                for core in 0..<coreCount {
                    result.append(
                        ChartSeries(
                            color: Color(nsColor: .systemGray),
                            points: samples.map { sample in
                                guard core < sample.cpuPerCore.count else { return nil }
                                return ChartPoint(t: sample.capturedAt, v: sample.cpuPerCore[core])
                            },
                            width: 1,
                            alpha: 0.35,
                            label: "核心 \(core + 1)",
                            format: Format.percent,
                        ),
                    )
                }
            }
            return result
        case .memory:
            return [
                ChartSeries(
                    color: Theme.mem,
                    points: samples.map { ChartPoint(t: $0.capturedAt, v: Double($0.memoryUsed)) },
                    fill: true,
                    label: "已使用",
                    format: { Format.bytes(UInt64(max(0, $0))) },
                ),
            ]
        case .network:
            let netSamples = model.netSamplesInWindow()
            return [
                ChartSeries(
                    color: Theme.netDown,
                    points: netSamples.map { ChartPoint(t: $0.t, v: $0.rx) },
                    fill: true,
                    label: "下载",
                    format: Format.rate,
                ),
                ChartSeries(
                    color: Theme.netUp,
                    points: netSamples.map { ChartPoint(t: $0.t, v: $0.tx) },
                    fill: true,
                    label: "上传",
                    format: Format.rate,
                ),
            ]
        default:
            return []
        }
    }

    private var chartYMax: Double {
        switch model.resource {
        case .cpu: 100
        case .memory: Double(model.history.last?.memoryTotal ?? 16 * 1024 * 1024 * 1024)
        case .network: model.netScaleMax ?? 1_048_576
        default: 100
        }
    }

    private var yLabel: (Double) -> String {
        switch model.resource {
        case .cpu: { "\(Int($0))%" }
        case .memory: { String(format: "%.0f GB", $0 / 1_073_741_824) }
        case .network: { Format.rate($0) }
        default: { "\($0)" }
        }
    }

//    private var refLine: (y: Double, label: String)? {
//        guard model.resource == .memory, let total = model.history.last?.memoryTotal else { return nil }
//        return (Double(total), "物理总量aa \(Format.bytes(total))")
//    }

    // MARK: - 统计行

    private var statRow: some View {
        HStack(spacing: 10) {
            switch model.resource {
            case .cpu:
                let values = model.samplesInWindow().compactMap(\.cpuTotal)
                let stats = model.windowStats(values: values)
                statTile("当前", model.history.last?.cpuTotal.map(Format.percent) ?? "—")
                statTile("平均（\(rangeLabel)）", stats.average.map(Format.percent) ?? "—")
                statTile("峰值（\(rangeLabel)）", stats.peak.map(Format.percent) ?? "—")
                statTile("逻辑核心", "\(ProcessInfo.processInfo.processorCount) 核")
            case .memory:
                let last = model.history.last
                let values = model.samplesInWindow().map { Double($0.memoryUsed) }
                let stats = model.windowStats(values: values)
                statTile("已使用", last.map { Format.bytes($0.memoryUsed) } ?? "—", sub: last.map { "共 \(Format.bytes($0.memoryTotal))" })
                statTile("平均（\(rangeLabel)）", stats.average.map { Format.bytes(UInt64(max(0, $0))) } ?? "—")
                statTile("交换空间", last.map { Format.bytes($0.swapUsed) } ?? "—")
                pressureTile
            case .network:
                let last = model.netHistory[model.selectedInterface]?.last
                let peakRx = model.netSamplesInWindow().map(\.rx).max()
                statTile("当前下载", last.map { Format.rate($0.rx) } ?? "—")
                statTile("当前上传", last.map { Format.rate($0.tx) } ?? "—")
                statTile("下载峰值（\(rangeLabel)）", peakRx.map(Format.rate) ?? "—")
                statTile("网卡", model.interfaceDisplayName(model.selectedInterface))
            default:
                EmptyView()
            }
        }
    }

    /// 统计瓦片：标签 / 数值 / 注释三行结构固定（无注释时占位），
    /// 等高拉伸 + 顶部对齐，保证一组瓦片高度与基线一致。
    private func statTile(_ label: String, _ value: String, sub: String? = nil) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.system(size: 11))
                .foregroundStyle(Theme.text2)
                .lineLimit(1)
                .frame(height: 16, alignment: .leading)
            Text(value)
                .font(.system(size: 17, weight: .semibold))
                .monospacedDigit()
                .lineLimit(1)
                .frame(height: 21, alignment: .leading)
            Text(sub ?? " ")
                .font(.system(size: 11))
                .foregroundStyle(Theme.text2)
                .lineLimit(1)
                .frame(height: 16, alignment: .leading)
        }
        .padding(.horizontal, 11)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Theme.raised)
        .overlay(RoundedRectangle(cornerRadius: Theme.radiusM).strokeBorder(Theme.sep, lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: Theme.radiusM))
    }

    @ViewBuilder
    private var pressureTile: some View {
        if let available = model.history.last?.memoryAvailablePercent {
            let kind = MemoryPressureKind(availablePercent: available)
            let (badgeKind, label): (StatusKind, String) = switch kind {
            case .normal: (.ok, "正常")
            case .warning: (.warn, "警告")
            case .critical: (.err, "严重")
            }
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 5) {
                    Text("内存压力")
                    StatusBadge(kind: .mut, label: "系统报告")
                }
                .font(.system(size: 11))
                .foregroundStyle(Theme.text2)
                .frame(height: 16, alignment: .leading)
                HStack {
                    StatusBadge(kind: badgeKind, label: label)
                }
                .frame(height: 21, alignment: .leading)
                Text("kern.memorystatus_level：可用 \(available)%")
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.text2)
                    .lineLimit(1)
                    .frame(height: 16, alignment: .leading)
            }
            .padding(.horizontal, 11)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(Theme.raised)
            .overlay(RoundedRectangle(cornerRadius: Theme.radiusM).strokeBorder(Theme.sep, lineWidth: 1))
            .clipShape(RoundedRectangle(cornerRadius: Theme.radiusM))
        }
    }

    // MARK: - 排行

    @ViewBuilder
    private var rankBox: some View {
        switch model.resource {
        case .cpu, .memory:
            let isCPU = model.resource == .cpu
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Text(isCPU ? "CPU 占用最高的进程" : "内存占用最高的进程")
                        .font(.system(size: 12.5, weight: .semibold))
                    Spacer()
                    Text("当前占用 · 实时排行")
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.text2)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                Theme.sep.frame(height: 1)
                ForEach(model.topProcesses(by: model.resource)) { entry in
                    rankRow(entry, isCPU: isCPU)
                }
                Theme.sep.frame(height: 1)
                Text("排行为当前实时占用。图表中历史时间点的系统指标与当前排行无对应关系。")
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.text2)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Theme.inset)
            }
            .background(Theme.raised)
            .overlay(RoundedRectangle(cornerRadius: Theme.radiusM).strokeBorder(Theme.sep, lineWidth: 1))
            .clipShape(RoundedRectangle(cornerRadius: Theme.radiusM))
        case .network:
            Text("本阶段不展示「每进程网络速率」——该指标口径尚未定义，避免误导。")
                .font(.system(size: 11))
                .foregroundStyle(Theme.text2)
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Theme.inset)
                .overlay(RoundedRectangle(cornerRadius: Theme.radiusM).strokeBorder(Theme.sep, lineWidth: 1))
                .clipShape(RoundedRectangle(cornerRadius: Theme.radiusM))
        default:
            EmptyView()
        }
    }

    private func rankRow(_ entry: ProcessEntry, isCPU: Bool) -> some View {
        Button {
            model.selectProcess(entry)
        } label: {
            HStack(spacing: 10) {
                Text(entry.name)
                    .font(.system(size: 12.5))
                    .lineLimit(1)
                    .truncationMode(.tail)
                Spacer()
                Text(verbatim: "PID \(entry.key.pid)")
                    .font(.system(size: 11.5))
                    .foregroundStyle(Theme.text3)
                    .monospacedDigit()
                Text(isCPU
                    ? entry.cpuPercent.map(Format.percent) ?? "—"
                    : entry.rssBytes.map(Format.bytes) ?? "—")
                    .font(.system(size: 12.5, weight: .semibold))
                    .monospacedDigit()
                    .frame(minWidth: 64, alignment: .trailing)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .contentShape(Rectangle())
        }
        .buttonStyle(RankRowButtonStyle())
    }

    // MARK: - 占位（后续阶段）

    private var placeholderBody: some View {
        VStack(spacing: 10) {
            Spacer()
            PhaseTag(label: "后续阶段设计范围")
            Text(model.resource == .disk ? "磁盘吞吐" : "网络吞吐")
                .font(.system(size: 14, weight: .semibold))
            Text(model.resource == .disk
                ? "当前版本不采集磁盘读写速率。该视图已按原型预留：\n读写吞吐图（纵轴自适应）与容量区块将在后续阶段接入真实卷信息。"
                : "当前版本不依据连接数或端口数推算网络速率。该视图已按原型预留：\n收发速率图与网卡选择将在后续阶段接入真实接口计数器。")
                .font(.system(size: 12))
                .foregroundStyle(Theme.text2)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 420)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    private var rangeLabel: String {
        switch Int(model.range) {
        case 60: "60 秒"
        case 300: "5 分钟"
        default: "15 分钟"
        }
    }
}

/// 排行行：悬停底色，按压不变形。
private struct RankRowButtonStyle: ButtonStyle {
    @State private var hovering = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(hovering ? Theme.hover : .clear)
            .foregroundStyle(Color.primary)
            .onHover { hovering = $0 }
            .animation(.easeOut(duration: 0.12), value: hovering)
    }
}
