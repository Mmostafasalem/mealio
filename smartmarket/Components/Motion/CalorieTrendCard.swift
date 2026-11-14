import SwiftUI
import Accessibility

// MARK: - Calorie Trend Card
//
// Port of designbookmark.com/motion "Stat Card" (stat-card/stat.js).
// Twelve springs (200, 17), one per chart point, drawn as a smooth curve with a
// filled area. A range change retargets them left to right with a 0.03 s
// stagger; the average and the change chip roll to their new values (160, 22)
// and the pill slides under the new tab (380, 30). No autoplay: it only moves
// when the range or the food log changes.

enum CalorieTrendRange: Int, CaseIterable, Identifiable {
    case week = 7
    case month = 30
    var id: Int { rawValue }
    var days: Int { rawValue }
    var title: String { "\(rawValue) days" }
}

/// One range's worth of numbers, derived from the food log.
struct CalorieTrend: Equatable {
    /// One value per calendar day, oldest first. `nil` = nothing logged that day.
    var daily: [Int?]
    /// Average kcal over the logged days in the range.
    var average: Int?
    /// Change of `average` vs the period just before, in percent. `nil` when that period is empty.
    var change: Double?
    /// The day the series starts on.
    var start: Date
    var range: CalorieTrendRange

    static let pointCount = 12

    init(entries: [FoodLogEntry], range: CalorieTrendRange, now: Date = Date(), calendar: Calendar = .current) {
        var totals: [Date: Int] = [:]
        for e in entries { totals[calendar.startOfDay(for: e.loggedAt), default: 0] += e.calories }
        let today = calendar.startOfDay(for: now)
        func days(endingDaysAgo end: Int) -> [Int?] {
            (0..<range.days).reversed().map { back in
                calendar.date(byAdding: .day, value: -(back + end), to: today).flatMap { totals[$0] }
            }
        }
        func mean(_ values: [Int?]) -> Double? {
            let logged = values.compactMap { $0 }
            return logged.isEmpty ? nil : Double(logged.reduce(0, +)) / Double(logged.count)
        }
        self.range = range
        daily = days(endingDaysAgo: 0)
        start = calendar.date(byAdding: .day, value: -(range.days - 1), to: today) ?? today
        let cur = mean(daily), prev = mean(days(endingDaysAgo: range.days))
        average = cur.map { Int($0.rounded()) }
        if let cur, let prev, prev > 0 { change = (cur - prev) / prev * 100 } else { change = nil }
    }

    /// Days with no log are bridged linearly from their logged neighbours, so a
    /// skipped day reads as a gap in the record rather than a zero-calorie day.
    var filled: [Double] {
        let known = daily.enumerated().compactMap { i, v in v.map { (i, Double($0)) } }
        guard let first = known.first, let last = known.last else { return daily.map { _ in 0 } }
        return daily.indices.map { i in
            if let v = daily[i] { return Double(v) }
            if i < first.0 { return first.1 }
            if i > last.0 { return last.1 }
            let a = known.last { $0.0 < i }!, b = known.first { $0.0 > i }!
            return a.1 + (b.1 - a.1) * Double(i - a.0) / Double(b.0 - a.0)
        }
    }

    /// Twelve chart heights in 0…1, resampled from the daily series.
    var points: [Double] {
        let f = filled
        guard f.count > 1 else { return Array(repeating: 0.5, count: Self.pointCount) }
        let lo = f.min()!, hi = f.max()!
        return (0..<Self.pointCount).map { i in
            let p = Double(i) / Double(Self.pointCount - 1) * Double(f.count - 1)
            let j = min(Int(p), f.count - 2), frac = p - Double(j)
            let v = f[j] + (f[j + 1] - f[j]) * frac
            return hi - lo < 1 ? 0.5 : 0.12 + 0.76 * (v - lo) / (hi - lo)
        }
    }
}

struct CalorieTrendCard: View {
    let entries: [FoodLogEntry]
    @State private var range: CalorieTrendRange = .week
    @State private var model = CalorieTrendModel()
    /// Derived from the log once per change of `cacheKey`, never per frame.
    @State private var trend: CalorieTrend?
    @State private var loggedDays = 0

