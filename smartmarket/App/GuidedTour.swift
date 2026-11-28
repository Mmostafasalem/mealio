import SwiftUI
import UIKit

// MARK: - Guided tour with Nourlo
//
// Owner, 28 Nov 2026: "include guide tour with Nourlo introducing it all over all
// pages and all features and how to use them". Nourlo (the real animated figure)
// walks through every page the person chose: Home, the quick-actions pills, Meals,
// Shop, Train and Profile. Each step lights up the real control, and Nourlo, in a
// speech bubble that moves to it, says what it is and how to use it. The tour
// switches tabs, opens the pills and Profile, and scrolls to each part by itself.
// Next / Back / Skip and "n of N"; only the features the person chose; Reduce
// Motion: no walking, each step fades in; VoiceOver reads each step.
// It runs once after onboarding and can be replayed from Profile › Help & legal
// (`ReplayTourRow`) and the quick actions ("Take the tour").

/// Which screen a step is on. The tour opens it itself.
enum TourPage: String, Equatable, Sendable {
    case home, quickActions, meals, shop, train, profile

    /// The tab the page lives on (the pills open over Home; Profile is pushed on Home).
    var tab: AppTab {
        switch self {
        case .home, .quickActions, .profile: return .home
        case .meals: return .meals
        case .shop: return .shop
        case .train: return .train
        }
    }
}

/// A part of the screen the tour can light up (`tourTarget`).
enum TourTarget: String, CaseIterable, Sendable {
    // Home
    case nourlo, calories, insights, logFood, voice, quests, todaysMeals, groceries, training
    // Quick actions
    case qaChat, qaVoice, qaPhoto, qaRecipe, qaTour
    // Meals
    case dayStrip, mealCard, reviewRecipe, mealsStock, regenerate
    // Shop
    case budget, aboutPrices, weeklyGroceries, catalogue, cart
    // Train
    case programmes, buildWorkout, exercises
    // Profile
    case profileCard, profileTargets, profileAppearance, profileHelp
}

struct GuidedTourStep: Equatable, Identifiable {
    let id: String
    let page: TourPage
    let target: TourTarget
    let title: String
    /// What it is.
    let what: String
    /// How to use it.
    let how: String
    let mood: MascotMood
    /// Scroll here first (the target's card, or the target itself).
    var scrollTo: TourTarget?
    /// Where the scrolled-to part should end up on screen.
    var scrollAnchor: UnitPoint = .center

    var detail: String { what + " " + how }

