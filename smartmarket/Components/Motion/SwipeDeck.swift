import SwiftUI

// MARK: - Swipe Deck
//
// Port of designbookmark.com/motion "Swipe Deck" (swipe-deck/deck.js).
// The top card follows the finger (--deck-drag 900/50) and tilts around the
// point you grabbed it by (0.065° per point, the other way when grabbed by the
// bottom half). The cards behind rise as you drag: their depth (260/22) eases
// by your progress. Past --deck-threshold (110 pt) or a fast throw (> 700 pt/s)
// it flies off (70/17, damped so it keeps going) and the next card is on top at
// once; otherwise it snaps back on --deck-return (280/16). Right = accept,
// left = skip. Decided cards leave the deck instead of recycling to the back
// like the demo; an empty deck shows `empty`. No autoplay, no keys.
// Reduce Motion: no tilt; a decided card fades out where it is instead of flying.
//
// Accessibility: the top card is one element with "accept" and "skip" actions;
// the cards behind are hidden. Put visible buttons under the deck too.

struct SwipeDeck<Item: Identifiable, Card: View, Empty: View>: View {
    let items: [Item]
    var acceptLabel: String = "Add to groceries"
    var skipLabel: String = "Skip"
    var acceptSymbol: String = "cart.badge.plus"
    var skipSymbol: String = "xmark"
    /// VoiceOver label of a card.
    let label: (Item) -> String
    /// Called as soon as a card is thrown (or a button / action decides it). Remove it from `items`.
    let onDecide: (Item, _ accepted: Bool) -> Void
    @ViewBuilder let card: (Item) -> Card
    @ViewBuilder let empty: () -> Empty

    @State private var model = SwipeDeckModel()
    /// Thrown cards stay drawn until they have flown off.
    @State private var flying: [Item] = []
    @State private var drag: DragState?
    @GestureState private var isDragging = false
    @State private var decisions = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private struct DragState {
        var key: AnyHashable
        var engaged: Bool?
    }

    private static var threshold: Double { 110 }
    private static var maxVisible: Int { 3 }

    var body: some View {
        let flyingKeys = Set(flying.map { AnyHashable($0.id) })
        let visible = Array(items.filter { !flyingKeys.contains(AnyHashable($0.id)) }.prefix(Self.maxVisible + 1))
        VStack(spacing: Spacing.md) {
            deck(visible)
            if let top = visible.first { buttons(top) }
        }
        .sensoryFeedback(.impact(weight: .light), trigger: decisions)
        .onAppear { model.sync(items.map { AnyHashable($0.id) }) }
        .onChange(of: items.map { AnyHashable($0.id) }) { _, ids in model.sync(ids) }
        .onChange(of: isDragging) { _, active in
            // A cancelled drag (no onEnded): put the card back.
            if !active, let d = drag {
                if d.engaged == true { model.release(d.key) }
                drag = nil
            }
        }
        .onDisappear { model.stop() }
    }

    private func deck(_ visible: [Item]) -> some View {
        let p = model.progress(threshold: Self.threshold)
        return DeckLayout {
            ForEach(Array(visible.reversed())) { item in
                let key = AnyHashable(item.id)
                let isTop = item.id == visible.first?.id
                cardView(item, key: key, isTop: isTop, rise: isTop ? 0 : p)
            }
            ForEach(flying) { item in
                cardView(item, key: AnyHashable(item.id), isTop: false, rise: 0)
            }
        }
        .background {
            GeometryReader { g in
                Color.clear
                    .onAppear { model.cardSize = g.size }
                    .onChange(of: g.size) { _, size in model.cardSize = size }
            }
        }
        .overlay {
            if items.isEmpty && flying.isEmpty {
                empty().transition(.opacity)
            }
        }
        // Room for the cards behind, which peek out 10 pt per level below the top one.
        .padding(.bottom, CGFloat(min(max(visible.count - 1, 0), 3)) * 10)
        .frame(minHeight: items.isEmpty && flying.isEmpty ? 120 : nil)
        .animation(reduceMotion ? .reducedFade : .smoothCard, value: items.isEmpty && flying.isEmpty)
    }

