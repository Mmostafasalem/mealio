import XCTest
@testable import smartmarket

private final class BarcodeStubProtocol: URLProtocol {
    nonisolated(unsafe) static var responses: [String: (Int, Data)] = [:]
    nonisolated(unsafe) static var requests: [URLRequest] = []
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        Self.requests.append(request)
        let path = request.url?.path ?? ""
        let (status, body) = Self.responses[path] ?? (404, Data(#"{"status":0}"#.utf8))
        let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: body)
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}

@MainActor
final class PolishTests: XCTestCase {

    // MARK: GTIN

    func testCheckDigitsOfRealCodes() {
        XCTAssertTrue(GTIN.hasValidCheckDigit("5901234123457"))   // EAN-13
        XCTAssertTrue(GTIN.hasValidCheckDigit("96385074"))        // EAN-8
        XCTAssertTrue(GTIN.hasValidCheckDigit("036000291452"))    // UPC-A
        XCTAssertTrue(GTIN.hasValidCheckDigit("10012345678902"))  // GTIN-14
        XCTAssertFalse(GTIN.hasValidCheckDigit("5901234123458"))
        XCTAssertFalse(GTIN.hasValidCheckDigit("59012341234"))
        XCTAssertFalse(GTIN.hasValidCheckDigit("590123412345A"))
    }

    func testNormalizeRejectsJunkAndWrongCheckDigits() {
        XCTAssertEqual(GTIN.normalize(" 5901234123457\n"), "5901234123457")
        XCTAssertNil(GTIN.normalize("5901234123450"))
        XCTAssertNil(GTIN.normalize("12345"))
        XCTAssertNil(GTIN.normalize("https://example.com"))
        XCTAssertNil(GTIN.normalize(""))
    }

    func testUPCEExpandsToUPCA() {
        XCTAssertEqual(GTIN.expandUPCE("01234565"), "012345000065")
        XCTAssertEqual(GTIN.expandUPCE("04252614"), "042100005264")
        // The scanner's symbology decides between a valid EAN-8 and a valid UPC-E.
        XCTAssertEqual(GTIN.normalize("01234565", symbology: .upce), "012345000065")
        XCTAssertEqual(GTIN.normalize("01234565", symbology: .ean8), "01234565")
        // Six-digit UPC-E bodies get number system 0 and their check digit.
        XCTAssertEqual(GTIN.normalize("123456", symbology: .upce), "012345000065")
        XCTAssertNil(GTIN.expandUPCE("21234565"))
    }

    func testEAN8WithABadCheckDigitIsNotReadAsUPCE() {
        // A code that is a valid UPC-E but fails the EAN-8 check.
        let upceOnly = "04252614"
        XCTAssertFalse(GTIN.hasValidCheckDigit(upceOnly))
        XCTAssertNotNil(GTIN.expandUPCE(upceOnly).flatMap { GTIN.hasValidCheckDigit($0) ? $0 : nil })
        // Read as EAN-8, a failed check is a misread: never another product.
        XCTAssertNil(GTIN.normalize(upceOnly, symbology: .ean8))
        // Read as UPC-E, or unknown, it is still the UPC-E product.
        XCTAssertEqual(GTIN.normalize(upceOnly, symbology: .upce), "042100005264")
        XCTAssertEqual(GTIN.normalize(upceOnly), "042100005264")
        XCTAssertEqual(GTIN.normalize("96385074", symbology: .ean8), "96385074")
    }

    func testUPCALooksUpAsEAN13First() {
        XCTAssertEqual(BarcodeLookupService.lookupCodes(for: "036000291452"), ["0036000291452", "036000291452"])
        XCTAssertEqual(BarcodeLookupService.lookupCodes(for: "5901234123457"), ["5901234123457"])
    }

    func testRequestSendsOnlyTheBarcode() throws {
        let url = try XCTUnwrap(BarcodeLookupService.requestURL(for: "5901234123457"))
        XCTAssertEqual(url.host, "world.openfoodfacts.org")
        XCTAssertEqual(url.path, "/api/v2/product/5901234123457.json")
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        XCTAssertEqual(items.map(\.name), ["fields"])
    }

    // MARK: Parsing

