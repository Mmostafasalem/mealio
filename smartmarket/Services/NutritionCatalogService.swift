import Foundation
import Observation

/// Nutrition lookup is independent of AI, account credentials and the grocery backend.
@MainActor @Observable
final class NutritionCatalogService {
    static let shared = NutritionCatalogService()
    static let cacheKey = "nutritionProducts_v1"
    static let customKey = "nutritionCustomFoods_v1"
    enum Market: String, CaseIterable, Identifiable {
        case worldwide, lithuania, egypt
        var id: String { rawValue }
        var title: String {
            switch self { case .worldwide: return "Worldwide"; case .lithuania: return "Lithuania"; case .egypt: return "Egypt" }
        }
        var language: String {
            switch self { case .worldwide: return "en"; case .lithuania: return "lt"; case .egypt: return "ar" }
        }
    }
    struct ProductPage {
        let foods: [NutritionFood]
        let hasMore: Bool
    }
    private(set) var foods: [NutritionFood] = []
    private(set) var loadError: String?
    private(set) var savedProducts: [NutritionFood] = []
    private(set) var customFoods: [NutritionFood] = []
    private var index = NutritionSearchIndex(foods: [])
    private var ingredientIndex = NutritionSearchIndex(foods: [])
    private let defaults: UserDefaults
    private let session: URLSession
    private let now: () -> Date
    private var generation = UUID()
    private var lastSearch: Date?
    private var queryCache: [String: ProductPage] = [:]
    private var queryOrder: [String] = []

    init(defaults: UserDefaults = .standard, session: URLSession? = nil, now: @escaping () -> Date = Date.init) {
        self.defaults = defaults
        self.now = now
        let configuration = URLSessionConfiguration.ephemeral
        configuration.urlCache = nil
        configuration.httpCookieStorage = nil
        configuration.urlCredentialStorage = nil
        configuration.httpShouldSetCookies = false
        self.session = session ?? URLSession(configuration: configuration)
        do { foods = try NutritionDatabase.load() }
        catch { loadError = "The offline food database could not be opened. Product search is still available." }
        reloadSaved()
    }
    func reloadSaved() {
        savedProducts = (defaults.data(forKey: Self.cacheKey)
            .flatMap { try? JSONDecoder().decode([NutritionFood].self, from: $0) } ?? [])
            .filter { $0.source == .openFoodFacts && $0.isValid }
        customFoods = (defaults.data(forKey: Self.customKey)
            .flatMap { try? JSONDecoder().decode([NutritionFood].self, from: $0) } ?? [])
            .filter { ($0.source == .menu || $0.source == .recipe) && $0.isValid }
        rebuildIndex()
    }
    private func rebuildIndex() {
        index = NutritionSearchIndex(foods: customFoods + savedProducts + foods)
        ingredientIndex = NutritionSearchIndex(foods: savedProducts + foods)
    }
    func searchIngredients(_ query: String) -> [NutritionFood] { ingredientIndex.search(query) }
    func saveCustom(_ food: NutritionFood) throws {
        guard food.isValid, food.source == .recipe || food.source == .menu else { throw NutritionEntryError.invalidMenu }
        guard customFoods.count < 200 || customFoods.contains(where: { $0.id == food.id }) else { throw NutritionEntryError.tooMany }
        customFoods.removeAll { $0.id == food.id }
        customFoods.insert(food, at: 0)
        try persistCustom()
    }
    func removeCustom(_ id: String) {
        customFoods.removeAll { $0.id == id }
        try? persistCustom()
    }
    private func persistCustom() throws {
        defaults.set(try JSONEncoder().encode(customFoods), forKey: Self.customKey)
        rebuildIndex()
    }
    func clear() {
        generation = UUID()
        savedProducts = []
        customFoods = []
        rebuildIndex()
        queryCache = [:]
        queryOrder = []
        defaults.removeObject(forKey: Self.cacheKey)
        defaults.removeObject(forKey: Self.customKey)
    }
    func remember(_ food: NutritionFood) {
        guard food.source == .openFoodFacts, food.isValid else { return }
        savedProducts.removeAll { $0.id == food.id }
        savedProducts.insert(food, at: 0)
        savedProducts = Array(savedProducts.prefix(200))
        rebuildIndex()
        if let data = try? JSONEncoder().encode(savedProducts) { defaults.set(data, forKey: Self.cacheKey) }
    }
    func find(_ id: String) -> NutritionFood? { customFoods.first { $0.id == id } ?? savedProducts.first { $0.id == id } ?? foods.first { $0.id == id } }
    func searchLocal(_ query: String) -> [NutritionFood] { index.search(query) }

