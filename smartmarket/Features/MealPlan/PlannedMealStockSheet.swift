import SwiftUI

// MARK: - Review recipe and log
//
// One sheet for a planned meal, opened by its single "Review recipe and log" button:
// how to make it (the AI recipe when online AI is offered, else Wikibooks recipes
// that use its foods) and the review of its portions with "Log meal from stock".
// The recipe only loads once its tab is opened, and stays loaded while the sheet is up.

struct MealReviewSheet: View {
    let entry: MealEntry
    let slot: MealSlot

    enum Tab: String, CaseIterable, Identifiable {
        case review, recipe
        var id: String { rawValue }
        var title: String { self == .review ? "Review and log" : "Recipe" }
    }

    @State private var tab: Tab
    /// Set once the recipe tab has been shown, so it isn't loaded again on every switch.
    @State private var recipeOpened: Bool
    @Environment(\.dismiss) private var dismiss

    init(entry: MealEntry, slot: MealSlot, startOn: Tab? = nil) {
        self.entry = entry
        self.slot = slot
        // A meal with portions starts on its review; one without starts on the recipe.
        let first = startOn ?? (entry.macrosAvailable ? .review : .recipe)
        _tab = State(initialValue: first)
        _recipeOpened = State(initialValue: first == .recipe)
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Picker("Show", selection: $tab) {
                    ForEach(Tab.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, Spacing.lg)
                .padding(.vertical, Spacing.sm)
                .accessibilityIdentifier("mealReview.tabs")

                ZStack {
                    PlannedMealReview(entry: entry, slot: slot)
                        .opacity(tab == .review ? 1 : 0)
                        .allowsHitTesting(tab == .review)
                        .accessibilityHidden(tab != .review)
                    if recipeOpened {
                        RecipeView(mealName: entry.foodName, slot: slot)
                            .opacity(tab == .recipe ? 1 : 0)
                            .allowsHitTesting(tab == .recipe)
                            .accessibilityHidden(tab != .recipe)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .background(Color.surfaceGrouped.ignoresSafeArea())
            .navigationTitle(entry.foodName)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }.fontWeight(.semibold)
                }
            }
            .onChange(of: tab) { _, new in if new == .recipe { recipeOpened = true } }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
    }

    /// Adds (or refreshes) the missing quantities as unbought grocery rows. Shared
    /// with the expanded meal card on the Meal Plan screen. Returns false when the
    /// entry has no stock operation to key the rows by.
    @discardableResult
    static func addMissingToGroceries(entry: MealEntry, missing: [NutritionIngredient]) -> Bool {
        guard let operationID = entry.stockOperationID else { return false }
        var groceries = GroceryStorage.load()
        for ingredient in missing {
            let id = "planned_" + operationID + "_" + ingredient.food.id
            let quantity = "\(ingredient.amount.formatted(.number.grouping(.never))) \(ingredient.food.basis.rawValue)"
            if let index = groceries.firstIndex(where: { $0.id == id }) {
                groceries[index].quantity = quantity
                groceries[index].isBought = false
            } else {
                groceries.append(GroceryItem(id: id, foodId: ingredient.food.id, foodName: ingredient.food.name,
                                              quantity: quantity, estimatedPrice: 0, storeId: "unassigned", storeName: "",
                                              isBought: false, priceKnown: false))
            }
        }
        GroceryStorage.save(groceries)
        NotificationCenter.default.post(name: .groceryListDidChange, object: nil)
        return true
    }
}

// MARK: - Review and log

/// The planned portions, what's missing from My Stock, and "Log meal from stock".
/// Existing native Form styling; ingredient quantities stay beside each source.
struct PlannedMealReview: View {
    let entry: MealEntry
    let slot: MealSlot
    @State private var stock = StockStore.shared
    @State private var notice: String?

    private var ingredients: [NutritionIngredient] { entry.nutritionIngredients ?? [] }
    private var missing: [NutritionIngredient]? { try? stock.missingIngredients(for: ingredients) }
    private var logged: Bool { entry.stockOperationID.map { stock.hasLoggedMeal($0) } ?? false }

    var body: some View {
        Form {
            Section(entry.foodName) {
                if entry.macrosAvailable {
                    Text("\(entry.calories) kcal · P \(Self.grams(entry.proteinG)) g · C \(Self.grams(entry.carbsG)) g · F \(Self.grams(entry.fatG)) g" as String)
                    Text("Calculated from these ingredient portions. Review the preparation and quantities before logging. Logging removes these amounts from My Stock.")
                        .font(.footnote).foregroundStyle(.secondary)
                } else {
                    Text("\(entry.calories) kcal · protein, carbs and fat not available" as String)
                    Text("This meal has no ingredient portions, so it can't be logged from My Stock. Log what you ate from Add Food.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }
            if !ingredients.isEmpty {
                Section("Planned portions") {
                    ForEach(ingredients) { ingredient in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(ingredient.food.name)
                            Text("\(ingredient.amount.formatted(.number.precision(.fractionLength(0...1)).grouping(.never))) \(ingredient.food.basis.rawValue) · \(ingredient.food.sourceName)" as String)
                                .font(.caption).foregroundStyle(.secondary)
                            if !logged {
                                StockSummaryLine(summary: stock.summary(for: ingredient.food, amount: ingredient.amount, exactOnly: true))
                            }
                            if let url = ingredient.food.sourceURL { Link("Nutrition source", destination: url).font(.caption) }
                        }
                    }
                }
            }
            if entry.macrosAvailable {
                if logged {
                    Section { Label("Meal already logged", systemImage: "checkmark.circle.fill") }
                } else if let missing, !missing.isEmpty {
                    Section("Needed before cooking") {
                        ForEach(missing) { ingredient in
                            Text("\(ingredient.food.name) · \(ingredient.amount.formatted(.number.grouping(.never))) \(ingredient.food.basis.rawValue) missing" as String)
                        }
                        Button("Add missing ingredients to checklist") { addMissing(missing) }
                            .accessibilityIdentifier("plannedMeal.addMissing")
                        Text("No store or price is assumed. After buying, add the actual quantity to My Stock.")
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                } else if missing == nil {
                    Text("The ingredient amounts could not be checked. Review the plan before logging.")
                }
                Section {
                    Button("Log meal from stock") {
                        guard let operationID = entry.stockOperationID else { return }
                        do {
                            try stock.consumeMeal(ingredients, slot: slot, operationID: operationID)
                            notice = "Logged. My Stock and today's totals are updated."
                        } catch { notice = error.localizedDescription }
                    }
                    .disabled(logged || missing == nil || missing?.isEmpty == false || entry.stockOperationID == nil)
                    .accessibilityIdentifier("plannedMeal.logStock")
                }
            }
            if let notice { Section { Text(notice).accessibilityIdentifier("plannedMeal.notice") } }
        }
        .scrollContentBackground(.hidden)
    }

    /// "29" or "15.3", never "29.0004".
    private static func grams(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(0...1)).grouping(.never))
    }

    private func addMissing(_ missing: [NutritionIngredient]) {
        guard MealReviewSheet.addMissingToGroceries(entry: entry, missing: missing) else { return }
        notice = "Missing quantities added to your checklist."
    }
}
