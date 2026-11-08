import SwiftUI

/// Existing native Form styling; ingredient quantities stay beside each source.
struct PlannedMealStockSheet: View {
    let entry: MealEntry
    let slot: MealSlot
    @Environment(\.dismiss) private var dismiss
    @State private var stock = StockStore.shared
    @State private var notice: String?

    private var ingredients: [NutritionIngredient] { entry.nutritionIngredients ?? [] }
    private var missing: [NutritionIngredient]? { try? stock.missingIngredients(for: ingredients) }
    private var logged: Bool { entry.stockOperationID.map { stock.hasLoggedMeal($0) } ?? false }

    var body: some View {
        NavigationStack {
            Form {
                Section(entry.foodName) {
                    Text("\(entry.calories) kcal · P \(entry.proteinG.formatted()) g · C \(entry.carbsG.formatted()) g · F \(entry.fatG.formatted()) g")
                    Text("Calculated from these ingredient portions. Review the preparation and quantities before logging. Logging removes these amounts from My Stock.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                Section("Planned portions") {
                    ForEach(ingredients) { ingredient in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(ingredient.food.name)
                            Text("\(ingredient.amount.formatted()) \(ingredient.food.basis.rawValue) · \(ingredient.food.sourceName)")
                                .font(.caption).foregroundStyle(.secondary)
                            if let url = ingredient.food.sourceURL { Link("Nutrition source", destination: url).font(.caption) }
                        }
                    }
                }
                if logged {
                    Section { Label("Meal already logged", systemImage: "checkmark.circle.fill") }
                } else if let missing, !missing.isEmpty {
                    Section("Needed before cooking") {
                        ForEach(missing) { ingredient in
                            Text("\(ingredient.food.name) · \(ingredient.amount.formatted()) \(ingredient.food.basis.rawValue) missing")
                        }
                        Button("Add missing ingredients to groceries") { addMissing(missing) }
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
                if let notice { Section { Text(notice).accessibilityIdentifier("plannedMeal.notice") } }
            }
            .navigationTitle("Review Meal")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
    }

    private func addMissing(_ missing: [NutritionIngredient]) {
        guard let operationID = entry.stockOperationID else { return }
        var groceries = GroceryStorage.load()
        for ingredient in missing {
            let id = "planned_" + operationID + "_" + ingredient.food.id
            let quantity = "\(ingredient.amount.formatted()) \(ingredient.food.basis.rawValue)"
            if let index = groceries.firstIndex(where: { $0.id == id }) {
                groceries[index].quantity = quantity
                groceries[index].isBought = false
            } else {
                groceries.append(GroceryItem(id: id, foodId: ingredient.food.id, foodName: ingredient.food.name,
                                              quantity: quantity, estimatedPrice: 0, storeId: "unassigned", storeName: "Choose a store",
                                              isBought: false, priceKnown: false))
            }
        }
        GroceryStorage.save(groceries)
        NotificationCenter.default.post(name: .groceryListDidChange, object: nil)
        notice = "Missing quantities added to Groceries."
    }
}
