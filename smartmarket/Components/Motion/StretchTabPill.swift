import SwiftUI

// MARK: - Stretch Tab Pill
//
// Port of designbookmark.com/motion "Tab Pill" (tab-pill/tabs.js).
// Two springs per pill, one per edge. The edge in the direction of travel is
// stiff (620, 40) and the other soft (170, 19), so the pill stretches toward the
// new tab and then pulls its tail in. Values are the literal ones in tabs.js.
// Reduce Motion: both edges share one calm spring (fade), so the pill slides
// without stretching. `animated: false` (keyboard tab switches) jumps.
//
// Usage: tag each tab's highlight area with `.stretchTabPillAnchor(index)` and
// draw one pill behind them all:
//
//     HStack { … }
//         .backgroundPreferenceValue(StretchTabPillAnchors.self) { anchors in
//             GeometryReader { geo in
//                 StretchTabPill(target: anchors[selection].map { geo[$0] }, id: selection, isHidden: false) {
//                     RoundedRectangle(cornerRadius: 12).fill(Color.brandLight)
//                 }
//             }
//         }

/// Each tab's highlight frame, keyed by tab index.
struct StretchTabPillAnchors: PreferenceKey {
    static var defaultValue: [Int: Anchor<CGRect>] { [:] }
    static func reduce(value: inout [Int: Anchor<CGRect>], nextValue: () -> [Int: Anchor<CGRect>]) {
        value.merge(nextValue()) { $1 }
    }
}

extension View {
    /// Reports this view's bounds as the pill target for tab `index`.
    func stretchTabPillAnchor(_ index: Int) -> some View {
        anchorPreference(key: StretchTabPillAnchors.self, value: .bounds) { [index: $0] }
    }
}

/// The shared pill. Place it in a full-size container in the same coordinate
/// space as `target` (e.g. inside a GeometryReader that resolved the anchor).
struct StretchTabPill<Shape: View>: View {
    /// Frame of the selected tab's highlight area; `nil` hides the pill.
    let target: CGRect?
    /// Identity of the selected tab; a change stretches, a re-layout of the same tab jumps.
    let id: Int
    /// Fades the pill out (for example while the tabs are collapsed).
    let isHidden: Bool
    /// `false` moves the pill with no motion (e.g. a ⌘-number tab switch).
    var animated: Bool = true
    @ViewBuilder let shape: () -> Shape

    init(target: CGRect?, id: Int, isHidden: Bool, animated: Bool = true, @ViewBuilder shape: @escaping () -> Shape) {
        self.target = target
        self.id = id
        self.isHidden = isHidden
        self.animated = animated
        self.shape = shape
    }

    @State private var model = StretchTabPillModel()

    private struct Inputs: Equatable {
        let target: CGRect?
        let id: Int
        let hidden: Bool
    }

    var body: some View {
        shape()
            .frame(width: max(0, model.right - model.left), height: model.height)
            .offset(x: model.left, y: model.top)
            .opacity(model.opacity)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            // Position and fade come from the springs; no implicit animation on top.
            .transaction { $0.animation = nil }
            .allowsHitTesting(false)
            .accessibilityHidden(true)
            .onAppear { model.update(target: target, id: id, hidden: isHidden, animated: false) }
            // One change handler so a new tab and its new frame arrive together.
            .onChange(of: Inputs(target: target, id: id, hidden: isHidden)) { _, n in
                model.update(target: n.target, id: n.id, hidden: n.hidden, animated: animated)
            }
            .onDisappear { model.stop() }
    }
}

// MARK: - Engine

@MainActor
@Observable
final class StretchTabPillModel {
    /// Lead edge (faces the move) and trail edge (lags, makes the stretch), from tabs.js.
    static let lead = MotionTokens.Preset(k: 620, c: 40)
    static let trail = MotionTokens.Preset(k: 170, c: 19)

    private(set) var left: Double = 0
    private(set) var right: Double = 0
    private(set) var top: Double = 0
    private(set) var height: Double = 0
    private(set) var opacity: Double = 0

    @ObservationIgnored private var a = MotionSpring(0, StretchTabPillModel.trail)
    @ObservationIgnored private var b = MotionSpring(0, StretchTabPillModel.lead)
    @ObservationIgnored private var o = MotionSpring(0, MotionTokens.fade)
    @ObservationIgnored private var lastID: Int?
    @ObservationIgnored private var wasHidden = true
    @ObservationIgnored private let clock = MotionClock()

    init() {
        clock.frame = { [weak self] dt in self?.frame(dt) }
        clock.render = { [weak self] in self?.render() }
    }

    func update(target: CGRect?, id: Int, hidden: Bool, animated: Bool = true) {
        let hide = hidden || target == nil
        let first = lastID == nil || !animated
        let moved = !first && lastID != id
        if target != nil { lastID = id }
        defer { wasHidden = hide }
        if let target {
            top = target.minY
            height = target.height
            if moved && !hide && !wasHidden {
                if MotionSettings.reduceMotion {
                    // Same spring on both edges: the pill slides, it doesn't stretch.
                    a.tune(MotionTokens.fade); b.tune(MotionTokens.fade)
                } else if target.midX > (a.t + b.t) / 2 {
                    // Stiff edge faces the move, soft edge trails it.
                    b.tune(Self.lead); a.tune(Self.trail)
                } else { a.tune(Self.lead); b.tune(Self.trail) }
                a.t = target.minX; b.t = target.maxX
            } else {
                // First frame, hidden, coming back, or the same tab re-laid out
                // (rotation, Dynamic Type): jump, don't stretch.
                a.snap(target.minX); b.snap(target.maxX)
            }
        }
        o.t = hide ? 0 : 1
        if first {
            o.snap(o.t)
            clock.stop()
        }
        render()
        if !first { clock.start() }
    }

    func stop() {
        clock.stop()
        a.snap(a.t); b.snap(b.t); o.snap(o.t)
        render()
    }

    private func frame(_ dt: Double) {
        a.step(dt); b.step(dt); o.step(dt)
    }

    private func render() {
        left = a.x
        right = max(a.x, b.x)
        opacity = motionClamp(o.x, 0, 1)
        if clock.isRunning, a.isSettled(within: MotionSpring.points), b.isSettled(within: MotionSpring.points), o.isSettled {
            stop()
        }
    }
}

// MARK: - Preview

#Preview("Stretch Tab Pill") {
    @Previewable @State var selection = 0
    let tabs = ["Home", "Meals", "Shop", "Map", "Profile"]
    HStack(spacing: 0) {
        ForEach(Array(tabs.enumerated()), id: \.offset) { i, title in
            Button { selection = i } label: {
                Text(title)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(i == selection ? Color.brandPrimary : Color.labelSecondary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 9)
                    .stretchTabPillAnchor(i)
                    .frame(minHeight: 44)
            }
            .buttonStyle(.plain)
            .accessibilityAddTraits(i == selection ? .isSelected : [])
        }
    }
    .padding(4)
    .backgroundPreferenceValue(StretchTabPillAnchors.self) { anchors in
        GeometryReader { geo in
            StretchTabPill(target: anchors[selection].map { geo[$0] }, id: selection, isHidden: false) {
                Capsule().fill(Color.brandLight)
            }
        }
    }
    .background(Color.surfaceSecondary, in: Capsule())
    .padding(24)
    .background(Color.surface)
}
