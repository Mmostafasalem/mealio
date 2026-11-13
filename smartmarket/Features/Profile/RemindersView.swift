import SwiftUI

/// Reminders for meals, training and logging: one bell to switch them all on,
/// then a time (and, for training, days) for each.
struct RemindersView: View {

    @State private var store = ReminderStore.shared
    @Environment(\.openURL) private var openURL

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
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background { GrainyGradient().ignoresSafeArea() }
        .navigationTitle("Reminders")
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarHidden(false)
        .task { await store.refreshPermission() }
    }
}

private struct ReminderRow: View {
    let reminder: Reminder
    let store: ReminderStore

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
            HStack(spacing: Spacing.md) {
                Image(systemName: reminder.symbol)
                    .foregroundStyle(Color.labelPrimary)
                    .frame(width: 26)
                    .accessibilityHidden(true)
                Text(reminder.title)
                Spacer(minLength: Spacing.sm)
                DatePicker(reminder.title + " time", selection: time, displayedComponents: .hourAndMinute)
                    .labelsHidden()
                    .disabled(!reminder.isOn)
                // The spring style draws its label, so the row's own title is the only text.
                Toggle(isOn: isOn) { EmptyView() }
                    .toggleStyle(.spring)
                    .fixedSize()
                    .accessibilityLabel(reminder.title + " reminder")
                    .accessibilityIdentifier("reminders.toggle." + reminder.id)
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
                                .frame(maxWidth: .infinity, minHeight: 36)
                                .background(chosen ? Color.dullPink : Color.surfaceSecondary, in: Circle())
                                .foregroundStyle(chosen ? Color.onAccent : Color.labelPrimary)
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
}

#Preview { NavigationStack { RemindersView() } }
