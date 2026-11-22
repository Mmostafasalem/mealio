import SwiftUI

// MARK: - About you (name, age, gender)

/// The first screen: who you are, on one page. Name and surname are optional
/// and sit side by side; age is a number with minus and plus (tap the number to
/// type it); gender is a three-way switch. Nothing scrolls: the fields you type
/// in sit above the keyboard even on a 667 pt screen, gender is under them.
struct NameStepView: View {

    @Bindable var vm: OnboardingViewModel

    private enum Field { case firstName, lastName, age }
    @FocusState private var focusedField: Field?
    @State private var ageText = ""
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private static let ageRange = Constants.Onboarding.minimumAge...Constants.Onboarding.maximumAge

    private var typedAge: Int? {
        // Any keyboard's digits ("٣٠") read as a number.
        guard let age = Int(TypedNumber.western(ageText)), Self.ageRange.contains(age) else { return nil }
        return age
    }

    var body: some View {
        OnboardingScaffold(vm: vm, step: .name, title: "About you",
                           subtitle: "Age and gender set your daily calories. Your name is optional.") {
            VStack(alignment: .leading, spacing: Spacing.lg) {
                HStack(alignment: .top, spacing: Spacing.md) {
                    field("First name", text: $vm.firstName, field: .firstName, contentType: .givenName)
                        .submitLabel(.next)
                        .onSubmit { focusedField = .lastName }
                    field("Surname", text: $vm.lastName, field: .lastName, contentType: .familyName)
                        .submitLabel(.done)
                        .onSubmit { focusedField = nil }
                }
                // Age sits above gender, so the keyboard never covers it on a small phone.
                ageStepper
                VStack(alignment: .leading, spacing: 6) {
                    label("Gender")
                    SpringSegmentedControl(selection: $vm.gender, options: Gender.allCases,
                                           label: \.displayName, accessibilityName: "Gender")
                }
            }
            .animation(reduceMotion ? nil : .smoothCard, value: focusedField == nil)
            // Tapping anywhere outside a field closes the keyboard too.
            .background(Color.clear.contentShape(Rectangle()).onTapGesture { focusedField = nil })
        } footer: {
            OnboardingNextButton(vm: vm, from: .name, identifier: "onboarding.name.continue")
                .disabled(typedAge == nil)
                .opacity(typedAge == nil ? 0.5 : 1)
        }
        // The page keeps its place when the keyboard comes up: no scrolling, no squeeze.
        .ignoresSafeArea(.keyboard, edges: .bottom)
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Done") { focusedField = nil }
                    .fontWeight(.semibold)
                    .accessibilityIdentifier("onboarding.keyboardDone")
            }
        }
        .onAppear { if ageText.isEmpty { ageText = String(vm.age) } }
        .onChange(of: ageText) { _, text in
            // Western digits only, three at most.
            let digits = String(TypedNumber.western(text).filter { $0.isASCII && $0.isNumber }.prefix(3))
            if digits != text { ageText = digits; return }
            if let typedAge { vm.age = typedAge }
        }
    }

    private func label(_ text: String) -> some View {
        Text(text)
            .font(.footnote.weight(.medium))
            .foregroundStyle(Color.labelSecondary)
    }

    private func fieldFrame<Content: View>(focused: Bool, invalid: Bool = false, padding: CGFloat = Spacing.lg,
                                             @ViewBuilder _ content: () -> Content) -> some View {
        content()
            .font(.body)
            .padding(.horizontal, padding)
            .frame(minHeight: 52)
            .background(Color.surface, in: RoundedRectangle(cornerRadius: Radius.tile, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: Radius.tile, style: .continuous)
                    .strokeBorder(invalid ? Color.brandDanger : focused ? Color.labelPrimary : Color.hairline,
                                  lineWidth: focused || invalid ? 1.5 : 1)
            )
    }

    private func field(_ title: String, text: Binding<String>, field: Field,
                       contentType: UITextContentType) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            label(title)
            fieldFrame(focused: focusedField == field) {
                TextField("", text: text)
                    .textContentType(contentType)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.words)
                    .focused($focusedField, equals: field)
                    .accessibilityLabel(title)
            }
        }
    }

    // MARK: Age

    /// One year down or up from the current age (or from the nearest limit when
    /// the box is empty or out of range).
    private func step(_ delta: Int) {
        let current = Int(TypedNumber.western(ageText)).map { min(max($0, Self.ageRange.lowerBound), Self.ageRange.upperBound) } ?? vm.age
        ageText = String(min(max(current + delta, Self.ageRange.lowerBound), Self.ageRange.upperBound))
    }

    private func stepButton(_ symbol: String, name: String, delta: Int, disabled: Bool) -> some View {
        Button { step(delta) } label: {
            Image(systemName: symbol)
                .font(.body.weight(.semibold))
                .foregroundStyle(Color.labelPrimary)
                .frame(width: 52, height: 52)
                .contentShape(Rectangle())
        }
        .buttonStyle(ScalePressStyle())
        .buttonRepeatBehavior(.enabled)
        .disabled(disabled)
        .opacity(disabled ? 0.35 : 1)
        .accessibilityLabel(name)
    }

    private var ageStepper: some View {
        VStack(alignment: .leading, spacing: 6) {
            label("Age")
            HStack(spacing: Spacing.md) {
                fieldFrame(focused: focusedField == .age, invalid: typedAge == nil && focusedField != .age, padding: 0) {
                    HStack(spacing: 0) {
                        stepButton("minus", name: "One year younger", delta: -1,
                                   disabled: (typedAge ?? Self.ageRange.upperBound) <= Self.ageRange.lowerBound)
                        HStack(alignment: .firstTextBaseline, spacing: 6) {
                            TextField("", text: $ageText)
                                .font(.title3.weight(.semibold))
                                .keyboardType(.numberPad)
                                .monospacedDigit()
                                .multilineTextAlignment(.trailing)
                                .focused($focusedField, equals: .age)
                                .fixedSize()
                                .frame(minWidth: 30)
                                .accessibilityLabel("Age in years")
                                .accessibilityIdentifier("onboarding.age")
                            Text("years")
                                .font(.subheadline)
                                .foregroundStyle(Color.labelSecondary)
                                .accessibilityHidden(true)
                        }
                        .frame(maxWidth: .infinity)
                        // Tapping anywhere in the middle starts typing.
                        .contentShape(Rectangle())
                        .onTapGesture { focusedField = .age }
                        stepButton("plus", name: "One year older", delta: 1,
                                   disabled: (typedAge ?? Self.ageRange.lowerBound) >= Self.ageRange.upperBound)
                    }
                }
                // The number pad has no return key and the keyboard bar doesn't always show,
                // so a plain button closes it. Beside the field, it stays above the keyboard.
                if focusedField != nil {
                    Button { focusedField = nil } label: {
                        Text("Done")
                            .font(.headline)
                            .foregroundStyle(Color.onAccent)
                            .padding(.horizontal, Spacing.xl)
                            .frame(minHeight: 52)
                            .background(Color.dullPink, in: Capsule())
                            .contentShape(Capsule())
                    }
                    .buttonStyle(ScalePressStyle())
                    .accessibilityIdentifier("onboarding.closeKeyboard")
                    .transition(.opacity)
                }
            }
            .sensoryFeedback(.selection, trigger: vm.age)
            if typedAge == nil {
                Text("Enter an age from \(Self.ageRange.lowerBound) to \(Self.ageRange.upperBound)." as String)
                    .font(.caption)
                    .foregroundStyle(Color.brandDanger)
            }
        }
    }
}

