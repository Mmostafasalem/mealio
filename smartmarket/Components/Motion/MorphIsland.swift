import SwiftUI

// MARK: - Morph Island
//
// Port of designbookmark.com/motion "Morph Island" (morph-island/island.js).
// One pill whose width, height and radius are springs. Width (380/24) is stiffer
// than height (300/22), so every change lands sideways first and then drops into
// place; while the height moves fast the width gives a little back. Content
// cross-fades with blur while the shape morphs. No autoplay: it only shows the
// notice it is handed, and hides when handed nil.
//
// Layout: the island floats at the top. It reserves layout space only for compact
// notices (a status pill), so an expanded card floats over the content instead of
// pushing the page down while the person is scrolled.
//
// Reduce Motion: the shape jumps to its new size and only opacity moves.

enum MorphIslandStyle: Equatable {
    /// A status pill, sized to its content.
    case compact
    /// A card as wide as the container.
    case expanded
}

struct MorphIsland<Item: Identifiable & Equatable, Content: View>: View {
    let item: Item?
    var style: (Item) -> MorphIslandStyle
    @ViewBuilder var content: (Item) -> Content

    @State private var engine = MorphIslandEngine()
    /// The notice on show plus any still fading out.
    @State private var layers: [Item] = []
    @State private var width: CGFloat = 0

    init(item: Item?,
         style: @escaping (Item) -> MorphIslandStyle,
         @ViewBuilder content: @escaping (Item) -> Content) {
        self.item = item
        self.style = style
        self.content = content
    }

