import SwiftUI

/// 侧栏资源卡片迷你图：仅描边，缺口断开。
struct SparklineView: View {
    var points: [ChartPoint]
    var color: Color
    var yMax: Double?
    var tickSeconds: TimeInterval = 1

    var body: some View {
        Canvas { context, size in
            guard points.count > 1, size.width > 0, size.height > 0 else { return }
            let ceiling = yMax ?? max(1, points.map(\.v).max() ?? 1)
            let xOf: (Int) -> CGFloat = { size.width * CGFloat($0) / CGFloat(max(1, points.count - 1)) }
            let yOf: (Double) -> CGFloat = { size.height - 2 - (size.height - 5) * CGFloat($0 / ceiling) }

            var path = Path()
            var pen = false
            var previous: ChartPoint?
            for (index, point) in points.enumerated() {
                let broken = previous.map {
                    MonitorLogic.hasSamplingGap(previous: $0.t, current: point.t, tickSeconds: tickSeconds)
                } ?? false
                let cg = CGPoint(x: xOf(index), y: yOf(point.v))
                if !pen || broken {
                    path.move(to: cg)
                    pen = true
                } else {
                    path.addLine(to: cg)
                }
                previous = point
            }
            context.stroke(
                path,
                with: .color(color),
                style: StrokeStyle(lineWidth: 1.3, lineCap: .round, lineJoin: .round),
            )
        }
        .frame(height: 30)
    }
}
