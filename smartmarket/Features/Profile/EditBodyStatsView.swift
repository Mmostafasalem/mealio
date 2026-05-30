import SwiftUI

struct EditBodyStatsView: View {

    @Bindable var vm: ProfileViewModel

    @State private var firstName: String = ""
    @State private var lastName: String = ""

    var body: some View {
        Form {
            Section("Name") {
                HStack {
                    Image(systemName: "person.fill")
                        .foregroundStyle(Color.brandPrimary)
                        .frame(width: 22)
                    TextField("First name", text: $firstName)
                        .textContentType(.givenName)
                        .onChange(of: firstName) { _, _ in syncName() }
                }
                HStack {
                    Image(systemName: "person.fill")
                        .foregroundStyle(Color.brandPrimary)
                        .frame(width: 22)
                    TextField("Last name", text: $lastName)
                        .textContentType(.familyName)
                        .onChange(of: lastName) { _, _ in syncName() }
                }
            }

            Section("Body") {
                StatSlider(label: "Weight", value: $vm.profile.weight, range: 40...150, step: 0.5, unit: "kg", symbol: "scalemass.fill")
                StatSlider(label: "Height", value: $vm.profile.height, range: 140...220, step: 1, unit: "cm", symbol: "ruler.fill")
                Stepper(value: $vm.profile.age, in: 10...100) {
                    HStack {
                        Image(systemName: "calendar").foregroundStyle(Color.brandPrimary).frame(width: 22)
                        Text("Age")
                        Spacer()
                        Text("\(vm.profile.age)").foregroundStyle(Color.brandPrimary).monospacedDigit()
                    }
                }
            }

            Section("Gender") {
                Picker("Gender", selection: $vm.profile.gender) {
                    ForEach(Gender.allCases) { Text($0.displayName).tag($0) }
                }
                .pickerStyle(.segmented)
            }

            Section("Activity level") {
                Picker("Activity", selection: $vm.profile.activityLevel) {
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
        .navigationTitle("Body Stats")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { loadName() }
        .onDisappear { vm.save() }
    }

    private func loadName() {
        let parts = vm.profile.name.split(separator: " ", maxSplits: 1)
        firstName = parts.indices.contains(0) ? String(parts[0]) : ""
        lastName  = parts.indices.contains(1) ? String(parts[1]) : ""
    }

    private func syncName() {
        let full = [firstName, lastName]
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        vm.profile.name = full.isEmpty ? "" : full
    }

    private var liveBMR: Int {
        Int(BMRCalculator.bmr(weight: vm.profile.weight, height: vm.profile.height,
                              age: vm.profile.age, gender: vm.profile.gender).rounded())
    }
}

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

#Preview {
    NavigationStack { EditBodyStatsView(vm: ProfileViewModel()) }
}
