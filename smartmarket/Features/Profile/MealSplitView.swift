import SwiftUI

/// Profile › Meal plan › Daily calorie split: how the day's calories are shared
/// between breakfast, lunch, dinner and a snack. Every day of the plan follows it.
struct MealSplitView: View {
    @State private var split = MealSplit.current
    @State private var saved = MealSplit.current
    @State private var appState = AppState.shared

    private var target: Int {
        appState.bmrData?.calories(forGoal: appState.userProfile.weightGoal.rawValue) ?? 2000
    }

    var body: some View {
        Form {
            Section {
                ForEach(MealSplit.presets, id: \.name) { preset in
                    Button { split = preset.split } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(preset.name).foregroundStyle(Color.labelPrimary)
                                Text(describe(preset.split)).font(.caption).foregroundStyle(Color.labelSecondary)
                            }
                            Spacer()
                            if split == preset.split { Image(systemName: "checkmark").foregroundStyle(Color.labelPrimary) }
                        }
                    }
                    .accessibilityIdentifier("mealSplit.preset.\(preset.name)")
                }
            } header: { Text("Choose a split") }

            Section {
                row("Breakfast", $split.breakfast, range: 5...60)
                row("Lunch", $split.lunch, range: 5...60)
                row("Dinner", $split.dinner, range: 5...60)
                row("Snack", $split.snack, range: 0...30)
            } header: {
                Text("Or set your own")
            } footer: {
                if split.total != 100 {
                    Text("These add up to \(split.total)%. Make them add up to 100% to save." as String)
                        .foregroundStyle(Color.brandDanger)
                } else {
                    Text("Each day of your plan follows this split. A snack of 0% leaves the snack out.")
                }
            }
        }
        .navigationTitle("Daily calorie split")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") { MealSplit.current = split; saved = split }
                    .fontWeight(.semibold)
                    .disabled(!split.isValid || split == saved)
                    .accessibilityIdentifier("mealSplit.save")
            }
        }
    }

    private func row(_ name: String, _ value: Binding<Int>, range: ClosedRange<Int>) -> some View {
        Stepper(value: value, in: range, step: 5) {
            HStack {
                Text(name)
                Spacer()
                Text("\(value.wrappedValue)% · \(target * value.wrappedValue / 100) kcal" as String)
                    .foregroundStyle(Color.labelSecondary).monospacedDigit()
            }
        }
    }

    private func describe(_ s: MealSplit) -> String {
        "Breakfast \(s.breakfast)% · lunch \(s.lunch)% · dinner \(s.dinner)%" + (s.snack > 0 ? " · snack \(s.snack)%" : "")
    }
}
