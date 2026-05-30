import SwiftUI
import Observation

@MainActor
@Observable
final class GroceryListViewModel {

    var items: [GroceryItem] = [] {
        didSet { recompute() }
    }

    init() {
        Task { @MainActor [weak self] in
            for await _ in NotificationCenter.default.notifications(named: .groceryListDidChange) {
                self?.loadItems()
            }
        }
    }

    private(set) var groupedByStore: [String: [GroceryItem]] = [:]
    private(set) var sortedStores: [String] = []
    private(set) var totalEstimatedCost: Double = 0

    private func recompute() {
        groupedByStore = Dictionary(grouping: items, by: { $0.storeName })
        sortedStores = groupedByStore.keys.sorted()
        totalEstimatedCost = items.reduce(0) { $0 + $1.estimatedPrice }
    }

    func estimatedCost(for store: String) -> Double {
        (groupedByStore[store] ?? []).reduce(0) { $0 + $1.estimatedPrice }
    }

    // MARK: - Persistence

    func loadItems() {
        items = GroceryStorage.load()
    }

    func saveItems() {
        GroceryStorage.save(items)
    }

    // MARK: - Mutations

    func toggleBought(_ item: GroceryItem) {
        guard let index = items.firstIndex(where: { $0.id == item.id }) else { return }
        items[index].isBought.toggle()
        saveItems()
    }

    func deleteItem(_ item: GroceryItem) {
        items.removeAll { $0.id == item.id }
        saveItems()
    }

    func clearBought() {
        items.removeAll { $0.isBought }
        saveItems()
    }

    func addItem(_ item: GroceryItem) {
        items.append(item)
        saveItems()
    }

    func shareText() -> String {
        var lines = ["SmartMarket Grocery List", ""]
        for store in sortedStores {
            lines.append("\(store):")
            for item in groupedByStore[store] ?? [] {
                let check = item.isBought ? "[x]" : "[ ]"
                lines.append("  \(check) \(item.foodName) (\(item.quantity)) — €\(String(format: "%.2f", item.estimatedPrice))")
            }
            lines.append("")
        }
        lines.append(String(format: "Total: €%.2f", totalEstimatedCost))
        return lines.joined(separator: "\n")
    }
}
