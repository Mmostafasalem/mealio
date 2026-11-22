import SwiftUI

// MARK: - Your week (the same settings as Profile › Your week and meals)

struct WeekStepView: View {

    @Bindable var vm: OnboardingViewModel
    @AppStorage(WeeklyReset.startDayKey) private var weekStartDay = 2
    @AppStorage(WeeklyReset.askKey) private var weeklyResetAsk = true
    @State private var split = MealSplit.current

    var body: some View {
        OnboardingScaffold(vm: vm, step: .week, title: "Your week and meals",
                           subtitle: "You can change these later in Profile.") {
            OnboardingOptionList {
                SetupCard(title: "Week starts on") {
                    HStack(spacing: 6) {
                        ForEach(WeeklyReset.dayNames, id: \.day) { entry in
                            let chosen = weekStartDay == entry.day
                            Button { weekStartDay = entry.day } label: {
                                Text(String(entry.name.prefix(2)))
                                    .font(.footnote.weight(.semibold))
                                    .frame(maxWidth: .infinity, minHeight: 44)
                                    .background(Color.surfaceSecondary, in: RoundedRectangle(cornerRadius: Radius.chip, style: .continuous))
                                    .overlay(RoundedRectangle(cornerRadius: Radius.chip, style: .continuous)
                                        .strokeBorder(chosen ? Color.progress : Color.clear, lineWidth: 2))
                                    .foregroundStyle(Color.labelPrimary)
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(entry.name)
                            .accessibilityAddTraits(chosen ? .isSelected : [])
                            .accessibilityIdentifier("onboarding.week.day.\(entry.day)")
                        }
                    }
                }

                SetupCard(title: "Daily calorie split", note: "Always 100%: raising one meal takes from the biggest other.") {
                    ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(MealSplit.presets, id: \.name) { preset in
                            let chosen = preset.split == split
                            Button {
                                split = preset.split
                                MealSplit.current = preset.split
                            } label: {
                                Text(preset.name)
                                    .font(.footnote.weight(.semibold))
                                    .padding(.horizontal, Spacing.md)
                                    .frame(minHeight: 44)
                                    .background(Color.surfaceSecondary, in: Capsule())
                                    .overlay(Capsule().strokeBorder(chosen ? Color.progress : Color.clear, lineWidth: 2))
                                    .foregroundStyle(Color.labelPrimary)
                            }
                            .buttonStyle(.plain)
                            .accessibilityAddTraits(chosen ? .isSelected : [])
                        }
                    }
                    .padding(.horizontal, Spacing.lg)
                    }
                    .padding(.horizontal, -Spacing.lg)
                    VStack(spacing: 0) {
                    ForEach(MealSplit.Meal.allCases) { meal in
                        SplitRow(meal: meal, split: split, dailyKcal: vm.liveDailyGoal) { step in
                            if let next = split.adjusting(meal, by: step) {
                                split = next
                                MealSplit.current = next
                            }
                        }
                    }
                    }
                }

                SetupCard {
                    SetupToggleRow(symbol: "arrow.counterclockwise", title: "Ask to empty cart and stock each week",
                                   detail: nil,
                                   isOn: $weeklyResetAsk, identifier: "onboarding.week.reset")
                }
            }
            .onChange(of: weekStartDay) { _, _ in WeeklyReset.startDayChanged() }
        } footer: {
            OnboardingNextButton(vm: vm, from: .week, identifier: "onboarding.week.continue")
        }
    }
}

// MARK: - Reminders and Apple Health (all off until switched on)

struct AlertsStepView: View {

    @Bindable var vm: OnboardingViewModel
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false
    @State private var reminders = ReminderStore.shared
    @State private var health = HealthService.shared

    private var bell: Binding<Bool> {
        Binding(get: { reminders.isEnabled }, set: { on in Task { await reminders.setEnabled(on) } })
    }

    private var healthOn: Binding<Bool> {
        Binding(get: { health.isEnabled }, set: { on in Task { await health.setEnabled(on) } })
    }

