import SwiftUI

struct FavoriteFoodsView: View {

    @Bindable var vm: OnboardingViewModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false

    private let columns = [
        GridItem(.flexible(), spacing: 12),
        GridItem(.flexible(), spacing: 12),
    ]

    var body: some View {

        VStack(spacing: 0) {

            // Progress bar + header (sticky)
            VStack(alignment: .leading, spacing: 16) {
                OnboardingProgressBar(currentStep: 5)
                    .padding(.top, 8)

                VStack(alignment: .leading, spacing: 6) {
                    Text("Pick your favorites")
                        .font(.largeTitle).fontWeight(.bold)
                    Text("We'll watch for discounts on these and build your meal plans around them.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 24)

                // Search bar
                HStack {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(.secondary)
                    TextField("Search foods...", text: $vm.foodSearchQuery)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                }
                .padding(10)
                .background(Color.surfaceSecondary)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .padding(.horizontal, 24)

                // Category filter scroll
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(FoodCategory.allCases) { cat in
                            CategoryChip(
                                category: cat,
                                isSelected: vm.selectedCategory == cat
                            ) {
                                vm.applyFilter(category: cat)
                            }
                        }
                    }
                    .padding(.horizontal, 24)
                }
            }
            .background(Color.surfaceGrouped)

            // Food grid
            ScrollView {
                if vm.filteredFoods.isEmpty {
                    ContentUnavailableView(
                        "No foods found",
                        systemImage: "magnifyingglass",
                        description: Text("Try a different search or category")
                    )
                    .padding(.top, 40)
                } else {
                    LazyVGrid(columns: columns, spacing: 12) {
                        ForEach(vm.filteredFoods) { food in
                            FoodGridCard(
                                food: food,
                                isFavorited: vm.favoriteFoodIDs.contains(food.id),
                                reduceMotion: reduceMotion
                            ) {
                                vm.toggleFavorite(food)
                            }
                        }
                    }
                    .padding(16)
                    .padding(.bottom, 100)   // space for the sticky footer
                }
            }
        }
        .background(Color.surfaceGrouped.ignoresSafeArea())
        .navigationBarHidden(true)
        .overlay(alignment: .bottom) {
            FinishButton(
                count: vm.favoritesCount,
                canFinish: vm.canFinish
            ) {
                vm.finish()
                hasCompletedOnboarding = true
            }
        }
    }
}

// MARK: - Category chip

private struct CategoryChip: View {
    let category: FoodCategory
    let isSelected: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 5) {
                Image(systemName: category.sfSymbol)
                    .font(.system(size: 12))
                Text(category.displayName)
                    .font(.subheadline)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(isSelected ? Color.brandPrimary : Color.surfaceSecondary)
            .foregroundStyle(isSelected ? .white : .primary)
            .clipShape(Capsule())
        }
        .buttonStyle(.plain)
        .sensoryFeedback(.selection, trigger: isSelected)
        .animation(.spring(duration: 0.2), value: isSelected)
    }
}

// MARK: - Food grid card

private struct FoodGridCard: View {
    let food: Food
    let isFavorited: Bool
    let reduceMotion: Bool
    let onTap: () -> Void

    @State private var heartScale: CGFloat = 1.0

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {

            // Food icon + heart button
            ZStack(alignment: .topTrailing) {
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.brandPrimary.opacity(0.08))
                    .frame(height: 80)
                    .overlay(
                        Image(systemName: foodIcon(for: food.category))
                            .font(.system(size: 32))
                            .foregroundStyle(Color.brandPrimary.opacity(0.5))
                    )

                Button(action: {
                    if !reduceMotion {
                        withAnimation(.spring(duration: 0.25, bounce: 0.5)) {
                            heartScale = 1.4
                        }
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                            withAnimation(.spring(duration: 0.2)) {
                                heartScale = 1.0
                            }
                        }
                    }
                    onTap()
                }) {
                    Image(systemName: isFavorited ? "heart.fill" : "heart")
                        .font(.system(size: 18))
                        .foregroundStyle(isFavorited ? Color.brandDanger : Color.labelSecondary)
                        .scaleEffect(heartScale)
                        .frame(width: 36, height: 36)
                }
                .sensoryFeedback(isFavorited ? .impact : .selection, trigger: isFavorited)
            }

            // Name
            Text(food.displayName)
                .font(.subheadline).fontWeight(.medium)
                .lineLimit(2)
                .minimumScaleFactor(0.85)

            // Calories
            Text("\(food.caloriesPer100g) kcal / 100g")
                .font(.caption)
                .foregroundStyle(Color.brandAmber)
                .fontWeight(.medium)

            // Macro hint
            Text(food.macroSummary)
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
        }
        .padding(12)
        .background(Color.surface)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .strokeBorder(
                    isFavorited ? Color.brandPrimary.opacity(0.4) : Color(.separator),
                    lineWidth: isFavorited ? 1.5 : 0.5
                )
        )
        .animation(.spring(duration: 0.2), value: isFavorited)
    }

    private func foodIcon(for category: FoodCategory) -> String {
        switch category {
        case .dairy:      return "drop.fill"
        case .meat:       return "fork.knife"
        case .vegetables: return "leaf.fill"
        case .fruits:     return "apple.logo"
        case .grains:     return "square.3.layers.3d"
        case .snacks:     return "popcorn.fill"
        case .beverages:  return "cup.and.saucer.fill"
        case .legumes:    return "circle.grid.2x2.fill"
        case .seafood:    return "fish.fill"
        case .all:        return "square.grid.2x2"
        }
    }
}

// MARK: - Finish button (sticky footer)

private struct FinishButton: View {
    let count: Int
    let canFinish: Bool
    let onTap: () -> Void

    private var remaining: Int { max(Constants.Onboarding.minimumFavorites - count, 0) }

    var body: some View {
        VStack(spacing: 6) {
            if !canFinish {
                Text("Select \(remaining) more to continue")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Button(action: onTap) {
                HStack {
                    Label("Finish Setup", systemImage: "checkmark.circle.fill")
                        .font(.headline)
                    if count > 0 {
                        Spacer()
                        Text("\(count) favorites")
                            .font(.subheadline)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 4)
                            .background(Color.white.opacity(0.25))
                            .clipShape(Capsule())
                    }
                }
                .frame(maxWidth: .infinity)
                .padding()
                .background(canFinish ? Color.brandPrimary : Color(.systemFill))
                .foregroundStyle(canFinish ? .white : Color(.secondaryLabel))
                .clipShape(RoundedRectangle(cornerRadius: 16))
            }
            .disabled(!canFinish)
            .animation(.spring(duration: 0.3), value: canFinish)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 16)
        .background(
            Color.surfaceGrouped
                .overlay(Divider(), alignment: .top)
        )
    }
}

#Preview {
    NavigationStack {
        FavoriteFoodsView(vm: OnboardingViewModel())
    }
}
