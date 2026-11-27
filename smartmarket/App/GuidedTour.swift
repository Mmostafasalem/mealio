import SwiftUI
import UIKit

// MARK: - Guided tour
//
// TestFlight B6 ("Guided tour"): once after onboarding, a spotlight walks through
// the main parts of the app: today's calories, Meals, the quick-actions button,
// Shop and Train (only those the person chose in Features). Everything else is
// dimmed; a card under or over the lit part says what it is. It can be replayed
// from Profile › Help (`ReplayTourRow`).

/// A part of the screen the tour can light up.
enum TourTarget: String, CaseIterable, Sendable {
    case calories, meals, quickActions, shop, train

    /// The tab's VoiceOver name, for the targets that are tabs.
    var tabName: String? {
        switch self {
        case .meals: return AppTab.meals.name
        case .shop: return AppTab.shop.name
        case .train: return AppTab.train.name
        case .calories, .quickActions: return nil
        }
    }

    var tab: AppTab? {
        switch self {
        case .meals: return .meals
        case .shop: return .shop
        case .train: return .train
        case .calories, .quickActions: return nil
        }
    }
}

struct GuidedTourStep: Equatable, Identifiable {
    let target: TourTarget
    let title: String
    let detail: String
    let symbol: String
    var id: TourTarget { target }

    private static let all: [GuidedTourStep] = [
        GuidedTourStep(target: .calories, title: "Your calories today",
                       detail: "The ring fills as you log food. Tap Insights for your calories over the last 7 and 30 days.",
                       symbol: "flame.fill"),
        GuidedTourStep(target: .meals, title: "Meals",
                       detail: "Your plan for each day, built from your cart and My Stock. Open a meal to cook it or log it.",
                       symbol: "fork.knife"),
        GuidedTourStep(target: .quickActions, title: "Quick actions",
                       detail: "Tap Nourlo any time to ask a question, speak a command, snap a meal, or open your checklist and My Stock.",
                       symbol: "square.grid.2x2.fill"),
        GuidedTourStep(target: .shop, title: "Shop",
                       detail: "Fill your cart for the week within your budget. Prices are estimates, not live store prices.",
                       symbol: "basket.fill"),
        GuidedTourStep(target: .train, title: "Train",
                       detail: "Build a workout, follow along, and see your progress.",
                       symbol: "figure.run"),
    ]

    /// The steps for the features the person chose. Quick actions is always there.
    static func steps(for features: Set<AppFeature>) -> [GuidedTourStep] {
        all.filter { step in
            switch step.target {
            case .calories: return features.contains(.tracking)
            case .quickActions: return true
            case .meals, .shop, .train:
                return step.target.tab.map { FeatureLayout.tabs(for: features).contains($0) } ?? false
            }
        }
    }
}

@MainActor
@Observable
final class GuidedTour {
    static let shared = GuidedTour()
    static let seenKey = "guidedTourSeen_v1"
    /// UI tests (which hide the tour) pass this to see it.
    static let showArgument = "-NourloShowTour"

    private(set) var steps: [GuidedTourStep] = []
    private(set) var index: Int?
    /// Where on screen (global coordinates) the Home targets are, reported by `tourTarget`.
    private(set) var frames: [TourTarget: CGRect] = [:]

    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private var pendingStart: Task<Void, Never>?

    init(defaults: UserDefaults = .standard) { self.defaults = defaults }

    var isRunning: Bool { index != nil }
    var current: GuidedTourStep? { index.flatMap { steps.indices.contains($0) ? steps[$0] : nil } }
    var hasSeen: Bool { defaults.bool(forKey: Self.seenKey) }

    /// Once after onboarding: the first time the main screen appears.
    func startIfNeeded(features: Set<AppFeature>) {
        guard !hasSeen, !isRunning else { return }
        let args = ProcessInfo.processInfo.arguments
        // UI tests drive the app themselves; the tour would cover what they tap.
        if args.contains("-NourloUITesting"), !args.contains(Self.showArgument) { return }
        start(features: features, after: 0.9)
    }

    /// From Profile › Help: back to Home, then the tour again.
    func replay() {
        NotificationCenter.default.post(name: .openHome, object: nil)
        start(features: AppState.shared.enabledFeatures, after: 0.7)
    }

    func start(features: Set<AppFeature>, after delay: Double = 0) {
        pendingStart?.cancel()
        pendingStart = Task { @MainActor [weak self] in
            if delay > 0 { try? await Task.sleep(for: .seconds(delay)) }
            guard let self, !Task.isCancelled else { return }
            self.steps = GuidedTourStep.steps(for: features)
            self.index = self.steps.isEmpty ? nil : 0
        }
    }

    func next() {
        guard let index else { return }
        if index + 1 < steps.count { self.index = index + 1 } else { finish() }
    }

