import Foundation

struct StoreRecipe: Identifiable {
    let id: String
    let name: String
    let requiredFoodIDs: [String]
    let availableFoodIDs: [String]
    let matchCount: Int
    let totalIngredients: Int
    var coverSymbol: String
}

// MARK: - Static catalog
extension StoreRecipe {

    /// All known recipes. Use `recipesMatching(discountedIDs:)` to get filtered, scored results.
    static let catalog: [StoreRecipeTemplate] = [
        StoreRecipeTemplate(
            id: "vistinios-sriuba",
            name: "Vištienos sriuba",
            requiredFoodIDs: ["visc-file", "morkos", "svogunu"],
            coverSymbol: "cup.and.saucer.fill"
        ),
        StoreRecipeTemplate(
            id: "aviziniai-pusrytiai",
            name: "Avižiniai pusryčiai",
            requiredFoodIDs: ["avizos", "kefyras", "bananai"],
            coverSymbol: "sunrise.fill"
        ),
        StoreRecipeTemplate(
            id: "lasisos-salotos",
            name: "Lašišos salotos",
            requiredFoodIDs: ["lasisa", "spinatai", "pomidorai", "agurkai"],
            coverSymbol: "leaf.fill"
        ),
        StoreRecipeTemplate(
            id: "griku-kosas",
            name: "Grikių košė su kiaušiniais",
            requiredFoodIDs: ["grikiai", "kiausiniai", "svogunu"],
            coverSymbol: "flame.fill"
        ),
        StoreRecipeTemplate(
            id: "lesiu-sriuba",
            name: "Lęšių sriuba",
            requiredFoodIDs: ["lesiai", "morkos", "svogunu"],
            coverSymbol: "drop.fill"
        ),
        StoreRecipeTemplate(
            id: "varske-vaisiuose",
            name: "Varškė su vaisiais",
            requiredFoodIDs: ["varske", "obuoliai", "bananai"],
            coverSymbol: "heart.fill"
        ),
        StoreRecipeTemplate(
            id: "brokoliu-omletai",
            name: "Brokolių omletas",
            requiredFoodIDs: ["kiausiniai", "brokoliai"],
            coverSymbol: "circle.fill"
        ),
        StoreRecipeTemplate(
            id: "ryziai-su-krevetems",
            name: "Ryžiai su krevetėmis",
            requiredFoodIDs: ["ryziai", "krevetes", "svogunu"],
            coverSymbol: "fish.fill"
        ),
        StoreRecipeTemplate(
            id: "kopustu-salotos",
            name: "Kopūstų salotos",
            requiredFoodIDs: ["kopustai", "morkos", "agurkai"],
            coverSymbol: "laurel.leading"
        ),
        StoreRecipeTemplate(
            id: "kiauliena-su-ryzhais",
            name: "Kiauliena su ryžiais",
            requiredFoodIDs: ["kiauliena", "ryziai", "svogunu"],
            coverSymbol: "fork.knife"
        ),
        StoreRecipeTemplate(
            id: "pupeliu-sriuba",
            name: "Pupelių sriuba",
            requiredFoodIDs: ["pupeles", "morkos", "svogunu", "kopustai"],
            coverSymbol: "leaf.circle.fill"
        ),
        StoreRecipeTemplate(
            id: "tuno-salotos",
            name: "Tuno salotos",
            requiredFoodIDs: ["tunas", "pomidorai", "agurkai", "kiausiniai"],
            coverSymbol: "star.fill"
        ),
        StoreRecipeTemplate(
            id: "jogurtas-su-chia",
            name: "Jogurtas su čia sėklomis",
            requiredFoodIDs: ["jogurtas", "chia", "bananai"],
            coverSymbol: "sparkles"
        ),
        StoreRecipeTemplate(
            id: "feta-salotos",
            name: "Feta salotos",
            requiredFoodIDs: ["feta", "pomidorai", "agurkai"],
            coverSymbol: "circle.hexagongrid.fill"
        ),
    ]

    /// Builds scored `StoreRecipe` values for the given set of discounted product IDs.
    static func recipesMatching(discountedIDs: Set<String>) -> [StoreRecipe] {
        catalog.compactMap { template in
            let available = template.requiredFoodIDs.filter { discountedIDs.contains($0) }
            guard !available.isEmpty else { return nil }
            return StoreRecipe(
                id: template.id,
                name: template.name,
                requiredFoodIDs: template.requiredFoodIDs,
                availableFoodIDs: available,
                matchCount: available.count,
                totalIngredients: template.requiredFoodIDs.count,
                coverSymbol: template.coverSymbol
            )
        }
        .sorted { $0.matchCount > $1.matchCount }
    }
}

// MARK: - Template (internal helper — not exposed outside module)
struct StoreRecipeTemplate {
    let id: String
    let name: String
    let requiredFoodIDs: [String]
    let coverSymbol: String
}
