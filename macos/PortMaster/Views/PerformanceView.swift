import SwiftUI

/// Performance 页：CPU / 内存 / 网络为真实采样；磁盘为后续阶段占位。
struct PerformanceView: View {
    @Bindable var model: MonitorViewModel
    var compact = false

    var body: some View {
        VStack(spacing: 0) {
            pageHead
            Theme.sep.frame(height: 1)
            switch model.performance.resource {
            case .cpu, .memory, .network, .disk:
                chartBody
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    // MARK: - 页头

    private var pageHead: some View {
        HStack(spacing: 12) {
            Text(title)
                .font(.system(size: 15, weight: .bold))
            Spacer()
            let status = model.performance.resourceStatus(model.performance.resource, paused: model.settings.paused)
            StatusBadge(kind: status.0, label: status.1)
            if model.performance.resource == .cpu {
                cpuViewPicker
            }
            if model.performance.resource == .network {
                Picker("网卡", selection: $model.performance.selectedInterface) {
                    ForEach(model.performance.interfaceNames, id: \.self) { name in
                        Text(model.performance.interfaceDisplayName(name)).tag(name)
                    }
                }
                .fixedSize()
                .labelsHidden()
                .help("选择网卡")
            }
            rangePicker
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    private var title: String {
        switch model.performance.resource {
        case .cpu: "CPU"
        case .memory: "Memory（内存）"
        case .disk: "Disk（磁盘）"
        case .network: "Network（网络）"
        }
    }

    /// 紧凑模式下用菜单样式（更窄），常规用分段控件。
    @ViewBuilder
    private var cpuViewPicker: some View {
        if compact {
            Picker("CPU 视图", selection: $model.performance.cpuShowPerCore) {
                Text("总体").tag(false)
                Text("逐逻辑核心").tag(true)
            }
            .pickerStyle(.menu)
            .fixedSize()
            .labelsHidden()
            .help("CPU 视图")
        } else {
            Picker("CPU 视图", selection: $model.performance.cpuShowPerCore) {
                Text("总体").tag(false)
                Text("逐逻辑核心").tag(true)
            }
            .pickerStyle(.segmented)
            .fixedSize()
            .labelsHidden()
        }
    }

    @ViewBuilder
    private var rangePicker: some View {
        if compact {
            Picker("时间范围", selection: $model.performance.range) {
                Text("60 秒").tag(TimeInterval(60))
                Text("5 分钟").tag(TimeInterval(300))
                Text("15 分钟").tag(TimeInterval(900))
            }
            .pickerStyle(.menu)
            .fixedSize()
            .labelsHidden()
            .help("时间范围")
        } else {
            Picker("时间范围", selection: $model.performance.range) {
                Text("60 秒").tag(TimeInterval(60))
                Text("5 分钟").tag(TimeInterval(300))
                Text("15 分钟").tag(TimeInterval(900))
            }
            .pickerStyle(.segmented)
            .fixedSize()
            .labelsHidden()
        }
    }

    // MARK: - 图表主体

    private var chartBody: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                chartBox
                statRow
                compositionCard
                capacityCard
                rankBox
            }
            .padding(14)
        }
    }

    /// 磁盘容量（独立于吞吐，原型设计）：根卷已用 / 总量 + 进度条。
    @ViewBuilder
    private var capacityCard: some View {
        if model.performance.resource == .disk, let capacity = model.performance.diskCapacity {
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .firstTextBaseline) {
                    Text("容量（独立于吞吐）")
                        .font(.system(size: 12.5, weight: .semibold))
                    Spacer()
                    Text("Macintosh HD (/)")
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.text2)
                }
                HStack {
                    Text("已用 ")
                        .foregroundStyle(Theme.text2)
                        + Text(Format.bytes(capacity.used))
                        .foregroundStyle(Color.primary)
                        .fontWeight(.semibold)
                        .monospacedDigit()
                    Spacer()
                    Text("共 \(Format.bytes(capacity.total))")
                        .foregroundStyle(Theme.text2)
                }
                .font(.system(size: 12))
                GeometryReader { proxy in
                    ZStack(alignment: .leading) {
                        Theme.inset
                        Theme.diskRead
                            .frame(width: proxy.size.width * min(1, Double(capacity.used) / Double(max(1, capacity.total))))
                    }
                }
                .frame(height: 6)
                .clipShape(Capsule())
                Text("容量与读写吞吐为不同指标，分别展示。可用空间含可清除内容（与 Finder 口径一致）。")
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.text3)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(Theme.raised)
            .overlay(RoundedRectangle(cornerRadius: Theme.radiusM).strokeBorder(Theme.sep, lineWidth: 1))
            .clipShape(RoundedRectangle(cornerRadius: Theme.radiusM))
        }
    }

    /// 内存构成（对应 top 的 PhysMem 分解）：应用 / 联动 / 已压缩 / 未占用。
    @ViewBuilder
    private var compositionCard: some View {
        if model.performance.resource == .memory, let last = model.performance.history.last {
            let segments: [(label: String, value: UInt64, color: Color)] = [
                ("应用", last.memoryActive, Theme.mem),
                ("联动", last.memoryWired, Theme.accent),
                ("已压缩", last.memoryCompressed, Theme.warn),
            ]
            let rest = last.memoryTotal - min(last.memoryUsed, last.memoryTotal)
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .firstTextBaseline) {
                    Text("内存构成")
                        .font(.system(size: 12.5, weight: .semibold))
                    Text("构成口径：应用 + 联动 + 已压缩 = 已使用；其余为未占用（含可回收）")
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.text2)
                }
                // 堆叠条
                Canvas { context, size in
                    var x: CGFloat = 0
                    let total = Double(max(1, last.memoryTotal))
                    for segment in segments + [("未占用", rest, Color.clear)] {
                        let width = size.width * Double(segment.value) / total
                        guard width > 0 else { continue }
                        let rect = CGRect(x: x, y: 0, width: width, height: size.height)
                        context.fill(Path(rect), with: .color(segment.color))
                        x += width
                    }
                }
                .frame(height: 14)
                .background(Theme.inset)
                .clipShape(RoundedRectangle(cornerRadius: 4))
                // 图例
                HStack(spacing: 14) {
                    ForEach(segments + [("未占用", rest, Color(nsColor: .systemGray))], id: \.label) { segment in
                        HStack(spacing: 5) {
                            RoundedRectangle(cornerRadius: 2)
                                .fill(segment.color)
                                .frame(width: 8, height: 8)
                            Text(segment.label)
                            Text(Format.bytes(segment.value))
                                .monospacedDigit()
                        }
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.text2)
                    }
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(Theme.raised)
            .overlay(RoundedRectangle(cornerRadius: Theme.radiusM).strokeBorder(Theme.sep, lineWidth: 1))
            .clipShape(RoundedRectangle(cornerRadius: Theme.radiusM))
        }
    }

    private var chartBox: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(chartTitle)
                    .font(.system(size: 12.5, weight: .semibold))
                    .lineLimit(1)
                // if !compact {
                //     Text(chartNote)
                //         .font(.system(size: 11))
                //         .foregroundStyle(Theme.text2)
                //         .lineLimit(1)
                //         .layoutPriority(-1)
                // }
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
                    window: model.performance.chartWindow,
                    yMin: 0,
                    yMax: chartYMax,
                    yLabel: yLabel,
                    tickSeconds: model.performance.tickInterval,
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
        switch model.performance.resource {
        case .network:
            return (model.performance.netHistory[model.performance.selectedInterface] ?? []).isEmpty
        case .disk:
            return model.performance.diskHistory.isEmpty
        default:
            return model.performance.history.isEmpty
        }
    }

    private var chartTitle: String {
        switch model.performance.resource {
        case .cpu:
            return model.performance.cpuShowPerCore
                ? "逐逻辑核心（\(ProcessInfo.processInfo.processorCount) 核）"
                : "整机 CPU 使用率"
        case .memory: return "内存使用"
        case .network: return "收发速率 · \(model.performance.interfaceDisplayName(model.performance.selectedInterface))"
        case .disk: return "读写吞吐 · 整机"
        }
    }

    private var chartNote: String {
        switch model.performance.resource {
        case .cpu: "纵轴固定 0–100%（整机口径）"
        case .memory: "以物理总量为参照；已使用 = 活动 + 联动 + 压缩"
        case .network: "收发速率（纵轴自适应、带迟滞）；不依据连接数或端口数推算"
        case .disk: "读写吞吐（纵轴自适应、带迟滞，IOKit 块存储计数）；容量见下方独立区块"
        }
    }

    @ViewBuilder
    private var legend: some View {
        HStack(spacing: 14) {
            switch model.performance.resource {
            case .cpu:
                legendSwatch(Theme.cpu, model.performance.cpuShowPerCore ? "整机" : "整机使用率")
                if model.performance.cpuShowPerCore {
                    legendSwatch(Color(nsColor: .systemGray), "各逻辑核心（\(ProcessInfo.processInfo.processorCount)）")
                }
            case .memory:
                legendSwatch(Theme.mem, "已使用")
                if let total = model.performance.history.last?.memoryTotal {
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
            case .disk:
                legendSwatch(Theme.diskRead, "读取")
                legendSwatch(Theme.diskWrite, "写入")
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
        let samples = model.performance.samplesInWindow()
        switch model.performance.resource {
        case .cpu:
            var result = [
                ChartSeries(
                    color: Theme.cpu,
                    points: samples.map { sample in sample.cpuTotal.map { ChartPoint(t: sample.capturedAt, v: $0) } },
                    fill: !model.performance.cpuShowPerCore,
                    width: model.performance.cpuShowPerCore ? 2.2 : 1.6,
                    label: "整机",
                    format: Format.percent,
                ),
            ]
            if model.performance.cpuShowPerCore, let coreCount = samples.last?.cpuPerCore.count {
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
            let netSamples = model.performance.netSamplesInWindow()
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
        case .disk:
            let diskSamples = model.performance.diskSamplesInWindow()
            return [
                ChartSeries(
                    color: Theme.diskRead,
                    points: diskSamples.map { ChartPoint(t: $0.t, v: $0.read) },
                    fill: true,
                    label: "读取",
                    format: Format.rate,
                ),
                ChartSeries(
                    color: Theme.diskWrite,
                    points: diskSamples.map { ChartPoint(t: $0.t, v: $0.write) },
                    fill: true,
                    label: "写入",
                    format: Format.rate,
                ),
            ]
        default:
            return []
        }
    }

    private var chartYMax: Double {
        switch model.performance.resource {
        case .cpu: 100
        case .memory: Double(model.performance.history.last?.memoryTotal ?? 16 * 1024 * 1024 * 1024)
        case .network: model.performance.netScaleMax ?? 1_048_576
        case .disk: model.performance.diskScaleMax ?? 1_048_576
        }
    }

    private var yLabel: (Double) -> String {
        switch model.performance.resource {
        case .cpu: { "\(Int($0))%" }
        case .memory: { String(format: "%.0f GB", $0 / 1_073_741_824) }
        case .network, .disk: { Format.rate($0) }
        }
    }

//    private var refLine: (y: Double, label: String)? {
//        guard model.performance.resource == .memory, let total = model.performance.history.last?.memoryTotal else { return nil }
//        return (Double(total), "物理总量aa \(Format.bytes(total))")
//    }

    // MARK: - 统计行

    private var statRow: some View {
        HStack(spacing: 10) {
            switch model.performance.resource {
            case .cpu:
                let last = model.performance.history.last
                let values = model.performance.samplesInWindow().compactMap(\.cpuTotal)
                let stats = model.performance.windowStats(values: values)
                let usageSub: String? = switch (last?.cpuUser, last?.cpuSystem) {
                case let (user?, system?): "用户 \(Format.percent(user)) · 系统 \(Format.percent(system))"
                default: nil
                }
                statTile("当前", last?.cpuTotal.map(Format.percent) ?? "—", sub: usageSub)
                statTile("平均（\(rangeLabel)）", stats.average.map(Format.percent) ?? "—")
                statTile("峰值（\(rangeLabel)）", stats.peak.map(Format.percent) ?? "—")
                statTile(
                    "Load Avg",
                    last.map { String(format: "%.2f · %.2f · %.2f", $0.load1, $0.load5, $0.load15) } ?? "—",
                    sub: "1 / 5 / 15 分钟",
                )
                statTile("逻辑核心", "\(ProcessInfo.processInfo.processorCount) 核")
            case .memory:
                let last = model.performance.history.last
                let values = model.performance.samplesInWindow().map { Double($0.memoryUsed) }
                let stats = model.performance.windowStats(values: values)
                statTile("已使用", last.map { Format.bytes($0.memoryUsed) } ?? "—", sub: last.map { "共 \(Format.bytes($0.memoryTotal))" })
                statTile("平均（\(rangeLabel)）", stats.average.map { Format.bytes(UInt64(max(0, $0))) } ?? "—")
                // swap 存量 + 换入/换出速率（事实信号，不做压力判决）
                let swapSub: String? = last.flatMap { sample in
                    guard let inRate = sample.swapInRate, let outRate = sample.swapOutRate else { return nil }
                    return String(format: "换入 %.1f/s · 换出 %.1f/s", inRate, outRate)
                }
                statTile("交换空间", last.map { Format.bytes($0.swapUsed) } ?? "—", sub: swapSub)
                // 可用内存：事实数值，不做正常/警告/严重判决（阈值无权威口径）
                statTile("可用内存", last?.memoryAvailablePercent.map { "\($0)%" } ?? "—", sub: "kern.memorystatus_level")
            case .network:
                let last = model.performance.netHistory[model.performance.selectedInterface]?.last
                let peakRx = model.performance.netSamplesInWindow().map(\.rx).max()
                statTile("当前下载", last.map { Format.rate($0.rx) } ?? "—")
                statTile("当前上传", last.map { Format.rate($0.tx) } ?? "—")
                statTile("下载峰值（\(rangeLabel)）", peakRx.map(Format.rate) ?? "—")
                statTile("网卡", model.performance.interfaceDisplayName(model.performance.selectedInterface))
            case .disk:
                let last = model.performance.diskHistory.last
                let peakRead = model.performance.diskSamplesInWindow().map(\.read).max()
                statTile("当前读取", last.map { Format.rate($0.read) } ?? "—")
                statTile("当前写入", last.map { Format.rate($0.write) } ?? "—")
                statTile("读取峰值（\(rangeLabel)）", peakRead.map(Format.rate) ?? "—")
//                statTile("设备", "整机")
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

    // MARK: - 排行

    @ViewBuilder
    private var rankBox: some View {
        switch model.performance.resource {
        case .cpu, .memory:
            let isCPU = model.performance.resource == .cpu
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
                ForEach(model.topProcesses(by: model.performance.resource)) { entry in
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
//        case .network:
//            Text("本阶段不展示「每进程网络速率」——该指标口径尚未定义，避免误导。")
//                .font(.system(size: 11))
//                .foregroundStyle(Theme.text2)
//                .padding(.horizontal, 12)
//                .padding(.vertical, 7)
//                .frame(maxWidth: .infinity, alignment: .leading)
//                .background(Theme.inset)
//                .overlay(RoundedRectangle(cornerRadius: Theme.radiusM).strokeBorder(Theme.sep, lineWidth: 1))
//                .clipShape(RoundedRectangle(cornerRadius: Theme.radiusM))
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

    private var rangeLabel: String {
        switch Int(model.performance.range) {
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
