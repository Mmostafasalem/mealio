import SwiftUI

// MARK: - Quick actions button
//
// The bowl in a round button beside the tab bar (not a tab), like the separate
// search button in Apple's own iOS 26 apps. It is filled with the colour theme's
// accent (TestFlight B2/B3: "in a unique colour", "distinctive from every other
// button"), with a soft accent shadow.

/// Where the bowl button sits.
///
/// iOS 26 on iPhone: in the round slot the system keeps beside the glass tab bar
/// for a search tab (the bar makes room for it, as in Music or Photos), drawn over
/// that slot with the same size and baseline. Elsewhere (iOS 17 and 18, where the
/// bar runs edge to edge, and iPad, where the tabs sit at the top) it floats at the
/// bottom right, just above the bar or the home indicator.
enum QuickActionsDock {
    /// The search-role tab that reserves the slot; never stays selected.
    static let slotTag = 99

    @MainActor static var usesSystemSlot: Bool {
        guard UIDevice.current.userInterfaceIdiom == .phone else { return false }
        if #available(iOS 26.0, *) { return true }
        return false
    }

    @MainActor static var diameter: CGFloat { usesSystemSlot ? 62 : 58 }
    @MainActor static var trailing: CGFloat { usesSystemSlot ? 21 : 16 }

    /// Distance from the screen's bottom edge to the button's bottom.
    /// `barInset` is the tab content's bottom safe area (the bar plus the home indicator).
    @MainActor static func bottom(barInset: CGFloat) -> CGFloat {
        usesSystemSlot ? 22 : barInset + 12
    }

    /// Room a floating bottom bar (the cart toast) leaves on the right so it doesn't
    /// run under the button: none where the button sits beside the tab bar.
    @MainActor static var trailingClearance: CGFloat {
        usesSystemSlot ? 0 : diameter + trailing + 8
    }
}

struct QuickActionsButton: View {
    var diameter: CGFloat = 56
    let action: () -> Void

    @Environment(\.colorScheme) private var colorScheme

    private var pose: MascotPose {
        var pose = MascotPose()
        pose.shadow = 0
        return pose
    }

    var body: some View {
        Button(action: action) {
            MascotFigure(pose: pose, size: diameter * 0.64)
                // The bowl's art sits a little low in its box; centre it in the circle.
                .offset(y: -diameter * 0.03)
                .frame(width: diameter, height: diameter)
                .background { background }
                .contentShape(Circle())
        }
        .buttonStyle(BowlPressStyle())
        .accessibilityLabel("Quick actions")
        .accessibilityHint("Opens chat, voice commands and shortcuts")
        .accessibilityIdentifier("navigation.quickActions")
    }

    /// The theme's accent (not the ink colour every other control uses), so the
    /// button is the one unique, most visible control on screen. A pale disc behind
    /// the bowl keeps the mascot readable on every accent (the bowl is pink itself),
    /// and an accent-coloured shadow lifts it off the tab bar. Solid on every iOS
    /// version: tinted glass washed the colour out.
    private var background: some View {
        ZStack {
            Circle()
                .fill(Color.dullPink)
                .shadow(color: Color.dullPink.opacity(colorScheme == .dark ? 0.55 : 0.5), radius: 12, x: 0, y: 6)
                .shadow(color: .black.opacity(colorScheme == .dark ? 0.4 : 0.14), radius: 3, x: 0, y: 2)
            Circle()
                .fill(Color.surface.opacity(colorScheme == .dark ? 0.14 : 0.4))
                .padding(diameter * 0.15)
            Circle()
                .strokeBorder(Color.surface.opacity(colorScheme == .dark ? 0.35 : 0.9), lineWidth: 2)
        }
    }
}

/// A deeper squeeze than `ScalePressStyle`: the bowl button is a toy-like control.
private struct BowlPressStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.9 : 1)
            .animation(reduceMotion ? .none : .spring(response: 0.25, dampingFraction: 0.6), value: configuration.isPressed)
    }
}

// MARK: - Quick actions panel

/// What the bowl button opens: a grid. The two most useful actions the person can
/// use right now are large tiles on top (chat and voice when offered), the rest
/// smaller tiles below. Which tiles exist comes from `FeatureLayout.quickActionIDs`.
struct QuickActionsPanel: View {
    enum Choice: Equatable { case action(MealioQuickAction), chat, voice, mealPhoto, stock, addRecipe }

