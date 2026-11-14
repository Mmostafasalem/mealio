import SwiftUI

// MARK: - Spring dropdown
//
// Port of designbookmark.com/motion "Spring Dropdown" (spring-dropdown/dropdown.js).
// The menu's height is a spring (300 23), so it drops with a slight overshoot while
// the whole control lifts by half that height (260 24) and stays centred on where
// it was. Rows fall in one after another (300 24, 45 ms apart; they fold away in
// reverse, 20 ms apart). The highlight under the finger has a stiff leading edge
// (620 36) and a soft trailing one (200 20), so it stretches between rows while
// you drag. Picking a row draws its check (260 26), rolls the new value up into the
// trigger (340 26) and folds the menu away 0.24 s later. No autoplay, no keyboard
// shortcuts.
//
// Accessibility: the whole control is represented as a Picker, so VoiceOver and
// UI tests see a normal menu picker. Reduce Motion: every spring is critically
// damped by the engine (no overshoot), and the rows still fade in.

struct SpringDropdown<Value: Hashable>: View {
    let title: String
    @Binding var selection: Value
    let options: [Value]
    let label: (Value) -> String
    var systemImage: ((Value) -> String)? = nil
    var accessibilityIdentifier: String? = nil

    @State private var model = SpringDropdownModel()
    @ScaledMetric(relativeTo: .body) private var row: CGFloat = 44
    @ScaledMetric(relativeTo: .body) private var triggerHeight: CGFloat = 52

    private static var pad: CGFloat { 6 }
    private static var gap: CGFloat { 8 }
    private var menuHeight: CGFloat { Self.pad * 2 + row * CGFloat(options.count) }
    private var selectedIndex: Int { options.firstIndex(of: selection) ?? 0 }

    var body: some View {
        trigger
            .overlay(alignment: .top) {
                if model.menuVisible { menu.offset(y: triggerHeight + Self.gap) }
            }
            .background {
                // A tap anywhere else closes it.
                if model.isOpen {
                    Color.clear
                        .frame(width: 4000, height: 4000)
                        .contentShape(Rectangle())
                        .onTapGesture { model.setOpen(false) }
                }
            }
            .offset(y: model.lift)
            .zIndex(model.menuVisible ? 10 : 0)
            .onAppear {
                model.configure(count: options.count, selected: selectedIndex,
                                row: Double(row), pad: Double(Self.pad), gap: Double(Self.gap))
            }
            .onChange(of: row) { _, r in
                model.configure(count: options.count, selected: selectedIndex,
                                row: Double(r), pad: Double(Self.pad), gap: Double(Self.gap))
            }
            .onChange(of: selection) { _, v in
                if let i = options.firstIndex(of: v) { model.show(i) }
            }
            .onDisappear { model.stop() }
            .sensoryFeedback(.selection, trigger: selection)
            .accessibilityRepresentation {
                Picker(title, selection: $selection) {
                    ForEach(options, id: \.self) { Text(label($0)).tag($0) }
                }
                .pickerStyle(.menu)
            }
            .accessibilityIdentifier(accessibilityIdentifier ?? "springDropdown")
    }

    // MARK: Trigger

