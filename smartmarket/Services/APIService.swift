import Foundation

@MainActor
final class APIService {

    static let shared = APIService()
    private let session: URLSession
    private let authorization: @MainActor () throws -> String
    init(session: URLSession = .shared,
         authorization: (@MainActor () throws -> String)? = nil) {
        self.session = session
        self.authorization = authorization ?? { try AIAccountService.shared.authorization() }
    }

    private let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.keyDecodingStrategy = .useDefaultKeys
        return d
    }()

    // MARK: - Product catalog (all markets, with/without discount)

    func fetchProducts(store: String? = nil, category: String? = nil, query: String? = nil) async throws -> [Product] {
        var path = Constants.API.Endpoint.products
        var params: [String] = []
        if let store    = store,    !store.isEmpty    { params.append("store=\(store)") }
        if let category = category, !category.isEmpty { params.append("category=\(category)") }
        if let query    = query,    !query.isEmpty    { params.append("q=\(query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? query)") }
        if !params.isEmpty { path += "?" + params.joined(separator: "&") }
        let req = try get(path)
        let (data, response) = try await session.data(for: req)
        try validateResponse(response)
        return try decoder.decode([Product].self, from: data)
    }

    // MARK: - Health

    func checkHealth() async throws -> Bool {
        let req = try get(Constants.API.Endpoint.health)
        let (_, response) = try await session.data(for: req)
        return (response as? HTTPURLResponse)?.statusCode == 200
    }

    // MARK: - Deals

    func getDeals() async throws -> [Deal] {
        do {
            let req = try get(Constants.API.Endpoint.deals)
            let (data, response) = try await session.data(for: req)
            try validateResponse(response)
            let deals = try decoder.decode([Deal].self, from: data)
            return deals.isEmpty ? FallbackData.deals : deals
        } catch {
            appLog("[API] getDeals failed — using offline fallback:", error)
            return FallbackData.deals
        }
    }

    /// Fetches deals pre-filtered by proximity on the backend.
    func getDeals(near lat: Double, lon: Double, radiusKm: Double = 8) async throws -> [Deal] {
        do {
            let path = Constants.API.Endpoint.deals + "?lat=\(lat)&lon=\(lon)&radius=\(radiusKm)"
            let req = try get(path)
            let (data, response) = try await session.data(for: req)
            try validateResponse(response)
            let deals = try decoder.decode([Deal].self, from: data)
            return deals.isEmpty ? FallbackData.deals : deals
        } catch {
            appLog("[API] getDeals(near:) failed — using offline fallback:", error)
            return FallbackData.deals
        }
    }

    // MARK: - BMR

    func calculateBMR(_ request: BMRRequest) async throws -> BMRResponse {
        do {
            let req = try post(Constants.API.Endpoint.bmr, body: request, timeout: 15)
            let (data, response) = try await session.data(for: req)
            try validateResponse(response)
            return try decoder.decode(BMRResponse.self, from: data)
        } catch {
            appLog("[API] calculateBMR failed — using local Mifflin-St Jeor fallback:", error)
            return FallbackData.bmr(for: request)
        }
    }

    // MARK: - Meal Plan (AI — allow up to 60s)

    func generateMealPlan(_ request: MealPlanRequest) async throws -> WeeklyMealPlan {
        do {
            let req = try post(Constants.API.Endpoint.mealPlan, body: request, timeout: 60)
            let (data, response) = try await session.data(for: req)
            try validateResponse(response)
            return try decoder.decode(WeeklyMealPlan.self, from: data)
        } catch {
            appLog("[API] generateMealPlan failed — using offline fallback:", error)
            let target: Int
            switch request.goal {
            case "lose": target = request.bmrData.loseCalories
            case "gain": target = request.bmrData.gainCalories
            default:     target = request.bmrData.maintainCalories
            }
            return FallbackData.mealPlan(targetKcal: target, pantry: request.groceryList)
        }
    }

    // MARK: - Gap Fillers (AI)

    func getGapFillers(_ request: GapFillerRequest) async throws -> [GapFiller] {
        let req = try post(Constants.API.Endpoint.gapFillers, body: request, timeout: 30)
        let (data, response) = try await session.data(for: req)
        try validateResponse(response)
        return try decoder.decode([GapFiller].self, from: data)
    }

    // MARK: - Shopping Advice (AI)

    func getShoppingAdvice(_ request: ShoppingAdviceRequest) async throws -> [ShoppingAdvice] {
        let req = try post(Constants.API.Endpoint.shoppingAdvice, body: request, timeout: 30)
        let (data, response) = try await session.data(for: req)
        try validateResponse(response)
        return try decoder.decode([ShoppingAdvice].self, from: data)
    }

    func agentChat(_ request: AgentChatRequest) async throws -> AgentChatResponse {
        let req = try post(Constants.API.Endpoint.agentChat, body: request, timeout: 30)
        let (data, response) = try await session.data(for: req)
        try validateResponse(response)
        return try decoder.decode(AgentChatResponse.self, from: data)
    }

    func fetchRecipe(mealName: String) async throws -> Recipe {
        guard UserDefaults.standard.bool(forKey: "aiSharingConsent_v1") else { throw APIError.aiConsentRequired }
        do {
            let req = try post(Constants.API.Endpoint.recipe,
                               body: RecipeRequest(mealName: mealName), timeout: 30)
            let (data, response) = try await session.data(for: req)
            try validateResponse(response)
            return try decoder.decode(Recipe.self, from: data)
        } catch {
            appLog("[API] fetchRecipe failed — using offline fallback:", error)
            return Recipe(
                mealName: mealName, prepTime: 10, cookTime: 20, servings: 2,
                ingredients: [RecipeIngredient(name: mealName, amount: "1 serving")],
                steps: ["Prep your ingredients.", "Cook until done.", "Season to taste and serve."],
                tip: "Connect to the internet for an AI-tailored recipe."
            )
        }
    }

    // MARK: - Legacy shims (used by HomeViewModel / GroceryListViewModel)

    // Vilnius store coordinates keyed by lowercased chain name. Used only as a
    // fallback when the backend omits per-product lat/lon. The five real chains
    // are kept in sync with the backend's STORES table (app.py) so the map pins
    // agree whichever source supplies them.
    static let storeCoordinates: [String: (lat: Double, lon: Double)] = [
        "maxima":     (54.6872, 25.2797),
        "rimi":       (54.6989, 25.2730),
        "iki":        (54.6750, 25.2800),
        "lidl":       (54.6680, 25.2750),
        "norfa":      (54.7100, 25.2600),
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

    /// GET request with API key header.
    private func get(_ path: String) throws -> URLRequest {
        guard let url = URL(string: Constants.API.baseURL + path) else {
            throw APIError.invalidURL
        }
        var req = URLRequest(url: url)
        req.timeoutInterval = 15
        if !Constants.API.appKey.isEmpty {
            req.setValue(Constants.API.appKey, forHTTPHeaderField: "X-API-Key")
        }
        return req
    }

    /// POST request with JSON body, timeout, and API key header.
    private func post<T: Encodable>(_ path: String, body: T, timeout: TimeInterval) throws -> URLRequest {
        if path != Constants.API.Endpoint.bmr && !UserDefaults.standard.bool(forKey: "aiSharingConsent_v1") {
            throw APIError.aiConsentRequired
        }
        guard let url = URL(string: Constants.API.baseURL + path) else {
            throw APIError.invalidURL
        }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if !Constants.API.appKey.isEmpty {
            req.setValue(Constants.API.appKey, forHTTPHeaderField: "X-API-Key")
        }
        if path != Constants.API.Endpoint.bmr {
            req.setValue(try authorization(), forHTTPHeaderField: "Authorization")
        }
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
        AIAccountService.shared.acceptHeaders(http)
        switch http.value(forHTTPHeaderField: "X-AI-Error") {
        case "ai_sign_in_required": throw AIAccountError.signInRequired
        case "ai_quota_exceeded": throw AIAccountError.quota(http.value(forHTTPHeaderField: "X-AI-Reset"))
        case "ai_shared_capacity": throw AIAccountError.sharedCapacity
        case "ai_unavailable": throw AIAccountError.unavailable
        default: break
        }
        guard (200..<300).contains(http.statusCode) else {
            throw APIError.httpError(http.statusCode)
        }
    }
}

// MARK: - Errors

enum APIError: LocalizedError {
    case aiConsentRequired
    case invalidURL
    case noResponse
    case httpError(Int)

    var errorDescription: String? {
        switch self {
        case .aiConsentRequired: return "Online AI sharing is off. You can enable it in Profile after reviewing the Privacy Policy."
        case .invalidURL:       return "Invalid API URL."
        case .noResponse:       return "No response from server."
        case .httpError(let c): return "Server error \(c)."
        }
    }
}
