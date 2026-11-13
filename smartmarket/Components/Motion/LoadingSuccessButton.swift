import SwiftUI
import UIKit

// MARK: - Loading > Success
//
// Port of designbookmark.com/motion "Loading > Success" (loading-success/submit.js).
// Tap: work that returns within 0.15 s goes straight to done (the label crossfades
// to the check + done title). Slower work: the label drops away and the pill
// closes into a circle with a spinner. When the work succeeds the circle opens into a pill tinted toward dull pink,
// the check draws itself and the done title rises in. A moment later
// `onFinished` runs and the button settles back. A failure returns to idle.

struct LoadingSuccessButton: View {
    enum Style {
        /// Rhino fill, almond text: the app's "Add" pill.
        case rhino
        /// Dull pink fill, on-accent text: the PrimaryButton look.
        case dullPink

        var fill: Color { self == .rhino ? .rhino : .dullPink }
        var text: Color { self == .rhino ? .almond : .onAccent }
    }

    let title: String
    let doneTitle: String
    var systemImage: String? = nil
    var style: Style = .rhino
    /// Announced to VoiceOver when `action` returns false.
    var failureMessage: String = "Couldn't add. Try again."
    let action: () async -> Bool
    var onFinished: (() -> Void)? = nil

    @State private var model = LoadingSuccessModel()
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ScaledMetric(relativeTo: .headline) private var height: CGFloat = 52
    @ScaledMetric(relativeTo: .headline) private var checkSide: CGFloat = 22

    init(
        title: String,
        doneTitle: String,
        systemImage: String? = nil,
        style: Style = .rhino,
        failureMessage: String = "Couldn't add. Try again.",
        action: @escaping () async -> Bool,
        onFinished: (() -> Void)? = nil
    ) {
        self.title = title
        self.doneTitle = doneTitle
        self.systemImage = systemImage
        self.style = style
        self.failureMessage = failureMessage
        self.action = action
        self.onFinished = onFinished
    }

    var body: some View {
        Button {
            model.go(
                circle: height, doneTitle: doneTitle, failureMessage: failureMessage,
                action: action, onFinished: onFinished)
        } label: {
            pill
                .frame(maxWidth: .infinity)
                .frame(height: height)
                .contentShape(Rectangle())
                .background {
                    GeometryReader { g in
                        Color.clear
                            .onAppear { model.setFull(g.size.width) }
                            .onChange(of: g.size.width) { _, w in model.setFull(w) }
                    }
                }
        }
        .buttonStyle(ScalePressStyle())
        .disabled(model.state != .idle)
        .accessibilityLabel(model.state == .done ? doneTitle : title)
        .accessibilityValue(accessibilityValue)
        .onAppear { model.appeared() }
        .onDisappear { model.disappeared() }
    }

    private var accessibilityValue: String {
        switch model.state {
        case .idle: return ""
        case .loading: return "In progress"
        case .done: return "Done"
        }
    }

    private var shape: RoundedRectangle { RoundedRectangle(cornerRadius: Radius.pill, style: .continuous) }

    private var pill: some View {
        ZStack {
            shape.fill(style.fill)
            shape.fill(Color.dullPink).opacity(model.green)

            HStack(spacing: Spacing.sm) {
                if let systemImage { Image(systemName: systemImage) }
                Text(title)
            }
            .fixedSize()
            .foregroundStyle(style.text)
            .opacity(model.label)
            // Reduce Motion: a plain crossfade, no slide.
            .offset(y: reduceMotion ? 0 : 14 * (1 - model.labelRaw))

            LoadingSpinner(color: style.text)
                .frame(width: 24, height: 24)
                .scaleEffect(0.6 + 0.4 * model.spinnerScale)
                .rotationEffect(.degrees(model.rotation))
                .opacity(model.spinner)

            HStack(spacing: Spacing.sm) {
                CheckShape()
                    .trim(from: 0, to: model.check)
                    .stroke(Color.onAccent, style: StrokeStyle(lineWidth: 2.6 * checkSide / 24, lineCap: .round, lineJoin: .round))
                    .frame(width: checkSide, height: checkSide)
                Text(doneTitle)
            }
            .fixedSize()
            .foregroundStyle(Color.onAccent)
            .opacity(model.done)
            .offset(y: reduceMotion ? 0 : 12 * (1 - model.doneRaw))
            .background {
                GeometryReader { g in
                    Color.clear
                        .onAppear { model.doneContent = g.size.width }
                        .onChange(of: g.size.width) { _, w in model.doneContent = w }
                }
            }
        }
        .font(.headline)
        .lineLimit(1)
        .frame(width: model.full > 0 ? model.width : nil, height: height)
        .frame(maxWidth: model.full > 0 ? nil : .infinity)
        .clipShape(shape)
    }
}

