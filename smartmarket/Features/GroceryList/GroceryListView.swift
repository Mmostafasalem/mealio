import SwiftUI

struct GroceryListView: View {

    @Binding var selectedTab: Int
    @State private var vm = GroceryListViewModel()
    @State private var showClearAlert = false

    var body: some View {
        NavigationStack {
            Group {
                if vm.items.isEmpty {
                    EmptyGroceryView { selectedTab = 0 }
                } else {
                    listContent
                }
            }
            .background(Color.surfaceGrouped.ignoresSafeArea())
            .navigationTitle("Groceries")
            .toolbar {
                if !vm.items.isEmpty {
                    ToolbarItem(placement: .topBarTrailing) {
                        ShareLink(item: vm.shareText()) {
                            Image(systemName: "square.and.arrow.up")
                        }
                        .accessibilityLabel("Share list")
                    }
                    ToolbarItem(placement: .topBarLeading) {
                        Button("Clear bought") { showClearAlert = true }
                            .disabled(!vm.items.contains { $0.isBought })
                    }
                }
            }
            .alert("Clear bought items?", isPresented: $showClearAlert) {
                Button("Clear", role: .destructive) { vm.clearBought() }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This removes all checked items from your list.")
            }
        }
        .onAppear { vm.loadItems() }
    }

    private var listContent: some View {
        VStack(spacing: 0) {
            List {
                ForEach(vm.sortedStores, id: \.self) { store in
                    Section {
                        ForEach(vm.groupedByStore[store] ?? []) { item in
                            GroceryRow(item: item) { vm.toggleBought(item) }
                                .swipeActions {
                                    Button(role: .destructive) {
                                        vm.deleteItem(item)
                                    } label: {
                                        Label("Delete", systemImage: "trash")
                                    }
                                }
                        }
                    } header: {
                        StoreHeaderView(
                            store: store,
                            count: (vm.groupedByStore[store] ?? []).count,
                            cost: vm.estimatedCost(for: store)
                        )
                    }
                }
            }
            .listStyle(.insetGrouped)

            FooterBar(total: vm.totalEstimatedCost, count: vm.items.count)
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
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Text(String(format: "€%.2f", item.estimatedPrice))
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .monospacedDigit()
        }
        .padding(.vertical, 2)
    }
}

// MARK: - Store header

private struct StoreHeaderView: View {
    let store: String
    let count: Int
    let cost: Double

    var body: some View {
        HStack {
            Text(store)
            Spacer()
            Text("\(count) item\(count == 1 ? "" : "s") · ~€\(cost, specifier: "%.2f")")
        }
        .font(.caption)
        .textCase(nil)
    }
}

// MARK: - Footer

private struct FooterBar: View {
    let total: Double
    let count: Int

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("Estimated total")
                    .font(.caption).foregroundStyle(.secondary)
                Text(String(format: "€%.2f", total))
                    .font(.title3).fontWeight(.bold)
                    .foregroundStyle(Color.brandPrimary)
                    .monospacedDigit()
            }
            Spacer()
            Text("\(count) item\(count == 1 ? "" : "s")")
                .font(.subheadline).foregroundStyle(.secondary)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
        .background(
            Color.surfaceGrouped.overlay(Divider(), alignment: .top)
        )
    }
}

// MARK: - Empty state

private struct EmptyGroceryView: View {
    let onBrowse: () -> Void

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: "cart")
                .font(.system(size: 44))
                .foregroundStyle(Color.brandPrimary.opacity(0.5))
            Text("Your grocery list is empty")
                .font(.headline)
            Button(action: onBrowse) {
                Text("Browse deals")
                    .font(.subheadline).fontWeight(.semibold)
                    .padding(.horizontal, 20).padding(.vertical, 10)
                    .foregroundStyle(.white)
                    .background(Color.brandPrimary)
                    .clipShape(Capsule())
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

#Preview {
    GroceryListView(selectedTab: .constant(2))
}
