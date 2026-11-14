import SwiftUI
import UIKit

// MARK: - Morph Tooltip
//
// Port of designbookmark.com/motion "Morph Tooltip" (morph-tooltip/tooltip.js).
// One tooltip bubble serves every InfoTooltip inside a host. The first tap pops it
// in place above the "i". After that it travels: the edge facing the new "i" is on
// a stiff spring (620/36) and the other on a soft one (190/19), so it stretches
// across and settles at the new text's size. The old text slides out the way it
// came, the new one slides in from the far side, and the tail follows on its own
// spring. A tap anywhere else in the host hides it after a moment.
// No autoplay (the original walks the toolbar by itself).
//
// Use: put `.morphTooltipHost()` on a container; every `InfoTooltip` inside it uses
// the shared bubble. An InfoTooltip outside a host keeps its own popover.
//
// Reduce Motion: the bubble doesn't travel or scale; it fades out and in at the new place.
// VoiceOver: the text is the button's hint; activating it also speaks the text. No bubble.

extension View {
    /// Makes every `InfoTooltip` inside share one travelling tooltip bubble.
    func morphTooltipHost() -> some View { modifier(MorphTooltipHost()) }
}

private struct MorphTooltipHost: ViewModifier {
    @State private var model = MorphTooltipModel()

    func body(content: Content) -> some View {
        content
            .environment(\.morphTooltip, model)
            .coordinateSpace(.named(MorphTooltipModel.space))
            .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { model.containerWidth = $0 }
            .overlay(alignment: .topLeading) { MorphTooltipLayer(model: model) }
            .simultaneousGesture(TapGesture().onEnded { model.dismissSoon() })
            .onDisappear { model.hideNow() }
    }
}

private struct MorphTooltipKey: EnvironmentKey {
    static let defaultValue: MorphTooltipModel? = nil
}

extension EnvironmentValues {
    var morphTooltip: MorphTooltipModel? {
        get { self[MorphTooltipKey.self] }
        set { self[MorphTooltipKey.self] = newValue }
    }
}

// MARK: - Bubble

private struct MorphTooltipLayer: View {
    let model: MorphTooltipModel

