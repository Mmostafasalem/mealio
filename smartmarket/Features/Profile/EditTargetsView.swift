import SwiftUI

/// Profile › Goals & targets › Change daily targets: the daily calorie goal and
/// the protein, carbs and fat targets, each starting at what is in use now.
/// Save keeps them for Home, Meals, widgets and the planner; "Use recommended"
/// goes back to Nourlo's numbers for the body stats and goal.
struct EditTargetsView: View {
    @Bindable var vm: ProfileViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var calories: Double = 2000
    @State private var protein = 0
    @State private var carbs = 0
    @State private var fat = 0
    /// Once a macro is changed by hand, a new calorie goal no longer re-splits the macros.
    @State private var macrosEdited = false
    @State private var isReady = false

    private static let calorieRange = Double(TargetOverrides.calorieRange.lowerBound)...Double(TargetOverrides.calorieRange.upperBound)

    private var kcal: Int { Int(calories.rounded()) }
    private var recommendedKcal: Int { vm.recommendedCalories }
    private var recommendedMacros: BMRCalculator.MacroTargets { vm.recommendedMacros(calories: kcal) }
    private var floor: Int { BMRCalculator.safetyFloor(for: vm.profile.gender) }

    var body: some View {
        List {
            Section {
                VStack(spacing: Spacing.sm) {
                    HStack {
                        Label("Daily goal", systemImage: "target")
                        Spacer()
                        TypeNumberButton(title: "Daily goal", unit: "kcal", current: "\(kcal)",
                                         hint: "Enter calories a day, from \(TargetOverrides.calorieRange.lowerBound) to \(TargetOverrides.calorieRange.upperBound).",
                                         keyboard: .numberPad, identifier: "targets.calories.type") { text in
                            guard let n = TypedNumber.parse(text) else { return }
                            calories = TypedNumber.fitted(n, range: Self.calorieRange, step: 10)
                        }
                    }
                    Text("\(kcal.formatted(.number.grouping(.never))) kcal" as String)
                        .font(.system(.title, design: .rounded).weight(.semibold))
                        .monospacedDigit()
                        .contentTransition(.numericText())
                        .animation(.snappyValue, value: kcal)
                        .accessibilityIdentifier("targets.calories.value")
                    RulerPicker(value: $calories, range: Self.calorieRange, step: 10,
                                majorEvery: 10, midEvery: 5, spacing: 8,
                                tickLabel: { "\(Int($0))" },
                                accessibilityName: "Daily calorie goal",
                                spokenValue: { "\(Int($0)) kilocalories" })
                        .frame(height: 96)
                }
                .padding(.vertical, Spacing.xs)
            } header: {
                Text("Calories")
            } footer: {
                VStack(alignment: .leading, spacing: Spacing.xs) {
                    Text("Recommended for you: \(recommendedKcal.formatted(.number.grouping(.never))) kcal a day." as String)
                    if kcal < floor {
                        Text("This is below \(floor) kcal, the least Nourlo plans for without a doctor's advice." as String)
                            .foregroundStyle(Color.brandDanger)
                    }
                }
            }

            Section {
                macroRow("Protein", symbol: "fish", value: $protein, recommended: recommendedMacros.proteinG, id: "protein")
                macroRow("Carbs", symbol: "leaf", value: $carbs, recommended: recommendedMacros.carbsG, id: "carbs")
                macroRow("Fat", symbol: "drop", value: $fat, recommended: recommendedMacros.fatG, id: "fat")
            } header: {
                Text("Macros a day")
            } footer: {
                let sum = TargetOverrides.kcal(protein: protein, carbs: carbs, fat: fat)
                Text("These add up to about \(sum.formatted(.number.grouping(.never))) kcal (protein and carbs 4 kcal a gram, fat 9)." as String)
            }

            Section {
                Button {
                    save()
                } label: {
                    Text("Save targets")
                        .font(.headline)
                        .foregroundStyle(Color.onAccent)
                        .frame(maxWidth: .infinity, minHeight: 52)
                        .background(Color.dullPink, in: Capsule())
                        .contentShape(Capsule())
                }
                .buttonStyle(ScalePressStyle())
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets())
                .accessibilityIdentifier("targets.save")

                Button {
                    vm.useRecommendedTargets()
                    load()
                } label: {
                    Label("Use recommended", systemImage: "arrow.counterclockwise")
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
                .disabled(vm.targetOverrides.isEmpty && !differsFromRecommended)
                .accessibilityIdentifier("targets.useRecommended")
            } footer: {
                Text(vm.targetOverrides.isEmpty
                     ? "You are using the recommended targets."
                     : "You are using your own targets. Use recommended goes back to Nourlo's numbers for your body stats and goal.")
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Daily targets")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { if !isReady { load() } }
        .onChange(of: kcal) { _, _ in
            guard isReady, !macrosEdited else { return }
            let split = recommendedMacros
            protein = split.proteinG; carbs = split.carbsG; fat = split.fatG
        }
    }

    private var differsFromRecommended: Bool {
        kcal != recommendedKcal || protein != recommendedMacros.proteinG
            || carbs != recommendedMacros.carbsG || fat != recommendedMacros.fatG
    }

    private func load() {
        calories = Double(vm.profile.dailyCalorieGoal)
        let current = vm.currentMacros
        protein = current.proteinG; carbs = current.carbsG; fat = current.fatG
        macrosEdited = vm.targetOverrides.hasMacros
        isReady = true
    }

    /// Only what differs from the recommendation is kept as typed, so a later
    /// change of body stats still moves the rest.
    private func save() {
        let split = recommendedMacros
        vm.setTargets(TargetOverrides(
            calories: kcal == recommendedKcal ? nil : kcal,
            proteinG: protein == split.proteinG ? nil : protein,
            carbsG: carbs == split.carbsG ? nil : carbs,
            fatG: fat == split.fatG ? nil : fat))
        dismiss()
    }

    private func macroRow(_ title: String, symbol: String, value: Binding<Int>, recommended: Int, id: String) -> some View {
        let range = TargetOverrides.macroRange
        let edited = Binding<Int>(get: { value.wrappedValue },
                                  set: { value.wrappedValue = $0; macrosEdited = true })
        return Stepper(value: edited, in: range, step: 5) {
            HStack(spacing: Spacing.sm) {
                Image(systemName: symbol).foregroundStyle(Color.brandPrimary).frame(width: 22)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                    Text("Recommended \(recommended) g" as String)
                        .font(.caption).foregroundStyle(Color.labelSecondary)
                }
                Spacer(minLength: Spacing.sm)
                Text("\(value.wrappedValue) g" as String)
                    .fontWeight(.semibold)
                    .monospacedDigit()
                    .foregroundStyle(Color.labelPrimary)
                    .contentTransition(.numericText())
                    .animation(.snappyValue, value: value.wrappedValue)
                    .accessibilityIdentifier("targets.\(id).value")
            }
        }
        .accessibilityValue("\(value.wrappedValue) grams, recommended \(recommended)" as String)
        .accessibilityIdentifier("targets.\(id)")
    }
}
