import SwiftUI

struct BMRInputView: View {

    @Bindable var vm: OnboardingViewModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private enum Field { case firstName, lastName }
    @FocusState private var focusedField: Field?

    var body: some View {

        ScrollView {
            VStack(alignment: .leading, spacing: 28) {

                OnboardingProgressBar(currentStep: 1)
                    .padding(.top, 8)

                // Header
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 10) {
                        ZStack {
                            Circle().fill(Color.brandPrimary.opacity(0.12)).frame(width: 40, height: 40)
                            Image(systemName: "person.crop.circle.fill")
                                .font(.system(size: 20))
                                .foregroundStyle(Color.brandPrimary)
                        }
                        Text("Step 1 of 5")
                            .font(.caption).fontWeight(.semibold)
                            .foregroundStyle(Color.brandPrimary)
                            .padding(.horizontal, 10).padding(.vertical, 4)
                            .background(Color.brandPrimary.opacity(0.1), in: Capsule())
                    }
                    Text("Tell us about\nyourself")
                        .font(.system(size: 32, weight: .bold, design: .rounded))
                        .lineSpacing(2)
                    Text("We use this to calculate your personal daily calorie needs.")
                        .font(.subheadline)
                        .foregroundStyle(Color.labelSecondary)
                }
                .padding(.horizontal, 24)

                // Name fields
                VStack(spacing: 12) {
                    // First name
                    HStack(spacing: 12) {
                        Image(systemName: "person.fill")
                            .foregroundStyle(Color.brandPrimary)
                            .frame(width: 22)
                        TextField("First name", text: $vm.firstName)
                            .font(.subheadline)
                            .autocorrectionDisabled()
                            .textInputAutocapitalization(.words)
                            .focused($focusedField, equals: .firstName)
                            .submitLabel(.next)
                            .onSubmit { focusedField = .lastName }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .background(Color.surface)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .strokeBorder(
                                focusedField == .firstName ? Color.brandPrimary : Color(.separator),
                                lineWidth: focusedField == .firstName ? 1.5 : 0.5
                            )
                    )

                    // Last name
                    HStack(spacing: 12) {
                        Image(systemName: "person.fill")
                            .foregroundStyle(Color.brandPrimary)
                            .frame(width: 22)
                        TextField("Last name", text: $vm.lastName)
                            .font(.subheadline)
                            .autocorrectionDisabled()
                            .textInputAutocapitalization(.words)
                            .focused($focusedField, equals: .lastName)
                            .submitLabel(.done)
                            .onSubmit { focusedField = nil }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .background(Color.surface)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .strokeBorder(
                                focusedField == .lastName ? Color.brandPrimary : Color(.separator),
                                lineWidth: focusedField == .lastName ? 1.5 : 0.5
                            )
                    )
                }
                .padding(.horizontal, 24)

                // Body stats
                VStack(spacing: 20) {

                    // Weight
                    SliderRow(
                        label: "Weight",
                        value: $vm.weight,
                        range: 40...150,
                        step: 0.5,
                        unit: "kg",
                        sfSymbol: "scalemass.fill"
                    )

                    // Height
                    SliderRow(
                        label: "Height",
                        value: $vm.height,
                        range: 140...220,
                        step: 1,
                        unit: "cm",
                        sfSymbol: "ruler.fill"
                    )

                    // Age
                    AgeRow(age: $vm.age)

                    Divider().padding(.horizontal, 24)

                    // Gender
                    GenderRow(gender: $vm.gender)

                    Divider().padding(.horizontal, 24)

                    // Activity level
                    ActivityLevelSection(selected: $vm.activityLevel)
                }

                // Live BMR preview card
                BMRPreviewCard(
                    bmr: vm.liveBMR,
                    tdee: vm.liveTDEE,
                    reduceMotion: reduceMotion
                )
                .padding(.horizontal, 24)

                // Continue button — disabled until required body stats are entered
                let inputValid = vm.weight > 0 && vm.height > 0 && vm.age > 0 && vm.age < 130
                NavigationLink(value: OnboardingStep.location) {
                    Label("Continue", systemImage: "arrow.right")
                        .primaryButtonLabel(enabled: inputValid)
                }
                .disabled(!inputValid)
                .accessibilityIdentifier("onboarding.body.continue")
                .padding(.horizontal, Spacing.xl)
                .padding(.bottom, Spacing.xxl)
            }
        }
        .navigationBarHidden(true)
        .background(Color.surfaceGrouped.ignoresSafeArea())
    }
}

// MARK: - Subviews

private struct SliderRow: View {
    let label: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    let step: Double
    let unit: String
    let sfSymbol: String

