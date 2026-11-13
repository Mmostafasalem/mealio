import SwiftUI
import UIKit

// MARK: - Hold to Confirm
//
// Port of designbookmark.com/motion "Hold Button" (hold-button/hold.js).
// Holding fills the pill from the left and the label inverts exactly under the
// fill (a mask). Let go early: the fill springs back past zero and the pill
// shakes "no". Hold to the end (--hold-ms 1200): the pill morphs into a circle
// and the check draws itself, then `action` runs.
//
// Assistive tech cannot hold. A plain tap (a quick touch, an accessibility
// activate, VoiceOver, Switch Control, or the named accessibility action)
// calls `fallback` instead, which should open a confirmation alert. Without a
// fallback, an assistive activation runs `action` directly.

struct HoldToConfirmButton: View {
    let title: String
    let holdingTitle: String
    let doneTitle: String
    var tint: Color = .brandPrimary
    var systemImage: String? = nil
    /// Spoken name; defaults to `title`.
    var accessibilityName: String? = nil
    /// Name of the custom accessibility action that runs `fallback`.
    var accessibilityActionName: String? = nil
    var fallback: (() -> Void)? = nil
    let action: () -> Void

    @State private var model = HoldToConfirmModel()
    @ScaledMetric(relativeTo: .headline) private var height: CGFloat = 56
    @ScaledMetric(relativeTo: .headline) private var checkSide: CGFloat = 26

    init(
        title: String,
        holdingTitle: String,
        doneTitle: String,
        tint: Color = .brandPrimary,
        systemImage: String? = nil,
        accessibilityName: String? = nil,
        accessibilityActionName: String? = nil,
        fallback: (() -> Void)? = nil,
        action: @escaping () -> Void
    ) {
        self.title = title
        self.holdingTitle = holdingTitle
        self.doneTitle = doneTitle
        self.tint = tint
        self.systemImage = systemImage
        self.accessibilityName = accessibilityName
        self.accessibilityActionName = accessibilityActionName
        self.fallback = fallback
        self.action = action
    }

    var body: some View {
        Button {
            if model.consumeTap() { runFallback() }
        } label: {
            pill
                .frame(maxWidth: .infinity)
                .frame(height: height)
                .contentShape(Rectangle())
                .background {
                    GeometryReader { g in
                        Color.clear
                            .onAppear { model.setFull(g.size.width, dot: height) }
                            .onChange(of: g.size.width) { _, w in model.setFull(w, dot: height) }
                    }
                }
        }
        .buttonStyle(HoldPressStyle { pressed in
            if pressed { model.start(onComplete: complete) } else { model.stop() }
        })
        .disabled(model.mode == .done)
        .accessibilityLabel(model.mode == .done ? doneTitle : (accessibilityName ?? title))
        .accessibilityHint(fallback == nil ? "Hold to confirm." : "Hold to confirm, or double-tap to confirm in an alert.")
        .accessibilityAction(named: Text(accessibilityActionName ?? (accessibilityName ?? title))) { runFallback() }
        .onDisappear { model.disappeared() }
    }

    private func runFallback() {
        if let fallback { fallback() } else { action() }
    }