    var body: some View {
        OnboardingScaffold(vm: vm, step: .alerts, title: "Reminders and Health",
                           subtitle: "All optional. Change them and the times any time in Profile.") {
            OnboardingOptionList {
                SetupCard {
                    SetupToggleRow(symbol: "heart.text.square", title: "Apple Health",
                                   detail: health.isAvailable ? "Saves food and workouts, reads weight and steps" : "Not available on this device",
                                   isOn: healthOn, identifier: "onboarding.alerts.health")
                        .disabled(!health.isAvailable || health.isRequesting)
                }

                SetupCard {
                    SetupToggleRow(symbol: "bell", title: "Reminders",
                                   detail: reminders.permissionDenied
                                       ? "Notifications are off for Nourlo in iOS Settings."
                                       : "Then pick which ones below",
                                   isOn: bell, identifier: "onboarding.alerts.reminders")
                    // Every alert as a chip: outlined when on, times in Profile › Reminders.
                    FlowLayout(spacing: 8) {
                        // Only reminders for the features chosen: workouts, or meals to log.
                        ForEach(reminders.reminders.filter { FeatureLayout.offersReminder($0.kind, vm.features) }) { reminder in
                            AlertChip(symbol: reminder.symbol, title: reminder.title, detail: nil,
                                      isOn: reminder.isOn, identifier: "onboarding.alerts." + reminder.id) {
                                var next = reminder; next.isOn.toggle(); reminders.update(next)
                            }
                        }
                        AlertChip(symbol: "bolt.heart", title: "Streak nudge", detail: nil,
                                  isOn: reminders.streakNudgeOn, identifier: "onboarding.alerts.streak") {
                            Task { await reminders.setStreakNudge(!reminders.streakNudgeOn) }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .disabled(!reminders.isEnabled)
                    .opacity(reminders.isEnabled ? 1 : 0.4)
                }
            }
            .task { await reminders.refreshPermission() }
        } footer: {
            Button {
                vm.finish()
                hasCompletedOnboarding = true
            } label: {
                Text("Done").primaryButtonLabel()
            }
            .buttonStyle(ScalePressStyle())
            .accessibilityIdentifier("onboarding.alerts.finish")
        }
    }
}

// MARK: - Your own split

extension MealSplit {
    enum Meal: String, CaseIterable, Identifiable {
        case breakfast, lunch, dinner, snack
        var id: String { rawValue }
        var title: String { rawValue.capitalized }
        /// Breakfast, lunch and dinner keep at least 5%; the snack can be left out.
        var range: ClosedRange<Int> { self == .snack ? 0...30 : 5...60 }
    }

    subscript(meal: Meal) -> Int {
        get {
            switch meal { case .breakfast: breakfast; case .lunch: lunch; case .dinner: dinner; case .snack: snack }
        }
        set {
            switch meal {
            case .breakfast: breakfast = newValue
            case .lunch: lunch = newValue
            case .dinner: dinner = newValue
            case .snack: snack = newValue
            }
        }
    }

    /// `meal` moved by `step` percent, the difference taken from (or given to) the
    /// biggest other meal that can move, so the day still adds up to 100%.
    /// Nil when nothing can move that way.
    func adjusting(_ meal: Meal, by step: Int) -> MealSplit? {
        guard meal.range.contains(self[meal] + step) else { return nil }
        let other = Meal.allCases
            .filter { $0 != meal && $0.range.contains(self[$0] - step) }
            .max { self[$0] < self[$1] }
        guard let other else { return nil }
        var next = self
        next[meal] += step
        next[other] -= step
        return next
    }
}

private struct SplitRow: View {
    let meal: MealSplit.Meal
    let split: MealSplit
    let dailyKcal: Int
    let change: (Int) -> Void

    var body: some View {
        HStack(spacing: Spacing.sm) {
            Text(meal.title)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(Color.labelPrimary)
            Spacer(minLength: Spacing.xs)
            Text("\(dailyKcal * split[meal] / 100) kcal" as String)
                .font(.caption)
                .monospacedDigit()
                .foregroundStyle(Color.labelSecondary)
            stepButton("minus", step: -5)
            Text("\(split[meal])%" as String)
                .font(.subheadline.weight(.semibold))
                .monospacedDigit()
                .frame(minWidth: 44)
                .contentTransition(.numericText())
            stepButton("plus", step: 5)
        }
        .frame(minHeight: 40)
        .animation(.snappyValue, value: split[meal])
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(meal.title)
        .accessibilityValue("\(split[meal]) percent" as String)
        .accessibilityAdjustableAction { direction in
            change(direction == .increment ? 5 : -5)
        }
    }

    private func stepButton(_ symbol: String, step: Int) -> some View {
        Button { change(step) } label: {
            Image(systemName: symbol)
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(Color.labelPrimary)
                .frame(width: 32, height: 32)
                .background(Color.surfaceSecondary, in: Circle())
                .frame(width: 44, height: 40)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(split.adjusting(meal, by: step) == nil)
        .opacity(split.adjusting(meal, by: step) == nil ? 0.35 : 1)
        .accessibilityIdentifier("onboarding.split.\(meal.rawValue).\(step > 0 ? "plus" : "minus")")
    }
}

private struct AlertChip: View {
    let symbol: String
    let title: String
    let detail: String?
    let isOn: Bool
    let identifier: String
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 6) {
                Image(systemName: symbol).font(.caption.weight(.semibold))
                Text(title).font(.footnote.weight(.semibold))
                if let detail {
                    Text(detail).font(.caption2).monospacedDigit().foregroundStyle(Color.labelSecondary)
                }
            }
            .foregroundStyle(Color.labelPrimary)
            .padding(.horizontal, Spacing.md)
            .frame(minHeight: 40)
            .background(Color.surfaceSecondary, in: Capsule())
            .overlay(Capsule().strokeBorder(isOn ? Color.progress : Color.clear, lineWidth: 2))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .sensoryFeedback(.selection, trigger: isOn)
        .accessibilityLabel(title + " reminder")
        .accessibilityValue(isOn ? "On" : "Off")
        .accessibilityAddTraits(isOn ? .isSelected : [])
        .accessibilityIdentifier(identifier)
    }
}

// MARK: - Shared pieces

private struct SetupCard<Content: View>: View {
    var title: String? = nil
    var note: String? = nil
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            if let title {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.body.weight(.semibold))
                        .foregroundStyle(Color.labelPrimary)
                    if let note {
                        Text(note)
                            .font(.caption)
                            .foregroundStyle(Color.labelSecondary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                    }
                }
            }
            content()
        }
        .padding(.horizontal, Spacing.lg)
        .padding(.vertical, Spacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.surface, in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Radius.card, style: .continuous).strokeBorder(Color.hairline, lineWidth: 1))
    }
}

private struct SetupToggleRow: View {
    let symbol: String
    let title: String
    var detail: String? = nil
    let isOn: Binding<Bool>
    let identifier: String

    var body: some View {
        HStack(spacing: Spacing.md) {
            Image(systemName: symbol)
                .foregroundStyle(Color.labelPrimary)
                .frame(width: 26)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(Color.labelPrimary)
                if let detail {
                    Text(detail)
                        .font(.caption)
                        .foregroundStyle(Color.labelSecondary)
                        .lineLimit(2)
                }
            }
            Spacer(minLength: Spacing.sm)
            Toggle(isOn: isOn) { EmptyView() }
                .toggleStyle(.spring)
                .fixedSize()
                .accessibilityLabel(title)
                .accessibilityIdentifier(identifier)
        }
        .frame(minHeight: 44)
    }
}

#Preview("Week") { NavigationStack { WeekStepView(vm: OnboardingViewModel()) } }
#Preview("Alerts") { NavigationStack { AlertsStepView(vm: OnboardingViewModel()) } }
