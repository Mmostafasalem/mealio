import SwiftUI

struct MealPlanView: View {
    @Environment(\.scenePhase) private var scenePhase

    @State private var vm = MealPlanViewModel()
    /// One meal open at a time, across every section.
    @State private var expandGroup = ExpandCardGroup()
    /// Last title shown per meal slot, so only titles a new plan changed decode.
    @State private var titleMemory = ScrambleMemory()
    /// Which way the last day change went, so the day slides in from that side.
    @State private var movingForward = true
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage("aiSharingConsent_v1") private var aiSharingConsent = false
    @AppStorage("ownerAISharingConsent_v1") private var ownerAISharingConsent = false

    private var sharingEnabled: Bool {
        OwnerAITestConfiguration.current == nil ? aiSharingConsent : ownerAISharingConsent
    }

    /// Today and the next six days.
    private var days: [Date] {
        let today = Calendar.current.startOfDay(for: Date())
        return (0..<7).compactMap { Calendar.current.date(byAdding: .day, value: $0, to: today) }
    }

    private func plan(forDay offset: Int) -> MealPlan? {
        if offset == 0, let today = vm.todaysPlan { return today }
        guard days.indices.contains(offset) else { return nil }
        return vm.weekPlans.first { Calendar.current.isDate($0.date, inSameDayAs: days[offset]) }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: Spacing.lg) {
                if let message = vm.errorMessage, vm.todaysPlan != nil {
                    Text(message).font(.footnote).foregroundStyle(Color.brandDanger)
                        .padding(.horizontal, Spacing.lg)
                }
                DayStrip(days: days, selected: Binding(get: { vm.selectedDay }, set: select),
                         marker: marker(forDay:))
                    .padding(.horizontal, Spacing.lg)

                if vm.isGenerating && vm.todaysPlan != nil {
                    HStack(spacing: Spacing.sm) {
                        ProgressView().controlSize(.small)
                        Text("Updating plan…").font(.footnote)
                    }
                    .foregroundStyle(Color.labelSecondary)
                    .transition(.opacity)
                }
                MissingFoodsBanner()
                    .padding(.horizontal, Spacing.lg)

                // Old and new day share one slot, so changing day cross-fades in place
                // instead of stacking both and jumping.
                ZStack(alignment: .top) {
                    dayContent(vm.selectedDay)
                        .id(vm.selectedDay)
                        .transition(dayTransition)
                }
                .frame(maxWidth: .infinity)
                .contentShape(Rectangle())
                .simultaneousGesture(daySwipe)
            }
            .padding(.top, Spacing.sm)
            .padding(.bottom, Spacing.xl)
            .animation(reduceMotion ? .reducedFade : .snappyValue, value: vm.isGenerating)
        }
        .background { GrainyGradient().ignoresSafeArea() }
        .navigationTitle("Meal plan")
        .toolbar { ToolbarItem(placement: .topBarTrailing) { NavigationLink("My Stock") { StockView() } } }
        .task {
            if vm.todaysPlan == nil { await vm.loadTodaysPlan() }
            await vm.loadWeekPlans()
        }
        .onReceive(NotificationCenter.default.publisher(for: .mealPlanDidUpdate)) { _ in refreshDay() }
        // A new day (midnight, a time-zone change, or the app opened the next morning):
        // "Today" moves on and the strip starts from the new day.
        .onReceive(NotificationCenter.default.publisher(for: .NSCalendarDayChanged)) { _ in refreshDay() }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.significantTimeChangeNotification)) { _ in refreshDay() }
        .onChange(of: scenePhase) { _, phase in if phase == .active { refreshDay() } }
    }

    private func refreshDay() {
        Task {
            await vm.loadTodaysPlan()
            await vm.loadWeekPlans()
        }
    }

    // MARK: - Changing day

    private func select(_ day: Int) {
        guard day != vm.selectedDay, (0..<7).contains(day) else { return }
        movingForward = day > vm.selectedDay
        // Each day's meals start folded; the open one belonged to the old day.
        expandGroup.show(nil, animated: false)
        withAnimation(reduceMotion ? .reducedFade : .smooth(duration: 0.32)) { vm.selectedDay = day }
    }

    /// A short slide toward the new day with a cross-fade; Reduce Motion: a fade.
    private var dayTransition: AnyTransition {
        guard !reduceMotion else { return .opacity }
        let shift: CGFloat = 36
        return .asymmetric(
            insertion: .offset(x: movingForward ? shift : -shift).combined(with: .opacity),
            removal: .offset(x: movingForward ? -shift : shift).combined(with: .opacity))
    }

    /// A clearly sideways swipe on the meals moves to the next or previous day.
    private var daySwipe: some Gesture {
        DragGesture(minimumDistance: 24)
            .onEnded { value in
                let dx = value.translation.width, dy = value.translation.height
                guard abs(dx) > 70, abs(dx) > abs(dy) * 2 else { return }
                select(vm.selectedDay + (dx < 0 ? 1 : -1))
            }
    }

    private func marker(forDay offset: Int) -> DayStrip.Marker {
        var marker = DayStrip.Marker()
        guard let plan = plan(forDay: offset) else { return marker }
        marker.missing = plan.allMeals.contains { $0.entries.contains { !($0.missing ?? []).isEmpty } }
        marker.logged = offset == 0 && !FoodLogStore.shared.entries.isEmpty
        return marker
    }

    // MARK: - One day

    @ViewBuilder
    private func dayContent(_ offset: Int) -> some View {
        if vm.isGenerating && vm.todaysPlan == nil {
            SkeletonMealPlanContent()
        } else if let errorMessage = vm.errorMessage, vm.todaysPlan == nil {
            ErrorStateView(message: errorMessage) { Task { await vm.loadTodaysPlan() } }
                .padding(.top, Spacing.xxl)
        } else if let plan = plan(forDay: offset) {
            dayPlan(plan, offset: offset)
        } else if vm.todaysPlan != nil {
            EmptyStateView(icon: "calendar", title: "Nothing planned for this day",
                           message: "Regenerate to plan the whole week from your cart and stock.",
                           actionTitle: "Regenerate plan") { Task { await vm.regenerate() } }
                .padding(.top, Spacing.xl)
        } else {
            EmptyStateView(icon: "fork.knife", title: "No meal plan yet",
                           message: "Generate a plan tailored to your goals and favourite foods.",
                           actionTitle: "Generate plan") { Task { await vm.loadTodaysPlan() } }
                .padding(.top, Spacing.xxl)
        }
    }

    private func dayPlan(_ plan: MealPlan, offset: Int) -> some View {
        VStack(spacing: Spacing.md) {
            DaySummary(plan: plan, isToday: offset == 0)
            // New identity per plan content, so a regenerated plan cross-fades in.
            VStack(spacing: Spacing.md) {
                ForEach(Array(plan.allMeals.enumerated()), id: \.offset) { _, meal in
                    MealSectionCard(title: meal.title, sfSymbol: meal.sfSymbol, entries: meal.entries,
                                    dayKey: "d\(offset)", isToday: offset == 0,
                                    expandGroup: expandGroup, titleMemory: titleMemory)
                }
            }
            .id(planGenerationToken(plan))
            .transition(reduceMotion ? .opacity : .opacity.combined(with: .offset(y: 6)))

            if offset == 0 {
                WhyThisPlanCard(notes: plan.agentNotes)
                if !vm.recommendations.isEmpty {
                    RecommendationsSection(items: vm.recommendations,
                                           onAdd: { vm.addToGroceryList([$0]) },
                                           onAddAll: { vm.addToGroceryList($0) })
                }
            }

            // One plan covers the whole week, so this rebuilds every day.
            RegenerateButton(isGenerating: vm.isGenerating) {
                Task { await vm.regenerate() }
            }
            .padding(.top, Spacing.xs)
            if let notice = vm.notice {
                Text(notice).font(.footnote).foregroundStyle(Color.labelSecondary)
                    .multilineTextAlignment(.center)
                    .accessibilityIdentifier("meals.regenerateNotice")
            }

            Text("Calorie & macro values are estimates and may vary by product and preparation.")
                .font(.caption2)
                .foregroundStyle(Color.labelSecondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
        }
        .padding(.horizontal, Spacing.lg)
        .animation(.smoothCard, value: planGenerationToken(plan))
        // A new plan starts with every meal folded.
        .onChange(of: planGenerationToken(plan)) { _, _ in expandGroup.show(nil, animated: false) }
    }

    /// Changes only when the plan's meals change (not on a reload of the same plan).
    private func planGenerationToken(_ plan: MealPlan) -> String {
        plan.allMeals
            .flatMap { meal in meal.entries.map { "\(meal.title):\($0.foodName):\($0.portionG)" } }
            .joined(separator: "|")
    }
}

