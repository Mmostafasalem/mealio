import SwiftUI
import UIKit

// MARK: - Bell Button
//
// Port of Kokonut UI "Bell Button" (bell-button.tsx, MIT), as shown at
// designbookmark.com/motion "Bell button". The bell and its clapper are two
// pendulums on the same pivot, coupled only by collisions: the swinging bell
// catches the clapper with its lip, flings it across, and it strikes the other
// side (a small arc flares there, with a light tap). Turning it on rings it;
// turning it off draws a slash and gives a dull shake with the clapper held
// still. Same constants as the original (angles in degrees, time in seconds).
// Reduce Motion: nothing swings; the arcs flare once when turned on.

@MainActor
@Observable
final class BellModel {
    private(set) var bell: Double = 0
    private(set) var clapper: Double = 0
    /// Bumped when the clapper strikes that side.
    private(set) var strikeLeft = 0
    private(set) var strikeRight = 0

    @ObservationIgnored private var bellSpeed: Double = 0
    @ObservationIgnored private var clapperSpeed: Double = 0
    @ObservationIgnored var muffled = true
    @ObservationIgnored private var carry: Double = 0
    @ObservationIgnored private let clock = MotionClock()

    private static let step = 1.0 / 240
    private static let bellStiffness = 380.0, bellDamping = 5.0
    private static let clapperStiffness = 150.0, clapperDamping = 4.0
    /// How far the clapper can swing inside the bell before it hits the lip.
    private static let lip = 13.0
    private static let restitution = 0.45
    /// Share of a hit that goes into the bell, which is much heavier.
    private static let recoil = 0.18
    /// Impacts harder than this ring out (deg/s, relative).
    private static let strikeSpeed = 260.0
    static let ringKick = 600.0, muteKick = 300.0
    private static let rest = 0.05

    init() {
        clock.frame = { [weak self] dt in self?.advance(dt) }
    }

    func kick(_ speed: Double) {
        guard !MotionSettings.reduceMotion else { return }
        bellSpeed += speed
        clock.start()
    }

    /// Swing away from the clapper so the first hit rings.
    func ring() { kick(bellSpeed >= 0 ? Self.ringKick : -Self.ringKick) }

    func flareBoth() { strikeLeft += 1; strikeRight += 1 }

    func stop() { clock.stop() }

    private func advance(_ dt: Double) {
        carry += min(dt, 0.05)
        while carry >= Self.step {
            stepOnce()
            carry -= Self.step
        }
        let energy = abs(bell) + abs(bellSpeed) * 0.02 + abs(clapper) + abs(clapperSpeed) * 0.02
        if energy < Self.rest {
            bell = 0; bellSpeed = 0; clapper = 0; clapperSpeed = 0; carry = 0
            clock.stop()
        }
    }

    private func stepOnce() {
        let h = Self.step
        bellSpeed += (-bell * Self.bellStiffness - bellSpeed * Self.bellDamping) * h
        bell += bellSpeed * h
        if muffled {
            clapper = bell
            clapperSpeed = bellSpeed
            return
        }
        clapperSpeed += (-clapper * Self.clapperStiffness - clapperSpeed * Self.clapperDamping) * h
        clapper += clapperSpeed * h
        let relative = clapper - bell
        guard abs(relative) > Self.lip else { return }
        let side: Double = relative > 0 ? 1 : -1
        let impact = (clapperSpeed - bellSpeed) * side
        clapper = bell + side * Self.lip
        guard impact > 0 else { return }
        clapperSpeed -= side * impact * (1 + Self.restitution)
        bellSpeed += side * impact * Self.recoil
        if impact > Self.strikeSpeed {
            if side > 0 { strikeRight += 1 } else { strikeLeft += 1 }
            UIImpactFeedbackGenerator(style: .light).impactOccurred(intensity: 0.5)
        }
    }
}

/// A bell that rings when switched on. `count` shows in a small pill (how many
/// reminders are active, say); pass `nil` to hide it.
struct BellButton: View {
    @Binding var isOn: Bool
    var label: String = "Notify me"
    var onLabel: String = "Subscribed"
    var count: Int? = nil

    @State private var model = BellModel()
    @State private var flareLeft = false
    @State private var flareRight = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private static let easeOut = Animation.timingCurve(0.23, 1, 0.32, 1, duration: 0.3)

    var body: some View {
        Button {
            isOn.toggle()
        } label: {
            HStack(spacing: Spacing.md) {
                bell
                    .frame(width: 22, height: 22)
                ZStack(alignment: .leading) {
                    Text(label).opacity(isOn ? 0 : 1).blur(radius: isOn ? 2 : 0)
                    Text(onLabel).opacity(isOn ? 1 : 0).blur(radius: isOn ? 0 : 2)
                }
                .font(.subheadline.weight(.semibold))
                .lineLimit(1)
                .fixedSize()
                .animation(.easeOut(duration: 0.2), value: isOn)
                if let count {
                    Text("\(count)")
                        .font(.footnote.weight(.semibold))
                        .monospacedDigit()
                        .contentTransition(.numericText(value: Double(count)))
                        .animation(Self.easeOut, value: count)
                        .frame(minWidth: 28, minHeight: 28)
                        .padding(.horizontal, 4)
                        .background((isOn ? Color.onAccent.opacity(0.14) : Color.surfaceSecondary), in: Capsule())
                        .foregroundStyle(isOn ? Color.onAccent.opacity(0.85) : Color.labelSecondary)
                        .accessibilityHidden(true)
                }
            }
            .foregroundStyle(isOn ? Color.onAccent : Color.labelPrimary)
            .padding(.leading, 18)
            .padding(.trailing, count == nil ? 18 : 10)
            .frame(minHeight: 48)
            .background(isOn ? Color.dullPink : Color.surface, in: Capsule())
            .overlay(Capsule().strokeBorder(isOn ? Color.clear : Color.hairline, lineWidth: 1))
            .contentShape(Capsule())
            .animation(.easeOut(duration: 0.2), value: isOn)
        }
        .buttonStyle(ScalePressStyle())
        .sensoryFeedback(.impact(weight: .medium), trigger: isOn)
        .accessibilityLabel(label)
        .accessibilityValue(isOn ? "On" : "Off")
        .accessibilityAddTraits(isOn ? .isSelected : [])
        .onAppear { model.muffled = !isOn }
        .onDisappear { model.stop() }
        .onChange(of: isOn) { _, on in
            model.muffled = !on
            if on {
                model.ring()
                if reduceMotion { model.flareBoth() }
            } else {
                // Off: a dull shake, the clapper held still against the bell.
                model.kick(-BellModel.muteKick)
            }
        }
        .onChange(of: model.strikeLeft) { _, _ in flare($flareLeft) }
        .onChange(of: model.strikeRight) { _, _ in flare($flareRight) }
    }

