import SwiftUI

/// Processes 页：搜索 + 吸顶表头表格（名称 / PID / CPU % / 内存 RSS / 工作目录）。
struct ProcessTableView: View {
    @Bindable var model: MonitorViewModel

    private let pidWidth: CGFloat = 64
    private let cpuWidth: CGFloat = 76
    private let rssWidth: CGFloat = 90

    var body: some View {
        VStack(spacing: 0) {
            PageHeadView(
                title: "Processes",
                count: "\(model.visibleProcesses.count) 个进程",
                placeholder: "搜索名称、PID、路径或端口",
                query: $model.query,
                extra: { EmptyView() },
            )
            if model.visibleProcesses.isEmpty {
                EmptyStateView(
                    title: "没有匹配的进程",
                    hint: "尝试更换关键词。可搜索进程名称、PID、可执行路径或本地端口号。",
                )
            } else {
                ScrollView {
                    LazyVStack(spacing: 0, pinnedViews: [.sectionHeaders]) {
                        Section(header: headerRow) {
                            ForEach(model.visibleProcesses) { entry in
                                row(entry)
                            }
                        }
                    }
                }
            }
        }
    }

    // MARK: - 表头

    private var headerRow: some View {
        HStack(spacing: 0) {
            sortableHeader("名称", sort: .name, ascendingDefault: true)
                .frame(maxWidth: .infinity, alignment: .leading)
            sortableHeader("PID", sort: .pid, ascendingDefault: true)
                .frame(width: pidWidth, alignment: .leading)
            sortableHeader("CPU % ⓘ", sort: .cpu, ascendingDefault: false,
                           help: "占整机总算力的百分比（全机合计 100%）")
                .frame(width: cpuWidth, alignment: .leading)
            sortableHeader("内存 (RSS)", sort: .memory, ascendingDefault: false,
                           help: "常驻内存；各进程 RSS 之和不等于系统已用内存")
                .frame(width: rssWidth, alignment: .leading)
            HeaderCell(title: "工作目录 / 上下文")
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .background(Theme.raised)
        .overlay(alignment: .bottom) { Theme.sepStrong.frame(height: 1) }
    }

    private func sortableHeader(
        _ title: String,
        sort: ProcessSort,
        ascendingDefault: Bool,
        help: String? = nil,
    ) -> some View {
        Button {
            if model.processSort == sort {
                model.sortDescending.toggle()
            } else {
                model.processSort = sort
                model.sortDescending = !ascendingDefault
            }
        } label: {
            HStack(spacing: 3) {
                HeaderCell(title: title, help: help)
                if model.processSort == sort {
                    Text(model.sortDescending ? "▼" : "▲")
                        .font(.system(size: 9))
                        .foregroundStyle(Theme.text2)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - 行

    private func row(_ entry: ProcessEntry) -> some View {
        let selected = model.selectedKey == entry.key
        return ProcessRow(
            entry: entry,
            selected: selected,
            pidWidth: pidWidth,
            cpuWidth: cpuWidth,
            rssWidth: rssWidth,
            onSelect: { model.selectProcess(entry) },
            onCopyPath: { path in model.copyText(path, label: "工作目录") },
        )
    }
}

private struct ProcessRow: View {
    let entry: ProcessEntry
    let selected: Bool
    let pidWidth: CGFloat
    let cpuWidth: CGFloat
    let rssWidth: CGFloat
    let onSelect: () -> Void
    let onCopyPath: (String) -> Void

    @State private var hovering = false

    private var restricted: Bool {
        entry.cwd.state == .restricted && entry.executable.state == .restricted
    }

    var body: some View {
        HStack(spacing: 0) {
            HStack(spacing: 5) {
                Text(entry.name)
                    .lineLimit(1)
                    .truncationMode(.tail)
                if restricted {
                    Text("（部分信息受限）")
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.text3)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Text(verbatim: "\(entry.key.pid)")
                .monospacedDigit()
                .frame(width: pidWidth, alignment: .leading)

            Text(entry.cpuPercent.map(Format.percent) ?? "采样…")
                .monospacedDigit()
                .frame(width: cpuWidth, alignment: .leading)

            Text(entry.rssBytes.map(Format.bytes) ?? "—")
                .monospacedDigit()
                .frame(width: rssWidth, alignment: .leading)

            cwdCell
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .font(.system(size: 12.5))
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(RowBackground(selected: selected, hovering: hovering))
        .overlay(alignment: .bottom) { Theme.sep.frame(height: 1) }
        .contentShape(Rectangle())
        .onTapGesture(perform: onSelect)
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.12), value: hovering)
    }

    @ViewBuilder
    private var cwdCell: some View {
        switch entry.cwd.state {
        case .restricted:
            StatusBadge(kind: .warn, label: "权限受限")
        case .unavailable:
            Text("不可用")
                .font(.system(size: 11.5))
                .foregroundStyle(Theme.text3)
        case .available:
            if let path = entry.cwd.path {
                Button {
                    onCopyPath(path)
                } label: {
                    Text(ProcessContextReader.abbreviateHome(path))
                        .font(.system(size: 11.5))
                        .foregroundStyle(Theme.text2)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                .buttonStyle(.plain)
                .help("\(path)（点击复制完整路径）")
            }
        }
    }
}
