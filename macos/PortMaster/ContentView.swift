import AppKit
import SwiftUI

/// 三栏布局：侧栏导航 + 主页面 + Inspector（按需打开）。
/// <880px 进入紧凑模式：侧栏收窄为图标，Inspector 覆盖主区并提供返回。
struct ContentView: View {
    @Bindable var model: MonitorViewModel
    @AppStorage("pm.theme") private var theme = "system"
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var inspectorOpen: Bool { model.selectedKey != nil }

    var body: some View {
        GeometryReader { proxy in
            let compact = proxy.size.width < 880
            VStack(spacing: 0) {
                TitleBarView(model: model)
                if let error = model.monitor.processError ?? model.monitor.socketError {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(Theme.err)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(8)
                        .background(Theme.err.opacity(0.08))
                }
                HStack(spacing: 0) {
                    // 侧栏优先保全：主区空间不足时绝不动侧栏宽度
                    SidebarView(model: model, compact: compact)
                        .layoutPriority(1)
                    if !(compact && inspectorOpen) {
                        mainPage(compact: compact)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .clipped() // 主区过窄时裁剪溢出内容，不挤压侧栏
                    }
                    if inspectorOpen {
                        InspectorPanelView(model: model, compact: compact, onBack: model.closeInspector)
                            .frame(width: compact ? nil : 300)
                            .frame(maxWidth: compact ? .infinity : nil)
                            .transition(inspectorTransition)
                    }
                }
                .animation(.easeOut(duration: 0.2), value: inspectorOpen)
                StatusFooterView(model: model)
            }
            .background(Theme.content)
            .overlay(alignment: .bottom) {
                if let toast = model.toast {
                    ToastView(text: toast.text)
                        .padding(.bottom, 36)
                        .transition(toastTransition)
                }
            }
            .animation(.easeOut(duration: 0.2), value: model.toast)
            .onAppear {
                applyAppearance()
                model.start()
            }
            .onChange(of: theme) { _, _ in applyAppearance() }
            .onDisappear { model.stop() }
        }
        // 最小尺寸必须加在 GeometryReader 外层才会传导为窗口最小尺寸
        //（GeometryReader 贪婪填充，不传导子视图约束）。与原型一致：700×480。
        .frame(minWidth: 700, minHeight: 480)
        .ignoresSafeArea(.container, edges: .top)
        .preferredColorScheme(colorScheme)
    }

    /// 同步 NSApp 外观，让窗口框架（红绿灯区域）跟随主题开关。
    private func applyAppearance() {
        NSApp.appearance = switch theme {
        case "light": NSAppearance(named: .aqua)
        case "dark": NSAppearance(named: .darkAqua)
        default: nil
        }
    }

    @ViewBuilder
    private func mainPage(compact: Bool) -> some View {
        switch model.page {
        case .performance:
            PerformanceView(model: model, compact: compact)
        case .processes:
            ProcessTableView(model: model)
        case .ports:
            PortsTableView(model: model)
        }
    }

    /// Inspector：偶尔触发 → 标准动画。reduced-motion 降级为纯淡入淡出。
    private var inspectorTransition: AnyTransition {
        reduceMotion
            ? .opacity
            : .move(edge: .trailing).combined(with: .opacity)
    }

    /// Toast：从底部进出，路径对称。
    private var toastTransition: AnyTransition {
        reduceMotion
            ? .opacity
            : .move(edge: .bottom).combined(with: .opacity)
    }

    private var colorScheme: ColorScheme? {
        switch theme {
        case "light": .light
        case "dark": .dark
        default: nil
        }
    }
}

private struct ToastView: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 12.5))
            .foregroundStyle(Color(nsColor: .windowBackgroundColor).opacity(0.95))
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(Color(nsColor: .labelColor).opacity(0.92))
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .shadow(color: .black.opacity(0.35), radius: 12, y: 8)
    }
}