// MARK: - Pieces

/// 24×24 conic ring spinner, like the original's masked conic-gradient.
private struct LoadingSpinner: View {
    let color: Color
    var body: some View {
        Circle()
            .strokeBorder(
                AngularGradient(
                    stops: [
                        .init(color: color.opacity(0), location: 0),
                        .init(color: color.opacity(0), location: 0.10),
                        .init(color: color, location: 0.85),
                        .init(color: color.opacity(0), location: 0.851),
                        .init(color: color.opacity(0), location: 1),
                    ],
                    center: .center,
                    startAngle: .degrees(-90),
                    endAngle: .degrees(270)
                ),
                lineWidth: 3.6
            )
    }
}

/// "M5 12.5 l4.5 4.5 L19 7.5" in a 24×24 box.
private struct CheckShape: Shape {
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
final class LoadingSuccessModel {
    enum State { case idle, loading, done }

    private(set) var state: State = .idle
    // Published per frame, and only when the value changed.
    private(set) var width: Double = 0
    private(set) var label: Double = 1
    private(set) var labelRaw: Double = 1
    private(set) var spinner: Double = 0
    private(set) var spinnerScale: Double = 0
    private(set) var rotation: Double = 0
    private(set) var done: Double = 0
    private(set) var doneRaw: Double = 0
    private(set) var green: Double = 0
    private(set) var check: Double = 0
    /// Measured container width (the idle pill width).
    private(set) var full: Double = 0
    /// Natural width of the check + done title.
    var doneContent: Double = 0
    @ObservationIgnored var isVisible = false

    @ObservationIgnored private var w = MotionSpring(0, 300, 22)   // width
    @ObservationIgnored private var t = MotionSpring(1, 400, 30)   // label
    @ObservationIgnored private var p = MotionSpring(0, 300, 28)   // spinner
    @ObservationIgnored private var d = MotionSpring(0, 220, 20)   // done label
    @ObservationIgnored private var g = MotionSpring(0, 200, 30)   // colour mix
    @ObservationIgnored private var k = MotionSpring(0, 120, 20)   // check draw
    @ObservationIgnored private var rot: Double = 0
    @ObservationIgnored private var pendingTimers = 0
    @ObservationIgnored private var run: Task<Void, Never>?
    @ObservationIgnored private var spinStart: Task<Void, Never>?
    /// True once the work outlasted `fastPath` and the pill closed into the spinner.
    @ObservationIgnored private var spinning = false
    @ObservationIgnored private var spinBegan: CFTimeInterval = 0
    @ObservationIgnored private var circle: Double = 52
    @ObservationIgnored private var finished: (() -> Void)?
    @ObservationIgnored private let clock = MotionClock()

    /// Work that returns within this long skips the spinner and goes straight to done.
    private static let fastPath: Double = 0.15
    /// Once shown, the spinner stays at least this long so it reads.
    private static let minSpin: Double = 0.6
    /// How long the done pill holds before `onFinished`, after an instant success.
    private static let fastHold: Double = 0.45
    /// How long the done pill holds before `onFinished`, after the spinner.
    private static let slowHold: Double = 0.6

    init() {
        clock.frame = { [weak self] dt in self?.frame(dt) }
        clock.render = { [weak self] in self?.render() }
    }

    func setFull(_ value: Double) {
        guard value > 0, value != full else { return }
        let first = full == 0
        full = value
        if state == .idle || (state == .done && !spinning) {
            if first { w.snap(value) } else { w.t = value; clock.start() }
            if first { render() }
        }
    }

    func go(
        circle: Double,
        doneTitle: String,
        failureMessage: String,
        action: @escaping () async -> Bool,
        onFinished: (() -> Void)?
    ) {
        guard state == .idle else { return }
        state = .loading
        spinning = false
        self.circle = circle
        finished = onFinished
        // Only close into the spinner if the work is genuinely slow.
        spinStart = Task { [weak self] in
            try? await Task.sleep(for: .seconds(Self.fastPath))
            guard let self, !Task.isCancelled, self.state == .loading, self.isVisible else { return }
            self.beginSpin()
        }
        run = Task { [weak self] in
            let ok = await action()
            guard let self else { return }
            self.spinStart?.cancel()
            self.spinStart = nil
            if self.spinning {
                let wait = Self.minSpin - (CACurrentMediaTime() - self.spinBegan)
                if wait > 0 { try? await Task.sleep(for: .seconds(wait)) }
            }
            // Gone from screen: no more motion, but a success must still report.
            guard self.isVisible else {
                self.snapIdle()
                if ok { self.finish() }
                return
            }
            guard ok else { self.fail(message: failureMessage); return }
            let fast = !self.spinning
            self.succeed(doneTitle: doneTitle, fast: fast)
            try? await Task.sleep(for: .seconds(fast ? Self.fastHold : Self.slowHold))
            guard !Task.isCancelled else { return }
            self.finish()
            if self.isVisible { self.reset() } else { self.snapIdle() }
        }
    }

