import SwiftUI

/// Debug dashboard: every dashboard/chart element we can think of, all named for component discovery.
struct DashboardView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Spacing.xl) {
                sectionHeader("KPI & metric cards")
                kpiCardsSection

                sectionHeader("Pie chart")
                PieChartDemo()

                sectionHeader("Donut chart")
                DonutChartDemo()

                sectionHeader("Bar chart (vertical)")
                VerticalBarChartDemo()

                sectionHeader("Bar chart (horizontal)")
                HorizontalBarChartDemo()

                sectionHeader("Stacked bar chart")
                StackedBarChartDemo()

                sectionHeader("Line chart")
                LineChartDemo()

                sectionHeader("Area chart")
                AreaChartDemo()

                sectionHeader("Combined line + area")
                LineAreaChartDemo()

                sectionHeader("Sparkline")
                SparklineDemo()

                sectionHeader("Gauge (radial)")
                GaugeRadialDemo()

                sectionHeader("Gauge (linear / progress)")
                GaugeLinearDemo()

                sectionHeader("Progress ring")
                ProgressRingDemo()

                sectionHeader("Treemap (rectangles)")
                TreemapDemo()

                sectionHeader("Heatmap")
                HeatmapDemo()

                sectionHeader("Waterfall chart")
                WaterfallChartDemo()

                sectionHeader("Radar / spider chart")
                RadarChartDemo()

                sectionHeader("Bubble chart")
                BubbleChartDemo()

                sectionHeader("Funnel chart")
                FunnelChartDemo()

                sectionHeader("Stat list (key-value)")
                StatListDemo()

                sectionHeader("Leaderboard / ranking")
                LeaderboardDemo()

                sectionHeader("Data table")
                DataTableDemo()

                Color.clear.frame(height: 40)
            }
            .padding(.horizontal, Theme.Spacing.md)
            .padding(.top, Theme.Spacing.md)
        }
        .background(Theme.Colors.background)
        .navigationTitle("Dashboard")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .tabBar)
    }

    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(Theme.Typography.headline)
            .foregroundColor(Theme.Colors.primaryText)
    }

    private var kpiCardsSection: some View {
        VStack(spacing: Theme.Spacing.sm) {
            HStack(spacing: Theme.Spacing.sm) {
                KPICard(title: "Revenue", value: "£12.4k", subtitle: "+8%")
                KPICard(title: "Orders", value: "1,240", subtitle: "+12%")
            }
            HStack(spacing: Theme.Spacing.sm) {
                KPICard(title: "Conversion", value: "3.2%", subtitle: "-0.1%")
                KPICard(title: "Avg. order", value: "£42", subtitle: "+5%")
            }
        }
    }
}

// MARK: - KPI card
private struct KPICard: View {
    let title: String
    let value: String
    let subtitle: String
    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            Text(title).font(Theme.Typography.caption).foregroundColor(Theme.Colors.secondaryText)
            Text(value).font(Theme.Typography.title2).foregroundColor(Theme.Colors.primaryText)
            Text(subtitle).font(.caption2).foregroundColor(Theme.primaryColor)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Theme.Spacing.md)
        .background(Theme.Colors.secondaryBackground)
        .cornerRadius(8)
    }
}

// MARK: - Pie chart
private struct PieChartDemo: View {
    private let segments: [(String, Double)] = [("A", 30), ("B", 45), ("C", 25)]
    var body: some View {
        PieChartView(segments: segments, colors: [Theme.primaryColor, .orange, .green])
            .frame(height: 160)
    }
}

private struct PieChartView: View {
    let segments: [(String, Double)]
    let colors: [Color]
    var body: some View {
        GeometryReader { geo in
            let total = segments.map(\.1).reduce(0, +)
            let size = min(geo.size.width, geo.size.height)
            let radius = size / 2
            ZStack {
                ForEach(Array(segments.enumerated()), id: \.offset) { i, seg in
                    let start = segments.prefix(i).map(\.1).reduce(0, +) / total * 360
                    let angle = seg.1 / total * 360
                    PieSlice(startAngle: .degrees(start), endAngle: .degrees(start + angle))
                        .fill(colors[i % colors.count])
                }
            }
            .frame(width: size, height: size)
        }
    }
}

