import SwiftUI

// MARK: - Quick actions menu (floating, grows out of the bowl button)
//
// Owner feedback on 28 Nov 2026: the sheet version was "not looking nice and not good
// transitions; it needs to be more seamless and appealing". So it is no longer a sheet:
// the screen dims and blurs, a compact card grows out of the bowl button (anchored at
// its corner), the button turns into a close button, and the tiles arrive one after
// another. Tap outside, the close button, or swipe the card down to close.
//
// Content: the two most useful actions as short featured tiles (chat and voice when
// offered), the rest as coloured app-style icons in a four-column grid, and Profile as
// the avatar in the header, so no tile sits alone on a row.

struct QuickActionsMenu: View {
    let features: Set<AppFeature>
    /// Where the bowl button is: distance from the bottom and right edges, and its size.
    let buttonBottom: CGFloat
    let buttonTrailing: CGFloat
    let buttonDiameter: CGFloat
    let close: () -> Void
    let choose: (QuickActionsPanel.Choice) -> Void

    @State private var shown = false
    @State private var drag: CGFloat = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.colorScheme) private var colorScheme

    private var items: [QuickActionsPanel.Item] { QuickActionsPanel.items(for: features) }
    private var profile: QuickActionsPanel.Item? { items.first { $0.choice == .action(.profile) } }
    private var featured: [QuickActionsPanel.Item] {
        Array(items.filter { $0.choice != .action(.profile) }.prefix(2))
    }
    private var grid: [QuickActionsPanel.Item] {
        let big = Set(featured.map(\.id))
        return items.filter { !big.contains($0.id) && $0.choice != .action(.profile) }
    }
    private var columns: Int { typeSize.isAccessibilitySize ? 2 : typeSize >= .xxLarge ? 3 : 4 }

    private var openSpring: Animation { reduceMotion ? .easeOut(duration: 0.18) : .spring(response: 0.42, dampingFraction: 0.8) }

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .bottomTrailing) {
                // Dimmed, blurred page behind; a tap anywhere on it closes the menu.
                Rectangle()
                    .fill(.ultraThinMaterial)
                    .overlay(Color.black.opacity(colorScheme == .dark ? 0.35 : 0.18))
                    .opacity(shown ? 1 : 0)
                    .ignoresSafeArea()
                    .onTapGesture { dismiss() }
                    .accessibilityLabel("Close quick actions")
                    .accessibilityAddTraits(.isButton)

                card(width: min(geo.size.width - 24, 420))
                    .padding(.trailing, 12)
                    .padding(.bottom, buttonBottom + buttonDiameter + 14)
                    .offset(y: max(drag, 0))
                    .gesture(DragGesture(minimumDistance: 8)
                        .onChanged { drag = $0.translation.height }
                        .onEnded { value in
                            if value.translation.height > 70 || value.predictedEndTranslation.height > 160 { dismiss() }
                            else { withAnimation(openSpring) { drag = 0 } }
                        })
                    // Grows out of the button's corner.
                    .scaleEffect(shown || reduceMotion ? 1 : 0.25, anchor: .bottomTrailing)
                    .opacity(shown ? 1 : 0)

                closeButton
                    .padding(.trailing, buttonTrailing)
                    .padding(.bottom, buttonBottom)
            }
            .ignoresSafeArea(.container, edges: .bottom)
        }
        .onAppear { withAnimation(openSpring) { shown = true } }
        .accessibilityAddTraits(.isModal)
    }

    // MARK: Card

    private func card(width: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            header
            featuredRow
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8, alignment: .top), count: columns),
                      spacing: 14) {
                ForEach(Array(grid.enumerated()), id: \.element.id) { index, item in
                    iconTile(item)
                        .modifier(Arrive(shown: shown, index: index + 2, reduceMotion: reduceMotion))
                }
            }
            .padding(.top, 2)
        }
        .padding(16)
        .frame(width: width)
        .background {
            RoundedRectangle(cornerRadius: 30, style: .continuous)
                .fill(.regularMaterial)
                .overlay(RoundedRectangle(cornerRadius: 30, style: .continuous)
                    .fill(LinearGradient(colors: [Color.dullPink.opacity(colorScheme == .dark ? 0.16 : 0.10), .clear],
                                         startPoint: .top, endPoint: .bottom)))
                .overlay(RoundedRectangle(cornerRadius: 30, style: .continuous)
                    .strokeBorder(Color.white.opacity(colorScheme == .dark ? 0.12 : 0.6), lineWidth: 1))
                .shadow(color: .black.opacity(colorScheme == .dark ? 0.45 : 0.16), radius: 30, x: 0, y: 14)
        }
    }

    private var header: some View {
        HStack(spacing: 10) {
            Text("Quick actions")
                .font(.headline)
                .foregroundStyle(Color.labelPrimary)
                .accessibilityAddTraits(.isHeader)
            Spacer(minLength: 8)
            if let profile {
                Button { pick(profile.choice) } label: {
                    HStack(spacing: 6) {
                        ProfileAvatar(size: 26)
                        Text("Profile").font(.subheadline.weight(.semibold)).foregroundStyle(Color.labelPrimary)
                    }
                    .padding(.leading, 4).padding(.trailing, 12).padding(.vertical, 4)
                    .background(Color.surfaceSecondary.opacity(0.8), in: Capsule())
                    .frame(minHeight: 44)
                    .contentShape(Capsule())
                }
                .buttonStyle(ScalePressStyle())
                .accessibilityLabel("Profile")
                .accessibilityIdentifier("quickActions." + profile.id)
            }
            Button { dismiss() } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(Color.labelSecondary)
                    .frame(width: 32, height: 32)
                    .background(Color.surfaceSecondary.opacity(0.8), in: Circle())
                    .frame(width: 44, height: 44)
                    .contentShape(Circle())
            }
            .buttonStyle(ScalePressStyle())
            .accessibilityLabel("Done")
            .accessibilityIdentifier("quickActions.done")
        }
        .modifier(Arrive(shown: shown, index: 0, reduceMotion: reduceMotion))
    }

    // MARK: Featured (chat, voice)

    @ViewBuilder private var featuredRow: some View {
        let layout = typeSize.isAccessibilitySize ? AnyLayout(VStackLayout(spacing: 10)) : AnyLayout(HStackLayout(spacing: 10))
        layout {
            ForEach(Array(featured.enumerated()), id: \.element.id) { index, item in
                featuredTile(item, primary: index == 0)
                    .modifier(Arrive(shown: shown, index: index + 1, reduceMotion: reduceMotion))
            }
        }
    }

    private func featuredTile(_ item: QuickActionsPanel.Item, primary: Bool) -> some View {
        let ink: Color = primary ? Color.onAccent : Color.labelPrimary
        return Button { pick(item.choice) } label: {
            HStack(spacing: 10) {
                Image(systemName: item.symbol)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(primary ? Color.onAccent : Color.dullPink)
                    .frame(width: 38, height: 38)
                    .background((primary ? Color.white.opacity(0.28) : Color.dullPink.opacity(0.16)), in: Circle())
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 1) {
                    Text(item.title)
                        .font(.subheadline.weight(.bold))
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(Self.shortDetail(item))
                        .font(.caption2)
                        .opacity(0.75)
                        .lineLimit(1)
                }
                .foregroundStyle(ink)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 12)
            .frame(maxWidth: .infinity, minHeight: 66, alignment: .leading)
            .background {
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(primary
                          ? AnyShapeStyle(LinearGradient(colors: [Color.dullPink, Color.progress],
                                                         startPoint: .topLeading, endPoint: .bottomTrailing))
                          : AnyShapeStyle(Color.surface.opacity(colorScheme == .dark ? 0.55 : 0.85)))
            }
            .contentShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        }
        .buttonStyle(ScalePressStyle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(item.title)
        .accessibilityHint(item.detail)
        .accessibilityAddTraits(.isButton)
        .accessibilityIdentifier("quickActions." + item.id)
    }

    // MARK: Icon grid

    private func iconTile(_ item: QuickActionsPanel.Item) -> some View {
        Button { pick(item.choice) } label: {
            VStack(spacing: 6) {
                Image(systemName: item.symbol)
                    .font(.system(size: 21, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 54, height: 54)
                    .background(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .fill(LinearGradient(colors: [Self.tint(item.id), Self.tint(item.id).opacity(0.78)],
                                                 startPoint: .top, endPoint: .bottom))
                            .shadow(color: Self.tint(item.id).opacity(0.35), radius: 6, x: 0, y: 3)
                    )
                    .accessibilityHidden(true)
                Text(item.title)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(Color.labelPrimary)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .minimumScaleFactor(0.85)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(ScalePressStyle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(item.title)
        .accessibilityAddTraits(.isButton)
        .accessibilityIdentifier("quickActions." + item.id)
    }

    /// A few words under a featured tile's title (the full detail is the VoiceOver hint).
    static func shortDetail(_ item: QuickActionsPanel.Item) -> String {
        switch item.id {
        case "chat": return "Ask anything"
        case "voice": return "Just say it"
        case MealioQuickAction.logFood.rawValue: return "What you ate"
        default: return item.detail
        }
    }

    /// Each action its own colour, like app icons, so the grid reads at a glance.
    static func tint(_ id: String) -> Color {
        switch id {
        case MealioQuickAction.logFood.rawValue: return Color(red: 0.96, green: 0.55, blue: 0.24)
        case "mealPhoto": return Color(red: 0.55, green: 0.40, blue: 0.92)
        case "addRecipe": return Color(red: 0.16, green: 0.66, blue: 0.62)
        case MealioQuickAction.cart.rawValue: return Color(red: 0.23, green: 0.52, blue: 0.95)
        case MealioQuickAction.groceries.rawValue: return Color(red: 0.24, green: 0.68, blue: 0.40)
        case MealioQuickAction.meals.rawValue: return Color(red: 0.93, green: 0.42, blue: 0.48)
        case "stock": return Color(red: 0.62, green: 0.45, blue: 0.30)
        case MealioQuickAction.train.rawValue: return Color(red: 0.90, green: 0.30, blue: 0.30)
        case "voice": return Color(red: 0.36, green: 0.42, blue: 0.95)
        case "chat": return Color.dullPink
        default: return Color.gray
        }
    }

    // MARK: Close button over the bowl

    /// The bowl button turns into a close button while the menu is open.
    private var closeButton: some View {
        Button { dismiss() } label: {
            Image(systemName: "xmark")
                .font(.system(size: buttonDiameter * 0.32, weight: .bold))
                .foregroundStyle(Color.onAccent)
                .rotationEffect(.degrees(shown || reduceMotion ? 0 : -90))
                .frame(width: buttonDiameter, height: buttonDiameter)
                .background(Circle().fill(Color.dullPink)
                    .shadow(color: Color.dullPink.opacity(0.5), radius: 12, x: 0, y: 6))
                .contentShape(Circle())
        }
        .buttonStyle(ScalePressStyle())
        .scaleEffect(shown || reduceMotion ? 1 : 0.6)
        .opacity(shown ? 1 : 0)
        .accessibilityLabel("Close quick actions")
        .accessibilityIdentifier("quickActions.close")
    }

    // MARK: Actions

    private func dismiss() {
        withAnimation(reduceMotion ? .easeOut(duration: 0.15) : .spring(response: 0.3, dampingFraction: 0.9)) {
            shown = false
            drag = 0
        }
        // Remove the overlay once the card has shrunk back into the button.
        DispatchQueue.main.asyncAfter(deadline: .now() + (reduceMotion ? 0.16 : 0.24)) { close() }
    }

    private func pick(_ choice: QuickActionsPanel.Choice) {
        withAnimation(.easeOut(duration: 0.16)) { shown = false }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.14) {
            close()
            choose(choice)
        }
    }
}

/// Header, featured tiles and icons arrive one after another as the card grows.
private struct Arrive: ViewModifier {
    let shown: Bool
    let index: Int
    let reduceMotion: Bool

    func body(content: Content) -> some View {
        content
            .opacity(shown || reduceMotion ? 1 : 0)
            .offset(y: shown || reduceMotion ? 0 : 10)
            .animation(reduceMotion ? nil : .spring(response: 0.38, dampingFraction: 0.8)
                .delay(0.04 + Double(index) * 0.022), value: shown)
    }
}
