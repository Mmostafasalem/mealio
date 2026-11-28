import SwiftUI

// MARK: - Quick actions (pills that drop out of Nourlo)
//
// Owner, 28 Nov 2026, with a Dribbble "floating action button / expandable menu"
// reference: "I wanted like this but use the current mascot with its animation as
// the button". So there is no card, grid or header: Nourlo at the top right is the
// button. Tapping it makes it hop, a small × appears on it, and a short stack of
// separate frosted pills springs down out of it one after another (each one a short
// label and a coloured icon, right-aligned under Nourlo so the icons line up in a
// column). Closing folds them back into Nourlo, the last one first. The page behind
// is only lightly dimmed, with Nourlo left clear so it can still be tapped to close.
// Reduce Motion: the pills fade in and out.

struct QuickActionsMenu: View {
    enum Choice: Equatable { case action(MealioQuickAction), chat, voice, mealPhoto, stock, addRecipe, tour }

    struct Item: Identifiable, Equatable {
        let id: String
        let title: String
        /// The VoiceOver hint.
        let detail: String
        let symbol: String
        let choice: Choice
    }

    /// Every action, in the order the pills show them.
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
        Item(id: "stock", title: "My Stock", detail: "Food you have at home",
             symbol: "cabinet.fill", choice: .stock),
        Item(id: MealioQuickAction.cart.rawValue, title: "Cart", detail: "What you're buying",
             symbol: "cart.fill", choice: .action(.cart)),
        Item(id: MealioQuickAction.groceries.rawValue, title: "Checklist", detail: "Tick off as you shop",
             symbol: "checklist", choice: .action(.groceries)),
        Item(id: MealioQuickAction.meals.rawValue, title: "Explore meals", detail: "This week's plan",
             symbol: "takeoutbag.and.cup.and.straw.fill", choice: .action(.meals)),
        Item(id: MealioQuickAction.train.rawValue, title: "Start workout", detail: "Build one and follow along",
             symbol: "figure.run", choice: .action(.train)),
        Item(id: MealioQuickAction.profile.rawValue, title: "Profile", detail: "Goals and settings",
             symbol: "person.crop.circle.fill", choice: .action(.profile)),
        Item(id: "tour", title: "Take the tour", detail: "Nourlo shows you every page and how to use it",
             symbol: "sparkles", choice: .tour),
    ]

    /// The pills this person can use now: the chosen features' actions
    /// (`FeatureLayout.quickActionIDs`), chat only while online AI is offered, and the tour.
    @MainActor static func items(for features: Set<AppFeature>) -> [Item] {
        items(for: features, offersChat: AIAccountService.shared.offersOnlineAI)
    }

    static func items(for features: Set<AppFeature>, offersChat: Bool) -> [Item] {
        let offered = Set(FeatureLayout.quickActionIDs(for: features) + ["tour"])
        return catalog.filter { offered.contains($0.id) && ($0.choice != .chat || offersChat) }
    }

    /// Up to this many pills show at once; the rest wait behind "More".
    static let firstPills = 6

    let features: Set<AppFeature>
    let choose: (Choice) -> Void

    @State private var center = QuickActionsCenter.shared
    @State private var shown = false
    @State private var expanded = false
    @State private var closing = false
    @AccessibilityFocusState private var focused: String?
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    @Environment(\.colorScheme) private var colorScheme

    /// UI tests tap pills as soon as they can be hit; they fade in place instead of
    /// springing down, so a tap never lands on a moving pill.
    private static let uiTesting = ProcessInfo.processInfo.arguments.contains("-NourloUITesting")
    private var reduceMotion: Bool { systemReduceMotion || Self.uiTesting }

    private var items: [Item] { Self.items(for: features) }
    /// With more than seven, the first six and a "More" pill.
    private var folds: Bool { items.count > Self.firstPills + 1 }
    private var head: [Item] { folds ? Array(items.prefix(Self.firstPills)) : items }
    private var rest: [Item] { folds ? Array(items.dropFirst(Self.firstPills)) : [] }

    var body: some View {
        GeometryReader { geo in
            let origin = geo.frame(in: .global).origin
            let anchor = center.anchor.offsetBy(dx: -origin.x, dy: -origin.y)
            let top = anchor.maxY + 4
            ZStack(alignment: .topLeading) {
                backdrop(anchor: anchor)
                ViewThatFits(in: .vertical) {
                    column
                    ScrollView {
                        column
                            .frame(maxWidth: .infinity, alignment: .trailing)
                            .padding(.bottom, 32)
                    }
                    .scrollIndicators(.hidden)
                    .scrollBounceBehavior(.basedOnSize)
                }
                .frame(maxHeight: max(120, geo.size.height - top - geo.safeAreaInsets.bottom - 12), alignment: .top)
                .padding(.top, top)
                .padding(.trailing, max(12, geo.size.width - anchor.maxX + 2))
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)

                closeBadge
                    .position(x: anchor.maxX - 7, y: anchor.minY + 5)
            }
        }
        .ignoresSafeArea()
        .accessibilityAddTraits(.isModal)
        .accessibilityAction(.escape) { dismiss() }
        .onAppear {
            DispatchQueue.main.async {
                withAnimation(reduceMotion ? .easeOut(duration: 0.18) : nil) { shown = true }
                focused = head.first?.id
            }
        }
        .onChange(of: center.closeRequests) { _, _ in dismiss() }
        .sensoryFeedback(.impact(weight: .light, intensity: 0.7), trigger: expanded)
    }

    // MARK: Backdrop

    /// A light dim (a little stronger behind the pills) with Nourlo left clear: a
    /// tap anywhere closes, and a tap on Nourlo reaches Nourlo, which closes too.
    private func backdrop(anchor: CGRect) -> some View {
        let dark = colorScheme == .dark
        let hole = CGRect(x: anchor.midX - 32, y: anchor.midY - 32, width: 64, height: 64)
        return ZStack {
            Rectangle().fill(.ultraThinMaterial).opacity(dark ? 0.55 : 0.6)
            LinearGradient(colors: [Color.black.opacity(dark ? 0.5 : 0.22), Color.black.opacity(dark ? 0.32 : 0.08)],
                           startPoint: .topTrailing, endPoint: .bottomLeading)
        }
        .mask {
            Rectangle()
                .overlay {
                    Circle()
                        .frame(width: hole.width, height: hole.height)
                        .position(x: hole.midX, y: hole.midY)
                        .blur(radius: 8)
                        .blendMode(.destinationOut)
                }
                .compositingGroup()
        }
        .contentShape(HoleShape(hole: hole), eoFill: true)
        .onTapGesture { dismiss() }
        .opacity(shown ? 1 : 0)
        .animation(.easeOut(duration: shown ? 0.25 : 0.2), value: shown)
        .accessibilityLabel("Close quick actions")
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { dismiss() }
    }

    // MARK: Pills

    private var column: some View {
        VStack(alignment: .trailing, spacing: 10) {
            ForEach(Array(head.enumerated()), id: \.element.id) { index, item in
                pill(item, index: index)
                    .modifier(Cascade(shown: shown, index: index, count: head.count + (folds ? 1 : 0), reduceMotion: reduceMotion))
                    .accessibilityFocused($focused, equals: item.id)
            }
            if folds && !expanded {
                morePill
                    .modifier(Cascade(shown: shown, index: head.count, count: head.count + 1, reduceMotion: reduceMotion))
                    .transition(.opacity.combined(with: .scale(scale: 0.8, anchor: .trailing)))
            }
            if expanded {
                ForEach(Array(rest.enumerated()), id: \.element.id) { index, item in
                    pill(item, index: head.count + index)
                        .modifier(Cascade(shown: shown, index: head.count + index, count: items.count, reduceMotion: reduceMotion))
                        .transition(reduceMotion ? .opacity
                                    : .asymmetric(insertion: .opacity.combined(with: .offset(y: -18))
                                                    .combined(with: .scale(scale: 0.6, anchor: .topTrailing))
                                                    .animation(.spring(response: 0.42, dampingFraction: 0.74)
                                                        .delay(Double(index) * 0.04)),
                                                  removal: .opacity))
            }
            }
        }
        .padding(.leading, 12)
    }

    private func pill(_ item: Item, index: Int) -> some View {
        Button { pick(item.choice) } label: {
            pillLabel(title: item.title) {
                if item.choice == .action(.profile) {
                    ProfileAvatar(size: 34)
                } else {
                    icon(item.symbol, tint: Self.tint(item.id))
                }
            }
        }
        .buttonStyle(PillPressStyle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(item.title)
        .accessibilityHint(item.detail)
        .accessibilityAddTraits(.isButton)
        .accessibilityIdentifier("quickActions." + item.id)
        .modifier(PillTourTarget(id: item.id))
    }

    private var morePill: some View {
        Button {
            withAnimation(reduceMotion ? .easeOut(duration: 0.18) : .spring(response: 0.38, dampingFraction: 0.8)) {
                expanded = true
            }
        } label: {
            pillLabel(title: "More") {
                icon("ellipsis", tint: Color(red: 0.45, green: 0.47, blue: 0.55))
            }
        }
        .buttonStyle(PillPressStyle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("More actions")
        .accessibilityHint("Shows \(rest.map(\.title).joined(separator: ", "))" as String)
        .accessibilityAddTraits(.isButton)
        .accessibilityIdentifier("quickActions.more")
    }

    private func icon(_ symbol: String, tint: Color) -> some View {
        Image(systemName: symbol)
            .font(.system(size: 15, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: 34, height: 34)
            .background {
                Circle().fill(LinearGradient(colors: [tint.opacity(0.92), tint],
                                             startPoint: .top, endPoint: .bottom))
                    .overlay(Circle().strokeBorder(Color.white.opacity(0.28), lineWidth: 0.6))
            }
            .accessibilityHidden(true)
    }

    /// A frosted capsule: the label, then the icon at the trailing end, so every
    /// pill's icon sits in one column under Nourlo.
    private func pillLabel<Icon: View>(title: String, @ViewBuilder icon: () -> Icon) -> some View {
        let dark = colorScheme == .dark
        return HStack(spacing: 10) {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Color.labelPrimary)
                .lineLimit(2)
                .multilineTextAlignment(.trailing)
                .fixedSize(horizontal: false, vertical: true)
            icon()
        }
        .padding(.leading, 18)
        .padding(.trailing, 6)
        .padding(.vertical, 6)
        .frame(minHeight: 46)
        .background {
            Capsule(style: .continuous)
                .fill(.regularMaterial)
                .overlay(Capsule(style: .continuous).fill(Color.white.opacity(dark ? 0.06 : 0.45)))
                .overlay(Capsule(style: .continuous)
                    .strokeBorder(LinearGradient(colors: [Color.white.opacity(dark ? 0.22 : 0.9), Color.white.opacity(dark ? 0.06 : 0.35)],
                                                 startPoint: .top, endPoint: .bottom), lineWidth: 0.8))
                .shadow(color: .black.opacity(dark ? 0.4 : 0.13), radius: 14, x: 0, y: 6)
                .shadow(color: .black.opacity(dark ? 0.25 : 0.05), radius: 2, x: 0, y: 1)
        }
        .contentShape(Capsule(style: .continuous))
        .dynamicTypeSize(...DynamicTypeSize.accessibility2)
    }

    /// Each action its own colour, like app icons, so the pills read at a glance.
    static func tint(_ id: String) -> Color {
        switch id {
        case "chat": return Color.dullPink
        case "voice": return Color(red: 0.36, green: 0.42, blue: 0.95)
        case MealioQuickAction.logFood.rawValue: return Color(red: 0.96, green: 0.55, blue: 0.24)
        case "mealPhoto": return Color(red: 0.55, green: 0.40, blue: 0.92)
        case "addRecipe": return Color(red: 0.16, green: 0.66, blue: 0.62)
        case "stock": return Color(red: 0.62, green: 0.45, blue: 0.30)
        case MealioQuickAction.cart.rawValue: return Color(red: 0.23, green: 0.52, blue: 0.95)
        case MealioQuickAction.groceries.rawValue: return Color(red: 0.24, green: 0.68, blue: 0.40)
        case MealioQuickAction.meals.rawValue: return Color(red: 0.93, green: 0.42, blue: 0.48)
        case MealioQuickAction.train.rawValue: return Color(red: 0.90, green: 0.30, blue: 0.30)
        case "tour": return Color(red: 0.96, green: 0.68, blue: 0.18)
        default: return Color.gray
        }
    }

    // MARK: Close badge on Nourlo

    /// The small × that appears on Nourlo while the pills are out.
    private var closeBadge: some View {
        Button { dismiss() } label: {
            Image(systemName: "xmark")
                .font(.system(size: 9, weight: .heavy))
                .foregroundStyle(Color.surface)
                .frame(width: 20, height: 20)
                .background(Circle().fill(Color.labelPrimary))
                .overlay(Circle().strokeBorder(Color.surface, lineWidth: 1.5))
                .shadow(color: .black.opacity(0.2), radius: 3, x: 0, y: 1)
                .frame(width: 36, height: 36)
                .contentShape(Circle())
        }
        .buttonStyle(PillPressStyle())
        .rotationEffect(.degrees(shown || reduceMotion ? 0 : -90))
        .scaleEffect(shown || reduceMotion ? 1 : 0.2)
        .opacity(shown ? 1 : 0)
        .animation(reduceMotion ? .easeOut(duration: 0.18) : .spring(response: 0.36, dampingFraction: 0.65), value: shown)
        .accessibilityLabel("Close quick actions")
        .accessibilityIdentifier("quickActions.done")
    }

    // MARK: Actions

    private var closeDuration: Double {
        reduceMotion ? 0.18 : 0.2 + Double(max(head.count, 1)) * 0.02
    }

    private func dismiss(then action: (() -> Void)? = nil) {
        guard !closing else { return }
        closing = true
        shown = false
        DispatchQueue.main.asyncAfter(deadline: .now() + closeDuration) {
            center.didClose()
            action?()
        }
    }

    private func pick(_ choice: Choice) {
        // A sheet starts sliding up as the last pills fold away.
        guard !closing else { return }
        closing = true
        shown = false
        DispatchQueue.main.asyncAfter(deadline: .now() + min(closeDuration, 0.16)) {
            center.didClose()
            choose(choice)
        }
    }
}

/// The pills spring down out of Nourlo one after another, and fold back up into
/// it the last one first. Reduce Motion: a fade.
private struct Cascade: ViewModifier {
    let shown: Bool
    let index: Int
    let count: Int
    let reduceMotion: Bool

    func body(content: Content) -> some View {
        let up = -CGFloat(index + 1) * 40
        return content
            .opacity(shown ? 1 : 0)
            .scaleEffect(shown || reduceMotion ? 1 : 0.45, anchor: .topTrailing)
            .offset(y: shown || reduceMotion ? 0 : up)
            .blur(radius: shown || reduceMotion ? 0 : 3)
            .animation(animation, value: shown)
            .allowsHitTesting(shown)
    }

    private var animation: Animation {
        if reduceMotion { return .easeOut(duration: 0.18) }
        return shown
            ? .spring(response: 0.46, dampingFraction: 0.72).delay(0.03 + Double(index) * 0.035)
            : .spring(response: 0.26, dampingFraction: 0.95).delay(Double(max(count - 1 - index, 0)) * 0.018)
    }
}

/// The pill tiles the tour points at.
private struct PillTourTarget: ViewModifier {
    let id: String
    func body(content: Content) -> some View {
        switch id {
        case "chat": content.tourTarget(.qaChat)
        case "voice": content.tourTarget(.qaVoice)
        case "mealPhoto": content.tourTarget(.qaPhoto)
        case "addRecipe": content.tourTarget(.qaRecipe)
        case "tour": content.tourTarget(.qaTour)
        default: content
        }
    }
}

private struct PillPressStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.94 : 1)
            .brightness(configuration.isPressed ? -0.03 : 0)
            .animation(reduceMotion ? nil : .spring(response: 0.22, dampingFraction: 0.7), value: configuration.isPressed)
    }
}

/// The whole screen with a round hole, for even-odd hit testing.
struct HoleShape: Shape {
    var hole: CGRect
    func path(in rect: CGRect) -> Path {
        var path = Path(rect.insetBy(dx: -400, dy: -400))
        path.addEllipse(in: hole)
        return path
    }
}
