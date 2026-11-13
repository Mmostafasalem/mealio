import SwiftUI

struct GroceryListView: View {

    @Environment(\.dismiss) private var dismiss
    @State private var vm = GroceryListViewModel()
    @State private var actionsMenu = DynamicMenuModel()
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
                        DynamicMenuToggle(model: actionsMenu, items: listActions, label: "List actions")
                            .accessibilityIdentifier("groceries.actions")
                    }
                }
            }
            .overlay(alignment: .topTrailing) {
                if !vm.items.isEmpty {
                    DynamicMenuPanel(model: actionsMenu, items: listActions)
                }
            }
            .onChange(of: vm.items.isEmpty) { _, empty in
                if empty && actionsMenu.isOpen { actionsMenu.set(false, count: listActions.count) }
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

    /// Share and Clear bought, in the toolbar's springy menu.
    private var listActions: [DynamicMenuItem] {
        [
            DynamicMenuItem("Share list", systemImage: "square.and.arrow.up",
                            id: "groceries.share", share: vm.shareText()),
            DynamicMenuItem("Clear bought", systemImage: "checkmark.circle",
                            id: "groceries.clearBought",
                            isDisabled: !vm.items.contains { $0.isBought }) { vm.clearBought() },
        ]
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
                Section {
                    GrocerySummaryRow(
                        bought: vm.items.filter(\.isBought).count,
                        total: vm.items.count,
                        copyText: copyText
                    )
                }
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

    /// Unbought items as plain lines for the pasteboard: "• Milk 2 × 1 L — Rimi".
    private var copyText: String {
        vm.sortedStores
            .flatMap { vm.groupedByStore[$0] ?? [] }
            .filter { !$0.isBought }
            .map { item in
                let q = item.quantity.trimmingCharacters(in: .whitespaces)
                // Cart rows store a bare count ("2"); show it as "× 2".
                let amount = q.isEmpty ? "" : (Int(q) != nil ? " × \(q)" : " \(q)")
                return "• \(item.foodName)\(amount) — \(item.storeName)"
            }
            .joined(separator: "\n")
    }
}

// MARK: - Row

private struct GroceryRow: View {
    let item: GroceryItem
    let onToggle: () -> Void

    private var priceText: String {
        item.priceKnown == false ? "Price unknown" : String(format: "€%.2f", item.estimatedPrice)
    }

    var body: some View {
        AnimatedCheckRow(
            title: item.foodName,
            isOn: item.isBought,
            action: onToggle,
            stateLabels: ("Bought", "Not bought"),
            accessibilityDetail: [item.quantity, priceText].filter { !$0.isEmpty }.joined(separator: ", ")
        ) {
            Text(item.quantity)
                .font(.caption).foregroundStyle(Color.labelSecondary)
        } trailing: {
            Text(priceText)
                .font(.subheadline.monospacedDigit())
                .foregroundStyle(item.isBought ? .tertiary : .secondary)
        }
        .padding(.vertical, 2)
    }
}

// MARK: - List summary

/// "N of M bought" rolling count and the Copy list button, above the stores.
private struct GrocerySummaryRow: View {
    let bought: Int
    let total: Int
    let copyText: String

    var body: some View {
        HStack(spacing: Spacing.md) {
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                RollingNumber(value: bought)
                    .fontWeight(.semibold)
                    .foregroundStyle(Color.labelPrimary)
                Text("of \(total) bought")
                    .foregroundStyle(Color.labelSecondary)
            }
            .font(.subheadline)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(bought) of \(total) bought")
            .accessibilityIdentifier("groceries.boughtCount")
            Spacer(minLength: Spacing.sm)
            CopyButton(title: "Copy list", doneTitle: "Copied", announcement: "Shopping list copied") { copyText }
                .disabled(copyText.isEmpty)
                .accessibilityHint(copyText.isEmpty ? "Everything is bought" : "Copies the items still to buy")
                .accessibilityIdentifier("groceries.copy")
        }
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
