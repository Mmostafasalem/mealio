import SwiftUI

// MARK: - Name

struct NameStepView: View {

    @Bindable var vm: OnboardingViewModel

    private enum Field { case firstName, lastName }
    @FocusState private var focusedField: Field?

    var body: some View {
        OnboardingScaffold(vm: vm, step: .name, title: "What's your name?",
                           subtitle: "So Nourlo knows what to call you. You can skip this.") {
            VStack(spacing: Spacing.lg) {
                field("First name", text: $vm.firstName, field: .firstName, contentType: .givenName)
                    .submitLabel(.next)
                    .onSubmit { focusedField = .lastName }
                field("Last name", text: $vm.lastName, field: .lastName, contentType: .familyName)
                    .submitLabel(.done)
                    .onSubmit { focusedField = nil }
            }
        } footer: {
            OnboardingNextButton(vm: vm, next: .gender, identifier: "onboarding.name.continue")
        }
    }

    private func field(_ label: String, text: Binding<String>, field: Field,
                       contentType: UITextContentType) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .font(.footnote.weight(.medium))
                .foregroundStyle(Color.labelSecondary)
            TextField("", text: text)
                .font(.title3)
                .textContentType(contentType)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.words)
                .focused($focusedField, equals: field)
                .padding(.horizontal, Spacing.lg)
                .frame(minHeight: 56)
                .background(Color.surface, in: RoundedRectangle(cornerRadius: Radius.tile, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: Radius.tile, style: .continuous)
                        .strokeBorder(focusedField == field ? Color.labelPrimary : Color.hairline,
                                      lineWidth: focusedField == field ? 1.5 : 1)
                )
                .accessibilityLabel(label)
        }
    }
}

// MARK: - Gender

struct GenderStepView: View {

    @Bindable var vm: OnboardingViewModel

    var body: some View {
        OnboardingScaffold(vm: vm, step: .gender, title: "What's your gender?",
                           subtitle: "It changes how your daily calories are estimated.") {
            OnboardingOptionList {
                ForEach(Gender.allCases) { gender in
                    OnboardingOptionRow(symbol: symbol(for: gender), title: gender.displayName,
                                        isSelected: vm.gender == gender) { vm.gender = gender }
                }
            }
        } footer: {
            OnboardingNextButton(vm: vm, next: .age, identifier: "onboarding.gender.continue")
        }
    }

    private func symbol(for gender: Gender) -> String {
        switch gender {
        case .male:   return "figure.stand"
        case .female: return "figure.stand.dress"
        case .other:  return "person.fill"
        }
    }
}

// MARK: - Age

struct AgeStepView: View {

    @Bindable var vm: OnboardingViewModel

    private var age: Binding<Double> {
        Binding(get: { Double(vm.age) }, set: { vm.age = Int($0.rounded()) })
    }

    var body: some View {
        OnboardingScaffold(vm: vm, step: .age, title: "How old are you?", contentPadding: 0) {
            VStack(spacing: Spacing.sm) {
                Spacer()
                OnboardingReadout(number: "\(vm.age)", unit: "years")
                RulerPicker(value: age, range: 10...100, step: 1,
                            accessibilityName: "Age", spokenValue: { "\(Int($0)) years" })
                    .frame(height: 130)
                Spacer()
                Spacer()
            }
        } footer: {
            OnboardingNextButton(vm: vm, next: .height, identifier: "onboarding.age.continue")
        }
    }
}

// MARK: - Height

struct HeightStepView: View {

    @Bindable var vm: OnboardingViewModel
    @AppStorage(Constants.Storage.heightUnit) private var unit: HeightUnit = .cm

    /// The marker line sits this far down the ruler; the figure stands under it.
    private let anchor: CGFloat = 0.22

    var body: some View {
        OnboardingScaffold(vm: vm, step: .height, title: "What's your height?", contentPadding: 0) {
            VStack(spacing: Spacing.md) {
                UnitToggle(selection: $unit, options: HeightUnit.allCases, label: \.label,
                           accessibilityName: "Height unit")
                GeometryReader { geo in
                    let lineY = geo.size.height * anchor
                    ZStack(alignment: .topLeading) {
                        HeightRuler(centimetres: $vm.height, unit: unit, axis: .vertical,
                                    anchor: anchor, showsMarker: false)

                        // Head at the marker line, feet on the floor.
                        Image(systemName: vm.gender == .female ? "figure.stand.dress" : "figure.stand")
                            .resizable()
                            .scaledToFit()
                            .foregroundStyle(Color.progress)
                            .frame(width: geo.size.width * 0.5, height: max(0, geo.size.height - lineY - 6))
                            .offset(x: geo.size.width * 0.1, y: lineY + 6)
                            .opacity(0.85)
                            .allowsHitTesting(false)
                            .accessibilityHidden(true)

                        readout
                            .padding(.leading, Spacing.xl)
                            .frame(height: lineY, alignment: .bottomLeading)

                        HStack(spacing: 0) {
                            Circle().frame(width: 9, height: 9)
                            Rectangle().frame(height: 2)
                        }
                        .foregroundStyle(Color.labelPrimary)
                        .padding(.leading, Spacing.xl)
                        .offset(y: lineY - 4.5)
                        .allowsHitTesting(false)
                    }
                }
            }
        } footer: {
            OnboardingNextButton(vm: vm, next: .weight, identifier: "onboarding.height.continue")
        }
    }

    private var readout: some View {
        Group {
            if unit == .cm {
                OnboardingReadout(number: String(format: "%.0f", vm.height), unit: "cm")
            } else {
                OnboardingReadout(number: HeightRuler.text(vm.height, .ft))
            }
        }
        .scaleEffect(0.8, anchor: .bottomLeading)
        .allowsHitTesting(false)
    }
}

// MARK: - Weight

struct WeightStepView: View {

    @Bindable var vm: OnboardingViewModel
    @AppStorage(Constants.Storage.weightUnit) private var unit: WeightUnit = .kg

    var body: some View {
        OnboardingScaffold(vm: vm, step: .weight, title: "What's your current weight?", contentPadding: 0) {
            VStack(spacing: Spacing.sm) {
                UnitToggle(selection: $unit, options: WeightUnit.allCases, label: \.label,
                           accessibilityName: "Weight unit")
                Spacer()
                OnboardingReadout(number: WeightRuler.number(vm.weight, unit), unit: unit.suffix)
                WeightRuler(kilograms: $vm.weight, unit: unit)
                    .frame(height: 130)
                Spacer()
                Spacer()
            }
        } footer: {
            OnboardingNextButton(vm: vm, next: .activity, identifier: "onboarding.weight.continue")
        }
    }
}

// MARK: - Activity

struct ActivityStepView: View {

    @Bindable var vm: OnboardingViewModel

    var body: some View {
        OnboardingScaffold(vm: vm, step: .activity, title: "How active are you?") {
            OnboardingOptionList {
                ForEach(ActivityLevel.allCases) { level in
                    OnboardingOptionRow(symbol: level.sfSymbol, title: level.displayName,
                                        subtitle: level.description,
                                        isSelected: vm.activityLevel == level) { vm.activityLevel = level }
                }
            }
        } footer: {
            OnboardingNextButton(vm: vm, next: .goal, identifier: "onboarding.activity.continue")
        }
    }
}

#Preview("Height") { NavigationStack { HeightStepView(vm: OnboardingViewModel()) } }
#Preview("Weight") { NavigationStack { WeightStepView(vm: OnboardingViewModel()) } }
#Preview("Activity") { NavigationStack { ActivityStepView(vm: OnboardingViewModel()) } }
