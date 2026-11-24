import SwiftUI

struct EditFavoriteFoodsView: View {

    @Bindable var vm: ProfileViewModel
    @State private var query = ""
    @State private var selectedCategory: CatalogCategory? = nil
    @State private var displayItems: [CatalogItem] = CatalogItem.all
    @State private var filterTask: Task<Void, Never>?
    /// The foods shown while "N selected" is on: the selection when it was tapped, so a
    /// food unticked by mistake stays in the list and can be ticked again.
    @State private var selectedOnly: Set<String>? = nil

    var body: some View {
        VStack(spacing: 0) {
            categoryStrip
            itemList
        }
        .background(Color.surfaceGrouped.ignoresSafeArea())
        .searchable(text: $query, prompt: "Search \(CatalogItem.all.count) products…")
        .onChange(of: query)            { _, _ in scheduleFilter() }
        .onChange(of: selectedCategory) { _, _ in scheduleFilter() }
        .navigationTitle("Favourite foods")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                if vm.favoriteFoodIDs.count > 0 || selectedOnly != nil {
                    Button {
                        selectedOnly = selectedOnly == nil ? vm.favoriteFoodIDs : nil
                    } label: {
                        Text(selectedOnly == nil ? "\(vm.favoriteFoodIDs.count) selected" as String : "Show all")
                            .font(.caption).fontWeight(.semibold)
                            .foregroundStyle(selectedOnly == nil ? Color.brandPrimary : Color.onAccent)
                            .padding(.horizontal, selectedOnly == nil ? 0 : 10).padding(.vertical, 4)
                            .background(selectedOnly == nil ? Color.clear : Color.dullPink, in: Capsule())
                    }
                    .accessibilityIdentifier("favorites.selectedOnly")
                    .accessibilityHint(selectedOnly == nil ? "Shows only the foods you picked" : "Shows every food again")
                }
            }
        }
        .onDisappear { vm.save() }
    }

    // MARK: - Category strip

    private var categoryStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                CategoryChip(label: "All", isSelected: selectedCategory == nil && selectedOnly == nil) {
                    selectedCategory = nil; selectedOnly = nil
                }
                ForEach(CatalogCategory.allCases) { cat in
                    CategoryChip(label: cat.displayName, isSelected: selectedCategory == cat && selectedOnly == nil) {
                        selectedOnly = nil
                        selectedCategory = (selectedCategory == cat) ? nil : cat
                    }
                }
            }
            .padding(.horizontal, 20).padding(.vertical, 10)
        }
        .background(Color.surfaceGrouped)
        .overlay(Divider(), alignment: .bottom)
    }

    // MARK: - List

    private func favoriteRow(_ item: CatalogItem) -> some View {
        ItemRow(item: item, isSelected: vm.favoriteFoodIDs.contains(item.id)) { vm.toggleFavorite(item) }
    }

    private var itemList: some View {
        List {
            if let chosen = selectedOnly {
                // Only the foods picked, in catalogue order, grouped by category.
                ForEach(CatalogCategory.allCases) { cat in
                    let items = CatalogItem.all.filter { $0.category == cat && chosen.contains($0.id) }
                        .filter { query.isEmpty || $0.name.lowercased().contains(query.lowercased()) }
                    if !items.isEmpty {
                        Section {
                            ForEach(items, content: favoriteRow)
                        } header: {
                            SectionHeader(category: cat, selectedIDs: vm.favoriteFoodIDs)
                        }
                    }
                }
            } else if displayItems.isEmpty {
                Text("No items match your search.")
                    .foregroundStyle(Color.labelSecondary)
                    .listRowBackground(Color.clear)
            } else if selectedCategory == nil && query.isEmpty {
                ForEach(CatalogCategory.allCases) { cat in
                    let items = CatalogItem.all.filter { $0.category == cat }
                    if !items.isEmpty {
                        Section {
                            ForEach(items, content: favoriteRow)
                        } header: {
                            SectionHeader(category: cat, selectedIDs: vm.favoriteFoodIDs)
                        }
                    }
                }
            } else {
                Section {
                    ForEach(displayItems) { item in
                        ItemRow(item: item,
                                isSelected: vm.favoriteFoodIDs.contains(item.id)) {
                            vm.toggleFavorite(item)
                        }
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .scrollDismissesKeyboard(.immediately)
    }

    private func scheduleFilter() {
        filterTask?.cancel()
        filterTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 100_000_000)
            guard !Task.isCancelled else { return }
            var base = CatalogItem.all
            if let cat = selectedCategory { base = base.filter { $0.category == cat } }
            let q = query.lowercased()
            if !q.isEmpty { base = base.filter { $0.name.lowercased().contains(q) } }
            displayItems = base
        }
    }
}

// MARK: - Subviews (private, local copies)

private struct CategoryChip: View {
    let label: String
    let isSelected: Bool
    let onTap: () -> Void
    var body: some View {
        Button(action: onTap) {
            Text(label)
                .font(.subheadline)
                .padding(.horizontal, 14).padding(.vertical, 6)
                .background(isSelected ? Color.dullPink : Color(.tertiarySystemFill))
                .foregroundStyle(isSelected ? Color.onAccent : Color.labelPrimary)
                .clipShape(Capsule())
                // The chip stays small; the tap area is 44 pt.
                .frame(minWidth: 44, minHeight: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        // Colour-only change, so it stays animated under Reduce Motion.
        .animation(.snappyValue, value: isSelected)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

private struct SectionHeader: View {
    let category: CatalogCategory
    let selectedIDs: Set<String>
    private var count: Int {
        CatalogItem.all.filter { $0.category == category && selectedIDs.contains($0.id) }.count
    }
    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: category.symbol).font(.system(size: 11, weight: .semibold)).foregroundStyle(Color.labelPrimary)
            Text(category.displayName)
            Spacer()
            if count > 0 {
                Text("\(count)" as String).font(.caption2).fontWeight(.bold).foregroundStyle(Color.onAccent)
                    .padding(.horizontal, 7).padding(.vertical, 2)
                    .background(Color.dullPink, in: Capsule())
            }
        }
        .font(.footnote).fontWeight(.semibold).foregroundStyle(Color.labelSecondary).textCase(nil)
    }
}

private struct ItemRow: View {
    let item: CatalogItem
    let isSelected: Bool
    let onTap: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 14) {
                Circle()
                    .fill(Color.labelPrimary.opacity(0.18))
                    .frame(width: 32, height: 32)
                    .overlay(Image(systemName: item.category.symbol).font(.system(size: 13, weight: .medium)).foregroundStyle(Color.labelPrimary))
                Text(item.name).font(.body).foregroundStyle(Color.labelPrimary)
                Spacer()
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 20))
                    .foregroundStyle(isSelected ? Color.dullPink : Color(.tertiaryLabel))
                    .contentTransition(.symbolEffect(.replace))
                    .animation(reduceMotion ? .none : .snappyValue, value: isSelected)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .sensoryFeedback(.selection, trigger: isSelected)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

#Preview {
    NavigationStack { EditFavoriteFoodsView(vm: ProfileViewModel()) }
}
