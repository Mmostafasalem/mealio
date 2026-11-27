import Foundation
import Observation

/// Every price in Nourlo is an average estimate in euros. `Money` shows it in
/// the person's currency (Profile › Currency & prices), converted at a fixed
/// rate table with its date, and turns amounts the person types back into euros.
/// Nothing is fetched: the rates are a fixed table, so the same cart always
/// shows the same numbers.
enum Money {

    struct Currency: Identifiable, Hashable, Sendable {
        let code: String
        let name: String
        /// How many of this currency one euro buys.
        let perEUR: Double
        var id: String { code }
    }

    /// When the table below was set. Shown with every "About prices" note.
    static let ratesDate: Date = {
        var c = DateComponents()
        c.year = 2026; c.month = 11; c.day = 27; c.hour = 12
        return Calendar(identifier: .gregorian).date(from: c) ?? Date(timeIntervalSince1970: 0)
    }()

    static var ratesDateText: String {
        ratesDate.formatted(.dateTime.day().month(.wide).year().locale(Locale(identifier: "en_GB")))
    }

    /// Fixed rates, per euro. Rounded on purpose: prices are estimates anyway.
    static let currencies: [Currency] = [
        Currency(code: "EUR", name: "Euro", perEUR: 1),
        Currency(code: "USD", name: "US dollar", perEUR: 1.16),
        Currency(code: "CAD", name: "Canadian dollar", perEUR: 1.62),
        Currency(code: "GBP", name: "British pound", perEUR: 0.87),
        Currency(code: "AUD", name: "Australian dollar", perEUR: 1.78),
        Currency(code: "NZD", name: "New Zealand dollar", perEUR: 2.02),
        Currency(code: "CHF", name: "Swiss franc", perEUR: 0.93),
        Currency(code: "SEK", name: "Swedish krona", perEUR: 10.95),
        Currency(code: "NOK", name: "Norwegian krone", perEUR: 11.70),
        Currency(code: "DKK", name: "Danish krone", perEUR: 7.46),
        Currency(code: "PLN", name: "Polish zloty", perEUR: 4.24),
        Currency(code: "CZK", name: "Czech koruna", perEUR: 24.30),
        Currency(code: "JPY", name: "Japanese yen", perEUR: 176),
        Currency(code: "CNY", name: "Chinese yuan", perEUR: 8.25),
        Currency(code: "INR", name: "Indian rupee", perEUR: 102),
        Currency(code: "AED", name: "UAE dirham", perEUR: 4.26),
        Currency(code: "SAR", name: "Saudi riyal", perEUR: 4.35),
        Currency(code: "EGP", name: "Egyptian pound", perEUR: 56),
        Currency(code: "TRY", name: "Turkish lira", perEUR: 48.5),
        Currency(code: "MXN", name: "Mexican peso", perEUR: 21.4),
        Currency(code: "BRL", name: "Brazilian real", perEUR: 6.25),
        Currency(code: "ZAR", name: "South African rand", perEUR: 20.3),
    ]

    static let storageKey = "currencyCode_v1"

    static func currency(code: String) -> Currency? { currencies.first { $0.code == code } }

    /// The phone's region's currency when the table has it (CAD in Canada), else euros.
    static func regionalDefault(locale: Locale = .current) -> Currency {
        if let code = locale.currency?.identifier, let found = currency(code: code) { return found }
        return currencies[0]
    }

    /// The chosen currency; until one is chosen, the region's. Read through an
    /// observable store, so every price on screen redraws when it changes.
    static var current: Currency {
        if let code = CurrencyStore.shared.code, let found = currency(code: code) { return found }
        return regionalDefault()
    }

    /// True while the region's currency is used because none was chosen.
    static var followsRegion: Bool {
        guard let code = CurrencyStore.shared.code else { return true }
        return currency(code: code) == nil
    }

    /// `nil` goes back to the region's currency.
    static func setCurrent(_ code: String?) {
        if let code, currency(code: code) != nil {
            CurrencyStore.shared.code = code
        } else {
            CurrencyStore.shared.code = nil
        }
        NotificationCenter.default.post(name: .currencyDidChange, object: nil)
    }

    // MARK: - Converting

    static func local(fromEUR eur: Double, in currency: Currency = current) -> Double { eur * currency.perEUR }
    static func eur(fromLocal amount: Double, in currency: Currency = current) -> Double { amount / currency.perEUR }

    // MARK: - Formatting

    /// English number style (the app is in English) with the phone's region, so a
    /// Canadian sees "$4.20" for CAD and someone elsewhere "CA$4.20".
    static var formattingLocale: Locale {
        Locale(identifier: "en_" + (Locale.current.region?.identifier ?? "US"))
    }

    /// "€4.20", "$4.20", "¥740": a euro amount shown in the currency.
    static func format(eur: Double, in currency: Currency = current, locale: Locale = formattingLocale) -> String {
        formatLocal(local(fromEUR: eur, in: currency), in: currency, locale: locale)
    }

    /// An amount already in the currency.
    static func formatLocal(_ amount: Double, in currency: Currency = current, locale: Locale = formattingLocale) -> String {
        amount.formatted(.currency(code: currency.code).locale(locale))
    }

