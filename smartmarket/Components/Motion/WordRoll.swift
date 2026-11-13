import SwiftUI

// MARK: - Word Roll
//
// Port of designbookmark.com/motion "Word Roll" (word-roll/roll.js).
// The last phrase rolls up and out letter by letter while the next one rolls in
// from below, and the slot it sits in stretches to the new width on a spring.
// It turns by itself every `interval` seconds while on screen (the app's one
// allowed autoplay), and pauses while the app is inactive or the view is covered.
// Reduce Motion swaps the rolling for a slow crossfade between phrases every 3 s.
// Assistive tech reads one static `accessibilityText`.

struct WordRoll: View {
    let lead: String
    let words: [String]
    var interval: Double = 2.4
    var font: Font = .title3.weight(.bold)
    var leadColor: Color = .labelSecondary
    var wordColor: Color = .labelPrimary
    let accessibilityText: String

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    @State private var model = WordRollModel()
    @State private var visible = false
    /// Reduce Motion: the phrase shown, swapped with a crossfade.
    @State private var fadeIndex = 0

    private static let reducedInterval: Double = 3
    private static let reducedFade: Double = 0.8

    /// The rotation loop restarts whenever one of these changes, and runs only when all allow it.
    private struct LoopKey: Equatable {
        var reduceMotion: Bool
        var active: Bool
        var visible: Bool
    }

    var body: some View {
        VStack(spacing: 2) {
            Text(lead)
                .foregroundStyle(leadColor)
            if reduceMotion { fadeSlot } else { slot }
        }
        .font(font)
        .dynamicTypeSize(...DynamicTypeSize.accessibility2)
        .multilineTextAlignment(.center)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
        .onAppear {
            visible = true
            model.show(words.first ?? "", first: true)
        }
        .task(id: LoopKey(reduceMotion: reduceMotion, active: scenePhase == .active, visible: visible)) {
            guard visible, scenePhase == .active, words.count > 1 else {
                model.stop()
                return
            }
            if reduceMotion {
                model.stop()
                while !Task.isCancelled {
                    try? await Task.sleep(for: .seconds(Self.reducedInterval))
                    guard !Task.isCancelled else { break }
                    withAnimation(.easeInOut(duration: Self.reducedFade)) {
                        fadeIndex = (fadeIndex + 1) % words.count
                    }
                }
                return
            }
            var i = model.index(of: words)
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(interval))
                guard !Task.isCancelled else { break }
                i = (i + 1) % words.count
                model.show(words[i], first: false)
            }
        }
        .onDisappear {
            visible = false
            model.stop()
        }
    }

    /// Reduce Motion: one phrase at a time, crossfading in place.
    private var fadeSlot: some View {
        ZStack {
            if words.indices.contains(fadeIndex) {
                Text(words[fadeIndex])
                    .foregroundStyle(wordColor)
                    .fixedSize()
                    .id(fadeIndex)
                    .transition(.opacity)
            }
        }
    }

    private var slot: some View {
        // The reference phrase sizes the line height; it is never drawn.
        Text("Ag")
            .hidden()
            .frame(width: model.full > 0 ? model.width : nil)
            .overlay(alignment: .topLeading) {
                ZStack(alignment: .topLeading) {
                    ForEach(model.live) { word in
                        WordView(word: word, color: wordColor) { w in
                            model.measured(word.id, width: w)
                        }
                    }
                }
            }
            // Clip top and bottom only, like `clip-path: inset(0 -.5em)`.
            .mask { Rectangle().padding(.horizontal, -24) }
    }
}

private struct WordView: View {
    let word: WordRollModel.Word
    let color: Color
    let onWidth: (Double) -> Void

    var body: some View {
        HStack(spacing: 0) {
            ForEach(Array(word.chars.enumerated()), id: \.offset) { k, ch in
                Text(String(ch))
                    .foregroundStyle(color)
                    .modifier(RollLetter(y: k < word.ys.count ? word.ys[k] : 0))
            }
        }
        .fixedSize()
        .background {
            GeometryReader { g in
                Color.clear
                    .onAppear { onWidth(g.size.width) }
                    .onChange(of: g.size.width) { _, w in onWidth(w) }
            }
        }
    }
}

/// translateY(y × 105%) and opacity 1 - |y| × 0.9, as in roll.js.
private struct RollLetter: ViewModifier {
    let y: Double
    func body(content: Content) -> some View {
        content
            .visualEffect { c, proxy in
                c.offset(y: y * 1.05 * proxy.size.height)
            }
            .opacity(motionClamp(1 - abs(y) * 0.9, 0, 1))
    }
}

// MARK: - Engine

@Observable
final class WordRollModel {
    struct Word: Identifiable {
        let id: Int
        let text: String
        let chars: [Character]
        var ys: [Double]
        var out = false
    }

    private(set) var live: [Word] = []
    private(set) var width: Double = 0
    private(set) var full: Double = 0