// MARK: - Day strip

/// Today and the next six days as compact date chips; the chosen day is filled,
/// today is outlined. A pink dot: a meal uses food you don't have yet; a green dot:
/// something is logged today.
private struct DayStrip: View {
    struct Marker { var missing = false; var logged = false }

    let days: [Date]
    @Binding var selected: Int
    let marker: (Int) -> Marker

    @Namespace private var highlight
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Group {
            if typeSize.isAccessibilitySize {
                ScrollView(.horizontal, showsIndicators: false) {
                    chips.padding(.vertical, 2)
                }
            } else {
                chips
            }
        }
        .sensoryFeedback(.selection, trigger: selected)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Days")
    }

    private var chips: some View {
        HStack(spacing: 6) {
            ForEach(Array(days.enumerated()), id: \.offset) { index, day in
                chip(index, day)
            }
        }
    }

    private func chip(_ index: Int, _ day: Date) -> some View {
        let isSelected = index == selected
        let isToday = index == 0
        let mark = marker(index)
        return Button { selected = index } label: {
            VStack(spacing: 3) {
                Text(day, format: .dateTime.weekday(.narrow))
                    .font(.caption2.weight(.semibold))
                    .opacity(isSelected ? 0.8 : 1)
                    .foregroundStyle(isSelected ? Color.surface : Color.labelSecondary)
                Text(day, format: .dateTime.day())
                    .font(.headline.monospacedDigit())
                    .foregroundStyle(isSelected ? Color.surface : Color.labelPrimary)
                HStack(spacing: 3) {
                    Circle().fill(Color.ringProtein).frame(width: 5, height: 5).opacity(mark.logged ? 1 : 0)
                    Circle().fill(Color.progress).frame(width: 5, height: 5).opacity(mark.missing ? 1 : 0)
                }
                .frame(height: 5)
            }
            .frame(maxWidth: typeSize.isAccessibilitySize ? nil : .infinity)
            .frame(minWidth: typeSize.isAccessibilitySize ? 72 : 44, minHeight: 62)
            .padding(.vertical, 4)
            .background {
                if isSelected {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(Color.brandPrimary)
                        .matchedGeometryEffect(id: "selectedDay", in: highlight)
                } else {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(Color.surface.opacity(0.85))
                        .overlay {
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .strokeBorder(isToday ? Color.brandPrimary : Color.hairline, lineWidth: isToday ? 1.5 : 1)
                        }
                }
            }
            .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(ScalePressStyle())
        .animation(reduceMotion ? nil : .snappyValue, value: selected)
        .accessibilityLabel(Text(isToday ? "Today, " : "") + Text(day, format: .dateTime.weekday(.wide).day().month(.wide)))
        .accessibilityValue([mark.logged ? "Food logged" : nil, mark.missing ? "Uses food you don't have yet" : nil]
            .compactMap { $0 }.joined(separator: ", "))
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityHint("Shows this day's meals")
        .accessibilityIdentifier("meals.day.\(index)")
    }
}

