import SwiftUI

struct EditBodyStatsView: View {

    @Bindable var vm: ProfileViewModel

    // Completely isolated local state variables
    @State private var firstName: String = ""
    @State private var lastName: String = ""
    @State private var weight: Double = 70.0
    @State private var height: Double = 170.0
    @State private var age: Int = 30
    @State private var gender: Gender = .male
    @State private var activityLevel: ActivityLevel = .sedentary
    
    @AppStorage(Constants.Storage.weightUnit) private var weightUnit: WeightUnit = .kg
    @AppStorage(Constants.Storage.heightUnit) private var heightUnit: HeightUnit = .cm

    @FocusState private var focusedField: Field?
    /// Edits save shortly after they stop, so a killed app keeps them.
    @State private var saveTask: Task<Void, Never>?
    @State private var isReady = false
    /// The goal was "lose weight" when this screen opened. Under 18 it is
    /// saved as maintain; raising the age again here brings it back.
    @State private var goalWasLose = false

    private enum Field {
        case firstName
        case lastName
    }

    var body: some View {
        // Fix 1: Changed from 'Form' to 'List' with 'InsetGroupedListStyle'
        // This stops the infinite cell height recalculation loop when the keyboard mounts.
        List {
            Section("Name") {
                HStack {
                    Image(systemName: "person.fill")
                        .foregroundStyle(Color.brandPrimary)
                        .frame(width: 22)
                    TextField("First name", text: $firstName)
                        .textContentType(.givenName)
                        .textInputAutocapitalization(.words)
                        .autocorrectionDisabled()
                        .focused($focusedField, equals: .firstName)
                        .submitLabel(.next)
                        .onSubmit { focusedField = .lastName }
                }
                HStack {
                    Image(systemName: "person.fill")
                        .foregroundStyle(Color.brandPrimary)
                        .frame(width: 22)
                    TextField("Last name", text: $lastName)
                        .textContentType(.familyName)
                        .textInputAutocapitalization(.words)
                        .autocorrectionDisabled()
                        .focused($focusedField, equals: .lastName)
                        .submitLabel(.done)
                        .onSubmit { focusedField = nil }
                }
            }

            Section("Body") {
                StatRuler(label: "Weight", symbol: "scalemass.fill", valueText: WeightRuler.text(weight, weightUnit)) {
                    UnitToggle(selection: $weightUnit, options: WeightUnit.allCases, label: \.label,
                               accessibilityName: "Weight unit")
                    TypeNumberButton(title: "Your weight", unit: weightUnit.suffix, current: WeightRuler.number(weight, weightUnit),
                                     identifier: "profile.weight.type") { text in
                        guard let number = TypedNumber.parse(text) else { return }
                        weight = weightUnit == .kg ? TypedNumber.fitted(number, range: WeightRuler.defaultRange, step: 0.5)
                                                   : WeightRuler.kilograms(fromPounds: number.rounded())
                    }
                } ruler: {
                    WeightRuler(kilograms: $weight, unit: weightUnit)
                }
                StatRuler(label: "Height", symbol: "ruler.fill", valueText: HeightRuler.text(height, heightUnit)) {
                    UnitToggle(selection: $heightUnit, options: HeightUnit.allCases, label: \.label,
                               accessibilityName: "Height unit")
                    TypeNumberButton(title: "Your height", unit: heightUnit == .cm ? "cm" : "feet and inches",
                                     current: heightUnit == .cm ? String(format: "%.0f", height) : HeightRuler.text(height, .ft),
                                     hint: heightUnit == .cm ? "Enter your height in centimetres." : "For example 5'11.",
                                     keyboard: heightUnit == .cm ? .numberPad : .numbersAndPunctuation,
                                     identifier: "profile.height.type") { text in
                        if heightUnit == .cm, let cm = TypedNumber.parse(text) {
                            height = TypedNumber.fitted(cm, range: HeightRuler.defaultRange, step: 1)
                        } else if heightUnit == .ft, let inches = TypedNumber.inches(text) {
                            height = HeightRuler.centimetres(fromInches: inches)
                        }
                    }
                } ruler: {
                    HeightRuler(centimetres: $height, unit: heightUnit)
                }
                
                Stepper(value: $age, in: Constants.Onboarding.minimumAge...Constants.Onboarding.maximumAge) {
                    HStack {
                        Image(systemName: "calendar").foregroundStyle(Color.brandPrimary).frame(width: 22)
                        Text("Age")
                        Spacer()
                        Text("\(age)").foregroundStyle(Color.brandPrimary).monospacedDigit()
                    }
                }
                if goalWasLose && !BMRCalculator.allowsWeightLoss(age: age) {
                    VStack(alignment: .leading, spacing: Spacing.xs) {
                        MinorGoalNote()
                        Text("Your goal is set to maintain weight.")
                            .font(.footnote).foregroundStyle(Color.labelSecondary)
                    }
                    .accessibilityElement(children: .combine)
                }
            }

            Section("Gender") {
                Picker("Gender", selection: $gender) {
                    ForEach(Gender.allCases) { Text($0.displayName).tag($0) }
                }
                .pickerStyle(.segmented)
            }

            Section("Activity level") {
                Picker("Activity", selection: $activityLevel) {
                    ForEach(ActivityLevel.allCases) { Text($0.displayName).tag($0) }
                }
                .pickerStyle(.inline)
                .labelsHidden()
            }

            Section {
                HStack {
                    Text("Estimated BMR")
                    Spacer()
                    Text("\(liveBMR) kcal")
                        .fontWeight(.semibold)
                        .foregroundStyle(Color.brandPrimary)
                        .monospacedDigit()
                }
            }
        }
        .listStyle(.insetGrouped) // Keeps the look exactly like a native Form
        .navigationTitle("Body Stats")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if focusedField != nil {
                ToolbarItem(placement: .keyboard) {
                    HStack {
                        Spacer()
                        Button("Done") { focusedField = nil }
                    }
                }
            }
        }
        .onAppear {
            // Edit local copies, isolated from the Observation layer.
            let parts = vm.profile.name.split(separator: " ", maxSplits: 1)
            firstName = parts.indices.contains(0) ? String(parts[0]) : ""
            lastName  = parts.indices.contains(1) ? String(parts[1]) : ""

            weight = vm.profile.weight
            height = vm.profile.height
            // Older data may hold an age outside the Stepper's range.
            age = min(max(vm.profile.age, Constants.Onboarding.minimumAge), Constants.Onboarding.maximumAge)
            goalWasLose = vm.profile.weightGoal == .lose
            gender = vm.profile.gender
            activityLevel = vm.profile.activityLevel
            isReady = true
        }
        .onChange(of: draft) { _, _ in scheduleSave() }
        .onDisappear {
            saveTask?.cancel()
            commit()
        }
    }

    private struct Draft: Equatable {
        var firstName: String, lastName: String
        var weight: Double, height: Double, age: Int
        var gender: Gender, activityLevel: ActivityLevel
    }

    private var draft: Draft {
        Draft(firstName: firstName, lastName: lastName, weight: weight, height: height, age: age,
              gender: gender, activityLevel: activityLevel)
    }

    private func scheduleSave() {
        guard isReady else { return }
        saveTask?.cancel()
        saveTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(600))
            guard !Task.isCancelled else { return }
            commit()
        }
    }

    /// Pushes the edits to the view model. `save()` skips (and posts nothing)
    /// when nothing actually changed.
    private func commit() {
        guard isReady else { return }
        let full = [firstName, lastName]
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .joined(separator: " ")

        vm.profile.name = full
        vm.profile.weight = weight
        vm.profile.height = height
        vm.profile.age = age
        vm.profile.gender = gender
        vm.profile.activityLevel = activityLevel
        // Saving moves an under-18 "lose" goal to maintain (see the note);
        // if the age goes back to 18 or over here, keep the original goal.
        if goalWasLose && BMRCalculator.allowsWeightLoss(age: age) { vm.profile.weightGoal = .lose }
        vm.save()
    }

    // Calculated instantly using pure local states without checking the server or VM properties
    private var liveBMR: Int {
        Int(BMRCalculator.bmr(weight: weight, height: height, age: age, gender: gender).rounded())
    }
}

/// A labelled ruler row: name and live value on top, unit switch, then the ruler.
private struct StatRuler<Toggle: View, Ruler: View>: View {
    let label: String
    let symbol: String
    let valueText: String
    @ViewBuilder var toggle: () -> Toggle
    @ViewBuilder var ruler: () -> Ruler

    var body: some View {
        VStack(spacing: Spacing.sm) {
            HStack {
                Image(systemName: symbol).foregroundStyle(Color.brandPrimary).frame(width: 22)
                Text(label)
                Spacer()
                HStack(spacing: Spacing.xs) { toggle() }.scaleEffect(0.85, anchor: .trailing)
            }
            Text(valueText)
                .font(.system(.title, design: .rounded).weight(.semibold))
                .monospacedDigit()
                .contentTransition(.numericText())
                .animation(.snappyValue, value: valueText)
                .accessibilityHidden(true)
            ruler().frame(height: 96)
        }
        .padding(.vertical, Spacing.xs)
    }
}
