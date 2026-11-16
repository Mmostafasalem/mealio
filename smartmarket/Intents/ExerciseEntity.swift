import AppIntents
import Foundation

// MARK: - Exercise entity

/// An exercise from the app's catalogue, for Siri, Shortcuts and Spotlight.
nonisolated struct ExerciseEntity: AppEntity, Identifiable, Sendable {
    static var typeDisplayRepresentation: TypeDisplayRepresentation { "Exercise" }
    static var defaultQuery: ExerciseEntityQuery { ExerciseEntityQuery() }

    let id: String
    let name: String
    let muscles: String
    let equipment: String
    let kindTitle: String
    let symbol: String

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(name)", subtitle: "\(muscles) · \(kindTitle)", image: .init(systemName: symbol))
    }

    @MainActor init(_ exercise: Exercise) {
        id = exercise.id
        name = exercise.name
        muscles = exercise.muscles
        equipment = exercise.equipment
        kindTitle = exercise.kind.title
        symbol = exercise.kind.symbol
    }
}

nonisolated struct ExerciseEntityQuery: EntityStringQuery {
    @MainActor
    func entities(for identifiers: [ExerciseEntity.ID]) async throws -> [ExerciseEntity] {
        // Spotlight items indexed before schema 2 carry an "exercise:" prefix.
        let wanted = Set(identifiers.map(AppRouter.exerciseID(fromIdentifier:)))
        return Exercise.catalog.filter { wanted.contains($0.id) }.map(ExerciseEntity.init)
    }

    @MainActor
    func entities(matching string: String) async throws -> [ExerciseEntity] {
        Self.search(string).map(ExerciseEntity.init)
    }

    /// The whole catalogue, so "Show <exercise> in Nourlo" knows every name.
    @MainActor
    func suggestedEntities() async throws -> [ExerciseEntity] {
        Exercise.catalog.map(ExerciseEntity.init)
    }

    /// Exercises by name (forgiving case, accents and plurals); when no name
    /// matches, exercises that work the named muscle ("glutes").
    @MainActor
    static func search(_ query: String, in catalog: [Exercise]? = nil, limit: Int = 25) -> [Exercise] {
        let catalog = catalog ?? Exercise.catalog
        let byName = IntentSearch.filter(catalog, query: query, name: \.name, limit: limit)
        if !byName.isEmpty { return byName }
        return IntentSearch.filter(catalog, query: query, name: \.muscles, limit: limit)
    }
}

// MARK: - Show an exercise

/// Opens Nourlo on an exercise's how-to guide.
struct ShowExerciseIntent: AppIntent {
    static var title: LocalizedStringResource { "Show exercise" }
    static var description: IntentDescription {
        IntentDescription("Opens the how-to guide for an exercise.", categoryName: "Workouts")
    }
    static var openAppWhenRun: Bool { true }

    @Parameter(title: "Exercise", requestValueDialog: "Which exercise?")
    var exercise: ExerciseEntity

    init() {}
    init(exercise: ExerciseEntity) { self.exercise = exercise }

    static var parameterSummary: some ParameterSummary { Summary("Show \(\.$exercise)") }

    @MainActor
    func perform() async throws -> some IntentResult {
        AppRouter.shared.showExercise(id: exercise.id)
        return .result()
    }
}

// MARK: - Spotlight (iOS 18)

@available(iOS 18, *)
nonisolated extension ExerciseEntity: IndexedEntity {}