    /// Cheap fingerprint of the inputs: what the card shows only changes when one of these does.
    private struct CacheKey: Equatable {
        var count: Int
        var lastDate: Date?
        var lastCalories: Int?
        var range: CalorieTrendRange
        var today: Date
    }

    private var cacheKey: CacheKey {
        CacheKey(count: entries.count, lastDate: entries.last?.loggedAt,
                 lastCalories: entries.last?.calories, range: range,
                 today: Calendar.current.startOfDay(for: Date()))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if let trend, loggedDays >= 2 {
                header(trend)
                chart(trend)
                rangePicker
            } else {
                emptyState
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.surface, in: RoundedRectangle(cornerRadius: Radius.card + 4, style: .continuous))
        .onChange(of: cacheKey, initial: true) {
            let animated = trend != nil
            let t = CalorieTrend(entries: entries, range: range)
            loggedDays = Set(entries.map { Calendar.current.startOfDay(for: $0.loggedAt) }).count
            guard t != trend else { return }
            trend = t
            model.show(t, range: range, animated: animated)
        }
        .onDisappear { model.stop() }
    }

    private var emptyState: some View {
        Label("Log food on two days to see your trend.", systemImage: "chart.xyaxis.line")
            .font(.subheadline)
            .foregroundStyle(Color.labelSecondary)
            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
    }

    private func header(_ trend: CalorieTrend) -> some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Daily average")
                    .font(.footnote)
                    .foregroundStyle(Color.labelSecondary)
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(trend.average == nil ? "–" : Int(max(0, model.total).rounded()).formatted())
                        .font(.largeTitle.weight(.bold).monospacedDigit())
                        .foregroundStyle(Color.labelPrimary)
                    Text("kcal")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(Color.labelSecondary)
                }
            }
            Spacer(minLength: Spacing.sm)
            if trend.change != nil {
                Text(Self.percent(model.change))
                    .font(.footnote.weight(.bold).monospacedDigit())
                    .foregroundStyle(Color.brandPrimary)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 4)
                    .background(Color.dullPink.opacity(0.28), in: Capsule())
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Self.summary(trend, range: range))
    }

    private func chart(_ trend: CalorieTrend) -> some View {
        TrendCurve(points: model.points, closed: true)
            .fill(LinearGradient(colors: [Color.dullPink.opacity(0.32), Color.dullPink.opacity(0)],
                                 startPoint: .top, endPoint: .bottom))
            .overlay {
                TrendCurve(points: model.points, closed: false)
                    .stroke(Color.dullPink, style: StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round))
            }
            .overlay(alignment: .topLeading) {
                GeometryReader { geo in
                    let p = TrendCurve.position(of: model.points.count - 1, in: model.points, size: geo.size)
                    Circle()
                        .fill(Color.brandPrimary)
                        .frame(width: 9, height: 9)
                        .offset(x: p.x - 4.5, y: p.y - 4.5)
                }
            }
            .frame(height: 96)
            .accessibilityElement()
            .accessibilityLabel("Daily calories, \(range.title)")
            .accessibilityValue(Self.summary(trend, range: range))
            .accessibilityChartDescriptor(CalorieTrendChartDescriptor(trend: trend, range: range))
    }

    private var rangePicker: some View {
        HStack(spacing: 0) {
            ForEach(CalorieTrendRange.allCases) { r in
                let on = r == range
                Button { range = r } label: {
                    Text(r.title)
                        .font(.footnote.weight(.medium))
                        .foregroundStyle(on ? Color.labelPrimary : Color.labelSecondary)
                        .frame(maxWidth: .infinity, minHeight: 32)
                        .contentShape(Rectangle())
                        .animation(.easeOut(duration: 0.2), value: on)
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(on ? .isSelected : [])
            }
        }
        .padding(3)
        .background(alignment: .leading) {
            GeometryReader { geo in
                let w = (geo.size.width - 6) / CGFloat(CalorieTrendRange.allCases.count)
                Capsule()
                    .fill(Color.surfaceElevated)
                    .overlay(Capsule().strokeBorder(Color.hairline, lineWidth: 0.5))
                    .frame(width: max(0, w), height: max(0, geo.size.height - 6))
                    .offset(x: 3 + model.pill * w, y: 3)
            }
            .allowsHitTesting(false)
            .accessibilityHidden(true)
        }
        .background(Color.surfaceSecondary, in: Capsule())
        .sensoryFeedback(.selection, trigger: range)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Range")
    }

    static func percent(_ v: Double) -> String {
        let r = Int(v.rounded())
        return r == 0 ? "0%" : (r > 0 ? "+\(r)%" : "\u{2212}\(-r)%")
    }

    static func summary(_ t: CalorieTrend, range: CalorieTrendRange) -> String {
        guard let avg = t.average else { return "Nothing logged in the last \(range.title)." }
        var s = "Average \(avg.formatted()) kilocalories a day over the last \(range.title)"
        if let c = t.change {
            let r = Int(c.rounded())
            s += r == 0 ? ", unchanged from the \(range.title) before"
                : ", \(r > 0 ? "up" : "down") \(abs(r)) percent from the \(range.title) before"
        }
        return s + "."
    }
}

