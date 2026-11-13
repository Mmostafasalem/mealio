import SwiftUI

// MARK: - Fan Cards
//
// Port of designbookmark.com/motion "Fan Cards" (fan-cards/fan.js).
// One fan spring (220, 18) spreads the stack: each card's offset and rotation
// grow around its bottom edge, and the outer cards dip. Each card has its own
// lift (420, 20) and scale (420, 22) spring: pressing a card lifts it 22 pt,
// brings it to the front and grows it 6 %; a tap kicks it up before it opens.
//
// The original fans on hover and browses by itself; here the stack spreads once
// when it comes on screen (no looping demo) and folds again when it leaves.
// Callers show a static list instead under VoiceOver, Reduce Motion and
// accessibility text sizes (see `FanCards.prefersStaticList`).

struct FanCards<Item: Identifiable, Card: View>: View {
    let items: [Item]
    /// Spoken label for a card, e.g. "Vištienos sriuba, 2 of 3 ingredients here".
    let label: (Item) -> String
    var hint: String = "Opens the recipe"
    let onOpen: (Item) -> Void
    @ViewBuilder let card: (Item) -> Card

    @State private var engine = FanCardsEngine()

    static var cardSize: CGSize { FanCardsEngine.cardSize }

    var body: some View {
        let s = engine.snap
        let size = Self.cardSize
        ZStack {
            ForEach(Array(items.enumerated()), id: \.element.id) { i, item in
                let t = s.cards.indices.contains(i) ? s.cards[i] : FanCardsEngine.CardPose()
                Button {
                    engine.kick(i)
                    onOpen(item)
                } label: {
                    card(item)
                        .frame(width: size.width, height: size.height)
                        .contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                }
                .buttonStyle(FanCardPressStyle { pressed in engine.setHot(pressed ? i : nil) })
                .scaleEffect(t.scale, anchor: .bottom)
                .rotationEffect(.degrees(t.rotation), anchor: .bottom)
                .offset(x: t.x, y: t.y)
                .zIndex(t.z)
                .accessibilityLabel(label(item))
                .accessibilityHint(hint)
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: size.height)
        .padding(.top, 34)
        .padding(.bottom, 26)
        .transaction { $0.animation = nil }
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { engine.setWidth($0) }
        .onAppear {
            engine.configure(count: items.count)
            engine.spread(true)
        }
        .onChange(of: items.count) { _, n in engine.configure(count: n) }
        .onDisappear { engine.spread(false, animated: false) }
    }

    /// VoiceOver, Reduce Motion or accessibility text sizes: use a plain list.
    static func prefersStaticList(voiceOver: Bool, reduceMotion: Bool, typeSize: DynamicTypeSize) -> Bool {
        voiceOver || reduceMotion || typeSize.isAccessibilitySize
    }
}

/// Reports press state to the fan; the visual lift comes from the springs.
private struct FanCardPressStyle: ButtonStyle {
    let onPress: (Bool) -> Void

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .onChange(of: configuration.isPressed) { _, pressed in onPress(pressed) }
    }
}

// MARK: - Engine

@MainActor
@Observable
final class FanCardsEngine {
    struct CardPose: Equatable {
        var x: Double = 0
        var y: Double = 0
        var rotation: Double = 0
        var scale: Double = 1
        var z: Double = 0
    }

    struct Snapshot: Equatable {
        var cards: [CardPose] = []
    }

    /// From fan.js.
    static let fanSpring = MotionTokens.Preset(k: 220, c: 18)
    static let liftSpring = MotionTokens.Preset(k: 420, c: 20)
    static let scaleSpring = MotionTokens.Preset(k: 420, c: 22)
    static let maxSpread: Double = 78
    /// Card size from fan.css.
    static let cardSize = CGSize(width: 150, height: 196)

    private(set) var snap = Snapshot()

