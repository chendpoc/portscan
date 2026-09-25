import SwiftUI

/// 自定义标题栏（hiddenTitleBar 窗口样式下代替原生标题栏）。
struct TitleBarView: View {
    @Bindable var model: MonitorViewModel
    var searchFocus: FocusState<Bool>.Binding
    @AppStorage("pm.theme") private var theme = "system"

    /// 标题栏是端口搜索入口：输入即跳转到 Ports 页（与主区搜索共享 query）。
    private var portQuery: Binding<String> {
        Binding(
            get: { model.query },
            set: { value in
                model.query = value
                if !value.isEmpty {
                    model.page = .ports
                    model.ports.resetFiltersForPortSearch()
                }
            },
        )
    }

    var body: some View {
        HStack(spacing: 10) {
            Text("PortMaster")
                .font(.system(size: 13, weight: .semibold))
            Spacer()
//            SearchField(placeholder: "端口搜索 ⌘K", text: portQuery, width: 160, focus: searchFocus)
            Button {
                var settings = model.settings
                settings.paused.toggle()
                model.updateSettings(settings)
            } label: {
                // 图标即状态：运行中显示暂停键（原色），已暂停显示播放键（警示色）
                Image(systemName: model.settings.paused ? "play.fill" : "pause.fill")
                    .foregroundStyle(model.settings.paused ? Theme.warn : Color.primary)
            }
            .buttonStyle(TitleBarButtonStyle())
            .help(model.settings.paused ? "恢复采样（保留时间缺口，不回填）" : "暂停采样（保留已有图表与表格）")

            Button {
                theme = theme == "dark" ? "light" : "dark"
            }
            label: {
                Image(systemName: "circle.lefthalf.filled")
            }
            .buttonStyle(TitleBarButtonStyle())
            .help("切换浅色 / 深色主题")

            Button {
                model.refreshNow()
            } label: {
                Image(systemName: "arrow.clockwise")
            }
            .buttonStyle(TitleBarButtonStyle())
            .disabled(model.refreshing)
            .help("立即刷新进程与端口数据")
        }
        // 红绿灯按钮 14×14，纵向中心固定在 y=16（系统决定，不随标题栏高度变化）。
        // 内容带高 26、顶部留 3，使标题/按钮与红绿灯垂直对齐。
        .padding(.leading, 78) // 避开红绿灯按钮（x: 9→69）
        .padding(.trailing, 12)
        .padding(.top, 3)
        .frame(height: 44, alignment: .top)
        .background(WindowDragView())
        .background(Theme.sidebar)
        .overlay(alignment: .bottom) { Theme.sep.frame(height: 1) }
    }
}

struct TitleBarButtonStyle: ButtonStyle {
    @State private var hovering = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12))
            .foregroundStyle(configuration.isPressed ? Theme.accent : Color.primary)
            .padding(.horizontal, 10)
            .frame(height: 26)
            .background(hovering || configuration.isPressed ? Theme.hover : .clear)
            .clipShape(RoundedRectangle(cornerRadius: Theme.radiusS))
            .onHover { hovering = $0 }
            .animation(.easeOut(duration: 0.12), value: hovering)
    }
}

/// 自定义标题栏区域拖动窗口。
struct WindowDragView: NSViewRepresentable {
    func makeNSView(context: Context) -> DragNSView { DragNSView() }
    func updateNSView(_ nsView: DragNSView, context: Context) {}

    final class DragNSView: NSView {
        override func mouseDown(with event: NSEvent) {
            window?.performDrag(with: event)
        }
        override var acceptsFirstResponder: Bool { false }
    }
}