    func appeared() {
        isVisible = true
    }

    func disappeared() {
        isVisible = false
        spinStart?.cancel()
        spinStart = nil
        clock.cancelAllTimers()
        pendingTimers = 0
        clock.stop()
        switch state {
        case .idle:
            break
        case .done:
            // The work already succeeded: report it now instead of after the hold.
            run?.cancel()
            run = nil
            snapIdle()
            finish()
        case .loading:
            // The work is still out; the run task reports when it returns.
            break
        }
    }

    private func finish() {
        let f = finished
        finished = nil
        f?()
    }

    private func beginSpin() {
        spinning = true
        spinBegan = CACurrentMediaTime()
        t.t = 0; w.t = circle; p.t = 1
        clock.start()
    }

    private func succeed(doneTitle: String, fast: Bool) {
        state = .done
        p.t = 0; g.t = 1; d.t = 1; t.t = 0
        if spinning {
            let doneWidth = max(140, doneContent + 48)
            w.t = full > 0 ? min(full, doneWidth) : doneWidth
        } else {
            w.t = full
        }
        later(fast ? 0.08 : 0.15) { [weak self] in self?.k.t = 1 }
        clock.start()
        UIAccessibility.post(notification: .announcement, argument: doneTitle)
    }

    private func fail(message: String) {
        UINotificationFeedbackGenerator().notificationOccurred(.error)
        UIAccessibility.post(notification: .announcement, argument: message)
        reset()
    }

    private func reset() {
        state = .idle
        spinning = false
        d.t = 0; g.t = 0; k.t = 0; p.t = 0
        w.t = full
        later(0.12) { [weak self] in self?.t.t = 1 }
        clock.start()
    }

    private func snapIdle() {
        state = .idle
        spinning = false
        clock.cancelAllTimers(); pendingTimers = 0
        w.snap(full); t.snap(1); p.snap(0); d.snap(0); g.snap(0); k.snap(0)
        render()
        clock.stop()
    }

    private func later(_ seconds: Double, _ fn: @escaping () -> Void) {
        pendingTimers += 1
        clock.after(seconds) { [weak self] in
            self?.pendingTimers -= 1
            fn()
        }
    }

    private func frame(_ dt: Double) {
        rot += dt * 360 * 1.4
        w.step(dt); t.step(dt); p.step(dt); d.step(dt); g.step(dt); k.step(dt)
    }

    private func publish(_ key: ReferenceWritableKeyPath<LoadingSuccessModel, Double>, _ value: Double) {
        if self[keyPath: key] != value { self[keyPath: key] = value }
    }

    private func render() {
        publish(\.width, max(0, w.x))
        publish(\.labelRaw, t.x)
        publish(\.label, motionClamp(t.x, 0, 1))
        publish(\.spinner, motionClamp(p.x, 0, 1))
        publish(\.spinnerScale, motionClamp(p.x, 0, 1.2))
        // The ring only needs to turn while it can be seen.
        if p.x > 0.001 { publish(\.rotation, rot.truncatingRemainder(dividingBy: 360)) }
        publish(\.doneRaw, d.x)
        publish(\.done, motionClamp(d.x, 0, 1))
        publish(\.green, motionClamp(g.x, 0, 1))
        publish(\.check, motionClamp(k.x, 0, 1))

        let settled = w.isSettled(within: MotionSpring.points)
            && t.isSettled && p.isSettled && d.isSettled && g.isSettled && k.isSettled
        if clock.isRunning, settled, pendingTimers == 0, !(state == .loading && spinning) {
            w.snap(w.t); t.snap(t.t); p.snap(p.t); d.snap(d.t); g.snap(g.t); k.snap(k.t)
            publish(\.width, max(0, w.x)); publish(\.label, t.x); publish(\.labelRaw, t.x)
            publish(\.spinner, p.x); publish(\.spinnerScale, p.x)
            publish(\.done, d.x); publish(\.doneRaw, d.x); publish(\.green, g.x); publish(\.check, k.x)
            clock.stop()
        }
    }
}

// MARK: - Preview

#Preview("Loading > Success") {
    VStack(spacing: 24) {
        LoadingSuccessButton(title: "Add to Lunch", doneTitle: "Added", systemImage: "plus") {
            try? await Task.sleep(for: .seconds(1))
            return true
        }
        LoadingSuccessButton(title: "Save", doneTitle: "Saved", style: .dullPink) {
            try? await Task.sleep(for: .seconds(0.4))
            return false
        }
    }
    .padding(16)
    .background(Color.surface)
}