    @ObservationIgnored private var f = MotionSpring(0, FanCardsEngine.fanSpring)
    @ObservationIgnored private var lift: [MotionSpring] = []
    @ObservationIgnored private var sc: [MotionSpring] = []
    @ObservationIgnored private var hot: Int?
    @ObservationIgnored private var width: Double = 0
    @ObservationIgnored private let clock = MotionClock()

    init() {
        clock.frame = { [weak self] dt in self?.frame(dt) }
        clock.render = { [weak self] in self?.render() }
    }

    func configure(count: Int) {
        guard count != lift.count else { return }
        lift = (0..<count).map { _ in MotionSpring(0, FanCardsEngine.liftSpring) }
        sc = (0..<count).map { _ in MotionSpring(1, FanCardsEngine.scaleSpring) }
        hot = nil
        render()
    }

    func setWidth(_ w: Double) {
        guard w > 0, w != width else { return }
        width = w
        render()
    }

    func spread(_ open: Bool, animated: Bool = true) {
        f.t = open ? 1 : 0
        if !animated || MotionSettings.reduceMotion {
            f.snap(f.t)
            for i in lift.indices { lift[i].snap(0); sc[i].snap(1) }
            hot = nil
            clock.stop()
            render()
        } else {
            clock.start()
        }
    }

    /// The pressed card lifts, comes forward and grows; `nil` lets it back down.
    func setHot(_ i: Int?) {
        hot = i
        for k in lift.indices {
            lift[k].t = k == i ? -22 : 0
            sc[k].t = k == i ? 1.06 : 1
        }
        clock.start()
    }

    /// The tap: a quick upward kick, as in the original's click.
    func kick(_ i: Int) {
        guard lift.indices.contains(i), !MotionSettings.reduceMotion else { return }
        lift[i].v = -260
        clock.start()
    }

    private func frame(_ dt: Double) {
        f.step(dt)
        for i in lift.indices { lift[i].step(dt); sc[i].step(dt) }
    }

    private func render() {
        let n = lift.count
        // the open fan is the card plus (n - 1) steps; narrow sheets get a tighter hand
        let room = width > 0 ? width - Self.cardSize.width - 24 : Self.maxSpread * 2
        let spread = n > 1 ? min(Self.maxSpread, max(20, room / Double(n - 1))) : 0
        let mid = Double(n - 1) / 2
        var s = Snapshot()
        s.cards = (0..<n).map { i in
            let d = Double(i) - mid
            var p = CardPose()
            p.x = d * (6 + f.x * (spread - 6))
            p.rotation = d * (3 + f.x * 9)
            p.y = abs(d) * f.x * 12 + lift[i].x
            p.scale = sc[i].x
            // pressed card in front, then the middle, then outwards
            p.z = i == hot ? 10 : 5 - abs(d)
            return p
        }
        if s != snap { snap = s }

        if clock.isRunning, hot == nil, f.isSettled,
           lift.allSatisfy({ $0.isSettled(within: MotionSpring.points) }), sc.allSatisfy(\.isSettled) {
            clock.stop()
        }
    }
}

// MARK: - Preview

private struct FanPreviewRecipe: Identifiable {
    let id: String
    let name: String
    let symbol: String
}

#Preview("Fan Cards") {
    let recipes = [
        FanPreviewRecipe(id: "a", name: "Vištienos sriuba", symbol: "cup.and.saucer.fill"),
        FanPreviewRecipe(id: "b", name: "Grikių košė su kiaušiniais", symbol: "flame.fill"),
        FanPreviewRecipe(id: "c", name: "Lęšių sriuba", symbol: "drop.fill"),
    ]
    FanCards(items: recipes, label: { $0.name }, onOpen: { _ in }) { r in
        VStack(alignment: .leading, spacing: 8) {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.brandLight)
                .frame(height: 100)
                .overlay(Image(systemName: r.symbol).font(.title).foregroundStyle(Color.rhino))
            Text(r.name).font(.subheadline.weight(.semibold)).lineLimit(2)
            Spacer(minLength: 0)
        }
        .padding(10)
        .background(Color.surface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(Color.hairline))
    }
    .padding()
    .background(Color.surfaceGrouped)
}
