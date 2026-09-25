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

    /// 启动序列状态机：动画渲染与数据采集/视图渲染严格分离——
    /// 采集在 onAppear 即开始（后台线程，与动画无依赖）；
    /// brand 阶段只渲染动画层，内容视图不挂载（首轮数百行渲染不与动画同帧）；
    /// 淡出时内容才挂载并错峰入场。
    private enum LaunchPhase { case brand, content }

    /// 品牌启动时刻：仅首次运行出现（约 2.5s），之后永不出现（delight 预算只花一次）。
    /// 从第一帧起全不透明覆盖内容，退出时内容入场接手。
    @AppStorage("pm.didLaunchBrand") private var didLaunchBrand = false
    @State private var phase: LaunchPhase

    init(model: MonitorViewModel, showsBrandLaunch: Bool = true) {
        _model = Bindable(wrappedValue: model)
        self.showsBrandLaunch = showsBrandLaunch
        // 首帧即覆盖：在 onAppear 之前置位，杜绝内容闪帧
        let shouldShow = LaunchLogic.shouldShowBrandLaunch(
            showsBrandLaunch: showsBrandLaunch,
            didLaunchBrand: UserDefaults.standard.bool(forKey: "pm.didLaunchBrand"),
        )
        _phase = State(initialValue: shouldShow ? .brand : .content)
    }

    var body: some View {
        GeometryReader { proxy in
            let compact = proxy.size.width < 880
            VStack(spacing: 0) {
                // 品牌动画期间不挂载内容：首轮数据渲染（数百行表格）若与动画
                // 同帧提交会卡顿；数据在后台照常采集，品牌淡出后内容再上屏
                if phase == .content {
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
                if phase == .brand {
                    didLaunchBrand = true
                    // 退场 = max(阶段驻留 2.6s, 数据就绪)：就绪文案至少可读 0.6s；
                    // 数据晚到时品牌层停留等待，进度条持续反馈；6s 兜底防止异常卡死
                    Task {
                        try? await Task.sleep(nanoseconds: 2_600_000_000)
                        let deadline = Date().addingTimeInterval(6)
                        while (model.monitor.processes == nil || model.monitor.sockets == nil), Date() < deadline {
                            try? await Task.sleep(nanoseconds: 100_000_000)
                        }
                        await MainActor.run {
                            phase = .content
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
        // 品牌层挂在 GeometryReader（恒为全窗口尺寸）上，而不是 VStack——
        // brand 阶段内容不挂载，VStack 尺寸塌缩为零会把 overlay 挤到角落
        .overlay {
            if phase == .brand {
                BrandLaunchView(model: model)
                    .transition(brandTransition)
            }
        }
        .animation(.easeOut(duration: 0.3), value: phase)
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

/// 品牌首启时刻：雷达扫描微叙事——环描绘 → 扫描 → 端口点弹出 → 名称落定 →
/// 收束编排（端口点汇聚入核、脉冲 + 涟漪扩散、名称先行淡出、背景最后退场）。
/// 首启限定（delight 预算只花一次）：弹簧回弹只用于端口点的 playful 弹出。
/// reduced-motion：去掉扫描与弹出，保留静态环 + 淡入淡出。
private struct BrandLaunchView: View {
    @Bindable var model: MonitorViewModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var ring: CGFloat = 0
    @State private var sweep = false
    @State private var sweepHidden = false // 扇面在转完前淡出，绝不硬停在半空
    @State private var coreShown = false
    @State private var dotCount = 0
    @State private var nameShown = false
    /// 收束阶段：端口点向中心汇聚、核心脉冲、涟漪扩散。
    @State private var finale = false
    @State private var ripple = false
    /// 展示阶段（0 读清单 / 1 扫端口 / 2 就绪）：推进规则 = max(最短驻留, 真实进度)，
    /// 慢机器等数据（诚实），快机器压节奏（可读）。
    @State private var shownStage = 0

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
                    .opacity(finale ? 0 : 1)
                // 收束涟漪：一圈声纳波向外扩散后消失
                Circle()
                    .strokeBorder(Theme.accent.opacity(0.4), lineWidth: 2)
                    .scaleEffect(ripple ? 1.6 : 0.9)
                    .opacity(ripple ? 0 : (finale ? 0.6 : 0))
                if !reduceMotion {
                    SweepWedge()
                        .fill(AngularGradient(
                            colors: [Theme.accent.opacity(0.5), Theme.accent.opacity(0)],
                            center: .center,
                            startAngle: .degrees(0),
                            endAngle: .degrees(60),
                        ))
                        .rotationEffect(.degrees(sweep ? 720 : 0)) // 两圈
                        .opacity(sweepHidden || finale ? 0 : 1)
                }
                Circle() // 中心核：收束时脉冲放大，像把端口点吸收进来
                    .fill(Theme.accent)
                    .frame(width: 16, height: 16)
                    .scaleEffect(finale ? 1.3 : (coreShown ? 1 : 0.5))
                    .opacity(coreShown ? 1 : 0)
                ForEach(Array(portDots.enumerated()), id: \.offset) { index, dot in
                    Circle()
                        .fill(dot.color)
                        .frame(width: 9, height: 9)
                        .scaleEffect(dotCount > index ? 1 : 0.3)
                        .opacity(finale ? 0 : (dotCount > index ? 1 : 0))
                        .offset(
                            x: finale ? 0 : cos(dot.angle * .pi / 180) * 34,
                            y: finale ? 0 : sin(dot.angle * .pi / 180) * 34,
                        )
                }
            }
            .frame(width: 76, height: 76)
            Text("PortMaster")
                .font(.system(size: 22, weight: .bold))
                .opacity(finale ? 0 : (nameShown ? 1 : 0))
                .offset(y: nameShown ? 0 : 5)

            // 吃豆人加载器：诚实的 indeterminate + playful（替代原进度条——
            // 与雷达动画同为加载信号会重复，且两阶段的"精确进度"名不副实）
            VStack(spacing: 6) {
                PacmanLoader()
                Text(bootStatus)
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.text3)
                    .contentTransition(.numericText())
            }
            .padding(.top, 6)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.window)
        .onAppear {
            startSequence()
            startStageTicker()
        }
    }

    private var bootStatus: String {
        switch shownStage {
        case 2:
            let processes = model.monitor.processes?.entries.count ?? 0
            let ports = model.monitor.sockets?.sockets.count ?? 0
            return "已就绪 · \(processes) 个进程，\(ports) 个端口"
        case 1:
            return "正在扫描本地端口…"
        default:
            return "正在读取进程清单…"
        }
    }

    /// 阶段推进器：真实进度与最短驻留（每段 1s）取较大者。
    private func startStageTicker() {
        let t0 = Date()
        Task {
            while shownStage < 2, !Task.isCancelled {
                let elapsed = Date().timeIntervalSince(t0)
                if model.bootProgress >= 1, elapsed >= 2.0 {
                    shownStage = 2
                } else if model.bootProgress >= 0.6, elapsed >= 1.0, shownStage == 0 {
                    shownStage = 1
                }
                try? await Task.sleep(nanoseconds: 50_000_000)
            }
        }
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
        // 加长版时间轴：每一拍都看得清，全程仅 GPU 属性
        withAnimation(.easeOut(duration: 0.6)) { ring = 1 }
        withAnimation(.linear(duration: 1.2).delay(0.15)) { sweep = true } // 雷达匀速扫两圈
        withAnimation(.spring(duration: 0.35, bounce: 0.25).delay(0.3)) { coreShown = true }
        for index in portDots.indices {
            withAnimation(.spring(duration: 0.35, bounce: 0.25).delay(0.55 + Double(index) * 0.12)) {
                dotCount = max(dotCount, index + 1) // 端口点错峰弹出（120ms stagger）
            }
        }
        withAnimation(.easeOut(duration: 0.4).delay(0.9)) { nameShown = true }
        // 扇面在转完前 0.3s 开始淡出：旋转元素骤停在半空 = 冻结感
        withAnimation(.easeOut(duration: 0.3).delay(1.05)) { sweepHidden = true }

        // 收束编排（名称落定后立即接手，不留静帧窗口）：
        // 1.45s 端口点汇聚入核（on-screen 移动用 ease-in-out），核心脉冲，名称先行淡出
        withAnimation(.easeInOut(duration: 0.45).delay(1.45)) { finale = true }
        withAnimation(.easeOut(duration: 0.55).delay(1.55)) { ripple = true } // 涟漪扩散
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

/// 吃豆人加载器：嘴部 280ms 往复开合，三颗豆子循环被吃掉。
/// 全部 transform/opacity（GPU）；reduced-motion 静态呈现。
private struct PacmanLoader: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var mouthOpen = false
    @State private var travel = false

    var body: some View {
        HStack(spacing: 2) {
            PacmanShape(openFraction: mouthOpen ? 1 : 0.12)
                .fill(Theme.accent)
                .frame(width: 22, height: 22)
            ZStack {
                ForEach(0..<3, id: \.self) { index in
                    Circle()
                        .fill(Theme.accent.opacity(0.75))
                        .frame(width: 5, height: 5)
                        .offset(x: travel ? 0 : 36)
                        .opacity(travel ? 0.2 : 1) // 到嘴边被吃掉
                        .animation(
                            .linear(duration: 1.1).repeatForever(autoreverses: false).delay(Double(index) * 0.37),
                            value: travel,
                        )
                }
            }
            .frame(width: 42, height: 22)
            .clipped()
        }
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.easeInOut(duration: 0.28).repeatForever(autoreverses: true)) {
                mouthOpen = true
            }
            travel = true
        }
    }
}

/// 吃豆人形状：圆缺一个朝向右侧（豆子方向）的楔形嘴。
struct PacmanShape: Shape {
    var openFraction: CGFloat // 0 闭合，1 全开（45°）

    var animatableData: CGFloat {
        get { openFraction }
        set { openFraction = newValue }
    }

    func path(in rect: CGRect) -> Path {
        let half = Double(openFraction) * .pi / 4
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let radius = min(rect.width, rect.height) / 2
        var path = Path()
        path.move(to: center)
        path.addArc(
            center: center,
            radius: radius,
            startAngle: .radians(half),
            endAngle: .radians(2 * .pi - half),
            clockwise: false, // 大弧经过左侧，缺口（嘴）留在右侧豆子方向
        )
        path.closeSubpath()
        return path
    }
}