// MARK: - Day summary

/// The chosen day in one line: its name and date, and its planned calories and macros.
private struct DaySummary: View {
    let plan: MealPlan
    let isToday: Bool

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: Spacing.sm) {
            VStack(alignment: .leading, spacing: 2) {
                Text(isToday ? "Today" : plan.date.formatted(.dateTime.weekday(.wide)))
                    .font(.title3.weight(.bold))
                    .foregroundStyle(Color.labelPrimary)
                Text(plan.date, format: .dateTime.day().month(.wide))
                    .font(.subheadline)
                    .foregroundStyle(Color.labelSecondary)
            }
            Spacer(minLength: Spacing.sm)
            VStack(alignment: .trailing, spacing: 2) {
                Text("\(plan.totalCalories) kcal" as String)
                    .font(.headline.monospacedDigit())
                    .foregroundStyle(Color.labelPrimary)
                    .contentTransition(.numericText(value: Double(plan.totalCalories)))
                Text("P \(Int(plan.totalProteinG)) · C \(Int(plan.totalCarbsG)) · F \(Int(plan.totalFatG)) g" as String)
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(Color.labelSecondary)
            }
        }
        .padding(.horizontal, Spacing.xs)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
        .accessibilityIdentifier("meals.daySummary")
    }
}

// MARK: - Meal section

