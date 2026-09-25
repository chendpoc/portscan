import SwiftUI

/// Ports 页：搜索 + 表格（端口 / 协议 / 状态 / 本地地址 / 所属进程 / PID）。
struct PortsTableView: View {
    @Bindable var model: MonitorViewModel

    private var visible: [SocketEntry] {
        model.ports.visible(in: model.monitor, query: model.query)
    }

    private let portWidth: CGFloat = 64
    private let protoWidth: CGFloat = 52
    private let stateWidth: CGFloat = 96
    private let addrWidth: CGFloat = 140
    private let pidWidth: CGFloat = 64

    var body: some View {
        VStack(spacing: 0) {
            PageHeadView(
                title: "Ports",
                count: "\(visible.count) 个监听端口",
                placeholder: "搜索端口、进程或地址",
                query: $model.query,
                extra: { EmptyView() },
            )
            if model.ports.portScope != nil {
                scopeBanner
            }
            if isInitialLoading {
                SkeletonTableView()
                    .transition(.opacity)
            } else if visible.isEmpty {
                EmptyStateView(
                    title: "没有匹配的端口",
                    hint: "尝试更换关键词。可搜索端口号、进程名称或本地地址。",
                )
                .transition(.opacity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 0, pinnedViews: [.sectionHeaders]) {
                        Section(header: headerRow) {
                            ForEach(visible) { entry in
                                PortRow(
                                    entry: entry,
                                    portWidth: portWidth,
                                    protoWidth: protoWidth,
                                    stateWidth: stateWidth,
                                    addrWidth: addrWidth,
                                    pidWidth: pidWidth,
                                    onSelect: { model.selectPort(entry) },
                                )
                            }
                        }
                    }
                }
            }
            TableFootNote(items: [model.ports.filter == .listeners
                ? "仅展示监听（LISTEN）状态的本地端口 · 完全相同的绑定合并显示"
                : "展示全部套接字（含已建立连接） · 完全相同的绑定合并显示"])
        }
        .animation(.easeOut(duration: 0.2), value: isInitialLoading)
    }

    /// 从未成功加载且未报错 → 仍在首轮采集中（三态判定见 MonitorLogic）。
    private var isInitialLoading: Bool {
        MonitorLogic.isInitialLoading(
            snapshotLoaded: model.monitor.sockets != nil,
            error: model.monitor.socketError,
        )
    }

    private var headerRow: some View {
        HStack(spacing: 0) {
            HeaderCell(title: "端口").frame(width: portWidth, alignment: .leading)
            HeaderCell(title: "协议").frame(width: protoWidth, alignment: .leading)
            HeaderCell(title: "状态").frame(width: stateWidth, alignment: .leading)
            HeaderCell(title: "本地地址").frame(width: addrWidth, alignment: .leading)
            HeaderCell(title: "所属进程").frame(maxWidth: .infinity, alignment: .leading)
            HeaderCell(title: "PID").frame(width: pidWidth, alignment: .leading)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .background(Theme.raised)
        .overlay(alignment: .bottom) { Theme.sepStrong.frame(height: 1) }
    }

    /// 按进程过滤的作用域横幅（从 Inspector「查看全部端口」进入）。
    private var scopeBanner: some View {
        HStack(spacing: 8) {
            Image(systemName: "line.3.horizontal.decrease.circle.fill")
                .foregroundStyle(Theme.accent)
            Text("仅显示 \(model.ports.scopedProcessName(in: model.monitor) ?? "所选进程") 的端口")
                .font(.system(size: 12))
            Spacer()
            Button {
                model.ports.clearScope()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(Theme.text3)
            }
            .buttonStyle(.plain)
            .help("清除进程过滤")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 6)
        .background(Theme.selected)
        .overlay(alignment: .bottom) { Theme.sep.frame(height: 1) }
    }
}

private struct PortRow: View {
    let entry: SocketEntry
    let portWidth: CGFloat
    let protoWidth: CGFloat
    let stateWidth: CGFloat
    let addrWidth: CGFloat
    let pidWidth: CGFloat
    let onSelect: () -> Void

    @State private var hovering = false

    var body: some View {
        HStack(spacing: 0) {
            Text(verbatim: "\(entry.localPort)")
                .font(.system(size: 12.5, weight: .semibold))
                .monospacedDigit()
                .lineLimit(1)
                .frame(width: portWidth, alignment: .leading)
            Text(entry.protocolKind.rawValue.uppercased())
                .lineLimit(1)
                .frame(width: protoWidth, alignment: .leading)
            stateBadge
                .frame(width: stateWidth, alignment: .leading)
            Text(entry.localAddress)
                .monospacedDigit()
                .lineLimit(1)
                .truncationMode(.middle)
                .help(entry.localAddress)
                .frame(width: addrWidth, alignment: .leading)
            Text(entry.processName ?? "—")
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(maxWidth: .infinity, alignment: .leading)
            Text(entry.pid.map(String.init) ?? "—")
                .monospacedDigit()
                .lineLimit(1)
                .frame(width: pidWidth, alignment: .leading)
        }
        .font(.system(size: 12.5))
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(RowBackground(selected: false, hovering: hovering))
        .overlay(alignment: .bottom) { Theme.sep.frame(height: 1) }
        .contentShape(Rectangle())
        .onTapGesture(perform: onSelect)
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.12), value: hovering)
    }

    @ViewBuilder
    private var stateBadge: some View {
        if entry.protocolKind == .tcp, entry.state == .listen {
            StatusBadge(kind: .ok, label: "LISTEN")
        } else if entry.protocolKind == .udp, entry.state == .none {
            StatusBadge(kind: .mut, label: "UDP")
        } else {
            StatusBadge(kind: .mut, label: entry.state.rawValue.uppercased())
        }
    }
}