private struct PieSlice: Shape {
    var startAngle: Angle
    var endAngle: Angle
    func path(in rect: CGRect) -> Path {
        var p = Path()
        let c = CGPoint(x: rect.midX, y: rect.midY)
        let r = min(rect.width, rect.height) / 2
        p.move(to: c)
        p.addArc(center: c, radius: r, startAngle: startAngle, endAngle: endAngle, clockwise: false)
        p.closeSubpath()
        return p
    }
}

// MARK: - Donut chart
private struct DonutChartDemo: View {
    private let segments: [(String, Double)] = [("X", 40), ("Y", 35), ("Z", 25)]
    var body: some View {
        DonutChartView(segments: segments, colors: [.blue, .purple, .pink])
            .frame(height: 160)
    }
}

private struct DonutChartView: View {
    let segments: [(String, Double)]
    let colors: [Color]
    var body: some View {
        GeometryReader { geo in
            let total = segments.map(\.1).reduce(0, +)
            let size = min(geo.size.width, geo.size.height)
            let r = size / 2
            ZStack {
                ForEach(Array(segments.enumerated()), id: \.offset) { i, seg in
                    let start = segments.prefix(i).map(\.1).reduce(0, +) / total * 360
                    let angle = seg.1 / total * 360
                    DonutSlice(startAngle: .degrees(start), endAngle: .degrees(start + angle), lineWidth: 24)
                        .fill(colors[i % colors.count])
                }
            }
            .frame(width: size, height: size)
        }
    }
}

private struct DonutSlice: Shape {
    var startAngle: Angle
    var endAngle: Angle
    var lineWidth: CGFloat
    func path(in rect: CGRect) -> Path {
        var p = Path()
        let c = CGPoint(x: rect.midX, y: rect.midY)
        let r = min(rect.width, rect.height) / 2
        let r2 = r - lineWidth
        p.addArc(center: c, radius: r, startAngle: startAngle, endAngle: endAngle, clockwise: false)
        p.addArc(center: c, radius: r2, startAngle: endAngle, endAngle: startAngle, clockwise: true)
        p.closeSubpath()
        return p
    }
}

// MARK: - Vertical bar chart
private struct VerticalBarChartDemo: View {
    private let data: [(String, Double)] = [("Mon", 40), ("Tue", 65), ("Wed", 50), ("Thu", 80), ("Fri", 55)]
    var body: some View {
        VerticalBarChartView(data: data, barColor: Theme.primaryColor)
            .frame(height: 140)
    }
}

private struct VerticalBarChartView: View {
    let data: [(String, Double)]
    let barColor: Color
    var body: some View {
        let maxVal = data.map(\.1).max() ?? 1
        HStack(alignment: .bottom, spacing: 8) {
            ForEach(Array(data.enumerated()), id: \.offset) { _, d in
                VStack(spacing: 4) {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(barColor)
                        .frame(height: max(4, 80 * (d.1 / maxVal)))
                    Text(d.0).font(.caption2).foregroundColor(Theme.Colors.secondaryText)
                }
                .frame(maxWidth: .infinity)
            }
        }
    }
}

// MARK: - Horizontal bar chart
private struct HorizontalBarChartDemo: View {
    private let data: [(String, Double)] = [("Cat A", 70), ("Cat B", 45), ("Cat C", 90)]
    var body: some View {
        HorizontalBarChartView(data: data, barColor: Theme.primaryColor)
            .frame(height: 100)
    }
}

