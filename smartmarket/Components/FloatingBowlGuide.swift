import SwiftUI

enum BowlPathway: String, Identifiable {
    case logFood, groceries, meals, shop, profile, chat
    var id: String { rawValue }
}

/// The bowl's guide panel: local next steps and a short tour, independent of
/// accounts and model availability. The bowl itself sits in Home's header
/// (`HeaderBowl`); tapping it asks this layer to open. The panel occupies only
/// its own hit area, so the screen behind stays usable.
struct FloatingBowlGuide: View {
    @Binding var selectedTab: Int
    var availableHeight: CGFloat = 640
    let choose: (BowlPathway) -> Void
    @AppStorage("bowlGuideIntroduced_v2") private var introduced = false
    @AppStorage("bowlGuideVisible_v2") private var visible = true
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var expanded = false
    @State private var tourStep: Int?
    @AccessibilityFocusState private var titleFocused: Bool
    /// The tour's titles live on sliding pages, one per step.
    @AccessibilityFocusState private var tourTitleFocus: Int?

    private let tour: [(title: String, detail: String, tab: Int, action: BowlPathway, cta: String)] = [
        ("Start with one meal", "Log something you ate. Choose its portion and meal, then your daily totals update here.", 0, .logFood, "Log my first food"),
        ("Build your grocery list", "Pick groceries in Shop, then tick them off in your checklist. Catalog prices are estimates, not retailer offers.", 2, .shop, "Browse groceries"),
        ("Make room for a plan", "Meals brings your suggestions together. Review ingredients and portions before logging. Local suggestions work without AI.", 1, .meals, "Explore my meals")
    ]

    private var title: String {
        if let step = tourStep { return tour[step].title }
        return ["A little help for today", "Find your next meal", "From shelf to checklist", "Move a little today"][selectedTab]
    }

    private var detail: String {
        if let step = tourStep { return tour[step].detail }
        return [
            "Start small. Log a meal, make a grocery list, or let me show you around.",
            "Review your suggestions and portions. Your grocery checklist is a good place to start planning.",
            "Add what you need, then open your checklist when you shop. Prices here are estimates.",
            "Pick a type and a length, then build a workout. Save the ones you like and tick them off when done."
        ][selectedTab]
    }

    var body: some View {
        ZStack(alignment: .topTrailing) {
            // At accessibility text sizes the guide opens as a sheet instead
            // (see `.sheet` below): the small panel can't hold it.
            if visible && expanded && !typeSize.isAccessibilitySize {
                panel
                    .padding(.horizontal, Spacing.lg)
                    // Drops down from under the header row, where the bowl sits.
                    .padding(.top, 76)
                    .transition(reduceMotion ? .opacity : .scale(scale: 0.97, anchor: .topTrailing).combined(with: .opacity))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
        .sheet(isPresented: Binding(
            get: { visible && expanded && typeSize.isAccessibilitySize },
            set: { if !$0 && expanded { close() } }
        )) {
            largeTextPanel
        }
        .animation(reduceMotion ? nil : .snappyValue, value: expanded)
        .onReceive(NotificationCenter.default.publisher(for: .toggleBowlGuide)) { _ in toggle() }
        .onChange(of: visible) { _, shown in if !shown { close() } }
    }

    private static let panelTop = "bowlGuidePanelTop"

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

            // Always open (and change step) at the top, so the first pathway is
            // in view even when large text makes the panel scroll.
            ScrollViewReader { proxy in
                ScrollView {
                    Color.clear.frame(height: 0).id(Self.panelTop)
                    panelContent
                }
                .scrollBounceBehavior(.basedOnSize)
                // Large text keeps growing the content while the panel lays out;
                // anchor to the top so it never opens scrolled down.
                .defaultScrollAnchor(.top)
                .frame(maxHeight: max(60, min(typeSize.isAccessibilitySize ? 330 : (tourStep == nil ? 380 : 270), availableHeight - 144)))
                .task(id: tourStep) {
                    proxy.scrollTo(Self.panelTop, anchor: .top)
                    // Again once the opening transition and text layout have settled.
                    try? await Task.sleep(for: .milliseconds(350))
                    proxy.scrollTo(Self.panelTop, anchor: .top)
                }
            }
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

    /// The guide at accessibility text sizes: a full sheet with native scrolling,
    /// same content, actions and identifiers as the floating panel.
    private var largeTextPanel: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Label(tourStep == nil ? "YOUR BOWL GUIDE" : "A QUICK LOOK AROUND", systemImage: "sparkles")
                    .font(.caption2.weight(.semibold)).tracking(1)
                    .foregroundStyle(Color.labelSecondary)
                Spacer(minLength: Spacing.sm)
                Button(action: close) {
                    Image(systemName: "xmark").font(.footnote.weight(.semibold))
                        .frame(minWidth: 44, minHeight: 44)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Close guide")
                .accessibilityIdentifier("guide.close")
            }
            ScrollView { panelContent.padding(.top, Spacing.sm) }
        }
        .padding(.horizontal, Spacing.lg)
        .padding(.top, Spacing.md)
        .foregroundStyle(Color.labelPrimary)
        .tint(Color.brandPrimary)
        .background(Color.surfaceElevated.ignoresSafeArea())
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
    }

