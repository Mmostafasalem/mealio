import Foundation
import Observation

// MARK: - GTIN

/// Retail barcodes (EAN-13, EAN-8, UPC-A, UPC-E, GTIN-14): validation and the
/// form used for lookups.
nonisolated enum GTIN {

    /// The GS1 check digit is valid for an 8, 12, 13 or 14 digit code.
    static func hasValidCheckDigit(_ code: String) -> Bool {
        guard [8, 12, 13, 14].contains(code.count),
              code.allSatisfy({ $0.isASCII && $0.isNumber }) else { return false }
        let digits = code.compactMap { $0.wholeNumberValue }
        let body = digits.dropLast()
        // Weights 3,1,3,1… from the digit next to the check digit.
        var sum = 0
        for (offset, digit) in body.reversed().enumerated() {
            sum += digit * (offset.isMultiple(of: 2) ? 3 : 1)
        }
        return (10 - sum % 10) % 10 == digits.last
    }

    /// Expands an 8-digit UPC-E (number system 0 or 1) to its 12-digit UPC-A.
    static func expandUPCE(_ code: String) -> String? {
        guard code.count == 8, code.allSatisfy({ $0.isASCII && $0.isNumber }) else { return nil }
        let d = Array(code)
        guard d[0] == "0" || d[0] == "1" else { return nil }
        let ns = String(d[0]), check = String(d[7])
        let m = String(d[1...6])
        let x = Array(m)
        let body: String
        switch x[5] {
        case "0", "1", "2": body = String(x[0...1]) + String(x[5]) + "0000" + String(x[2...4])
        case "3": body = String(x[0...2]) + "00000" + String(x[3...4])
        case "4": body = String(x[0...3]) + "00000" + String(x[4])
        default: body = String(x[0...4]) + "0000" + String(x[5])
        }
        return ns + body + check
    }

    /// What the scanner said it read, when it knows. An 8-digit code can be a
    /// valid EAN-8 and a valid UPC-E at once, so the symbology decides.
    enum Symbology { case ean8, upce, unknown }

    /// The code to look up, or nil when it isn't a valid retail barcode.
    /// Without a symbology, an 8-digit code with a valid EAN-8 check digit is EAN-8,
    /// else a valid UPC-E; read as EAN-8, it must pass the EAN-8 check.
    static func normalize(_ raw: String, symbology: Symbology = .unknown) -> String? {
        let code = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard code.allSatisfy({ $0.isASCII && $0.isNumber }) else { return nil }
        switch code.count {
        case 6 where symbology == .upce:
            // Some readers drop the number system and check digit: assume 0 and compute.
            for check in 0...9 {
                if let upcA = expandUPCE("0" + code + String(check)), hasValidCheckDigit(upcA) { return upcA }
            }
            return nil
        case 8:
            if symbology == .upce {
                if let upcA = expandUPCE(code), hasValidCheckDigit(upcA) { return upcA }
                return nil
            }
            if hasValidCheckDigit(code) { return code }
            // A code read as EAN-8 that fails its check is a misread, not a UPC-E.
            if symbology == .ean8 { return nil }
            if let upcA = expandUPCE(code), hasValidCheckDigit(upcA) { return upcA }
            return nil
        case 12, 13, 14:
            return hasValidCheckDigit(code) ? code : nil
        default:
            return nil
        }
    }
}

// MARK: - Lookup

/// Finds a scanned barcode's nutrition: first in the app's own saved products,
/// then on Open Food Facts. Only the barcode is sent, with a generic User-Agent.
@MainActor @Observable
final class BarcodeLookupService {
    static let shared = BarcodeLookupService()

    enum Outcome: Equatable {
        case found(NutritionFood)
        /// A valid code nobody has usable nutrition for.
        case notFound(code: String)
        /// The scanned value isn't a retail barcode.
        case invalidCode(String)
        /// Network or server trouble; the person can retry or enter it by hand.
        case failed(code: String, message: String)
    }

    private let session: URLSession
    private let catalog: @MainActor () -> NutritionCatalogService
    private var cache: [String: Outcome] = [:]

    init(session: URLSession? = nil, catalog: (@MainActor () -> NutritionCatalogService)? = nil) {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.urlCache = nil
        configuration.httpCookieStorage = nil
        configuration.urlCredentialStorage = nil
        configuration.httpShouldSetCookies = false
        configuration.timeoutIntervalForRequest = 8
        configuration.timeoutIntervalForResource = 12
        self.session = session ?? URLSession(configuration: configuration)
        self.catalog = catalog ?? { NutritionCatalogService.shared }
    }

    func lookup(_ raw: String, symbology: GTIN.Symbology = .unknown) async -> Outcome {
        guard let code = GTIN.normalize(raw, symbology: symbology) else { return .invalidCode(raw) }
        if let cached = cache[code] { return cached }
        // The app's own catalogue: products already looked up and saved.
        // (The bundled USDA catalogue carries no barcodes.)
        for candidate in Self.lookupCodes(for: code) {
            if let saved = catalog().find("off:" + candidate) { return .found(saved) }
        }
        do {
            for candidate in Self.lookupCodes(for: code) {
                if let food = try await fetch(candidate) {
                    // Kept for this session only; the food logger saves it when it's logged.
                    cache[code] = .found(food)
                    return .found(food)
                }
            }
            cache[code] = .notFound(code: code)
            return .notFound(code: code)
        } catch is CancellationError {
            return .failed(code: code, message: "The lookup was cancelled.")
        } catch {
            // Not cached, so a retry can succeed once the connection is back.
            return .failed(code: code, message: "Couldn't reach the product database. Check your connection, or enter it yourself.")
        }
    }

