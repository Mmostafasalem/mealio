import SwiftUI

// MARK: - Star Rating
//
// Port of designbookmark.com/motion "Star Rating" (star-rating/stars.js).
// Each star has a fill spring (300, 24) and a pop spring (520, 13). Setting a
// rating lights the stars up to it one after another (50 ms stagger), each
// popping as it lights; stars turning off empty at once. The word under the
// stars rolls on its own spring (260, 22). The source's hover preview has no
// touch equivalent, so a tap sets the rating. No autoplay.
// Reduce Motion: no pop, the fill crossfades and the word crossfades in place.
//
// Accessibility: one adjustable element (swipe up / down), value "3 of 5, Good".

struct StarRating: View {
    @Binding var rating: Int
    var title: String = "How was it?"
    /// Word for 0…5; index 0 is the "not rated yet" prompt.
    var words: [String] = ["Tap a star", "Didn't like it", "Okay", "Good", "Great", "Loved it"]

    @State private var model = StarRatingModel()
    @ScaledMetric(relativeTo: .title2) private var star: CGFloat = 34
    @ScaledMetric(relativeTo: .subheadline) private var wordHeight: CGFloat = 22
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: Spacing.md) {
            Text(title)
                .font(.headline)
                .foregroundStyle(Color.labelPrimary)
            HStack(spacing: 6) {
                ForEach(0..<5, id: \.self) { i in starButton(i) }
            }
            word
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
        .accessibilityValue(rating == 0 ? "Not rated" : "\(rating) of 5, \(words[rating])")
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: rating = min(5, rating + 1)
            case .decrement: rating = max(0, rating - 1)
            @unknown default: break
            }
        }
        .sensoryFeedback(.selection, trigger: rating)
        .onAppear { model.light(rating, animated: false) }
        .onChange(of: rating) { _, n in model.light(n, animated: true) }
        .onDisappear { model.stop() }
    }

    private func starButton(_ i: Int) -> some View {
        Button { rating = i + 1 } label: {
            ZStack {
                Image(systemName: "star.fill")
                    .foregroundStyle(Color.progressTrack)
                Image(systemName: "star.fill")
                    .foregroundStyle(Color.progress)
                    .opacity(model.fill[i])
            }
            .font(.system(size: star * 0.82))
            .scaleEffect(model.pop[i])
            .frame(width: max(44, star + 6), height: max(44, star + 6))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder private var word: some View {
        let w = model.word
        if reduceMotion {
            ZStack {
                ForEach(words.indices, id: \.self) { i in
                    Text(words[i]).opacity(motionClamp(1 - abs(w - Double(i)), 0, 1))
                }
            }
            .modifier(WordStyle(height: wordHeight))
        } else {
            VStack(spacing: 0) {
                ForEach(words.indices, id: \.self) { i in
                    Text(words[i]).frame(height: wordHeight)
                }
            }
            .offset(y: -wordHeight * w)
            .frame(height: wordHeight, alignment: .top)
            .clipped()
            .modifier(WordStyle(height: wordHeight))
        }
    }

    private struct WordStyle: ViewModifier {
        let height: CGFloat
        func body(content: Content) -> some View {
            content
                .font(.subheadline.weight(.medium))
                .foregroundStyle(Color.labelSecondary)
                .lineLimit(1)
                .frame(maxWidth: .infinity)
                .frame(height: height)
        }
    }
}

// MARK: - Engine

@MainActor
@Observable
final class StarRatingModel {
    private(set) var fill: [Double] = Array(repeating: 0, count: 5)
    private(set) var pop: [Double] = Array(repeating: 1, count: 5)
    private(set) var word: Double = 0

    @ObservationIgnored private var f = Array(repeating: MotionSpring(0, 300, 24), count: 5)
    @ObservationIgnored private var p = Array(repeating: MotionSpring(1, 520, 13), count: 5)
    @ObservationIgnored private var w = MotionSpring(0, 260, 22)
    @ObservationIgnored private var lit = Array(repeating: false, count: 5)
    @ObservationIgnored private var timers: [Int] = []
    @ObservationIgnored private let clock = MotionClock()

    private static let stagger = 0.05

    init() {
        clock.frame = { [weak self] dt in self?.frame(dt) }
        clock.render = { [weak self] in self?.render() }
    }

    func light(_ n: Int, animated: Bool) {
        guard animated else {
            timers.forEach(clock.cancel); timers = []
            for i in 0..<5 {
                lit[i] = i < n
                f[i].snap(lit[i] ? 1 : 0); p[i].snap(1)
            }
            w.snap(Double(n))
            render()
            return
        }
        w.t = Double(n)
        var order = 0
        for i in 0..<5 {
            let on = i < n
            guard on != lit[i] else { continue }
            lit[i] = on
            if on {
                // Only the newly lit stars stagger, starting right away.
                let delay = Double(order) * Self.stagger
                order += 1
                timers.append(clock.after(delay) { [weak self] in self?.ignite(i) })
            } else {
                f[i].t = 0
            }
        }
        clock.start()
    }

    func stop() {
        timers.forEach(clock.cancel); timers = []
        for i in 0..<5 { f[i].snap(f[i].t); p[i].snap(1) }
        w.snap(w.t)
        render()
        clock.stop()
    }

    private func ignite(_ i: Int) {
        guard lit[i] else { return }
        f[i].t = 1
        // Purely decorative pop; Reduce Motion skips it.
        if !MotionSettings.reduceMotion { p[i].x = 0.7; p[i].v = 7 }
    }

    private func frame(_ dt: Double) {
        for i in 0..<5 { f[i].step(dt); p[i].step(dt) }
        w.step(dt)
    }

    private func render() {
        fill = f.map { motionClamp($0.x, 0, 1) }
        pop = p.map(\.x)
        word = w.x
        let pending = lit.indices.contains { lit[$0] && f[$0].t < 1 }
        if clock.isRunning, !pending, f.allSatisfy(\.isSettled), p.allSatisfy(\.isSettled), w.isSettled {
            for i in 0..<5 { f[i].snap(f[i].t); p[i].snap(1) }
            w.snap(w.t)
            fill = f.map(\.x); pop = p.map(\.x); word = w.x
            timers = []
            clock.stop()
        }
    }
}

// MARK: - Preview

#Preview("Star Rating") {
    @Previewable @State var rating = 0
    @Previewable @State var rated = 4
    VStack(spacing: Spacing.xl) {
        StarRating(rating: $rating)
        StarRating(rating: $rated)
    }
    .padding(Spacing.lg)
    .background(Color.surface, in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
    .padding(Spacing.lg)
    .background(Color.surfaceGrouped)
}
