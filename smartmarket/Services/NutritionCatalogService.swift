import Foundation
import Observation

/// Nutrition lookup is independent of AI, account credentials and the grocery backend.
@MainActor @Observable
final class NutritionCatalogService {
    static let shared = NutritionCatalogService()
    static let cacheKey = "nutritionProducts_v1"
    private(set) var foods: [NutritionFood] = []
    private(set) var loadError: String?
    private(set) var savedProducts: [NutritionFood] = []
    private let defaults: UserDefaults
    private let session: URLSession
    private var generation = UUID()
    private var lastSearch: Date?
    private var queryCache: [String: [NutritionFood]] = [:]
    private var queryOrder: [String] = []

    init(defaults: UserDefaults = .standard, session: URLSession? = nil) {
        self.defaults = defaults
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
            .flatMap { try? JSONDecoder().decode([NutritionFood].self, from: $0) } ?? []).filter(\.isValid)
    }
    func clear() {
        generation = UUID()
        savedProducts = []
        queryCache = [:]
        queryOrder = []
        defaults.removeObject(forKey: Self.cacheKey)
    }
    func remember(_ food: NutritionFood) {
        guard food.source == .openFoodFacts, food.isValid else { return }
        savedProducts.removeAll { $0.id == food.id }
        savedProducts.insert(food, at: 0)
        savedProducts = Array(savedProducts.prefix(200))
        if let data = try? JSONEncoder().encode(savedProducts) { defaults.set(data, forKey: Self.cacheKey) }
    }
    func find(_ id: String) -> NutritionFood? { savedProducts.first { $0.id == id } ?? foods.first { $0.id == id } }
    func searchLocal(_ query: String) -> [NutritionFood] {
        NutritionDatabase.search(query, in: savedProducts + foods)
    }

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
    func searchProducts(_ input: String) async throws -> [NutritionFood] {
        let query = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard query.count >= 2, query.count <= 100 else { throw LookupError.invalidQuery }
        let key = query.lowercased()
        if let cached = queryCache[key] { return cached }
        let isBarcode = query.allSatisfy { $0.isASCII && $0.isNumber }
        if isBarcode && ![8, 12, 13, 14].contains(query.count) { throw LookupError.invalidQuery }
        // OFF limits text searches to 10/min/IP. Only explicit submissions make requests.
        if let lastSearch, Date().timeIntervalSince(lastSearch) < 6.1 { throw LookupError.rateLimited }
        lastSearch = Date()
        let fields = "code,product_name,product_name_en,generic_name,brands,nutriments,product_quantity_unit,serving_quantity_unit,nutrition_data_per"
        var parts = URLComponents(string: "https://world.openfoodfacts.org")!
        parts.path = isBarcode ? "/api/v2/product/\(query).json" : "/cgi/search.pl"
        parts.queryItems = [URLQueryItem(name: "fields", value: fields)]
        if !isBarcode {
            parts.queryItems! += [URLQueryItem(name: "search_terms", value: query), URLQueryItem(name: "search_simple", value: "1"),
                URLQueryItem(name: "action", value: "process"), URLQueryItem(name: "json", value: "1"),
                URLQueryItem(name: "page_size", value: "40"), URLQueryItem(name: "page", value: "1")]
        }
        var request = URLRequest(url: parts.url!, timeoutInterval: 20)
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
            if status == 0 { return [] }
            guard status == 1, let product = root["product"] as? [String: Any] else { throw LookupError.invalidResponse }
            // Require an exact identifier. Never fall back to a different name match.
            guard product["code"] as? String == query else { return [] }
            products = [product]
        } else {
            guard let list = root["products"] as? [[String: Any]] else { throw LookupError.invalidResponse }
            products = list
        }
        var ids = Set<String>()
        let result = products.compactMap(NutritionFood.openFoodFacts).filter { ids.insert($0.id).inserted }
        queryCache[key] = result
        queryOrder.append(key)
        if queryOrder.count > 30 { queryCache.removeValue(forKey: queryOrder.removeFirst()) }
        return result
    }
}