    private func product(_ nutriments: String, extra: String = "") -> Data {
        Data("""
        {"code":"5901234123457","status":1,"product":{"code":"5901234123457","product_name":"Oat flakes",
        "brands":"Good Mill, Other","serving_size":"40 g"\(extra),"nutriments":{\(nutriments)}}}
        """.utf8)
    }

    func testParsesPer100GramValues() throws {
        let data = product(#""energy-kcal_100g":372,"proteins_100g":13.5,"carbohydrates_100g":58.7,"fat_100g":7"#)
        let food = try XCTUnwrap(BarcodeLookupService.parse(data, code: "5901234123457"))
        XCTAssertEqual(food.name, "Oat flakes")
        XCTAssertEqual(food.brand, "Good Mill")
        XCTAssertEqual(food.basis, .grams)
        XCTAssertEqual(food.kcal, 372)
        XCTAssertEqual(food.protein, 13.5)
        XCTAssertEqual(food.carbs, 58.7)
        XCTAssertEqual(food.fat, 7)
        XCTAssertEqual(food.id, "off:5901234123457")
        XCTAssertEqual(food.source, .openFoodFacts)
    }

    func testConvertsKilojoulesAndStringNumbers() throws {
        let data = product(#""energy-kj_100g":"1556","proteins_100g":"13,5","carbohydrates_100g":58.7,"fat_100g":7"#)
        let food = try XCTUnwrap(BarcodeLookupService.parse(data, code: "5901234123457"))
        XCTAssertEqual(food.kcal, 1556 / 4.184, accuracy: 0.01)
        XCTAssertEqual(food.protein, 13.5)
    }

    func testDrinksArePer100Millilitres() throws {
        let data = product(#""energy-kcal_100g":42,"proteins_100g":0,"carbohydrates_100g":10.6,"fat_100g":0"#,
                           extra: #","quantity":"330 ml""#)
        XCTAssertEqual(try XCTUnwrap(BarcodeLookupService.parse(data, code: "5901234123457")).basis, .millilitres)
    }

    func testRejectsMissingValues() {
        XCTAssertNil(BarcodeLookupService.parse(product(#""energy-kcal_100g":372,"proteins_100g":13.5,"fat_100g":7"#),
                                                code: "5901234123457"))
        XCTAssertNil(BarcodeLookupService.parse(product(#""proteins_100g":1,"carbohydrates_100g":1,"fat_100g":1"#),
                                                code: "5901234123457"))
        XCTAssertNil(BarcodeLookupService.parse(Data(#"{"status":0,"status_verbose":"product not found"}"#.utf8),
                                                code: "5901234123457"))
        XCTAssertNil(BarcodeLookupService.parse(Data("not json".utf8), code: "5901234123457"))
    }

    func testRejectsAbsurdValues() {
        for nutriments in [
            #""energy-kcal_100g":3720,"proteins_100g":13,"carbohydrates_100g":58,"fat_100g":7"#,   // > 900 kcal
            #""energy-kcal_100g":-5,"proteins_100g":13,"carbohydrates_100g":58,"fat_100g":7"#,     // negative
            #""energy-kcal_100g":372,"proteins_100g":130,"carbohydrates_100g":5,"fat_100g":7"#,    // > 100 g
            #""energy-kcal_100g":800,"proteins_100g":60,"carbohydrates_100g":60,"fat_100g":10"#,   // macros > 100 g
            #""energy-kcal_100g":10,"proteins_100g":20,"carbohydrates_100g":50,"fat_100g":20"#,    // energy far below macros
            #""energy-kcal_100g":true,"proteins_100g":1,"carbohydrates_100g":1,"fat_100g":1"#,     // boolean
        ] {
            XCTAssertNil(BarcodeLookupService.parse(product(nutriments), code: "5901234123457"), nutriments)
        }
        // Spirits: energy from alcohol, no macros. Plausible.
        XCTAssertNotNil(BarcodeLookupService.per100(["energy-kcal_100g": 231, "proteins_100g": 0, "carbohydrates_100g": 0, "fat_100g": 0]))
    }

    func testRejectsADifferentProductCode() {
        let data = product(#""energy-kcal_100g":372,"proteins_100g":13.5,"carbohydrates_100g":58.7,"fat_100g":7"#)
        XCTAssertNil(BarcodeLookupService.parse(data, code: "4006381333931"))
    }

    func testMissingNameFallsBackToBrandOrCode() throws {
        let data = Data("""
        {"status":1,"product":{"code":"5901234123457","nutriments":{"energy-kcal_100g":100,"proteins_100g":1,"carbohydrates_100g":20,"fat_100g":1}}}
        """.utf8)
        XCTAssertEqual(try XCTUnwrap(BarcodeLookupService.parse(data, code: "5901234123457")).name, "Product 5901234123457")
    }

    // MARK: Lookup

    private func service(_ suite: String) -> (BarcodeLookupService, NutritionCatalogService) {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [BarcodeStubProtocol.self]
        let session = URLSession(configuration: config)
        let catalog = NutritionCatalogService(defaults: UserDefaults(suiteName: suite)!, session: session)
        return (BarcodeLookupService(session: session, catalog: { catalog }), catalog)
    }

    func testLookupFindsButDoesNotSaveUntilLogged() async throws {
        let suite = "PolishTests." + UUID().uuidString
        defer { UserDefaults().removePersistentDomain(forName: suite) }
        BarcodeStubProtocol.requests = []
        BarcodeStubProtocol.responses = ["/api/v2/product/5901234123457.json":
            (200, product(#""energy-kcal_100g":372,"proteins_100g":13.5,"carbohydrates_100g":58.7,"fat_100g":7"#))]
        let (lookup, catalog) = service(suite)

        guard case .found(let food) = await lookup.lookup("5901234123457") else { return XCTFail("expected a match") }
        XCTAssertEqual(food.kcal, 372)
        XCTAssertEqual(food.name, "Oat flakes")
        // Saved only when the person logs it (the food logger calls `remember`).
        XCTAssertNil(catalog.find("off:5901234123457"), "a scanned product isn't saved before it's confirmed")
        let request = try XCTUnwrap(BarcodeStubProtocol.requests.first)
        XCTAssertEqual(request.value(forHTTPHeaderField: "User-Agent"), "Nourlo/1.0 (nourlo.app.support@gmail.com)")
        XCTAssertNil(request.httpBody)

        _ = await lookup.lookup("5901234123457")
        XCTAssertEqual(BarcodeStubProtocol.requests.count, 1, "second lookup this session is served from memory")
        catalog.remember(food)
        XCTAssertEqual(catalog.find("off:5901234123457")?.name, "Oat flakes")
    }

    func testLookupReportsNoMatchAndInvalidCodes() async {
        let suite = "PolishTests." + UUID().uuidString
        defer { UserDefaults().removePersistentDomain(forName: suite) }
        BarcodeStubProtocol.requests = []
        BarcodeStubProtocol.responses = [:]
        let (lookup, _) = service(suite)
        let missing = await lookup.lookup("4006381333931")
        XCTAssertEqual(missing, .notFound(code: "4006381333931"))
        let invalid = await lookup.lookup("4006381333932")
        XCTAssertEqual(invalid, .invalidCode("4006381333932"))
        XCTAssertEqual(BarcodeStubProtocol.requests.count, 1, "an invalid code never leaves the device")
    }

    // MARK: Tips

    func testUITestingArgumentHidesTips() {
        let empty = UserDefaults(suiteName: "PolishTests.tips." + UUID().uuidString)!
        XCTAssertTrue(NourloTips.isUITesting(arguments: ["app", "-NourloUITesting", "YES"], defaults: empty))
        XCTAssertTrue(NourloTips.isUITesting(arguments: ["app", "-NourloUITesting"], defaults: empty))
        XCTAssertFalse(NourloTips.isUITesting(arguments: ["app", "-NourloUITesting", "NO"], defaults: empty))
        XCTAssertFalse(NourloTips.isUITesting(arguments: ["app"], defaults: empty))
    }

    func testScanIsOfferedOnlyWhenTheDeviceCanScan() {
        XCTAssertTrue(NourloTips.shouldOfferScan(isSupported: true, cameraRestricted: false))
        XCTAssertFalse(NourloTips.shouldOfferScan(isSupported: false, cameraRestricted: false))
        XCTAssertFalse(NourloTips.shouldOfferScan(isSupported: true, cameraRestricted: true))
    }
}