// MARK: - Curve

/// Catmull-Rom curve through evenly spaced points (values 0…1, 1 = top), as in the original.
private struct TrendCurve: Shape {
    var points: [Double]
    var closed: Bool

    static func position(of i: Int, in pts: [Double], size: CGSize) -> CGPoint {
        let n = max(pts.count, 2)
        let x = 4 + CGFloat(i) / CGFloat(n - 1) * (size.width - 8)
        let v = pts.indices.contains(i) ? motionClamp(pts[i], -0.05, 1.05) : 0
        return CGPoint(x: x, y: 8 + (1 - CGFloat(v)) * (size.height - 16))
    }

    func path(in rect: CGRect) -> Path {
        var p = Path()
        let xy = points.indices.map { Self.position(of: $0, in: points, size: rect.size) }
        guard let first = xy.first, xy.count > 1 else { return p }
        p.move(to: first)
        for i in 0..<(xy.count - 1) {
            let p0 = i > 0 ? xy[i - 1] : xy[i], p1 = xy[i], p2 = xy[i + 1]
            let p3 = i + 2 < xy.count ? xy[i + 2] : p2
            p.addCurve(to: p2,
                       control1: CGPoint(x: p1.x + (p2.x - p0.x) / 6, y: p1.y + (p2.y - p0.y) / 6),
                       control2: CGPoint(x: p2.x - (p3.x - p1.x) / 6, y: p2.y - (p3.y - p1.y) / 6))
        }
        if closed {
            p.addLine(to: CGPoint(x: xy[xy.count - 1].x, y: rect.height))
            p.addLine(to: CGPoint(x: first.x, y: rect.height))
            p.closeSubpath()
        }
        return p
    }
}

// MARK: - Audio graph

private struct CalorieTrendChartDescriptor: AXChartDescriptorRepresentable {
    let trend: CalorieTrend
    let range: CalorieTrendRange

    func makeChartDescriptor() -> AXChartDescriptor {
        let values = trend.daily.map { Double($0 ?? 0) }
        let top = max(values.max() ?? 0, 1)
        let x = AXCategoricalDataAxisDescriptor(
            title: "Day",
            categoryOrder: trend.daily.indices.map(label))
        let y = AXNumericDataAxisDescriptor(
            title: "Calories", range: 0...top, gridlinePositions: []) { "\(Int($0)) kilocalories" }
        let points = trend.daily.enumerated().compactMap { i, v in
            v.map { AXDataPoint(x: label(i), y: Double($0)) }
        }
        return AXChartDescriptor(
            title: "Daily calories, \(range.title)",
            summary: CalorieTrendCard.summary(trend, range: range),
            xAxis: x, yAxis: y, additionalAxes: [],
            series: [AXDataSeriesDescriptor(name: "Calories", isContinuous: true, dataPoints: points)])
    }

    private func label(_ i: Int) -> String {
        let day = Calendar.current.date(byAdding: .day, value: i, to: trend.start) ?? trend.start
        return day.formatted(.dateTime.month(.abbreviated).day())
    }
}

// MARK: - Engine

