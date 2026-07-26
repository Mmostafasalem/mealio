import SwiftUI
import Observation

@MainActor
@Observable
final class GroceryListViewModel {

    var items: [GroceryItem] = [] {
        didSet { recompute() }
    }

    private(set) var recentlyDeletedItem: GroceryItem?
    private var undoTask: Task<Void, Never>?

    init() {
        loadItems()
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

        // Cart-sourced row: round-trip the deletion to the Shop cart (no undo).
        if let coords = ShoppingCartService.parseCartRowId(item.id) {
            ShoppingCartService.shared.removeLine(catalogId: coords.catalogId, store: coords.store)
            return
        }

        // Manual / deal-buy item: optimistic delete with 4-second undo.
        recentlyDeletedItem = item
        saveItems()
        undoTask?.cancel()
        undoTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(4))
            self?.recentlyDeletedItem = nil
        }
    }

    func undoDelete() {
        guard let item = recentlyDeletedItem else { return }
        undoTask?.cancel()
        recentlyDeletedItem = nil
        items.append(item)
        saveItems()
    }

    func clearBought() {
        // Round-trip any cart-sourced bought rows to the Shop cart first — otherwise
        // the cart still holds them and the next cart change would silently re-add
        // them (unbought). Mirrors deleteItem's cart round-trip.
        for item in items where item.isBought {
            if let coords = ShoppingCartService.parseCartRowId(item.id) {
                ShoppingCartService.shared.removeLine(catalogId: coords.catalogId, store: coords.store)
            }
        }
        items.removeAll { $0.isBought }
        saveItems()
    }

    func addItem(_ item: GroceryItem) {
        items.append(item)
        saveItems()
    }

    func shareText() -> String {
        var lines = ["Mealio Grocery List", ""]
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
