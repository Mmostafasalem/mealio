import Foundation

actor APIService {

    static let shared = APIService()
    private init() {}

    private let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.keyDecodingStrategy = .useDefaultKeys
        return d
    }()

    // MARK: - Health

    func checkHealth() async throws -> Bool {
        let req = try await get(Constants.API.Endpoint.health)
        let (_, response) = try await URLSession.shared.data(for: req)
        return (response as? HTTPURLResponse)?.statusCode == 200
    }

    // MARK: - Deals

    func getDeals() async throws -> [Deal] {
        let req = try get(Constants.API.Endpoint.deals)
        let (data, response) = try await URLSession.shared.data(for: req)
        try validateResponse(response)
        return try decoder.decode([Deal].self, from: data)
    }

    /// Fetches deals pre-filtered by proximity on the backend.
    func getDeals(near lat: Double, lon: Double, radiusKm: Double = 8) async throws -> [Deal] {
        let path = Constants.API.Endpoint.deals + "?lat=\(lat)&lon=\(lon)&radius=\(radiusKm)"
        let req = try get(path)
        let (data, response) = try await URLSession.shared.data(for: req)
        try validateResponse(response)
        return try decoder.decode([Deal].self, from: data)
    }

    // MARK: - BMR

    func calculateBMR(_ request: BMRRequest) async throws -> BMRResponse {
        let req = try post(Constants.API.Endpoint.bmr, body: request, timeout: 15)
        let (data, response) = try await URLSession.shared.data(for: req)
        try validateResponse(response)
        return try decoder.decode(BMRResponse.self, from: data)
    }

    // MARK: - Meal Plan (AI — allow up to 60s)

    func generateMealPlan(_ request: MealPlanRequest) async throws -> WeeklyMealPlan {
        let req = try post(Constants.API.Endpoint.mealPlan, body: request, timeout: 60)
        let (data, response) = try await URLSession.shared.data(for: req)
        try validateResponse(response)
        return try decoder.decode(WeeklyMealPlan.self, from: data)
    }

    // MARK: - Gap Fillers (AI)

    func getGapFillers(_ request: GapFillerRequest) async throws -> [GapFiller] {
        let req = try post(Constants.API.Endpoint.gapFillers, body: request, timeout: 30)
        let (data, response) = try await URLSession.shared.data(for: req)
        try validateResponse(response)
        return try decoder.decode([GapFiller].self, from: data)
    }

    // MARK: - Shopping Advice (AI)

    func getShoppingAdvice(_ request: ShoppingAdviceRequest) async throws -> [ShoppingAdvice] {
        let req = try post(Constants.API.Endpoint.shoppingAdvice, body: request, timeout: 30)
        let (data, response) = try await URLSession.shared.data(for: req)
        try validateResponse(response)
        return try decoder.decode([ShoppingAdvice].self, from: data)
    }

    // MARK: - Legacy shims (used by HomeViewModel / GroceryListViewModel)

    // Vilnius store coordinates keyed by lowercased chain name.
    static let storeCoordinates: [String: (lat: Double, lon: Double)] = [
        "maxima":     (54.7154, 25.2539),
        "iki":        (54.6891, 25.2012),
        "rimi":       (54.6634, 25.2897),
        "lidl":       (54.7032, 25.2205),
        "norfa":      (54.7021, 25.3221),
        "barbora":    (54.6872, 25.2797),
        "senukai":    (54.6960, 25.2690),
        "prisma":     (54.6920, 25.2750),
    ]

    /// Fetches live deals and converts them to MarketDeal for existing UI.
    func fetchMarketDeals() async throws -> [MarketDeal] {
        let deals = try await getDeals()
        return deals.map { d in
            let key = d.store.lowercased()
            let fallback = Self.storeCoordinates[key] ?? (54.6872, 25.2797)
            let lat = d.latitude ?? fallback.lat
            let lon = d.longitude ?? fallback.lon
            let store = Store(
                id: key,
                chain: d.store,
                name: d.store,
                address: "",
                latitude: lat,
                longitude: lon
            )
            let expiryDate: Date = {
                if d.expiresIn.lowercased() == "today" {
                    return Calendar.current.startOfDay(for: Date()).addingTimeInterval(86399)
                }
                return Date().addingTimeInterval(7 * 86400)
            }()
            return MarketDeal(
                id: "\(d.id)",
                store: store,
                productId: "\(d.id)",
                productName: d.name,
                originalPrice: d.originalPrice,
                discountPrice: d.discountedPrice,
                discountPercent: d.discount,
                validUntil: expiryDate,
                dealType: .weeklySpecial,
                quantity: "\(d.weeklyQty) \(d.unit)"
            )
        }
    }

    // MARK: - Helpers

    /// GET request pre-stamped with the ngrok bypass header.
    private func get(_ path: String) throws -> URLRequest {
        guard let url = URL(string: Constants.API.baseURL + path) else {
            throw APIError.invalidURL
        }
        var req = URLRequest(url: url)
        req.timeoutInterval = 15
        req.setValue("true", forHTTPHeaderField: "ngrok-skip-browser-warning")
        return req
    }

    /// POST request with JSON body, timeout, and ngrok bypass header.
    private func post<T: Encodable>(_ path: String, body: T, timeout: TimeInterval) throws -> URLRequest {
        guard let url = URL(string: Constants.API.baseURL + path) else {
            throw APIError.invalidURL
        }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("true", forHTTPHeaderField: "ngrok-skip-browser-warning")
        req.httpBody = try JSONEncoder().encode(body)
        req.timeoutInterval = timeout
        return req
    }

    /// Returns coordinates for a store name (case-insensitive), defaulting to Vilnius centre.
    static func storeCoordinates(for storeName: String) -> (lat: Double, lon: Double) {
        storeCoordinates[storeName.lowercased()] ?? (54.6872, 25.2797)
    }

    private func validateResponse(_ response: URLResponse) throws {
        guard let http = response as? HTTPURLResponse else { throw APIError.noResponse }
        guard (200..<300).contains(http.statusCode) else {
            throw APIError.httpError(http.statusCode)
        }
    }
}

// MARK: - Errors

enum APIError: LocalizedError {
    case invalidURL
    case noResponse
    case httpError(Int)

    var errorDescription: String? {
        switch self {
        case .invalidURL:       return "Invalid API URL."
        case .noResponse:       return "No response from server."
        case .httpError(let c): return "Server error \(c)."
        }
    }
}
