import SwiftUI

// MARK: - RecipeSheet

struct RecipeSheet: View {

    let mealName: String
    @State private var recipe: Recipe?
    @State private var isLoading = false
    @State private var failed = false
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Group {
                if isLoading {
                    loadingView
                } else if let recipe {
                    recipeContent(recipe)
                } else if failed {
                    errorView
                }
            }
            .navigationTitle(mealName)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .fontWeight(.semibold)
                }
            }
        }
        .task { await loadRecipe() }
    }

    // MARK: - Loading

    private var loadingView: some View {
        VStack(spacing: 20) {
            ProgressView()
                .scaleEffect(1.4)
                .tint(.brandPrimary)
            Text("Generating recipe…")
                .font(.subheadline)
                .foregroundStyle(Color.labelSecondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Error

    private var errorView: some View {
        ErrorStateView(
            title: "Couldn't load recipe",
            message: "We couldn't reach the kitchen. Check your connection and try again."
        ) { Task { await loadRecipe() } }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Recipe content

    @ViewBuilder
    private func recipeContent(_ r: Recipe) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {

                // Time + servings strip
                HStack(spacing: 0) {
                    statPill(icon: "clock",        label: "Prep",     value: "\(r.prepTime)m")
                    Divider().frame(height: 32)
                    statPill(icon: "flame",        label: "Cook",     value: "\(r.cookTime)m")
                    Divider().frame(height: 32)
                    statPill(icon: "person.2",     label: "Serves",   value: "\(r.servings)")
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(Color.surface)
                .clipShape(RoundedRectangle(cornerRadius: 14))

                // Ingredients
                sectionHeader(icon: "cart.fill", title: "Ingredients")
                VStack(spacing: 0) {
                    ForEach(Array(r.ingredients.enumerated()), id: \.offset) { idx, ing in
                        HStack {
                            Circle()
                                .fill(Color.brandPrimary.opacity(0.15))
                                .frame(width: 8, height: 8)
                            Text(ing.name.capitalized)
                                .font(.body)
                            Spacer()
                            Text(ing.amount)
                                .font(.subheadline)
                                .foregroundStyle(Color.labelSecondary)
                        }
                        .padding(.vertical, 10)
                        .padding(.horizontal, 14)
                        if idx < r.ingredients.count - 1 {
                            Divider().padding(.leading, 14)
                        }
                    }
                }
                .background(Color.surface)
                .clipShape(RoundedRectangle(cornerRadius: 14))

                // Steps
                sectionHeader(icon: "list.number", title: "Instructions")
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(Array(r.steps.enumerated()), id: \.offset) { idx, step in
                        HStack(alignment: .top, spacing: 14) {
                            Text("\(idx + 1)")
                                .font(.caption).fontWeight(.bold)
                                .foregroundStyle(Color.onAccent)
                                .frame(width: 26, height: 26)
                                .background(Color.dullPink)
                                .clipShape(Circle())
                            Text(step)
                                .font(.body)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .padding(14)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.surface)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                }

                // Tip
                if let tip = r.tip, !tip.isEmpty {
                    HStack(alignment: .top, spacing: 12) {
                        Image(systemName: "lightbulb.fill")
                            .foregroundStyle(Color.brandAmber)
                        Text(tip)
                            .font(.subheadline)
                            .foregroundStyle(Color.labelSecondary)
                    }
                    .padding(14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.brandAmber.opacity(0.08))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                }
            }
            .padding(16)
        }
        .background(Color.surfaceGrouped)
    }

    // MARK: - Helpers

    private func statPill(icon: String, label: String, value: String) -> some View {
        VStack(spacing: 4) {
            Image(systemName: icon)
                .font(.caption)
                .foregroundStyle(Color.brandPrimary)
            Text(value)
                .font(.subheadline).fontWeight(.semibold)
            Text(label)
                .font(.caption2)
                .foregroundStyle(Color.labelSecondary)
        }
        .frame(maxWidth: .infinity)
    }

    private func sectionHeader(icon: String, title: String) -> some View {
        Label(title, systemImage: icon)
            .font(.headline)
            .foregroundStyle(Color.labelPrimary)
    }

    // MARK: - Data

    private func loadRecipe() async {
        isLoading = true
        failed    = false
        do {
            recipe = try await APIService.shared.fetchRecipe(mealName: mealName)
        } catch {
            failed = true
        }
        isLoading = false
    }
}