// MARK: - Height

struct HeightStepView: View {

    @Bindable var vm: OnboardingViewModel
    @AppStorage(Constants.Storage.heightUnit) private var unit: HeightUnit = .cm
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var mascot = MascotRig()
    /// 0 at the shortest height, 1 at the tallest. Starts small so Nourlo grows in.
    @State private var growth: Double = 0
    @State private var settleTask: Task<Void, Never>?

    private let range: ClosedRange<Double> = HeightRuler.defaultRange

    private var targetGrowth: Double {
        min(max((vm.height - range.lowerBound) / (range.upperBound - range.lowerBound), 0), 1)
    }

    var body: some View {
        OnboardingScaffold(vm: vm, step: .height, title: "What's your height?", contentPadding: 0) {
            VStack(spacing: Spacing.md) {
                HStack(spacing: Spacing.sm) {
                    UnitToggle(selection: $unit, options: HeightUnit.allCases, label: \.label,
                               accessibilityName: "Height unit")
                    TypeNumberButton(title: "Your height", unit: unit == .cm ? "cm" : "feet and inches",
                                     current: unit == .cm ? String(format: "%.0f", vm.height) : HeightRuler.text(vm.height, .ft),
                                     hint: unit == .cm ? "Enter your height in centimetres." : "For example 5'11.",
                                     keyboard: unit == .cm ? .numberPad : .numbersAndPunctuation,
                                     identifier: "onboarding.height.type") { text in
                        if unit == .cm, let cm = TypedNumber.parse(text) {
                            vm.height = TypedNumber.fitted(cm, range: range, step: 1)
                        } else if unit == .ft, let inches = TypedNumber.inches(text) {
                            vm.height = HeightRuler.centimetres(fromInches: inches, range: range)
                        }
                    }
                }
                HeightScene(growth: growth, height: $vm.height, unit: unit, range: range, pose: mascot.pose)
            }
        } footer: {
            OnboardingNextButton(vm: vm, from: .height, identifier: "onboarding.height.continue")
        }
        .onAppear {
            mascot.reduceMotion = reduceMotion
            mascot.set(mood: .happy)
            mascot.setActive(true)
            // Grow in from small, then say hello.
            withAnimation(reduceMotion ? .reducedFade : .spring(response: 0.7, dampingFraction: 0.62).delay(0.15)) {
                growth = targetGrowth
            }
            mascot.react(.tap)
        }
        .onDisappear {
            settleTask?.cancel()
            mascot.setActive(false)
        }
        .onChange(of: reduceMotion) { _, on in mascot.reduceMotion = on }
        .onChange(of: vm.height) { old, new in heightChanged(from: old, to: new) }
    }