    /// Two short arcs flare out on the side that was struck (0.42 s).
    private func flare(_ flag: Binding<Bool>) {
        flag.wrappedValue = true
        withAnimation(.timingCurve(0.23, 1, 0.32, 1, duration: 0.42)) { flag.wrappedValue = false }
    }

    private var bell: some View {
        // Drawn in the original's 24-unit box; the pivot is at (12, 2.5).
        GeometryReader { geo in
            let s = min(geo.size.width, geo.size.height) / 24
            let pivot = UnitPoint(x: 12.0 / 24, y: 2.5 / 24)
            let stroke = StrokeStyle(lineWidth: 2 * s, lineCap: .round, lineJoin: .round)
            ZStack {
                BellWave(right: true).stroke(style: stroke)
                    .opacity(flareRight ? 0.9 : 0).offset(x: flareRight ? 0 : 3 * s)
                BellWave(right: false).stroke(style: stroke)
                    .opacity(flareLeft ? 0.9 : 0).offset(x: flareLeft ? 0 : -3 * s)
                BellClapper().stroke(style: stroke)
                    .rotationEffect(.degrees(model.clapper), anchor: pivot)
                ZStack {
                    BellBody().fill(isOn ? AnyShapeStyle(.foreground) : AnyShapeStyle(.clear))
                    BellBody().stroke(style: stroke)
                    // The mute slash, drawn across when off.
                    BellSlash().trim(from: 0, to: isOn ? 0 : 1).stroke(style: stroke)
                        .animation(reduceMotion ? nil : Self.easeOut, value: isOn)
                }
                .rotationEffect(.degrees(model.bell), anchor: pivot)
            }
        }
        .accessibilityHidden(true)
    }
}

// The bell's outline, clapper, slash and ring arcs (lucide "bell", 24-unit box).

private struct BellBody: Shape {
    func path(in rect: CGRect) -> Path {
        let s = min(rect.width, rect.height) / 24
        func p(_ x: Double, _ y: Double) -> CGPoint { CGPoint(x: rect.minX + x * s, y: rect.minY + y * s) }
        var path = Path()
        path.move(to: p(3.26, 15.33))
        path.addQuadCurve(to: p(4, 17), control: p(2.6, 16.6))
        path.addLine(to: p(20, 17))
        path.addQuadCurve(to: p(20.74, 15.33), control: p(21.4, 16.6))
        path.addCurve(to: p(18, 8), control1: p(19.41, 13.96), control2: p(18, 12.5))
        path.addArc(center: p(12, 8), radius: 6 * s, startAngle: .degrees(0), endAngle: .degrees(180), clockwise: true)
        path.addCurve(to: p(3.26, 15.33), control1: p(6, 12.5), control2: p(4.59, 13.96))
        path.closeSubpath()
        return path
    }
}

private struct BellClapper: Shape {
    func path(in rect: CGRect) -> Path {
        let s = min(rect.width, rect.height) / 24
        var path = Path()
        path.move(to: CGPoint(x: rect.minX + 10.27 * s, y: rect.minY + 21 * s))
        path.addQuadCurve(to: CGPoint(x: rect.minX + 13.73 * s, y: rect.minY + 21 * s),
                          control: CGPoint(x: rect.minX + 12 * s, y: rect.minY + 23.2 * s))
        return path
    }
}

private struct BellSlash: Shape {
    func path(in rect: CGRect) -> Path {
        let s = min(rect.width, rect.height) / 24
        var path = Path()
        path.move(to: CGPoint(x: rect.minX + 3 * s, y: rect.minY + 3 * s))
        path.addLine(to: CGPoint(x: rect.minX + 21 * s, y: rect.minY + 21 * s))
        return path
    }
}

private struct BellWave: Shape {
    let right: Bool
    func path(in rect: CGRect) -> Path {
        let s = min(rect.width, rect.height) / 24
        func p(_ x: Double, _ y: Double) -> CGPoint { CGPoint(x: rect.minX + (right ? x : 24 - x) * s, y: rect.minY + y * s) }
        var path = Path()
        path.move(to: p(21.5, 4.5))
        path.addCurve(to: p(23.3, 10), control1: p(22.7, 6.1), control2: p(23.3, 7.9))
        return path
    }
}

#Preview {
    @Previewable @State var on = false
    VStack(spacing: 24) {
        BellButton(isOn: $on, label: "Reminders off", onLabel: "Reminders on", count: on ? 4 : 0)
        BellButton(isOn: $on, label: "Notify me", onLabel: "Subscribed")
    }
    .padding(40)
}