    /// Every step, in order. `steps(for:)` keeps the ones the person's features use.
    static func all(offersChat: Bool) -> [(step: GuidedTourStep, needs: (Set<AppFeature>) -> Bool)] {
        let always: (Set<AppFeature>) -> Bool = { _ in true }
        func has(_ f: AppFeature) -> (Set<AppFeature>) -> Bool { { $0.contains(f) } }
        let tracking = has(.tracking)
        let voice: (Set<AppFeature>) -> Bool = { $0.contains(.tracking) && FeatureLayout.showsVoice($0) }
        return [
            // Home
            (GuidedTourStep(id: "hello", page: .home, target: .nourlo, title: "Hi, I'm Nourlo!",
                            what: "Let me show you every page and how it works.",
                            how: "Tap Next to follow me, or Skip to look around on your own.", mood: .help,
                            scrollTo: .nourlo, scrollAnchor: .top), always),
            (GuidedTourStep(id: "calories", page: .home, target: .calories, title: "Calories today",
                            what: "The ring shows what you've eaten against today's goal, with protein, carbs and fat below.",
                            how: "It fills up as you log food.", mood: .happy,
                            scrollTo: .calories, scrollAnchor: .top), tracking),
            (GuidedTourStep(id: "insights", page: .home, target: .insights, title: "Insights",
                            what: "Your calories over the last 7 and 30 days, your streak and your macros.",
                            how: "Tap Insights to open them.", mood: .cheeky,
                            scrollTo: .calories, scrollAnchor: .top), tracking),
            (GuidedTourStep(id: "logFood", page: .home, target: .logFood, title: "Log food",
                            what: "Add what you ate in a few taps.",
                            how: "Tap Log food, search for it, pick the portion and the meal.", mood: .happy,
                            scrollTo: .calories, scrollAnchor: .top), tracking),
            (GuidedTourStep(id: "voice", page: .home, target: .voice, title: "Just say it",
                            what: "The microphone turns what you say into a log, a cart item or a workout.",
                            how: "Tap it and say something like \"two eggs for breakfast\". It stops when you stop.", mood: .cheeky,
                            scrollTo: .calories, scrollAnchor: .top), voice),
            (GuidedTourStep(id: "quests", page: .home, target: .quests, title: "Today's quests",
                            what: "Small goals for today that build your streak.",
                            how: "Tap a quest to go straight to it.", mood: .celebrate, scrollTo: .quests, scrollAnchor: .top), always),
            (GuidedTourStep(id: "todaysMeals", page: .home, target: .todaysMeals, title: "Today's meals",
                            what: "A preview of today's plan and its calories.",
                            how: "Tap Open plan to see every meal.", mood: .happy, scrollTo: .todaysMeals, scrollAnchor: .top), has(.meals)),
            (GuidedTourStep(id: "groceries", page: .home, target: .groceries, title: "Groceries",
                            what: "Your cart, checklist and My Stock at a glance.",
                            how: "Tap a row to open it, or Shop to fill your week.", mood: .happy, scrollTo: .groceries, scrollAnchor: .top), has(.groceries)),
            (GuidedTourStep(id: "training", page: .home, target: .training, title: "Training",
                            what: "This week's workouts and minutes.",
                            how: "Tap it to build a workout and start.", mood: .flex, scrollTo: .training, scrollAnchor: .top), has(.workouts)),
            (GuidedTourStep(id: "quickActions", page: .home, target: .nourlo, title: "I'm your shortcut",
                            what: "I sit at the top of every page.",
                            how: "Tap me and your quick actions drop down. Tap me again to close them.", mood: .help,
                            scrollTo: .nourlo, scrollAnchor: .top), always),
            // Quick actions
            (GuidedTourStep(id: "qaChat", page: .quickActions, target: .qaChat, title: "Ask Nourlo",
                            what: "Chat with me about meals, swaps, food or training.",
                            how: "Type a question and I'll answer.", mood: .cheeky, scrollTo: .nourlo, scrollAnchor: .top), { _ in offersChat }),
            (GuidedTourStep(id: "qaVoice", page: .quickActions, target: .qaVoice, title: "Speak a command",
                            what: "Log food, fill the cart or start a workout with your voice.",
                            how: "Tap it, speak, and check what I heard before it's saved.", mood: .happy, scrollTo: .nourlo, scrollAnchor: .top), { FeatureLayout.showsVoice($0) }),
            (GuidedTourStep(id: "qaPhoto", page: .quickActions, target: .qaPhoto, title: "Snap a meal",
                            what: "A photo of your plate becomes a food log.",
                            how: "Take the photo, then check the foods and grams and save.", mood: .love, scrollTo: .nourlo, scrollAnchor: .top), tracking),
            (GuidedTourStep(id: "qaRecipe", page: .quickActions, target: .qaRecipe, title: "Add a recipe",
                            what: "Keep your own recipes next to the ones I suggest.",
                            how: "Paste the text, share a link or take a photo of the page.", mood: .happy, scrollTo: .nourlo, scrollAnchor: .top), tracking),
            (GuidedTourStep(id: "qaTour", page: .quickActions, target: .qaTour, title: "Take the tour",
                            what: "This tour lives here too.",
                            how: "Tap it whenever you want me to show you around again.", mood: .help, scrollTo: .nourlo, scrollAnchor: .top), always),
            // Meals
            (GuidedTourStep(id: "dayStrip", page: .meals, target: .dayStrip, title: "Your week of meals",
                            what: "Today and the next six days.",
                            how: "Tap a day, or swipe the meals sideways to change day.", mood: .happy, scrollTo: .dayStrip), has(.meals)),
            (GuidedTourStep(id: "mealCard", page: .meals, target: .mealCard, title: "A meal",
                            what: "Each meal is built from your cart and My Stock to fit your goal.",
                            how: "Tap a meal to see its ingredients, portions and macros.", mood: .love, scrollTo: .mealCard, scrollAnchor: .top), has(.meals)),
            (GuidedTourStep(id: "reviewRecipe", page: .meals, target: .reviewRecipe, title: "Review recipe and log",
                            what: "Shows how to make the meal and the portions it uses.",
                            how: "Check the amounts, then log it; the food comes out of My Stock.", mood: .happy,
                            scrollTo: .reviewRecipe), has(.meals)),
            (GuidedTourStep(id: "mealsStock", page: .meals, target: .mealsStock, title: "My Stock",
                            what: "The food you have at home. Your plan uses it first.",
                            how: "Tap My Stock to add food or mark what you used.", mood: .cheeky, scrollTo: .dayStrip), has(.meals)),
            (GuidedTourStep(id: "regenerate", page: .meals, target: .regenerate, title: "A fresh plan",
                            what: "Changed your cart or your stock?",
                            how: "Tap Regenerate plan and I'll rebuild the whole week.", mood: .thinking, scrollTo: .regenerate), has(.meals)),
            // Shop
            (GuidedTourStep(id: "budget", page: .shop, target: .budget, title: "Weekly budget",
                            what: "What's in your cart against this week's budget.",
                            how: "Tap Edit to change the amount.", mood: .happy, scrollTo: .budget), has(.groceries)),
            (GuidedTourStep(id: "aboutPrices", page: .shop, target: .aboutPrices, title: "About prices",
                            what: "Prices are estimates for one product catalogue, not live store prices.",
                            how: "Tap Change to show them in your currency.", mood: .thinking, scrollTo: .aboutPrices), has(.groceries)),
            (GuidedTourStep(id: "weeklyGroceries", page: .shop, target: .weeklyGroceries, title: "This week's groceries",
                            what: "A balanced week of shopping that fits what's left of your budget.",
                            how: "Remove what you don't want, then tap Add all.", mood: .love, scrollTo: .weeklyGroceries, scrollAnchor: .top), has(.groceries)),
            (GuidedTourStep(id: "catalogue", page: .shop, target: .catalogue, title: "Catalogue and My Stock",
                            what: "Every product by category, and the food you already have.",
                            how: "Open the catalogue and tap + on a product to add it to your cart.", mood: .happy,
                            scrollTo: .catalogue), has(.groceries)),
            (GuidedTourStep(id: "cart", page: .shop, target: .cart, title: "Your cart",
                            what: "Everything you're buying this week.",
                            how: "Tap the cart up here, or the View cart bar that floats over the catalogue.", mood: .cheeky,
                            scrollTo: .budget), has(.groceries)),
            // Train
            (GuidedTourStep(id: "programmes", page: .train, target: .programmes, title: "Programmes",
                            what: "Plans to follow week after week.",
                            how: "Tap See all, start one, and I'll keep track of the next day.", mood: .flex, scrollTo: .programmes, scrollAnchor: .top), has(.workouts)),
            (GuidedTourStep(id: "buildWorkout", page: .train, target: .buildWorkout, title: "Build a workout",
                            what: "A workout made for you from a type, a level and a length.",
                            how: "Choose them, tap Build, then follow along set by set.", mood: .flex,
                            scrollTo: .buildWorkout, scrollAnchor: .top), has(.workouts)),
            (GuidedTourStep(id: "exercises", page: .train, target: .exercises, title: "Exercises by muscle",
                            what: "Every exercise, with a moving demo of how to do it.",
                            how: "Tap a muscle, then an exercise to see how it's done.", mood: .happy, scrollTo: .exercises, scrollAnchor: .top), has(.workouts)),
            // Profile
            (GuidedTourStep(id: "profileCard", page: .profile, target: .profileCard, title: "Your profile",
                            what: "Your name and photo.",
                            how: "Tap the card to edit them.", mood: .love), always),
            (GuidedTourStep(id: "profileTargets", page: .profile, target: .profileTargets, title: "Goals & targets",
                            what: "Your goal, your daily calories and macros.",
                            how: "Tap it to change your goal or set your own targets.", mood: .thinking), always),
            (GuidedTourStep(id: "profileAppearance", page: .profile, target: .profileAppearance, title: "Appearance",
                            what: "Light or dark, and colour themes.",
                            how: "Tap it and pick the look you like.", mood: .happy), always),
            (GuidedTourStep(id: "profileHelp", page: .profile, target: .profileHelp, title: "Help & legal",
                            what: "Support, privacy, and this tour.",
                            how: "Tap Replay the tour in here whenever you like.", mood: .help), always),
            // The end, back on Home
            (GuidedTourStep(id: "bye", page: .home, target: .nourlo, title: "That's everything!",
                            what: "You know your way around now.",
                            how: "Tap me whenever you need something. Enjoy Nourlo!", mood: .celebrate,
                            scrollTo: .nourlo, scrollAnchor: .top), always),
        ]
    }

