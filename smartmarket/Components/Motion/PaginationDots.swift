import SwiftUI

// MARK: - Pagination Dots
//
// Port of designbookmark.com/motion "Pagination Dots" (pagination-dots/dots.js).
// The active dot is a pill 20 wide over 8 pt dots 22 apart. It has two edge
// springs: the edge facing the move is stiff (520, 34), the other soft
// (140, 18), so the pill stretches across the gap and gathers on the new dot.
// The pages slide on one spring (170, 22): `PaginationStrip`.
// Reduce Motion: both edges share one calm spring (no stretch) and the strip
// changes page without sliding.

struct PaginationDots: View {
    let count: Int
    let selection: Int
    /// Spoken name of page `i`, e.g. "Step 2 of 3".
    var pageLabel: (Int) -> String = { "Page \($0 + 1)" }
    let onSelect: (Int) -> Void

    @State private var engine = PaginationDotsEngine()

    static let dot: CGFloat = 8
    static let pitch: CGFloat = 22
    static let pill: CGFloat = 20

    var body: some View {
        let s = engine.snap
        HStack(spacing: 0) {
            ForEach(0..<count, id: \.self) { i in
                Button { onSelect(i) } label: {
                    Circle()
                        .fill(Color.labelTertiary.opacity(0.35))
                        .frame(width: Self.dot, height: Self.dot)
                        .frame(width: Self.pitch, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(pageLabel(i))
                .accessibilityAddTraits(i == selection ? .isSelected : [])
            }
        }
        .background(alignment: .leading) {
            Capsule()
                .fill(Color.brandPrimary)
                .frame(width: max(Self.dot, s.right - s.left), height: Self.dot)
                .offset(x: s.left)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
        .transaction { $0.animation = nil }
        .onAppear { engine.place(selection) }
        .onChange(of: selection) { _, i in engine.go(i) }
        .onDisappear { engine.stop() }
    }
}

/// Pages in a row, sliding on one spring. Only the current page is in the
/// accessibility tree.
struct PaginationStrip<Page: View>: View {
    let count: Int
    let selection: Int
    @ViewBuilder let page: (Int) -> Page

    @State private var engine = PaginationStripEngine()
    @State private var width: CGFloat = 0

    var body: some View {
        // Pages share one layout slot (as wide as offered, as tall as the tallest)
        // and each is offset by its distance from the current position.
        ZStack(alignment: .topLeading) {
            ForEach(0..<count, id: \.self) { i in
                let d = Double(i) - engine.position
                page(i)
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                    .offset(x: d * width)
                    // pages more than one away are off screen: skip drawing them
                    .opacity(abs(d) < 1 ? 1 : 0)
                    .accessibilityHidden(i != selection)
                    .allowsHitTesting(i == selection)
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width = $0 }
        .clipped()
        .transaction { $0.animation = nil }
        .onAppear { engine.place(selection) }
        .onChange(of: selection) { _, i in engine.go(i) }
        .onDisappear { engine.stop() }
    }
}

// MARK: - Engines

@MainActor
@Observable
final class PaginationDotsEngine {
    struct Snapshot: Equatable {
        var left: Double = 0
        var right: Double = 0
    }

    /// From dots.js.
    static let lead = MotionTokens.Preset(k: 520, c: 34)
    static let trail = MotionTokens.Preset(k: 140, c: 18)

    private(set) var snap = Snapshot()

    @ObservationIgnored private var cur = 0
    @ObservationIgnored private var A = MotionSpring(0, 400, 30)
    @ObservationIgnored private var B = MotionSpring(0, 400, 30)
    @ObservationIgnored private let clock = MotionClock()

    init() {
        clock.frame = { [weak self] dt in self?.frame(dt) }
        clock.render = { [weak self] in self?.render() }
    }

    private func edges(_ i: Int) -> (Double, Double) {
        let c = (Double(i) + 0.5) * Double(PaginationDots.pitch)
        let w = Double(PaginationDots.pill)
        return (c - w / 2, c + w / 2)
    }

    func place(_ i: Int) {
        cur = i
        let (a, b) = edges(i)
        A.snap(a); B.snap(b)
        render()
    }

    func go(_ i: Int) {
        guard i != cur else { return }
        let forward = i > cur
        cur = i
        let (a, b) = edges(i)
        A.t = a; B.t = b
        if MotionSettings.reduceMotion {
            A.tune(MotionTokens.fade); B.tune(MotionTokens.fade)
        } else if forward {
            B.tune(Self.lead); A.tune(Self.trail)
        } else {
            A.tune(Self.lead); B.tune(Self.trail)
        }
        clock.start()
    }

    func stop() {
        clock.stop()
        A.snap(A.t); B.snap(B.t)
        render()
    }

    private func frame(_ dt: Double) { A.step(dt); B.step(dt) }

    private func render() {
        let s = Snapshot(left: A.x, right: max(A.x, B.x))
        if s != snap { snap = s }
        if clock.isRunning, A.isSettled(within: MotionSpring.points), B.isSettled(within: MotionSpring.points) {
            clock.stop()
        }
    }
}

@MainActor
@Observable
final class PaginationStripEngine {
    /// From dots.js: the strip slides on one spring.
    static let slide = MotionTokens.Preset(k: 170, c: 22)

    /// Current page position (0 = first page; fractional while sliding).
    private(set) var position: Double = 0

    @ObservationIgnored private var P = MotionSpring(0, PaginationStripEngine.slide)
    @ObservationIgnored private let clock = MotionClock()

    init() {
        clock.frame = { [weak self] dt in self?.P.step(dt) }
        clock.render = { [weak self] in self?.render() }
    }

    func place(_ i: Int) {
        P.snap(Double(i))
        position = P.x
    }

    func go(_ i: Int) {
        P.t = Double(i)
        if MotionSettings.reduceMotion {
            // change page, don't slide
            P.snap(P.t)
            position = P.x
            clock.stop()
            return
        }
        clock.start()
    }

    func stop() {
        clock.stop()
        P.snap(P.t)
        position = P.x
    }

    private func render() {
        if position != P.x { position = P.x }
        // a thousandth of a page is under a point on any phone
        if clock.isRunning, P.isSettled(within: 0.001) { stop() }
    }
}

// MARK: - Preview

#Preview("Pagination Dots") {
    @Previewable @State var page = 0
    let titles = ["Start with one meal", "Build your grocery list", "Make room for a plan"]
    VStack(alignment: .leading, spacing: 16) {
        PaginationDots(count: titles.count, selection: page,
                       pageLabel: { "Step \($0 + 1) of \(titles.count)" }) { page = $0 }
        PaginationStrip(count: titles.count, selection: page) { i in
            Text(titles[i]).font(.title2.weight(.semibold))
        }
        Button("Next") { page = (page + 1) % titles.count }
    }
    .padding(24)
    .background(Color.surfaceElevated)
}
