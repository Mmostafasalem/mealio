import SwiftUI

// MARK: - Checkbox List
//
// Port of designbookmark.com/motion "Checkbox List" (checkbox-list/check.js).
// Each row has a fill spring (the box fills with dull pink), a pop spring, a
// check that draws itself a moment later, and a strike line that runs under
// the text from the left while the text dims. `RollingNumber` is the count
// above the list, rolling on digit columns. No autoplay: rows only move when
// `isOn` changes.

/// A tappable checklist row: animated box, struck-through title, optional
/// detail line under the title and trailing content (a price, a badge).
struct AnimatedCheckRow<Detail: View, Trailing: View>: View {
    let title: String
    let isOn: Bool
    let action: () -> Void
    /// Spoken state, e.g. ("Bought", "Not bought").
    var stateLabels: (on: String, off: String) = ("Done", "Not done")
    /// Extra spoken detail after the state (quantity, price).
    var accessibilityDetail: String? = nil
    @ViewBuilder var detail: () -> Detail
    @ViewBuilder var trailing: () -> Trailing

    @State private var model = AnimatedCheckModel()
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        Button(action: action) {
            HStack(spacing: Spacing.md) {
                AnimatedCheckBox(model: model)
                VStack(alignment: .leading, spacing: 2) {
                    titleText
                    detail()
                }
                Spacer(minLength: Spacing.sm)
                trailing()
            }
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .sensoryFeedback(.selection, trigger: isOn)
        .accessibilityLabel(title)
        .accessibilityValue([isOn ? stateLabels.on : stateLabels.off, accessibilityDetail].compactMap { $0 }.joined(separator: ", "))
        .accessibilityAddTraits(isOn ? .isSelected : [])
        .onAppear { model.set(isOn, animated: false) }
        .onChange(of: isOn) { _, on in model.set(on, animated: true) }
        .onDisappear { model.stop() }
    }

    @ViewBuilder private var titleText: some View {
        let text = Text(title)
            .font(.subheadline).fontWeight(.medium)
            .foregroundStyle(isOn ? Color.labelSecondary : Color.labelPrimary)
            .animation(.easeOut(duration: 0.2), value: isOn)
        if dynamicTypeSize.isAccessibilitySize {
            // Wrapped text: a single drawn line can't follow every line, use the native strike.
            text.strikethrough(isOn, color: .labelSecondary)
        } else {
            text
                .lineLimit(1)
                .overlay(alignment: .leading) {
                    GeometryReader { g in
                        let w = g.size.width * model.strike
                        Capsule()
                            .fill(Color.labelSecondary)
                            .frame(width: w, height: 1.5)
                            .position(x: w / 2, y: g.size.height / 2)
                    }
                    .allowsHitTesting(false)
                }
        }
    }
}

extension AnimatedCheckRow where Trailing == EmptyView {
    init(title: String, isOn: Bool, action: @escaping () -> Void,
         stateLabels: (on: String, off: String) = ("Done", "Not done"),
         accessibilityDetail: String? = nil,
         @ViewBuilder detail: @escaping () -> Detail) {
        self.init(title: title, isOn: isOn, action: action, stateLabels: stateLabels,
                  accessibilityDetail: accessibilityDetail, detail: detail, trailing: { EmptyView() })
    }
}

/// The 24-pt box: fills, pops and draws its check from the row's model.
private struct AnimatedCheckBox: View {
    let model: AnimatedCheckModel
    @ScaledMetric(relativeTo: .subheadline) private var side: CGFloat = 24

    var body: some View {
        let unit = side / 24
        let shape = RoundedRectangle(cornerRadius: 8 * unit, style: .continuous)
        ZStack {
            shape.fill(Color.labelPrimary.opacity(0.14))
            shape.fill(Color.dullPink).opacity(model.fill)
            // The original's 16-px svg (24 viewBox) inside the 24-px box.
            CheckBoxPath()
                .trim(from: 0, to: model.check)
                .stroke(Color.onAccent, style: StrokeStyle(lineWidth: 2.8 * 16 / 24 * unit, lineCap: .round, lineJoin: .round))
                .frame(width: 16 * unit, height: 16 * unit)
        }
        .frame(width: side, height: side)
        .scaleEffect(model.pop)
        .accessibilityHidden(true)
    }
}

