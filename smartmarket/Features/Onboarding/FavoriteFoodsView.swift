import SwiftUI

struct FavoriteFoodsView: View {

    @Bindable var vm: OnboardingViewModel
    /// One section open at a time; with none open the sections are a grid that fits the screen.
    @State private var openSection: CatalogCategory?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        OnboardingScaffold(vm: vm, step: .favorites, title: "Pick your foods",
                           subtitle: "Pick at least \(Constants.Onboarding.minimumFavorites) foods you buy. Your meal plans start from them.",
                           contentPadding: 0) {
            VStack(spacing: 0) {
                searchField
                    .padding(.bottom, Spacing.md)
                itemList
            }
        } footer: {
            finishButton
        }
    }

    private func chip(_ item: CatalogItem) -> some View {
        FoodChip(item: item, isSelected: vm.favoriteFoodIDs.contains(item.id)) { vm.toggleFavorite(item) }
    }

    /// One category's foods as wrapping chips, like the diet screen.
    private func chips(_ items: [CatalogItem]) -> some View {
        FlowLayout(spacing: 10) {
            ForEach(items, content: chip)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// A section: its header with Select all, then its foods by kind (chicken, pork…).
    private func section(_ cat: CatalogCategory) -> some View {
        let items = CatalogItem.all.filter { $0.category == cat }
        let groups = cat.groups(of: items)
        return VStack(alignment: .leading, spacing: Spacing.md) {
            CategorySectionHeader(category: cat, selectedIDs: vm.favoriteFoodIDs,
                                  allSelected: Set(items.map(\.id)).isSubset(of: vm.favoriteFoodIDs),
                                  isOpen: true, canFold: true,
                                  onToggleOpen: {
                                      withAnimation(reduceMotion ? nil : .snappy) { openSection = nil }
                                  }) {
                vm.toggleAll(items)
            }
            do {
            ForEach(groups) { group in
                VStack(alignment: .leading, spacing: Spacing.sm) {
                    if groups.count > 1 {
                        Text(group.name)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(Color.labelSecondary)
                            .accessibilityAddTraits(.isHeader)
                    }
                    chips(group.items)
                }
            }
            }
        }
    }

    // MARK: - Search

    private var searchField: some View {
        HStack(spacing: Spacing.sm) {
            Image(systemName: "magnifyingglass").foregroundStyle(Color.labelSecondary)
            TextField("Search \(CatalogItem.all.count) products", text: $vm.foodSearchQuery)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                .submitLabel(.search)
            if !vm.foodSearchQuery.isEmpty {
                Button { vm.foodSearchQuery = "" } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(Color.labelTertiary)
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .padding(.trailing, -Spacing.md)
                .accessibilityLabel("Clear search")
            }
        }
        .padding(.horizontal, Spacing.lg)
        .frame(minHeight: 48)
        .background(Color.surface, in: Capsule())
        .overlay(Capsule().strokeBorder(Color.hairline, lineWidth: 1))
        .padding(.horizontal, Spacing.xl)
    }

    // MARK: - Item list

    private var itemList: some View {
        // The catalogue is the one thing here that has to scroll.
        ScrollView {
            LazyVStack(alignment: .leading, spacing: Spacing.sm) {
                if vm.filteredItems.isEmpty {
                    Text("No items match your search.")
                        .foregroundStyle(Color.labelSecondary)
                } else if vm.foodSearchQuery.isEmpty {
                    if let open = openSection {
                        // The open section, grouped by kind; its header folds it back.
                        section(open)
                    } else {
                        sectionGrid
                    }
                } else {
                    // Search results as one list.
                    chips(vm.filteredItems)
                }
            }
            .padding(.horizontal, Spacing.xl)
            .padding(.bottom, Spacing.xl)
        }
        .scrollIndicators(.hidden)
        .scrollDismissesKeyboard(.immediately)
        .accessibilityIdentifier("favorites.list")
    }

    /// Every section as a small tile, three to a row: tap one to open it.
    private var sectionGrid: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 3), spacing: 8) {
            ForEach(CatalogCategory.allCases) { cat in
                let picked = CatalogItem.all.filter { $0.category == cat && vm.favoriteFoodIDs.contains($0.id) }.count
                Button {
                    withAnimation(reduceMotion ? nil : .snappy) { openSection = cat }
                } label: {
                    VStack(spacing: 4) {
                        Image(systemName: cat.symbol)
                            .font(.system(size: 14, weight: .semibold))
                        Text(cat.displayName)
                            .font(.caption.weight(.semibold))
                            .multilineTextAlignment(.center)
                            .lineLimit(2)
                            .minimumScaleFactor(0.85)
                    }
                    .foregroundStyle(Color.labelPrimary)
                    .padding(.horizontal, 4)
                    .frame(maxWidth: .infinity, minHeight: 56)
                    .background(Color.surfaceSecondary, in: RoundedRectangle(cornerRadius: Radius.chip, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: Radius.chip, style: .continuous)
                        .strokeBorder(picked > 0 ? Color.progress : Color.clear, lineWidth: 2))
                    .overlay(alignment: .topTrailing) {
                        if picked > 0 {
                            Text("\(picked)" as String)
                                .font(.caption2.weight(.bold))
                                .foregroundStyle(Color.onAccent)
                                .padding(.horizontal, 6).padding(.vertical, 1)
                                .background(Color.dullPink, in: Capsule())
                                .padding(4)
                        }
                    }
                }
                .buttonStyle(ScalePressStyle())
                .accessibilityLabel(cat.displayName)
                .accessibilityValue(picked > 0 ? "\(picked) picked" : "")
                .accessibilityHint("Opens this section")
                .accessibilityIdentifier("favorites.section.\(cat.rawValue)")
            }
        }
    }

    // MARK: - Finish

    private var finishButton: some View {
        Button {
            vm.advance(to: .week)
        } label: {
            Text(vm.canFinish
                 ? "Next — \(vm.favoritesCount) items"
                 : "Pick \(Constants.Onboarding.minimumFavorites - vm.favoritesCount) more to continue")
                .contentTransition(.numericText())
                .primaryButtonLabel(enabled: vm.canFinish)
        }
        .buttonStyle(ScalePressStyle())
        .disabled(!vm.canFinish)
        .accessibilityIdentifier("onboarding.favorites.finish")
        .animation(.snappyValue, value: vm.favoritesCount)
    }
}

