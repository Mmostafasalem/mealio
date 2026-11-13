import SwiftUI
import UIKit

// MARK: - Goo Pull to Refresh
//
// Port of designbookmark.com/motion "Pull to Refresh" (pull-refresh/pull.js).
// Pulling the list down past the top opens a gap; a drop stretches out of a small
// handle in that gap (one goo layer: blur + alpha threshold, so they stay fused).
// Past 88 pt the drop pops (haptic) and, once refreshing, becomes a spinner while
// the list holds 64 pt down. When the work is done the list springs home (260/18).
//
// The scroll view's own rubber band is kept (it is the same 0.55 resistance as the
// original's first stretch), so scrolling still feels native. The pull distance is
// read from the scroll view: onScrollGeometryChange on iOS 18, and the content's
// top edge measured against the header's bottom edge on iOS 17.
// iOS 18+: the refresh starts when the finger lets go past the threshold (pull back
// above it to cancel), like the original. iOS 17 has no release signal, so it starts
// on crossing the threshold, like UIRefreshControl.
//
// Reduce Motion: springs are critically damped and the drop doesn't stretch or move;
// a dot fades in where the spinner will be, then the spinner fades over it.
// VoiceOver: a "Refresh" action on the scroll view, with spoken progress.

struct GooPullRefresh<Header: View, Content: View>: View {
    var action: () async -> Void
    @ViewBuilder var header: () -> Header
    @ViewBuilder var content: () -> Content

    @State private var engine = GooPullEngine()
    /// iOS 17: where the content's top edge sits at rest (bottom of the header inset).
    @State private var restTop: CGFloat?

    init(action: @escaping () async -> Void,
         @ViewBuilder header: @escaping () -> Header,
         @ViewBuilder content: @escaping () -> Content) {
        self.action = action
        self.header = header
        self.content = content
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 0) {
                // Top edge of the content, above the hold spacer, so the spacer never feeds back.
                Color.clear
                    .frame(height: 0)
                    .onGeometryChange(for: CGFloat.self) { $0.frame(in: .global).minY } action: { y in
                        if #available(iOS 18.0, *) { return }
                        guard let restTop else { return }
                        engine.update(overscroll: y - restTop)
                    }
                content()
                    .modifier(GooPullHoldOffset(engine: engine))
            }
        }
        .modifier(GooPullScrollReader(engine: engine))
        .safeAreaInset(edge: .top, spacing: 0) {
            VStack(spacing: 0) { header() }
                .frame(maxWidth: .infinity)
                .onGeometryChange(for: CGFloat.self) { $0.frame(in: .global).maxY } action: { restTop = $0 }
                .overlay(alignment: .bottom) {
                    GooPullIndicator(engine: engine)
                        .offset(y: GooPullEngine.indicatorHeight)
                }
        }
        .sensoryFeedback(.impact(weight: .medium), trigger: engine.armTick)
        .onChange(of: engine.refreshTick) { _, _ in Task { await run() } }
        .accessibilityAction(named: "Refresh") { engine.beginRefresh() }
    }

    private func run() async {
        AccessibilityNotification.Announcement("Refreshing").post()
        let start = ContinuousClock.now
        await action()
        // Hold at least a beat, so the spinner reads as a spinner and not a flicker.
        let elapsed = ContinuousClock.now - start
        if elapsed < GooPullEngine.minimumHold {
            try? await Task.sleep(for: GooPullEngine.minimumHold - elapsed)
        }
        engine.finishRefresh()
        AccessibilityNotification.Announcement("Updated just now").post()
    }
}

extension GooPullRefresh where Header == EmptyView {
    init(action: @escaping () async -> Void, @ViewBuilder content: @escaping () -> Content) {
        self.init(action: action, header: { EmptyView() }, content: content)
    }
}

// MARK: - Pieces

/// iOS 18: exact overscroll and the finger lifting, straight from the scroll view.
private struct GooPullScrollReader: ViewModifier {
    let engine: GooPullEngine

    func body(content: Content) -> some View {
        if #available(iOS 18.0, *) {
            content
                .onScrollGeometryChange(for: CGFloat.self) { g in
                    -(g.contentOffset.y + g.contentInsets.top)
                } action: { _, y in
                    engine.update(overscroll: y)
                }
                .onScrollPhaseChange { old, new in
                    let wasHeld = old == .interacting || old == .tracking
                    let held = new == .interacting || new == .tracking
                    engine.setReleaseAware()
                    if wasHeld && !held { engine.released() }
                }
        } else {
            content
        }
    }
}

