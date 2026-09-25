import SwiftUI

/// 原型视觉令牌：中性色为主，少量语义色；等宽数字；4px 间距体系。
enum Theme {
    static let accent = Color(red: 10 / 255, green: 132 / 255, blue: 255 / 255)
    static let cpu = accent
    static let mem = Color(red: 48 / 255, green: 209 / 255, blue: 88 / 255)
    static let netDown = Color(red: 48 / 255, green: 209 / 255, blue: 88 / 255)
    static let netUp = accent
    static let diskRead = Color(red: 255 / 255, green: 159 / 255, blue: 10 / 255)
    static let diskWrite = Color(red: 191 / 255, green: 90 / 255, blue: 242 / 255)
    static let ok = Color(red: 40 / 255, green: 200 / 255, blue: 64 / 255)
    static let warn = Color(red: 255 / 255, green: 159 / 255, blue: 10 / 255)
    static let err = Color(red: 255 / 255, green: 69 / 255, blue: 58 / 255)

    /// 显式双色动态色（原型取值）。不用 NSColor 语义色——underPageBackgroundColor
    /// 在浅色模式下是深灰，曾被误用为侧栏底色。
    private static func dynamic(light: UInt32, dark: UInt32) -> Color {
        func ns(_ hex: UInt32) -> NSColor {
            NSColor(
                srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
                green: CGFloat((hex >> 8) & 0xFF) / 255,
                blue: CGFloat(hex & 0xFF) / 255,
                alpha: 1,
            )
        }
        return Color(nsColor: NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? ns(dark) : ns(light)
        })
    }

    /// 侧栏 / 标题栏 / 状态栏：浅 #F6F6F8，深 #262628。
    static let sidebar = dynamic(light: 0xF6F6F8, dark: 0x262628)
    /// 卡片与表头：浅 #FFFFFF，深 #2C2C2E。
    static let raised = dynamic(light: 0xFFFFFF, dark: 0x2C2C2E)
    /// 主内容区：浅 #FFFFFF，深 #1E1E20。
    static let content = dynamic(light: 0xFFFFFF, dark: 0x1E1E20)
    /// 窗口底色：浅 #ECECEE，深 #262628。
    static let window = dynamic(light: 0xECECEE, dark: 0x262628)

    static let hover = Color.primary.opacity(0.05)
    static let selected = accent.opacity(0.15)
    static let inset = Color.primary.opacity(0.04)
    static let sep = Color.primary.opacity(0.10)
    static let sepStrong = Color.primary.opacity(0.18)
    static let text2 = Color.secondary
    static let text3 = Color(nsColor: .tertiaryLabelColor)
    static let grid = Color.primary.opacity(0.08)

    static let radiusS: CGFloat = 5
    static let radiusM: CGFloat = 8

    static let mono = Font.system(.caption, design: .monospaced)
}

// MARK: - 格式化（与原型一致）

enum Format {
    /// 原型 fmtMB：≥1GB 显示 "x.x GB"，否则整数 MB。
    static func bytes(_ value: UInt64) -> String {
        let mb = Double(value) / 1_048_576
        if mb >= 1024 { return String(format: "%.1f GB", mb / 1024) }
        return "\(Int(mb.rounded())) MB"
    }

    static func percent(_ value: Double) -> String {
        String(format: "%.1f%%", value)
    }

    /// 原型 fmtRate：≥1MB/s 一位小数，≥1KB/s 整数 KB/s，否则 B/s。
    static func rate(_ bytesPerSec: Double) -> String {
        if bytesPerSec >= 1_048_576 { return String(format: "%.1f MB/s", bytesPerSec / 1_048_576) }
        if bytesPerSec >= 1024 { return String(format: "%.0f KB/s", bytesPerSec / 1024) }
        return "\(Int(bytesPerSec.rounded())) B/s"
    }

    /// top 风格累计 CPU 时间：≥1 小时 "H:MM:SS"，否则 "M:SS.t"。
    static func cpuTime(_ seconds: Double) -> String {
        let total = Int(seconds)
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let secs = total % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, secs)
        }
        let tenths = Int((seconds - Double(total)) * 10)
        return String(format: "%d:%02d.%d", minutes, secs, tenths)
    }

    /// HH:mm:ss
    static func time(_ date: Date) -> String {
        timeFormatter.string(from: date)
    }

    /// HH:mm
    static func timeShort(_ date: Date) -> String {
        timeShortFormatter.string(from: date)
    }

    static func dateTime(_ date: Date) -> String {
        dateTimeFormatter.string(from: date)
    }

    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss"
        return f
    }()

    private static let timeShortFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        return f
    }()

    private static let dateTimeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy/M/d HH:mm:ss"
        return f
    }()
}

// MARK: - 状态点与徽标

enum StatusKind {
    case ok, warn, err, mut

    var color: Color {
        switch self {
        case .ok: Theme.ok
        case .warn: Theme.warn
        case .err: Theme.err
        case .mut: Theme.text3
        }
    }
}

struct StatusDot: View {
    let kind: StatusKind

    var body: some View {
        Circle()
            .fill(kind.color)
            .frame(width: 7, height: 7)
    }
}

struct StatusBadge: View {
    let kind: StatusKind
    let label: String

    var body: some View {
        HStack(spacing: 4) {
            StatusDot(kind: kind)
            Text(label)
        }
        .font(.system(size: 10.5, weight: .semibold))
        .foregroundStyle(kind.color)
        .padding(.horizontal, 7)
        .padding(.vertical, 1.5)
        .background(kind.color.opacity(0.1))
        .overlay(Capsule().strokeBorder(kind.color.opacity(0.4), lineWidth: 1))
        .clipShape(Capsule())
    }
}

/// 原型 phase-tag：小号边框标签（如「后续阶段」）。
struct PhaseTag: View {
    let label: String

    var body: some View {
        Text(label)
            .font(.system(size: 10, weight: .bold))
            .foregroundStyle(Theme.text3)
            .padding(.horizontal, 4)
            .overlay(
                RoundedRectangle(cornerRadius: 4)
                    .strokeBorder(Theme.sepStrong, lineWidth: 1),
            )
    }
}
