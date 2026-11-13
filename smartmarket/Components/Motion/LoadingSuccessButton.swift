import SwiftUI
import UIKit

// MARK: - Loading > Success
//
// Port of designbookmark.com/motion "Loading > Success" (loading-success/submit.js).
// Tap: the label drops away and the pill closes into a circle with a spinner.
// When the work succeeds the circle opens into a pill tinted toward dull pink,
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
    let action: () async -> Bool
    var onFinished: (() -> Void)? = nil

    @State private var model = LoadingSuccessModel()
    @ScaledMetric(relativeTo: .headline) private var height: CGFloat = 52
    @ScaledMetric(relativeTo: .headline) private var checkSide: CGFloat = 22

    init(
        title: String,
        doneTitle: String,
        systemImage: String? = nil,
        style: Style = .rhino,
        action: @escaping () async -> Bool,
        onFinished: (() -> Void)? = nil
    ) {
        self.title = title
        self.doneTitle = doneTitle
        self.systemImage = systemImage
        self.style = style
        self.action = action
        self.onFinished = onFinished
    }

    var body: some View {
        Button {
            model.go(circle: height, doneTitle: doneTitle, action: action, onFinished: onFinished)
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
        .onAppear { model.isVisible = true }
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
            .offset(y: 14 * (1 - model.labelRaw))

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
            .offset(y: 12 * (1 - model.doneRaw))
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
    // Published per frame.
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
    @ObservationIgnored private let clock = MotionClock()

    /// The spinner stays at least this long so it reads.
    private static let minSpin: Double = 0.6
    /// How long the done pill holds before `onFinished`.
    private static let hold: Double = 1.2

    init() {
        clock.frame = { [weak self] dt in self?.frame(dt) }
        clock.render = { [weak self] in self?.render() }
    }

    func setFull(_ value: Double) {
        guard value > 0, value != full else { return }
        let first = full == 0
        full = value
        if state == .idle {
            if first { w.snap(value) } else { w.t = value; clock.start() }
            if first { render() }
        }
    }

    func go(circle: Double, doneTitle: String, action: @escaping () async -> Bool, onFinished: (() -> Void)?) {
        guard state == .idle else { return }
        state = .loading
        t.t = 0; w.t = circle; p.t = 1
        clock.start()
        run = Task { [weak self] in
            let started = CACurrentMediaTime()
            let ok = await action()
            let wait = Self.minSpin - (CACurrentMediaTime() - started)
            if wait > 0 { try? await Task.sleep(for: .seconds(wait)) }
            guard let self, !Task.isCancelled else { return }
            guard ok else { self.reset(); return }
            self.succeed(doneTitle: doneTitle)
            try? await Task.sleep(for: .seconds(Self.hold))
            guard !Task.isCancelled else { return }
            onFinished?()
            if self.isVisible { self.reset() } else { self.snapIdle() }
        }
    }

    func disappeared() {
        isVisible = false
        // Let a running flow finish (onFinished must still fire); just stop drawing.
        if state == .idle { clock.stop() }
    }

    private func succeed(doneTitle: String) {
        state = .done
        p.t = 0; g.t = 1; d.t = 1
        let doneWidth = max(140, doneContent + 48)
        w.t = full > 0 ? min(full, doneWidth) : doneWidth
        later(0.15) { [weak self] in self?.k.t = 1 }
        clock.start()
        UIAccessibility.post(notification: .announcement, argument: doneTitle)
    }

    private func reset() {
        state = .idle
        d.t = 0; g.t = 0; k.t = 0; p.t = 0
        w.t = full
        later(0.12) { [weak self] in self?.t.t = 1 }
        clock.start()
    }

    private func snapIdle() {
        state = .idle
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

    private func render() {
        width = max(0, w.x)
        labelRaw = t.x
        label = motionClamp(t.x, 0, 1)
        spinner = motionClamp(p.x, 0, 1)
        spinnerScale = motionClamp(p.x, 0, 1.2)
        rotation = rot.truncatingRemainder(dividingBy: 360)
        doneRaw = d.x
        done = motionClamp(d.x, 0, 1)
        green = motionClamp(g.x, 0, 1)
        check = motionClamp(k.x, 0, 1)

        let settled = w.isSettled && t.isSettled && p.isSettled && d.isSettled && g.isSettled && k.isSettled
        if clock.isRunning, settled, pendingTimers == 0, state != .loading {
            w.snap(w.t); t.snap(t.t); p.snap(p.t); d.snap(d.t); g.snap(g.t); k.snap(k.t)
            width = w.x; label = t.x; labelRaw = t.x; spinner = p.x; spinnerScale = p.x
            done = d.x; doneRaw = d.x; green = g.x; check = k.x
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