private struct MealSectionCard: View {
    let title: String
    let sfSymbol: String
    let entries: [MealEntry]
    /// The day's place in the strip ("d0" today), so each day keeps its own titles.
    let dayKey: String
    let isToday: Bool
    let expandGroup: ExpandCardGroup
    let titleMemory: ScrambleMemory
    @State private var expanded = true
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private var accentColor: Color {
        switch sfSymbol {
        case "sunrise.fill": return .carbsAccent
        case "sun.max.fill": return .calorieAccent
        case "moon.fill":    return .fatAccent
        case "sparkles":     return .proteinAccent
        default:             return .brandPrimary
        }
    }

    var body: some View {
        DisclosureGroup(isExpanded: $expanded) {
            VStack(spacing: 8) {
                if entries.isEmpty {
                    Text("Nothing planned")
                        .font(.caption).foregroundStyle(Color.labelSecondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                ForEach(Array(entries.enumerated()), id: \.element.id) { index, entry in
                    MealEntryRow(entry: entry, slot: title == "Breakfast" ? .breakfast : title == "Lunch" ? .lunch : title == "Dinner" ? .dinner : .snack,
                                 slotKey: "\(dayKey)|\(title)#\(index)", isToday: isToday,
                                 expandGroup: expandGroup, titleMemory: titleMemory)
                }
            }
            .padding(.top, 8)
        } label: {
            let headerLayout = dynamicTypeSize.isAccessibilitySize
                ? AnyLayout(VStackLayout(alignment: .leading, spacing: Spacing.sm))
                : AnyLayout(HStackLayout(spacing: Spacing.md))
            headerLayout {
                Image(systemName: sfSymbol)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(accentColor)
                    .frame(width: 34, height: 34)
                    .background(accentColor.opacity(0.12))
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                Text(title).font(.headline)
                if !dynamicTypeSize.isAccessibilitySize { Spacer() }
                Text("\(entries.reduce(0) { $0 + $1.calories }) kcal" as String)
                    .font(.subheadline).foregroundStyle(Color.labelSecondary)
                    .monospacedDigit()
                    .contentTransition(.numericText())
            }
        }
        .tint(.primary)
        .padding(Spacing.lg)
        .premiumCard(radius: Radius.tile)
    }
}

private struct MealEntryRow: View {
    let entry: MealEntry
    let slot: MealSlot
    /// Stable per slot position ("Lunch#0"), so a new plan's title can decode in.
    let slotKey: String
    /// A later day's meal opens on its recipe; logging is for what you eat today.
    let isToday: Bool
    let expandGroup: ExpandCardGroup
    let titleMemory: ScrambleMemory

    @State private var showReview = false
    @State private var stock = StockStore.shared
    @State private var addedNotice: String?
    @State private var addedTrigger = false
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private var ingredients: [NutritionIngredient] { entry.nutritionIngredients ?? [] }
    private var cardID: String { slotKey + "|" + entry.id }

    private var subtitle: String {
        entry.notes?.isEmpty == false ? entry.notes! : (entry.portionG > 0 ? "\(entry.portionG) g" : "Portion not specified")
    }

    var body: some View {
        ExpandCard(id: cardID, group: expandGroup,
                   accessibilityLabel: "\(entry.foodName), \(subtitle), \(entry.calories) kcal",
                   hint: "Shows ingredients, portions and macros", identifier: "mealPlan.meal") { p in
            header(p)
        } detail: {
            detail
        }
        .sheet(isPresented: $showReview) { MealReviewSheet(entry: entry, slot: slot, startOn: isToday ? nil : .recipe) }
    }

    // MARK: Header

    private func header(_ p: Double) -> some View {
        let q = motionClamp(p, 0, 1)
        let rowLayout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: Spacing.sm))
            : AnyLayout(HStackLayout(spacing: Spacing.md))
        return rowLayout {
            VStack(alignment: .leading, spacing: 2) {
                ScrambleText(text: entry.foodName, key: slotKey, memory: titleMemory,
                             font: .subheadline.weight(.medium))
                    .fixedSize(horizontal: false, vertical: true)
                Text(subtitle)
                    .font(.caption).foregroundStyle(Color.labelSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                if let missing = entry.missing, !missing.isEmpty {
                    Label("Not in your stock: \(missing.joined(separator: ", "))" as String, systemImage: "cart.badge.plus")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(Color.brandAmber)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            // The title rides up a little as the card opens.
            .offset(y: -2 * q)
            if !dynamicTypeSize.isAccessibilitySize { Spacer() }
            VStack(alignment: dynamicTypeSize.isAccessibilitySize ? .leading : .trailing, spacing: 2) {
                Text("\(entry.calories) kcal" as String)
                    .font(.caption).fontWeight(.semibold)
                    .foregroundStyle(Color.labelSecondary).monospacedDigit()
                // The macro summary moves into the details while open.
                Group {
                    // Nothing extra when a meal has only an estimated calorie figure.
                    if entry.macrosAvailable {
                        Text("Calculated from ingredient portions")
                            .font(.caption2).foregroundStyle(Color.labelSecondary)
                        Text("P\(Int(entry.proteinG))  C\(Int(entry.carbsG))  F\(Int(entry.fatG))" as String)
                            .font(.caption2).foregroundStyle(Color.labelTertiary).monospacedDigit()
                    }
                }
                .opacity(1 - q)
            }
            if !dynamicTypeSize.isAccessibilitySize {
                Image(systemName: "chevron.right")
                    .font(.caption2)
                    .foregroundStyle(Color.labelTertiary)
                    .rotationEffect(.degrees(90 * q))
            }
        }
        .padding(.vertical, Spacing.xs)
    }

    // MARK: Details

    private var detail: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            Divider().overlay(Color.hairline)
            if !ingredients.isEmpty {
                VStack(alignment: .leading, spacing: Spacing.sm) {
                    Text("Ingredients").font(.caption.weight(.semibold)).foregroundStyle(Color.labelSecondary)
                    ForEach(ingredients) { ingredient in
                        HStack(alignment: .firstTextBaseline, spacing: Spacing.sm) {
                            Text(ingredient.food.name)
                                .font(.subheadline).foregroundStyle(Color.labelPrimary)
                                .fixedSize(horizontal: false, vertical: true)
                            Spacer(minLength: Spacing.sm)
                            Text("\(ingredient.amount.formatted(.number.grouping(.never))) \(ingredient.food.basis.rawValue)" as String)
                                .font(.caption.weight(.medium)).foregroundStyle(Color.labelSecondary)
                                .monospacedDigit()
                        }
                        .accessibilityElement(children: .combine)
                    }
                }
            }
            macros
            actions
            if let addedNotice {
                Label(addedNotice, systemImage: "checkmark.circle.fill")
                    .font(.caption).foregroundStyle(Color.labelSecondary)
            }
        }
        .padding(.top, Spacing.sm)
        .padding(.bottom, Spacing.xs)
    }

    @ViewBuilder private var macros: some View {
        if entry.macrosAvailable {
            let chips = [("Protein", entry.proteinG), ("Carbs", entry.carbsG), ("Fat", entry.fatG)]
            FlowLayout(spacing: 6) {
                ForEach(chips, id: \.0) { chip in
                    Text("\(chip.0) \(chip.1.formatted(.number.precision(.fractionLength(0...1)))) g" as String)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(Color.labelPrimary)
                        .monospacedDigit()
                        .padding(.horizontal, 10).padding(.vertical, 5)
                        .background(Color.surfaceSecondary, in: Capsule())
                }
            }
        }
    }

    private var missing: [NutritionIngredient]? {
        guard entry.macrosAvailable else { return nil }
        if let id = entry.stockOperationID, stock.hasLoggedMeal(id) { return [] }
        return try? stock.missingIngredients(for: ingredients)
    }

    private var actions: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            // One button: the recipe and the review-and-log flow share one sheet.
            actionButton(isToday ? "Review recipe and log" : "View recipe", systemImage: "fork.knife", prominent: true) { showReview = true }
                .accessibilityHint(entry.macrosAvailable ? "Shows how to make it, and reviews the portions to log from stock"
                                                         : "Shows how to make it")
                .accessibilityIdentifier("mealPlan.reviewRecipeLog")
            if let missing, !missing.isEmpty, entry.stockOperationID != nil {
                actionButton("Add missing ingredients to checklist", systemImage: "cart.badge.plus", prominent: false) {
                    if MealReviewSheet.addMissingToGroceries(entry: entry, missing: missing) {
                        addedNotice = "Missing quantities added to your checklist."
                        addedTrigger.toggle()
                    }
                }
                .sensoryFeedback(.success, trigger: addedTrigger)
                .accessibilityIdentifier("mealPlan.addMissing")
            }
        }
    }

    private func actionButton(_ title: String, systemImage: String, prominent: Bool,
                              action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(prominent ? Color.onAccent : Color.labelPrimary)
                .padding(.horizontal, Spacing.md)
                .frame(minHeight: 44)
                .background(prominent ? Color.progress : Color.surfaceSecondary,
                            in: RoundedRectangle(cornerRadius: Radius.chip, style: .continuous))
                .contentShape(RoundedRectangle(cornerRadius: Radius.chip, style: .continuous))
        }
        .buttonStyle(ScalePressStyle())
    }
}

