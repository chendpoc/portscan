import SwiftUI

/// 原型风格搜索框：放大镜 + 圆角内陷底。
struct SearchField: View {
    let placeholder: String
    @Binding var text: String

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 11))
                .foregroundStyle(Theme.text3)
            TextField(placeholder, text: $text)
                .textFieldStyle(.plain)
                .font(.system(size: 12.5))
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .frame(width: 220)
        .background(Theme.inset)
        .clipShape(RoundedRectangle(cornerRadius: 7))
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