    var body: some View {
        let s = model.snap
        let a = motionClamp(s.shown, 0, 1.15), op = motionClamp(s.shown, 0, 1)
        let scale = s.reduced ? 1 : 0.72 + 0.28 * a
        ZStack(alignment: .topLeading) {
            // tail first, so the bubble covers its upper half
            RoundedRectangle(cornerRadius: 3, style: .continuous)
                .fill(Color.labelPrimary)
                .frame(width: 12, height: 12)
                .rotationEffect(.degrees(45))
                .scaleEffect(s.reduced ? 1 : a)
                .offset(x: s.tailX - 6, y: s.bottom - 7 + (s.reduced ? 0 : (1 - a) * 8))
                .opacity(op)

            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .fill(Color.labelPrimary)
                .frame(width: max(s.right - s.left, 0), height: max(s.bottom - s.top, 0))
                .overlay { labels(s) }
                .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
                .scaleEffect(scale, anchor: UnitPoint(x: 0.5, y: 1.4))
                .offset(x: s.left, y: s.top + (s.reduced ? 0 : (1 - a) * 6))
                .opacity(op)
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private func labels(_ s: MorphTooltipModel.Snapshot) -> some View {
        ZStack {
            ForEach(model.entries) { entry in
                let l = s.labels[entry.id] ?? .init()
                let o = motionClamp(l.opacity, 0, 1)
                Text(entry.text)
                    .font(.caption)
                    .foregroundStyle(Color.surface)
                    .multilineTextAlignment(.leading)
                    .frame(width: MorphTooltipModel.textWidth(for: model.containerWidth), alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, MorphTooltipModel.padH)
                    .padding(.vertical, MorphTooltipModel.padV)
                    .fixedSize()
                    .onGeometryChange(for: CGSize.self) { $0.size } action: { model.setSize($0, for: entry.id) }
                    .offset(y: s.reduced ? 0 : l.dir * (1 - o) * 14)
                    .blur(radius: o > 0.02 && o < 0.98 && !s.reduced ? (1 - o) * 3 : 0)
                    .opacity(o)
            }
        }
    }
}

// MARK: - Model

@MainActor
@Observable
final class MorphTooltipModel {
    struct Entry: Identifiable, Equatable {
        let id: String
        var text: String
    }

    struct LabelState: Equatable {
        var opacity: Double = 0
        var dir: Double = 0
    }

    struct Snapshot: Equatable {
        var left: Double = 0, right: Double = 0, top: Double = 0, bottom: Double = 0
        var tailX: Double = 0
        var shown: Double = 0
        var labels: [String: LabelState] = [:]
        var reduced = false
    }

    nonisolated static let space = "morphTooltip"
    static let padH: Double = 12
    static let padV: Double = 9
    static func textWidth(for container: Double) -> Double {
        max(min(230, container - 16) - 2 * padH, 60)
    }

    private(set) var snap = Snapshot()
    /// Registered tooltips, in the order they appeared.
    private(set) var entries: [Entry] = []
    var containerWidth: Double = 0

    private static let lead = MotionTokens.lead     // 620 36
    private static let trail = MotionTokens.trail   // 190 19

    @ObservationIgnored private var anchors: [String: CGRect] = [:]
    @ObservationIgnored private var sizes: [String: CGSize] = [:]
    @ObservationIgnored private var labelO: [String: MotionSpring] = [:]
    @ObservationIgnored private var labelDir: [String: Double] = [:]
    @ObservationIgnored private var L = MotionSpring(0, MotionTokens.lead)
    @ObservationIgnored private var R = MotionSpring(0, MotionTokens.lead)
    @ObservationIgnored private var T = MotionSpring(0, MotionTokens.lead)
    @ObservationIgnored private var B = MotionSpring(0, MotionTokens.lead)
    @ObservationIgnored private var TX = MotionSpring(0, 300, 22)    // tail centre
    @ObservationIgnored private var A = MotionSpring(0, 420, 26)     // shown
    @ObservationIgnored private var current: String?
    @ObservationIgnored private var hideToken: Int?
    @ObservationIgnored private var lastPoint: CFTimeInterval = 0
    @ObservationIgnored private let clock = MotionClock()

    init() {
        clock.frame = { [weak self] dt in self?.frame(dt) }
        clock.render = { [weak self] in self?.render() }
    }

    // MARK: Registration (InfoTooltip)

    func register(_ id: String, text: String) {
        if let i = entries.firstIndex(where: { $0.id == id }) {
            if entries[i].text != text { entries[i].text = text }
        } else {
            entries.append(Entry(id: id, text: text))
            labelO[id] = MotionSpring(0, MotionTokens.fade)
        }
    }

    func unregister(_ id: String) {
        entries.removeAll { $0.id == id }
        anchors[id] = nil; sizes[id] = nil; labelO[id] = nil; labelDir[id] = nil
        if current == id { hideNow() }
    }

    func setAnchor(_ frame: CGRect, for id: String) {
        anchors[id] = frame
        if id == current { place(id, snap: false); clock.start() }
    }

    func setSize(_ size: CGSize, for id: String) {
        guard sizes[id] != size else { return }
        sizes[id] = size
        if id == current { place(id, snap: A.x < 0.3); clock.start() }
    }

    // MARK: Showing

    /// Show the bubble at this tooltip (a second tap on the same one hides it).
    func point(_ id: String) {
        lastPoint = CACurrentMediaTime()
        if let hideToken { clock.cancel(hideToken); self.hideToken = nil }
        if id == current, A.t == 1 { hide(); return }
        guard anchors[id] != nil else { return }
        let reduce = MotionSettings.reduceMotion

        if A.x < 0.3 || reduce || current == nil {
            // Nothing on screen yet (or Reduce Motion): appear where it is needed.
            place(id, snap: true)
            for key in labelO.keys {
                labelO[key]?.snap(key == id ? 1 : 0)
                labelDir[key] = 0
            }
            if reduce, A.x > 0.3 { A.x = 0 }   // fade out and in at the new place
        } else if let cur = current, let from = anchors[cur], let to = anchors[id] {
            // Travel: the edge facing the move leads, the other one trails.
            let dy = to.midY - from.midY, dx = to.midX - from.midX
            let down = dy >= 0, right = dx >= 0
            B.tune(down ? Self.lead : Self.trail); T.tune(down ? Self.trail : Self.lead)
            R.tune(right ? Self.lead : Self.trail); L.tune(right ? Self.trail : Self.lead)
            place(id, snap: false)
            let dir: Double = dy == 0 ? 0 : (down ? 1 : -1)
            for key in labelO.keys {
                if key == id { labelDir[key] = dir; labelO[key]?.t = 1 }
                else if labelO[key]?.t == 1 { labelDir[key] = -dir; labelO[key]?.t = 0 }
            }
        }
        current = id
        A.t = 1
        clock.start()
    }

    /// A tap somewhere else in the host: hide after a moment, unless that tap was on an "i".
    func dismissSoon() {
        guard current != nil, CACurrentMediaTime() - lastPoint > 0.3 else { return }
        if let hideToken { clock.cancel(hideToken) }
        hideToken = clock.after(0.25) { [weak self] in
            self?.hideToken = nil
            self?.hide()
        }
    }

    func hideNow() {
        if let hideToken { clock.cancel(hideToken); self.hideToken = nil }
        current = nil
        A.snap(0)
        for key in labelO.keys { labelO[key]?.snap(0) }
        render()
    }

    private func hide() {
        A.t = 0
        current = nil
        clock.start()
    }

    /// Bubble above the "i", centred on it but kept inside the host; tail under the glyph.
    private func place(_ id: String, snap: Bool) {
        guard let anchor = anchors[id] else { return }
        let textW = Self.textWidth(for: containerWidth)
        let size = sizes[id] ?? CGSize(width: textW + 2 * Self.padH, height: 48)
        let w = Double(size.width), h = Double(size.height)
        let cx = Double(anchor.midX)
        let left = motionClamp(cx - w / 2, 8, max(8, containerWidth - 8 - w))
        let bottom = Double(anchor.midY) - 16
        L.t = left; R.t = left + w; T.t = bottom - h; B.t = bottom; TX.t = cx
        if snap { L.snap(left); R.snap(left + w); T.snap(bottom - h); B.snap(bottom); TX.snap(cx) }
    }

    // MARK: Simulation

    private func frame(_ dt: Double) {
        L.step(dt); R.step(dt); T.step(dt); B.step(dt); TX.step(dt); A.step(dt)
        for key in labelO.keys { labelO[key]?.step(dt) }
    }

    private func render() {
        var s = Snapshot()
        s.reduced = MotionSettings.reduceMotion
        // Keep a minimum size while the edges cross over.
        let l0 = min(L.x, R.x - 30)
        let t0 = min(T.x, B.x - 24)
        s.left = l0; s.right = R.x; s.top = t0; s.bottom = B.x
        s.tailX = motionClamp(TX.x, l0 + 14, max(l0 + 14, R.x - 14))
        s.shown = A.x
        for (key, o) in labelO { s.labels[key] = LabelState(opacity: o.x, dir: labelDir[key] ?? 0) }
        if s != snap { snap = s }

        let pts = MotionSpring.points
        let settled = [L, R, T, B, TX].allSatisfy { $0.isSettled(within: pts) } && A.isSettled
            && labelO.values.allSatisfy { $0.isSettled } && hideToken == nil
        if settled && clock.isRunning { clock.stop() }
    }
}

// MARK: - Preview

#Preview("Morph Tooltip") {
    VStack(alignment: .leading, spacing: Spacing.sm) {
        Spacer().frame(height: 120)
        ForEach([("Protein", "Protein builds and repairs muscle. Your target is 120g/day based on your weight and goal."),
                 ("Carbs", "Carbohydrates are your body's primary fuel. Choose complex sources like oats, rice, and legumes."),
                 ("Fat", "Healthy fats support hormones and brain function. Include olive oil, nuts, and fatty fish.")],
                id: \.0) { row in
            HStack(spacing: Spacing.sm) {
                Text(row.0).font(.subheadline.weight(.semibold))
                InfoTooltip(text: row.1)
                Spacer()
            }
        }
    }
    .padding(Spacing.lg)
    .background(Color.surface, in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
    .morphTooltipHost()
    .padding(Spacing.lg)
    .background(Color.surfaceGrouped)
}
