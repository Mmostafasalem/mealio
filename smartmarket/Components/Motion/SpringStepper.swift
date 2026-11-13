import SwiftUI

// MARK: - Number Stepper
//
// Port of designbookmark.com/motion "Number Stepper" (number-stepper/stepper.js).
// A change sets a roll spring back to 1 and lets it settle to 0: the new number
// comes in from below going up (from above going down) while the old one leaves
// the other way. Past the limit the button gets a sideways kick and the number
// a small push the same way, so you feel the wall. No autoplay.
// Tapped many times a row, so the wall springs are nearly unbouncy, and a tap
// during a roll retargets it instead of restarting. Reduce Motion: the number
// crossfades in place and the wall kick is skipped.
//
// Accessibility: the minus and plus stay buttons, and the number itself is an
// adjustable element (swipe up / down in VoiceOver) with the formatted value.

struct SpringStepper: View {
    @Binding var value: Int
    let range: ClosedRange<Int>
    var step: Int = 1
    var format: (Int) -> String = { "\($0)" }
    /// Spoken name of the value, e.g. "Quantity".
    var label: String = "Amount"
    var decrementLabel: String = "Decrease"
    var incrementLabel: String = "Increase"
    var font: Font = .system(.title3, design: .rounded).weight(.bold)

    @State private var model = SpringStepperModel()
    @ScaledMetric(relativeTo: .title3) private var button: CGFloat = 44
    @ScaledMetric(relativeTo: .title3) private var numberHeight: CGFloat = 32
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(value: Binding<Int>, in range: ClosedRange<Int>, step: Int = 1,
         format: @escaping (Int) -> String = { "\($0)" },
         label: String = "Amount",
         decrementLabel: String = "Decrease",
         incrementLabel: String = "Increase",
         font: Font = .system(.title3, design: .rounded).weight(.bold)) {
        _value = value
        self.range = range
        self.step = max(1, step)
        self.format = format
        self.label = label
        self.decrementLabel = decrementLabel
        self.incrementLabel = incrementLabel
        self.font = font
    }

    var body: some View {
        HStack(spacing: 6) {
            stepButton(-1, symbol: "minus", label: decrementLabel, kick: model.kickMinus)
            number
            stepButton(1, symbol: "plus", label: incrementLabel, kick: model.kickPlus)
        }
        .sensoryFeedback(.selection, trigger: value)
        .onAppear { model.set(value, animated: false) }
        .onChange(of: value) { _, v in model.set(v, animated: true) }
        .onDisappear { model.stop() }
    }

    private func change(_ d: Int) {
        let next = value + d * step
        guard range.contains(next) else {
            model.kick(d)
            return
        }
        value = next
    }

    private func atLimit(_ d: Int) -> Bool { !range.contains(value + d * step) }

    private func stepButton(_ d: Int, symbol: String, label: String, kick: Double) -> some View {
        Button { change(d) } label: {
            Image(systemName: symbol)
                .font(.system(size: button * 0.4, weight: .semibold))
                .foregroundStyle(Color.brandPrimary)
                .frame(width: button, height: button)
                .background(Color.surfaceSecondary, in: Circle())
                .opacity(atLimit(d) ? 0.4 : 1)
                .contentShape(Circle())
        }
        // Stays tappable at the limit so the kick can answer "no".
        .buttonStyle(ScalePressStyle())
        .offset(x: kick)
        .accessibilityLabel(label)
    }

    private var number: some View {
        let r = model.roll
        // Reduce Motion: crossfade only, no vertical slide.
        let dir = reduceMotion ? 0 : Double(model.direction)
        return ZStack {
            // Widest values reserve the width so the buttons never shift.
            Text(format(range.lowerBound)).hidden()
            Text(format(range.upperBound)).hidden()
            Text(model.previous.map(format) ?? "")
                .offset(y: (r - 1) * dir * numberHeight)
                .opacity(motionClamp(r, 0, 1))
            Text(format(model.current ?? value))
                .offset(y: dir * r * numberHeight)
                .opacity(motionClamp(1 - abs(r), 0, 1))
        }
        .font(font)
        .monospacedDigit()
        .foregroundStyle(Color.labelPrimary)
        .lineLimit(1)
        .padding(.horizontal, 2)
        .frame(minWidth: 40)
        .frame(height: numberHeight)
        .clipped()
        .offset(x: model.nudge)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label)
        .accessibilityValue(format(value))
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: change(1)
            case .decrement: change(-1)
            @unknown default: break
            }
        }
    }
}

