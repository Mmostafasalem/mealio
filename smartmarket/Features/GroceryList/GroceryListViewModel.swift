import SwiftUI
import Observation

@MainActor
@Observable
final class GroceryListViewModel {

    var items: [GroceryItem] = [] {
        didSet { recompute() }
    }

    private(set) var undoMessage: String?
    private var deletedItems: [GroceryItem] = []
    private var deletedCartLines: [CartItem] = []
    private var undoGeneration: UUID?
    private var undoID = UUID()
    private let undoDuration: Duration
    @ObservationIgnored private var undoTask: Task<Void, Never>?
    @ObservationIgnored private var changesTask: Task<Void, Never>?

    init(undoDuration: Duration = .seconds(8)) {
        self.undoDuration = undoDuration
        loadItems()
        changesTask = Task { @MainActor [weak self] in
            for await _ in NotificationCenter.default.notifications(named: .groceryListDidChange) {
                self?.loadItems()
            }
        }
    }

    deinit {
        changesTask?.cancel()
        undoTask?.cancel()
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
        removeItems([item], message: "\(item.foodName) removed")
    }

    private func prepareUndo(_ removed: [GroceryItem], lines: [CartItem], message: String) {
        undoTask?.cancel()
        deletedItems = removed
        deletedCartLines = lines
        undoMessage = message
        undoGeneration = AppState.shared.dataGeneration
        let expected = UUID()
        undoID = expected
        let duration = undoDuration
        undoTask = Task { @MainActor [weak self] in
            do { try await Task.sleep(for: duration) } catch { return }
            guard let self, self.undoID == expected else { return }
            self.discardUndo()
        }
    }

    private func discardUndo() {
        undoTask?.cancel()
        undoMessage = nil
        deletedItems = []
        deletedCartLines = []
        undoGeneration = nil
        undoID = UUID()
    }

    private func removeItems(_ removed: [GroceryItem], message: String) {
        guard !removed.isEmpty else { return }
        let ids = Set(removed.map(\.id))
        let cart = ShoppingCartService.shared
        let lines = cart.cartItems.filter {
            ids.contains(ShoppingCartService.cartRowId(catalogId: $0.catalogId, store: $0.store))
        }
        prepareUndo(removed, lines: lines, message: message)
        // Update local storage immediately; optional CloudKit sync happens separately.
        for line in lines { cart.removeLine(catalogId: line.catalogId, store: line.store) }
        items = GroceryStorage.load().filter { !ids.contains($0.id) }
        saveItems()
    }

    func undoDelete() {
        guard undoGeneration == AppState.shared.dataGeneration else { discardUndo(); return }
        let removed = deletedItems
        let lines = deletedCartLines
        let existingIDs = Set(GroceryStorage.load().map(\.id))
        discardUndo()
        ShoppingCartService.shared.restoreRemovedLines(lines)
        var restored = GroceryStorage.load()
        for item in removed {
            if let index = restored.firstIndex(where: { $0.id == item.id }) {
                if !existingIDs.contains(item.id) { restored[index].isBought = item.isBought }
            } else if ShoppingCartService.parseCartRowId(item.id) == nil {
                restored.append(item)
            }
        }
        items = restored
        saveItems()
    }

    func clearBought() {
        let bought = items.filter(\.isBought)
        removeItems(bought, message: "\(bought.count) bought items removed")
    }

    func clearCart() {
        let cart = ShoppingCartService.shared
        guard !cart.cartItems.isEmpty else { return }
        let rows = GroceryStorage.load().filter { ShoppingCartService.parseCartRowId($0.id) != nil }
        prepareUndo(rows, lines: cart.cartItems, message: "Cart cleared")
        cart.clear()
        loadItems()
    }

    func addItem(_ item: GroceryItem) {
        items.append(item)
        saveItems()
    }

    func shareText() -> String {
        var lines = ["Nourlo Grocery List", ""]
        for store in sortedStores {
            lines.append("\(store):")
            for item in groupedByStore[store] ?? [] {
                let check = item.isBought ? "[x]" : "[ ]"
                let price = item.priceKnown == false ? "Price unknown" : String(format: "€%.2f", item.estimatedPrice)
                lines.append("  \(check) \(item.foodName) (\(item.quantity)) — \(price)")
            }
            lines.append("")
        }
        let label = items.contains { $0.priceKnown == false } ? "Known estimates only" : "Estimated total"
        lines.append(String(format: "\(label): €%.2f", totalEstimatedCost))
        return lines.joined(separator: "\n")
    }
}