@MainActor
@Observable
final class CalorieTrendModel {
    private(set) var points: [Double] = Array(repeating: 0.5, count: CalorieTrend.pointCount)
    private(set) var total: Double = 0
    private(set) var change: Double = 0
    /// Pill position in tabs (0 = first).
    private(set) var pill: Double = 0

    @ObservationIgnored private var pts = (0..<CalorieTrend.pointCount).map { _ in MotionSpring(0.5, 200, 17) }
    @ObservationIgnored private var val = MotionSpring(0, 160, 22)
    @ObservationIgnored private var dv = MotionSpring(0, 160, 22)
    @ObservationIgnored private var px = MotionSpring(0, 380, 30)
    @ObservationIgnored private var generation = 0
    @ObservationIgnored private var pending = 0
    @ObservationIgnored private var shown = false
    @ObservationIgnored private let clock = MotionClock()

    init() {
        clock.frame = { [weak self] dt in self?.frame(dt) }
        clock.render = { [weak self] in self?.render() }
    }

    func show(_ trend: CalorieTrend, range: CalorieTrendRange, animated: Bool) {
        let targets = trend.points
        let index = Double(CalorieTrendRange.allCases.firstIndex(of: range) ?? 0)
        let avg = Double(trend.average ?? 0), ch = trend.change ?? 0
        if !animated || !shown {
            shown = true
            for k in pts.indices { pts[k].snap(targets[k]) }
            val.snap(avg); dv.snap(ch); px.snap(index)
            render()
            return
        }
        generation += 1
        val.t = avg; dv.t = ch; px.t = index
        clock.cancelAllTimers()
        pending = 0
        if MotionSettings.reduceMotion {
            for k in pts.indices { pts[k].t = targets[k] }
        } else {
            let gen = generation
            for k in pts.indices {
                pending += 1
                clock.after(Double(k) * 0.03) { [weak self] in
                    guard let self else { return }
                    self.pending -= 1
                    if self.generation == gen { self.pts[k].t = targets[k] }
                }
            }
        }
        clock.start()
    }

    func stop() {
        clock.stop()
        clock.cancelAllTimers()
        pending = 0
        for k in pts.indices { pts[k].snap(pts[k].t) }
        val.snap(val.t); dv.snap(dv.t); px.snap(px.t)
        render()
    }

    private func frame(_ dt: Double) {
        for k in pts.indices { pts[k].step(dt) }
        val.step(dt); dv.step(dt); px.step(dt)
    }

    private func render() {
        // Write only what changed, so a settled value doesn't invalidate the view.
        if pts.indices.contains(where: { pts[$0].x != points[$0] }) { points = pts.map(\.x) }
        if total != val.x { total = val.x }
        if change != dv.x { change = dv.x }
        if pill != px.x { pill = px.x }
        // `val` is kcal and `dv` is percent: settle them within a visible step, not 0.001.
        if clock.isRunning, pending == 0, val.isSettled(within: 0.5), dv.isSettled(within: 0.05), px.isSettled,
           pts.allSatisfy({ $0.isSettled }) {
            stop()
        }
    }
}

// MARK: - Preview

#Preview("Calorie Trend Card") {
    let cal = Calendar.current
    let kcal = [1820, 2140, 1960, 2310, 1750, 2050, 1890, 2200, 1980, 2120, 1700, 2400, 1900, 2050,
                1850, 1990, 2260, 2010, 1780, 2150, 1930, 2080, 2290, 1870, 2000, 1950, 2170, 1820,
                2060, 1910, 2230, 1880, 2020, 1960, 2140, 1790, 2090, 1940, 2180, 1860]
    let entries = kcal.enumerated().compactMap { i, k -> FoodLogEntry? in
        guard i % 6 != 3, let day = cal.date(byAdding: .day, value: -i, to: Date()) else { return nil }
        return FoodLogEntry(name: "Lunch", slot: .lunch, servingG: 300, calories: k,
                            proteinG: 30, carbsG: 60, fatG: 20, loggedAt: day)
    }
    VStack(spacing: 24) {
        CalorieTrendCard(entries: entries)
        CalorieTrendCard(entries: Array(entries.prefix(1)))
    }
    .padding(20)
    .background(Color.surfaceGrouped)
}