    /// The steps for the features the person chose.
    static func steps(for features: Set<AppFeature>, offersChat: Bool = false) -> [GuidedTourStep] {
        all(offersChat: offersChat).filter { $0.needs(features) }.map(\.step)
    }

    static func == (lhs: GuidedTourStep, rhs: GuidedTourStep) -> Bool { lhs.id == rhs.id }
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
    /// Where on screen (global coordinates) each target is, reported by `tourTarget`.
    /// The owner is the view that reported it, so a view that goes away only removes its own.
    @ObservationIgnored private var frames: [TourTarget: (owner: UUID, frame: CGRect)] = [:]
    /// Bumped when a frame changes, so the overlay can follow it.
    private(set) var framesRevision = 0

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

    /// From Profile › Help or the quick actions: back to Home, then the tour again.
    func replay() {
        NotificationCenter.default.post(name: .openHome, object: nil)
        start(features: AppState.shared.enabledFeatures, after: 0.7)
    }

    func start(features: Set<AppFeature>, after delay: Double = 0) {
        pendingStart?.cancel()
        pendingStart = Task { @MainActor [weak self] in
            if delay > 0 { try? await Task.sleep(for: .seconds(delay)) }
            guard let self, !Task.isCancelled else { return }
            self.steps = GuidedTourStep.steps(for: features, offersChat: AIAccountService.shared.offersOnlineAI)
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

    func report(_ target: TourTarget, frame: CGRect, owner: UUID) {
        if let old = frames[target], old.owner == owner, old.frame == frame { return }
        frames[target] = (owner, frame)
        if isRunning, current?.target == target { framesRevision &+= 1 }
    }

    func remove(_ target: TourTarget, owner: UUID) {
        guard frames[target]?.owner == owner else { return }
        frames[target] = nil
        if isRunning, current?.target == target { framesRevision &+= 1 }
    }

    func frame(for target: TourTarget) -> CGRect? {
        guard let frame = frames[target]?.frame, frame.width > 1, frame.height > 1 else { return nil }
        return frame
    }
}

extension View {
    /// Marks this view as the part of the screen the guided tour lights up for `target`.
    func tourTarget(_ target: TourTarget) -> some View {
        modifier(TourTargetModifier(target: target))
    }

    /// Scrolls the enclosing `ScrollViewReader` to the current tour step's part of this page.
    func tourScrolling(_ pages: Set<TourPage>, proxy: ScrollViewProxy) -> some View {
        modifier(TourScrollModifier(pages: pages, proxy: proxy))
    }
}

private struct TourTargetModifier: ViewModifier {
    let target: TourTarget
    @State private var owner = UUID()

    func body(content: Content) -> some View {
        content
            .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { frame in
                GuidedTour.shared.report(target, frame: frame, owner: owner)
            }
            .onDisappear { GuidedTour.shared.remove(target, owner: owner) }
    }
}

private struct TourScrollModifier: ViewModifier {
    let pages: Set<TourPage>
    let proxy: ScrollViewProxy
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content.onChange(of: GuidedTour.shared.current?.id) { _, _ in scroll() }
            .onAppear { scroll() }
    }

    private func scroll() {
        guard let step = GuidedTour.shared.current, pages.contains(step.page), let target = step.scrollTo else { return }
        // After a tab switch or a card opening has had a moment to lay out.
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(120))
            withAnimation(reduceMotion ? nil : .smooth(duration: 0.45)) {
                proxy.scrollTo(target, anchor: step.scrollAnchor)
            }
        }
    }
}

