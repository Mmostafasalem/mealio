import SwiftUI

/// Today's food log grouped by meal slot, with quick add/remove.
struct TodaysLogCard: View {
    let vm: HomeViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            HStack {
                Label("Today's Log", systemImage: "list.bullet.clipboard.fill")
                    .font(.sectionTitle)
                Spacer()
                Text("\(vm.remaining) kcal left")
                    .font(.caption).fontWeight(.semibold)
                    .foregroundStyle(Color.calorieAccent)
                    .contentTransition(.numericText())
            }
            .accessibilityAddTraits(.isHeader)

            ForEach(Array(MealSlot.allCases.enumerated()), id: \.element) { idx, slot in
                MealSlotRow(
                    slot: slot,
                    entries: vm.entries(for: slot),
                    onAdd: { vm.openLog(slot: slot) },
                    onDelete: { vm.removeLog($0) }
                )
                if idx < MealSlot.allCases.count - 1 {
                    Divider().padding(.leading, 40)
                }
            }
        }
        .padding(Spacing.lg)
        .premiumCard()
        .animation(.snappyValue, value: vm.consumed)
    }
}

/// One meal slot with its logged entries.
struct MealSlotRow: View {
    let slot: MealSlot
    let entries: [FoodLogEntry]
    let onAdd: () -> Void
    let onDelete: (FoodLogEntry) -> Void

    private var kcal: Int { entries.reduce(0) { $0 + $1.calories } }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            HStack(spacing: Spacing.sm) {
                Image(systemName: slot.sfSymbol)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(slot.accent)
                    .frame(width: 30, height: 30)
                    .background(slot.accent.opacity(0.12), in: Circle())

                Text(slot.title).font(.subheadline).fontWeight(.semibold)
                Spacer()
                if kcal > 0 {
                    Text("\(kcal) kcal")
                        .font(.caption).fontWeight(.semibold)
                        .foregroundStyle(.secondary).monospacedDigit()
                        .contentTransition(.numericText())
                }
                Button(action: onAdd) {
                    Image(systemName: "plus.circle.fill")
                        .font(.system(size: 22))
                        .foregroundStyle(slot.accent)
                }
                .buttonStyle(.plain)
                .minTapTarget()
                .accessibilityLabel("Add to \(slot.title)")
            }

            ForEach(entries) { entry in
                HStack(spacing: Spacing.sm) {
                    Text(entry.name).font(.caption).foregroundStyle(.primary).lineLimit(1)
                    Spacer()
                    Text("\(entry.servingG)g").font(.caption2).foregroundStyle(.secondary)
                    Text("\(entry.calories)")
                        .font(.caption2).fontWeight(.semibold)
                        .foregroundStyle(.secondary).monospacedDigit()
                    Button { onDelete(entry) } label: {
                        Image(systemName: "minus.circle.fill")
                            .font(.system(size: 16))
                            .foregroundStyle(Color.brandDanger.opacity(0.7))
                    }
                    .buttonStyle(.plain)
                .minTapTarget()
                    .accessibilityLabel("Remove \(entry.name)")
                }
                .padding(.leading, 40)
                .accessibilityElement(children: .combine)
            }
        }
    }
}
