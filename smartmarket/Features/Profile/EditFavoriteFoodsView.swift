import SwiftUI

struct EditFavoriteFoodsView: View {

    @Bindable var vm: ProfileViewModel
    @State private var query = ""
    /// The open section's id (`FoodSection.id`); nil shows every section.
    @State private var selectedCategory: String? = nil
    @State private var displayItems: [CatalogItem] = CatalogItem.all
    @State private var filterTask: Task<Void, Never>?
    /// The foods shown while "N selected" is on: the selection when it was tapped, so a
    /// food unticked by mistake stays in the list and can be ticked again.
    @State private var selectedOnly: Set<String>? = nil
    /// Foods starred as the ones bought most (saved straight away).
    @State private var starred: Set<String> = StarredFoods.load()

    /// Only what the diet allows is offered, with the same rule as onboarding (`FoodChoices`).
    private var sections: [FoodSection] { FoodChoices.sections(diets: vm.selectedPreferences) }
    private var offered: [CatalogItem] { sections.flatMap(\.items) }

    var body: some View {
        VStack(spacing: 0) {
            categoryStrip
            itemList
        }
        .background(Color.surfaceGrouped.ignoresSafeArea())
        .searchable(text: $query, prompt: "Search \(offered.count) foods…")
        .onChange(of: query)            { _, _ in scheduleFilter() }
        .onChange(of: selectedCategory) { _, _ in scheduleFilter() }
        .onChange(of: vm.selectedPreferences) { _, _ in scheduleFilter() }
        .onAppear { scheduleFilter() }
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
                ForEach(sections) { sec in
                    CategoryChip(label: sec.title, isSelected: selectedCategory == sec.id && selectedOnly == nil) {
                        selectedOnly = nil
                        selectedCategory = (selectedCategory == sec.id) ? nil : sec.id
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
        ItemRow(item: item, isSelected: vm.favoriteFoodIDs.contains(item.id), isStarred: starred.contains(item.id),
                onTap: {
                    vm.toggleFavorite(item)
                    if !vm.favoriteFoodIDs.contains(item.id), starred.remove(item.id) != nil { StarredFoods.save(starred) }
                },
                onStar: {
                    if starred.remove(item.id) == nil {
                        starred.insert(item.id)
                        if !vm.favoriteFoodIDs.contains(item.id) { vm.toggleFavorite(item) }
                    }
                    StarredFoods.save(starred)
                })
    }

    private var itemList: some View {
        List {
            if let chosen = selectedOnly {
                // Only the foods picked, grouped like the full list.
                ForEach(sections) { sec in
                    let items = sec.items.filter { chosen.contains($0.id) }
                        .filter { query.isEmpty || $0.name.lowercased().contains(query.lowercased()) }
                    if !items.isEmpty { categorySection(sec, items: items) }
                }
            } else if displayItems.isEmpty {
                Text("No foods match your search.")
                    .foregroundStyle(Color.labelSecondary)
                    .listRowBackground(Color.clear)
            } else if query.isEmpty {
                // Grouped by section, then by what the food is (Chicken, Pork, Beef …).
                ForEach(sections.filter { selectedCategory == nil || $0.id == selectedCategory }) { sec in
                    categorySection(sec, items: sec.items)
                }
            } else {
                Section {
                    ForEach(displayItems, content: favoriteRow)
                }
            }
        }
        .listStyle(.insetGrouped)
        .scrollDismissesKeyboard(.immediately)
    }

    /// One section: a header with "Select all" for the whole section, then its
    /// subgroups, each with its own heading and "Select all".
    private func categorySection(_ sec: FoodSection, items: [CatalogItem]) -> some View {
        let groups = CatalogSubgroups.groups(of: items, in: sec.category)
        return Section {
            ForEach(groups, id: \.title) { group in
                if groups.count > 1 { subgroupHeader(group.title, items: group.items) }
                ForEach(group.items, content: favoriteRow)
            }
        } header: {
            HStack(spacing: 8) {
                SectionHeader(section: sec, selectedIDs: vm.favoriteFoodIDs)
                selectAllButton(items, label: "all \(sec.title)")
                    .accessibilityIdentifier("favorites.selectAll.\(sec.id)")
            }
        }
    }

    private func subgroupHeader(_ title: String, items: [CatalogItem]) -> some View {
        let picked = items.filter { vm.favoriteFoodIDs.contains($0.id) }.count
        return HStack(spacing: 8) {
            Text(title).font(.subheadline.weight(.bold)).foregroundStyle(Color.labelPrimary)
            Text("\(picked) of \(items.count)" as String).font(.caption).foregroundStyle(Color.labelSecondary)
                .monospacedDigit()
            Spacer()
            selectAllButton(items, label: title)
                .accessibilityIdentifier("favorites.selectAll.\(title)")
        }
        .padding(.top, 6)
        .listRowBackground(Color.surface.opacity(0.6))
        .accessibilityElement(children: .contain)
        .accessibilityAddTraits(.isHeader)
    }

    /// "Select all" when anything in the group is unpicked, otherwise "Clear".
    private func selectAllButton(_ items: [CatalogItem], label: String) -> some View {
        let allPicked = items.allSatisfy { vm.favoriteFoodIDs.contains($0.id) }
        return Button {
            withAnimation(.snappy) { vm.setFavorites(items, selected: !allPicked) }
            if allPicked, !starred.isDisjoint(with: items.map(\.id)) {
                starred.subtract(items.map(\.id))
                StarredFoods.save(starred)
            }
        } label: {
            Text(allPicked ? "Clear" : "Select all")
                .font(.caption.weight(.semibold))
                .foregroundStyle(allPicked ? Color.labelSecondary : Color.brandPrimary)
                .padding(.horizontal, 10).padding(.vertical, 5)
                .background(Color(.tertiarySystemFill), in: Capsule())
                .frame(minHeight: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.borderless)
        .textCase(nil)
        .accessibilityLabel(allPicked ? "Clear \(label)" : "Select \(label)")
    }

    private func scheduleFilter() {
        filterTask?.cancel()
        filterTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 100_000_000)
            guard !Task.isCancelled else { return }
            var base = offered
            if let id = selectedCategory { base = sections.first { $0.id == id }?.items ?? [] }
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
    let section: FoodSection
    let selectedIDs: Set<String>
    private var count: Int {
        section.items.filter { selectedIDs.contains($0.id) }.count
    }
    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: section.symbol).font(.system(size: 11, weight: .semibold)).foregroundStyle(Color.labelPrimary)
            Text(section.title)
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
    let isStarred: Bool
    let onTap: () -> Void
    let onStar: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body: some View {
        HStack(spacing: 14) {
            Button(action: onTap) {
                HStack(spacing: 14) {
                    Circle()
                        .fill(Color.labelPrimary.opacity(0.18))
                        .frame(width: 32, height: 32)
                        .overlay(Image(systemName: item.category.symbol).font(.system(size: 13, weight: .medium)).foregroundStyle(Color.labelPrimary))
                    Text(item.name).font(.body).foregroundStyle(Color.labelPrimary)
                    Spacer()
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.borderless)
            .accessibilityLabel(item.name + (isStarred ? ", starred" : ""))
            .accessibilityAddTraits(isSelected ? .isSelected : [])
            .accessibilityAction(named: isStarred ? "Remove star" : "Star", onStar)
            // A star for the foods bought most, its own 44 pt button.
            Button(action: onStar) {
                Image(systemName: isStarred ? "star.fill" : "star")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(isStarred ? Color.brandAmber : Color(.tertiaryLabel))
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.borderless)
            .accessibilityHidden(true)
            .accessibilityIdentifier("favorites.star.\(item.id)")
            Button(action: onTap) {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 20))
                    .foregroundStyle(isSelected ? Color.dullPink : Color(.tertiaryLabel))
                    .contentTransition(.symbolEffect(.replace))
                    .animation(reduceMotion ? .none : .snappyValue, value: isSelected)
                    .frame(minWidth: 32, minHeight: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.borderless)
            .accessibilityHidden(true)
        }
        .sensoryFeedback(.selection, trigger: isSelected)
    }
}

#Preview {
    NavigationStack { EditFavoriteFoodsView(vm: ProfileViewModel()) }
}