// MARK: - Overlay

/// The dimmed screen with the lit part and Nourlo's speech bubble. Lives above every tab.
struct GuidedTourOverlay: View {
    @State private var tour = GuidedTour.shared
    @State private var rig = MascotRig()
    /// The lit rectangle in the overlay's coordinates (`nil`: nothing to light).
    @State private var hole: CGRect?
    /// Measured height of the bubble, to place it above the lit part.
    @State private var bubbleHeight: CGFloat = 190
    /// True from a step change until its part has been found and lit.
    @State private var moving = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.scenePhase) private var scenePhase
    @AccessibilityFocusState private var titleFocused: Bool

    var body: some View {
        if let step = tour.current, let index = tour.index {
            GeometryReader { geometry in
                let size = geometry.size
                let origin = geometry.frame(in: .global).origin
                let insets = Self.windowInsets
                let layout = BubbleLayout(hole: hole, size: size, bubbleHeight: bubbleHeight,
                                          safeTop: insets.top, safeBottom: insets.bottom)
                ZStack(alignment: .topLeading) {
                    SpotlightShape(hole: hole ?? CGRect(x: size.width / 2, y: size.height / 2, width: 0, height: 0), radius: radius(for: step, hole))
                        .fill(Color.black.opacity(0.6), style: FillStyle(eoFill: true))
                        .contentShape(Rectangle())
                        .onTapGesture {}
                        .accessibilityHidden(true)
                    if let hole {
                        RoundedRectangle(cornerRadius: radius(for: step, hole), style: .continuous)
                            .strokeBorder(Color.dullPink, lineWidth: 2.5)
                            .shadow(color: Color.dullPink.opacity(0.6), radius: 8)
                            .frame(width: hole.width, height: hole.height)
                            .position(x: hole.midX, y: hole.midY)
                            .allowsHitTesting(false)
                            .accessibilityHidden(true)
                    }
                    bubble(step, index: index, layout: layout)
                        .frame(width: layout.width)
                        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { bubbleHeight = $0 }
                        .offset(x: layout.x, y: layout.y)
                        .id(reduceMotion ? step.id : "bubble")
                        .transition(.opacity)
                }
                .animation(reduceMotion ? nil : .spring(response: 0.55, dampingFraction: 0.82), value: hole)
                .animation(reduceMotion ? nil : .spring(response: 0.55, dampingFraction: 0.82), value: bubbleHeight)
                .animation(reduceMotion ? .easeInOut(duration: 0.25) : nil, value: step.id)
                .task(id: step.id) { await follow(step, origin: origin, size: size) }
                .onChange(of: tour.framesRevision) { _, _ in
                    guard !moving else { return }
                    hole = lit(step, origin: origin, size: size)
                }
            }
            .ignoresSafeArea()
            .transition(.opacity)
            .accessibilityAddTraits(.isModal)
            .onAppear {
                rig.reduceMotion = reduceMotion
                rig.setActive(true)
            }
            .onDisappear { rig.setActive(false); hole = nil }
            .onChange(of: scenePhase) { _, phase in rig.setActive(phase == .active) }
        }
    }

    // MARK: Following the steps

    /// Waits for the step's part to be laid out (a tab switch, a scroll, a card
    /// opening), then moves the light and Nourlo there.
    private func follow(_ step: GuidedTourStep, origin: CGPoint, size: CGSize) async {
        moving = true
        if !reduceMotion { rig.walk(speed: 1) }
        // Read the part's frame until it holds still.
        var last: CGRect?
        var steady = 0
        for _ in 0..<16 {
            try? await Task.sleep(for: .milliseconds(110))
            if Task.isCancelled { return }
            let now = lit(step, origin: origin, size: size)
            if let now, let last, abs(now.minY - last.minY) < 0.5, abs(now.height - last.height) < 0.5 {
                steady += 1
                if steady >= 2 { break }
            } else {
                steady = 0
            }
            last = now
        }
        hole = lit(step, origin: origin, size: size)
        moving = false
        try? await Task.sleep(for: .milliseconds(reduceMotion ? 0 : 420))
        rig.walk(speed: 0)
        rig.set(mood: step.mood)
        if !reduceMotion, step.mood == .happy || step.mood == .idle { rig.react(.tap) }
        titleFocused = true
        AccessibilityNotification.Announcement(
            "Step \((tour.index ?? 0) + 1) of \(tour.steps.count). \(step.title). \(step.detail)").post()
    }

    /// The lit rectangle for a step, in the overlay's coordinates, a little larger than its part.
    private func lit(_ step: GuidedTourStep, origin: CGPoint, size: CGSize) -> CGRect? {
        guard var frame = tour.frame(for: step.target) else { return nil }
        frame = frame.offsetBy(dx: -origin.x, dy: -origin.y)
        let pad: CGFloat = step.target == .nourlo ? 2 : 6
        frame = frame.insetBy(dx: -pad, dy: -pad)
        // A tall card: light its top and leave room for Nourlo's bubble.
        frame.size.height = min(frame.height, size.height * 0.42)
        let screen = CGRect(origin: .zero, size: size).insetBy(dx: 4, dy: 4)
        let visible = frame.intersection(screen)
        guard !visible.isNull, visible.width > 8, visible.height > 8 else { return nil }
        return visible
    }

    private func radius(for step: GuidedTourStep, _ hole: CGRect?) -> CGFloat {
        guard let hole else { return 0 }
        switch step.target {
        case .nourlo, .voice: return min(hole.width, hole.height) / 2
        case .calories, .quests, .todaysMeals, .groceries, .training, .mealCard, .budget,
             .weeklyGroceries, .aboutPrices, .buildWorkout, .programmes, .exercises:
            return Radius.card + 4
        default: return min(hole.height / 2, 22)
        }
    }

    private static var windowInsets: UIEdgeInsets {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .first(where: \.isKeyWindow)?.safeAreaInsets ?? UIEdgeInsets(top: 59, left: 0, bottom: 34, right: 0)
    }

    // MARK: Bubble

    private func bubble(_ step: GuidedTourStep, index: Int, layout: BubbleLayout) -> some View {
        let stacked = typeSize.isAccessibilitySize
        let speaker = MascotFigure(pose: rig.pose, size: stacked ? 48 : 58)
            .frame(width: stacked ? 56 : 64, height: stacked ? 56 : 64)
            .accessibilityHidden(true)
        let text = VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: Spacing.sm) {
                Text(step.title)
                    .font(.headline)
                    .foregroundStyle(Color.labelPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityAddTraits(.isHeader)
                    .accessibilityFocused($titleFocused)
                    .accessibilityIdentifier("tour.title")
                Spacer(minLength: 0)
                Text("\(index + 1) of \(tour.steps.count)" as String)
                    .font(.caption.weight(.semibold).monospacedDigit())
                    .foregroundStyle(Color.labelSecondary)
                    .accessibilityLabel("Step \(index + 1) of \(tour.steps.count)" as String)
                    .accessibilityIdentifier("tour.progress")
            }
            Text(step.what)
                .font(.subheadline)
                .foregroundStyle(Color.labelPrimary.opacity(0.9))
                .fixedSize(horizontal: false, vertical: true)
            Text(step.how)
                .font(.subheadline)
                .foregroundStyle(Color.labelSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        return VStack(alignment: .leading, spacing: Spacing.md) {
            if stacked {
                speaker
                text
            } else {
                HStack(alignment: .top, spacing: 10) {
                    speaker.padding(.top, -6).padding(.leading, -6)
                    text
                }
            }
            controls(index: index)
            progressDots(index: index)
        }
        .padding(Spacing.lg)
        .background {
            BubbleShape(tailX: layout.tailX, tailUp: layout.tailUp, showsTail: layout.showsTail)
                .fill(Color.surfaceElevated)
                .shadow(color: .black.opacity(0.28), radius: 18, x: 0, y: 8)
        }
        .dynamicTypeSize(...DynamicTypeSize.accessibility2)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("tour.callout")
    }

    private func controls(index: Int) -> some View {
        HStack(spacing: Spacing.md) {
            Button("Skip") { tour.finish() }
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Color.labelSecondary)
                .frame(minHeight: 44)
                .accessibilityLabel("Skip tour")
                .accessibilityIdentifier("tour.skip")
            Spacer(minLength: 0)
            if index > 0 {
                Button("Back") { tour.back() }
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.labelPrimary)
                    .padding(.horizontal, Spacing.sm)
                    .frame(minWidth: 44, minHeight: 44)
                    .contentShape(Rectangle())
                    .accessibilityIdentifier("tour.back")
            }
            Button { tour.next() } label: {
                Text(index + 1 == tour.steps.count ? "Done" : "Next")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(Color.onAccent)
                    .padding(.horizontal, Spacing.xl)
                    .frame(minHeight: 44)
                    .background(Color.dullPink, in: Capsule())
                    .contentShape(Capsule())
            }
            .buttonStyle(ScalePressStyle())
            .accessibilityIdentifier("tour.next")
        }
        .buttonStyle(.plain)
    }

    /// A slim progress bar along the bottom of the bubble.
    private func progressDots(index: Int) -> some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.labelPrimary.opacity(0.08))
                Capsule().fill(Color.dullPink)
                    .frame(width: max(6, geo.size.width * CGFloat(index + 1) / CGFloat(max(tour.steps.count, 1))))
            }
        }
        .frame(height: 4)
        .animation(reduceMotion ? nil : .smooth(duration: 0.4), value: index)
        .accessibilityHidden(true)
    }
}

