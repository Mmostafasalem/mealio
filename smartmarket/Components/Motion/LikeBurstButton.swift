import SwiftUI

// MARK: - Like Burst
//
// Port of designbookmark.com/motion "Like Burst" (like-burst/like.js).
// Like: the heart squashes down and bounces up, fills, and a ring of dots flies
// out and fades. The count rolls up by one. Unlike rolls it back and the heart
// empties with a small dip. No autoplay: it only moves when `isOn` changes.
// A rare delight moment, so it keeps the bouncy (520, 13) squash. Reduce Motion:
// no squash or burst, the heart and the count crossfade.

/// Pill button with the animated heart and an optional rolling count.
struct LikeBurstButton: View {
    @Binding var isOn: Bool
    /// Likes from everyone else. The pill shows `count + 1` while `isOn`, and
    /// rolls between the two when toggled. `nil` shows the heart only.
    var count: Int? = nil
    let label: String

    var body: some View {
        Button { isOn.toggle() } label: {
            LikeBurstHeart(isOn: isOn, count: count)
                .padding(.leading, count == nil ? 9 : 16)
                .padding(.trailing, count == nil ? 9 : 20)
                .frame(minWidth: 44, minHeight: 44)
                .background(Color.surfaceSecondary, in: RoundedRectangle(cornerRadius: Radius.pill, style: .continuous))
                .contentShape(RoundedRectangle(cornerRadius: Radius.pill, style: .continuous))
        }
        .buttonStyle(ScalePressStyle())
        .sensoryFeedback(.impact(weight: .light), trigger: isOn)
        .accessibilityLabel(label)
        .accessibilityValue(count.map { "\($0 + (isOn ? 1 : 0))" } ?? "")
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }
}

/// The animated heart (and optional count) without a button around it, for rows
/// that are themselves the tap target. Animates whenever `isOn` changes.
struct LikeBurstHeart: View {
    let isOn: Bool
    var count: Int? = nil

    @State private var model = LikeBurstModel()
    @ScaledMetric(relativeTo: .title3) private var side: CGFloat = 26
    @ScaledMetric(relativeTo: .headline) private var row: CGFloat = 22
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private static let dotColors: [Color] = [
        .dullPink, .almond, .rhino, .brandLight, .dullPink, .almond, .rhino, .brandLight,
    ]

    var body: some View {
        HStack(spacing: 10) {
            heart
            if let count { counter(count) }
        }
        .accessibilityHidden(true)
        .onAppear { model.set(isOn, animated: false) }
        .onChange(of: isOn) { _, on in model.set(on, animated: true) }
        .onDisappear { model.stop() }
    }

    private var heart: some View {
        let unit = side / 26
        return ZStack {
            Image(systemName: "heart")
                .foregroundStyle(Color.labelSecondary)
                .opacity(1 - model.fill)
            Image(systemName: "heart.fill")
                .foregroundStyle(Color.dullPink)
                .opacity(model.fill)
        }
        .font(.system(size: side * 0.86, weight: .medium))
        .frame(width: side, height: side)
        .scaleEffect(x: model.scaleX, y: model.scaleY)
        .background {
            // Dots sit behind the heart, centred on it, like the original's .burst.
            if model.burst < 1 {
                ZStack {
                    ForEach(0..<8, id: \.self) { i in
                        let d = model.dot(i)
                        Circle()
                            .fill(Self.dotColors[i])
                            .frame(width: 6 * unit, height: 6 * unit)
                            .scaleEffect(d.scale)
                            .offset(x: d.x * unit, y: d.y * unit)
                            .opacity(d.opacity)
                    }
                }
                .allowsHitTesting(false)
            }
        }
    }

    @ViewBuilder private func counter(_ base: Int) -> some View {
        if reduceMotion {
            // Crossfade in place instead of rolling.
            ZStack {
                Text(base.formatted()).opacity(1 - motionClamp(model.roll, 0, 1))
                Text((base + 1).formatted()).opacity(motionClamp(model.roll, 0, 1))
            }
            .font(.headline.monospacedDigit())
            .foregroundStyle(Color.labelPrimary)
            .frame(height: row)
        } else {
            rollingCounter(base)
        }
    }

