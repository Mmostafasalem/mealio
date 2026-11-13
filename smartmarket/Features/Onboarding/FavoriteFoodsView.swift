import SwiftUI

struct FavoriteFoodsView: View {

    @Bindable var vm: OnboardingViewModel
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false

    var body: some View {
        OnboardingScaffold(vm: vm, step: .favorites, title: "Build your fridge",
                           subtitle: "Pick at least \(Constants.Onboarding.minimumFavorites) things you buy regularly. Meal plans start from these.",
                           contentPadding: 0) {
            VStack(spacing: 0) {
                searchField
                categoryStrip
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
                }
                .accessibilityLabel("Clear search")
            }
        }
        .padding(.horizontal, Spacing.lg)
        .frame(minHeight: 48)
        .background(Color.surface, in: Capsule())
        .overlay(Capsule().strokeBorder(Color.hairline, lineWidth: 1))
        .padding(.horizontal, Spacing.xl)
    }

    // MARK: - Category strip

    private var categoryStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                CategoryChip(label: "All", isSelected: vm.selectedCategory == nil) {
                    vm.applyFilter(category: nil)
                }
                ForEach(CatalogCategory.allCases) { cat in
                    CategoryChip(label: cat.displayName, isSelected: vm.selectedCategory == cat) {
                        vm.applyFilter(category: cat)
                    }
                }
            }
            .padding(.horizontal, Spacing.xl)
            .padding(.vertical, Spacing.md)
        }
    }

    // MARK: - Item list

    private var itemList: some View {
        // The catalogue is the one thing here that has to scroll.
        ScrollView {
            LazyVStack(alignment: .leading, spacing: Spacing.xl) {
                if vm.filteredItems.isEmpty {
                    Text("No items match your search.")
                        .foregroundStyle(Color.labelSecondary)
                } else if vm.selectedCategory == nil && vm.foodSearchQuery.isEmpty {
                    // Grouped by category
                    ForEach(CatalogCategory.allCases) { cat in
                        let items = CatalogItem.all.filter { $0.category == cat }
                        if !items.isEmpty {
                            VStack(alignment: .leading, spacing: Spacing.md) {
                                CategorySectionHeader(category: cat, selectedIDs: vm.favoriteFoodIDs)
                                chips(items)
                            }
                        }
                    }
                } else {
                    // One group when searching or filtered to a category
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

    // MARK: - Finish

    private var finishButton: some View {
        Button {
            vm.finish()
            hasCompletedOnboarding = true
        } label: {
            Text(vm.canFinish
                 ? "Done — \(vm.favoritesCount) items"
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

// MARK: - Category chip (strip)

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
        }
        .buttonStyle(.plain)
        // Colour-only change, so it stays animated under Reduce Motion.
        .animation(.snappyValue, value: isSelected)
    }
}

// MARK: - Section header

private struct CategorySectionHeader: View {
    let category: CatalogCategory
    let selectedIDs: Set<String>

    private var count: Int {
        CatalogItem.all.filter { $0.category == category && selectedIDs.contains($0.id) }.count
    }

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: category.symbol)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Color.labelPrimary)
            Text(category.displayName)
            Spacer()
            if count > 0 {
                Text("\(count)")
                    .font(.caption2).fontWeight(.bold)
                    .foregroundStyle(Color.onAccent)
                    .padding(.horizontal, 7).padding(.vertical, 2)
                    .background(Color.dullPink, in: Capsule())
            }
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
            HStack(spacing: 6) {
                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.caption.weight(.bold))
                        .transition(.scale.combined(with: .opacity))
                }
                Text(item.name)
                    .font(.subheadline.weight(.medium))
                    .lineLimit(1)
            }
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
