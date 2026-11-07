import SwiftUI

enum BowlPathway: String, Identifiable {
    case logFood, groceries, meals, shop, map, profile, chat
    var id: String { rawValue }
}

/// A local companion, independent of accounts and model availability.
/// The panel occupies only its own hit area; navigation remains reachable.
struct FloatingBowlGuide: View {
    @Binding var selectedTab: Int
    var availableHeight: CGFloat = 640
    let choose: (BowlPathway) -> Void
    @AppStorage("bowlGuideIntroduced_v2") private var introduced = false
    @AppStorage("bowlGuideLeading_v2") private var leading = false
    @AppStorage("bowlGuideVisible_v2") private var visible = true
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var expanded = false
    @State private var tourStep: Int?
    @State private var celebrating = false
    @State private var celebration: UUID?
    @AccessibilityFocusState private var titleFocused: Bool

    private let tour: [(title: String, detail: String, tab: Int, action: BowlPathway, cta: String)] = [
        ("Start with one meal", "Log something you ate. Choose its portion and meal, then your daily totals update here.", 0, .logFood, "Log my first food"),
        ("Build your grocery list", "Pick groceries in Shop, then tick them off in your checklist. Catalog prices are estimates, not retailer offers.", 2, .shop, "Browse groceries"),
        ("Make room for a plan", "Meals brings your suggestions together. Review ingredients and portions before logging. Local suggestions work without AI.", 1, .meals, "Explore my meals")
    ]

    private var title: String {
        if let step = tourStep { return tour[step].title }
        return ["A little help for today", "Find your next meal", "From shelf to checklist", "Find your way there", "Make Mealio yours"][selectedTab]
    }

    private var detail: String {
        if let step = tourStep { return tour[step].detail }
        return [
            "Start small. Log a meal, make a grocery list, or let me show you around.",
            "Review your suggestions and portions. Your grocery checklist is a good place to start planning.",
            "Add what you need, then open your checklist when you shop. Prices here are estimates.",
            "Use the map to explore stores. Check the retailer for opening hours, stock and shelf prices.",
            "Your goals, privacy choices and optional AI controls live here. You can hide me here, too."
        ][selectedTab]
    }

    var body: some View {
        if visible {
            VStack(alignment: leading ? .leading : .trailing, spacing: Spacing.sm) {
                if expanded {
                    panel
                        .transition(reduceMotion ? .opacity : .scale(scale: 0.97, anchor: leading ? .bottomLeading : .bottomTrailing).combined(with: .opacity))
                }
                HStack(spacing: Spacing.sm) {
                    if !introduced && !expanded && !typeSize.isAccessibilitySize && !leading {
                        invitation
                    }
                    MascotGuideView(mood: expanded ? .help : (celebrating ? .celebrate : (AppState.shared.isGeneratingMealPlan ? .thinking : .idle)), size: 52, onTap: toggle)
                        .background(Color.surfaceElevated, in: Circle())
                        .overlay(Circle().strokeBorder(Color.hairline.opacity(0.5), lineWidth: 0.7))
                        .elevation(Elevation.high)
                        .accessibilityHint(expanded ? "Closes your local guide." : "Opens helpful next steps and a short tour. No AI request is sent.")
                        .accessibilityAction(named: "Take a quick tour", startTour)
                        .contextMenu {
                            Button("Take a quick tour", systemImage: "sparkles", action: startTour)
                            Button(leading ? "Move to right" : "Move to left", systemImage: "arrow.left.arrow.right") { leading.toggle() }
                            Button("Hide guide", systemImage: "eye.slash") { close(); visible = false }
                        }
                    if !introduced && !expanded && !typeSize.isAccessibilitySize && leading { invitation }
                }
            }
            .frame(maxWidth: .infinity, alignment: leading ? .leading : .trailing)
            .padding(.horizontal, Spacing.lg)
            .padding(.bottom, Spacing.sm)
            .animation(reduceMotion ? nil : .snappyValue, value: expanded)
            .animation(reduceMotion ? nil : .snappyValue, value: leading)
            .onChange(of: FoodLogStore.shared.entries.count) { old, new in
                if new > old { celebration = UUID() }
            }
            .task(id: celebration) {
                guard celebration != nil else { return }
                celebrating = true
                do { try await Task.sleep(for: .seconds(1.6)) }
                catch { celebrating = false; return }
                celebrating = false
            }
            .onDisappear { celebrating = false }
        }
    }

    private var invitation: some View {
        Button(action: toggle) {
            Text("Need a little direction?")
                .font(.footnote.weight(.medium))
                .foregroundStyle(Color.labelPrimary)
                .padding(.horizontal, Spacing.lg)
                .frame(minHeight: 44)
                .background(Color.surfaceElevated, in: Capsule())
                .overlay(Capsule().strokeBorder(Color.hairline.opacity(0.5), lineWidth: 0.7))
        }
        .buttonStyle(ScalePressStyle())
        .accessibilityIdentifier("guide.invitation")
    }

