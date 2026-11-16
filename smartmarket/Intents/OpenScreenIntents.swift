import AppIntents
import Foundation

// MARK: - Intents that open a screen
//
// Each hands a `NourloLink` to `NourloLinkInbox`, the same path as
// `OpenNourloIntent`, so a cold launch and a running app both land there.

/// Opens the food logger.
nonisolated struct OpenFoodLoggerIntent: AppIntent {
    static var title: LocalizedStringResource { "Open food log" }
    static var description: IntentDescription {
        IntentDescription("Opens Nourlo's food logger so you can search and add what you ate.", categoryName: "Food log")
    }
    static var openAppWhenRun: Bool { true }
    init() {}

    func perform() async throws -> some IntentResult {
        NourloLinkInbox.post(.logFood)
        return .result()
    }
}

/// Opens the grocery list.
nonisolated struct ShowGroceriesIntent: AppIntent {
    static var title: LocalizedStringResource { "Show grocery list" }
    static var description: IntentDescription {
        IntentDescription("Opens your grocery list in Nourlo.", categoryName: "Groceries")
    }
    static var openAppWhenRun: Bool { true }
    init() {}

    func perform() async throws -> some IntentResult {
        NourloLinkInbox.post(.groceries)
        return .result()
    }
}

/// Opens the food logger with the barcode scanner.
nonisolated struct ScanBarcodeIntent: AppIntent {
    static var title: LocalizedStringResource { "Scan a barcode" }
    static var description: IntentDescription {
        IntentDescription("Opens the barcode scanner to log a packaged food.", categoryName: "Food log")
    }
    static var openAppWhenRun: Bool { true }
    init() {}

    func perform() async throws -> some IntentResult {
        NourloLinkInbox.post(.scan)
        return .result()
    }
}

/// Opens Train, optionally on a workout kind. (Siri's "Start a gym workout"
/// uses `StartWorkoutKindIntent`, whose kind is required.)
struct StartWorkoutIntent: AppIntent {
    static var title: LocalizedStringResource { "Start a workout" }
    static var description: IntentDescription {
        IntentDescription("Opens Train to build a workout.", categoryName: "Workouts")
    }
    static var openAppWhenRun: Bool { true }

    @Parameter(title: "Kind", description: "Leave empty to choose in the app.")
    var kind: WorkoutKindOption?

    init() {}
    init(kind: WorkoutKindOption?) { self.kind = kind }

    static var parameterSummary: some ParameterSummary { Summary("Start a \(\.$kind) workout") }

    @MainActor
    func perform() async throws -> some IntentResult {
        AppRouter.shared.startWorkout(kind: kind?.exerciseKind)
        return .result()
    }
}

/// "Start a cardio workout": opens Train on a kind. App Shortcut phrases need a
/// non-optional parameter, so this is `StartWorkoutIntent` with the kind required.
struct StartWorkoutKindIntent: AppIntent {
    static var title: LocalizedStringResource { "Start a workout of a kind" }
    static var description: IntentDescription {
        IntentDescription("Opens Train to build a workout of the kind you choose.", categoryName: "Workouts")
    }
    static var openAppWhenRun: Bool { true }

    @Parameter(title: "Kind", requestValueDialog: "Which kind of workout?")
    var kind: WorkoutKindOption

    init() {}
    init(kind: WorkoutKindOption) { self.kind = kind }

    static var parameterSummary: some ParameterSummary { Summary("Start a \(\.$kind) workout") }

    @MainActor
    func perform() async throws -> some IntentResult {
        AppRouter.shared.startWorkout(kind: kind.exerciseKind)
        return .result()
    }
}
