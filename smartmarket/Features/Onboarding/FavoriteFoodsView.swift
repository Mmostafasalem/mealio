import SwiftUI

/// "Pick your foods": opens with a ready list made from the diet and goal
/// (`FoodChoices.starterList`). The person takes off what they don't buy, stars the
/// foods they buy most, and adds more from the sections below. Foods and sections
/// the diet rules out are not offered at all.
struct FavoriteFoodsView: View {

    @Bindable var vm: OnboardingViewModel
    /// One section open at a time; with none open the screen shows the list and the sections.
    @State private var openSection: FoodSection?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        OnboardingScaffold(vm: vm, step: .favorites, title: "Pick your foods",
                           subtitle: "We made you a list from your diet and goal. Take off what you don't buy, star what you buy most, and add more.",
                           contentPadding: 0) {
            VStack(spacing: 0) {
                searchField
                    .padding(.bottom, Spacing.md)
                itemList
            }
        } footer: {
            finishButton
        }
        .onAppear { vm.prepareFavorites() }
    }

    private func open(_ section: FoodSection?) {
        withAnimation(reduceMotion ? nil : .snappy) { openSection = section }
    }

    private func chip(_ item: CatalogItem) -> some View {
        FoodChip(item: item, isSelected: vm.favoriteFoodIDs.contains(item.id),
                 isStarred: vm.starredFoodIDs.contains(item.id)) { vm.toggleFavorite(item) }
    }

    /// Foods as wrapping chips, like the diet screen.
    private func chips(_ items: [CatalogItem]) -> some View {
        FlowLayout(spacing: 10) {
            ForEach(items, content: chip)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Your list

    private var yourList: some View {
        let list = vm.yourList
        let picked = list.filter { vm.favoriteFoodIDs.contains($0.id) }.count
        return VStack(alignment: .leading, spacing: Spacing.sm) {
            HStack(alignment: .firstTextBaseline) {
                Label("Your list", systemImage: "checklist")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(Color.labelPrimary)
                Spacer()
                Text("\(picked) picked · \(vm.starredFoodIDs.count) starred" as String)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color.labelSecondary)
                    .monospacedDigit()
                    .contentTransition(.numericText())
            }
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isHeader)
            FlowLayout(spacing: 8) {
                ForEach(list) { item in
                    ListChip(item: item, isSelected: vm.favoriteFoodIDs.contains(item.id),
                             isStarred: vm.starredFoodIDs.contains(item.id),
                             onToggle: { vm.toggleFavorite(item) }, onStar: { vm.toggleStar(item) })
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("favorites.yourList")
        }
    }

    // MARK: - A section, open

    /// A section: its header with Select all, then its foods by kind (chicken, pork…),
    /// each kind with its own Select all, and "Select more foods" to go back to the sections.
    private func section(_ section: FoodSection) -> some View {
        let groups = CatalogSubgroups.groups(of: section.items, in: section.category)
        return VStack(alignment: .leading, spacing: Spacing.md) {
            CategorySectionHeader(section: section, selectedIDs: vm.favoriteFoodIDs,
                                  allSelected: Set(section.items.map(\.id)).isSubset(of: vm.favoriteFoodIDs),
                                  onClose: { open(nil) }) {
                vm.toggleAll(section.items)
            }
            ForEach(groups, id: \.title) { group in
                VStack(alignment: .leading, spacing: Spacing.sm) {
                    if groups.count > 1 { subgroupHeader(group.title, items: group.items) }
                    chips(group.items)
                }
            }
            Button { open(nil) } label: {
                Label("Select more foods", systemImage: "square.grid.2x2")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.labelPrimary)
                    .frame(maxWidth: .infinity, minHeight: 48)
                    .background(Color.surfaceSecondary, in: RoundedRectangle(cornerRadius: Radius.chip, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: Radius.chip, style: .continuous)
                        .strokeBorder(Color.hairline, lineWidth: 1))
                    .contentShape(Rectangle())
            }
            .buttonStyle(ScalePressStyle())
            .padding(.top, Spacing.sm)
            .accessibilityHint("Goes back to every section")
            .accessibilityIdentifier("favorites.selectMore")
        }
    }

    private func subgroupHeader(_ title: String, items: [CatalogItem]) -> some View {
        let picked = items.filter { vm.favoriteFoodIDs.contains($0.id) }.count
        let allPicked = picked == items.count
        return HStack(spacing: 8) {
            Text(title).font(.caption.weight(.bold)).foregroundStyle(Color.labelPrimary)
            Text("\(picked) of \(items.count)" as String)
                .font(.caption).foregroundStyle(Color.labelSecondary).monospacedDigit()
            Spacer()
            Button {
                withAnimation(.snappy) { vm.toggleAll(items) }
            } label: {
                Text(allPicked ? "Clear" : "Select all")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(allPicked ? Color.labelSecondary : Color.labelPrimary)
                    .padding(.horizontal, 10).padding(.vertical, 5)
                    .background(Color(.tertiarySystemFill), in: Capsule())
                    .frame(minHeight: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(allPicked ? "Clear \(title)" : "Select all \(title)")
            .accessibilityIdentifier("favorites.selectAll.\(title)")
        }
        .accessibilityElement(children: .contain)
    }

    // MARK: - Search

    private var searchField: some View {
        HStack(spacing: Spacing.sm) {
            Image(systemName: "magnifyingglass").foregroundStyle(Color.labelSecondary)
            TextField("Search \(vm.offeredItems.count) foods", text: $vm.foodSearchQuery)
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
        // The list is the one thing here that has to scroll.
        ScrollView {
            LazyVStack(alignment: .leading, spacing: Spacing.lg) {
                if !vm.foodSearchQuery.isEmpty {
                    if vm.filteredItems.isEmpty {
                        Text("No foods match your search.")
                            .foregroundStyle(Color.labelSecondary)
                    } else {
                        chips(vm.filteredItems)
                    }
                } else if let open = openSection, let current = vm.foodSections.first(where: { $0.id == open.id }) {
                    section(current)
                } else {
                    yourList
                    VStack(alignment: .leading, spacing: Spacing.sm) {
                        Label("Add more foods", systemImage: "plus.circle")
                            .font(.subheadline.weight(.bold))
                            .foregroundStyle(Color.labelPrimary)
                            .accessibilityAddTraits(.isHeader)
                        sectionGrid
                    }
                }
            }
            .padding(.horizontal, Spacing.xl)
            .padding(.bottom, Spacing.xl)
        }
        .scrollIndicators(.hidden)
        .scrollDismissesKeyboard(.immediately)
        .accessibilityIdentifier("favorites.list")
    }

    /// Every section the diet allows as a small tile, three to a row: tap one to open it.
    private var sectionGrid: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 3), spacing: 8) {
            ForEach(vm.foodSections) { sec in
                let picked = sec.items.filter { vm.favoriteFoodIDs.contains($0.id) }.count
                Button { open(sec) } label: {
                    VStack(spacing: 4) {
                        Image(systemName: sec.symbol)
                            .font(.system(size: 14, weight: .semibold))
                        Text(sec.title)
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
                .accessibilityLabel(sec.title)
                .accessibilityValue(picked > 0 ? "\(picked) of \(sec.items.count) picked" : "\(sec.items.count) foods")
                .accessibilityHint("Opens this section")
                .accessibilityIdentifier("favorites.section.\(sec.id)")
            }
        }
    }

    // MARK: - Finish

    private var finishButton: some View {
        Button {
            vm.continueFrom(.favorites)
        } label: {
            Text(vm.canFinish
                 ? "Next — \(vm.favoritesCount) foods"
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
    let section: FoodSection
    let selectedIDs: Set<String>
    let allSelected: Bool
    let onClose: () -> Void
    let onToggleAll: () -> Void

    private var count: Int { section.items.filter { selectedIDs.contains($0.id) }.count }

    var body: some View {
        HStack(spacing: 6) {
            Button(action: onClose) {
                HStack(spacing: 6) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(Color.labelSecondary)
                    Image(systemName: section.symbol)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Color.labelPrimary)
                    Text(section.title)
                        .foregroundStyle(Color.labelPrimary)
                    Spacer()
                }
                .frame(minHeight: 44)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Back to every section")
            .accessibilityValue(section.title)
            .accessibilityIdentifier("favorites.sectionHeader.\(section.id)")
            if count > 0 {
                Text("\(count)" as String)
                    .font(.caption2).fontWeight(.bold)
                    .foregroundStyle(Color.onAccent)
                    .padding(.horizontal, 7).padding(.vertical, 2)
                    .background(Color.dullPink, in: Capsule())
                    .accessibilityLabel("\(count) picked")
            }
            Button(action: onToggleAll) {
                Text(allSelected ? "Clear all" : "Select all")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Color.onAccent)
                    .padding(.horizontal, 12).padding(.vertical, 6)
                    .background(Color.progress, in: Capsule())
                    .frame(minHeight: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel((allSelected ? "Clear all " : "Select all ") + section.title)
            .accessibilityIdentifier("favorites.selectAll.\(section.id)")
        }
        .font(.subheadline).fontWeight(.bold)
        .textCase(nil)
    }
}

// MARK: - Chips

/// A food as a pill you tap to pick, matching the diet screen's chips.
private struct FoodChip: View {
    let item: CatalogItem
    let isSelected: Bool
    var isStarred = false
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            // No tick: picking a food only changes its colour, so the chip keeps its
            // width and nothing jumps to another row.
            HStack(spacing: 4) {
                if isStarred && isSelected {
                    Image(systemName: "star.fill").font(.caption2.weight(.bold)).accessibilityHidden(true)
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
        .accessibilityLabel(item.name + (isStarred && isSelected ? ", starred" : ""))
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

/// A food on "Your list": a star to mark the ones bought most, and a tap to take it off
/// (it stays, unpicked, with a plus to put it back). The leading slot keeps its width
/// either way, so the chips don't reflow.
private struct ListChip: View {
    let item: CatalogItem
    let isSelected: Bool
    let isStarred: Bool
    let onToggle: () -> Void
    let onStar: () -> Void

    var body: some View {
        HStack(spacing: 0) {
            Button(action: isSelected ? onStar : onToggle) {
                Image(systemName: isSelected ? (isStarred ? "star.fill" : "star") : "plus")
                    .font(.footnote.weight(.bold))
                    .contentTransition(.symbolEffect(.replace))
                    .frame(width: 34, height: 44)
                    .padding(.leading, 6)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .sensoryFeedback(.selection, trigger: isStarred)
            .accessibilityLabel(isStarred ? "Remove star from \(item.name)" : "Star \(item.name)")
            .accessibilityHint("Starred foods come first in your weekly groceries")
            .accessibilityHidden(!isSelected)
            .accessibilityIdentifier("favorite.star.\(item.id)")
            Button(action: onToggle) {
                Text(item.name)
                    .font(.subheadline.weight(.medium))
                    .lineLimit(1)
                    .strikethrough(!isSelected, color: Color.labelTertiary)
                    .padding(.trailing, 14)
                    .frame(minHeight: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("favorite.item.\(item.id)")
            .accessibilityLabel(item.name + (isStarred ? ", starred" : ""))
            .accessibilityHint(isSelected ? "Takes it off your list" : "Puts it back on your list")
            .accessibilityAddTraits(isSelected ? .isSelected : [])
        }
        .foregroundStyle(isSelected ? Color.onAccent : Color.labelSecondary)
        .background(isSelected ? Color.dullPink : Color.surfaceSecondary, in: Capsule())
        .overlay(Capsule().strokeBorder(isSelected ? Color.clear : Color(.separator), lineWidth: 0.5))
        .sensoryFeedback(.selection, trigger: isSelected)
        .animation(.spring(duration: 0.2, bounce: 0.3), value: isSelected)
        .animation(.snappy, value: isStarred)
    }
}

#Preview {
    NavigationStack { FavoriteFoodsView(vm: OnboardingViewModel()) }
}
