import SwiftUI

/// Ultra-low-friction food logging.
/// Open (tap 1) → tap a food's ⊕ (tap 2) = logged at its default serving.
/// Or tap the row to fine-tune the serving, then Add (tap 3).
struct LogFoodSheet: View {

    @Bindable var vm: HomeViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var slot: MealSlot = .suggested()
    @State private var query: String = ""
    @State private var addedToast: String?
    @State private var detailFood: Food?
    @FocusState private var searchFocused: Bool

    private var results: [Food] {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        guard !q.isEmpty else { return [] }
        return Food.catalog.filter {
            $0.nameEn.lowercased().contains(q) || $0.name.lowercased().contains(q)
        }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                slotPicker
                searchField

                List {
                    if query.isEmpty {
                        if !vm.plannedEntries(for: slot).isEmpty {
                            Section("From today's plan — tap to log") {
                                ForEach(vm.plannedEntries(for: slot)) { entry in plannedRow(entry) }
                            }
                        }
                        if !vm.recentFoods.isEmpty {
                            Section("Recent") {
                                ForEach(vm.recentFoods) { food in row(food) }
                            }
                        }
                        Section("All foods") {
                            ForEach(Food.catalog) { food in row(food) }
                        }
                    } else if results.isEmpty {
                        ContentUnavailableView.search(text: query)
                    } else {
                        Section("Results") {
                            ForEach(results) { food in row(food) }
                        }
                    }
                }
                .listStyle(.insetGrouped)
                .navigationDestination(item: $detailFood) { food in
                    ServingDetailView(food: food, slot: slot) { grams in
                        vm.logFood(food, slot: slot, grams: grams)
                        vm.showLogSheet = false
                    }
                }
            }
            .navigationTitle("Add Food")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
            .overlay(alignment: .bottom) { toast }
            .onAppear {
                slot = vm.logSheetSlot ?? .suggested()
            }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
    }

    // MARK: - Slot picker

    private var slotPicker: some View {
        Picker("Meal", selection: $slot) {
            ForEach(MealSlot.allCases) { Text($0.title).tag($0) }
        }
        .pickerStyle(.segmented)
        .padding(.horizontal, 16)
        .padding(.top, 8)
    }

    // MARK: - Search

    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass").foregroundStyle(Color.labelSecondary)
            TextField("Search foods", text: $query)
                .focused($searchFocused)
                .autocorrectionDisabled()
                .submitLabel(.search)
            if !query.isEmpty {
                Button { query = "" } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(Color.labelSecondary)
                }
                .accessibilityLabel("Clear search")
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(Color.surfaceElevated, in: RoundedRectangle(cornerRadius: 12))
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }

    // MARK: - Row

    private func row(_ food: Food) -> some View {
        HStack(spacing: 12) {
            // Tapping the info area opens the serving detail (fine-tune → Add).
            Button {
                detailFood = food
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: food.category.sfSymbol)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(slot.accent)
                        .frame(width: 34, height: 34)
                        .background(slot.accent.opacity(0.12), in: Circle())

                    VStack(alignment: .leading, spacing: 2) {
                        Text(food.displayName).font(.subheadline).fontWeight(.medium)
                            .foregroundStyle(Color.labelPrimary)
                        Text("\(food.servingSizeG)g · \(food.macroSummary)")
                            .font(.caption2).foregroundStyle(Color.labelSecondary)
                    }
                    Spacer()
                    Text("\(kcal(food, grams: food.servingSizeG)) kcal")
                        .font(.caption).fontWeight(.semibold)
                        .foregroundStyle(Color.labelSecondary).monospacedDigit()
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            // Quick-add at default serving (the 2-tap path).
            Button {
                quickAdd(food)
            } label: {
                Image(systemName: "plus.circle.fill")
                    .font(.system(size: 24))
                    .foregroundStyle(slot.accent)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Add \(food.displayName)")
        }
        .padding(.vertical, 2)
    }

    // MARK: - Toast

    @ViewBuilder private var toast: some View {
        if let msg = addedToast {
            Label(msg, systemImage: "checkmark.circle.fill")
                .font(.subheadline).fontWeight(.semibold)
                .foregroundStyle(Color.almond)
                .padding(.horizontal, 16).padding(.vertical, 10)
                .background(Color.rhino, in: Capsule())
                .padding(.bottom, 24)
                .transition(.move(edge: .bottom).combined(with: .opacity))
        }
    }

    // MARK: - Actions

    private func quickAdd(_ food: Food) {
        vm.logFood(food, slot: slot, grams: food.servingSizeG)
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        showToast("Added \(food.displayName)")
    }

    private func showToast(_ message: String) {
        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) { addedToast = message }
        Task {
            try? await Task.sleep(for: .seconds(1.4))
            withAnimation { addedToast = nil }
        }
    }

    // MARK: - Planned meal row (one-tap log from today's plan)

    private func plannedRow(_ entry: MealEntry) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "sparkles")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(slot.accent)
                .frame(width: 34, height: 34)
                .background(slot.accent.opacity(0.12), in: Circle())

            VStack(alignment: .leading, spacing: 2) {
                Text(entry.foodName).font(.subheadline).fontWeight(.medium)
                Text(portionText(entry)).font(.caption2).foregroundStyle(Color.labelSecondary)
            }
            Spacer()
            Text("\(entry.calories) kcal")
                .font(.caption).fontWeight(.semibold)
                .foregroundStyle(Color.labelSecondary).monospacedDigit()

            Button {
                vm.logPlanned(entry, slot: slot)
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                showToast("Logged \(entry.foodName)")
            } label: {
                Image(systemName: "plus.circle.fill")
                    .font(.system(size: 24))
                    .foregroundStyle(slot.accent)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Log \(entry.foodName)")
        }
        .padding(.vertical, 2)
    }

    private func portionText(_ entry: MealEntry) -> String {
        let notes = entry.notes ?? ""
        return notes.isEmpty ? "\(entry.portionG)g" : notes
    }

    private func kcal(_ food: Food, grams: Int) -> Int {
        Int((Double(food.caloriesPer100g) * Double(grams) / 100).rounded())
    }
}

