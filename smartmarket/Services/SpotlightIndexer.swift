import AppIntents
import CoreSpotlight
import CryptoKit
import Foundation
import UniformTypeIdentifiers

/// Puts the exercise catalogue in Spotlight. Only the app's own catalogue is
/// indexed (no personal data), so nothing needs removing when the user
/// deletes their data. Opening a result goes through `AppRouter.handle(_:)`.
@MainActor
final class SpotlightIndexer {
    static let shared = SpotlightIndexer()

    static let exerciseDomain = "exercises"
    /// Bump when the item layout changes, to re-index even if the catalogue didn't.
    /// 2: identifiers are the bare exercise id, the same as `ExerciseEntity.id`.
    static let schemaVersion = 2
    static let versionKey = "spotlightExerciseIndexVersion"

    private let defaults: UserDefaults
    private var isIndexing = false

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    /// Indexes the catalogue when it (or the item layout) changed since the last
    /// successful run. Cheap to call at every launch.
    func indexIfNeeded() {
        guard CSSearchableIndex.isIndexingAvailable(), !isIndexing else { return }
        let version = Self.catalogVersion()
        guard defaults.string(forKey: Self.versionKey) != version else { return }
        isIndexing = true
        let items = Self.items(for: Exercise.catalog)
        Task {
            defer { isIndexing = false }
            let index = CSSearchableIndex.default()
            do {
                // Replace the whole domain so removed or renamed exercises don't linger.
                try? await index.deleteSearchableItems(withDomainIdentifiers: [Self.exerciseDomain])
                try await index.indexSearchableItems(items)
                defaults.set(version, forKey: Self.versionKey)
            } catch {
                // Not saved, so the next launch tries again.
            }
        }
    }

    /// A stable fingerprint of everything Spotlight shows for the catalogue.
    static func catalogVersion(_ catalog: [Exercise]? = nil) -> String {
        let catalog = catalog ?? Exercise.catalog
        var text = "v\(schemaVersion)\n"
        for exercise in catalog {
            text += [exercise.id, exercise.name, exercise.muscles, exercise.equipment, exercise.kind.rawValue,
                     exercise.focus?.rawValue ?? "", exercise.level.rawValue, exercise.prescription, exercise.howTo]
                .joined(separator: "|") + "\n"
        }
        return SHA256.hash(data: Data(text.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    /// The item's identifier is the exercise id, the same id as the `ExerciseEntity`
    /// it is associated with on iOS 18, so Spotlight can resolve the entity.
    /// (The domain keeps exercises apart from anything else indexed.)
    static func identifier(for exercise: Exercise) -> String { exercise.id }

    static func items(for catalog: [Exercise]) -> [CSSearchableItem] {
        catalog.map(item(for:))
    }

    static func item(for exercise: Exercise) -> CSSearchableItem {
        let attributes = CSSearchableItemAttributeSet(contentType: .content)
        attributes.title = exercise.name
        attributes.displayName = exercise.name
        attributes.contentDescription = description(for: exercise)
        attributes.keywords = keywords(for: exercise)
        if #available(iOS 18, *) {
            attributes.associateAppEntity(ExerciseEntity(exercise), priority: 1)
        }
        let item = CSSearchableItem(uniqueIdentifier: identifier(for: exercise), domainIdentifier: exerciseDomain,
                                    attributeSet: attributes)
        item.expirationDate = .distantFuture
        return item
    }

    /// "Quads, glutes · Barbell, rack · Gym · Intermediate · 3 × 8"
    static func description(for exercise: Exercise) -> String {
        [exercise.muscles, exercise.equipment, exercise.kind.title, exercise.level.title, exercise.prescription]
            .filter { !$0.isEmpty }.joined(separator: " · ")
    }

    static func keywords(for exercise: Exercise) -> [String] {
        func parts(_ text: String) -> [String] {
            text.components(separatedBy: CharacterSet(charactersIn: ",;()"))
                .flatMap { $0.components(separatedBy: " or ") }
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
                .filter { !$0.isEmpty }
        }
        var words = ["exercise", "workout", exercise.kind.title.lowercased(), exercise.level.title.lowercased()]
        if let focus = exercise.focus { words.append(focus.title.lowercased()) }
        words += parts(exercise.muscles) + parts(exercise.equipment)
        var seen = Set<String>()
        return words.filter { seen.insert($0).inserted }
    }
}
