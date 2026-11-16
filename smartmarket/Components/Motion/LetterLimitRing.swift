import SwiftUI
import UIKit

// MARK: - Letter limit ring
//
// Port of designbookmark.com/motion "Letter Limit" (letter-limit/limit.js).
// A small ring fills as you type (settle 280 22), turns to the warning colour near
// the limit and to the danger colour at it; the number of characters left shows
// once it gets close. Whatever would take the text past the limit is cut off the
// end and thrown out as letters: each one hops, falls with gravity and spin,
// bounces once, comes to rest on a small pile under the box (the floor rises where
// letters already lie) and then fades. Every refused letter shakes the ring
// (700 12) and pops the count (520 16). Delete and the pile gives back, newest
// first. No autoplay: nothing is typed by itself.
//
// `LetterLimitRing` draws the ring, `LetterLimitPile` the letters; both read one
// `LetterLimitModel`, which the text box feeds through `enforce`.
//
// Reduce Motion: no falling letters and no shake or pop, only the colour change.
// VoiceOver hears the count when it is close and an announcement when text is cut.

@MainActor @Observable
final class LetterLimitModel {

    struct Letter {
        let ch: String
        var x: Double, y: Double
        var vx: Double, vy: Double
        var r: Double = 0, vr: Double
        var rest = false
        var hits = 0
        var bin: Int?
        var restedFor: Double = 0
        var out: Double = 0
        var scale: Double = 1
    }

    static let near = 0.1          // the last 10% is "near" (limit.js: 10 of 60)
    static let maxPile = 24
    static let bin: Double = 10
    static let fadeAfter: Double = 1.4

    private(set) var frame = 0
    private(set) var fill: Double = 0
    private(set) var countScale: Double = 1
    private(set) var shake: Double = 0

    @ObservationIgnored private(set) var letters: [Letter] = []
    @ObservationIgnored private var F = MotionSpring(0, MotionTokens.settle)
    @ObservationIgnored private var CP = MotionSpring(1, MotionTokens.pop)
    @ObservationIgnored private var SH = MotionSpring(0, 700, 12)
    @ObservationIgnored private var bins: [Int: Int] = [:]
    @ObservationIgnored private var length = 0
    @ObservationIgnored private var started = false
    @ObservationIgnored private var lastAnnounce: Date = .distantPast
    @ObservationIgnored private let clock = MotionClock()

    /// Pile geometry, in the pile view's coordinates.
    @ObservationIgnored var width: Double = 320
    @ObservationIgnored var floor: Double = 80
    @ObservationIgnored var origin = CGPoint(x: 280, y: 30)

    init() {
        clock.frame = { [weak self] dt in self?.step(dt) }
        clock.render = { [weak self] in self?.render() }
    }

    /// Cuts `text` to `limit`, throws the rest out, and updates the ring.
    /// Returns the text that fits (the caller writes it back if it changed).
    func enforce(_ text: String, limit: Int) -> String {
        var kept = text
        if text.count > limit {
            let extra = String(text.dropFirst(limit))
            kept = String(text.prefix(limit))
            refuse(extra, limit: limit)
        }
        set(count: kept.count, limit: limit)
        return kept
    }

    func set(count: Int, limit: Int) {
        let was = length
        length = count
        F.t = Double(count) / Double(max(1, limit))
        if !started { started = true; F.snap(F.t); render(); return }
        if count < was {
            // Room was made: the pile gives back as many, newest first.
            var free = was - count
            for i in letters.indices.reversed() where free > 0 && letters[i].out == 0 {
                leave(i); free -= 1
            }
        }
        if count != was && !MotionSettings.reduceMotion { CP.x = max(CP.x, 1.12) }
        clock.start()
    }

    private func refuse(_ chars: String, limit: Int) {
        if Date().timeIntervalSince(lastAnnounce) > 2 {
            lastAnnounce = Date()
            UIAccessibility.post(notification: .announcement,
                                 argument: "Messages can be up to \(limit.formatted()) characters. The extra text was not added.")
        }
        UIImpactFeedbackGenerator(style: .rigid).impactOccurred(intensity: 0.6)
        guard !MotionSettings.reduceMotion else { return }
        for (i, ch) in chars.prefix(Self.maxPile).enumerated() {
            let s = String(ch)
            guard !s.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { continue }
            letters.append(Letter(ch: s, x: origin.x - 4 - Double(i) * 9, y: origin.y,
                                  // thrown back over the text, away from the edge
                                  vx: 40 - Double.random(in: 0...150), vy: -150 - Double.random(in: 0...110),
                                  vr: Double.random(in: -360...360)))
        }
        var live = letters.filter { $0.out == 0 }.count
        var i = 0
        while live > Self.maxPile, i < letters.count {
            if letters[i].out == 0 { leave(i); live -= 1 }
            i += 1
        }
        SH.v += 34
        CP.x = 1.25
        clock.start()
    }

    func stop() {
        letters.removeAll(); bins.removeAll()
        F.snap(F.t); CP.snap(1); SH.snap(0)
        render()
        clock.stop()
    }

    private func leave(_ i: Int) {
        guard letters[i].out == 0 else { return }
        letters[i].out = 0.001
        letters[i].vy = -230
        letters[i].rest = false
        if let b = letters[i].bin { bins[b] = max(0, (bins[b] ?? 0) - 1); letters[i].bin = nil }
    }