    @State private var textValue: String = ""
    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: sfSymbol)
                    .foregroundStyle(Color.brandPrimary)
                    .frame(width: 22)
                Text(label)
                    .font(.subheadline).fontWeight(.medium)
                Spacer()
                HStack(spacing: 4) {
                    TextField("", text: $textValue)
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                        .font(.subheadline).fontWeight(.semibold)
                        .foregroundStyle(Color.brandPrimary)
                        .focused($focused)
                        .frame(width: 56)
                        .onSubmit { commitText() }
                    Text(unit)
                        .font(.subheadline)
                        .foregroundStyle(Color.labelSecondary)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(Color.surfaceSecondary)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .strokeBorder(focused ? Color.brandPrimary : Color.clear, lineWidth: 1.5)
                )
            }
            Slider(value: $value, in: range, step: step)
                .tint(Color.brandPrimary)
                .onChange(of: value) { _, _ in
                    if !focused { syncText() }
                }
        }
        .padding(.horizontal, 24)
        .onAppear { syncText() }
        .onChange(of: focused) { _, isFocused in
            if !isFocused { commitText() }
        }
    }

    private func syncText() {
        textValue = step < 1
            ? String(format: "%.1f", value)
            : String(format: "%.0f", value)
    }

    private func commitText() {
        let normalised = textValue.replacingOccurrences(of: ",", with: ".")
        if let v = Double(normalised) {
            let clamped = min(max(v, range.lowerBound), range.upperBound)
            let rounded = (clamped / step).rounded() * step
            value = rounded
        }
        syncText()
    }
}

private struct AgeRow: View {
    @Binding var age: Int
    @State private var ageString: String = ""

    var body: some View {
        HStack {
            Image(systemName: "calendar")
                .foregroundStyle(Color.brandPrimary)
                .frame(width: 22)
            Text("Age")
                .font(.subheadline).fontWeight(.medium)
            Spacer()
            TextField("25", text: $ageString)
                .keyboardType(.numberPad)
                .multilineTextAlignment(.trailing)
                .font(.subheadline).fontWeight(.semibold)
                .foregroundStyle(Color.brandPrimary)
                .frame(width: 60)
                .onChange(of: ageString) { _, new in
                    if let v = Int(new), (10...100).contains(v) { age = v }
                }
        }
        .padding(.horizontal, 24)
        .onAppear { ageString = "\(age)" }
    }
}

private struct GenderRow: View {
    @Binding var gender: Gender

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: "person.fill")
                    .foregroundStyle(Color.brandPrimary)
                    .frame(width: 22)
                Text("Gender")
                    .font(.subheadline).fontWeight(.medium)
            }
            .padding(.horizontal, 24)

            Picker("Gender", selection: $gender) {
                ForEach(Gender.allCases) { g in
                    Text(g.displayName).tag(g)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 24)
        }
    }
}

private struct ActivityLevelSection: View {
    @Binding var selected: ActivityLevel

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: "flame.fill")
                    .foregroundStyle(Color.brandPrimary)
                    .frame(width: 22)
                Text("Activity level")
                    .font(.subheadline).fontWeight(.medium)
            }
            .padding(.horizontal, 24)

            VStack(spacing: 2) {
                ForEach(ActivityLevel.allCases) { level in
                    ActivityRow(level: level, isSelected: selected == level) {
                        selected = level
                    }
                }
            }
        }
    }
}

private struct ActivityRow: View {
    let level: ActivityLevel
    let isSelected: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 14) {
                Image(systemName: level.sfSymbol)
                    .font(.system(size: 18))
                    .foregroundStyle(isSelected ? Color.brandPrimary : .secondary)
                    .frame(width: 26)

                VStack(alignment: .leading, spacing: 2) {
                    Text(level.displayName)
                        .font(.subheadline).fontWeight(.medium)
                        .foregroundStyle(isSelected ? Color.brandPrimary : .primary)
                    Text(level.description)
                        .font(.caption)
                        .foregroundStyle(Color.labelSecondary)
                }

                Spacer()

                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(Color.brandPrimary)
                }
            }
            .padding(.vertical, 10)
            .padding(.horizontal, 24)
            .background(isSelected ? Color.brandPrimary.opacity(0.07) : Color.clear)
        }
        .buttonStyle(.plain)
        .sensoryFeedback(.selection, trigger: isSelected)
        .animation(.spring(duration: 0.2), value: isSelected)
    }
}

private struct BMRPreviewCard: View {
    let bmr: Int
    let tdee: Int
    let reduceMotion: Bool

    @State private var appeared = false

    var body: some View {
        VStack(spacing: 4) {
            Text("Your estimated BMR")
                .font(.caption)
                .foregroundStyle(Color.labelSecondary)

            Text("\(bmr)")
                .font(.system(size: 48, weight: .bold, design: .rounded))
                .foregroundStyle(Color.brandPrimary)
                .monospacedDigit()
                .contentTransition(.numericText())
                .animation(reduceMotion ? .none : .spring(duration: 0.4), value: bmr)

            Text("kcal / day at rest")
                .font(.caption)
                .foregroundStyle(Color.labelSecondary)

            Divider().padding(.vertical, 4)

            HStack {
                Image(systemName: "flame.fill")
                    .foregroundStyle(Color.brandAmber)
                Text("With activity: **\(tdee) kcal / day** (TDEE)")
                    .font(.subheadline)
            }
        }
        .multilineTextAlignment(.center)
        .padding(20)
        .background(Color.surface)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .strokeBorder(Color(.separator), lineWidth: 0.5)
        )
    }
}

#Preview {
    NavigationStack {
        BMRInputView(vm: OnboardingViewModel())
    }
}
