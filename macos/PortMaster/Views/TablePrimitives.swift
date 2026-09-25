import SwiftUI

/// 原型风格搜索框：放大镜 + 圆角内陷底。
struct SearchField: View {
    let placeholder: String
    @Binding var text: String
    var width: CGFloat = 220
    var focus: FocusState<Bool>.Binding?

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 11))
                .foregroundStyle(Theme.text3)
            field
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .frame(width: width)
        .background(Theme.inset)
        .clipShape(RoundedRectangle(cornerRadius: 7))
    }

    @ViewBuilder
    private var field: some View {
        if let focus {
            TextField(placeholder, text: $text)
                .textFieldStyle(.plain)
                .font(.system(size: 12.5))
                .focused(focus)
        } else {
            TextField(placeholder, text: $text)
                .textFieldStyle(.plain)
                .font(.system(size: 12.5))
        }
    }
}

/// 表头单元格：可排序列显示 ▲▼ 箭头。
struct HeaderCell: View {
    let title: String
    var help: String? = nil

    var body: some View {
        Text(title)
            .font(.system(size: 11.5, weight: .semibold))
            .foregroundStyle(Theme.text2)
            .lineLimit(1)
            .help(help ?? "")
    }
}

/// 行通用悬停/选中背景。
struct RowBackground: View {
    var selected: Bool
    var hovering: Bool

    var body: some View {
        if selected {
            Theme.selected
        } else if hovering {
            Theme.hover
        } else {
            Color.clear
        }
    }
}

/// 空态。
struct EmptyStateView: View {
    let title: String
    let hint: String

    var body: some View {
        VStack(spacing: 8) {
            Text(title)
                .font(.system(size: 14, weight: .semibold))
            Text(hint)
                .font(.system(size: 12))
                .foregroundStyle(Theme.text2)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 340)
                .lineSpacing(3)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(40)
    }
}

/// 首次加载骨架屏：预览表格结构（感知速度）+ 轻脉冲（活性信号）。
/// 脉冲为循环动画：仅在加载期间短暂出现；reduced-motion 下静态呈现。
struct SkeletonTableView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var pulse = false

    var body: some View {
        VStack(spacing: 0) {
            ForEach(0..<9, id: \.self) { SkeletonRow(seed: $0) }
            Spacer(minLength: 0)
        }
        .opacity(reduceMotion ? 0.5 : (pulse ? 0.85 : 0.45))
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.easeInOut(duration: 1.1).repeatForever(autoreverses: true)) {
                pulse = true
            }
        }
    }
}

private struct SkeletonRow: View {
    let seed: Int

    /// 伪随机但确定的宽度（按行号取模），避免每次重渲染闪烁。
    private var nameWidth: CGFloat { [120, 88, 148, 106, 96, 132][seed % 6] }

    var body: some View {
        HStack(spacing: 0) {
            bar(nameWidth).frame(maxWidth: .infinity, alignment: .leading)
            bar(34).frame(width: 64, alignment: .leading)
            bar(42).frame(width: 76, alignment: .leading)
            bar(48).frame(width: 84, alignment: .leading)
            bar(28).frame(width: 56, alignment: .leading)
            bar(52).frame(width: 90, alignment: .leading)
            bar(130).frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private func bar(_ width: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: 3)
            .fill(Color.primary.opacity(0.10))
            .frame(width: width, height: 10)
    }
}

/// 页头（标题 + 计数 + 搜索框）。
struct PageHeadView<Extra: View>: View {
    let title: String
    let count: String
    let placeholder: String
    @Binding var query: String
    @ViewBuilder var extra: Extra

    var body: some View {
        HStack(spacing: 12) {
            Text(title)
                .font(.system(size: 15, weight: .bold))
            Text(count)
                .font(.system(size: 12))
                .foregroundStyle(Theme.text2)
            Spacer()
            extra
            SearchField(placeholder: placeholder, text: $query)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .overlay(alignment: .bottom) { Theme.sep.frame(height: 1) }
    }
}

/// 表格页脚注释。
struct TableFootNote: View {
    let items: [String]

    var body: some View {
        HStack(spacing: 18) {
            ForEach(items, id: \.self) { item in
                Text(item)
            }
            Spacer()
        }
        .font(.system(size: 11))
        .foregroundStyle(Theme.text2)
        .padding(.horizontal, 14)
        .padding(.vertical, 7)
        .overlay(alignment: .top) { Theme.sep.frame(height: 1) }
    }
}