    /// For people who don't swipe; they decide the top card the same way.
    private func buttons(_ top: Item) -> some View {
        HStack(spacing: Spacing.sm) {
            Button { decide(top, accepted: false) } label: {
                Label(skipLabel, systemImage: skipSymbol)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.labelPrimary)
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .background(Color.surfaceSecondary, in: RoundedRectangle(cornerRadius: Radius.chip, style: .continuous))
                    .contentShape(RoundedRectangle(cornerRadius: Radius.chip, style: .continuous))
            }
            .accessibilityIdentifier("swipeDeck.skip")
            Button { decide(top, accepted: true) } label: {
                Label(acceptLabel, systemImage: acceptSymbol)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.onAccent)
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .background(Color.progress, in: RoundedRectangle(cornerRadius: Radius.chip, style: .continuous))
                    .contentShape(RoundedRectangle(cornerRadius: Radius.chip, style: .continuous))
            }
            .accessibilityIdentifier("swipeDeck.accept")
        }
        .buttonStyle(ScalePressStyle())
    }

    // MARK: Card

    private func cardView(_ item: Item, key: AnyHashable, isTop: Bool, rise: Double) -> some View {
        let s = model.state(for: key, rise: rise)
        let tilt = reduceMotion ? 0 : s.x * 0.065 * s.grabSign
        return card(item)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(Color.surface, in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
            .overlay {
                // No shadows: each card behind is a step deeper, that separates them.
                RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
                    .fill(Color.surfaceGrouped.opacity(min(s.depth, 3) * 0.22))
                    .allowsHitTesting(false)
            }
            .overlay(RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
                .strokeBorder(Color.hairline, lineWidth: 0.5))
            .overlay(alignment: .topLeading) {
                stamp(acceptLabel, fill: Color.progress, ink: Color.onAccent, angle: -10)
                    .opacity(isTop || s.flying ? motionClamp(s.x / Self.threshold, 0, 1) : 0)
                    .padding(Spacing.md)
            }
            .overlay(alignment: .topTrailing) {
                stamp(skipLabel, fill: Color.labelPrimary, ink: Color.surface, angle: 10)
                    .opacity(isTop || s.flying ? motionClamp(-s.x / Self.threshold, 0, 1) : 0)
                    .padding(Spacing.md)
            }
            .scaleEffect(1 - min(s.depth, 3) * 0.055, anchor: .bottom)
            .rotationEffect(.degrees(tilt), anchor: s.anchor)
            .offset(x: s.x, y: s.y + min(s.depth, 3) * 10)
            .opacity(motionClamp(3.6 - s.depth, 0, 1) * s.opacity)
            .zIndex(s.flying ? 50 : 40 - s.depthTarget)
            .allowsHitTesting(isTop)
            // Simultaneous, so a vertical swipe that starts on a card still scrolls the page.
            .simultaneousGesture(dragGesture(item, key: key), including: isTop ? .all : .subviews)
            .accessibilityElement(children: .combine)
            .accessibilityLabel(label(item))
            .accessibilityHint("Swipe right or use actions to \(acceptLabel.lowercased()), left to \(skipLabel.lowercased())")
            .accessibilityAction(named: acceptLabel) { decide(item, accepted: true) }
            .accessibilityAction(named: skipLabel) { decide(item, accepted: false) }
            .accessibilityHidden(!isTop)
    }

    private func stamp(_ text: String, fill: Color, ink: Color, angle: Double) -> some View {
        Text(text)
            .font(.caption.weight(.bold))
            .textCase(.uppercase)
            .foregroundStyle(ink)
            .padding(.horizontal, 10).padding(.vertical, 5)
            .background(fill, in: Capsule())
            .rotationEffect(.degrees(reduceMotion ? 0 : angle))
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }

    // MARK: Drag

    private func dragGesture(_ item: Item, key: AnyHashable) -> some Gesture {
        DragGesture(minimumDistance: 8, coordinateSpace: .local)
            .updating($isDragging) { _, active, _ in active = true }
            .onChanged { v in
                if drag == nil {
                    drag = DragState(key: key, engaged: nil)
                }
                if drag?.engaged == nil {
                    // Lock to an axis on the first movement, so a vertical swipe still scrolls the page.
                    let dx = abs(v.translation.width), dy = abs(v.translation.height)
                    guard dx > 6 || dy > 6 else { return }
                    let horizontal = dx > dy
                    drag?.engaged = horizontal
                    if horizontal {
                        model.grab(key, at: v.startLocation)
                    }
                }
                guard drag?.engaged == true else { return }
                model.move(key, x: v.translation.width, y: v.translation.height * 0.6)
            }
            .onEnded { v in
                defer { drag = nil }
                guard drag?.engaged == true else { return }
                let x = v.translation.width
                let vx = v.velocity.width
                let dir: Double
                if abs(x) > Self.threshold { dir = x > 0 ? 1 : -1 }
                else if abs(vx) > 700, (x == 0 || (x > 0) == (vx > 0)) { dir = vx > 0 ? 1 : -1 }
                else { dir = 0 }
                if dir != 0 {
                    throwCard(item, dir: dir, vx: vx, vy: v.velocity.height)
                } else {
                    model.release(key)
                }
            }
    }

    // MARK: Decide

    private func decide(_ item: Item, accepted: Bool) {
        throwCard(item, dir: accepted ? 1 : -1, vx: 0, vy: 0)
    }

    private func throwCard(_ item: Item, dir: Double, vx: Double, vy: Double) {
        let key = AnyHashable(item.id)
        guard !flying.contains(where: { AnyHashable($0.id) == key }) else { return }
        flying.append(item)
        decisions += 1
        model.fling(key, dir: dir, vx: vx, vy: vy, threshold: Self.threshold) {
            flying.removeAll { AnyHashable($0.id) == key }
        }
        onDecide(item, dir > 0)
    }
}