/// Where Nourlo's bubble goes: under the lit part when there's more room there,
/// else over it, with its tail pointing at it; centred when nothing is lit.
private struct BubbleLayout {
    let width: CGFloat
    let x: CGFloat
    let y: CGFloat
    let tailX: CGFloat
    let tailUp: Bool
    let showsTail: Bool

    init(hole: CGRect?, size: CGSize, bubbleHeight: CGFloat, safeTop: CGFloat, safeBottom: CGFloat) {
        let width = min(size.width - 24, 440)
        let x = (size.width - width) / 2
        self.width = width
        self.x = x
        let minY = safeTop + 8
        let maxY = size.height - safeBottom - 8 - bubbleHeight
        guard let hole else {
            y = max(minY, (size.height - bubbleHeight) / 2)
            tailX = width / 2; tailUp = true; showsTail = false
            return
        }
        let below = size.height - hole.maxY >= hole.minY
        let gap: CGFloat = 16
        let wanted = below ? hole.maxY + gap : hole.minY - gap - bubbleHeight
        let clamped = min(max(wanted, minY), max(minY, maxY))
        y = clamped
        tailUp = below
        showsTail = abs(clamped - wanted) < 1
        tailX = min(max(hole.midX - x, 30), width - 30)
    }
}

/// A rounded bubble with a small tail on its top or bottom edge.
private struct BubbleShape: Shape {
    var tailX: CGFloat
    var tailUp: Bool
    var showsTail: Bool