/// "M6 12.5 l4 4 L18 8" in a 24×24 box.
private struct CheckBoxPath: Shape {
    func path(in rect: CGRect) -> Path {
        let s = min(rect.width, rect.height) / 24
        let o = CGPoint(x: rect.midX - 12 * s, y: rect.midY - 12 * s)
        var p = Path()
        p.move(to: CGPoint(x: o.x + 6 * s, y: o.y + 12.5 * s))
        p.addLine(to: CGPoint(x: o.x + 10 * s, y: o.y + 16.5 * s))
        p.addLine(to: CGPoint(x: o.x + 18 * s, y: o.y + 8 * s))
        return p
    }
}

@Observable
final class AnimatedCheckModel {
    private(set) var fill: Double = 0
    private(set) var pop: Double = 1
    private(set) var check: Double = 0
    private(set) var strike: Double = 0

    @ObservationIgnored private var f = MotionSpring(0, 300, 24)   // box fill
    // Ticked tens of times a day: a quick, nearly unbouncy pop.
    @ObservationIgnored private var p = MotionSpring(1, 520, 30)   // pop
    @ObservationIgnored private var c = MotionSpring(0, 160, 20)   // check draw
    @ObservationIgnored private var k = MotionSpring(0, 140, 22)   // strike
    @ObservationIgnored private var on: Bool?
    @ObservationIgnored private var timers: [Int] = []
    @ObservationIgnored private let clock = MotionClock()

    init() {
        clock.frame = { [weak self] dt in self?.frame(dt) }
        clock.render = { [weak self] in self?.render() }
    }

    func set(_ isOn: Bool, animated: Bool) {
        guard isOn != on else { return }
        let first = on == nil
        on = isOn
        timers.forEach(clock.cancel); timers = []
        if !animated || first {
            let v: Double = isOn ? 1 : 0
            f.snap(v); p.snap(1); c.snap(v); k.snap(v)
            render()
            clock.stop()
            return
        }
        f.t = isOn ? 1 : 0
        if !MotionSettings.reduceMotion {
            // The pop is decorative: skip it with Reduce Motion. Add to the
            // current motion instead of restarting it, so a fast check-uncheck
            // never jumps; only a box at rest dips first.
            if p.isSettled && p.x == 1 { p.x = isOn ? 0.9 : 0.95 }
            p.v += 3
            p.t = 1
        }
        if isOn {
            timers.append(clock.after(0.08) { [weak self] in if self?.on == true { self?.c.t = 1 } })
            timers.append(clock.after(0.16) { [weak self] in if self?.on == true { self?.k.t = 1 } })
        } else {
            c.t = 0; k.t = 0
        }
        clock.start()
    }

    func stop() {
        clock.cancelAllTimers(); timers = []
        if let on {
            let v: Double = on ? 1 : 0
            f.snap(v); p.snap(1); c.snap(v); k.snap(v)
            render()
        }
        clock.stop()
    }

    private func frame(_ dt: Double) {
        f.step(dt); p.step(dt); c.step(dt); k.step(dt)
    }

    private func render() {
        fill = motionClamp(f.x, 0, 1)
        pop = p.x
        check = motionClamp(c.x, 0, 1)
        strike = motionClamp(k.x, 0, 1)
        // Drop timers that already fired (they're removed from the clock when due).
        if clock.isRunning, f.isSettled, p.isSettled, c.isSettled, k.isSettled,
           // Pending check/strike timers still need the clock.
           c.t == (on == true ? 1 : 0), k.t == (on == true ? 1 : 0) {
            f.snap(f.t); p.snap(p.t); c.snap(c.t); k.snap(k.t)
            fill = f.x; pop = p.x; check = c.x; strike = k.x
            timers = []
            clock.stop()
        }
    }
}

// MARK: - Rolling number

/// An integer that rolls on digit columns (an odometer): each digit slides
/// through its neighbours, and a column only turns when the one to its right
/// carries. New leading digits grow in as the count crosses 9, 99…
/// Uses the surrounding font; pair it with Text for the rest of the phrase.
struct RollingNumber: View {
    let value: Int