private struct HorizontalBarChartView: View {
    let data: [(String, Double)]
    let barColor: Color
    var body: some View {
        let maxVal = data.map(\.1).max() ?? 1
        VStack(alignment: .leading, spacing: 8) {
            ForEach(Array(data.enumerated()), id: \.offset) { _, d in
                HStack(spacing: 8) {
                    Text(d.0).font(.caption).foregroundColor(Theme.Colors.primaryText).frame(width: 44, alignment: .leading)
                    GeometryReader { g in
                        RoundedRectangle(cornerRadius: 4)
                            .fill(barColor)
                            .frame(width: g.size.width * (d.1 / maxVal))
                    }
                    .frame(height: 20)
                }
            }
        }
    }
}

// MARK: - Stacked bar chart
private struct StackedBarChartDemo: View {
    private let stacks: [(String, [Double])] = [("W1", [30, 40, 30]), ("W2", [20, 50, 30]), ("W3", [40, 30, 30])]
    var body: some View {
        StackedBarChartView(stacks: stacks, colors: [Theme.primaryColor, .orange, .green])
            .frame(height: 120)
    }
}

private struct StackedBarChartView: View {
    let stacks: [(String, [Double])]
    let colors: [Color]
    var body: some View {
        let maxVal = stacks.map { $0.1.reduce(0, +) }.max() ?? 1
        VStack(alignment: .leading, spacing: 8) {
            ForEach(Array(stacks.enumerated()), id: \.offset) { _, s in
                let total = s.1.reduce(0, +)
                HStack(spacing: 2) {
                    ForEach(Array(s.1.enumerated()), id: \.offset) { j, v in
                        RoundedRectangle(cornerRadius: 2)
                            .fill(colors[j % colors.count])
                            .frame(maxWidth: .infinity)
                            .frame(height: 24)
                    }
                }
                .frame(height: 24)
                .frame(maxWidth: .infinity)
                .overlay(alignment: .leading) {
                    Text(s.0).font(.caption2).foregroundColor(Theme.Colors.primaryText).padding(.leading, 4)
                }
            }
        }
    }
}

// MARK: - Line chart
private struct LineChartDemo: View {
    private let points: [Double] = [20, 45, 35, 60, 50, 75, 65]
    var body: some View {
        LineChartView(points: points, lineColor: Theme.primaryColor)
            .frame(height: 120)
    }
}

private struct LineChartView: View {
    let points: [Double]
    let lineColor: Color
    var body: some View {
        LineChartShape(points: points)
            .stroke(lineColor, lineWidth: 2)
    }
}

private struct LineChartShape: Shape {
    let points: [Double]
    func path(in rect: CGRect) -> Path {
        guard !points.isEmpty else { return Path() }
        let maxP = points.max() ?? 1
        let minP = points.min() ?? 0
        let range = maxP - minP
        let stepX = rect.width / CGFloat(max(points.count - 1, 1))
        var p = Path()
        for (i, v) in points.enumerated() {
            let x = CGFloat(i) * stepX
            let y = range > 0 ? rect.height * (1 - CGFloat((v - minP) / range)) : rect.height / 2
            if i == 0 { p.move(to: CGPoint(x: x, y: y)) }
            else { p.addLine(to: CGPoint(x: x, y: y)) }
        }
        return p
    }
}

// MARK: - Area chart
private struct AreaChartDemo: View {
    private let points: [Double] = [10, 30, 25, 50, 45, 70, 60]
    var body: some View {
        AreaChartView(points: points, fillColor: Theme.primaryColor.opacity(0.3), lineColor: Theme.primaryColor)
            .frame(height: 120)
    }
}

private struct AreaChartView: View {
    let points: [Double]
    let fillColor: Color
    let lineColor: Color
    var body: some View {
        GeometryReader { geo in
            ZStack {
                AreaChartShape(points: points)
                    .fill(fillColor)
                AreaChartShape(points: points)
                    .stroke(lineColor, lineWidth: 2)
            }
        }
    }
}