    private func complete() {
        UIAccessibility.post(notification: .announcement, argument: doneTitle)
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        // Let the check draw before the work (which may leave this screen) starts.
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(MotionSettings.reduceMotion ? 0.2 : 0.6))
            action()
        }
    }

    private var shape: RoundedRectangle { RoundedRectangle(cornerRadius: Radius.pill, style: .continuous) }

    private var labelContent: some View {
        HStack(spacing: Spacing.sm) {
            if let systemImage { Image(systemName: systemImage) }
            Text(model.mode == .holding ? holdingTitle : title)
        }
        .font(.headline)
        .lineLimit(1)
        .minimumScaleFactor(0.7)
        .padding(.horizontal, Spacing.lg)
    }

    private var pill: some View {
        let w: CGFloat? = model.full > 0 ? CGFloat(model.width) : nil
        return ZStack {
            shape.fill(Color.surface)
            shape.strokeBorder(Color.hairline, lineWidth: 1)

            labelContent
                .foregroundStyle(tint)

            // The fill grows from the left; its corners follow the pill.
            Rectangle()
                .fill(tint)
                .frame(width: model.fillWidth)
                .frame(maxWidth: .infinity, alignment: .leading)

            // The inverted label only shows where the fill is.
            labelContent
                .foregroundStyle(Color.surface)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .mask(alignment: .leading) {
                    Rectangle().frame(width: model.fillWidth)
                }
                .accessibilityHidden(true)

            shape.fill(Color.dullPink).opacity(model.isDone ? 1 : 0)

            HoldCheckShape()
                .trim(from: 0, to: model.isDone ? 1 : 0)
                .stroke(Color.onAccent, style: StrokeStyle(lineWidth: 2.6 * checkSide / 24, lineCap: .round, lineJoin: .round))
                .frame(width: checkSide, height: checkSide)
                .opacity(model.isDone ? 1 : 0)
                .animation(model.isDone && !MotionSettings.reduceMotion
                           ? .timingCurve(0.65, 0, 0.35, 1, duration: 0.45).delay(0.16) : nil,
                           value: model.isDone)
        }
        .compositingGroup()
        .animation(.easeOut(duration: 0.2), value: model.isDone)
        .frame(width: w, height: height)
        .clipShape(shape)
        .scaleEffect(model.scale)
        .offset(x: model.shake)
    }
}

/// Reports press changes; the visual squash comes from the model's spring.
private struct HoldPressStyle: ButtonStyle {
    let onPress: (Bool) -> Void
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .onChange(of: configuration.isPressed) { _, pressed in onPress(pressed) }
    }
}

/// "M5 12.5 l4.5 4.5 L19 7.5" in a 24×24 box.
private struct HoldCheckShape: Shape {
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
final class HoldToConfirmModel {
    enum Mode { case idle, holding, done }

    private(set) var mode: Mode = .idle
    private(set) var isDone = false
    // Published per frame.
    private(set) var width: Double = 0
    private(set) var fillWidth: Double = 0
    private(set) var scale: Double = 1
    private(set) var shake: Double = 0
    /// Measured container width: the idle pill.
    private(set) var full: Double = 0
    @ObservationIgnored private var dot: Double = 56

    // tokens.css
    private static let holdSec = 1.2                       // --hold-ms
    private static let release = MotionTokens.Preset(k: 260, c: 14) // --hold-release
    private static let morph = MotionTokens.Preset(k: 320, c: 20)   // --hold-morph
    private static let doneSec = 1.7                       // --hold-done-ms
    /// A press shorter than this is a tap: it asks for confirmation instead of shaking.
    private static let tapSec = 0.3

    @ObservationIgnored private var p = MotionSpring(0, HoldToConfirmModel.release)   // fill 0…1
    @ObservationIgnored private var w = MotionSpring(0, HoldToConfirmModel.morph)     // pill width
    @ObservationIgnored private var sc = MotionSpring(1, 520, 20)                      // press squash
    @ObservationIgnored private var sh = MotionSpring(0, 700, 9)                       // "no" wobble
    @ObservationIgnored private var pressStart: CFTimeInterval = 0
    @ObservationIgnored private var lastPress: (duration: Double, at: CFTimeInterval)?
    @ObservationIgnored private var completedThisPress = false
    @ObservationIgnored private var onComplete: (() -> Void)?
    @ObservationIgnored private var pendingTimers = 0
    @ObservationIgnored private let clock = MotionClock()

    private var assistiveTechRunning: Bool {
        UIAccessibility.isVoiceOverRunning || UIAccessibility.isSwitchControlRunning
    }

    init() {
        clock.frame = { [weak self] dt in self?.frame(dt) }
        clock.render = { [weak self] in self?.render() }
    }

    func setFull(_ value: Double, dot: Double) {
        self.dot = dot
        guard value > 0, value != full else { return }
        let first = full == 0
        full = value
        guard mode != .done else { return }
        if first { w.snap(value); render() } else { w.t = value; clock.start() }
    }

    func start(onComplete: @escaping () -> Void) {
        pressStart = CACurrentMediaTime()
        completedThisPress = false
        guard mode == .idle, !assistiveTechRunning else { return }
        self.onComplete = onComplete
        mode = .holding
        sc.t = 0.96
        clock.start()
    }

