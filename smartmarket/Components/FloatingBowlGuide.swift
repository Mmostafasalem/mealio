import SwiftUI

enum BowlPathway: String, Identifiable {
    case logFood, groceries, meals, shop, profile, chat
    var id: String { rawValue }
}

/// A local companion, independent of accounts and model availability.
/// The panel occupies only its own hit area; navigation remains reachable.
/// The bowl can be picked up and thrown anywhere above the tab bar; it lands and
/// walks to the nearest spot on the left or right edge (see `BowlGuideMover`).
struct FloatingBowlGuide: View {
    @Binding var selectedTab: Int
    var availableHeight: CGFloat = 640
    /// True while a sheet or notice is up; the bowl glances toward it as it appears.
    var attention: Bool = false
    let choose: (BowlPathway) -> Void
    @AppStorage("bowlGuideIntroduced_v2") private var introduced = false
    @AppStorage("bowlGuideLeading_v2") private var leading = false
    /// Resting height along the side: 0 top … 1 bottom (just above the tab bar).
    @AppStorage("bowlGuideRestY_v3") private var restFraction: Double = 1
    @AppStorage("bowlGuideVisible_v2") private var visible = true
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var expanded = false
    @State private var tourStep: Int?
    @State private var celebrating = false
    @State private var celebration: UUID?
    @State private var mover = BowlGuideMover(rig: MascotRig())
    @State private var carrying = false
    @State private var lastCarryEnd = Date.distantPast
    @GestureState private var carryGesture = false
    @State private var pickups = 0
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
        if visible {
            GeometryReader { geometry in
                ZStack(alignment: .topLeading) {
                    // At accessibility text sizes the guide opens as a sheet instead
                    // (see `.sheet` below): the small floating panel can't hold it.
                    if expanded && !typeSize.isAccessibilitySize {
                        VStack(alignment: leading ? .leading : .trailing, spacing: Spacing.sm) {
                            panel
                            Color.clear.frame(width: Self.slot, height: Self.slot).accessibilityHidden(true)
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: leading ? .bottomLeading : .bottomTrailing)
                        .padding(.horizontal, Spacing.lg)
                        .padding(.bottom, Spacing.sm)
                        .transition(reduceMotion ? .opacity : .scale(scale: 0.97, anchor: leading ? .bottomLeading : .bottomTrailing).combined(with: .opacity))
                    }
                    mascot
                        .offset(x: mover.position.x - Self.slot / 2, y: mover.position.y - Self.slot / 2)
                        .opacity(mover.isPlaced ? 1 : 0)
                }
                .frame(width: geometry.size.width, height: geometry.size.height, alignment: .topLeading)
                .coordinateSpace(name: Self.space)
                .onAppear { configure(geometry.size) }
                .onChange(of: geometry.size) { _, size in configure(size) }
            }
            .sheet(isPresented: Binding(
                get: { expanded && typeSize.isAccessibilitySize },
                set: { if !$0 && expanded { close() } }
            )) {
                largeTextPanel
            }
            .animation(reduceMotion ? nil : .snappyValue, value: expanded)
            .onChange(of: FoodLogStore.shared.entries.count) { old, new in
                if new > old { celebration = UUID() }
            }
            .onChange(of: expanded) { _, open in
                // Open: dock at the bottom of its side under the panel, looking up at it.
                mover.settle(leading: leading, fraction: open ? 1 : restFraction, remember: false)
                mover.rig.look(at: open ? CGPoint(x: leading ? 0.5 : -0.5, y: -1) : nil)
            }
            .onChange(of: attention) { _, on in if on { glanceAtNotice() } }
            .task(id: celebration) {
                guard celebration != nil else { return }
                celebrating = true
                do { try await Task.sleep(for: .seconds(1.6)) }
                catch { celebrating = false; return }
                celebrating = false
            }
            .sensoryFeedback(.impact(weight: .light), trigger: pickups)
            .sensoryFeedback(.impact(flexibility: .soft, intensity: 0.6), trigger: mover.landings)
            .onDisappear {
                celebrating = false
                mover.stop()
            }
        }
    }

    /// The bowl's button slot: 52 pt character plus the 12 pt touch padding on each side.
    private static let slot: CGFloat = 76
    private static let space = "bowlGuideRegion"
    private static let panelTop = "bowlGuidePanelTop"

    private var mood: MascotMood {
        expanded ? .help : (celebrating ? .celebrate : (AppState.shared.isGeneratingMealPlan ? .thinking : .idle))
    }

    private var mascot: some View {
        MascotGuideView(mood: mood, size: 52, onTap: tapMascot, rig: mover.rig)
            // Just the character, no disc: a soft shadow that follows its
            // silhouette keeps it legible over any content.
            .shadow(color: .black.opacity(0.18), radius: 6, x: 0, y: 3)
            .frame(width: Self.slot, height: Self.slot)
            .overlay(alignment: leading ? .leading : .trailing) {
                if !introduced && !expanded && !typeSize.isAccessibilitySize && !mover.isMoving {
                    invitation
                        .fixedSize()
                        .alignmentGuide(leading ? .leading : .trailing) { d in
                            leading ? d[.leading] - (Self.slot + Spacing.sm) : d[.trailing] + Self.slot + Spacing.sm
                        }
                }
            }
            .accessibilityHint(expanded ? "Closes your local guide." : "Opens helpful next steps and a short tour. No AI request is sent.")
            .accessibilityAction(named: expanded ? "Close guide" : "Open guide") { toggle() }
            .accessibilityAction(named: "Take a quick tour", startTour)
            .accessibilityAction(named: "Move to other side", moveToOtherSide)
            .accessibilityAction(named: "Hide") { hide() }
            .contextMenu {
                Button("Take a quick tour", systemImage: "sparkles", action: startTour)
                Button(leading ? "Move to right" : "Move to left", systemImage: "arrow.left.arrow.right", action: moveToOtherSide)
                Button("Hide guide", systemImage: "eye.slash") { hide() }
            }
            .simultaneousGesture(carry)
            .onChange(of: carryGesture) { _, active in
                if !active { endCarry(velocity: .zero) }
            }
    }

    /// Press and move to pick the bowl up (no long press); a plain tap still opens the guide.
    private var carry: some Gesture {
        DragGesture(minimumDistance: 8, coordinateSpace: .named(Self.space))
            .onChanged { value in
                if !carrying {
                    carrying = true
                    if expanded { close() }
                    mover.grab(at: value.startLocation)
                    pickups += 1
                }
                mover.drag(to: value.location, velocity: value.velocity)
            }
            .updating($carryGesture) { _, active, _ in active = true }
            .onEnded { value in
                endCarry(velocity: value.velocity)
            }
    }

    private func configure(_ size: CGSize) {
        mover.onRest = { side, fraction in
            leading = side
            restFraction = fraction
        }
        mover.configure(region: CGRect(origin: .zero, size: size), radius: Self.slot / 2,
                        inset: CGSize(width: Spacing.lg, height: Spacing.sm),
                        leading: leading, fraction: expanded ? 1 : restFraction)
    }

    /// Release (or a cancelled gesture, which never reaches `onEnded`).
    private func endCarry(velocity: CGSize) {
        guard carrying else { return }
        carrying = false
        lastCarryEnd = Date()
        mover.release(velocity: velocity, reduceMotion: reduceMotion)
    }

    private func tapMascot() {
        // The button's own tap fires on the touch-up that ends a carry; ignore it.
        guard !carrying, Date().timeIntervalSince(lastCarryEnd) > 0.35 else { return }
        mover.rig.react(.tap)
        toggle()
    }

    private func moveToOtherSide() {
        leading.toggle()
        mover.settle(leading: leading, fraction: expanded ? 1 : restFraction, remember: !expanded)
    }

    private func hide() {
        close()
        visible = false
    }

    /// A sheet or notice just appeared: look toward it, then back.
    private func glanceAtNotice() {
        mover.rig.look(at: CGPoint(x: leading ? 0.7 : -0.7, y: -0.7))
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(1.4))
            if !expanded && !carrying { mover.rig.look(at: nil) }
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
