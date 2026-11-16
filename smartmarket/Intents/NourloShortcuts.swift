import AppIntents

/// Siri phrases and the Shortcuts app's ready-made actions. Every phrase names
/// the app; foods and exercises in phrases come from each query's
/// `suggestedEntities()` (refreshed by `NourloIntents.start()`). Every
/// parameter used in a phrase is non-optional (phrases with an optional one
/// may not register), so a whole-day / any-kind phrase and its parameterised
/// form are separate shortcuts. At most 10 shortcuts.
nonisolated struct NourloShortcuts: AppShortcutsProvider {
    static var shortcutTileColor: ShortcutTileColor { .pink }

    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: LogFoodIntent(),
            phrases: [
                "Log \(\.$food) in \(.applicationName)",
                "Add \(\.$food) to \(.applicationName)",
                "I ate \(\.$food) in \(.applicationName)",
                "Quick log in \(.applicationName)",
            ],
            shortTitle: "Quick log",
            systemImageName: "plus.circle.fill"
        )
        AppShortcut(
            intent: OpenFoodLoggerIntent(),
            phrases: [
                "Log food in \(.applicationName)",
                "Open my food log in \(.applicationName)",
                "Track a meal in \(.applicationName)",
            ],
            shortTitle: "Log food",
            systemImageName: "fork.knife"
        )
        AppShortcut(
            intent: CaloriesLeftIntent(),
            phrases: [
                "How many calories do I have left in \(.applicationName)",
                "Calories left in \(.applicationName)",
                "How am I doing today in \(.applicationName)",
                "Check my calories in \(.applicationName)",
            ],
            shortTitle: "Calories left",
            systemImageName: "flame.fill"
        )
        AppShortcut(
            intent: TodaysMealsIntent(),
            phrases: [
                "What's on my meal plan in \(.applicationName)",
                "Today's meals in \(.applicationName)",
                "What am I eating today in \(.applicationName)",
            ],
            shortTitle: "Today's meals",
            systemImageName: "calendar"
        )
        AppShortcut(
            intent: MealPlanForMealIntent(),
            phrases: [
                "What's for \(\.$meal) in \(.applicationName)",
                "What's my \(\.$meal) in \(.applicationName)",
            ],
            shortTitle: "Planned meal",
            systemImageName: "fork.knife.circle"
        )
        AppShortcut(
            intent: ShowGroceriesIntent(),
            phrases: [
                "Show my grocery list in \(.applicationName)",
                "Open my shopping list in \(.applicationName)",
                "What do I need to buy in \(.applicationName)",
            ],
            shortTitle: "Grocery list",
            systemImageName: "checklist"
        )
        AppShortcut(
            intent: StartWorkoutIntent(),
            phrases: [
                "Start a workout in \(.applicationName)",
                "Let's train in \(.applicationName)",
            ],
            shortTitle: "Start workout",
            systemImageName: "figure.strengthtraining.traditional"
        )
        AppShortcut(
            intent: StartWorkoutKindIntent(),
            phrases: [
                "Start a \(\.$kind) workout in \(.applicationName)",
                "Start a \(\.$kind) session in \(.applicationName)",
            ],
            shortTitle: "Workout by kind",
            systemImageName: "dumbbell"
        )
        AppShortcut(
            intent: ScanBarcodeIntent(),
            phrases: [
                "Scan a barcode in \(.applicationName)",
                "Scan food in \(.applicationName)",
                "Scan a product in \(.applicationName)",
            ],
            shortTitle: "Scan barcode",
            systemImageName: "barcode.viewfinder"
        )
        AppShortcut(
            intent: ShowExerciseIntent(),
            phrases: [
                "Show \(\.$exercise) in \(.applicationName)",
                "How do I do \(\.$exercise) in \(.applicationName)",
                "Show an exercise in \(.applicationName)",
            ],
            shortTitle: "Exercise guide",
            systemImageName: "figure.cooldown"
        )
    }
}