    /// Whole units only ("$96", "€60"), for ruler ticks and short budget labels.
    static func formatWhole(eur: Double, in currency: Currency = current, locale: Locale = formattingLocale) -> String {
        formatLocalWhole(local(fromEUR: eur, in: currency), in: currency, locale: locale)
    }

    static func formatLocalWhole(_ amount: Double, in currency: Currency = current, locale: Locale = formattingLocale) -> String {
        amount.rounded().formatted(.currency(code: currency.code).precision(.fractionLength(0)).locale(locale))
    }

    /// The symbol shown before a typed amount ("€", "$", "CA$", "£").
    static func symbol(in currency: Currency = current, locale: Locale = formattingLocale) -> String {
        let f = NumberFormatter()
        f.numberStyle = .currency
        f.locale = locale
        f.currencyCode = currency.code
        return f.currencySymbol ?? currency.code
    }

    /// Spoken by VoiceOver: "4.20 Canadian dollars".
    static func spoken(eur: Double, in currency: Currency = current) -> String {
        let amount = local(fromEUR: eur, in: currency)
        return amount.formatted(.number.precision(.fractionLength(currency.code == "JPY" ? 0 : 2))) + " " + currency.code
    }

    /// Typical whole-number steps for typed and ruler amounts: 5 for euros or
    /// dollars, 500 for yen, so a ruler never has thousands of ticks.
    static func niceStep(base: Double = 5, in currency: Currency = current) -> Double {
        guard currency.perEUR >= 10 else { return base }
        let magnitude = pow(10, floor(log10(currency.perEUR)))
        return base * magnitude
    }

    // MARK: - Typed amounts

    /// Reads an amount typed in the currency ("4.20", "4,20", "$4.20", "CA$ 4"),
    /// with the same rules as `EuroInput.parse`. Returns the amount in the currency.
    static func parseLocal(_ text: String, in currency: Currency = current) -> Double? {
        var body = text.trimmingCharacters(in: .whitespacesAndNewlines)
        for mark in [symbol(in: currency), currency.code, "€", "$", "£", "¥"] where !mark.isEmpty {
            if body.hasPrefix(mark) { body.removeFirst(mark.count) }
            if body.hasSuffix(mark) { body.removeLast(mark.count) }
            body = body.trimmingCharacters(in: .whitespaces)
        }
        return EuroInput.parse(body)
    }

    /// A euro range (budget, price) in the currency, for checking typed amounts.
    static func localRange(_ eurRange: ClosedRange<Double>, in currency: Currency = current) -> ClosedRange<Double> {
        let lo = (local(fromEUR: eurRange.lowerBound, in: currency) * 100).rounded(.up) / 100
        let hi = (local(fromEUR: eurRange.upperBound, in: currency) * 100).rounded(.down) / 100
        return lo...max(hi, lo)
    }

    enum Problem: Error, Equatable { case unreadable, outOfRange(ClosedRange<Double>) }

    /// Checks a typed amount in the currency against a euro range; gives euros back.
    static func validateLocal(_ text: String, eurRange: ClosedRange<Double>,
                              in currency: Currency = current) -> Result<Double, Problem> {
        guard let amount = parseLocal(text, in: currency) else { return .failure(.unreadable) }
        let range = localRange(eurRange, in: currency)
        guard range.contains(amount) else { return .failure(.outOfRange(range)) }
        return .success(eur(fromLocal: amount, in: currency))
    }

    static func message(for problem: Problem, example: String, in currency: Currency = current) -> String {
        switch problem {
        case .unreadable:
            return "Enter an amount like \(example)."
        case .outOfRange(let range):
            return "Enter an amount from \(formatLocal(range.lowerBound, in: currency)) to \(formatLocal(range.upperBound, in: currency))."
        }
    }

    /// Plain text for typed fields: "60", "4.20" (no symbol, no grouping).
    static func inputText(eur: Double, in currency: Currency = current) -> String {
        let amount = (local(fromEUR: eur, in: currency) * 100).rounded() / 100
        return amount == amount.rounded() ? String(format: "%.0f", amount) : String(format: "%.2f", amount)
    }

    // MARK: - About prices

    /// Said in Shop and in the currency setting.
    static var aboutPricesText: String {
        let c = current
        let conversion = c.code == "EUR"
            ? "They are set in euros (rates fixed on \(ratesDateText) for other currencies)."
            : "They are set in euros and converted to \(c.name) at a fixed rate on \(ratesDateText): 1 EUR = \(c.perEUR.formatted(.number.precision(.fractionLength(0...2)))) \(c.code)."
        return "These are average estimated prices, not live store prices. \(conversion) What you pay in your shop will differ; tap a price to enter your own."
    }
}

/// Where the chosen currency code lives (UserDefaults, this iPhone only).
@Observable
final class CurrencyStore {
    static let shared = CurrencyStore()
    var code: String? {
        didSet {
            if let code { UserDefaults.standard.set(code, forKey: Money.storageKey) }
            else { UserDefaults.standard.removeObject(forKey: Money.storageKey) }
        }
    }
    init(defaults: UserDefaults = .standard) {
        code = defaults.string(forKey: Money.storageKey)
    }
    /// Re-reads storage (after Delete All Data).
    func reload() { code = UserDefaults.standard.string(forKey: Money.storageKey) }
}

extension Notification.Name {
    /// The person chose another currency in Profile.
    static let currencyDidChange = Notification.Name("currencyDidChange")
}