private struct AreaChartShape: Shape {
    let points: [Double]
    func path(in rect: CGRect) -> Path {
        guard !points.isEmpty else { return Path() }
        let maxP = points.max() ?? 1
        let minP = points.min() ?? 0
        let range = maxP - minP
        let stepX = rect.width / CGFloat(max(points.count - 1, 1))
        var areaPath = Path()
        for (i, v) in points.enumerated() {
            let x = CGFloat(i) * stepX
            let y = range > 0 ? rect.height * (1 - CGFloat((v - minP) / range)) : rect.height / 2
            if i == 0 {
                areaPath.move(to: CGPoint(x: x, y: rect.height))
                areaPath.addLine(to: CGPoint(x: x, y: y))
            } else {
                areaPath.addLine(to: CGPoint(x: x, y: y))
            }
        }
        areaPath.addLine(to: CGPoint(x: CGFloat(points.count - 1) * stepX, y: rect.height))
        areaPath.closeSubpath()
        return areaPath
    }
}

// MARK: - Line + area combined
private struct LineAreaChartDemo: View {
    private let points: [Double] = [15, 40, 30, 55, 50]
    var body: some View {
        AreaChartView(points: points, fillColor: Theme.primaryColor.opacity(0.2), lineColor: Theme.primaryColor)
            .frame(height: 100)
    }
}

// MARK: - Sparkline
private struct SparklineDemo: View {
    private let points: [Double] = [1, 3, 2, 5, 4, 6, 5, 8]
    var body: some View {
        LineChartView(points: points, lineColor: Theme.primaryColor)
            .frame(height: 44)
    }
}

// MARK: - Gauge radial
private struct GaugeRadialDemo: View {
    var body: some View {
        ZStack {
            Circle()
                .stroke(Theme.Colors.secondaryBackground, lineWidth: 12)
                .frame(width: 100, height: 100)
            Circle()
                .trim(from: 0, to: 0.65)
                .stroke(Theme.primaryColor, style: StrokeStyle(lineWidth: 12, lineCap: .round))
                .frame(width: 100, height: 100)
                .rotationEffect(.degrees(-90))
            Text("65%").font(Theme.Typography.headline).foregroundColor(Theme.Colors.primaryText)
        }
    }
}

// MARK: - Gauge linear (progress bar)
private struct GaugeLinearDemo: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Progress").font(.caption).foregroundColor(Theme.Colors.secondaryText)
            GeometryReader { g in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 6).fill(Theme.Colors.secondaryBackground).frame(height: 12)
                    RoundedRectangle(cornerRadius: 6).fill(Theme.primaryColor).frame(width: g.size.width * 0.7, height: 12)
                }
            }
            .frame(height: 12)
        }
    }
}

// MARK: - Progress ring
private struct ProgressRingDemo: View {
    var body: some View {
        ZStack {
            Circle().stroke(Theme.Colors.secondaryBackground, lineWidth: 8).frame(width: 80, height: 80)
            Circle()
                .trim(from: 0, to: 0.8)
                .stroke(Theme.primaryColor, style: StrokeStyle(lineWidth: 8, lineCap: .round))
                .frame(width: 80, height: 80)
                .rotationEffect(.degrees(-90))
        }
    }
}

// MARK: - Treemap
private struct TreemapDemo: View {
    var body: some View {
        GeometryReader { g in
            let w = g.size.width
            let h = g.size.height
            ZStack(alignment: .topLeading) {
                Rectangle().fill(Theme.primaryColor.opacity(0.6)).frame(width: w * 0.6, height: h * 0.6)
                Rectangle().fill(Color.orange.opacity(0.6)).frame(width: w * 0.4, height: h * 0.6).offset(x: w * 0.6)
                Rectangle().fill(Color.green.opacity(0.6)).frame(width: w * 0.6, height: h * 0.4).offset(y: h * 0.6)
                Rectangle().fill(Color.pink.opacity(0.6)).frame(width: w * 0.4, height: h * 0.4).offset(x: w * 0.6, y: h * 0.6)
            }
        }
        .frame(height: 100)
    }
}