// MARK: - Section header

private struct CategorySectionHeader: View {
    let category: CatalogCategory
    let selectedIDs: Set<String>
    let allSelected: Bool
    let isOpen: Bool
    let canFold: Bool
    let onToggleOpen: () -> Void
    let onToggleAll: () -> Void

    private var count: Int {
        CatalogItem.all.filter { $0.category == category && selectedIDs.contains($0.id) }.count
    }

    var body: some View {
        HStack(spacing: 6) {
            Button(action: onToggleOpen) {
                HStack(spacing: 6) {
                    if canFold {
                        Image(systemName: "chevron.right")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(Color.labelSecondary)
                            .rotationEffect(.degrees(isOpen ? 90 : 0))
                    }
                    Image(systemName: category.symbol)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Color.labelPrimary)
                    Text(category.displayName)
                    Spacer()
                }
                .frame(minHeight: 44)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(!canFold)
            .accessibilityLabel(category.displayName)
            .accessibilityValue(isOpen ? "Expanded" : "Collapsed")
            .accessibilityIdentifier("favorites.sectionHeader.\(category.rawValue)")
            if count > 0 {
                Text("\(count)" as String)
                    .font(.caption2).fontWeight(.bold)
                    .foregroundStyle(Color.onAccent)
                    .padding(.horizontal, 7).padding(.vertical, 2)
                    .background(Color.dullPink, in: Capsule())
            }
            Button(allSelected ? "Clear all" : "Select all", action: onToggleAll)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(Color.labelPrimary)
                .frame(minHeight: 44)
                .contentShape(Rectangle())
                .buttonStyle(.plain)
                .accessibilityLabel((allSelected ? "Clear all " : "Select all ") + category.displayName)
                .accessibilityIdentifier("favorites.selectAll.\(category.rawValue)")
        }
        .font(.footnote).fontWeight(.semibold)
        .foregroundStyle(Color.labelSecondary)
        .textCase(nil)
    }
}

// MARK: - Food chip

/// A food as a pill you tap to pick, matching the diet screen's chips.
private struct FoodChip: View {
    let item: CatalogItem
    let isSelected: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            // No tick: picking a food only changes its colour, so the chip keeps its
            // width and nothing jumps to another row.
            Text(item.name)
                .font(.subheadline.weight(.medium))
                .lineLimit(1)
            .padding(.horizontal, 14)
            .frame(minHeight: 44)
            .background(isSelected ? Color.dullPink : Color.surfaceSecondary, in: Capsule())
            .foregroundStyle(isSelected ? Color.onAccent : Color.labelPrimary)
            .overlay(Capsule().strokeBorder(isSelected ? Color.clear : Color(.separator), lineWidth: 0.5))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .sensoryFeedback(.selection, trigger: isSelected)
        .animation(.spring(duration: 0.2, bounce: 0.3), value: isSelected)
        .accessibilityIdentifier("favorite.item.\(item.id)")
        .accessibilityLabel(item.name)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

// MARK: - Shared card for profile editing

struct ProductFavoriteCard: View {
    let item: CatalogItem
    let isSelected: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                Circle()
                    .fill(Color.labelPrimary.opacity(0.15))
                    .frame(width: 38, height: 38)
                    .overlay(
                        Image(systemName: item.category.symbol)
                            .font(.system(size: 15, weight: .medium))
                            .foregroundStyle(Color.labelPrimary)
                    )
                Text(item.name)
                    .font(.subheadline)
                    .foregroundStyle(Color.labelPrimary)
                Spacer()
                // Like Burst heart; the whole row stays the tap target.
                LikeBurstHeart(isOn: isSelected)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .sensoryFeedback(.selection, trigger: isSelected)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

#Preview {
    NavigationStack { FavoriteFoodsView(vm: OnboardingViewModel()) }
}
