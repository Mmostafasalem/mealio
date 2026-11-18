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
    /// Cart lines whose My Stock packs went with them (not bought): undo puts the packs back.
    private var deletedRestock: [String: Double] = [:]
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

    /// Flips one row against the latest stored list, so rows the cart or sync
    /// rewrote since this screen loaded are not overwritten.
    func toggleBought(_ item: GroceryItem) {
        var latest = GroceryStorage.load()
        guard let index = latest.firstIndex(where: { $0.id == item.id }) else { items = latest; return }
        latest[index].isBought.toggle()
        ShoppingCartService.noteBoughtTick(rowId: latest[index].id, quantity: latest[index].quantity,
                                           isBought: latest[index].isBought)
        GroceryStorage.save(latest)
        items = latest
    }

    func deleteItem(_ item: GroceryItem) {
        removeItems([item], message: "\(item.foodName) removed")
    }

    private func prepareUndo(_ removed: [GroceryItem], lines: [CartItem], message: String) {
        undoTask?.cancel()
        deletedItems = removed
        deletedCartLines = lines
        deletedRestock = [:]
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
        deletedRestock = [:]
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
        // A bought row's food is in the kitchen: My Stock keeps it. An unbought row was
        // never bought, so its pack leaves My Stock (and comes back on undo).
        let bought = Set(removed.filter(\.isBought).map(\.id))
        for line in lines {
            let keep = bought.contains(ShoppingCartService.cartRowId(catalogId: line.catalogId, store: line.store))
            let left = cart.removeLine(catalogId: line.catalogId, store: line.store, keepStock: keep)
            if left > 0 { deletedRestock[line.catalogId, default: 0] += left }
        }
        items = GroceryStorage.load().filter { !ids.contains($0.id) }
        saveItems()
    }

    func undoDelete() {
        guard undoGeneration == AppState.shared.dataGeneration else { discardUndo(); return }
        let removed = deletedItems
        let lines = deletedCartLines
        let restock = deletedRestock
        let existingIDs = Set(GroceryStorage.load().map(\.id))
        discardUndo()
        ShoppingCartService.shared.restoreRemovedLines(lines, restock: restock)
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

    /// Bought rows, and how many of them are cart lines (removing those also
    /// takes them out of the cart and the budget total).
    var boughtItems: [GroceryItem] { items.filter(\.isBought) }
    var boughtCartCount: Int { boughtItems.filter { ShoppingCartService.parseCartRowId($0.id) != nil }.count }

    /// Removes every bought row. Cart rows leave the cart too, so the view asks
    /// for confirmation first; an undo toast follows.
    func clearBought() {
        let bought = GroceryStorage.load().filter(\.isBought)
        let noun = bought.count == 1 ? "item" : "items"
        removeItems(bought, message: "\(bought.count) bought \(noun) removed")
    }

    func clearCart() {
        let cart = ShoppingCartService.shared
        guard !cart.cartItems.isEmpty else { return }
        let rows = GroceryStorage.load().filter { ShoppingCartService.parseCartRowId($0.id) != nil }
        prepareUndo(rows, lines: cart.cartItems, message: "Cart cleared")
        deletedRestock = cart.clear()
        loadItems()
    }

    func addItem(_ item: GroceryItem) {
        var latest = GroceryStorage.load()
        latest.append(item)
        GroceryStorage.save(latest)
        items = latest
    }

    func shareText() -> String {
        var lines = ["Nourlo Grocery List", ""]
        for item in items {
            let check = item.isBought ? "[x]" : "[ ]"
            let price = item.priceKnown == false ? "Price unknown" : String(format: "€%.2f", item.estimatedPrice)
            lines.append("\(check) \(item.foodName) (\(item.quantity)) — \(price)")
        }
        lines.append("")
        let label = items.contains { $0.priceKnown == false } ? "Known estimates only" : "Estimated total"
        lines.append(String(format: "\(label): €%.2f", totalEstimatedCost))
        return lines.joined(separator: "\n")
    }
}