    /// Nourlo stretches or squashes toward the new height, watches the marker
    /// while it moves, and does a little hop once the ruler comes to rest.
    private func heightChanged(from old: Double, to new: Double) {
        withAnimation(reduceMotion ? .reducedFade : .spring(response: 0.45, dampingFraction: 0.6)) {
            growth = targetGrowth
        }
        mascot.resize(by: (new - old) / 6)
        mascot.look(at: CGPoint(x: 0.5, y: -1))
        settleTask?.cancel()
        settleTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(0.6))
            guard !Task.isCancelled else { return }
            mascot.look(at: nil)
            mascot.hop()
        }
    }
}

/// The ruler, Nourlo and the marker line. `growth` is animatable, so a change
/// in height springs the mascot's size (and the line resting on its bowl)
/// instead of jumping.
private struct HeightScene: View, Animatable {
    var growth: Double
    @Binding var height: Double
    let unit: HeightUnit
    let range: ClosedRange<Double>
    let pose: MascotPose

    /// Share of the mascot's square frame that is empty above its bowl.
    private let headroom: CGFloat = 0.1

    var animatableData: Double {
        get { growth }
        set { growth = newValue }
    }

    var body: some View {
        GeometryReader { geo in
            // Nourlo stands on the floor; the marker line rests on top of the bowl.
            let tallest = max(0, min(geo.size.height - 64, geo.size.width * 0.62) / (1 - headroom))
            let size = max(1, tallest * (0.55 + 0.45 * CGFloat(growth)))
            let lineY = min(max(geo.size.height - size * (1 - headroom), 56), geo.size.height)
            ZStack(alignment: .topLeading) {
                HeightRuler(centimetres: $height, unit: unit, axis: .vertical,
                            anchor: lineY / max(geo.size.height, 1), showsMarker: false, range: range)

                MascotFigure(pose: pose, size: size)
                    .frame(width: size, height: size)
                    .offset(x: Spacing.lg, y: geo.size.height - size)
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

    private var readout: some View {
        Group {
            if unit == .cm {
                OnboardingReadout(number: String(format: "%.0f", height), unit: "cm")
            } else {
                OnboardingReadout(number: HeightRuler.text(height, .ft))
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
                HStack(spacing: Spacing.sm) {
                    UnitToggle(selection: $unit, options: WeightUnit.allCases, label: \.label,
                               accessibilityName: "Weight unit")
                    TypeNumberButton(title: "Your weight", unit: unit.suffix, current: WeightRuler.number(vm.weight, unit),
                                     identifier: "onboarding.weight.type") { text in
                        guard let number = TypedNumber.parse(text) else { return }
                        vm.weight = unit == .kg ? TypedNumber.fitted(number, range: WeightRuler.defaultRange, step: 0.5)
                                                : WeightRuler.kilograms(fromPounds: number.rounded())
                    }
                }
                Spacer()
                OnboardingReadout(number: WeightRuler.number(vm.weight, unit), unit: unit.suffix)
                WeightRuler(kilograms: $vm.weight, unit: unit)
                    .frame(height: 130)
                Spacer()
                Spacer()
            }
        } footer: {
            OnboardingNextButton(vm: vm, from: .weight, identifier: "onboarding.weight.continue")
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
            OnboardingNextButton(vm: vm, from: .activity, identifier: "onboarding.activity.continue")
        }
    }
}

#Preview("Height") { NavigationStack { HeightStepView(vm: OnboardingViewModel()) } }
#Preview("Weight") { NavigationStack { WeightStepView(vm: OnboardingViewModel()) } }
#Preview("Activity") { NavigationStack { ActivityStepView(vm: OnboardingViewModel()) } }
