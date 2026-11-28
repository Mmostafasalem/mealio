import SwiftUI

// MARK: - To clarify: meal photos finished later
//
// A photo saved by "Snap a meal" that wasn't logged yet. Opening it shows the photo and
// its time; the person picks the foods and amounts (or, when online AI is offered, has
// the photo read), and they're logged at the time the photo was taken.

/// One saved photo in a list: thumbnail, "Lunch · today 12:41", "To clarify".
struct PendingMealRow: View {
    let meal: PendingMeal
    @State private var image: UIImage?

    var body: some View {
        HStack(spacing: 12) {
            Group {
                if let image {
                    Image(uiImage: image).resizable().scaledToFill()
                } else {
                    Image(systemName: "photo").foregroundStyle(Color.labelSecondary)
                }
            }
            .frame(width: 48, height: 48)
            .background(Color.surfaceSecondary)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(meal.slot.title).font(.subheadline.weight(.semibold)).foregroundStyle(Color.labelPrimary)
                Text(Self.when(meal.takenAt)).font(.caption).foregroundStyle(Color.labelSecondary)
            }
            Spacer(minLength: 8)
            Text("Clarify")
                .font(.caption.weight(.semibold))
                .foregroundStyle(Color.onAccent)
                .padding(.horizontal, 10).padding(.vertical, 5)
                .background(Color.progress, in: Capsule())
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(meal.slot.title) photo, \(Self.when(meal.takenAt)), to clarify" as String)
        .task { image = PendingMealStore.shared.image(for: meal) }
    }

    /// "Today, 12:41" / "Yesterday, 19:05" / "24 Nov, 08:10".
    static func when(_ date: Date) -> String {
        let time = date.formatted(date: .omitted, time: .shortened)
        let calendar = Calendar.current
        if calendar.isDateInToday(date) { return "Today, \(time)" }
        if calendar.isDateInYesterday(date) { return "Yesterday, \(time)" }
        return date.formatted(.dateTime.day().month(.abbreviated)) + ", " + time
    }
}

/// For Home: the photos waiting to be clarified, each opening its sheet. Shows nothing
/// when there are none.
struct PendingMealsCard: View {
    @State private var store = PendingMealStore.shared
    @State private var open: PendingMeal?

    var body: some View {
        if !store.meals.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                Label("To clarify", systemImage: "camera.viewfinder")
                    .font(.headline)
                    .foregroundStyle(Color.labelPrimary)
                ForEach(store.meals.prefix(3)) { meal in
                    Button { open = meal } label: { PendingMealRow(meal: meal) }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("home.toClarify")
                }
                if store.meals.count > 3 {
                    Text("\(store.meals.count - 3) more in Add Food" as String)
                        .font(.caption).foregroundStyle(Color.labelSecondary)
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.surfaceElevated, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .sheet(item: $open) { meal in ClarifyMealSheet(meal: meal) { open = nil } }
        }
    }
}

/// Finishing a saved photo: what was in it, how much, and which meal.
struct ClarifyMealSheet: View {
    let meal: PendingMeal
    let close: () -> Void

    private struct Pick: Identifiable {
        let id = UUID()
        let food: NutritionFood
        var amount: Double
        var kcal: Int { Int(food.portion(amount).kcal.rounded()) }
    }

    @State private var picks: [Pick] = []
    @State private var slot: MealSlot
    @State private var image: UIImage?
    @State private var showPicker = false
    @State private var showAI = false
    @State private var confirmDelete = false
    @State private var logVM = HomeViewModel()
    @State private var stock = StockStore.shared
    @State private var logged: [FoodLogEntry]?

    init(meal: PendingMeal, close: @escaping () -> Void) {
        self.meal = meal
        self.close = close
        _slot = State(initialValue: meal.slot)
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    VStack(alignment: .leading, spacing: 10) {
                        if let image {
                            Image(uiImage: image)
                                .resizable()
                                .scaledToFit()
                                .frame(maxWidth: .infinity, maxHeight: 260)
                                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                                .accessibilityLabel("Your meal photo")
                        }
                        Label("Taken \(PendingMealRow.when(meal.takenAt).lowercased())" as String, systemImage: "clock")
                            .font(.footnote).foregroundStyle(Color.labelSecondary)
                    }
                    .listRowBackground(Color.clear)
                    Picker("Meal", selection: $slot) { ForEach(MealSlot.allCases) { Text($0.title).tag($0) } }
                        .accessibilityIdentifier("clarify.slot")
                }