// MARK: - Why this plan

private struct WhyThisPlanCard: View {
    let notes: String
    @State private var expanded = false

    var body: some View {
        DisclosureGroup("Why this plan?", isExpanded: $expanded) {
            Text(notes.isEmpty ? "No notes provided." : notes)
                .font(.subheadline).italic()
                .foregroundStyle(Color.labelSecondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, 8)
        }
        .tint(Color.brandPrimary)
        .padding(16)
        .background(Color.brandPrimary.opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }
}

// MARK: - Recommendations

private struct RecommendationsSection: View {
    let items: [ShoppingRecommendation]
    let onAdd: (ShoppingRecommendation) -> Void
    let onAddAll: ([ShoppingRecommendation]) -> Void
    /// Cards still in the deck this session (skipped ones just leave it).
    @State private var remaining: [ShoppingRecommendation] = []
    @State private var addedTrigger = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text("Gaps & Recommendations")
                    .font(.headline)
                Spacer()
                if !remaining.isEmpty {
                    Text("\(remaining.count) left" as String)
                        .font(.caption).foregroundStyle(Color.labelSecondary)
                        .monospacedDigit()
                        .contentTransition(.numericText())
                }
            }

            SwipeDeck(items: remaining, acceptLabel: "Add to checklist", skipLabel: "Skip",
                      label: { item in
                          "\(item.foodName). \(item.reason). €\(String(format: "%.2f", item.estimatedPrice)). \(PriorityBadge.label(item.priority)) priority"
                      },
                      onDecide: { item, accepted in
                          if accepted { onAdd(item); addedTrigger.toggle() }
                          remaining.removeAll { $0.id == item.id }
                      }) { item in
                recommendationCard(item)
            } empty: {
                VStack(spacing: 4) {
                    Label("All done", systemImage: "checkmark.circle")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Color.labelPrimary)
                    Text("Added items are in your checklist.")
                        .font(.caption).foregroundStyle(Color.labelSecondary)
                }
                .frame(maxWidth: .infinity)
                .accessibilityElement(children: .combine)
            }

            if remaining.count > 1 {
                Button {
                    addedTrigger.toggle()
                    onAddAll(remaining)
                    remaining = []
                } label: {
                    Label("Add all to checklist", systemImage: "cart.badge.plus")
                        .font(.subheadline).fontWeight(.semibold)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .foregroundStyle(Color.labelPrimary)
                }
                .buttonStyle(ScalePressStyle())
            }
        }
        .sensoryFeedback(.success, trigger: addedTrigger)
        .padding(16)
        .premiumCard(radius: 16)
        .onAppear { if remaining.isEmpty { remaining = items } }
        .onChange(of: items.map(\.id)) { _, _ in remaining = items }
    }

    private func recommendationCard(_ item: ShoppingRecommendation) -> some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            HStack(alignment: .firstTextBaseline) {
                Text(item.foodName).font(.headline).foregroundStyle(Color.labelPrimary)
                Spacer(minLength: Spacing.sm)
                PriorityBadge(priority: item.priority)
            }
            Text(item.reason)
                .font(.subheadline).foregroundStyle(Color.labelSecondary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            Text("est. €\(item.estimatedPrice, specifier: "%.2f")")
                .font(.caption).foregroundStyle(Color.labelSecondary)
        }
        .padding(Spacing.lg)
        .padding(.top, Spacing.lg)   // room for the Add / Skip stamps
    }
}