@Observable
final class SpringStepperModel {
    private(set) var roll: Double = 0
    private(set) var direction = 1
    private(set) var current: Int?
    private(set) var previous: Int?
    private(set) var kickMinus: Double = 0
    private(set) var kickPlus: Double = 0
    private(set) var nudge: Double = 0

    @ObservationIgnored private var r = MotionSpring(0, 260, 24)    // roll
    @ObservationIgnored private var km = MotionSpring(0, 600, 30)   // minus kick
    @ObservationIgnored private var kp = MotionSpring(0, 600, 30)   // plus kick
    @ObservationIgnored private var nn = MotionSpring(0, 500, 28)   // number push
    @ObservationIgnored private let clock = MotionClock()

    // The original maps these springs to px with ×0.06 and ×0.04, which comes out
    // under a point on screen; these keep the same curves but make the wall readable.
    private static let kickScale = 0.6
    private static let nudgeScale = 0.4

    init() {
        clock.frame = { [weak self] dt in self?.frame(dt) }
        clock.render = { [weak self] in self?.render() }
    }

    func set(_ value: Int, animated: Bool) {
        guard value != current else { return }
        guard animated, let old = current else {
            current = value; previous = nil
            r.snap(0); render()
            return
        }
        let dir = value > old ? 1 : -1
        if previous != nil, !r.isSettled {
            // A change mid-roll retargets the roll instead of restarting it, so
            // nothing on screen jumps out.
            if dir != direction {
                // Reversing: the incoming number becomes the outgoing one and the
                // outgoing one (usually the value we're going back to) the incoming,
                // mirrored so both stay exactly where they are.
                previous = old
                r.x = 1 - r.x; r.v = -r.v
            } else if r.x >= 0.5 {
                // The outgoing number still holds the slot: keep it, and swap only
                // the faint incoming one for the new value; the roll keeps going
                // from where it is.
            } else {
                // The incoming number has mostly arrived: it becomes the outgoing
                // one and the new value starts its way in. Keep the velocity.
                previous = old
                r.x = min(1, r.x + 1)
            }
            current = value
            direction = dir
        } else {
            previous = old
            current = value
            direction = dir
            r.x = 1; r.v = 0
        }
        clock.start()
    }

    /// Past the limit: the pressed side's button kicks, the number pushes the same way.
    func kick(_ d: Int) {
        // Purely decorative, so Reduce Motion skips it.
        guard !MotionSettings.reduceMotion else { return }
        if d < 0 { km.v = -300 } else { kp.v = 300 }
        nn.v = 160 * Double(d)
        clock.start()
    }

    func stop() {
        r.snap(0); km.snap(0); kp.snap(0); nn.snap(0)
        render()
        clock.stop()
    }

    private func frame(_ dt: Double) {
        r.step(dt); km.step(dt); kp.step(dt); nn.step(dt)
    }

    private func render() {
        roll = r.x
        kickMinus = km.x * Self.kickScale
        kickPlus = kp.x * Self.kickScale
        nudge = nn.x * Self.nudgeScale
        // The kick springs are measured in pre-scale points.
        let kickEps = MotionSpring.points / Self.kickScale, nudgeEps = MotionSpring.points / Self.nudgeScale
        if clock.isRunning, r.isSettled, km.isSettled(within: kickEps), kp.isSettled(within: kickEps),
           nn.isSettled(within: nudgeEps) {
            r.snap(0); km.snap(0); kp.snap(0); nn.snap(0)
            roll = 0; kickMinus = 0; kickPlus = 0; nudge = 0
            previous = nil
            clock.stop()
        }
    }
}

// MARK: - Preview

#Preview("Number Stepper") {
    @Previewable @State var portions = 2
    @Previewable @State var quarters = 4
    VStack(spacing: Spacing.lg) {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("Portions").font(.headline).foregroundStyle(Color.labelPrimary)
                Text("Up to 8 per meal").font(.caption).foregroundStyle(Color.labelSecondary)
            }
            Spacer()
            SpringStepper(value: $portions, in: 1...8, label: "Portions")
        }
        HStack {
            Text("Serving").font(.headline).foregroundStyle(Color.labelPrimary)
            Spacer()
            SpringStepper(value: $quarters, in: 1...80,
                          format: { (Double($0) / 4).formatted(.number.precision(.fractionLength(0...2))) },
                          label: "Number of servings")
        }
    }
    .padding(Spacing.lg)
    .background(Color.surface, in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
    .padding(Spacing.lg)
    .background(Color.surfaceGrouped)
}
