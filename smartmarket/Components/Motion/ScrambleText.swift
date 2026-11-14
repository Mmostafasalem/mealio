import SwiftUI

// MARK: - Scramble Text
//
// Port of designbookmark.com/motion "Scramble Text" (scramble-text/scramble.js).
// Each letter flickers through random glyphs (a new one every 55 ms) and settles
// on the right one, left to right with a little randomness. Unsettled letters
// are dim, settled ones full ink. The source spreads a phrase over ~1 s
// (0.18 s + 35 ms per letter + up to 0.28 s); here the per-letter delay is
// scaled to the title's length so a whole title lands in about half a second.
// No autoplay and no hover: it decodes only when the text changes from one it
// showed before (see `ScrambleMemory`). Proportional system font, so the final
// text reserves the layout and the scrambled copy is drawn over it.
// Reduce Motion: a plain cross-fade to the new text.
//
// Accessibility: the label is always the final text.

/// Remembers the last text shown under each key, so a title only decodes when a
/// new plan really changed it (not on first load, a reload or a re-appear).
@MainActor
final class ScrambleMemory {
    private var last: [String: String] = [:]

    /// Returns whether `text` differs from the one shown before under `key`, and records it.
    func changed(_ key: String, to text: String) -> Bool {
        defer { last[key] = text }
        guard let old = last[key] else { return false }
        return old != text
    }
}

struct ScrambleText: View {
    let text: String
    /// Stable slot identity (e.g. "Lunch#0"); with `memory`, decides whether to decode on appear.
    var key: String? = nil
    var memory: ScrambleMemory? = nil
    var font: Font = .subheadline.weight(.medium)
    var color: Color = .labelPrimary
    var dimColor: Color = .labelTertiary

    @State private var model = ScrambleTextModel()
    @State private var fade: Double = 1
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Text(text)
            .font(font)
            .foregroundStyle(color)
            .opacity(model.isRunning ? 0 : fade)
            .overlay(alignment: .topLeading) {
                if model.isRunning {
                    Text(model.attributed(color: color, dim: dimColor))
                        .font(font)
                        .accessibilityHidden(true)
                }
            }
            .accessibilityLabel(text)
            .onAppear {
                if let key, let memory, memory.changed(key, to: text) { play() }
            }
            .onChange(of: text) { _, new in
                if let key, let memory { _ = memory.changed(key, to: new) }
                play()
            }
            .onDisappear { model.stop() }
    }

    private func play() {
        if reduceMotion {
            model.stop()
            fade = 0
            withAnimation(.reducedFade) { fade = 1 }
        } else {
            fade = 1
            model.decode(text)
        }
    }
}

// MARK: - Engine

@MainActor
@Observable
final class ScrambleTextModel {
    private struct Cell {
        let to: Character
        let at: Double
        var shown: Character
        var tick: Double = 0
        var done = false
    }

    private(set) var isRunning = false
    /// Bumped every frame something changes, so SwiftUI redraws.
    private(set) var revision = 0

    @ObservationIgnored private var cells: [Cell] = []
    @ObservationIgnored private var clock = 0.0
    @ObservationIgnored private let motion = MotionClock()

    private static let glyphs = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789#%&*+=")
    private static let flicker = 0.055
    /// Whole title in about this long, whatever its length.
    private static let spread = 0.3
    private static let lead = 0.08
    private static let jitter = 0.12

    init() {
        motion.frame = { [weak self] dt in self?.clock += dt }
        motion.render = { [weak self] in self?.render() }
    }

    func decode(_ text: String) {
        let chars = Array(text)
        let n = max(chars.count - 1, 1)
        clock = 0
        cells = chars.enumerated().map { i, ch in
            Cell(to: ch,
                 at: Self.lead + Double(i) / Double(n) * Self.spread + Double.random(in: 0..<Self.jitter),
                 shown: ch.isWhitespace ? ch : Self.glyph(),
                 done: ch.isWhitespace)
        }
        isRunning = !cells.isEmpty
        revision += 1
        if isRunning { motion.start() }
    }

    func stop() {
        cells = []
        isRunning = false
        motion.stop()
    }

    func attributed(color: Color, dim: Color) -> AttributedString {
        _ = revision
        var out = AttributedString()
        for c in cells {
            var piece = AttributedString(String(c.done ? c.to : c.shown))
            piece.foregroundColor = c.done ? color : dim
            out += piece
        }
        return out
    }

    private static func glyph() -> Character { glyphs.randomElement() ?? "#" }

    private func render() {
        var left = 0
        var changed = false
        for i in cells.indices where !cells[i].done {
            if clock >= cells[i].at {
                cells[i].done = true
                changed = true
            } else {
                left += 1
                if clock >= cells[i].tick {
                    cells[i].shown = Self.glyph()
                    cells[i].tick = clock + Self.flicker
                    changed = true
                }
            }
        }
        if changed { revision += 1 }
        if left == 0 { stop() }
    }
}

// MARK: - Preview

#Preview("Scramble Text") {
    @Previewable @State var index = 0
    @Previewable @State var memory = ScrambleMemory()
    let titles = ["Oatmeal with berries and kefir", "Buckwheat with chicken and cucumber salad", "Cold beet soup with potatoes"]
    VStack(alignment: .leading, spacing: Spacing.lg) {
        ScrambleText(text: titles[index % titles.count], key: "Lunch#0", memory: memory)
        Button("New plan") { index += 1 }
            .buttonStyle(.borderedProminent)
            .tint(Color.dullPink)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .padding(Spacing.lg)
    .background(Color.surface, in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
    .padding(Spacing.lg)
    .background(Color.surfaceGrouped)
}