// MARK: - Serving detail (fine-tune grams before logging)

private struct ServingDetailView: View {
    let food: Food
    let slot: MealSlot
    let onAdd: (Int) -> Void

    @State private var grams: Double

    init(food: Food, slot: MealSlot, onAdd: @escaping (Int) -> Void) {
        self.food = food
        self.slot = slot
        self.onAdd = onAdd
        _grams = State(initialValue: Double(food.servingSizeG))
    }

    private var factor: Double { grams / 100.0 }
    private var kcal: Int { Int((Double(food.caloriesPer100g) * factor).rounded()) }

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                // Calorie hero for this serving
                VStack(spacing: 4) {
                    Text("\(kcal)")
                        .font(.system(size: 52, weight: .bold, design: .rounded))
                        .foregroundStyle(Color.labelPrimary).monospacedDigit()
                        .contentTransition(.numericText())
                    Text("kcal · \(Int(grams))g").font(.subheadline).foregroundStyle(Color.labelSecondary)
                    // Household equivalent so users don't have to think in grams.
                    Text(Portion.household(grams: Int(grams), category: food.category.rawValue))
                        .font(.subheadline).fontWeight(.semibold)
                        .foregroundStyle(slot.accent)
                }
                .padding(.top, 12)
                .animation(.spring(response: 0.3, dampingFraction: 0.85), value: grams)

                // Macro chips
                HStack(spacing: 10) {
                    macroChip("Protein", food.proteinPer100g * factor, .proteinAccent)
                    macroChip("Carbs", food.carbsPer100g * factor, .carbsAccent)
                    macroChip("Fat", food.fatPer100g * factor, .fatAccent)
                }

                // Serving stepper
                VStack(spacing: 12) {
                    HStack {
                        Text("Serving").font(.headline)
                        Spacer()
                        Text("\(Int(grams)) g").font(.headline).monospacedDigit()
                    }
                    Slider(value: $grams, in: 10...1000, step: 10)
                        .tint(slot.accent)
                    HStack(spacing: 8) {
                        ForEach([50, 100, 150, 200], id: \.self) { preset in
                            Button("\(preset)g") { grams = Double(preset) }
                                .font(.caption).fontWeight(.semibold)
                                .padding(.horizontal, 12).padding(.vertical, 6)
                                .background(Color.surfaceElevated, in: Capsule())
                        }
                    }
                }
                .padding(16)
                .premiumCard()
            }
            .padding(16)
        }
        .background(Color.surfaceGrouped.ignoresSafeArea())
        .navigationTitle(food.displayName)
        .navigationBarTitleDisplayMode(.inline)
        .safeAreaInset(edge: .bottom) {
            Button {
                onAdd(Int(grams))
            } label: {
                Label("Add to \(slot.title)", systemImage: "plus")
                    .font(.headline).foregroundStyle(Color.almond)
                    .frame(maxWidth: .infinity).padding(.vertical, 14)
                    .background(Color.rhino, in: RoundedRectangle(cornerRadius: Radius.pill))
            }
            .padding(.horizontal, 16).padding(.bottom, 8)
        }
    }

    private func macroChip(_ label: String, _ grams: Double, _ color: Color) -> some View {
        VStack(spacing: 3) {
            Text("\(Int(grams.rounded()))g")
                .font(.system(size: 17, weight: .bold, design: .rounded))
                .foregroundStyle(color).monospacedDigit()
            Text(label).font(.caption2).foregroundStyle(Color.labelSecondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background(color.opacity(0.10), in: RoundedRectangle(cornerRadius: 12))
    }
}
