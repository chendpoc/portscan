import SwiftUI

struct ChartPoint: Equatable {
    var t: Date
    var v: Double
}

struct ChartSeries: Identifiable {
    let id = UUID()
    var color: Color
    /// nil 样本 = 采集失败断点，不补零。
    var points: [ChartPoint?]
    var fill = false
    var width: CGFloat = 1.6
    var alpha: Double = 1
    var label: String = ""
    var format: (Double) -> String = { String(format: "%.1f", $0) }
}

/// 折线图：缺口断开、不平滑、不补零；悬停十字线 + tooltip。
/// 所有绘制走 Canvas（transform/opacity 之外的绘制一次性完成，无布局开销）。
struct MetricChartView: View {
    var series: [ChartSeries]
    var window: ClosedRange<Date>
    var yMin: Double
    var yMax: Double
    var yLabel: (Double) -> String
    var tickSeconds: TimeInterval = 1
    var height: CGFloat = 220
    var mini = false
    var refLine: (y: Double, label: String)?

    @State private var hoverT: Date?

    private var padL: CGFloat { mini ? 34 : 46 }
    private var padR: CGFloat { 10 }
    private var padT: CGFloat { mini ? 5 : 8 }
    private var padB: CGFloat { mini ? 13 : 18 }

    var body: some View {
        Canvas { context, size in
            let iw = size.width - padL - padR
            let ih = size.height - padT - padB
            guard iw > 0, ih > 0 else { return }
            let t0 = window.lowerBound.timeIntervalSince1970
            let t1 = window.upperBound.timeIntervalSince1970
            let span = max(1, t1 - t0)
            let xOf: (Date) -> CGFloat = { padL + iw * CGFloat(($0.timeIntervalSince1970 - t0) / span) }
            let yOf: (Double) -> CGFloat = { padT + ih * (1 - CGFloat(($0 - yMin) / max(1e-9, yMax - yMin))) }

            drawGrid(context: context, size: size, xOf: xOf, yOf: yOf, span: span)
            if let refLine {
                drawRefLine(context: context, size: size, y: refLine.y, label: refLine.label, yOf: yOf)
            }
            for item in series {
                drawSeries(item, context: context, xOf: xOf, yOf: yOf, yMin: yMin)
            }
            if let hoverT {
                let x = xOf(hoverT)
                var path = Path()
                path.move(to: CGPoint(x: x, y: padT))
                path.addLine(to: CGPoint(x: x, y: padT + ih))
                context.stroke(path, with: .color(Theme.text3), style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
            }
        }
        .frame(height: height)
        .clipped() // 窗口边缘外的采样点不画出图表框
        .onGeometryChange(for: CGFloat.self, of: { $0.size.width }) { width in
            currentWidth = width
        }
        .onContinuousHover(coordinateSpace: .local) { phase in
            switch phase {
            case .active(let location):
                let iw = max(1, currentWidth - padL - padR)
                let fraction = min(1, max(0, (location.x - padL) / iw))
                let t0 = window.lowerBound.timeIntervalSince1970
                let span = max(1, window.upperBound.timeIntervalSince1970 - t0)
                hoverT = Date(timeIntervalSince1970: t0 + span * Double(fraction))
            case .ended:
                hoverT = nil
            }
        }
        .overlay(alignment: .topLeading) {
            if let hoverT, let content = tooltipContent(at: hoverT) {
                tooltip(content)
                    .position(x: tooltipX(for: hoverT), y: mini ? 24 : 28)
                    .allowsHitTesting(false)
            }
        }
    }

    /// onContinuousHover 的闭包拿不到 Canvas 的 size，通过 onGeometryChange 记录宽度。
    @State private var currentWidth: CGFloat = 600

    private func drawGrid(
        context: GraphicsContext,
        size: CGSize,
        xOf: (Date) -> CGFloat,
        yOf: (Double) -> CGFloat,
        span: TimeInterval,
    ) {
        let gridCount = mini ? 2 : 4
        for index in 0...gridCount {
            let value = yMin + (yMax - yMin) * Double(index) / Double(gridCount)
            let y = yOf(value)
            var path = Path()
            path.move(to: CGPoint(x: padL, y: y))
            path.addLine(to: CGPoint(x: size.width - padR, y: y))
            context.stroke(path, with: .color(Theme.grid), lineWidth: 1)
            let label = Text(yLabel(value))
                .font(.system(size: mini ? 9 : 10))
                .foregroundStyle(Theme.text3)
            context.draw(label, at: CGPoint(x: padL - 6, y: y), anchor: .trailing)
        }
        guard !mini else { return }
        let labelCount = span <= 65 ? 4 : 5
        for index in 0...labelCount {
            let t = window.lowerBound.addingTimeInterval(span * Double(index) / Double(labelCount))
            let label = Text(span <= 65 ? Format.time(t) : Format.timeShort(t))
                .font(.system(size: 10))
                .foregroundStyle(Theme.text3)
                .monospacedDigit()
            context.draw(label, at: CGPoint(x: xOf(t), y: size.height - padB + 5), anchor: .top)
        }
    }

    private func drawRefLine(
        context: GraphicsContext,
        size: CGSize,
        y: Double,
        label: String,
        yOf: (Double) -> CGFloat,
    ) {
        let py = yOf(y)
        var path = Path()
        path.move(to: CGPoint(x: padL, y: py))
        path.addLine(to: CGPoint(x: size.width - padR, y: py))
        context.stroke(path, with: .color(Theme.text3), style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
        let text = Text(label).font(.system(size: 10)).foregroundStyle(Theme.text2)
        context.draw(text, at: CGPoint(x: size.width - padR - 2, y: py - 2), anchor: .bottomTrailing)
    }

    private func drawSeries(
        _ item: ChartSeries,
        context: GraphicsContext,
        xOf: (Date) -> CGFloat,
        yOf: (Double) -> CGFloat,
        yMin: Double,
    ) {
        let t0 = window.lowerBound.addingTimeInterval(-tickSeconds)
        let t1 = window.upperBound.addingTimeInterval(tickSeconds)
        let visible = item.points.compactMap { $0 }.filter { $0.t >= t0 && $0.t <= t1 }

        var segments: [[ChartPoint]] = []
        var current: [ChartPoint] = []
        var previous: ChartPoint?
        for point in visible {
            if let previous, MonitorLogic.hasSamplingGap(previous: previous.t, current: point.t, tickSeconds: tickSeconds) {
                if !current.isEmpty { segments.append(current) }
                current = []
            }
            current.append(point)
            previous = point
        }
        if !current.isEmpty { segments.append(current) }

        for segment in segments {
            if item.fill, let first = segment.first, let last = segment.last {
                var fillPath = Path()
                fillPath.move(to: CGPoint(x: xOf(first.t), y: yOf(yMin)))
                for point in segment {
                    fillPath.addLine(to: CGPoint(x: xOf(point.t), y: yOf(point.v)))
                }
                fillPath.addLine(to: CGPoint(x: xOf(last.t), y: yOf(yMin)))
                fillPath.closeSubpath()
                context.fill(fillPath, with: .color(item.color.opacity(0.13 * item.alpha)))
            }
            var strokePath = Path()
            for (index, point) in segment.enumerated() {
                let cg = CGPoint(x: xOf(point.t), y: yOf(point.v))
                if index == 0 { strokePath.move(to: cg) } else { strokePath.addLine(to: cg) }
            }
            context.stroke(
                strokePath,
                with: .color(item.color.opacity(item.alpha)),
                style: StrokeStyle(lineWidth: item.width, lineCap: .round, lineJoin: .round),
            )
        }
    }

    // MARK: - Tooltip

    private struct TooltipRow {
        var color: Color
        var label: String
        var value: String
    }

    private func tooltipContent(at t: Date) -> (time: Date, rows: [TooltipRow])? {
        let tolerance = max(3 * tickSeconds, window.upperBound.timeIntervalSince(window.lowerBound) / 60)
        var rows: [TooltipRow] = []
        var time: Date?
        for item in series {
            var best: ChartPoint?
            var bestDistance = Double.greatestFiniteMagnitude
            for point in item.points {
                guard let point else { continue }
                let distance = abs(point.t.timeIntervalSince(t))
                if distance < bestDistance { bestDistance = distance; best = point }
            }
            if let best, bestDistance <= tolerance {
                time = best.t
                rows.append(TooltipRow(color: item.color, label: item.label, value: item.format(best.v)))
            }
        }
        guard let time, !rows.isEmpty else { return nil }
        return (time, rows)
    }

    private func tooltip(_ content: (time: Date, rows: [TooltipRow])) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(Format.time(content.time))
                .font(.system(size: 11.5))
                .foregroundStyle(Theme.text2)
                .monospacedDigit()
            ForEach(content.rows.indices, id: \.self) { index in
                let row = content.rows[index]
                HStack(spacing: 6) {
                    RoundedRectangle(cornerRadius: 2).fill(row.color).frame(width: 8, height: 8)
                    if !row.label.isEmpty { Text(row.label) }
                    Text(row.value).fontWeight(.semibold).monospacedDigit()
                }
                .font(.system(size: 11.5))
            }
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 6)
        .background(Theme.raised)
        .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Theme.sepStrong, lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .shadow(color: .black.opacity(0.18), radius: 7, y: 4)
    }

    private func tooltipX(for t: Date) -> CGFloat {
        let iw = max(1, currentWidth - padL - padR)
        let fraction = CGFloat(t.timeIntervalSince(window.lowerBound) / max(1, window.upperBound.timeIntervalSince(window.lowerBound)))
        let x = padL + iw * fraction + 14
        return min(max(70, x), currentWidth - 70)
    }
}
