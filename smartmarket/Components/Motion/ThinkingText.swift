import SwiftUI

// MARK: - Thinking Text
//
// Port of Kokonut UI "AI Text Loading" (ai-text-loading.tsx, MIT), as shown at
// designbookmark.com/motion "Thinking text". Short status phrases take turns:
// each new phrase's letters rise in one after another (18 ms apart, 0.28 s,
// from 8 pt below, blurred), the old phrase lifts 6 pt and fades in 0.15 s,
// and a soft brightness wave runs through the letters (each dips to 30 %,
// 1.6 s per cycle, 70 ms between neighbours). Reduce Motion: phrases swap with
// a fade and the letters hold still.

struct ThinkingText: View {
    var phrases: [String] = ["Thinking…", "Working it out…", "Almost there…"]
    /// Seconds each phrase stays up.
    var interval: Double = 1.5
    var font: Font = .subheadline.weight(.semibold)
    var color: Color = .labelPrimary
    /// Stable status for VoiceOver; the cycling words are hidden from it.
    var label: String = "Working on it"

    @State private var index = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    static let easeOut = Animation.timingCurve(0.23, 1, 0.32, 1, duration: 0.28)

    var body: some View {
        let phrase = phrases.isEmpty ? "" : phrases[index % phrases.count]
        ZStack(alignment: .leading) {
            ThinkingPhrase(text: phrase, font: font, color: color, reduceMotion: reduceMotion)
                .id(index)
                .transition(.asymmetric(
                    insertion: .identity,
                    removal: reduceMotion ? .opacity : .opacity.combined(with: .offset(y: -6))))
        }
        .animation(.timingCurve(0.23, 1, 0.32, 1, duration: 0.15), value: index)
        .task(id: phrases.count) {
            guard phrases.count > 1 else { return }
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(interval))
                guard !Task.isCancelled else { return }
                index = (index + 1) % phrases.count
            }
        }
        .accessibilityElement()
        .accessibilityLabel(label)
        .accessibilityAddTraits(.updatesFrequently)
    }
}

private struct ThinkingPhrase: View {
    let text: String
    let font: Font
    let color: Color
    let reduceMotion: Bool

    @State private var shown = false

    var body: some View {
        let letters = Array(text)
        TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: reduceMotion)) { timeline in
            let t = timeline.date.timeIntervalSinceReferenceDate
            HStack(spacing: 0) {
                ForEach(letters.indices, id: \.self) { i in
                    Text(String(letters[i]))
                        .font(font)
                        .foregroundStyle(color)
                        // The wave: 1 → 0.3 → 1 over 1.6 s, each letter 70 ms after its neighbour.
                        .opacity(reduceMotion ? 1 : 1 - 0.7 * (0.5 - 0.5 * cos(2 * .pi * (t - Double(i) * 0.07) / 1.6)))
                        // The entrance: rise, sharpen and fade in, staggered.
                        .opacity(shown ? 1 : 0)
                        .offset(y: shown || reduceMotion ? 0 : 8)
                        .blur(radius: shown || reduceMotion ? 0 : 4)
                        .animation(ThinkingText.easeOut.delay(Double(i) * 0.018), value: shown)
                }
            }
        }
        .fixedSize()
        .onAppear { shown = true }
    }
}

#Preview {
    VStack(alignment: .leading, spacing: 24) {
        ThinkingText()
        ThinkingText(phrases: ["Checking your stock…", "Reading your goals…", "Writing a reply…"],
                     font: .title3.weight(.bold))
    }
    .padding(40)
}