    var body: some View {
        Color.clear
            .frame(maxWidth: .infinity)
            .frame(height: engine.snap.reserve)
            .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width = $0 }
            .overlay(alignment: .top) { island }
            .onAppear { sync() }
            .onChange(of: item) { _, _ in sync() }
            .onChange(of: engine.snap.live) { _, live in
                layers.removeAll { !live.contains(AnyHashable($0.id)) && $0.id != item?.id }
            }
    }

    @ViewBuilder private var island: some View {
        let s = engine.snap
        if s.visible {
            ZStack {
                ForEach(layers) { layer in
                    let key = AnyHashable(layer.id)
                    let o = s.opacity[key] ?? 0
                    let isCurrent = layer.id == item?.id
                    sized(content(layer), style(layer))
                        .onGeometryChange(for: CGSize.self) { $0.size } action: { size in
                            engine.setSize(size, for: key)
                        }
                        .opacity(o)
                        .blur(radius: s.reduced ? 0 : (1 - o) * 6)
                        .scaleEffect(s.reduced ? 1 : 0.9 + 0.1 * o)
                        .allowsHitTesting(isCurrent)
                        .accessibilityHidden(!isCurrent)
                }
            }
            .frame(width: max(s.width, 0), height: max(s.height, 0))
            .background(Color.surface)
            .clipShape(RoundedRectangle(cornerRadius: s.radius, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: s.radius, style: .continuous)
                .strokeBorder(Color.hairline, lineWidth: 0.5))
            .elevation(Elevation.high)
            .opacity(s.presence)
            .padding(.top, MorphIslandEngine.topGap)
        }
    }

    @ViewBuilder private func sized(_ view: Content, _ style: MorphIslandStyle) -> some View {
        switch style {
        case .compact:
            view.fixedSize()
        case .expanded:
            view
                .frame(width: max(width - 2 * Spacing.lg, 0))
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func sync() {
        if let item {
            if !layers.contains(where: { $0.id == item.id }) { layers.append(item) }
            engine.show(AnyHashable(item.id), style: style(item))
        } else {
            engine.show(nil, style: .compact)
        }
    }
}

// MARK: - Engine

@MainActor
@Observable
final class MorphIslandEngine {
    struct Snapshot: Equatable {
        var width: Double = 0
        var height: Double = 0
        var radius: Double = 0
        var reserve: Double = 0
        var presence: Double = 0
        var opacity: [AnyHashable: Double] = [:]
        /// Layers still on screen (current, or fading out).
        var live: Set<AnyHashable> = []
        var visible = false
        var reduced = false
    }

    // tokens.css: --island-w 380 24, --island-h 300 22, --island-radius 32
    static let maxRadius: Double = 32
    static let topGap: Double = Spacing.xs
    /// Room under a compact pill before the content starts.
    static let reserveGap: Double = Spacing.sm

    private(set) var snap = Snapshot()

    @ObservationIgnored private var W = MotionSpring(0, 380, 24)
    @ObservationIgnored private var H = MotionSpring(0, 300, 22)
    @ObservationIgnored private var R = MotionSpring(0, 300, 22)        // reserved layout height
    @ObservationIgnored private var P = MotionSpring(0, MotionTokens.fade) // presence
    @ObservationIgnored private var layerO: [AnyHashable: MotionSpring] = [:]
    @ObservationIgnored private var sizes: [AnyHashable: CGSize] = [:]
    @ObservationIgnored private var current: AnyHashable?
    @ObservationIgnored private var currentStyle: MorphIslandStyle = .compact
    @ObservationIgnored private var fadeInToken: Int?
    @ObservationIgnored private let clock = MotionClock()

    init() {
        clock.frame = { [weak self] dt in self?.frame(dt) }
        clock.render = { [weak self] in self?.render() }
    }

    func show(_ id: AnyHashable?, style: MorphIslandStyle) {
        guard id != current || style != currentStyle else { return }
        let previous = current
        current = id
        currentStyle = style
        if let fadeInToken { clock.cancel(fadeInToken) }
        fadeInToken = nil

        // The outgoing content leaves now; the incoming one waits a beat (0.09 s in the original).
        for key in layerO.keys where key != id { layerO[key]?.t = 0 }
        if let id {
            if layerO[id] == nil { layerO[id] = MotionSpring(0, MotionTokens.fade) }
            if previous == nil || MotionSettings.reduceMotion {
                layerO[id]?.t = 1
            } else {
                fadeInToken = clock.after(0.09) { [weak self] in
                    self?.layerO[id]?.t = 1
                    self?.fadeInToken = nil
                }
            }
            P.t = 1
            retarget()
        } else {
            // Hide: shrink up into a small pill and fade.
            P.t = 0
            H.tune(300 * 1.3, 22)
            H.t = 0
            W.t = W.x * 0.5
            R.t = 0
            if MotionSettings.reduceMotion { W.snap(W.t); H.snap(0) }
        }
        publish()
        clock.start()
    }

    func setSize(_ size: CGSize, for id: AnyHashable) {
        guard sizes[id] != size else { return }
        sizes[id] = size
        if id == current { retarget() }
        clock.start()
    }

    private func retarget() {
        guard let current, let size = sizes[current] else { return }
        let w = Double(size.width), h = Double(size.height)
        let appearing = P.x < 0.05 && H.x < 1
        if appearing {
            // Grow out of a small pill at the top.
            W.snap(w * 0.4); H.snap(0)
        }
        let grow = w * h > W.t * H.t
        W.tune(380, 24)
        H.tune(300 * (grow ? 1 : 1.3), 22)
        W.t = w; H.t = h
        switch currentStyle {
        case .compact: R.t = h + Self.reserveGap
        case .expanded: break   // floats over the content; keep whatever was reserved
        }
        if MotionSettings.reduceMotion { W.snap(w); H.snap(h) }
    }

    // MARK: Simulation

    private func frame(_ dt: Double) {
        W.step(dt); H.step(dt); R.step(dt); P.step(dt)
        for key in layerO.keys { layerO[key]?.step(dt) }
    }

    private func render() {
        // Drop layers that have finished fading out.
        for (key, o) in layerO where key != current && o.t == 0 && o.isSettled(within: 0.01) {
            layerO[key] = nil
        }
        publish()
        let pts = MotionSpring.points
        let settled = W.isSettled(within: pts) && H.isSettled(within: pts) && R.isSettled(within: pts)
            && P.isSettled && layerO.values.allSatisfy { $0.isSettled } && fadeInToken == nil
        if settled && clock.isRunning {
            if current == nil { layerO.removeAll(); publish() }
            clock.stop()
        }
    }

    private func publish() {
        let reduce = MotionSettings.reduceMotion
        var s = Snapshot()
        s.reduced = reduce
        let h = max(H.x, 0)
        // Volume: while the height moves fast the width gives back a little.
        let give = reduce ? 0 : motionClamp(-H.v / 7000, -0.05, 0.05)
        s.width = max(W.x * (1 + give), 0)
        s.height = h
        s.radius = min(h / 2, Self.maxRadius)
        s.reserve = max(R.x, 0)
        s.presence = motionClamp(P.x, 0, 1)
        s.opacity = layerO.mapValues { motionClamp($0.x, 0, 1) }
        s.live = Set(layerO.keys)
        s.visible = current != nil || P.x > 0.01
        if s != snap { snap = s }
    }
}

// MARK: - Preview

private enum PreviewNotice: String, Identifiable, CaseIterable {
    case offline, online, deal
    var id: String { rawValue }
}

#Preview("Morph Island") {
    @Previewable @State var notice: PreviewNotice? = .offline
    VStack(spacing: Spacing.lg) {
        MorphIsland(item: notice, style: { $0 == .deal ? .expanded : .compact }) { n in
            switch n {
            case .offline:
                Label("Offline · using saved data", systemImage: "wifi.slash")
                    .font(.footnote.weight(.semibold))
                    .padding(.horizontal, 14).padding(.vertical, 9)
            case .online:
                Label("Back online", systemImage: "wifi")
                    .font(.footnote.weight(.semibold))
                    .padding(.horizontal, 14).padding(.vertical, 9)
            case .deal:
                VStack(alignment: .leading, spacing: Spacing.sm) {
                    Text("Greek yogurt 2%").font(.headline)
                    Text("Rimi Akropolis · 400g").font(.footnote).foregroundStyle(Color.labelSecondary)
                    HStack {
                        Button("Skip") { notice = .offline }
                        Spacer()
                        Button("Add to list") { notice = nil }
                    }
                }
                .padding(Spacing.lg)
            }
        }
        .foregroundStyle(Color.labelPrimary)
        Spacer()
        HStack {
            ForEach(PreviewNotice.allCases) { n in Button(n.rawValue) { notice = n } }
            Button("none") { notice = nil }
        }
        .buttonStyle(.bordered)
    }
    .padding(.vertical, Spacing.lg)
    .background(Color.surfaceGrouped)
}