private struct PriorityBadge: View {
    let priority: Int

    static func label(_ priority: Int) -> String {
        switch priority {
        case 1: return "High"
        case 2: return "Medium"
        default: return "Low"
        }
    }
    private var label: String { Self.label(priority) }
    private var color: Color {
        switch priority {
        case 1: return .brandDanger
        case 2: return .brandAmber
        default: return .secondary
        }
    }

    var body: some View {
        Text(label)
            .font(.caption2).fontWeight(.bold)
            .foregroundStyle(color)
            .padding(.horizontal, 8).padding(.vertical, 3)
            .background(color.opacity(0.12))
            .clipShape(Capsule())
    }
}

// MARK: - Regenerate

private struct RegenerateButton: View {
    let isGenerating: Bool
    var idleTitle = "Regenerate plan"
    let onTap: () -> Void

    var body: some View {
        PrimaryButton(
            title: isGenerating ? "Building your plan…" : idleTitle,
            systemImage: isGenerating ? nil : "arrow.clockwise",
            isLoading: isGenerating,
            action: onTap
        )
    }
}

// MARK: - States

// MARK: - Skeleton loaders

private struct SkeletonMealPlanContent: View {
    var body: some View {
        VStack(spacing: 16) {
            ForEach(0..<4, id: \.self) { _ in SkeletonMealSection() }
            // Placeholder for regenerate button
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(.systemFill))
                .frame(height: 54)
        }
        .padding(.horizontal, 16)
        // One band across the whole placeholder, not one animation per bar.
        .shimmer()
        .accessibilityHidden(true)
    }
}