    private var panel: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Label(tourStep == nil ? "YOUR BOWL GUIDE" : "A QUICK LOOK AROUND", systemImage: "sparkles")
                    .font(.caption2.weight(.semibold)).tracking(1)
                    .dynamicTypeSize(...DynamicTypeSize.xxxLarge).lineLimit(1)
                    .foregroundStyle(Color.labelSecondary)
                Spacer(minLength: Spacing.sm)
                Button(action: close) {
                    Image(systemName: "xmark").font(.footnote.weight(.semibold))
                        .dynamicTypeSize(...DynamicTypeSize.xxxLarge).frame(width: 44, height: 44)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Close guide")
                .accessibilityIdentifier("guide.close")
            }

            ScrollView { panelContent }
                .scrollBounceBehavior(.basedOnSize)
                .frame(maxHeight: max(60, min(typeSize.isAccessibilitySize ? 330 : (tourStep == nil ? 380 : 270), availableHeight - 144)))
        }
        .padding(.horizontal, Spacing.lg)
        .padding(.bottom, Spacing.sm)
        .foregroundStyle(Color.labelPrimary)
        .tint(Color.brandPrimary)
        .frame(maxWidth: 360)
        .background(Color.surfaceElevated, in: RoundedRectangle(cornerRadius: Radius.sheet, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Radius.sheet, style: .continuous).strokeBorder(Color.hairline.opacity(0.5), lineWidth: 0.7))
        .elevation(Elevation.high)
    }

    private var panelContent: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            if let step = tourStep {
                HStack(spacing: Spacing.xs) {
                    ForEach(0..<3) { index in
                        Capsule().fill(index <= step ? Color.brandPrimary : Color.surfaceSecondary)
                            .frame(height: 3)
                    }
                    Text("\(step + 1) / 3").font(.caption.monospacedDigit()).padding(.leading, Spacing.xs)
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Tour step \(step + 1) of 3")
            }
            Text(title).font(.title2.weight(.semibold))
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
                .accessibilityFocused($titleFocused)
                .accessibilityIdentifier("guide.title")
            Text(detail).font(.subheadline).foregroundStyle(Color.labelSecondary)
                .fixedSize(horizontal: false, vertical: true)

            if let step = tourStep {
                PrimaryButton(title: tour[step].cta) { route(tour[step].action) }
                    .accessibilityIdentifier("guide.tryStep")
                HStack {
                    Button("Skip tour", action: close).frame(minHeight: 44)
                        .accessibilityIdentifier("guide.skip")
                    Spacer()
                    Button(step == 2 ? "Finish" : "Next") {
                        if step == 2 { close() }
                        else { tourStep = step + 1; selectedTab = tour[step + 1].tab; titleFocused = true }
                    }
                    .fontWeight(.semibold).frame(minHeight: 44)
                    .accessibilityIdentifier("guide.next")
                }
                .font(.subheadline)
            } else {
                pathway("Log food", subtitle: "A small start for today", symbol: "plus", action: .logFood)
                pathway("Grocery checklist", subtitle: "Keep your shopping together", symbol: "checklist", action: .groceries)
                pathway("Explore meals", subtitle: "Suggestions, ingredients and portions", symbol: "fork.knife", action: .meals)
                Divider().overlay(Color.hairline.opacity(0.3))
                HStack {
                    Button("Quick tour", action: startTour).fontWeight(.semibold)
                        .accessibilityIdentifier("guide.tour")
                    Spacer()
                    Button("AI chat") { route(.chat) }
                        .accessibilityIdentifier("guide.chat")
                }
                .font(.footnote).frame(minHeight: 44)
                Text("These shortcuts work without AI.")
                    .font(.caption).foregroundStyle(Color.labelSecondary)
            }
        }
        .padding(.bottom, Spacing.sm)
    }

    private func pathway(_ title: String, subtitle: String, symbol: String, action: BowlPathway) -> some View {
        Button { route(action) } label: {
            HStack(spacing: Spacing.md) {
                Image(systemName: symbol).font(.body.weight(.medium))
                    .frame(width: 40, height: 40)
                    .background(Color.brandLight.opacity(0.5), in: RoundedRectangle(cornerRadius: Radius.chip, style: .continuous))
                VStack(alignment: .leading, spacing: Spacing.xs) {
                    Text(title).font(.subheadline.weight(.semibold))
                    Text(subtitle).font(.caption).foregroundStyle(Color.labelSecondary)
                }
                Spacer(minLength: 0)
                Image(systemName: "arrow.up.right").font(.caption.weight(.semibold))
            }
            .frame(maxWidth: .infinity, minHeight: 48, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(ScalePressStyle())
        .accessibilityIdentifier("guide.path.\(action.rawValue)")
    }

    private func toggle() {
        introduced = true
        expanded.toggle()
        if !expanded { tourStep = nil }
        titleFocused = expanded
    }

    private func startTour() {
        introduced = true; expanded = true; tourStep = 0; selectedTab = 0; titleFocused = true
    }

    private func close() {
        introduced = true; expanded = false; tourStep = nil; titleFocused = false
    }

    private func route(_ action: BowlPathway) {
        close()
        choose(action)
    }
}