/// Stacks every card in the same frame, sized to the tallest one.
private struct DeckLayout: Layout {
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let w = proposal.width ?? 320
        let h = subviews.map { $0.sizeThatFits(ProposedViewSize(width: w, height: nil)).height }.max() ?? 0
        return CGSize(width: w, height: h)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        for s in subviews {
            s.place(at: bounds.origin, anchor: .topLeading, proposal: ProposedViewSize(bounds.size))
        }
    }
}

// MARK: - Engine

@MainActor
@Observable
final class SwipeDeckModel {
    struct CardState {
        var x: Double = 0
        var y: Double = 0
        var depth: Double = 0
        var depthTarget: Double = 0
        var opacity: Double = 1
        var grabSign: Double = 1
        var anchor: UnitPoint = .center
        var flying = false
    }

    /// Size of the deck, for the grab point and how far a thrown card travels.
    @ObservationIgnored var cardSize = CGSize(width: 320, height: 140)

    private(set) var revision = 0

    @ObservationIgnored private var cards: [AnyHashable: Springs] = [:]
    @ObservationIgnored private var order: [AnyHashable] = []
    @ObservationIgnored private var topKey: AnyHashable?
    @ObservationIgnored private let clock = MotionClock()

    static let drag = MotionTokens.Preset(k: 900, c: 50)    // --deck-drag
    static let back = MotionTokens.Preset(k: 280, c: 16)    // --deck-return
    static let fly = MotionTokens.Preset(k: 70, c: 17)

    private struct Springs {
        var x = MotionSpring(0, SwipeDeckModel.drag)
        var y = MotionSpring(0, SwipeDeckModel.drag)
        var d: MotionSpring
        var o = MotionSpring(1, MotionTokens.fade)
        var grabSign: Double = 1
        var anchor: UnitPoint = .center
        var flying = false
        init(depth: Double) { d = MotionSpring(depth, 260, 22) }
    }

    init() {
        clock.frame = { [weak self] dt in self?.frame(dt) }
        clock.render = { [weak self] in self?.render() }
    }

    func state(for key: AnyHashable, rise: Double) -> CardState {
        _ = revision
        guard let c = cards[key] else { return CardState() }
        let depth = max(0, c.d.x - (c.flying ? 0 : rise))
        return CardState(x: c.x.x, y: c.y.x, depth: depth, depthTarget: c.d.t,
                         opacity: motionClamp(c.o.x, 0, 1), grabSign: c.grabSign,
                         anchor: c.anchor, flying: c.flying)
    }

    /// Drag progress of the top card, 0…1 (how far the cards behind have risen).
    func progress(threshold: Double) -> Double {
        _ = revision
        guard let topKey, let c = cards[topKey], !c.flying else { return 0 }
        return motionClamp(abs(c.x.x) / (threshold * 1.6), 0, 1)
    }

    /// The remaining cards, top first.
    func sync(_ ids: [AnyHashable]) {
        let first = cards.isEmpty
        for (i, id) in ids.enumerated() {
            if cards[id] == nil {
                // A card joining later comes up from deeper than the last one.
                cards[id] = Springs(depth: first ? Double(i) : Double(ids.count) + 0.5)
            }
            cards[id]!.d.t = Double(i)
        }
        // Forget cards that left and are not flying.
        for key in cards.keys where !ids.contains(key) && !(cards[key]!.flying) { cards[key] = nil }
        order = ids
        topKey = ids.first
        revision += 1
        clock.start()
    }

    func grab(_ key: AnyHashable, at point: CGPoint) {
        guard cards[key] != nil else { return }
        let w = max(cardSize.width, 1), h = max(cardSize.height, 1)
        // Grabbed by the top it tilts one way, by the bottom the other, pivoting on the finger.
        cards[key]!.grabSign = point.y < h / 2 ? 1 : -1
        cards[key]!.anchor = UnitPoint(x: motionClamp(point.x / w, 0, 1), y: motionClamp(point.y / h, 0, 1))
        cards[key]!.x.tune(Self.drag); cards[key]!.y.tune(Self.drag)
        clock.maxFramesPerSecond = 120
    }