    private func rollingCounter(_ base: Int) -> some View {
        VStack(spacing: 0) {
            Text(base.formatted()).frame(height: row)
            Text((base + 1).formatted()).frame(height: row)
        }
        .font(.headline.monospacedDigit())
        .foregroundStyle(Color.labelPrimary)
        .offset(y: -row * model.roll)
        .frame(height: row, alignment: .top)
        .clipped()
    }
}

// MARK: - Engine

@MainActor
@Observable
final class LikeBurstModel {
    // Published per frame for SwiftUI.
    private(set) var scaleX: Double = 1
    private(set) var scaleY: Double = 1
    private(set) var fill: Double = 0
    private(set) var roll: Double = 0
    /// Burst progress 0…1 (1 = finished / hidden).
    private(set) var burst: Double = 1

    @ObservationIgnored private var h = MotionSpring(1, 520, 13)   // heart squash
    @ObservationIgnored private var f = MotionSpring(0, 300, 26)   // fill
    @ObservationIgnored private var n = MotionSpring(0, 260, 20)   // count roll
    @ObservationIgnored private var bt: Double = 9                  // seconds since burst
    @ObservationIgnored private var current: Bool?
    @ObservationIgnored private let clock = MotionClock()

    private static let burstDuration = 0.55

    init() {
        clock.frame = { [weak self] dt in self?.frame(dt) }
        clock.render = { [weak self] in self?.render() }
    }

    func set(_ on: Bool, animated: Bool) {
        guard on != current else { return }
        let first = current == nil
        current = on
        if !animated || first {
            h.snap(1); f.snap(on ? 1 : 0); n.snap(on ? 1 : 0); bt = 9
            render()
            return
        }
        f.t = on ? 1 : 0; n.t = on ? 1 : 0
        if MotionSettings.reduceMotion {
            // No squash or burst: fill and count crossfade only.
            h.snap(1); bt = 9
        } else {
            // Add to the heart's motion rather than restarting it, so a quick
            // like-unlike never jumps; only a heart at rest gets squashed first.
            if h.isSettled && h.x == 1 { h.x = on ? 0.6 : 0.85 }
            h.v += on ? 9 : 3
            h.t = 1
            if on { bt = 0 }
        }
        clock.start()
    }

    func stop() { clock.stop() }

    func dot(_ i: Int) -> (x: Double, y: Double, scale: Double, opacity: Double) {
        let k = burst, e = 1 - pow(1 - k, 3)
        let a = Double(i) / 8 * 2 * .pi + 0.2
        let r = 10 + e * (22 + Double(i % 2) * 6)
        return (cos(a) * r, sin(a) * r, 1 - 0.7 * k, k >= 1 ? 0 : 1 - k * k)
    }

    private func frame(_ dt: Double) {
        bt += dt
        h.step(dt); f.step(dt); n.step(dt)
    }

    private func render() {
        let sq = h.x
        scaleX = sq * (2 - min(sq, 1.15))
        scaleY = sq
        fill = motionClamp(f.x, 0, 1)
        roll = n.x
        burst = motionClamp(bt / Self.burstDuration, 0, 1)

        if clock.isRunning, h.isSettled, f.isSettled, n.isSettled, burst >= 1 {
            h.snap(h.t); f.snap(f.t); n.snap(n.t)
            scaleX = 1; scaleY = 1; fill = f.x; roll = n.x
            clock.stop()
        }
    }
}

// MARK: - Preview

#Preview("Like Burst") {
    @Previewable @State var liked = false
    @Previewable @State var faved = true
    VStack(spacing: 32) {
        LikeBurstButton(isOn: $liked, count: 1284, label: "Like")
        LikeBurstButton(isOn: $faved, label: "Favorite")
    }
    .padding(40)
    .background(Color.surface)
}