/// Holds the list down while refreshing, then lets the return spring overshoot upward.
/// Reads the engine itself, so the content isn't rebuilt every frame.
private struct GooPullHoldOffset: ViewModifier {
    let engine: GooPullEngine

    func body(content: Content) -> some View {
        let o = engine.snap.listOffset
        content
            .padding(.top, max(0, o))
            .offset(y: min(0, o))
    }
}

/// The handle, the drop and the spinner, in the gap that opens above the list.
private struct GooPullIndicator: View {
    let engine: GooPullEngine

    var body: some View {
        let s = engine.snap
        let E = GooPullEngine.self
        ZStack(alignment: .top) {
            if s.reduced {
                // Reduce Motion: no stretch, no travel; a dot fades in where the spinner goes.
                Circle()
                    .fill(Color.labelPrimary)
                    .frame(width: E.dropSize, height: E.dropSize)
                    .offset(y: E.hold / 2 - E.dropSize / 2)
                    .opacity(s.pullProgress * (1 - s.spin))
            } else {
                Canvas { ctx, size in draw(s, in: &ctx, size: size) }
                    .opacity(1 - s.spin)
            }
            Circle()
                .fill(Color.labelPrimary)
                .frame(width: E.dropSize, height: E.dropSize)
                .overlay {
                    ProgressView()
                        .tint(Color.surface)
                        .controlSize(.small)
                }
                .scaleEffect(s.reduced ? 1 : 0.6 + 0.4 * s.spin)
                .offset(y: (s.reduced ? E.hold / 2 : s.dropY) - E.dropSize / 2)
                .opacity(s.spin)
        }
        .frame(maxWidth: .infinity)
        .frame(height: E.indicatorHeight, alignment: .top)
        .opacity(s.gapOpacity)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private func draw(_ s: GooPullEngine.Snapshot, in ctx: inout GraphicsContext, size: CGSize) {
        let E = GooPullEngine.self
        let cx = size.width / 2
        ctx.drawLayer { goo in
            goo.addFilter(.alphaThreshold(min: 0.5, color: .labelPrimary))
            goo.addFilter(.blur(radius: E.blur))
            goo.drawLayer { b in
                // handle: 44×6 at the top of the gap (drawn a little fuller, the threshold trims it)
                b.fill(Path(roundedRect: CGRect(x: cx - 24, y: 0, width: 48, height: 10), cornerRadius: 5),
                       with: .color(.black))
                // drop: squashes sideways and stretches down with its speed
                var d = b
                d.translateBy(x: cx, y: s.dropY)
                d.scaleBy(x: s.dropScale / s.stretch, y: s.dropScale * s.stretch)
                let r = E.dropSize / 2 + 2
                d.fill(Path(ellipseIn: CGRect(x: -r, y: -r, width: 2 * r, height: 2 * r)), with: .color(.black))
            }
        }
    }
}

// MARK: - Engine

@MainActor
@Observable
final class GooPullEngine {
    struct Snapshot: Equatable {
        /// Hold spacer above the list; negative while the return spring overshoots.
        var listOffset: Double = 0
        var dropY: Double = GooPullEngine.restY
        var dropScale: Double = GooPullEngine.restScale
        var stretch: Double = 1
        var spin: Double = 0
        /// 0…1 of the way to the threshold.
        var pullProgress: Double = 0
        /// The whole indicator fades with the gap, so nothing sits on the content at rest.
        var gapOpacity: Double = 0
        var reduced = false
    }

    // tokens.css: --pull-threshold 88, --pull-return 260 18
    static let threshold: Double = 88
    static let hold: Double = 64
    static let restY: Double = 5
    static let restScale: Double = 0.25
    static let dropSize: Double = 32
    static let blur: Double = 8
    static let indicatorHeight: Double = 120
    static let minimumHold: Duration = .milliseconds(600)

    private(set) var snap = Snapshot()
    /// Bumped when the pull crosses the threshold (haptic).
    private(set) var armTick = 0
    /// Bumped when a refresh should start; the view runs the action.
    private(set) var refreshTick = 0

    private enum Mode { case idle, pulling, loading, settling }
    @ObservationIgnored private var mode: Mode = .idle
    @ObservationIgnored private var armed = false
    @ObservationIgnored private var pull: Double = 0
    @ObservationIgnored private var releaseAware = false

    @ObservationIgnored private var P = MotionSpring(0, 260, 18)       // hold spacer (--pull-return)
    @ObservationIgnored private var D = MotionSpring(GooPullEngine.restY, 380, 24)       // drop centre y
    @ObservationIgnored private var DS = MotionSpring(GooPullEngine.restScale, 420, 26)  // drop scale
    @ObservationIgnored private var SP = MotionSpring(0, 400, 26)      // spinner
    @ObservationIgnored private let clock = MotionClock()