// MARK: - Heatmap
private struct HeatmapDemo: View {
    private let rows = 4
    private let cols = 5
    private let values: [[Double]] = (0..<4).map { _ in (0..<5).map { _ in Double.random(in: 0...1) } }
    var body: some View {
        Grid(horizontalSpacing: 2, verticalSpacing: 2) {
            ForEach(0..<rows, id: \.self) { r in
                GridRow {
                    ForEach(0..<cols, id: \.self) { c in
                        RoundedRectangle(cornerRadius: 2)
                            .fill(Color.green.opacity(values[r][c]))
                            .aspectRatio(1, contentMode: .fit)
                    }
                }
            }
        }
        .frame(height: 80)
    }
}

// MARK: - Waterfall chart
private struct WaterfallChartDemo: View {
    private let items: [(String, Double)] = [("Start", 100), ("+A", 20), ("-B", -15), ("+C", 30), ("End", 135)]
    var body: some View {
        ScrollView(.horizontal) {
            HStack(alignment: .bottom, spacing: 4) {
                ForEach(Array(items.enumerated()), id: \.offset) { i, d in
                    VStack(spacing: 2) {
                        RoundedRectangle(cornerRadius: 4)
                            .fill(d.1 >= 0 ? Theme.primaryColor : Color.red.opacity(0.8))
                            .frame(width: 44, height: max(8, min(60, abs(d.1))))
                        Text(d.0).font(.caption2).foregroundColor(Theme.Colors.secondaryText)
                    }
                }
            }
        }
        .frame(height: 90)
    }
}

// MARK: - Radar chart
private struct RadarChartDemo: View {
    private let values: [Double] = [0.8, 0.6, 0.9, 0.5, 0.7]
    private let labels = ["A", "B", "C", "D", "E"]
    var body: some View {
        RadarChartView(values: values, labels: labels, color: Theme.primaryColor)
            .frame(height: 140)
    }
}

private struct RadarChartView: View {
    let values: [Double]
    let labels: [String]
    let color: Color
    var body: some View {
        GeometryReader { geo in
            let n = values.count
            let center = CGPoint(x: geo.size.width / 2, y: geo.size.height / 2)
            let r = min(geo.size.width, geo.size.height) / 2 - 20
            let path = Path { p in
                for (i, v) in values.enumerated() {
                    let angle = .pi * 2 * CGFloat(i) / CGFloat(n) - .pi / 2
                    let pt = CGPoint(x: center.x + r * CGFloat(v) * cos(angle), y: center.y + r * CGFloat(v) * sin(angle))
                    if i == 0 { p.move(to: pt) } else { p.addLine(to: pt) }
                }
                p.closeSubpath()
            }
            path.stroke(color, lineWidth: 2)
            path.fill(color.opacity(0.2))
        }
    }
}

// MARK: - Bubble chart
private struct BubbleChartDemo: View {
    private let bubbles: [(x: Double, y: Double, r: Double)] = [(0.3, 0.4, 0.15), (0.6, 0.7, 0.25), (0.5, 0.3, 0.1)]
    var body: some View {
        GeometryReader { g in
            ZStack(alignment: .bottomLeading) {
                ForEach(Array(bubbles.enumerated()), id: \.offset) { i, b in
                    let colors: [Color] = [Theme.primaryColor, .orange, .green]
                    Circle()
                        .fill(colors[i].opacity(0.6))
                        .frame(width: g.size.width * b.r * 2, height: g.size.height * b.r * 2)
                        .position(x: g.size.width * b.x, y: g.size.height * (1 - b.y))
                }
            }
        }
        .frame(height: 100)
    }
}

// MARK: - Funnel chart
private struct FunnelChartDemo: View {
    private let steps: [Double] = [100, 70, 45, 20]
    var body: some View {
        let maxW = steps.max() ?? 1
        VStack(spacing: 2) {
            ForEach(Array(steps.enumerated()), id: \.offset) { i, v in
                TrapezoidShape(topRatio: (steps.indices.contains(i + 1) ? steps[i + 1] / maxW : 0), bottomRatio: v / maxW)
                    .fill(Theme.primaryColor.opacity(0.3 + Double(i) * 0.2))
                    .frame(height: 28)
            }
        }
        .frame(height: 120)
    }
}

