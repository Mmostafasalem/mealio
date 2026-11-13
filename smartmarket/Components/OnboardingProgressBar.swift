import SwiftUI

/// 5-step progress indicator shown at the top of every onboarding screen.
///
/// Port of designbookmark.com/motion "Step Progress" (step-progress/steps.js).
/// The line's length is a spring toward the current step. Each step has a fill
/// spring (dull pink when done), a check that draws itself, and a pop when it
/// becomes current. Every onboarding screen creates its own bar, so on appear
/// it starts from the previous step and moves on to `currentStep`.
struct OnboardingProgressBar: View {

    let currentStep: Int   // 1-indexed, 1...5
    let totalSteps = 5

    @State private var model = StepProgressModel(count: 5)
    @ScaledMetric(relativeTo: .caption2) private var dotSize: CGFloat = 28

    var body: some View {
        VStack(spacing: 10) {
            GeometryReader { g in
                track(width: g.size.width)
            }
            .frame(height: dot)
            .padding(.horizontal, 24)
        }
        .padding(.top, 8)
        .onAppear { model.appear(at: currentStep - 1) }
        .onChange(of: currentStep) { _, step in model.go(step - 1) }
        .onDisappear { model.stop() }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Setup progress")
        .accessibilityValue("Step \(min(max(currentStep, 1), totalSteps)) of \(totalSteps)")
    }

    private var dot: CGFloat { min(dotSize, 40) }

    private func track(width: CGFloat) -> some View {
        let r = dot / 2
        let span = max(0, width - dot)
        return ZStack(alignment: .leading) {
            Capsule()
                .fill(Color.surfaceSecondary)
                .frame(width: span, height: 4)
                .offset(x: r)
            Capsule()
                .fill(Color.dullPink)
                .frame(width: span * model.line, height: 4)
                .offset(x: r)
            ForEach(0..<totalSteps, id: \.self) { k in
                StepDot(number: k + 1, state: model.steps[k], size: dot)
                    .offset(x: span * CGFloat(k) / CGFloat(totalSteps - 1))
            }
        }
        .frame(width: width, height: dot, alignment: .leading)
    }
}

private struct StepDot: View {
    let number: Int
    let state: StepProgressModel.StepState
    let size: CGFloat

    var body: some View {
        ZStack {
            Circle().fill(Color.surfaceSecondary)
            Circle().fill(Color.surface).opacity(state.current * (1 - state.fill))
            Circle().strokeBorder(Color.brandPrimary, lineWidth: 2).opacity(state.current * (1 - state.fill))
            Circle().fill(Color.dullPink).opacity(state.fill)
            Text("\(number)")
                .font(.caption2.weight(.bold))
                .foregroundStyle(state.current > 0.5 ? Color.brandPrimary : Color.labelSecondary)
                .opacity(1 - state.fill)
                .minimumScaleFactor(0.6)
            StepCheckShape()
                .trim(from: 0, to: state.check)
                .stroke(Color.onAccent, style: StrokeStyle(lineWidth: 2.8 * size / 32, lineCap: .round, lineJoin: .round))
                .frame(width: size / 2, height: size / 2)
        }
        .frame(width: size, height: size)
        .scaleEffect(state.pop)
    }
}

/// "M5 12.5 l4.5 4.5 L19 7.5" in a 24×24 box.
private struct StepCheckShape: Shape {
    func path(in rect: CGRect) -> Path {
        let s = min(rect.width, rect.height) / 24
        let o = CGPoint(x: rect.midX - 12 * s, y: rect.midY - 12 * s)
        var p = Path()
        p.move(to: CGPoint(x: o.x + 5 * s, y: o.y + 12.5 * s))
        p.addLine(to: CGPoint(x: o.x + 9.5 * s, y: o.y + 17 * s))
        p.addLine(to: CGPoint(x: o.x + 19 * s, y: o.y + 7.5 * s))
        return p
    }
}

// MARK: - Engine