    func move(_ key: AnyHashable, x: Double, y: Double) {
        guard cards[key] != nil else { return }
        cards[key]!.x.t = x
        cards[key]!.y.t = y
        clock.start()
    }

    func release(_ key: AnyHashable) {
        clock.maxFramesPerSecond = 60
        guard cards[key] != nil else { return }
        cards[key]!.x.tune(Self.back); cards[key]!.y.tune(Self.back)
        cards[key]!.x.t = 0; cards[key]!.y.t = 0
        clock.start()
    }

    func fling(_ key: AnyHashable, dir: Double, vx: Double, vy: Double, threshold: Double,
               done: @escaping () -> Void) {
        clock.maxFramesPerSecond = 60
        guard var c = cards[key], !c.flying else { done(); return }
        // The cards behind had risen with the drag; bake that rise into their
        // springs now so they don't drop back a level and rise again.
        let p = motionClamp(abs(c.x.x) / (threshold * 1.6), 0, 1)
        for k in cards.keys where k != key { cards[k]!.d.x = max(0, cards[k]!.d.x - p) }
        c.flying = true
        if MotionSettings.reduceMotion {
            c.o.t = 0
        } else {
            c.x.tune(Self.fly); c.y.tune(Self.fly)
            c.x.v = dir * max(abs(vx), 1500)
            c.x.t = dir * max(cardSize.width + 240, abs(c.x.x) + 420)    // always ahead of it
            c.y.t = c.y.x + motionClamp(vy * 0.2, -120, 120)
            c.o.t = 0
            c.o.tune(60, 16)    // fades late, while it is already off to the side
        }
        cards[key] = c
        clock.after(0.42) { [weak self] in
            self?.cards[key] = nil
            self?.revision += 1
            done()
        }
        clock.start()
    }

    func stop() {
        for key in cards.keys {
            cards[key]!.x.snap(0); cards[key]!.y.snap(0)
            cards[key]!.d.snap(cards[key]!.d.t)
        }
        revision += 1
        clock.stop()
    }

    private func frame(_ dt: Double) {
        for key in cards.keys {
            cards[key]!.x.step(dt); cards[key]!.y.step(dt); cards[key]!.d.step(dt); cards[key]!.o.step(dt)
        }
    }

    private func render() {
        revision += 1
        let anyFlying = cards.values.contains(where: \.flying)
        let settled = cards.values.allSatisfy {
            $0.x.isSettled(within: MotionSpring.points) && $0.y.isSettled(within: MotionSpring.points)
                && $0.d.isSettled && $0.o.isSettled
        }
        if clock.isRunning, !anyFlying, settled, clock.maxFramesPerSecond < 120 {
            for key in cards.keys {
                cards[key]!.x.snap(cards[key]!.x.t); cards[key]!.y.snap(cards[key]!.y.t)
                cards[key]!.d.snap(cards[key]!.d.t)
            }
            clock.stop()
        }
    }
}

// MARK: - Preview

private struct PreviewRecommendation: Identifiable {
    let id: String
    let name: String
    let reason: String
    let store: String
    let price: Double
}

#Preview("Swipe Deck") {
    @Previewable @State var items = [
        PreviewRecommendation(id: "1", name: "Greek yogurt", reason: "Adds 20 g of protein to reach today's goal.", store: "Maxima", price: 1.89),
        PreviewRecommendation(id: "2", name: "Buckwheat", reason: "Slow carbs for dinner, fits your budget.", store: "Rimi", price: 1.29),
        PreviewRecommendation(id: "3", name: "Salmon fillet", reason: "Healthy fats you are short on this week.", store: "Lidl", price: 5.49),
    ]
    VStack(alignment: .leading, spacing: Spacing.md) {
        Text("Gaps & Recommendations").font(.headline)
        SwipeDeck(items: items, label: { "\($0.name). \($0.reason)" },
                  onDecide: { item, _ in items.removeAll { $0.id == item.id } }) { item in
            VStack(alignment: .leading, spacing: 4) {
                Text(item.name).font(.headline)
                Text(item.reason).font(.subheadline).foregroundStyle(Color.labelSecondary)
                Text("\(item.store) · €\(String(format: "%.2f", item.price))")
                    .font(.caption).foregroundStyle(Color.labelSecondary)
            }
            .padding(Spacing.lg)
        } empty: {
            Label("All done", systemImage: "checkmark.circle")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Color.labelSecondary)
        }
    }
    .padding(Spacing.lg)
    .background(Color.surfaceGrouped)
}