                if let logged {
                    Section {
                        Label("Logged \(logged.count == 1 ? logged[0].name : "\(logged.count) foods"), \(logged.reduce(0) { $0 + $1.calories }) kcal" as String,
                              systemImage: "checkmark.circle.fill")
                            .foregroundStyle(Color.ringProtein)
                            .accessibilityIdentifier("clarify.done")
                        Button("Undo") { undo(logged) }
                    }
                } else {
                    Section {
                        ForEach(picks) { pick in
                            VStack(alignment: .leading, spacing: 4) {
                                Text(pick.food.name).font(.subheadline.weight(.semibold))
                                Text("\(LogFoodSheet.amountText(pick.amount, basis: pick.food.basis)) · \(pick.kcal) kcal" as String)
                                    .font(.footnote.monospacedDigit())
                                StockSummaryLine(summary: stock.summary(for: pick.food, amount: pick.amount))
                            }
                            .accessibilityElement(children: .combine)
                        }
                        .onDelete { picks.remove(atOffsets: $0) }
                        Button { showPicker = true } label: {
                            Label(picks.isEmpty ? "Add what was in it" : "Add another food", systemImage: "plus.circle.fill")
                        }
                        .accessibilityIdentifier("clarify.addFood")
                    } header: {
                        Text("What was in it")
                    } footer: {
                        Text("Pick each food and the amount you ate. Foods in My Stock come out of it.")
                    }
                    if MealPhotoAccess.isUsable {
                        Section {
                            Button { showAI = true } label: { Label("Have online AI read the photo", systemImage: "sparkles") }
                        }
                    }
                    Section {
                        Button("Delete photo", role: .destructive) { confirmDelete = true }
                            .foregroundStyle(Color.brandDanger)
                            .accessibilityIdentifier("clarify.delete")
                    }
                }
            }
            .navigationTitle("Clarify meal")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button(logged == nil ? "Later" : "Close") { close() } }
                if logged == nil {
                    ToolbarItem(placement: .confirmationAction) {
                        Button(picks.isEmpty ? "Log" : "Log \(picks.reduce(0) { $0 + $1.kcal }) kcal" as String) { log() }
                            .fontWeight(.semibold)
                            .disabled(picks.isEmpty)
                            .accessibilityIdentifier("clarify.log")
                    }
                }
            }
            .sheet(isPresented: $showPicker) {
                LogFoodSheet(vm: logVM, onSelect: { food, amount in
                    picks.append(Pick(food: food, amount: amount))
                }, pickTitle: "Add to this meal")
            }
            .sheet(isPresented: $showAI) {
                VoiceCommandSheet(photoMode: true, pending: meal, close: {
                    showAI = false
                    if !PendingMealStore.shared.contains(meal.id) { close() }
                }, navigate: { _ in showAI = false })
            }
            .confirmationDialog("Delete this photo?", isPresented: $confirmDelete, titleVisibility: .visible) {
                Button("Delete photo", role: .destructive) {
                    PendingMealStore.shared.remove(meal.id)
                    close()
                }
            } message: {
                Text("Nothing was logged from it.")
            }
            .task { image = PendingMealStore.shared.image(for: meal) }
        }
    }

    private func log() {
        guard !picks.isEmpty else { return }
        PendingMealStore.shared.setSlot(slot, for: meal.id)
        var entries: [FoodLogEntry] = []
        for pick in picks {
            let entry = FoodLogEntry(nutritionFood: pick.food, slot: slot, amount: pick.amount, loggedAt: meal.takenAt)
            if pick.food.source == .openFoodFacts { NutritionCatalogService.shared.remember(pick.food) }
            FoodLogStore.shared.add(entry)
            entries.append(entry)
        }
        undoData = PendingMealStore.shared.imageData(for: meal)
        PendingMealStore.shared.remove(meal.id)
        logged = entries
    }

    @State private var undoData: Data?

    private func undo(_ entries: [FoodLogEntry]) {
        entries.forEach { FoodLogStore.shared.remove($0) }
        if let undoData { PendingMealStore.shared.add(jpeg: undoData, slot: slot, at: meal.takenAt, id: meal.id) }
        logged = nil
    }
}