private struct SkeletonMealSection: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color(.systemFill))
                    .frame(width: 34, height: 34)
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color(.systemFill))
                    .frame(width: 110, height: 15)
                Spacer()
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color(.systemFill))
                    .frame(width: 55, height: 13)
            }
            ForEach(0..<2, id: \.self) { i in
                HStack(spacing: 10) {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color(.systemFill))
                        .frame(width: i == 0 ? 160 : 120, height: 13)
                    Spacer()
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color(.systemFill))
                        .frame(width: 48, height: 13)
                }
                .padding(.leading, 46)
            }
        }
        .padding(16)
        .background(Color.surface)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .shadow(color: .black.opacity(0.05), radius: 6, x: 0, y: 2)
    }
}

#Preview {
    NavigationStack { MealPlanView() }
}

/// Shown when the plan uses foods that aren't in the cart or My Stock: what they
/// are, and one tap to add them (the cart fills My Stock, and the plan is rebuilt).
private struct MissingFoodsBanner: View {
    @State private var appState = AppState.shared
    @State private var added = 0

    private var missing: [(id: String, name: String)] {
        guard let plan = appState.weeklyMealPlan else { return [] }
        var seen = Set<String>(), out: [(String, String)] = []
        for day in plan.allDays.map(\.plan) {
            for meal in [day.pusryciai, day.pietus, day.vakariene, day.uzkandziai].compactMap({ $0 }) {
                for (i, id) in (meal.missingCatalogIds ?? []).enumerated() where seen.insert(id).inserted {
                    out.append((id, meal.missing?.indices.contains(i) == true ? meal.missing![i] : id))
                }
            }
        }
        return out
    }

    var body: some View {
        let missing = missing
        if !missing.isEmpty {
            VStack(alignment: .leading, spacing: Spacing.sm) {
                Label("Some meals use food you don't have yet", systemImage: "cart.badge.plus")
                    .font(.subheadline.weight(.semibold))
                Text("Not in your cart or stock: \(missing.map(\.name).joined(separator: ", ")). Add them so the plan is made from your own kitchen." as String)
                    .font(.footnote).foregroundStyle(Color.labelSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                Button {
                    for m in missing {
                        if let item = CatalogItem.all.first(where: { $0.id == m.id }) { ShoppingCartService.shared.add(item, store: .catalog) }
                    }
                    AgentLoop.rebuildPlanNow()
                    added &+= 1
                } label: {
                    Label("Add \(missing.count) to cart and stock" as String, systemImage: "plus")
                        .font(.subheadline.weight(.semibold))
                        .padding(.horizontal, Spacing.lg).frame(minHeight: 44)
                        .background(Color.dullPink, in: Capsule())
                        .foregroundStyle(Color.onAccent)
                        .contentShape(Capsule())
                }
                .buttonStyle(ScalePressStyle())
                .accessibilityIdentifier("meals.addMissing")
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(Spacing.lg)
            .premiumCard(radius: Radius.tile)
            .sensoryFeedback(.success, trigger: added)
            .accessibilityElement(children: .contain)
        }
    }
}