    @ObservationIgnored private var springs: [Int: [MotionSpring]] = [:]
    @ObservationIgnored private var widths: [Int: Double] = [:]
    @ObservationIgnored private var w = MotionSpring(0, 320, 30)
    @ObservationIgnored private var nextID = 0
    @ObservationIgnored private var pendingTimers = 0
    @ObservationIgnored private let clock = MotionClock()

    init() {
        clock.frame = { [weak self] dt in self?.frame(dt) }
        clock.render = { [weak self] in self?.render() }
    }

    func index(of words: [String]) -> Int {
        guard let current = live.last(where: { !$0.out }) else { return 0 }
        return words.firstIndex(of: current.text) ?? 0
    }

    func show(_ text: String, first: Bool) {
        if first {
            // Rest state: just this phrase, no motion.
            if live.count == 1, live[0].text == text, !live[0].out { return }
            clock.cancelAllTimers(); pendingTimers = 0
            springs.removeAll(); widths.removeAll()
            let id = makeWord(text, inPlace: true)
            live = [Word(id: id, text: text, chars: Array(text), ys: Array(repeating: 0, count: text.count))]
            full = 0
            clock.stop()
            return
        }
        // Roll the current phrase out, letter by letter.
        for i in live.indices where !live[i].out {
            live[i].out = true
            let id = live[i].id
            for k in 0..<(springs[id]?.count ?? 0) {
                later(Double(k) * 0.022) { [weak self] in self?.springs[id]?[k].t = -1 }
            }
            later(1) { [weak self] in self?.remove(id) }
        }
        // Roll the next one in from below.
        let id = makeWord(text, inPlace: false)
        live.append(Word(id: id, text: text, chars: Array(text), ys: Array(repeating: 1, count: text.count)))
        for k in 0..<text.count {
            later(0.06 + Double(k) * 0.028) { [weak self] in self?.springs[id]?[k].t = 0 }
        }
        if let measured = widths[id] { w.t = measured }
        clock.start()
    }

    func measured(_ id: Int, width value: Double) {
        widths[id] = value
        guard id == live.last?.id else { return }
        if full == 0 {
            full = value
            w.snap(value)
            width = value
        } else {
            w.t = value
            clock.start()
        }
    }

    func stop() {
        clock.cancelAllTimers(); pendingTimers = 0
        if let last = live.last {
            live = [Word(id: last.id, text: last.text, chars: last.chars, ys: Array(repeating: 0, count: last.chars.count))]
            springs = [last.id: (springs[last.id] ?? []).map { var s = $0; s.snap(0); return s }]
            if let lw = widths[last.id] { w.snap(lw); width = lw }
        }
        clock.stop()
    }

    private func makeWord(_ text: String, inPlace: Bool) -> Int {
        nextID += 1
        // 1 = below the slot, 0 = in place, -1 = above.
        springs[nextID] = Array(repeating: MotionSpring(inPlace ? 0 : 1, 420, 26), count: text.count)
        return nextID
    }

    private func remove(_ id: Int) {
        live.removeAll { $0.id == id }
        springs[id] = nil
        widths[id] = nil
    }

    private func later(_ seconds: Double, _ fn: @escaping () -> Void) {
        pendingTimers += 1
        clock.after(seconds) { [weak self] in
            self?.pendingTimers -= 1
            fn()
        }
    }

    private func frame(_ dt: Double) {
        w.step(dt)
        // Step in place: no new arrays per frame.
        for slot in springs.values.indices {
            for k in springs.values[slot].indices { springs.values[slot][k].step(dt) }
        }
    }

    private func render() {
        let newWidth = max(0, w.x)
        if width != newWidth { width = newWidth }
        var settled = w.isSettled(within: MotionSpring.points)
        var changed = false
        for word in live {
            guard let s = springs[word.id] else { continue }
            if !changed {
                changed = s.count != word.ys.count || s.indices.contains { s[$0].x != word.ys[$0] }
            }
            settled = settled && s.allSatisfy(\.isSettled)
        }
        // Publish only when a letter moved, so a resting slot doesn't invalidate the view.
        if changed {
            var next = live
            for i in next.indices {
                guard let s = springs[next[i].id] else { continue }
                if next[i].ys.count != s.count { next[i].ys = Array(repeating: 0, count: s.count) }
                for k in s.indices { next[i].ys[k] = s[k].x }
            }
            live = next
        }
        if clock.isRunning, settled, pendingTimers == 0 {
            clock.stop()
        }
    }
}

// MARK: - Preview

#Preview("Word Roll") {
    WordRoll(
        lead: "Nourlo helps you",
        words: ["plan meals", "track calories", "shop on budget", "cook what you have"],
        accessibilityText: "Nourlo helps you plan meals, track calories, shop on budget and cook what you have."
    )
    .padding()
    .background(Color.surface)
}
