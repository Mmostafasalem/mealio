import XCTest
@testable import smartmarket

private final class NutritionTestProtocol: URLProtocol {
    static var body = Data()
    static var status = 200
    static var requests: [URLRequest] = []
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        Self.requests.append(request)
        let response = HTTPURLResponse(url: request.url!, statusCode: Self.status, httpVersion: nil, headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Self.body)
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}

@MainActor
final class NutritionLookupTests: XCTestCase {
    private var defaults: UserDefaults!
    private var suite: String!
    private var session: URLSession!
    override func setUp() async throws {
        suite = "NutritionLookupTests." + UUID().uuidString
        defaults = UserDefaults(suiteName: suite)!
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [NutritionTestProtocol.self]
        session = URLSession(configuration: config)
        NutritionTestProtocol.requests = []
        NutritionTestProtocol.status = 200
    }
    override func tearDown() async throws {
        defaults.removePersistentDomain(forName: suite)
        session.invalidateAndCancel()
    }
    private var product: [String: Any] {
        ["code": "12345678", "product_name": "Example yogurt", "brands": "Example", "serving_quantity_unit": "g",
         "nutriments": ["energy-kcal_100g": 80, "proteins_100g": 4.25, "carbohydrates_100g": 5.5, "fat_100g": 2.5]]
    }
    func testExplicitSearchSendsOnlyQueryAndCachesRepeatedLookup() async throws {
        NutritionTestProtocol.body = try JSONSerialization.data(withJSONObject: ["products": [product]])
        let catalog = NutritionCatalogService(defaults: defaults, session: session)
        let first = try await catalog.searchProducts("Example yogurt")
        XCTAssertEqual(first.count, 1)
        let repeated = try await catalog.searchProducts("Example yogurt")
        XCTAssertEqual(repeated, first)
        XCTAssertEqual(NutritionTestProtocol.requests.count, 1)
        let req = try XCTUnwrap(NutritionTestProtocol.requests.first)
        XCTAssertEqual(req.url?.host, "world.openfoodfacts.org")
        XCTAssertEqual(req.url?.path, "/cgi/search.pl")
        XCTAssertNil(req.httpBody)
        XCTAssertNil(req.value(forHTTPHeaderField: "Authorization"))
        XCTAssertNil(req.value(forHTTPHeaderField: "X-API-Key"))
        XCTAssertTrue(req.value(forHTTPHeaderField: "User-Agent")?.contains("Nourlo") == true)
        do { _ = try await catalog.searchProducts("another food"); XCTFail("Rapid uncached requests must be limited") }
        catch NutritionCatalogService.LookupError.rateLimited { }
    }
    func testSelectedProductsSurviveRestartAndClearWithDataDeletion() async throws {
        let food = try XCTUnwrap(NutritionFood.openFoodFacts(product))
        let catalog = NutritionCatalogService(defaults: defaults, session: session)
        catalog.remember(food)
        let reopened = NutritionCatalogService(defaults: defaults, session: session)
        XCTAssertEqual(reopened.find(food.id), food)
        XCTAssertEqual(reopened.searchLocal("Example yogurt").first, food)
        reopened.clear()
        XCTAssertNil(defaults.data(forKey: NutritionCatalogService.cacheKey))
        XCTAssertNil(reopened.find(food.id))
        XCTAssertFalse(reopened.searchLocal("apples raw").isEmpty)
    }
    func testBarcodeNeverFallsBackToAnotherProduct() async throws {
        NutritionTestProtocol.body = try JSONSerialization.data(withJSONObject: ["status": 1, "product": product])
        let catalog = NutritionCatalogService(defaults: defaults, session: session)
        let result = try await catalog.searchProducts("87654321")
        XCTAssertTrue(result.isEmpty)
        XCTAssertEqual(NutritionTestProtocol.requests.first?.url?.path, "/api/v2/product/87654321.json")
    }
    func testProviderRateLimitIsExplicitAndNotEmptySuccess() async throws {
        NutritionTestProtocol.status = 429
        NutritionTestProtocol.body = Data("{}".utf8)
        let catalog = NutritionCatalogService(defaults: defaults, session: session)
        do { _ = try await catalog.searchProducts("yogurt"); XCTFail("Must report rate limit") }
        catch NutritionCatalogService.LookupError.rateLimited { }
        XCTAssertFalse(catalog.searchLocal("chicken breast").isEmpty)
    }
    func testMalformedSuccessIsNotReportedAsNoMatches() async throws {
        NutritionTestProtocol.body = Data("{}".utf8)
        let catalog = NutritionCatalogService(defaults: defaults, session: session)
        do { _ = try await catalog.searchProducts("yogurt"); XCTFail("Missing products is a provider error") }
        catch NutritionCatalogService.LookupError.invalidResponse { }
    }
    func testMarketPaginationAndLanguageStaySeparateInCache() async throws {
        var raw = product
        raw["product_name_ar"] = "زبادي"
        raw["product_name_lt"] = "Jogurtas"
        NutritionTestProtocol.body = try JSONSerialization.data(withJSONObject: ["products": [raw], "count": 81])
        var clock = Date()
        let catalog = NutritionCatalogService(defaults: defaults, session: session, now: { clock })
        let egypt = try await catalog.fetchProducts("yogurt", market: .egypt)
        XCTAssertEqual(egypt.foods.first?.name, "زبادي")
        XCTAssertTrue(egypt.hasMore)
        func parameters() throws -> [String: String] {
            let url = try XCTUnwrap(NutritionTestProtocol.requests.last?.url)
            return Dictionary(uniqueKeysWithValues: URLComponents(url: url, resolvingAgainstBaseURL: false)!.queryItems!.map { ($0.name, $0.value ?? "") })
        }
        XCTAssertEqual(try parameters()["tag_0"], "en:egypt")
        XCTAssertEqual(try parameters()["lc"], "ar")
        clock.addTimeInterval(7)
        let lithuania = try await catalog.fetchProducts("yogurt", market: .lithuania)
        XCTAssertEqual(lithuania.foods.first?.name, "Jogurtas")
        XCTAssertEqual(try parameters()["tag_0"], "en:lithuania")
        clock.addTimeInterval(7)
        _ = try await catalog.fetchProducts("yogurt", market: .egypt, page: 2)
        XCTAssertEqual(try parameters()["page"], "2")
        XCTAssertEqual(NutritionTestProtocol.requests.count, 3)
        _ = try await catalog.fetchProducts("yogurt", market: .egypt)
        XCTAssertEqual(NutritionTestProtocol.requests.count, 3)
    }
    func testBarcodeIsNotRestrictedBySelectedCountry() async throws {
        NutritionTestProtocol.body = try JSONSerialization.data(withJSONObject: ["status": 1, "product": product])
        let catalog = NutritionCatalogService(defaults: defaults, session: session)
        let result = try await catalog.fetchProducts("12345678", market: .egypt)
        XCTAssertEqual(result.foods.count, 1)
        XCTAssertFalse(result.hasMore)
        let url = try XCTUnwrap(NutritionTestProtocol.requests.last?.url)
        XCTAssertFalse(URLComponents(url: url, resolvingAgainstBaseURL: false)!.queryItems!.contains { $0.name == "tag_0" })
    }

}
