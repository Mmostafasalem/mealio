import Foundation

/// Manages the live product catalog fetched from all Lithuanian markets.
/// The catalog is the authoritative source for the favorites picker.
/// Favorites are matched by product name (case-insensitive) across all stores.
@MainActor
@Observable
final class ProductCatalogService {

    static let shared = ProductCatalogService()
    private init() {
        // Hydrate before a network wait: opening a picker can use saved data immediately.
        if let cached = loadFromDisk(), !cached.isEmpty {
            products = cached
            lastFetch = UserDefaults.standard.object(forKey: fetchedAtKey) as? Date
        }
    }

    // MARK: - State

    private(set) var products: [Product] = []
    private(set) var isLoading = false
    private(set) var error: String?
    private var lastFetch: Date?

    /// All unique category strings present in the loaded catalog.
    var categories: [String] {
        let cats = Set(products.map(\.category)).sorted()
        return ["all"] + cats
    }

    // MARK: - Loading

    /// Loads the catalog from backend if not already loaded or if stale (> 6 h).
    func loadIfNeeded() async {
        if let last = lastFetch, Date().timeIntervalSince(last) < 6 * 3600 && !products.isEmpty {
            return
        }
        await load()
    }

    func load() async {
        guard !isLoading else { return }
        isLoading = true
        error     = nil
        defer { isLoading = false }

        // Try live backend first
        do {
            let fetched = try await APIService.shared.fetchProducts()
            if !fetched.isEmpty {
                products  = fetched
                lastFetch = Date()
                saveToDisk(fetched)
                UserDefaults.standard.set(lastFetch, forKey: fetchedAtKey)
                return
            }
        } catch {
            self.error = "Could not reach the server. Showing cached data."
            appLog("[ProductCatalog] fetch failed:", error)
        }

        // Fall back to disk cache
        if let cached = loadFromDisk(), !cached.isEmpty {
            products  = cached
            // A failed network refresh must not make old data look fresh.
        }
    }

    // MARK: - Search / filter

    func filtered(query: String, category: String) -> [Product] {
        var result = products
        if category != "all" {
            result = result.filter { $0.category == category }
        }
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        if !q.isEmpty {
            result = result.filter { $0.matches(q) }
        }
        return result
    }

    // MARK: - Favorite name matching (for AgentLoop deal notifications)

    /// Returns lowercase name tokens for all favorited items.
    /// Checks live backend products first, then falls back to the static catalog.
    func nameFor(ids: Set<String>) -> [String] {
        var names: [String] = products
            .filter { ids.contains($0.id) }
            .map { $0.nameSlug }
        // Static catalog fallback (covers IDs like "chicken-breast")
        let staticNames: [String] = CatalogItem.all
            .filter { ids.contains($0.id) }
            .map { $0.name.lowercased() }
        for n in staticNames where !names.contains(n) { names.append(n) }
        return names
    }

    /// Returns all products currently favorited.
    func favorited(ids: Set<String>) -> [Product] {
        products.filter { ids.contains($0.id) }
    }

    // MARK: - Disk cache (so favorites picker works offline)

    private let diskKey = "productCatalogCache"
    private let fetchedAtKey = "productCatalogFetchedAt"

    private func saveToDisk(_ products: [Product]) {
        guard let data = try? JSONEncoder().encode(products) else { return }
        UserDefaults.standard.set(data, forKey: diskKey)
    }

    private func loadFromDisk() -> [Product]? {
        guard let data = UserDefaults.standard.data(forKey: diskKey) else { return nil }
        return try? JSONDecoder().decode([Product].self, from: data)
    }
}

// MARK: - Store color helper

extension Product {
    var storeColor: String {
        switch store {
        case "Rimi":   return "#DC2626"
        case "Maxima": return "#0055A5"
        case "Lidl":   return "#0050AA"
        case "Iki":    return "#8B5CF6"
        case "Norfa":  return "#16A34A"
        default:       return "#6B7280"
        }
    }

    var categoryDisplayName: String {
        switch category {
        case "meat":       return "Meat"
        case "fish":       return "Fish"
        case "dairy":      return "Dairy"
        case "eggs":       return "Eggs"
        case "bread":      return "Bread"
        case "vegetables": return "Vegetables"
        case "fruits", "fruit": return "Fruits"
        case "grains":     return "Grains"
        case "legumes":    return "Legumes"
        case "frozen":     return "Frozen"
        case "snacks":     return "Snacks"
        case "beverages":  return "Beverages"
        case "condiments": return "Condiments"
        case "oils":       return "Oils"
        case "spices":     return "Spices"
        case "packaged":   return "Packaged"
        default:           return category.capitalized
        }
    }

    var categorySymbol: String {
        switch category {
        case "meat":       return "fork.knife"
        case "fish":       return "fish.fill"
        case "dairy":      return "drop.fill"
        case "eggs":       return "oval.fill"
        case "bread":      return "birthday.cake.fill"
        case "vegetables": return "leaf.fill"
        case "fruits", "fruit": return "apple.logo"
        case "grains":     return "square.3.layers.3d"
        case "legumes":    return "circle.grid.2x2.fill"
        case "frozen":     return "snowflake"
        case "snacks":     return "popcorn.fill"
        case "beverages":  return "cup.and.saucer.fill"
        case "condiments": return "waterbottle.fill"
        case "oils":       return "drop.triangle.fill"
        case "packaged":   return "shippingbox.fill"
        default:           return "cart.fill"
        }
    }

    var macroSummary: String {
        "P \(Int(proteinPer100g))g · C \(Int(carbsPer100g))g · F \(Int(fatPer100g))g"
    }
}