    var animatableData: CGFloat {
        get { tailX }
        set { tailX = newValue }
    }

    func path(in rect: CGRect) -> Path {
        var path = Path(roundedRect: rect, cornerRadius: 26, style: .continuous)
        guard showsTail else { return path }
        let w: CGFloat = 22, h: CGFloat = 10
        var tail = Path()
        if tailUp {
            tail.move(to: CGPoint(x: tailX - w / 2, y: rect.minY + 1))
            tail.addQuadCurve(to: CGPoint(x: tailX, y: rect.minY - h), control: CGPoint(x: tailX - 3, y: rect.minY - 2))
            tail.addQuadCurve(to: CGPoint(x: tailX + w / 2, y: rect.minY + 1), control: CGPoint(x: tailX + 3, y: rect.minY - 2))
        } else {
            tail.move(to: CGPoint(x: tailX - w / 2, y: rect.maxY - 1))
            tail.addQuadCurve(to: CGPoint(x: tailX, y: rect.maxY + h), control: CGPoint(x: tailX - 3, y: rect.maxY + 2))
            tail.addQuadCurve(to: CGPoint(x: tailX + w / 2, y: rect.maxY - 1), control: CGPoint(x: tailX + 3, y: rect.maxY + 2))
        }
        tail.closeSubpath()
        path.addPath(tail)
        return path
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