    init() {
        clock.frame = { [weak self] dt in self?.frame(dt) }
        clock.render = { [weak self] in self?.render() }
    }

    /// iOS 18 reports the finger lifting: wait for release instead of firing on crossing.
    func setReleaseAware() { releaseAware = true }

    /// How far the content's top edge is pulled below its rest position, in points.
    func update(overscroll y: Double) {
        let next = max(0, y)
        guard abs(next - pull) > 0.01 || (next == 0 && pull != 0) else { return }
        pull = next
        switch mode {
        case .idle:
            if pull > 0.5 { mode = .pulling; armed = false }
        case .pulling:
            if pull >= Self.threshold, !armed {
                armed = true
                armTick += 1
                if !MotionSettings.reduceMotion { DS.v += 4 }
                if !releaseAware { _ = beginRefresh() }
            } else if pull < Self.threshold, armed, releaseAware {
                armed = false
            } else if pull <= 0.5, !armed {
                mode = .idle
            }
        case .loading, .settling:
            break
        }
        clock.maxFramesPerSecond = pull > 0.5 ? 120 : 60
        clock.start()
    }

    /// The finger let go (iOS 18).
    func released() {
        if mode == .pulling, armed { _ = beginRefresh() }
    }

    /// Starts a refresh unless one is running. Also the VoiceOver path.
    @discardableResult
    func beginRefresh() -> Bool {
        guard mode != .loading else { return false }
        mode = .loading
        armed = false
        P.tune(MotionTokens.settle)
        refreshTick += 1
        clock.start()
        return true
    }

    func finishRefresh() {
        guard mode == .loading else { return }
        mode = .settling
        P.tune(260, 18)
        P.t = 0
        clock.maxFramesPerSecond = 60
        clock.start()
    }

    // MARK: Simulation

    private func frame(_ dt: Double) {
        let E = Self.self
        let p = motionClamp(pull / E.threshold, 0, 1)
        switch mode {
        case .loading:
            // Fill in behind the scroll view's own bounce so the list comes to rest 64 down.
            P.t = motionClamp(E.hold - pull, 0, E.hold)
            D.t = E.hold / 2; DS.t = 1; SP.t = 1
        case .pulling:
            P.t = 0
            D.t = max(E.restY, pull * 0.5); DS.t = E.restScale + (1 - E.restScale) * p; SP.t = 0
        case .idle, .settling:
            P.t = 0
            D.t = E.restY; DS.t = E.restScale; SP.t = 0
        }
        P.step(dt); D.step(dt); DS.step(dt); SP.step(dt)
    }

    private func render() {
        let E = Self.self
        let reduce = MotionSettings.reduceMotion
        var s = Snapshot()
        s.reduced = reduce
        s.listOffset = P.x
        s.dropY = D.x
        s.dropScale = DS.x
        s.stretch = reduce ? 1 : 1 + motionClamp(abs(D.v) / 1600, 0, 0.35)
        s.spin = motionClamp(SP.x, 0, 1)
        s.pullProgress = motionClamp(pull / E.threshold, 0, 1)
        let gap = pull + max(0, P.x)
        s.gapOpacity = motionClamp((gap - 4) / 20, 0, 1)
        if s != snap { snap = s }

        let pts = MotionSpring.points
        let settled = P.isSettled(within: pts) && D.isSettled(within: pts) && DS.isSettled && SP.isSettled
        if settled {
            if mode == .settling { mode = pull > 0.5 ? .pulling : .idle }
            if clock.isRunning { clock.stop() }
        }
    }
}

// MARK: - Preview

#Preview("Goo Pull to Refresh") {
    @Previewable @State var updated = Date()
    GooPullRefresh(action: {
        try? await Task.sleep(for: .seconds(1.2))
        updated = Date()
    }) {
        VStack(alignment: .leading, spacing: Spacing.md) {
            Text("Today").font(.largeTitle.weight(.bold))
            Text("Updated \(updated.formatted(date: .omitted, time: .standard))")
                .font(.footnote).foregroundStyle(Color.labelSecondary)
            ForEach(["Breakfast", "Lunch", "Dinner", "Snack"], id: \.self) { slot in
                Text(slot)
                    .font(.headline)
                    .frame(maxWidth: .infinity, minHeight: 72, alignment: .leading)
                    .padding(.horizontal, Spacing.lg)
                    .background(Color.surface, in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
            }
        }
        .padding(Spacing.lg)
    }
    .background(Color.surfaceGrouped)
}
