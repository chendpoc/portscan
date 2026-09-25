import SwiftUI

/// 自定义标题栏（hiddenTitleBar 窗口样式下代替原生标题栏）。
struct TitleBarView: View {
    @Bindable var model: MonitorViewModel
    @AppStorage("pm.theme") private var theme = "system"

    var body: some View {
        HStack(spacing: 10) {
            Text("PortMaster")
                .font(.system(size: 13, weight: .semibold))
            Spacer()
            Button {
                var settings = model.settings
                settings.paused.toggle()
                model.updateSettings(settings)
            } label: {
                HStack(spacing: 6) {
                    StatusDot(kind: model.settings.paused ? .warn : .ok)
                    Text(model.settings.paused ? "恢复" : "暂停")
                }
            }
            .buttonStyle(TitleBarButtonStyle())
            .help("暂停后停止新增采样，保留已有图表与表格；恢复后保留时间缺口")

            Button {
                theme = theme == "dark" ? "light" : "dark"
            } label: {
                Label("主题", systemImage: "circle.lefthalf.filled")
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
        .padding(.leading, 78) // 避开红绿灯按钮
        .padding(.trailing, 12)
        .frame(height: 44)
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