    func stop() {
        let now = CACurrentMediaTime()
        let held = now - pressStart
        lastPress = (held, now)
        guard mode == .holding else { return }
        mode = .idle
        sc.t = 1
        if p.x < 1 {
            p.tune(Self.release.k, Self.release.c)
            p.t = 0   // spring back, overshooting a hair below zero
            if held >= Self.tapSec {
                // "No": a shake, or under Reduce Motion the error haptic alone.
                if MotionSettings.reduceMotion {
                    UINotificationFeedbackGenerator().notificationOccurred(.error)
                } else {
                    sh.v += 260 * min(1, p.x * 2 + 0.3)
                }
            }
        }
        clock.start()
    }

    /// The button's action fired. True when it was a tap (or an assistive
    /// activation) that should ask for confirmation.
    func consumeTap() -> Bool {
        defer { lastPress = nil }
        if mode == .done || completedThisPress { return false }
        let now = CACurrentMediaTime()
        let duration: Double?
        if mode == .holding {
            duration = now - pressStart
        } else if let last = lastPress, now - last.at < 0.5 {
            duration = last.duration
        } else {
            duration = nil   // no touch at all: accessibility activate
        }
        guard duration == nil || duration! < Self.tapSec else { return false }
        if mode == .holding {
            // The action fired before the release callback; settle quietly.
            mode = .idle
            sc.t = 1
            p.tune(Self.release.k, Self.release.c)
            p.t = 0
            clock.start()
        }
        return true
    }

    func disappeared() {
        if mode == .holding { mode = .idle }
        if mode == .done { return }   // let the done state finish its timers
        clock.cancelAllTimers(); pendingTimers = 0
        p.snap(0); sc.snap(1); sh.snap(0); w.snap(full)
        render()
        clock.stop()
    }

    private func complete() {
        mode = .done
        completedThisPress = true
        isDone = true
        w.tune(Self.morph.k, Self.morph.c)
        w.t = dot
        sc.t = 1
        sc.v += 2.5
        onComplete?()
        onComplete = nil
        later(Self.doneSec) { [weak self] in self?.reset() }
    }

    private func reset() {
        isDone = false
        w.tune(Self.morph.k * 0.8, Self.morph.c)
        w.t = full
        p.snap(0)
        mode = .idle
        clock.start()
    }

    private func later(_ seconds: Double, _ fn: @escaping () -> Void) {
        pendingTimers += 1
        clock.after(seconds) { [weak self] in
            self?.pendingTimers -= 1
            fn()
        }
    }

    private func frame(_ dt: Double) {
        if mode == .holding {
            // Linear while held: it is a progress bar; the spring takes over on release.
            p.x = min(1, p.x + dt / Self.holdSec)
            p.v = 0
            p.t = p.x
            if p.x >= 1 { complete() }
        } else {
            p.step(dt)
        }
        w.step(dt); sc.step(dt); sh.step(dt)
    }

    private func render() {
        width = max(0, w.x)
        fillWidth = max(0, p.x) * width
        scale = sc.x
        shake = sh.x
        let settled = p.isSettled && w.isSettled(within: MotionSpring.points) && sc.isSettled
            && sh.isSettled(within: MotionSpring.points)
        if clock.isRunning, settled, pendingTimers == 0, mode != .holding {
            p.snap(p.t); w.snap(w.t); sc.snap(sc.t); sh.snap(sh.t)
            width = max(0, w.x); fillWidth = max(0, p.x) * width; scale = sc.x; shake = sh.x
            clock.stop()
        }
    }
}

// MARK: - Preview

#Preview("Hold to Confirm") {
    VStack(spacing: 24) {
        HoldToConfirmButton(
            title: "Hold to delete all data",
            holdingTitle: "Keep holding…",
            doneTitle: "Deleting data",
            tint: .brandDanger,
            systemImage: "trash",
            accessibilityName: "Delete All Data",
            fallback: { print("confirm in alert") }
        ) { print("deleted") }
    }
    .padding(16)
    .background(Color.surfaceGrouped)
}