    private var panelContent: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            if let step = tourStep {
                HStack(spacing: Spacing.sm) {
                    PaginationDots(count: tour.count, selection: step,
                                   pageLabel: { "Step \($0 + 1) of \(tour.count): \(tour[$0].title)" },
                                   onSelect: goToStep)
                        .accessibilityElement(children: .contain)
                        .accessibilityLabel("Tour step \(step + 1) of \(tour.count)")
                        .accessibilityIdentifier("guide.dots")
                    Spacer(minLength: 0)
                    Text("\(step + 1) / \(tour.count)").font(.caption.monospacedDigit())
                        .foregroundStyle(Color.labelSecondary)
                        .accessibilityHidden(true)
                }
                PaginationStrip(count: tour.count, selection: step) { i in
                    tourPage(i)
                }
                HStack {
                    Button("Skip tour", action: close).frame(minHeight: 44)
                        .accessibilityIdentifier("guide.skip")
                    Spacer()
                    Button(step == tour.count - 1 ? "Finish" : "Next") {
                        if step == tour.count - 1 { close() }
                        else { goToStep(step + 1) }
                    }
                    .fontWeight(.semibold).frame(minHeight: 44)
                    .accessibilityIdentifier("guide.next")
                }
                .font(.subheadline)
            } else {
                Text(title).font(.title2.weight(.semibold))
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityAddTraits(.isHeader)
                    .accessibilityFocused($titleFocused)
                    .accessibilityIdentifier("guide.title")
                Text(detail).font(.subheadline).foregroundStyle(Color.labelSecondary)
                    .fixedSize(horizontal: false, vertical: true)
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
            }
        }
        .padding(.bottom, Spacing.sm)
    }

    /// One tour step on the sliding strip: title, detail and its try-it button.
    private func tourPage(_ i: Int) -> some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            Text(tour[i].title).font(.title2.weight(.semibold))
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
                .accessibilityFocused($tourTitleFocus, equals: i)
                .accessibilityIdentifier("guide.title")
            Text(tour[i].detail).font(.subheadline).foregroundStyle(Color.labelSecondary)
                .fixedSize(horizontal: false, vertical: true)
            PrimaryButton(title: tour[i].cta) { route(tour[i].action) }
                .accessibilityIdentifier("guide.tryStep")
        }
    }

    /// Jump to a tour step (Next, or a tapped dot).
    private func goToStep(_ i: Int) {
        guard tour.indices.contains(i) else { return }
        tourStep = i
        selectedTab = tour[i].tab
        tourTitleFocus = i
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
        introduced = true; expanded = true; tourStep = 0; selectedTab = tour[0].tab; tourTitleFocus = 0
    }

    private func close() {
        introduced = true; expanded = false; tourStep = nil; titleFocused = false; tourTitleFocus = nil
    }

    private func route(_ action: BowlPathway) {
        close()
        choose(action)
    }
}