    enum LookupError: LocalizedError {
        case invalidQuery, rateLimited, unavailable, invalidResponse
        var errorDescription: String? {
            switch self {
            case .invalidQuery: return "Enter at least two letters, or an 8–14 digit product barcode."
            case .rateLimited: return "Please wait a few seconds before searching products again."
            case .unavailable: return "Product search is unavailable. You can still search the offline USDA foods and saved products."
            case .invalidResponse: return "The product database returned an unreadable response. Please try again later."
            }
        }
    }
    func searchProducts(_ input: String, market: Market = .worldwide, page: Int = 1) async throws -> [NutritionFood] {
        try await fetchProducts(input, market: market, page: page).foods
    }
    func fetchProducts(_ input: String, market: Market = .worldwide, page: Int = 1, retailer: String? = nil) async throws -> ProductPage {
        let query = input.trimmingCharacters(in: .whitespacesAndNewlines)
        let storeTag = retailer?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard (query.count >= 2 || (query.isEmpty && !(storeTag ?? "").isEmpty)), query.count <= 100,
              (storeTag?.count ?? 0) <= 100, (1...1000).contains(page) else { throw LookupError.invalidQuery }
        let isBarcode = !query.isEmpty && query.allSatisfy { $0.isASCII && $0.isNumber }
        if isBarcode && ![8, 12, 13, 14].contains(query.count) { throw LookupError.invalidQuery }
        let newTextSearch = !isBarcode && storeTag == nil
        let structured = query.isEmpty && storeTag != nil
        let keyPrefix = "retailer:" + (storeTag ?? "") + ":"
        let key = keyPrefix + (isBarcode ? "barcode:" + market.language + ":" + query : market.rawValue + ":" + String(page) + ":" + query.lowercased())
        if let cached = queryCache[key] { return cached }
        // OFF limits text searches to 10/min/IP. Only explicit submissions make requests.
        let timestamp = now()
        if let lastSearch, timestamp.timeIntervalSince(lastSearch) < 6.1 { throw LookupError.rateLimited }
        lastSearch = timestamp
        let fields = "code,product_name,product_name_en,product_name_lt,product_name_ar,generic_name,brands,quantity,nutriments,product_quantity_unit,serving_quantity_unit,nutrition_data_per,stores_tags,countries_tags"
        var parts = URLComponents(string: "https://world.openfoodfacts.org")!
        parts.path = isBarcode ? "/api/v2/product/\(query).json" : (structured ? "/api/v2/search" : "/cgi/search.pl")
        parts.queryItems = [URLQueryItem(name: "fields", value: fields)]
        if !isBarcode {
            parts.queryItems! += [URLQueryItem(name: "search_terms", value: query), URLQueryItem(name: "search_simple", value: "1"),
                URLQueryItem(name: "action", value: "process"), URLQueryItem(name: "json", value: "1"),
                URLQueryItem(name: "page_size", value: "40"), URLQueryItem(name: "page", value: String(page)), URLQueryItem(name: "lc", value: market.language)]
        }
        if structured {
            parts.queryItems!.removeAll { ["search_terms", "search_simple", "action", "json"].contains($0.name) }
            parts.queryItems!.append(URLQueryItem(name: "stores_tags", value: storeTag))
            if market != .worldwide { parts.queryItems!.append(URLQueryItem(name: "countries_tags", value: "en:" + market.rawValue)) }
        } else if !isBarcode, let storeTag, !storeTag.isEmpty {
            parts.queryItems! += [URLQueryItem(name: "tagtype_1", value: "stores"), URLQueryItem(name: "tag_contains_1", value: "contains"), URLQueryItem(name: "tag_1", value: storeTag)]
        }
        if !structured, !isBarcode, market != .worldwide {
            parts.queryItems! += [URLQueryItem(name: "tagtype_0", value: "countries"),
                                  URLQueryItem(name: "tag_contains_0", value: "contains"),
                                  URLQueryItem(name: "tag_0", value: "en:" + market.rawValue)]
        }
        var request = URLRequest(url: parts.url!, timeoutInterval: 20)
        if newTextSearch {
            func literal(_ value: String) -> String {
                "\"" + value.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"") + "\""
            }
            // The service treats plain text and explicit taxonomy filters
            // differently. Remove query operators from user input, and enforce
            // selected country again on returned records.
            var search = query.components(separatedBy: CharacterSet.alphanumerics.inverted)
                .filter { !$0.isEmpty }.joined(separator: " ").lowercased()
            guard !search.isEmpty else { throw LookupError.invalidQuery }
            if market != .worldwide { search += " countries_tags:" + literal("en:" + market.rawValue) }
            request = URLRequest(url: URL(string: "https://search.openfoodfacts.org/search")!, timeoutInterval: 20)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONSerialization.data(withJSONObject: ["q": search, "page": page, "page_size": 40,
                                                                         "langs": Array(Set([market.language, "en"])).sorted(),
                                                                         "fields": fields.components(separatedBy: ",")])
        }
        request.setValue("Nourlo/1.0 (https://github.com/Mmostafasalem/mealio)", forHTTPHeaderField: "User-Agent")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let requestGeneration = generation
        let (data, response) = try await session.data(for: request)
        try Task.checkCancellation()
        guard generation == requestGeneration else { throw CancellationError() }
        guard let response = response as? HTTPURLResponse else { throw LookupError.invalidResponse }
        if response.statusCode == 429 { throw LookupError.rateLimited }
        guard response.statusCode == 200 else { throw LookupError.unavailable }
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { throw LookupError.invalidResponse }
        let products: [[String: Any]]
        if isBarcode {
            guard let status = root["status"] as? Int else { throw LookupError.invalidResponse }
            if status == 0 { return ProductPage(foods: [], hasMore: false) }
            guard status == 1, let product = root["product"] as? [String: Any] else { throw LookupError.invalidResponse }
            // Require an exact identifier. Never fall back to a different name match.
            guard product["code"] as? String == query else { return ProductPage(foods: [], hasMore: false) }
            products = [product]
        } else {
            if newTextSearch {
                guard root["timed_out"] as? Bool != true,
                      (root["errors"] as? [Any] ?? []).isEmpty,
                      let list = root["hits"] as? [[String: Any]] else { throw LookupError.invalidResponse }
                products = list
            } else {
                guard let list = root["products"] as? [[String: Any]] else { throw LookupError.invalidResponse }
                products = list
            }
        }
        var ids = Set<String>()
        let scopedProducts = products.filter { product in
            if newTextSearch, market != .worldwide,
               !(product["countries_tags"] as? [String] ?? []).contains("en:" + market.rawValue) { return false }
            guard let storeTag, !storeTag.isEmpty else { return true }
            return (product["stores_tags"] as? [String] ?? []).contains(storeTag)
        }
        let result = scopedProducts.compactMap { NutritionFood.openFoodFacts($0, language: market.language) }.filter { ids.insert($0.id).inserted }
        let count = root["count"] as? Int
        let hasMore = !isBarcode && (count.map { $0 > page * 40 } ?? (products.count == 40))
        let output = ProductPage(foods: result, hasMore: hasMore)
        queryCache[key] = output
        queryOrder.append(key)
        if queryOrder.count > 30 { queryCache.removeValue(forKey: queryOrder.removeFirst()) }
        return output
    }
}
