import Foundation

// MARK: - Store
struct Store: Codable, Identifiable {
    let id: String
    let chain: String          // "Maxima", "Iki", "Rimi", "Lidl", "Norfa"
    let name: String
    let address: String
    let latitude: Double
    let longitude: Double

    var chainIcon: String { String(chain.prefix(1)) }

    var chainColor: String {
        switch chain {
        case "Maxima": return "#0044FF"
        case "Iki":    return "#F97316"
        case "Rimi":   return "#DC2626"
        case "Lidl":   return "#FACC15"
        case "Norfa":  return "#16A34A"
        default:       return "#6B7280"
        }
    }
}

// MARK: - Market deal
struct MarketDeal: Codable, Identifiable {
    let id: String
    let store: Store
    let productId: String
    let productName: String
    let originalPrice: Double   // EUR
    let discountPrice: Double   // EUR
    let discountPercent: Int    // 0–100
    let validUntil: Date
    let dealType: DealType
    let quantity: String        // e.g. "1kg", "500g"

    var savings: Double { originalPrice - discountPrice }

    enum DealType: String, Codable {
        case weeklySpecial  = "weekly_special"
        case dailyFresh     = "daily_fresh"
        case loyaltyCard    = "loyalty_card"
        case clearance      = "clearance"
        case bulkDeal       = "bulk_deal"

        var displayName: String {
            switch self {
            case .weeklySpecial: return "Weekly Deal"
            case .dailyFresh:    return "Fresh Today"
            case .loyaltyCard:   return "Member Price"
            case .clearance:     return "Clearance"
            case .bulkDeal:      return "Bulk Deal"
            }
        }
    }

    enum CodingKeys: String, CodingKey {
        case id, store, quantity
        case productId      = "product_id"
        case productName    = "product_name"
        case originalPrice  = "original_price"
        case discountPrice  = "discount_price"
        case discountPercent = "discount_percent"
        case validUntil     = "valid_until"
        case dealType       = "deal_type"
    }
}

// MARK: - API response wrapper (matches Python GET /market-deals)
struct MarketDealsResponse: Codable {
    let deals: [MarketDeal]
}

// MARK: - Mocked deals (used until API is ready)
extension MarketDeal {
    static let mocked: [MarketDeal] = {
        let maxima = Store(id: "maxima-seskine", chain: "Maxima", name: "Maxima XX Šeškinė",
                           address: "Šeškinės g. 24, Vilnius", latitude: 54.7154, longitude: 25.2539)
        let iki    = Store(id: "iki-lazdynai",   chain: "Iki",    name: "Iki Lazdynai",
                           address: "Erfurto g. 2, Vilnius",   latitude: 54.6891, longitude: 25.2012)
        let rimi   = Store(id: "rimi-bclv",      chain: "Rimi",   name: "Rimi Hypermarket",
                           address: "Bičiulių g. 2, Vilnius",  latitude: 54.6634, longitude: 25.2897)
        let lidl   = Store(id: "lidl-virsul",    chain: "Lidl",   name: "Lidl Viršuliškių",
                           address: "Viršuliškių g. 34, Vilnius", latitude: 54.7032, longitude: 25.2205)
        let norfa  = Store(id: "norfa-ant",      chain: "Norfa",  name: "Norfa Antakalnis",
                           address: "Antakalnio g. 36, Vilnius",  latitude: 54.7021, longitude: 25.3221)

        let future = Date().addingTimeInterval(86400 * 6)

        return [
            MarketDeal(id: "d1", store: maxima, productId: "visc-file",    productName: "Vištienos filė",       originalPrice: 4.99, discountPrice: 3.49, discountPercent: 30, validUntil: future, dealType: .weeklySpecial, quantity: "1kg"),
            MarketDeal(id: "d2", store: maxima, productId: "grikiai",      productName: "Grikiai",              originalPrice: 1.49, discountPrice: 0.99, discountPercent: 34, validUntil: future, dealType: .weeklySpecial, quantity: "1kg"),
            MarketDeal(id: "d3", store: iki,    productId: "lasisa",       productName: "Lašiša filė",          originalPrice: 5.99, discountPrice: 3.99, discountPercent: 33, validUntil: future, dealType: .loyaltyCard,   quantity: "300g"),
            MarketDeal(id: "d4", store: iki,    productId: "brokoliai",    productName: "Brokoliai",            originalPrice: 1.29, discountPrice: 0.79, discountPercent: 39, validUntil: future, dealType: .dailyFresh,    quantity: "500g"),
            MarketDeal(id: "d5", store: rimi,   productId: "kefyras",      productName: "Kefyras 3.5%",         originalPrice: 0.99, discountPrice: 0.69, discountPercent: 30, validUntil: future, dealType: .weeklySpecial, quantity: "1L"),
            MarketDeal(id: "d6", store: lidl,   productId: "avizos",       productName: "Avižiniai dribsniai",  originalPrice: 1.19, discountPrice: 0.79, discountPercent: 34, validUntil: future, dealType: .weeklySpecial, quantity: "1kg"),
            MarketDeal(id: "d7", store: norfa,  productId: "kiausiniai",   productName: "Kiaušiniai",           originalPrice: 2.29, discountPrice: 1.59, discountPercent: 31, validUntil: future, dealType: .bulkDeal,      quantity: "10vnt"),
            MarketDeal(id: "d8", store: rimi,   productId: "lesiai",       productName: "Lęšiai",               originalPrice: 1.39, discountPrice: 0.89, discountPercent: 36, validUntil: future, dealType: .clearance,     quantity: "500g"),
        ]
    }()
}
