import SwiftUI

struct FavoriteFoodsView: View {

    @Bindable var vm: OnboardingViewModel
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false

    var body: some View {
        VStack(spacing: 0) {
            itemList
            finishBar
        }
        .background(Color.surfaceGrouped.ignoresSafeArea())
        .navigationBarHidden(true)
    }

    // MARK: - Progress + title

    private func favoriteRow(_ item: CatalogItem) -> some View {
        ItemRow(item: item, isSelected: vm.favoriteFoodIDs.contains(item.id)) { vm.toggleFavorite(item) }
    }

    private var progressHeader: some View {
        VStack(alignment: .leading, spacing: 12) {
            OnboardingProgressBar(currentStep: 5).padding(.top, 8)
            Text("Build your fridge")
                .font(.title2).fontWeight(.bold)
            Text("Pick everything you buy regularly. We'll use these to tailor your meal plans and grocery suggestions.")
                .font(.subheadline).foregroundStyle(Color.labelSecondary).fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 14)
        .background(Color.surfaceGrouped)
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
            .padding(.horizontal, 20)
            .padding(.vertical, 10)
        }
        .background(Color.surfaceGrouped)
        .overlay(Divider(), alignment: .bottom)
    }

    // MARK: - Item list

    private var itemList: some View {
        List {
            // Keep explanatory content scrollable: at accessibility text sizes
            // a fixed header can consume the entire product list's height.
            progressHeader
                .listRowInsets(EdgeInsets())
                .listRowSeparator(.hidden)
                .listRowBackground(Color.clear)
            categoryStrip
                .listRowInsets(EdgeInsets())
                .listRowSeparator(.hidden)
                .listRowBackground(Color.clear)
            if vm.filteredItems.isEmpty {
                Text("No items match your search.")
                    .foregroundStyle(Color.labelSecondary)
                    .listRowBackground(Color.clear)
            } else if vm.selectedCategory == nil && vm.foodSearchQuery.isEmpty {
                // Grouped by category
                ForEach(CatalogCategory.allCases) { cat in
                    let items = CatalogItem.all.filter { $0.category == cat }
                    if !items.isEmpty {
                        Section {
                            ForEach(items, content: favoriteRow)
                        } header: {
                            CategorySectionHeader(category: cat, selectedIDs: vm.favoriteFoodIDs)
                        }
                    }
                }
            } else {
                // Flat list when searching or category filtered
                Section {
                    ForEach(vm.filteredItems) { item in
                        ItemRow(
                            item: item,
                            isSelected: vm.favoriteFoodIDs.contains(item.id)
                        ) { vm.toggleFavorite(item) }
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .searchable(text: $vm.foodSearchQuery, prompt: "Search \(CatalogItem.all.count) products…")
        .scrollDismissesKeyboard(.immediately)
    }

    // MARK: - Finish bar

    private var finishBar: some View {
        VStack(spacing: 6) {
            if !vm.canFinish {
                let remaining = Constants.Onboarding.minimumFavorites - vm.favoritesCount
                Text("Pick \(remaining) more to continue")
                    .font(.caption).foregroundStyle(Color.labelSecondary)
            }
            Button {
                vm.finish()
                hasCompletedOnboarding = true
            } label: {
                HStack(spacing: 10) {
                    Text(vm.canFinish ? "Done — \(vm.favoritesCount) items" : "Finish Setup")
                        .font(.headline)
                    Spacer()
                    Image(systemName: "checkmark.circle.fill")
                        .font(.title3)
                }
                .padding(.horizontal, Spacing.xl)
                .padding(.vertical, Spacing.lg)
                .background(vm.canFinish ? Color.dullPink : Color(.systemFill),
                            in: RoundedRectangle(cornerRadius: Radius.tile, style: .continuous))
                .foregroundStyle(vm.canFinish ? Color.onAccent : Color.labelSecondary)
            }
            .disabled(!vm.canFinish)
            .accessibilityIdentifier("onboarding.favorites.finish")
            .animation(.spring(duration: 0.3), value: vm.canFinish)
            .padding(.horizontal, 20)
        }
        .padding(.vertical, 14)
        .background(.ultraThinMaterial)
        .overlay(Divider(), alignment: .top)
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
        .animation(.spring(duration: 0.2), value: isSelected)
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

// MARK: - Item row

private struct ItemRow: View {
    let item: CatalogItem
    let isSelected: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 14) {
                // Category color dot
                Circle()
                    .fill(Color.labelPrimary.opacity(0.18))
                    .frame(width: 32, height: 32)
                    .overlay(
                        Image(systemName: item.category.symbol)
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(Color.labelPrimary)
                    )

                Text(item.name)
                    .font(.body)
                    .foregroundStyle(Color.labelPrimary)

                Spacer()

                // Checkmark
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 20))
                    .foregroundStyle(isSelected ? Color.dullPink : Color(.tertiaryLabel))
                    .animation(.spring(duration: 0.2, bounce: 0.4), value: isSelected)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .sensoryFeedback(.selection, trigger: isSelected)
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
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 20))
                    .foregroundStyle(isSelected ? Color.dullPink : Color(.tertiaryLabel))
                    .animation(.spring(duration: 0.2, bounce: 0.4), value: isSelected)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .sensoryFeedback(.selection, trigger: isSelected)
    }
}

#Preview {
    NavigationStack { FavoriteFoodsView(vm: OnboardingViewModel()) }
}