    func back() {
        guard let index, index > 0 else { return }
        self.index = index - 1
    }

    func finish() {
        pendingStart?.cancel()
        index = nil
        defaults.set(true, forKey: Self.seenKey)
    }

    func report(_ target: TourTarget, frame: CGRect) {
        guard frames[target] != frame else { return }
        frames[target] = frame
    }

    /// A Home target's reported frame, or a tab's / the bowl button's frame read from the screen.
    func frame(for target: TourTarget) -> CGRect? {
        if let name = target.tabName { return TabBarLocator.frame(ofTabNamed: name) }
        return frames[target]
    }
}

extension View {
    /// Marks this view as the part of the screen the guided tour lights up for `target`.
    func tourTarget(_ target: TourTarget) -> some View {
        onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { frame in
            GuidedTour.shared.report(target, frame: frame)
        }
    }
}

/// Finds a tab's button in the system tab bar (SwiftUI doesn't say where it is).
@MainActor
enum TabBarLocator {
    static func frame(ofTabNamed name: String) -> CGRect? {
        guard let window = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .flatMap(\.windows)
            .first(where: \.isKeyWindow),
              let bar = find(UITabBar.self, in: window), !bar.isHidden else { return nil }
        if let element = element(named: name, in: bar) {
            let frame = element.accessibilityFrame
            if frame.width > 1, frame.height > 1 { return frame }
        }
        // Fallback: the tabs share the bar evenly.
        guard let items = bar.items, let i = items.firstIndex(where: { $0.title == name || $0.accessibilityLabel == name }) else { return nil }
        let barFrame = bar.convert(bar.bounds, to: nil)
        let width = barFrame.width / CGFloat(max(items.count, 1))
        return CGRect(x: barFrame.minX + width * CGFloat(i), y: barFrame.minY, width: width, height: min(barFrame.height, 60))
    }

    private static func find<T: UIView>(_ type: T.Type, in view: UIView) -> T? {
        if let match = view as? T { return match }
        for sub in view.subviews { if let match = find(type, in: sub) { return match } }
        return nil
    }

    private static func element(named name: String, in view: UIView) -> NSObject? {
        if view.isAccessibilityElement, view.accessibilityLabel == name { return view }
        for case let element as NSObject in view.accessibilityElements ?? []
        where element.isAccessibilityElement && element.accessibilityLabel == name { return element }
        for sub in view.subviews { if let hit = element(named: name, in: sub) { return hit } }
        return nil
    }
}

// MARK: - Overlay

/// The dimmed screen with the lit target and the step's card. Lives above every tab.
struct GuidedTourOverlay: View {
    @State private var tour = GuidedTour.shared
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AccessibilityFocusState private var titleFocused: Bool
    /// Read again shortly after a step changes, once a tab switch or scroll has settled.
    @State private var refresh = 0

    var body: some View {
        if let step = tour.current, let index = tour.index {
            GeometryReader { geometry in
                let origin = geometry.frame(in: .global).origin
                let hole = spotlight(for: step, origin: origin, size: geometry.size)
                ZStack {
                    SpotlightShape(hole: hole, radius: cornerRadius(step, hole))
                        .fill(Color.black.opacity(0.62), style: FillStyle(eoFill: true))
                        .contentShape(Rectangle())
                        .onTapGesture {}
                        .accessibilityHidden(true)
                    RoundedRectangle(cornerRadius: cornerRadius(step, hole), style: .continuous)
                        .strokeBorder(Color.dullPink, lineWidth: 3)
                        .frame(width: hole.width, height: hole.height)
                        .position(x: hole.midX, y: hole.midY)
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                    callout(step, index: index)
                        .padding(.horizontal, Spacing.lg)
                        .frame(maxWidth: 440)
                        .frame(maxWidth: .infinity, maxHeight: .infinity,
                               alignment: calloutBelow(hole, size: geometry.size) ? .top : .bottom)
                        .padding(.top, calloutBelow(hole, size: geometry.size) ? min(hole.maxY + 16, geometry.size.height - 260) : 0)
                        .padding(.bottom, calloutBelow(hole, size: geometry.size) ? 0 : max(geometry.size.height - hole.minY + 16, 40))
                }
                .animation(reduceMotion ? nil : .spring(response: 0.45, dampingFraction: 0.85), value: index)
                .animation(reduceMotion ? nil : .spring(response: 0.45, dampingFraction: 0.85), value: refresh)
            }
            .ignoresSafeArea()
            .transition(.opacity)
            .accessibilityAddTraits(.isModal)
            .task(id: index) {
                titleFocused = true
                AccessibilityNotification.Announcement("\(step.title). \(step.detail)").post()
                // A tab's button can move as the bar settles; look again.
                for _ in 0..<3 {
                    try? await Task.sleep(for: .milliseconds(250))
                    refresh &+= 1
                }
            }
        }
    }

