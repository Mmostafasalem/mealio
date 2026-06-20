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
                StatSlider(label: "Weight", value: $weight, range: 40...150, step: 0.5, unit: "kg", symbol: "scalemass.fill")
                StatSlider(label: "Height", value: $height, range: 140...220, step: 1, unit: "cm", symbol: "ruler.fill")
                
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

// Keep this component isolated and clean
private struct StatSlider: View {
    let label: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    let step: Double
    let unit: String
    let symbol: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Image(systemName: symbol).foregroundStyle(Color.brandPrimary).frame(width: 22)
                Text(label)
                Spacer()
                Text("\(value, specifier: step < 1 ? "%.1f" : "%.0f") \(unit)")
                    .foregroundStyle(Color.brandPrimary).monospacedDigit()
            }
            Slider(value: $value, in: range, step: step).tint(Color.brandPrimary)
        }
    }
}
