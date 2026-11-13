import SwiftUI

/// Today's food log grouped by meal slot, with quick add/remove.
struct TodaysLogCard: View {
    let vm: HomeViewModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            HStack(spacing: Spacing.md) {
                // Title on one line, the remaining calories under it.
                VStack(alignment: .leading, spacing: 2) {
                    HomeCardTitle(title: "Today's Log", symbol: "list.bullet.clipboard.fill")
                    Text("\(vm.remaining) kcal left")
                        .font(.footnote.weight(.medium))
                        .monospacedDigit()
                        .foregroundStyle(Color.labelSecondary)
                        .contentTransition(.numericText())
                        .padding(.leading, HomeGrid.textInset)
                }
                Spacer(minLength: Spacing.sm)
                GooMenu(items: Self.quickAddItems, accessibilityLabel: "Add food to a meal") { item in
                    if let slot = MealSlot(rawValue: item.id) { vm.openLog(slot: slot) }
                }
            }
            // The menu's bubbles pour down over the rows below.
            .zIndex(1)

            ForEach(Array(MealSlot.allCases.enumerated()), id: \.element) { idx, slot in
                MealSlotRow(
                    slot: slot,
                    entries: vm.entries(for: slot),
                    onAdd: { vm.openLog(slot: slot) },
                    onDelete: { vm.removeLog($0) }
                )
                if idx < MealSlot.allCases.count - 1 {
                    Divider().padding(.leading, HomeGrid.textInset)
                }
            }
        }
        .padding(Spacing.lg)
        .premiumCard()
        .animation(reduceMotion ? nil : .snappyValue, value: vm.consumed)
    }

    /// Goo menu bubbles, one per meal slot (ids are `MealSlot` raw values).
    static let quickAddItems: [GooMenuItem] = [
        GooMenuItem(id: MealSlot.breakfast.rawValue, title: MealSlot.breakfast.title, systemImage: "sunrise"),
        GooMenuItem(id: MealSlot.lunch.rawValue, title: MealSlot.lunch.title, systemImage: "sun.max"),
        GooMenuItem(id: MealSlot.dinner.rawValue, title: MealSlot.dinner.title, systemImage: "moon"),
        GooMenuItem(id: MealSlot.snack.rawValue, title: MealSlot.snack.title, systemImage: "sparkles"),
    ]
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
            HStack(spacing: HomeGrid.gap) {
                Image(systemName: slot.sfSymbol)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(slot.accent)
                    .frame(width: HomeGrid.icon, height: HomeGrid.icon)
                    .background(slot.accent.opacity(0.12), in: Circle())

                Text(slot.title).font(.subheadline).fontWeight(.semibold)
                Spacer()
                if kcal > 0 {
                    Text("\(kcal) kcal")
                        .font(.footnote).fontWeight(.semibold)
                        .foregroundStyle(Color.labelSecondary).monospacedDigit()
                        .contentTransition(.numericText())
                }
                Button(action: onAdd) {
                    Image(systemName: "plus.circle.fill")
                        .font(.system(size: 22))
                        .foregroundStyle(slot.accent)
                }
                .buttonStyle(.plain)
                // 44pt target, with the glyph on the card's right edge.
                .frame(width: 44, height: 44, alignment: .trailing)
                .contentShape(Rectangle())
                .accessibilityLabel("Add to \(slot.title)")
            }

            ForEach(entries) { entry in
                HStack(spacing: Spacing.sm) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(entry.name).font(.caption).foregroundStyle(Color.labelPrimary).lineLimit(2)
                        Text(entry.nutritionFood?.sourceName ?? "Estimated / older entry")
                            .font(.caption2).foregroundStyle(Color.labelSecondary)
                    }
                    Spacer()
                    Text("\(entry.amount.formatted(.number.precision(.fractionLength(0...1)))) \(entry.amountUnit)").font(.caption2).foregroundStyle(Color.labelSecondary)
                    Text("\(entry.calories)")
                        .font(.caption2).fontWeight(.semibold)
                        .foregroundStyle(Color.labelSecondary).monospacedDigit()
                    Button { onDelete(entry) } label: {
                        Image(systemName: "minus.circle.fill")
                            .font(.system(size: 16))
                            .foregroundStyle(Color.brandDanger.opacity(0.7))
                    }
                    .buttonStyle(.plain)
                    .frame(width: 44, height: 44, alignment: .trailing)
                    .contentShape(Rectangle())
                    .accessibilityLabel("Remove \(entry.name)")
                }
                .padding(.leading, HomeGrid.textInset)
                .accessibilityElement(children: .combine)
            }
        }
    }
}
