import AppKit
import SwiftUI

extension Notification.Name {
    static let focusPortSearch = Notification.Name("pm.focusPortSearch")
}

/// 三栏布局：侧栏导航 + 主页面 + Inspector（按需打开）。
/// <880px 进入紧凑模式：侧栏收窄为图标，Inspector 覆盖主区并提供返回。
struct ContentView: View {
    @Bindable var model: MonitorViewModel
    /// 测试/渲染诊断时关闭品牌首启层，避免污染真实用户的 UserDefaults。
    var showsBrandLaunch = true
    @AppStorage("pm.theme") private var theme = "system"
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @FocusState private var portSearchFocused: Bool

    private var inspectorOpen: Bool { model.selectedKey != nil }

    /// 启动动画只播一次（rare 档）：淡入 + 5px 上浮，chrome→内容→底栏错峰 50ms。
    @State private var launched = false

    /// 品牌启动时刻：仅首次运行出现（约 1.45s），之后永不出现（delight 预算只花一次）。
    /// 从第一帧起全不透明覆盖内容，退出时内容入场接手。
    @AppStorage("pm.didLaunchBrand") private var didLaunchBrand = false
    @State private var brandVisible: Bool

    init(model: MonitorViewModel, showsBrandLaunch: Bool = true) {
        _model = Bindable(wrappedValue: model)
        self.showsBrandLaunch = showsBrandLaunch
        // 首帧即覆盖：在 onAppear 之前置位，杜绝内容闪帧
        let shouldShow = showsBrandLaunch && !UserDefaults.standard.bool(forKey: "pm.didLaunchBrand")
        _brandVisible = State(initialValue: shouldShow)
    }

    var body: some View {
        GeometryReader { proxy in
            let compact = proxy.size.width < 880
            VStack(spacing: 0) {
                TitleBarView(model: model, searchFocus: $portSearchFocused)
                    .launchAppear(launched, delay: 0, reduceMotion: reduceMotion)
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
                .launchAppear(launched, delay: 0.05, reduceMotion: reduceMotion)
                StatusFooterView(model: model)
                    .launchAppear(launched, delay: 0.09, reduceMotion: reduceMotion)
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
            .overlay {
                if brandVisible {
                    BrandLaunchView()
                        .transition(brandTransition)
                }
            }
            .animation(.easeOut(duration: 0.3), value: brandVisible)
            .onAppear {
                applyAppearance()
                model.start()
                if brandVisible {
                    didLaunchBrand = true
                    // 扫描叙事约 1.05s 完成，停留一拍后品牌层 300ms 淡出；
                    // 内容错峰入场在同一刻开始，淡出与接手无缝交叠
                    Task {
                        try? await Task.sleep(nanoseconds: 1_150_000_000)
                        await MainActor.run {
                            brandVisible = false
                            launched = true
                        }
                    }
                } else {
                    launched = true
                }
            }
            .onChange(of: theme) { _, _ in applyAppearance() }
            .onReceive(NotificationCenter.default.publisher(for: .focusPortSearch)) { _ in
                portSearchFocused = true
            }
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

    /// 品牌层仅淡出（首帧即存在，无插入过渡）；reduced-motion 纯淡入淡出。
    private var brandTransition: AnyTransition {
        reduceMotion
            ? .opacity
            : .scale(scale: 0.98).combined(with: .opacity)
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

private extension View {
    /// 启动入场：淡入 + 5px 上浮，250ms ease-out（入场的唯一合法曲线），按区域错峰。
    /// reduced-motion：去掉位移，只保留淡入。
    func launchAppear(_ launched: Bool, delay: Double, reduceMotion: Bool) -> some View {
        opacity(launched ? 1 : 0)
            .offset(y: launched || reduceMotion ? 0 : 5)
            .animation(.easeOut(duration: 0.25).delay(delay), value: launched)
    }
}

/// 品牌首启时刻：雷达扫描微叙事——环描绘 → 扫描 → 端口点弹出 → 名称落定。
/// 首启限定（delight 预算只花一次）：弹簧回弹只用于端口点的 playful 弹出。
/// reduced-motion：去掉扫描与弹出，保留静态环 + 淡入。
private struct BrandLaunchView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var ring: CGFloat = 0
    @State private var sweep = false
    @State private var coreShown = false
    @State private var dotCount = 0
    @State private var nameShown = false

    /// 环上端口点：角度（度，3 点钟为 0，顺时针）+ 语义色
    private let portDots: [(angle: Double, color: Color)] = [
        (-50, Theme.ok), (15, Theme.accent), (95, Theme.warn), (185, Theme.mem),
    ]

    var body: some View {
        VStack(spacing: 18) {
            ZStack {
                Circle() // 底环
                    .strokeBorder(Theme.accent.opacity(0.15), lineWidth: 4)
                Circle() // 描绘环
                    .trim(from: 0, to: ring)
                    .stroke(Theme.accent, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                if !reduceMotion {
                    SweepWedge()
                        .fill(AngularGradient(
                            colors: [Theme.accent.opacity(0.5), Theme.accent.opacity(0)],
                            center: .center,
                            startAngle: .degrees(0),
                            endAngle: .degrees(60),
                        ))
                        .rotationEffect(.degrees(sweep ? 360 : 0))
                }
                Circle() // 中心核
                    .fill(Theme.accent)
                    .frame(width: 16, height: 16)
                    .scaleEffect(coreShown ? 1 : 0.5)
                    .opacity(coreShown ? 1 : 0)
                ForEach(Array(portDots.enumerated()), id: \.offset) { index, dot in
                    Circle()
                        .fill(dot.color)
                        .frame(width: 9, height: 9)
                        .scaleEffect(dotCount > index ? 1 : 0.3)
                        .opacity(dotCount > index ? 1 : 0)
                        .offset(
                            x: cos(dot.angle * .pi / 180) * 34,
                            y: sin(dot.angle * .pi / 180) * 34,
                        )
                }
            }
            .frame(width: 76, height: 76)
            Text("PortMaster")
                .font(.system(size: 22, weight: .bold))
                .opacity(nameShown ? 1 : 0)
                .offset(y: nameShown ? 0 : 5)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.window)
        .onAppear { startSequence() }
    }

    private func startSequence() {
        if reduceMotion {
            withAnimation(.easeOut(duration: 0.3)) { ring = 1; coreShown = true }
            withAnimation(.easeOut(duration: 0.3).delay(0.1)) {
                dotCount = portDots.count
                nameShown = true
            }
            return
        }
        withAnimation(.easeOut(duration: 0.5)) { ring = 1 }
        withAnimation(.linear(duration: 0.75).delay(0.1)) { sweep = true } // 匀速扫描一圈
        withAnimation(.spring(duration: 0.35, bounce: 0.25).delay(0.15)) { coreShown = true }
        for index in portDots.indices {
            withAnimation(.spring(duration: 0.35, bounce: 0.25).delay(0.35 + Double(index) * 0.1)) {
                dotCount = max(dotCount, index + 1) // 端口点错峰弹出（100ms stagger）
            }
        }
        withAnimation(.easeOut(duration: 0.4).delay(0.6)) { nameShown = true }
    }
}

/// 雷达扫描扇面：60° 楔形，angular gradient 沿旋转方向拖尾。
private struct SweepWedge: Shape {
    func path(in rect: CGRect) -> Path {
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let radius = min(rect.width, rect.height) / 2 - 8
        var path = Path()
        path.move(to: center)
        path.addArc(center: center, radius: radius, startAngle: .degrees(0), endAngle: .degrees(60), clockwise: false)
        path.closeSubpath()
        return path
    }
}
