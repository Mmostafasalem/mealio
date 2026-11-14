import SwiftUI
import UIKit

// MARK: - Spring Toggle
//
// Port of designbookmark.com/motion "Toggle Switch" (toggle-switch/switch.js).
// Each switch has a position spring and a stretch spring. Flipping kicks the
// stretch, so the knob grows long toward where it is going, then the position
// lands with a small bounce and the knob rounds back up while the track fills
// dull pink.
//
// Accessibility: the styled row is represented to assistive tech by a native
// switch-style Toggle, so VoiceOver, Switch Control and UI tests still see a
// Switch element with value "0"/"1" and any identifier set on the Toggle.

struct SpringToggleStyle: ToggleStyle {
    func makeBody(configuration: Configuration) -> some View {
        SpringToggleRow(configuration: configuration)
    }
}

extension ToggleStyle where Self == SpringToggleStyle {
    /// Nourlo's spring switch: the knob stretches as it travels, then bounces on arrival.
    static var spring: SpringToggleStyle { SpringToggleStyle() }
}

private struct SpringToggleRow: View {
    let configuration: ToggleStyleConfiguration

    @Environment(\.isEnabled) private var isEnabled
    @State private var model = SpringToggleModel()

    var body: some View {
        HStack(spacing: Spacing.md) {
            configuration.label
            Spacer(minLength: Spacing.sm)
            SpringSwitchTrack(model: model)
                .contentShape(Rectangle())
                .onTapGesture { configuration.isOn.toggle() }
                .opacity(isEnabled ? 1 : 0.45)
        }
        .onAppear { model.snap(configuration.isOn) }
        .onChange(of: configuration.isOn) { _, on in model.flip(to: on) }
        .onDisappear { model.stop() }
        .accessibilityRepresentation {
            Toggle(isOn: configuration.$isOn) { configuration.label }
                .toggleStyle(.switch)
        }
    }
}

/// The 52 × 32 track and its 26 pt knob (3 pt inset, 20 pt of travel), as in switch.css.
private struct SpringSwitchTrack: View {
    let model: SpringToggleModel

    private static let knobColor = Color(UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 0xF4 / 255, green: 0xDA / 255, blue: 0xD4 / 255, alpha: 1) // almond
            : .white
    })

    var body: some View {
        ZStack(alignment: .leading) {
            Capsule().fill(Color.surfaceSecondary)
            Capsule().fill(Color.dullPink).opacity(model.fill)
            Capsule()
                .fill(Self.knobColor)
                .frame(width: model.knobWidth, height: 26)
                .shadow(color: .black.opacity(0.14), radius: 2, y: 1)
                .offset(x: 3 + model.knobX)
        }
        .frame(width: 52, height: 32)
    }
}

// MARK: - Engine

@MainActor
@Observable
final class SpringToggleModel {
    private(set) var knobWidth: Double = 26
    private(set) var knobX: Double = 0
    private(set) var fill: Double = 0

    @ObservationIgnored private var on = false
    @ObservationIgnored private var p = MotionSpring(0, 320, 18)   // position 0…1
    @ObservationIgnored private var w = MotionSpring(0, 300, 20)   // stretch
    @ObservationIgnored private var didSnap = false
    @ObservationIgnored private let clock = MotionClock()

    init() {
        clock.frame = { [weak self] dt in self?.frame(dt) }
        clock.render = { [weak self] in self?.render() }
    }

    /// Show a value with no motion (first appearance).
    func snap(_ value: Bool) {
        on = value
        p.snap(value ? 1 : 0)
        w.snap(0)
        didSnap = true
        render()
    }

    func flip(to value: Bool) {
        guard didSnap else { snap(value); return }
        guard value != on else { return }
        on = value
        p.t = value ? 1 : 0
        w.t = 0
        // The stretch is decorative: Reduce Motion just slides the knob.
        if !MotionSettings.reduceMotion { w.v = 60 }
        clock.start()
    }

    func stop() {
        p.snap(p.t); w.snap(0)
        render()
        clock.stop()
    }

    private func frame(_ dt: Double) {
        p.step(dt); w.step(dt)
    }

    private func render() {
        // The knob grows long while it travels; the edge in front leads.
        let grow = motionClamp(w.x, 0, 1) * 10
        let x = p.x * 20
        let pc = motionClamp(p.x, 0, 1)
        knobWidth = 26 + grow
        knobX = on ? x - grow * pc : x
        fill = pc
        if clock.isRunning, p.isSettled, w.isSettled {
            p.snap(p.t); w.snap(w.t)
            knobWidth = 26; knobX = p.x * 20; fill = p.x
            clock.stop()
        }
    }
}

// MARK: - Preview

private struct SpringTogglePreview: View {
    @State private var a = true
    @State private var b = false
    var body: some View {
        Form {
            Toggle("Allow online AI suggestions", isOn: $a)
            Toggle("Sync with iCloud", isOn: $b)
            Toggle("Disabled", isOn: .constant(true)).disabled(true)
        }
        .toggleStyle(.spring)
    }
}

#Preview("Spring Toggle") { SpringTogglePreview() }