    private var trigger: some View {
        Button {
            model.press()
            model.setOpen(!model.isOpen)
        } label: {
            HStack(spacing: 10) {
                ZStack(alignment: .leading) {
                    // The widest value reserves the width.
                    ForEach(options, id: \.self) { valueLabel($0).hidden() }
                    slot(model.slots[0], roll: model.front == 0 ? model.roll : 1 - model.roll, incoming: model.front == 0)
                    slot(model.slots[1], roll: model.front == 1 ? model.roll : 1 - model.roll, incoming: model.front == 1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .frame(height: triggerHeight)
                .clipped()
                Image(systemName: "chevron.down")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.labelSecondary)
                    .rotationEffect(.degrees(180 * model.chevron))
            }
            .padding(.leading, 16)
            .padding(.trailing, 14)
            .frame(height: triggerHeight)
            .background(Color.surfaceSecondary, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .scaleEffect(model.triggerScale)
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func slot(_ index: Int?, roll r: Double, incoming: Bool) -> some View {
        if let index, options.indices.contains(index) {
            valueLabel(options[index])
                .opacity(motionClamp(r, 0, 1))
                // The incoming value comes up from below, the outgoing one leaves upward.
                .offset(y: incoming ? (1 - r) * 20 : -(1 - r) * 20)
        }
    }

    private func valueLabel(_ value: Value) -> some View {
        HStack(spacing: 10) {
            if let systemImage {
                Image(systemName: systemImage(value))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.labelSecondary)
                    .frame(width: 22)
            }
            Text(label(value))
                .font(.body.weight(.medium))
                .foregroundStyle(Color.labelPrimary)
                .lineLimit(1)
        }
    }

    // MARK: Menu

    private var menu: some View {
        let h = max(0, model.height)
        let full = menuHeight
        return ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.surfaceSecondary)
                .frame(height: max(0, model.highlightBottom - model.highlightTop))
                .offset(y: model.highlightTop - Self.pad)
                .opacity(model.highlightOpacity)
            VStack(spacing: 0) {
                ForEach(Array(options.enumerated()), id: \.offset) { i, value in
                    HStack(spacing: 10) {
                        valueLabel(value)
                        Spacer(minLength: 8)
                        DropdownCheck()
                            .trim(from: 0, to: motionClamp(model.check(i), 0, 1))
                            .stroke(Color.labelPrimary, style: StrokeStyle(lineWidth: 2.2, lineCap: .round, lineJoin: .round))
                            .frame(width: 18, height: 18)
                    }
                    .padding(.leading, 12)
                    .padding(.trailing, 10)
                    .frame(height: row)
                    .opacity(motionClamp(model.rowIn(i), 0, 1))
                    .offset(y: (model.rowIn(i) - 1) * 14)
                }
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { g in model.hover(index(at: g.location.y)) }
                    .onEnded { g in
                        guard g.location.y >= -8, g.location.y <= row * CGFloat(options.count) + 8 else { return }
                        pick(index(at: g.location.y))
                    }
            )
        }
        .padding(Self.pad)
        .frame(height: full, alignment: .top)
        .frame(height: h, alignment: .top)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .background(Color.surfaceElevated, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .elevation(Elevation.high)
        .scaleEffect(x: 0.9 + 0.1 * motionClamp(Double(h / max(1, full)), 0, 1.06), y: 1, anchor: .top)
        .frame(height: full, alignment: .top)
        .opacity(model.menuOpacity)
        .allowsHitTesting(model.isOpen)
    }

    private func index(at y: CGFloat) -> Int {
        Int(motionClamp(Double(floor(y / row)), 0, Double(options.count - 1)))
    }

    private func pick(_ i: Int) {
        guard model.isOpen, options.indices.contains(i) else { return }
        model.select(i)
        if options[i] != selection { selection = options[i] }
    }
}

/// The check from the original (M5 12.5 l4.5 4.5 L19 7.5 in a 24 box).
private struct DropdownCheck: Shape {
    func path(in rect: CGRect) -> Path {
        let s = min(rect.width, rect.height) / 24
        var p = Path()
        p.move(to: CGPoint(x: 5 * s, y: 12.5 * s))
        p.addLine(to: CGPoint(x: 9.5 * s, y: 17 * s))
        p.addLine(to: CGPoint(x: 19 * s, y: 7.5 * s))
        return p
    }
}

// MARK: - Model (dropdown.js)

@MainActor @Observable
final class SpringDropdownModel {
    private(set) var isOpen = false
    private(set) var menuVisible = false
    private(set) var height: CGFloat = 0
    private(set) var lift: CGFloat = 0
    private(set) var chevron: Double = 0
    private(set) var menuOpacity: Double = 0
    private(set) var triggerScale: Double = 1
    private(set) var roll: Double = 1
    private(set) var front = 0
    private(set) var slots: [Int?] = [0, nil]
    private(set) var highlightTop: CGFloat = 6
    private(set) var highlightBottom: CGFloat = 50
    private(set) var highlightOpacity: Double = 0
    private(set) var rows: [Double] = []
    private(set) var checks: [Double] = []

    @ObservationIgnored private var H = MotionSpring(0, 300, 23)
    @ObservationIgnored private var Y = MotionSpring(0, 260, 24)
    @ObservationIgnored private var C = MotionSpring(0, 300, 18)
    @ObservationIgnored private var O = MotionSpring(0, 400, 34)
    @ObservationIgnored private var TS = MotionSpring(1, 500, 18)
    @ObservationIgnored private var R = MotionSpring(1, 340, 26)
    @ObservationIgnored private var HT = MotionSpring(6, 620, 36)
    @ObservationIgnored private var HB = MotionSpring(50, 620, 36)
    @ObservationIgnored private var HO = MotionSpring(0, 400, 32)
    @ObservationIgnored private var rowS: [MotionSpring] = []
    @ObservationIgnored private var checkS: [MotionSpring] = []
    @ObservationIgnored private var timers: [Int] = []
    /// Timers scheduled and not yet fired (the clock must keep running for them).
    @ObservationIgnored private var pending = 0
    @ObservationIgnored private var sel = 0
    @ObservationIgnored private var hov = -1
    @ObservationIgnored private var row: Double = 44
    @ObservationIgnored private var pad: Double = 6
    @ObservationIgnored private var gap: Double = 8
    @ObservationIgnored private let clock = MotionClock()

    private var menuHeight: Double { pad * 2 + row * Double(rowS.count) }

    init() {
        clock.maxFramesPerSecond = 120   // the highlight follows a finger
        clock.frame = { [weak self] dt in self?.step(dt) }
        clock.render = { [weak self] in self?.render() }
    }

    func rowIn(_ i: Int) -> Double { rows.indices.contains(i) ? rows[i] : 0 }
    func check(_ i: Int) -> Double { checks.indices.contains(i) ? checks[i] : 0 }

    func configure(count: Int, selected: Int, row: Double, pad: Double, gap: Double) {
        self.row = row; self.pad = pad; self.gap = gap
        if rowS.count != count {
            rowS = (0..<count).map { _ in MotionSpring(0, 300, 24) }
            checkS = (0..<count).map { MotionSpring($0 == selected ? 1 : 0, 260, 26) }
            sel = selected
            slots = [selected, nil]; front = 0; R.snap(1)
        }
        if isOpen { H.t = menuHeight; Y.t = -(gap + menuHeight) / 2 }
        render()
    }

    /// Selection changed from outside: roll it in without opening.
    func show(_ i: Int) {
        guard i != sel else { return }
        rollIn(i)
        for k in checkS.indices { checkS[k].t = k == sel ? 1 : 0 }
        clock.start()
    }

    func press() {
        TS.x = 0.965
        clock.start()
    }

    func setOpen(_ o: Bool) {
        guard isOpen != o else { return }
        isOpen = o
        H.t = o ? menuHeight : 0
        Y.t = o ? -(gap + menuHeight) / 2 : 0
        C.t = o ? 1 : 0
        O.t = o ? 1 : 0
        cancelTimers()
        let n = rowS.count
        for i in 0..<n {
            let delay = o ? 0.05 + Double(i) * MotionTokens.stagger : Double(n - 1 - i) * 0.02
            later(delay) { [weak self] in
                guard let self, rowS.indices.contains(i) else { return }
                rowS[i].t = isOpen ? 1 : 0
            }
        }
        if o {
            menuVisible = true
            hover(sel, snap: true)
        } else {
            hov = -1
            HO.t = 0
        }
        clock.start()
    }

    func hover(_ i: Int, snap: Bool = false) {
        guard isOpen, i != hov, i >= 0, i < rowS.count else { return }
        let top = pad + Double(i) * row
        if snap || hov < 0 {
            HT.snap(top); HB.snap(top + row)
        } else {
            let down = i > hov
            if down { HB.tune(620, 36); HT.tune(200, 20) } else { HT.tune(620, 36); HB.tune(200, 20) }
            HT.t = top; HB.t = top + row
        }
        hov = i
        HO.t = 1
        clock.start()
    }

    func select(_ i: Int) {
        guard rowS.indices.contains(i) else { return }
        hover(i)
        if i != sel { rollIn(i) }
        for k in checkS.indices { checkS[k].t = k == sel ? 1 : 0 }
        TS.x = 0.955
        later(0.24) { [weak self] in self?.setOpen(false) }
        clock.start()
    }

    func stop() {
        cancelTimers()
        isOpen = false
        H.snap(0); Y.snap(0); C.snap(0); O.snap(0); HO.snap(0)
        TS.snap(1); R.snap(1)
        for i in rowS.indices { rowS[i].snap(0) }
        for i in checkS.indices { checkS[i].snap(checkS[i].t) }
        render()
        clock.stop()
    }

    private func later(_ seconds: Double, _ fn: @escaping () -> Void) {
        pending += 1
        timers.append(clock.after(seconds) { [weak self] in
            self?.pending -= 1
            fn()
        })
    }

    private func cancelTimers() {
        timers.forEach(clock.cancel)
        timers.removeAll()
        pending = 0
    }

    private func rollIn(_ i: Int) {
        sel = i
        front ^= 1
        slots[front] = i
        R.x = 0; R.v = 0; R.t = 1
    }

    private func step(_ dt: Double) {
        H.step(dt); Y.step(dt); C.step(dt); O.step(dt); TS.step(dt); R.step(dt)
        HT.step(dt); HB.step(dt); HO.step(dt)
        for i in rowS.indices { rowS[i].step(dt) }
        for i in checkS.indices { checkS[i].step(dt) }
    }

    private func render() {
        let mh = menuHeight
        height = CGFloat(max(0, H.x))
        lift = CGFloat(Y.x)
        chevron = C.x
        menuOpacity = motionClamp(O.x, 0, 1)
        triggerScale = TS.x
        roll = R.x
        // Keep the highlight at least 16 pt tall and inside the menu (dropdown.js).
        let ht = motionClamp(min(HT.x, HB.x - 16), pad, mh - pad - 16)
        let hb = motionClamp(HB.x, ht + 16, mh - pad)
        highlightTop = CGFloat(ht)
        highlightBottom = CGFloat(hb)
        highlightOpacity = motionClamp(HO.x, 0, 1) * menuOpacity
        rows = rowS.map(\.x)
        checks = checkS.map(\.x)
        if !isOpen && H.x < 1 && H.isSettled(within: MotionSpring.points) { menuVisible = false }

        guard clock.isRunning, pending == 0, settled else { return }
        if R.t == 1, slots[front ^ 1] != nil { slots[front ^ 1] = nil }
        clock.stop()
    }

    private var settled: Bool {
        let pts = MotionSpring.points
        return H.isSettled(within: pts) && Y.isSettled(within: pts) && C.isSettled && O.isSettled
            && TS.isSettled && R.isSettled && HT.isSettled(within: pts) && HB.isSettled(within: pts) && HO.isSettled
            && rowS.allSatisfy(\.isSettled) && checkS.allSatisfy(\.isSettled)
    }
}

// MARK: - Preview

#Preview("Spring dropdown") {
    @Previewable @State var slot: MealSlot = .lunch
    VStack(spacing: Spacing.lg) {
        Spacer()
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("Meal").font(.headline).foregroundStyle(Color.labelPrimary)
                Text("Logged to \(slot.title)").font(.caption).foregroundStyle(Color.labelSecondary)
            }
            Spacer()
            SpringDropdown(title: "Meal", selection: $slot, options: MealSlot.allCases,
                           label: \.title, systemImage: \.sfSymbol)
                .frame(width: 190)
        }
        .padding(Spacing.lg)
        .background(Color.surface, in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
        .zIndex(1)
        Text("Add to \(slot.title)").font(.footnote).foregroundStyle(Color.labelSecondary)
        Spacer()
    }
    .padding(Spacing.lg)
    .background(Color.surfaceGrouped)
}
