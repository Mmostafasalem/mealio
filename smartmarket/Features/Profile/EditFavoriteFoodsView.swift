import SwiftUI

struct EditFavoriteFoodsView: View {

    @Bindable var vm: ProfileViewModel
    @State private var query = ""
    @State private var filtered: [Food] = Food.catalog
    @State private var filterTask: Task<Void, Never>?

    private let columns = [
        GridItem(.flexible(), spacing: 12),
        GridItem(.flexible(), spacing: 12),
    ]

    var body: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 12) {
                ForEach(filtered) { food in
                    FavoriteCard(
                        food: food,
                        isFavorited: vm.favoriteFoodIDs.contains(food.id)
                    ) {
                        vm.toggleFavorite(food)
                    }
                }
            }
            .padding(16)
        }
        .background(Color.surfaceGrouped.ignoresSafeArea())
        .searchable(text: $query, prompt: "Search foods")
        .onChange(of: query) { _, newValue in
            filterTask?.cancel()
            filterTask = Task {
                try? await Task.sleep(nanoseconds: 150_000_000)
                guard !Task.isCancelled else { return }
                let q = newValue.lowercased()
                filtered = q.isEmpty ? Food.catalog : Food.catalog.filter {
                    $0.name.lowercased().contains(q) || $0.nameEn.lowercased().contains(q)
                }
            }
        }
        .navigationTitle("Favorite Foods")
        .navigationBarTitleDisplayMode(.inline)
        .onDisappear { vm.save() }
    }
}

private struct FavoriteCard: View {
    let food: Food
    let isFavorited: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Image(systemName: food.category.sfSymbol)
                        .foregroundStyle(Color.brandPrimary.opacity(0.6))
                    Spacer()
                    Image(systemName: isFavorited ? "heart.fill" : "heart")
                        .foregroundStyle(isFavorited ? Color.brandDanger : Color.labelSecondary)
                }
                Text(food.displayName)
                    .font(.subheadline).fontWeight(.medium)
                    .lineLimit(2).minimumScaleFactor(0.85)
                    .multilineTextAlignment(.leading)
                Text("\(food.caloriesPer100g) kcal / 100g")
                    .font(.caption).foregroundStyle(Color.brandAmber)
            }
            .frame(maxWidth: .infinity, minHeight: 90, alignment: .topLeading)
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
        }
        .buttonStyle(.plain)
        .sensoryFeedback(.selection, trigger: isFavorited)
        .animation(.spring(duration: 0.2), value: isFavorited)
    }
}

#Preview {
    NavigationStack { EditFavoriteFoodsView(vm: ProfileViewModel()) }
}
