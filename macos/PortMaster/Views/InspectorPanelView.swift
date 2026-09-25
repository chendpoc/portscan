import SwiftUI

/// Inspector：状态 / 身份 KV、从选中起记录的 CPU/RSS 趋势、路径与命令、关联端口、操作。
struct InspectorPanelView: View {
    @Bindable var model: MonitorViewModel
    var compact: Bool
    var onBack: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            header
            Theme.sep.frame(height: 1)
            if model.selectedKey != nil {
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        if model.selectedExited {
                            exitedBanner
                        }
                        identitySection
                        trendSection
                        if model.detailLoading {
                            HStack(spacing: 6) {
                                ProgressView().controlSize(.small)
                                Text("正在读取进程详情…")
                                    .font(.system(size: 11))
                                    .foregroundStyle(Theme.text2)
                            }
                        }
                        if let detail = model.detail {
                            pathsSection(detail)
                        } else if let error = model.detailError, !model.selectedExited {
                            Text(error)
                                .font(.system(size: 11))
                                .foregroundStyle(Theme.err)
                        }
                        portsSection
                        actionsSection
                    }
                    .padding(12)
                }
            } else {
                Spacer()
            }
        }
        .background(Theme.sidebar)
        .overlay(alignment: .leading) { Theme.sep.frame(width: 1) }
    }

    // MARK: - 头部

    private var header: some View {
        HStack(spacing: 8) {
            if compact {
                Button(action: onBack) {
                    Label("返回", systemImage: "chevron.left")
                        .font(.system(size: 12.5))
                        .foregroundStyle(Theme.accent)
                }
                .buttonStyle(.plain)
            }
            Text(model.selectedSnapshot?.name ?? "Inspector")
                .font(.system(size: 13, weight: .bold))
                .lineLimit(1)
                .truncationMode(.tail)
            Spacer()
            Button(action: onBack) {
                Image(systemName: "xmark")
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.text2)
                    .frame(width: 24, height: 24)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("关闭 Inspector")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }

    private var exitedBanner: some View {
        Text("该进程已退出。以下为退出前最后记录的信息，趋势图已停止更新。")
            .font(.system(size: 11.5))
            .foregroundStyle(Theme.warn)
            .lineSpacing(2)
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.warn.opacity(0.1))
            .overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(Theme.warn.opacity(0.4), lineWidth: 1))
            .clipShape(RoundedRectangle(cornerRadius: 7))
    }

    // MARK: - 身份

    private var identitySection: some View {
        VStack(alignment: .leading, spacing: 7) {
            kvRow("状态") {
                statusBadge
            }
            if let key = model.selectedKey {
                kvRow("PID") {
                    HStack(spacing: 6) {
                        Text(verbatim: "\(key.pid)").monospacedDigit()
//                        Text("实例键：PID+启动时间")
//                            .font(.system(size: 11))
//                            .foregroundStyle(Theme.text3)
                    }
                }
                kvRow("启动时间") {
                    Text(Format.dateTime(Date(timeIntervalSince1970: TimeInterval(key.startSec))))
                        .monospacedDigit()
                }
            }
            kvRow("用户") {
                Text(model.detail?.userName ?? "—")
            }
            kvRow("父进程") {
                parentView
            }
        }
    }

    @ViewBuilder
    private var statusBadge: some View {
        if model.selectedExited {
            StatusBadge(kind: .warn, label: "已退出")
        } else if let snapshot = model.selectedSnapshot,
                  snapshot.cwd.state == .restricted, snapshot.executable.state == .restricted {
            StatusBadge(kind: .warn, label: "权限受限")
        } else {
            StatusBadge(kind: .ok, label: "运行中")
        }
    }

    @ViewBuilder
    private var parentView: some View {
        if let parentPid = model.selectedSnapshot?.parentPid,
           let parent = (model.monitor.processes?.entries ?? []).first(where: { $0.key.pid == parentPid }) {
            Button {
                model.selectProcess(parent)
            } label: {
                Text(verbatim: "\(parent.name) (PID \(parent.key.pid))")
                    .foregroundStyle(Theme.accent)
            }
            .buttonStyle(.plain)
        } else {
            Text(model.selectedSnapshot?.parentPid.map { "PID \($0)" } ?? "—")
                .monospacedDigit()
        }
    }

    // MARK: - 趋势（从选中起记录）

    @ViewBuilder
    private var trendSection: some View {
        if let key = model.selectedKey {
            let id = ProcessKeyFormatting.id(for: key)
            let record = model.observed[id]
            section(title: "趋势（CPU / RSS）") {
                if let record, record.samples.count > 1 {
                    let cpuPoints = record.samples.compactMap { sample in sample.cpu.map { ChartPoint(t: sample.t, v: $0) } }
                    let rssPoints = record.samples.compactMap { sample in sample.rss.map { ChartPoint(t: sample.t, v: Double($0)) } }
                    if cpuPoints.isEmpty, rssPoints.isEmpty {
                        // 任务信息不可读（系统守护进程常见）：明示不可用，绝不显示伪造的 0 刻度轴
                        StatusBadge(kind: .mut, label: "指标不可用")
                        note("macOS 拒绝读取该进程的任务信息（通常见于系统守护进程）。CPU / RSS 不可用时不展示，而不是显示为 0。")
                    } else {
                        if !cpuPoints.isEmpty {
                            trendChart(
                                title: "CPU %（整机口径）",
                                points: cpuPoints,
                                color: Theme.cpu,
                                yMax: 100,
                                yLabel: { "\(Int($0))%" },
                                format: Format.percent,
                                t0: record.t0,
                            )
                        }
                        if !rssPoints.isEmpty {
                            trendChart(
                                title: "内存 RSS",
                                points: rssPoints,
                                color: Theme.mem,
                                yMax: max(1, (record.samples.compactMap(\.rss).max().map(Double.init) ?? 1) * 1.2),
                                yLabel: { Format.bytes(UInt64(max(0, $0))) },
                                format: { Format.bytes(UInt64(max(0, $0))) },
                                t0: record.t0,
                            )
                        }
                    }
//                    note("观察起点 \(Format.time(record.t0)) —— \(model.selectedExited ? "进程已退出，以上为保留的最后记录。" : "")")
                } else {
                    trendPlaceholder("CPU %（整机口径）")
                    trendPlaceholder("内存 RSS")
                }
            }
        }
    }

    /// 首个样本积累期的占位图框：与正式图框同结构同尺寸，图表出现后布局不跳动。
    private func trendPlaceholder(_ title: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(title)
                    .font(.system(size: 11.5))
                    .foregroundStyle(Theme.text2)
                Spacer()
                Text("—")
                    .font(.system(size: 11.5))
                    .monospacedDigit()
            }
            ZStack {
                Theme.inset
                HStack(spacing: 6) {
                    ProgressView().controlSize(.mini)
                    Text("正在采集首个样本…")
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.text3)
                }
            }
            .frame(height: 52)
            .clipShape(RoundedRectangle(cornerRadius: Theme.radiusS))
        }
        .padding(8)
        .background(Theme.raised)
        .overlay(RoundedRectangle(cornerRadius: Theme.radiusM).strokeBorder(Theme.sep, lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: Theme.radiusM))
    }

    private func trendChart(
        title: String,
        points: [ChartPoint],
        color: Color,
        yMax: Double,
        yLabel: @escaping (Double) -> String,
        format: @escaping (Double) -> String,
        t0: Date,
    ) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(title)
                    .font(.system(size: 11.5))
                    .foregroundStyle(Theme.text2)
                Spacer()
                Text(points.last.map { format($0.v) } ?? "—")
                    .font(.system(size: 11.5))
                    .monospacedDigit()
            }
            MetricChartView(
                // 迷你趋势图用纯折线：52px 高度下填充会糊成色块，描边更清晰
                series: [ChartSeries(color: color, points: points, fill: false, width: 2, format: format)],
                window: t0...max(t0, model.now),
                yMin: 0,
                yMax: yMax,
                yLabel: yLabel,
                // 观察样本跟随进程刷新间隔（1/2/5s 可调），断线阈值必须用真实采样节奏，
                // 否则 5s 间隔时所有样本被判为缺口，折线全部消失
                tickSeconds: TimeInterval(model.settings.intervalMs) / 1000,
                height: 52,
                mini: true,
            )
        }
        .padding(8)
        .background(Theme.raised)
        .overlay(RoundedRectangle(cornerRadius: Theme.radiusM).strokeBorder(Theme.sep, lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: Theme.radiusM))
    }

    // MARK: - 路径与命令

    private func pathsSection(_ detail: ProcessDetail) -> some View {
        section(title: "路径与命令") {
            pathRow(label: "工作目录", evidence: detail.cwd, copyLabel: "工作目录")
            pathRow(label: "可执行文件", evidence: detail.executable, copyLabel: "可执行路径")
            if let command = detail.command?.joined(separator: " "), !command.isEmpty {
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Text("启动命令")
                        .font(.system(size: 11.5))
                        .foregroundStyle(Theme.text2)
                        .frame(width: 64, alignment: .leading)
                    Text(command)
                        .font(.system(size: 12, design: .monospaced))
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .help(command)
                    copyMini(command, label: "启动命令")
                }
            }
        }
    }

    private func pathRow(label: String, evidence: PathEvidence, copyLabel: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(label)
                .font(.system(size: 11.5))
                .foregroundStyle(Theme.text2)
                .frame(width: 64, alignment: .leading)
            switch evidence.state {
            case .available:
                if let path = evidence.path {
                    Text(ProcessContextReader.abbreviateHome(path))
                        .font(.system(size: 12))
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .help(path)
                    copyMini(path, label: copyLabel)
                }
            case .restricted:
                StatusBadge(kind: .warn, label: "权限受限")
                Spacer()
            case .unavailable:
                Text("不可用").font(.system(size: 12)).foregroundStyle(Theme.text3)
                Spacer()
            }
        }
    }

    private func copyMini(_ text: String, label: String) -> some View {
        Button {
            model.copyText(text, label: label)
        } label: {
            Text("复制")
                .font(.system(size: 10.5))
                .foregroundStyle(Theme.text3)
                .padding(.horizontal, 5)
                .padding(.vertical, 1)
        }
        .buttonStyle(.plain)
        .help("复制到剪贴板")
    }

    // MARK: - 关联端口

    @ViewBuilder
    private var portsSection: some View {
        if let key = model.selectedKey {
            let endpoints = model.endpoints(for: key)
            section(title: "关联端口（\(endpoints.count)）") {
                if endpoints.isEmpty {
                    Text("无监听端口")
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.text3)
                } else {
                    FlowLayout(spacing: 5) {
                        ForEach(endpoints) { endpoint in
                            Button {
                                model.investigate(port: endpoint.localPort)
                            } label: {
                                Text("\(endpoint.localAddress):\(endpoint.localPort) · \(endpoint.protocolKind.rawValue.uppercased())")
                                    .font(.system(size: 11))
                                    .monospacedDigit()
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 2)
                                    .background(Theme.inset)
                                    .overlay(Capsule().strokeBorder(Theme.sep, lineWidth: 1))
                                    .clipShape(Capsule())
                            }
                            .buttonStyle(.plain)
                            .help("跳转到 Ports 页查看")
                        }
                    }
                    Button {
                        model.scopePorts(to: key)
                    } label: {
                        Text("查看全部 \(endpoints.count) 个端口")
                            .font(.system(size: 12))
                            .foregroundStyle(Theme.accent)
                    }
                    .buttonStyle(.plain)
                    .help("在 Ports 页按该进程过滤")
                }
            }
        }
    }

    // MARK: - 操作

    private var actionsSection: some View {
        section(title: "操作") {
            actionButton("复制进程信息", action: model.copyReport)
            actionButton("在 Finder 中显示", action: model.revealInFinder)
            actionButton("在终端中打开工作目录", action: model.openTerminal)
        }
    }

    private func actionButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 12))
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Theme.raised)
                .overlay(RoundedRectangle(cornerRadius: Theme.radiusS).strokeBorder(Theme.sepStrong, lineWidth: 1))
                .clipShape(RoundedRectangle(cornerRadius: Theme.radiusS))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - 构件

    private func section<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Theme.text2)
                .textCase(.uppercase)
                .tracking(0.5)
            content()
        }
        .padding(.top, 10)
        .overlay(alignment: .top) { Theme.sep.frame(height: 1) }
    }

    private func kvRow<Content: View>(_ label: String, @ViewBuilder content: () -> Content) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(label)
                .font(.system(size: 11.5))
                .foregroundStyle(Theme.text2)
                .frame(width: 64, alignment: .leading)
            content()
                .font(.system(size: 12))
            Spacer(minLength: 0)
        }
    }

    private func note(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 11))
            .foregroundStyle(Theme.text2)
            .lineSpacing(2)
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.inset)
            .clipShape(RoundedRectangle(cornerRadius: 6))
    }
}

/// 简易流式布局（端口 chips 换行）。
private struct FlowLayout: Layout {
    var spacing: CGFloat = 5

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? 0
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > width, x > 0 {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
        return CGSize(width: width, height: y + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX
        var y = bounds.minY
        var rowHeight: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > bounds.maxX, x > bounds.minX {
                x = bounds.minX
                y += rowHeight + spacing
                rowHeight = 0
            }
            subview.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}