    /// The lit rectangle in the overlay's coordinates, a little larger than the target.
    private func spotlight(for step: GuidedTourStep, origin: CGPoint, size: CGSize) -> CGRect {
        _ = refresh
        guard var frame = tour.frame(for: step.target) else {
            // Nothing to light (the target isn't on screen): a thin band at the centre.
            return CGRect(x: size.width / 2, y: size.height / 2, width: 0, height: 0)
        }
        frame = frame.offsetBy(dx: -origin.x, dy: -origin.y)
        let pad: CGFloat = step.target == .calories ? 6 : 8
        frame = frame.insetBy(dx: -pad, dy: -pad)
        // The calorie card is taller than half the screen: light its top (title,
        // ring and figures) and leave room under it for the card that explains it.
        if step.target == .calories { frame.size.height = min(frame.height, size.height * 0.56) }
        // The calorie card can reach under the tab bar; light only what's on screen.
        return frame.intersection(CGRect(origin: .zero, size: size).insetBy(dx: 4, dy: 4))
    }

    private func cornerRadius(_ step: GuidedTourStep, _ hole: CGRect) -> CGFloat {
        switch step.target {
        case .quickActions: return hole.width / 2
        case .calories: return Radius.card + 6
        default: return min(hole.height / 2, 28)
        }
    }

    /// Under the lit part when there is more room there than above it.
    private func calloutBelow(_ hole: CGRect, size: CGSize) -> Bool {
        size.height - hole.maxY >= hole.minY
    }

    private func callout(_ step: GuidedTourStep, index: Int) -> some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            HStack(spacing: Spacing.sm) {
                Image(systemName: step.symbol)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(Color.onAccent)
                    .frame(width: 36, height: 36)
                    .background(Color.dullPink, in: Circle())
                    .accessibilityHidden(true)
                Text(step.title)
                    .font(.title3.weight(.bold))
                    .foregroundStyle(Color.labelPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityAddTraits(.isHeader)
                    .accessibilityFocused($titleFocused)
                    .accessibilityIdentifier("tour.title")
                Spacer(minLength: 0)
                Text("\(index + 1) of \(tour.steps.count)" as String)
                    .font(.footnote.weight(.semibold).monospacedDigit())
                    .foregroundStyle(Color.labelSecondary)
                    .accessibilityLabel("Step \(index + 1) of \(tour.steps.count)" as String)
            }
            Text(step.detail)
                .font(.subheadline)
                .foregroundStyle(Color.labelSecondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: Spacing.md) {
                Button("Skip tour") { tour.finish() }
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.labelSecondary)
                    .frame(minHeight: 44)
                    .accessibilityIdentifier("tour.skip")
                Spacer(minLength: 0)
                if index > 0 {
                    Button("Back") { tour.back() }
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Color.labelPrimary)
                        .frame(minHeight: 44)
                        .accessibilityIdentifier("tour.back")
                }
                Button { tour.next() } label: {
                    Text(index + 1 == tour.steps.count ? "Done" : "Next")
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(Color.onAccent)
                        .padding(.horizontal, Spacing.lg)
                        .frame(minHeight: 44)
                        .background(Color.dullPink, in: Capsule())
                        .contentShape(Capsule())
                }
                .buttonStyle(ScalePressStyle())
                .accessibilityIdentifier("tour.next")
            }
        }
        .padding(Spacing.lg)
        .background(Color.surfaceElevated, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .shadow(color: .black.opacity(0.25), radius: 16, x: 0, y: 8)
        .dynamicTypeSize(...DynamicTypeSize.accessibility2)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("tour.callout")
    }
}

/// The whole screen with a rounded hole; filled even-odd so the hole stays clear.
private struct SpotlightShape: Shape {
    var hole: CGRect
    var radius: CGFloat

    var animatableData: AnimatablePair<AnimatablePair<CGFloat, CGFloat>, AnimatablePair<AnimatablePair<CGFloat, CGFloat>, CGFloat>> {
        get { .init(.init(hole.minX, hole.minY), .init(.init(hole.width, hole.height), radius)) }
        set {
            hole = CGRect(x: newValue.first.first, y: newValue.first.second,
                          width: newValue.second.first.first, height: newValue.second.first.second)
            radius = newValue.second.second
        }
    }

    func path(in rect: CGRect) -> Path {
        var path = Path(rect.insetBy(dx: -200, dy: -200))
        if hole.width > 0, hole.height > 0 {
            path.addRoundedRect(in: hole, cornerSize: CGSize(width: radius, height: radius), style: .continuous)
        }
        return path
    }
}
