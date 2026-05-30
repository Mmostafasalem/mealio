import Foundation

enum DietaryPreference: String, Codable, CaseIterable, Identifiable {
    case glutenFree      = "gluten_free"
    case lactoseFree     = "lactose_free"
    case vegan           = "vegan"
    case vegetarian      = "vegetarian"
    case keto            = "keto"
    case paleo           = "paleo"
    case nutAllergy      = "nut_allergy"
    case shellfishAllergy = "shellfish_allergy"
    case halal           = "halal"
    case noPork          = "no_pork"

    var id: String { rawValue }

    var isAllergy: Bool {
        switch self {
        case .nutAllergy, .shellfishAllergy: return true
        default: return false
        }
    }

    var displayName: String {
        switch self {
        case .glutenFree:       return "Gluten Free"
        case .lactoseFree:      return "Lactose Free"
        case .vegan:            return "Vegan"
        case .vegetarian:       return "Vegetarian"
        case .keto:             return "Keto"
        case .paleo:            return "Paleo"
        case .nutAllergy:       return "Nut Allergy"
        case .shellfishAllergy: return "Shellfish Allergy"
        case .halal:            return "Halal"
        case .noPork:           return "No Pork"
        }
    }

    var sfSymbol: String {
        switch self {
        case .glutenFree:       return "xmark.circle"
        case .lactoseFree:      return "drop.fill"
        case .vegan:            return "leaf.fill"
        case .vegetarian:       return "leaf"
        case .keto:             return "bolt.fill"
        case .paleo:            return "fossil.shell.fill"
        case .nutAllergy:       return "exclamationmark.triangle.fill"
        case .shellfishAllergy: return "exclamationmark.triangle"
        case .halal:            return "moon.fill"
        case .noPork:           return "nosign"
        }
    }
}

// MARK: - Persistence
extension Set where Element == DietaryPreference {
    static func load() -> Set<DietaryPreference> {
        guard let raw = UserDefaults.standard.stringArray(forKey: Constants.Storage.selectedDietaryFilters) else {
            return []
        }
        return Set(raw.compactMap { DietaryPreference(rawValue: $0) })
    }

    func save() {
        let raw = map(\.rawValue)
        UserDefaults.standard.set(raw, forKey: Constants.Storage.selectedDietaryFilters)
    }
}