@Observable
final class StepProgressModel {
    struct StepState: Equatable {
        var fill: Double = 0
        var check: Double = 0
        var pop: Double = 1
        var current: Double = 0
    }

    private struct Springs {
        var f = MotionSpring(0, 260, 24)    // fill (done)
        var c = MotionSpring(0, 140, 20)    // check draw
        var p = MotionSpring(1, 500, 14)    // pop
        var on = MotionSpring(0, 300, 26)   // current
    }

    private(set) var line: Double = 0
    private(set) var steps: [StepState]

    @ObservationIgnored private let count: Int
    @ObservationIgnored private var L = MotionSpring(0, 160, 22)
    @ObservationIgnored private var s: [Springs]
    @ObservationIgnored private var cur = -1
    @ObservationIgnored private var checkTimers: [Int: Int] = [:]
    @ObservationIgnored private let clock = MotionClock()

    init(count: Int) {
        self.count = count
        steps = Array(repeating: StepState(), count: count)
        s = Array(repeating: Springs(), count: count)
        clock.frame = { [weak self] dt in self?.frame(dt) }
        clock.render = { [weak self] in self?.render() }
    }

    /// Show the previous step at rest, then move on to `index`.
    func appear(at index: Int) {
        let i = Int(motionClamp(Double(index), 0, Double(count - 1)))
        if MotionSettings.reduceMotion {
            go(i)
            settleAll()
            return
        }
        if i > 0 {
            go(i - 1)
            settleAll()
            s[i - 1].p.snap(1)
            render()
        }
        go(i)
    }

    func go(_ index: Int) {
        let i = Int(motionClamp(Double(index), 0, Double(count - 1)))
        guard i != cur else { return }
        cur = i
        L.t = Double(i) / Double(count - 1)
        for k in 0..<count {
            let done = k < i
            s[k].f.t = done ? 1 : 0
            s[k].on.t = k == i ? 1 : 0
            if let token = checkTimers.removeValue(forKey: k) { clock.cancel(token) }
            if done {
                if s[k].c.t != 1 {
                    checkTimers[k] = clock.after(0.12) { [weak self] in
                        self?.checkTimers[k] = nil
                        self?.s[k].c.t = 1
                    }
                }
            } else {
                s[k].c.t = 0
            }
        }
        if !MotionSettings.reduceMotion {
            s[i].p.x = 0.7
            s[i].p.v = 6
        }
        clock.start()
    }

    func stop() {
        settleAll()
        clock.stop()
    }

    private func settleAll() {
        clock.cancelAllTimers(); checkTimers.removeAll()
        L.snap(L.t)
        for k in 0..<count {
            s[k].f.snap(s[k].f.t)
            s[k].c.snap(s[k].f.t)
            s[k].p.snap(1)
            s[k].on.snap(s[k].on.t)
        }
        render()
    }

    private func frame(_ dt: Double) {
        L.step(dt)
        for k in 0..<count {
            s[k].f.step(dt); s[k].c.step(dt); s[k].p.step(dt); s[k].on.step(dt)
        }
    }

    private func render() {
        let nextLine = motionClamp(L.x, 0, 1)
        if line != nextLine { line = nextLine }
        var next = steps
        var settled = L.isSettled
        for k in 0..<count {
            next[k] = StepState(
                fill: motionClamp(s[k].f.x, 0, 1),
                check: motionClamp(s[k].c.x, 0, 1),
                pop: s[k].p.x,
                current: motionClamp(s[k].on.x, 0, 1)
            )
            settled = settled && s[k].f.isSettled && s[k].c.isSettled && s[k].p.isSettled && s[k].on.isSettled
        }
        // Write only on change, so a resting bar doesn't invalidate every dot.
        if next != steps { steps = next }
        if clock.isRunning, settled, checkTimers.isEmpty {
            clock.stop()
        }
    }
}

#Preview {
    VStack(spacing: 24) {
        ForEach(1...5, id: \.self) { step in
            OnboardingProgressBar(currentStep: step)
        }
    }
    .padding()
    .background(Color.surface)
}
