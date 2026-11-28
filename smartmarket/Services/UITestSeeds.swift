import UIKit

#if DEBUG
/// UI tests only (`-NourloUITesting YES`): put known food in My Stock and a meal photo
/// under "To clarify", so the logging screens can be checked without a camera.
///
/// `-NourloSeedStock "Veggie burger, on bun=440|Bread, whole-wheat, commercially prepared=600:20:slice"`
/// (name=amount, optionally :pieces:piece name). `-NourloSeedPendingPhoto YES` adds one photo.
@MainActor
enum UITestSeeds {
    static func apply() {
        guard NourloTips.isUITesting() else { return }
        let defaults = UserDefaults.standard
        if let spec = defaults.string(forKey: "NourloSeedStock"), !spec.isEmpty {
            seedStock(spec)
        }
        if defaults.bool(forKey: "NourloSeedPendingPhoto") {
            PendingMealStore.shared.clear()
            let image = UIGraphicsImageRenderer(size: CGSize(width: 600, height: 450)).image { context in
                UIColor(red: 0.96, green: 0.93, blue: 0.86, alpha: 1).setFill()
                context.fill(CGRect(x: 0, y: 0, width: 600, height: 450))
                UIColor.white.setFill()
                context.cgContext.fillEllipse(in: CGRect(x: 120, y: 60, width: 360, height: 330))
                UIColor(red: 0.85, green: 0.55, blue: 0.25, alpha: 1).setFill()
                context.cgContext.fillEllipse(in: CGRect(x: 200, y: 140, width: 120, height: 90))
                UIColor(red: 0.35, green: 0.65, blue: 0.3, alpha: 1).setFill()
                context.cgContext.fillEllipse(in: CGRect(x: 300, y: 200, width: 110, height: 100))
            }
            PendingMealStore.shared.add(image, slot: .lunch, at: Date().addingTimeInterval(-45 * 60))
        }
    }

    private static func seedStock(_ spec: String) {
        guard let foods = try? NutritionDatabase.load() else { return }
        let store = StockStore.shared
        for item in spec.split(separator: "|") {
            let parts = item.split(separator: "=", maxSplits: 1).map(String.init)
            guard parts.count == 2 else { continue }
            let name = parts[0]
            let numbers = parts[1].split(separator: ":").map(String.init)
            guard let amount = Double(numbers[0]) else { continue }
            guard var food = foods.first(where: { $0.name == name })
                    ?? NutritionDatabase.search(name, in: foods, limit: 5).first else { continue }
            if numbers.count >= 2, let pieces = Double(numbers[1]) {
                food = food.withPieces(pieces, name: numbers.count >= 3 ? numbers[2] : "piece", package: amount)
            }
            if !store.items.contains(where: { $0.food.id == food.id }) { try? store.add(food: food, amount: amount) }
        }
    }
}
#endif
