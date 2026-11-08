import SwiftUI

struct GroceryListView: View {

    @Environment(\.dismiss) private var dismiss
    @State private var vm = GroceryListViewModel()
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        NavigationStack {
            Group {
                if vm.items.isEmpty {
                    EmptyStateView(icon: "cart",
                                   title: "Your grocery list is empty",
                                   message: "Add items from the Shop tab to build your shopping list.",
                                   actionTitle: "Browse groceries") { dismiss() }
                } else {
                    listContent
                }
            }
            .background(Color.surfaceGrouped.ignoresSafeArea())
            .navigationTitle("Groceries")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }.accessibilityIdentifier("groceries.done")
                }
                if !vm.items.isEmpty {
                    ToolbarItem(placement: .topBarTrailing) {
                        ShareLink(item: vm.shareText()) {
                            Image(systemName: "square.and.arrow.up")
                        }
                        .accessibilityLabel("Share list")
                    }
                    ToolbarItem(placement: .topBarLeading) {
                        Button("Clear bought") { vm.clearBought() }
                            .disabled(!vm.items.contains { $0.isBought })
                    }
                }
            }

        }
        .safeAreaInset(edge: .bottom) {
            if let message = vm.undoMessage {
                UndoToast(message: message) { vm.undoDelete() }
                    .padding(.vertical, Spacing.sm)
                    .transition(reduceMotion ? .opacity : .move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(reduceMotion ? .none : .snappyValue, value: vm.undoMessage)
        .onAppear { vm.loadItems() }
    }

    // A typed View closure avoids MapKit's competing ForEach result builder
    // being inferred by older supported Swift compilers.
    private func groceryRow(_ item: GroceryItem) -> some View {
        GroceryRow(item: item) { vm.toggleBought(item) }
            .swipeActions(edge: .trailing) {
                Button(role: .destructive) { vm.deleteItem(item) } label: {
                    Label("Delete", systemImage: "trash")
                }
            }
    }

    private var listContent: some View {
        VStack(spacing: 0) {
            List {
                ForEach(vm.sortedStores, id: \.self) { store in
                    Section {
                        ForEach(vm.groupedByStore[store] ?? [], content: groceryRow)
                    } header: {
                        StoreHeaderView(
                            store: store,
                            count: (vm.groupedByStore[store] ?? []).count,
                            cost: vm.estimatedCost(for: store),
                            hasUnknownPrices: (vm.groupedByStore[store] ?? []).contains { $0.priceKnown == false }
                        )
                    }
                }
            }
            .listStyle(.insetGrouped)

            FooterBar(total: vm.totalEstimatedCost, count: vm.items.count, hasUnknownPrices: vm.items.contains { $0.priceKnown == false })
        }

    }
}

// MARK: - Row

private struct GroceryRow: View {
    let item: GroceryItem
    let onToggle: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Button(action: onToggle) {
                Image(systemName: item.isBought ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 22))
                    .foregroundStyle(item.isBought ? Color.brandPrimary : Color.labelSecondary)
                    .minTapTarget()
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .sensoryFeedback(.selection, trigger: item.isBought)
            .accessibilityLabel(item.isBought ? "Mark \(item.foodName) as not bought" : "Mark \(item.foodName) as bought")

            VStack(alignment: .leading, spacing: 2) {
                Text(item.foodName)
                    .font(.subheadline).fontWeight(.medium)
                    .strikethrough(item.isBought)
                    .foregroundStyle(item.isBought ? .secondary : .primary)
                Text(item.quantity)
                    .font(.caption).foregroundStyle(Color.labelSecondary)
            }
            Spacer()
            Text(item.priceKnown == false ? "Price unknown" : String(format: "€%.2f", item.estimatedPrice))
                .font(.subheadline.monospacedDigit())
                .foregroundStyle(item.isBought ? .tertiary : .secondary)
        }
        .padding(.vertical, 2)
    }
}

// MARK: - Store header

private struct StoreHeaderView: View {
    let store: String
    let count: Int
    let cost: Double
    let hasUnknownPrices: Bool

    private var storeColor: Color { .labelPrimary }

    var body: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(storeColor)
                .frame(width: 8, height: 8)
            Text(store)
                .fontWeight(.semibold)
            Spacer()
            Text(hasUnknownPrices ? "\(count) items · prices incomplete" : "\(count) item\(count == 1 ? "" : "s") · ~€\(cost, specifier: "%.2f")")
        }
        .font(.caption)
        .textCase(nil)
    }
}

// MARK: - Footer

private struct FooterBar: View {
    let total: Double
    let count: Int
    let hasUnknownPrices: Bool

    var body: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 2) {
                Text(hasUnknownPrices ? "Known estimates only" : "Estimated total")
                    .font(.caption).foregroundStyle(Color.labelSecondary)
                Text(String(format: "€%.2f", total))
                    .font(.title2).fontWeight(.bold)
                    .foregroundStyle(Color.brandPrimary)
                    .monospacedDigit()
                    .contentTransition(.numericText())
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text("Items")
                    .font(.caption).foregroundStyle(Color.labelSecondary)
                Text("\(count)")
                    .font(.title2).fontWeight(.bold)
                    .monospacedDigit()
                    .contentTransition(.numericText())
            }
        }
        .padding(.horizontal, Spacing.xl)
        .padding(.vertical, Spacing.lg)
        .background(.ultraThinMaterial)
        .overlay(Divider(), alignment: .top)
        .animation(.snappyValue, value: total)
    }
}

#Preview {
    GroceryListView()
}