private struct TrapezoidShape: Shape {
    var topRatio: CGFloat
    var bottomRatio: CGFloat
    func path(in rect: CGRect) -> Path {
        var p = Path()
        let w = rect.width
        let t = w * (1 - topRatio) / 2
        let b = w * (1 - bottomRatio) / 2
        p.move(to: CGPoint(x: t, y: 0))
        p.addLine(to: CGPoint(x: w - t, y: 0))
        p.addLine(to: CGPoint(x: w - b, y: rect.height))
        p.addLine(to: CGPoint(x: b, y: rect.height))
        p.closeSubpath()
        return p
    }
}

// MARK: - Stat list (key-value)
private struct StatListDemo: View {
    private let rows: [(String, String)] = [("Revenue", "£12.4k"), ("Orders", "1,240"), ("Conversion", "3.2%")]
    var body: some View {
        VStack(spacing: 0) {
            ForEach(Array(rows.enumerated()), id: \.offset) { i, r in
                HStack {
                    Text(r.0).font(Theme.Typography.body).foregroundColor(Theme.Colors.secondaryText)
                    Spacer()
                    Text(r.1).font(Theme.Typography.headline).foregroundColor(Theme.Colors.primaryText)
                }
                .padding(.vertical, Theme.Spacing.sm)
                if i < rows.count - 1 {
                    Rectangle().fill(Theme.Colors.glassBorder).frame(height: 0.5)
                }
            }
        }
        .padding(Theme.Spacing.md)
        .background(Theme.Colors.secondaryBackground)
        .cornerRadius(8)
    }
}

// MARK: - Leaderboard
private struct LeaderboardDemo: View {
    private let items: [(Int, String, String)] = [(1, "Seller A", "£2.4k"), (2, "Seller B", "£1.8k"), (3, "Seller C", "£1.2k")]
    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            ForEach(Array(items.enumerated()), id: \.offset) { i, row in
                HStack(spacing: Theme.Spacing.md) {
                    Text("\(row.0)").font(Theme.Typography.headline).foregroundColor(Theme.Colors.secondaryText).frame(width: 24)
                    Text(row.1).font(Theme.Typography.body).foregroundColor(Theme.Colors.primaryText)
                    Spacer()
                    Text(row.2).font(Theme.Typography.subheadline).foregroundColor(Theme.primaryColor)
                }
                .padding(.vertical, 4)
            }
        }
        .padding(Theme.Spacing.md)
        .background(Theme.Colors.secondaryBackground)
        .cornerRadius(8)
    }
}

// MARK: - Data table
private struct DataTableDemo: View {
    private let headers = ["Name", "Value", "Change"]
    private let rows: [[String]] = [["Item 1", "100", "+5%"], ["Item 2", "200", "-2%"], ["Item 3", "150", "+10%"]]
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                ForEach(headers, id: \.self) { h in
                    Text(h).font(Theme.Typography.caption).foregroundColor(Theme.Colors.secondaryText).frame(maxWidth: .infinity)
                }
            }
            .padding(.vertical, Theme.Spacing.sm)
            Rectangle().fill(Theme.Colors.glassBorder).frame(height: 0.5)
            ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                HStack {
                    ForEach(row, id: \.self) { cell in
                        Text(cell).font(Theme.Typography.caption).foregroundColor(Theme.Colors.primaryText).frame(maxWidth: .infinity)
                    }
                }
                .padding(.vertical, Theme.Spacing.xs)
            }
        }
        .padding(Theme.Spacing.md)
        .background(Theme.Colors.secondaryBackground)
        .cornerRadius(8)
    }
}

#Preview {
    NavigationStack {
        DashboardView()
    }
}