    private func step(_ dt: Double) {
        F.step(dt); CP.step(dt); SH.step(dt)
        for i in letters.indices {
            if letters[i].out > 0 {
                letters[i].out += dt
                letters[i].vy += 900 * dt
                letters[i].y += letters[i].vy * dt
                letters[i].scale = max(0, 1 - letters[i].out / 0.32)
                continue
            }
            if letters[i].rest {
                letters[i].restedFor += dt
                if letters[i].restedFor > Self.fadeAfter { leave(i) }
                continue
            }
            letters[i].vy += 1900 * dt
            letters[i].x += letters[i].vx * dt
            letters[i].y += letters[i].vy * dt
            letters[i].r += letters[i].vr * dt
            if letters[i].x < 10 { letters[i].x = 10; letters[i].vx = abs(letters[i].vx) * 0.5 }
            else if letters[i].x > width - 10 { letters[i].x = width - 10; letters[i].vx = -abs(letters[i].vx) * 0.5 }
            let b = Int((letters[i].x / Self.bin).rounded())
            let ground = floor - Double(bins[b] ?? 0) * 7
            if letters[i].y >= ground && letters[i].vy > 0 {
                letters[i].y = ground
                if letters[i].hits < 1 && letters[i].vy > 260 {
                    letters[i].hits += 1
                    letters[i].vy *= -0.3; letters[i].vx *= 0.6; letters[i].vr *= 0.5
                } else {
                    // It stays: lie down on the nearest side, and raise the floor here.
                    letters[i].rest = true
                    letters[i].bin = b
                    bins[b] = min(3, (bins[b] ?? 0) + 1)
                    letters[i].r = (letters[i].r / 90).rounded() * 90 + Double.random(in: -17...17)
                }
            }
        }
        letters.removeAll { $0.out > 0.34 }
    }

    private func render() {
        fill = motionClamp(F.x, 0, 1)
        countScale = CP.x
        shake = SH.x * 0.5
        frame &+= 1
        if clock.isRunning, letters.isEmpty, F.isSettled, CP.isSettled, SH.isSettled(within: MotionSpring.points) {
            F.snap(F.t); CP.snap(1); SH.snap(0)
            fill = motionClamp(F.x, 0, 1); countScale = 1; shake = 0
            clock.stop()
        }
    }
}

// MARK: - Ring

struct LetterLimitRing: View {
    let model: LetterLimitModel
    let count: Int
    let limit: Int

    @ScaledMetric(relativeTo: .footnote) private var size: CGFloat = 20

    private var left: Int { limit - count }
    private var isNear: Bool { Double(left) <= Double(limit) * LetterLimitModel.near && left > 0 }
    private var isFull: Bool { left <= 0 }
    private var tone: Color { isFull ? .brandDanger : (isNear ? .progress : .labelSecondary) }

    var body: some View {
        HStack(spacing: 4) {
            if isNear || isFull {
                Text(left, format: .number)
                    .font(.caption.weight(.medium))
                    .monospacedDigit()
                    .foregroundStyle(isFull ? Color.brandDanger : Color.labelSecondary)
                    .scaleEffect(model.countScale)
                    .offset(x: model.shake)
            }
            ZStack {
                Circle().stroke(Color.progressTrack, lineWidth: size * 0.13)
                Circle()
                    .trim(from: 0, to: model.fill)
                    .stroke(tone, style: StrokeStyle(lineWidth: size * 0.13, lineCap: .round))
                    .rotationEffect(.degrees(-90))
            }
            .frame(width: size, height: size)
            .offset(x: model.shake)
            .animation(.easeOut(duration: 0.2), value: tone)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Characters left")
        .accessibilityValue("\(left.formatted()) of \(limit.formatted())")
        .accessibilityHidden(!(isNear || isFull))
    }
}

// MARK: - Pile

/// The refused letters. Place it over the text box; letters fall to `floorInset`
/// below the box's bottom edge. Never takes touches.
struct LetterLimitPile: View {
    let model: LetterLimitModel
    /// Where letters leave from, in this view's coordinates.
    var origin: CGPoint
    var floorInset: CGFloat = 8

    var body: some View {
        let frame = model.frame
        Canvas { ctx, size in
            _ = frame
            let font = Font.footnote.weight(.semibold)
            for l in model.letters {
                var c = ctx
                c.opacity = l.out > 0 ? l.scale : 1
                c.translateBy(x: l.x, y: l.y)
                c.rotate(by: .degrees(l.r))
                c.scaleBy(x: l.scale, y: l.scale)
                c.draw(Text(l.ch).font(font).foregroundStyle(l.rest ? Color.labelSecondary : Color.brandDanger),
                       at: .zero, anchor: .center)
            }
        }
        .onGeometryChange(for: CGSize.self) { $0.size } action: { size in
            model.width = size.width
            model.floor = size.height + floorInset
        }
        .onChange(of: origin, initial: true) { _, o in model.origin = o }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

// MARK: - Preview

#Preview("Letter limit") {
    struct Demo: View {
        @State private var text = "A short note about tonight's dinner"
        @State private var model = LetterLimitModel()
        let limit = 60
        var body: some View {
            VStack(alignment: .leading, spacing: Spacing.md) {
                HStack(alignment: .bottom) {
                    TextField("Ask about meals or groceries…", text: $text, axis: .vertical)
                        .lineLimit(1...4)
                    LetterLimitRing(model: model, count: text.count, limit: limit)
                }
                .padding(Spacing.lg)
                .background(Color.surface, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
                .overlay { LetterLimitPile(model: model, origin: CGPoint(x: 260, y: 24)) }
                .onChange(of: text, initial: true) { _, t in
                    let kept = model.enforce(t, limit: limit)
                    if kept != t { text = kept }
                }
                Spacer().frame(height: 40)
                Text("Type past 60 characters to see the extra letters fall.")
                    .font(.footnote).foregroundStyle(Color.labelSecondary)
            }
            .padding(Spacing.lg)
            .frame(maxHeight: .infinity)
            .background(Color.surfaceGrouped)
        }
    }
    return Demo()
}