    struct Item: Identifiable {
        let id: String
        let title: String
        /// Shown only when the item is one of the two large tiles.
        let detail: String
        let symbol: String
        let choice: Choice
    }

    /// Only actions for these features are offered (`FeatureLayout.quickActionIDs`).
    let features: Set<AppFeature>
    /// Closes the sheet through `MainTabView`'s own state (its single sheet path).
    let close: () -> Void
    let choose: (Choice) -> Void

    @State private var appeared = false
    @State private var contentHeight: CGFloat = 560
    /// Follows the measured content, so the sheet is exactly as tall as the grid.
    @State private var detent: PresentationDetent = .height(560)
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.horizontalSizeClass) private var sizeClass

    static let catalog: [Item] = [
        Item(id: "chat", title: "Ask Nourlo", detail: "Ideas, swaps and answers",
             symbol: "bubble.left.and.text.bubble.right.fill", choice: .chat),
        Item(id: "voice", title: "Speak a command", detail: "Log food, fill the cart, start a workout",
             symbol: "mic.fill", choice: .voice),
        Item(id: MealioQuickAction.logFood.rawValue, title: "Log food", detail: "Add what you ate",
             symbol: "fork.knife", choice: .action(.logFood)),
        Item(id: "mealPhoto", title: "Snap a meal", detail: "A photo becomes a log",
             symbol: "camera.fill", choice: .mealPhoto),
        Item(id: "addRecipe", title: "Add a recipe", detail: "Paste, link or photo",
             symbol: "text.book.closed.fill", choice: .addRecipe),
        Item(id: MealioQuickAction.cart.rawValue, title: "Cart", detail: "What you're buying",
             symbol: "cart.fill", choice: .action(.cart)),
        Item(id: MealioQuickAction.groceries.rawValue, title: "Checklist", detail: "Tick off as you shop",
             symbol: "checklist", choice: .action(.groceries)),
        Item(id: MealioQuickAction.meals.rawValue, title: "Explore meals", detail: "This week's plan",
             symbol: "takeoutbag.and.cup.and.straw.fill", choice: .action(.meals)),
        Item(id: "stock", title: "My Stock", detail: "Food you have at home",
             symbol: "cabinet.fill", choice: .stock),
        Item(id: MealioQuickAction.train.rawValue, title: "Start workout", detail: "Build one and follow along",
             symbol: "figure.run", choice: .action(.train)),
        Item(id: MealioQuickAction.profile.rawValue, title: "Profile", detail: "Goals and settings",
             symbol: "person.crop.circle.fill", choice: .action(.profile)),
    ]

    /// The tiles this person can use now, most useful first.
    private var items: [Item] { Self.items(for: features) }

    static func items(for features: Set<AppFeature>) -> [Item] {
        let offered = FeatureLayout.quickActionIDs(for: features)
        return offered.compactMap { id in Self.catalog.first { $0.id == id } }.filter { item in
            switch item.choice {
            case .chat: return AIAccountService.shared.offersOnlineAI
            default: return true
            }
        }
    }

    /// The first two, except Profile, which is never a large tile.
    private var featured: [Item] {
        Array(items.filter { $0.choice != .action(.profile) }.prefix(2))
    }

    private var others: [Item] {
        let big = Set(featured.map(\.id))
        return items.filter { !big.contains($0.id) }
    }

    private var columnCount: Int {
        if typeSize.isAccessibilitySize { return 2 }
        if typeSize >= .xxLarge { return 3 }
        return sizeClass == .regular ? 5 : 4
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.lg) {
                header
                featuredTiles
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: Spacing.md, alignment: .top),
                                         count: columnCount),
                          spacing: Spacing.md) {
                    ForEach(Array(others.enumerated()), id: \.element.id) { index, item in
                        smallTile(item)
                            .modifier(PopIn(shown: appeared, index: index + featured.count, reduceMotion: reduceMotion))
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 22)
            .padding(.bottom, Spacing.lg)
            // The sheet is as tall as its tiles (a preference wouldn't leave the ScrollView).
            .onGeometryChange(for: CGFloat.self) { proxy in proxy.size.height } action: { height in
                fit(height)
            }
        }
        .scrollBounceBehavior(.basedOnSize)
        .presentationDetents(typeSize.isAccessibilitySize ? [.large] : [.height(contentHeight), .large], selection: $detent)
        .presentationDragIndicator(.visible)
        .presentationCornerRadius(34)
        .onAppear {
            appeared = true
            if typeSize.isAccessibilitySize { detent = .large }
        }
    }

    private func fit(_ height: CGFloat) {
        // Ignore an empty first pass; keep a little room above the home indicator.
        guard height > 120 else { return }
        let fitted = (height + 8).rounded()
        guard abs(fitted - contentHeight) > 1 else { return }
        let wasFitted = detent != .large
        contentHeight = fitted
        if wasFitted && !typeSize.isAccessibilitySize { detent = .height(fitted) }
    }

    private var header: some View {
        HStack(alignment: .center, spacing: Spacing.md) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Quick actions")
                    .font(.title3.weight(.bold))
                    .foregroundStyle(Color.labelPrimary)
                    .accessibilityAddTraits(.isHeader)
                Text("What would you like to do?")
                    .font(.subheadline)
                    .foregroundStyle(Color.labelSecondary)
            }
            Spacer(minLength: Spacing.sm)
            Button { close() } label: {
                Text("Done")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(Color.labelPrimary)
                    .padding(.horizontal, Spacing.md)
                    .frame(minWidth: 44, minHeight: 44)
                    .background(Color.surfaceSecondary, in: Capsule())
                    .contentShape(Capsule())
            }
            .buttonStyle(ScalePressStyle())
            .accessibilityIdentifier("quickActions.done")
        }
    }

    @ViewBuilder private var featuredTiles: some View {
        let layout = typeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(spacing: Spacing.md))
            : AnyLayout(HStackLayout(alignment: .top, spacing: Spacing.md))
        layout {
            ForEach(Array(featured.enumerated()), id: \.element.id) { index, item in
                bigTile(item, primary: index == 0)
                    .modifier(PopIn(shown: appeared, index: index, reduceMotion: reduceMotion))
            }
        }
    }

    private func bigTile(_ item: Item, primary: Bool) -> some View {
        // The first is the inverse of the page; the second the soft pink accent.
        let fill = primary ? Color.brandPrimary : Color.progress
        let ink = primary ? Color.surface : Color.onAccent
        return Button { choose(item.choice) } label: {
            VStack(alignment: .leading, spacing: Spacing.sm) {
                Image(systemName: item.symbol)
                    .font(.system(size: 18, weight: .semibold))
                    .frame(width: 42, height: 42)
                    .background(ink.opacity(0.14), in: Circle())
                    .accessibilityHidden(true)
                Spacer(minLength: Spacing.sm)
                Text(item.title)
                    .font(.headline)
                    .fixedSize(horizontal: false, vertical: true)
                Text(item.detail)
                    .font(.caption)
                    .opacity(0.78)
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .foregroundStyle(ink)
            .multilineTextAlignment(.leading)
            .frame(maxWidth: .infinity, minHeight: 112, alignment: .topLeading)
            .padding(Spacing.lg)
            .background(fill, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        }
        .buttonStyle(ScalePressStyle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(item.title)
        .accessibilityHint(item.detail)
        .accessibilityAddTraits(.isButton)
        .accessibilityIdentifier("quickActions." + item.id)
    }

    private func smallTile(_ item: Item) -> some View {
        Button { choose(item.choice) } label: {
            VStack(spacing: Spacing.sm) {
                Image(systemName: item.symbol)
                    .font(.system(size: 19, weight: .semibold))
                    .foregroundStyle(Color.labelPrimary)
                    .frame(width: 46, height: 46)
                    .background(Color.surface, in: Circle())
                    .accessibilityHidden(true)
                Text(item.title)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(Color.labelPrimary)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .minimumScaleFactor(0.85)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, minHeight: 96, alignment: .top)
            .padding(.vertical, Spacing.md)
            .padding(.horizontal, Spacing.xs)
            .background(Color.surfaceSecondary, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        }
        .buttonStyle(ScalePressStyle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(item.title)
        .accessibilityAddTraits(.isButton)
        .accessibilityIdentifier("quickActions." + item.id)
    }
}

/// Tiles spring in one after another as the panel rises; Reduce Motion shows them at once.
private struct PopIn: ViewModifier {
    let shown: Bool
    let index: Int
    let reduceMotion: Bool

    func body(content: Content) -> some View {
        content
            .opacity(shown || reduceMotion ? 1 : 0)
            .scaleEffect(shown || reduceMotion ? 1 : 0.86)
            .offset(y: shown || reduceMotion ? 0 : 14)
            .animation(reduceMotion ? nil : .spring(response: 0.42, dampingFraction: 0.72)
                .delay(0.05 + Double(index) * 0.03), value: shown)
    }
}
