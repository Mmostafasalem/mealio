import SwiftUI

/// Reminders for meals, training and logging: one bell to switch them all on,
/// then a time (and, for training, days) for each.
struct RemindersView: View {

    @State private var store = ReminderStore.shared
    @Environment(\.openURL) private var openURL
    @Environment(\.scenePhase) private var scenePhase

    private var bell: Binding<Bool> {
        Binding(get: { store.isEnabled }, set: { on in Task { await store.setEnabled(on) } })
    }

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: Spacing.md) {
                    BellButton(isOn: bell, label: "Reminders off", onLabel: "Reminders on",
                               count: store.reminders.filter(\.isOn).count)
                        .accessibilityIdentifier("reminders.bell")
                    Text("Gentle nudges for meals, training and logging. They are scheduled on this iPhone only; nothing is sent to a server.")
                        .font(.footnote)
                        .foregroundStyle(Color.labelSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                    if store.permissionDenied {
                        VStack(alignment: .leading, spacing: Spacing.sm) {
                            Label("Notifications are switched off for Nourlo in iOS Settings.", systemImage: "exclamationmark.triangle")
                                .font(.footnote)
                                .foregroundStyle(Color.labelPrimary)
                            Button("Open Settings") {
                                if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
                            }
                            .font(.footnote.weight(.semibold))
                        }
                    }
                }
                .padding(.vertical, Spacing.xs)
            }

            Section("Meals") {
                ForEach(store.reminders.filter { $0.mealSlot != nil }) { ReminderRow(reminder: $0, store: store) }
            }
            Section("Training and logging") {
                ForEach(store.reminders.filter { $0.mealSlot == nil }) { ReminderRow(reminder: $0, store: store) }
            }
            Section {
                HStack(spacing: Spacing.sm) {
                    Image(systemName: "bolt.heart")
                        .foregroundStyle(Color.labelPrimary)
                        .frame(width: 26)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Streak nudge")
                        Text("One evening note if today doesn't count yet")
                            .font(.footnote)
                            .foregroundStyle(Color.labelSecondary)
                    }
                    Spacer(minLength: Spacing.sm)
                    Toggle(isOn: Binding(get: { store.streakNudgeOn },
                                         set: { on in Task { await store.setStreakNudge(on) } })) { EmptyView() }
                        .toggleStyle(.spring)
                        .fixedSize()
                        .accessibilityLabel("Streak nudge")
                        .accessibilityIdentifier("reminders.toggle.streak")
                }
                .disabled(!store.isEnabled)
            } header: {
                Text("Streak")
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background { GrainyGradient().ignoresSafeArea() }
        .navigationTitle("Reminders")
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarHidden(false)
        .task { await store.refreshPermission() }
        // Back from Settings: the permission may have changed there.
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { Task { await store.refreshPermission() } }
        }
    }
}

private struct ReminderRow: View {
    let reminder: Reminder
    let store: ReminderStore
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private static let weekdayOrder = [2, 3, 4, 5, 6, 7, 1]      // Monday first
    private static let weekdayLetters = [1: "S", 2: "M", 3: "T", 4: "W", 5: "T", 6: "F", 7: "S"]
    private static let weekdayNames = [1: "Sunday", 2: "Monday", 3: "Tuesday", 4: "Wednesday", 5: "Thursday", 6: "Friday", 7: "Saturday"]

    private var time: Binding<Date> {
        Binding(
            get: {
                var c = DateComponents()
                c.hour = reminder.hour
                c.minute = reminder.minute
                return Calendar.current.date(from: c) ?? Date()
            },
            set: { date in
                var next = reminder
                let c = Calendar.current.dateComponents([.hour, .minute], from: date)
                next.hour = c.hour ?? reminder.hour
                next.minute = c.minute ?? reminder.minute
                store.update(next)
            })
    }

    private var isOn: Binding<Bool> {
        Binding(get: { reminder.isOn }, set: { on in var next = reminder; next.isOn = on; store.update(next) })
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            if dynamicTypeSize.isAccessibilitySize {
                // Large text: the title gets its own line, the controls sit under it.
                title
                HStack(spacing: Spacing.sm) {
                    timePicker
                    Spacer(minLength: Spacing.sm)
                    toggle
                }
            } else {
                HStack(spacing: Spacing.sm) {
                    title
                    Spacer(minLength: Spacing.sm)
                    timePicker
                    toggle
                }
            }
            if reminder.kind == .workout && reminder.isOn {
                HStack(spacing: 6) {
                    ForEach(Self.weekdayOrder, id: \.self) { day in
                        let chosen = reminder.weekdays.contains(day)
                        Button {
                            var next = reminder
                            if chosen { next.weekdays.remove(day) } else { next.weekdays.insert(day) }
                            store.update(next)
                        } label: {
                            Text(Self.weekdayLetters[day] ?? "")
                                .font(.footnote.weight(.semibold))
                                .frame(width: 36, height: 36)
                                .background(chosen ? Color.dullPink : Color.surfaceSecondary, in: Circle())
                                .foregroundStyle(chosen ? Color.onAccent : Color.labelPrimary)
                                // The circle stays small; the touch target is 44 pt.
                                .frame(maxWidth: .infinity, minHeight: 44)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(Self.weekdayNames[day] ?? "")
                        .accessibilityAddTraits(chosen ? .isSelected : [])
                    }
                }
                Text(reminder.weekdays.isEmpty ? "No days picked, so it reminds you every day." : "Reminds you on the days picked.")
                    .font(.caption)
                    .foregroundStyle(Color.labelSecondary)
            }
        }
        .padding(.vertical, 2)
    }

    private var title: some View {
        HStack(spacing: Spacing.sm) {
            Image(systemName: reminder.symbol)
                .foregroundStyle(Color.labelPrimary)
                .frame(width: 26)
                .accessibilityHidden(true)
            Text(reminder.title)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var timePicker: some View {
        DatePicker(reminder.title + " time", selection: time, displayedComponents: .hourAndMinute)
            .labelsHidden()
            .disabled(!reminder.isOn)
    }

    // The spring style draws its label, so the row's own title is the only text.
    private var toggle: some View {
        Toggle(isOn: isOn) { EmptyView() }
            .toggleStyle(.spring)
            .fixedSize()
            .accessibilityLabel(reminder.title + " reminder")
            .accessibilityIdentifier("reminders.toggle." + reminder.id)
    }
}

#Preview { NavigationStack { RemindersView() } }