    @State private var model = RollingNumberModel()
    @State private var cell: CGSize = .zero
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Group {
            if reduceMotion {
                // Reduce Motion: the number crossfades in place, no vertical roll.
                Text("\(value)")
                    .monospacedDigit()
                    .contentTransition(.opacity)
                    .animation(.easeOut(duration: 0.2), value: value)
            } else {
                odometer
            }
        }
        .accessibilityHidden(true)
        .onAppear { model.set(value, animated: false) }
        .onChange(of: value) { _, v in model.set(v, animated: !reduceMotion) }
        .onDisappear { model.stop() }
    }

    private var odometer: some View {
        let x = model.x
        let columns = max(1, String(max(abs(model.target), Int(max(0, x).rounded(.up)))).count)
        return HStack(spacing: 0) {
            ForEach((0..<columns).reversed(), id: \.self) { place in
                DigitColumn(position: Self.position(x, place: place), cell: cell)
                    .frame(width: cell.width > 0 ? cell.width * Self.visibility(x, place: place) : nil,
                           alignment: .trailing)
                    .opacity(Self.visibility(x, place: place))
            }
        }
        .monospacedDigit()
        .background {
            Text("0").hidden()
                .background(GeometryReader { g in
                    Color.clear
                        .onAppear { cell = g.size }
                        .onChange(of: g.size) { _, s in cell = s }
                })
        }
        .clipped()
    }

    /// Continuous position (0…10, wrapping) of the digit column at `place` (0 = ones).
    static func position(_ x: Double, place: Int) -> Double {
        let p = pow(10, Double(place))
        if place == 0 { return x.truncatingRemainder(dividingBy: 10).wrapped10 }
        let base = (x / p).rounded(.down)
        let below = x - base * p                     // what the lower columns show
        let carry = motionClamp(below - (p - 1), 0, 1) // the last unit before a carry turns this column
        return (base + carry).truncatingRemainder(dividingBy: 10).wrapped10
    }

    /// Leading columns fade and grow in as the count reaches them.
    static func visibility(_ x: Double, place: Int) -> Double {
        guard place > 0 else { return 1 }
        let p = pow(10, Double(place))
        return motionClamp(x - (p - 1), 0, 1)
    }
}

private extension Double {
    var wrapped10: Double { self < 0 ? self + 10 : self }
}

private struct DigitColumn: View {
    let position: Double
    let cell: CGSize

    var body: some View {
        Text("0").hidden()
            .overlay(alignment: .top) {
                VStack(spacing: 0) {
                    // 0…9 then 0 again, so 9 → 0 rolls on without a jump.
                    ForEach(0..<11, id: \.self) { d in
                        Text("\(d % 10)")
                            .frame(height: cell.height > 0 ? cell.height : nil)
                    }
                }
                .fixedSize()
                .offset(y: -cell.height * position)
            }
            .clipped()
    }
}

@Observable
final class RollingNumberModel {
    private(set) var x: Double = 0
    private(set) var target: Int = 0

    @ObservationIgnored private var n = MotionSpring(0, 260, 22)
    @ObservationIgnored private var ready = false
    @ObservationIgnored private let clock = MotionClock()

    init() {
        clock.frame = { [weak self] dt in self?.n.step(dt) }
        clock.render = { [weak self] in self?.render() }
    }

    func set(_ value: Int, animated: Bool) {
        target = value
        if !animated || !ready {
            ready = true
            n.snap(Double(value)); x = n.x
            clock.stop()
            return
        }
        n.t = Double(value)
        clock.start()
    }

    func stop() {
        n.snap(n.t); x = n.x
        clock.stop()
    }

    private func render() {
        x = max(n.x, -0.4)
        if clock.isRunning, n.isSettled {
            n.snap(n.t); x = n.x
            clock.stop()
        }
    }
}

// MARK: - Preview

#Preview("Checkbox List") {
    @Previewable @State var done: Set<Int> = [1]
    let items = [("Milk", "2 × 1 L"), ("Rye bread", "1 loaf"), ("Greek yogurt", "4 × 150 g"), ("Bananas", "1 kg")]
    VStack(alignment: .leading, spacing: Spacing.sm) {
        HStack(alignment: .firstTextBaseline) {
            Text("Rimi").font(.headline).foregroundStyle(Color.labelPrimary)
            Spacer()
            HStack(spacing: 4) {
                RollingNumber(value: done.count).foregroundStyle(Color.labelPrimary).fontWeight(.semibold)
                Text("of \(items.count) bought").foregroundStyle(Color.labelSecondary)
            }
            .font(.footnote)
        }
        ForEach(items.indices, id: \.self) { i in
            AnimatedCheckRow(
                title: items[i].0,
                isOn: done.contains(i),
                action: { if done.contains(i) { done.remove(i) } else { done.insert(i) } },
                stateLabels: ("Bought", "Not bought")
            ) {
                Text(items[i].1).font(.caption).foregroundStyle(Color.labelSecondary)
            } trailing: {
                Text("€1.29").font(.subheadline.monospacedDigit()).foregroundStyle(Color.labelSecondary)
            }
        }
    }
    .padding(Spacing.lg)
    .background(Color.surface, in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
    .padding(Spacing.lg)
    .background(Color.surfaceGrouped)
}
