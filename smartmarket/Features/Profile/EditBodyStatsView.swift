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
                } ruler: {
                    WeightRuler(kilograms: $weight, unit: weightUnit)
                }
                StatRuler(label: "Height", symbol: "ruler.fill", valueText: HeightRuler.text(height, heightUnit)) {
                    UnitToggle(selection: $heightUnit, options: HeightUnit.allCases, label: \.label,
                               accessibilityName: "Height unit")
                } ruler: {
                    HeightRuler(centimetres: $height, unit: heightUnit)
                }
                
                Stepper(value: $age, in: 10...100) {
                    HStack {
                        Image(systemName: "calendar").foregroundStyle(Color.brandPrimary).frame(width: 22)
                        Text("Age")
                        Spacer()
                        Text("\(age)").foregroundStyle(Color.brandPrimary).monospacedDigit()
                    }
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
            // Fix 2: Initialize local copies from the VM so editing happens
            // completely in isolation from the Observation layer.
            let parts = vm.profile.name.split(separator: " ", maxSplits: 1)
            firstName = parts.indices.contains(0) ? String(parts[0]) : ""
            lastName  = parts.indices.contains(1) ? String(parts[1]) : ""
            
            weight = vm.profile.weight
            height = vm.profile.height
            age = vm.profile.age
            gender = vm.profile.gender
            activityLevel = vm.profile.activityLevel
        }
        .onDisappear {
            // Fix 3: Push everything back to the view model all at once when the screen closes.
            let full = [firstName, lastName]
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }
                .joined(separator: " ")
            
            vm.profile.name = full.isEmpty ? "" : full
            vm.profile.weight = weight
            vm.profile.height = height
            vm.profile.age = age
            vm.profile.gender = gender
            vm.profile.activityLevel = activityLevel
            
            vm.save()
        }
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
                toggle().scaleEffect(0.85, anchor: .trailing)
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