    /// A 12-digit UPC-A is stored by Open Food Facts as its 13-digit EAN form.
    static func lookupCodes(for code: String) -> [String] {
        code.count == 12 ? ["0" + code, code] : [code]
    }

    static func requestURL(for code: String) -> URL? {
        var parts = URLComponents(string: "https://world.openfoodfacts.org")!
        parts.path = "/api/v2/product/\(code).json"
        parts.queryItems = [URLQueryItem(name: "fields",
                                         value: "code,product_name,brands,nutriments,serving_size,serving_quantity,serving_quantity_unit,quantity,product_quantity,product_quantity_unit,number_of_units,nutrition_data_per")]
        return parts.url
    }

    private func fetch(_ code: String) async throws -> NutritionFood? {
        guard let url = Self.requestURL(for: code) else { return nil }
        var request = URLRequest(url: url, timeoutInterval: 8)
        request.setValue("Nourlo/1.0 (nourlo.app.support@gmail.com)", forHTTPHeaderField: "User-Agent")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let (data, response) = try await session.data(for: request)
        try Task.checkCancellation()
        guard let http = response as? HTTPURLResponse else { throw URLError(.badServerResponse) }
        // OFF answers 404 for an unknown product.
        if http.statusCode == 404 { return nil }
        guard http.statusCode == 200 else { throw URLError(.badServerResponse) }
        return Self.parse(data, code: code)
    }

    // MARK: Parsing (pure)

    /// Per-100 g (or ml) values from an Open Food Facts product response.
    struct Per100: Equatable {
        let kcal: Double
        let protein: Double
        let carbs: Double
        let fat: Double
    }

    /// Reads a product response into a loggable food, or nil when the product
    /// is unknown or its nutrition is missing or implausible.
    static func parse(_ data: Data, code: String, retrieved: Date = Date()) -> NutritionFood? {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              (root["status"] as? Int) == 1 || (root["status"] as? String) == "1" || root["status"] == nil,
              let product = root["product"] as? [String: Any],
              let nutriments = product["nutriments"] as? [String: Any],
              let values = per100(nutriments, servingAmount: OFFPackage.servingAmount(product, basis: basis(product))) else { return nil }
        let returnedCode = (product["code"] as? String) ?? (root["code"] as? String) ?? code
        guard returnedCode == code else { return nil }

        let brand = (product["brands"] as? String)?
            .split(separator: ",").first.map { $0.trimmingCharacters(in: .whitespaces) }
            .flatMap { $0.isEmpty ? nil : $0 }
        let productName = (product["product_name"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let name = !productName.isEmpty ? productName : (brand.map { "\($0) product" } ?? "Product \(code)")

        var food = NutritionFood(id: "off:\(code)", name: name, brand: brand, basis: basis(product),
                                 kcal: values.kcal, protein: values.protein, carbs: values.carbs, fat: values.fat,
                                 source: .openFoodFacts, sourceID: code,
                                 sourceDate: String(ISO8601DateFormatter().string(from: retrieved).prefix(10)))
        food.searchNames = [productName].filter { !$0.isEmpty }
        OFFPackage.apply(product, to: &food)
        return food.isValid ? food : nil
    }

    /// kcal and macros per 100 g, with kJ converted when kcal is missing.
    /// Nil when any value is missing, negative, non-finite or impossible.
    nonisolated static func per100(_ n: [String: Any], servingAmount: Double? = nil) -> Per100? {
        guard let read = OFFPackage.per100(n, servingAmount: servingAmount) else { return nil }
        let values = Per100(kcal: read.kcal, protein: read.protein, carbs: read.carbs, fat: read.fat)
        return isPlausible(values) ? values : nil
    }

    /// Pure fat is 900 kcal per 100 g, and 100 g can't hold more than 100 g of
    /// macros (a little slack for rounding on labels).
    nonisolated static func isPlausible(_ v: Per100) -> Bool {
        let all = [v.kcal, v.protein, v.carbs, v.fat]
        guard all.allSatisfy({ $0.isFinite && $0 >= 0 }) else { return false }
        guard v.kcal <= 900, v.protein <= 100, v.carbs <= 100, v.fat <= 100 else { return false }
        guard v.protein + v.carbs + v.fat <= 102 else { return false }
        // Macros can't hold far more energy than the label states
        // (alcohol, fibre and polyols push the other way, so only this side is checked).
        let fromMacros = 4 * v.protein + 4 * v.carbs + 9 * v.fat
        return fromMacros <= v.kcal * 1.5 + 50
    }

    /// Liquids are per 100 ml when the product says so; otherwise per 100 g.
    nonisolated static func basis(_ product: [String: Any]) -> NutritionFood.Basis {
        if (product["nutrition_data_per"] as? String)?.lowercased() == "100ml" { return .millilitres }
        let volume: Set<String> = ["ml", "l", "cl", "dl"]
        if let unit = (product["product_quantity_unit"] as? String)?.lowercased(), volume.contains(unit) { return .millilitres }
        if let quantity = (product["quantity"] as? String)?.lowercased(),
           let range = quantity.range(of: #"(?<=\d)\s*(ml|cl|dl|l)\s*$"#, options: .regularExpression),
           volume.contains(quantity[range].trimmingCharacters(in: .whitespaces)) {
            return .millilitres
        }
        return .grams
    }
}
