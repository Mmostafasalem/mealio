import SwiftUI

// MARK: - RecipeSheet

struct RecipeSheet: View {

    let mealName: String
    @State private var recipe: Recipe?
    @State private var isLoading: Bool
    @State private var failed = false
    /// Wikibooks recipes for this meal's foods, shown when AI recipes aren't available.
    @State private var cookbook: [CookbookRecipe]? = nil
    /// Why the last load failed: the error screen says so, instead of always blaming the connection.
    @State private var failure = Failure.connection
    @State private var speaker = ReadAlongSpeaker()
    @State private var ratings = RecipeRatingStore.shared
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    /// `recipe` shows a recipe without loading it (previews).
    init(mealName: String, recipe: Recipe? = nil) {
        self.mealName = mealName
        _recipe = State(initialValue: recipe)
        _isLoading = State(initialValue: recipe == nil)
    }

    private var language: String { AppState.shared.lang }

    private var rating: Binding<Int> {
        Binding(get: { ratings.rating(for: mealName) },
                set: { ratings.setRating($0, for: mealName) })
    }

    var body: some View {
        NavigationStack {
            Group {
                if isLoading {
                    loadingView
                } else if let recipe {
                    recipeContent(recipe)
                } else if let cookbook {
                    cookbookList(cookbook)
                } else if failed {
                    errorView
                }
            }
            .animation(reduceMotion ? .none : .easeOut(duration: 0.2), value: isLoading)
            .navigationTitle(mealName)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .fontWeight(.semibold)
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .presentationCornerRadius(Radius.sheet)
        .task { if recipe == nil { await loadRecipe() } }
        // Speech never outlives the sheet.
        .onDisappear { speaker.stop() }
    }

    // MARK: - Loading

    private var loadingView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.xl) {
                RoundedRectangle(cornerRadius: Radius.tile, style: .continuous).frame(height: 72)
                ForEach(0..<2) { _ in
                    RoundedRectangle(cornerRadius: 6, style: .continuous).frame(width: 130, height: 20)
                    VStack(spacing: Spacing.md) {
                        ForEach(0..<4) { _ in
                            RoundedRectangle(cornerRadius: 6, style: .continuous).frame(height: 24)
                        }
                    }
                }
            }
            .foregroundStyle(Color.labelTertiary.opacity(0.15))
            .padding(Spacing.lg)
            .shimmer()
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Loading recipe")
        .accessibilityIdentifier("recipe.loading")
    }

    // MARK: - Error

    private var errorView: some View {
        ErrorStateView(title: failure.title, message: failure.message) { Task { await loadRecipe() } }
            .accessibilityIdentifier("recipe.error")
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Recipe content

    @ViewBuilder
    private func recipeContent(_ r: Recipe) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {

                // Time + servings strip
                let statsLayout = dynamicTypeSize.isAccessibilitySize
                    ? AnyLayout(VStackLayout(spacing: Spacing.lg))
                    : AnyLayout(HStackLayout(spacing: 0))
                statsLayout {
                    statPill(icon: "clock",        label: "Prep",     value: "\(r.prepTime)m")
                    if !dynamicTypeSize.isAccessibilitySize { Divider().frame(height: 32) }
                    statPill(icon: "flame",        label: "Cook",     value: "\(r.cookTime)m")
                    if !dynamicTypeSize.isAccessibilitySize { Divider().frame(height: 32) }
                    statPill(icon: "person.2",     label: "Serves",   value: "\(r.servings)")
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(Color.surface)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))

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
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))

                // Steps
                HStack(alignment: .firstTextBaseline, spacing: Spacing.sm) {
                    sectionHeader(icon: "list.number", title: "Instructions")
                    Spacer(minLength: Spacing.sm)
                    if !r.steps.isEmpty { readAloudButton(r) }
                }
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(Array(r.steps.enumerated()), id: \.offset) { idx, step in
                        HStack(alignment: .top, spacing: 14) {
                            Text("\(idx + 1)" as String)
                                .font(.caption).fontWeight(.bold)
                                .foregroundStyle(Color.onAccent)
                                .frame(width: 26, height: 26)
                                .background(Color.dullPink)
                                .clipShape(Circle())
                            ReadAlongText(speaker: speaker, paragraph: idx, text: step, language: language)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .padding(14)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.surface)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }
                }
                .onAppear { speaker.load(r.steps) }

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
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                }

                // Rating (stored on this device only)
                StarRating(rating: rating)
                    .padding(.vertical, Spacing.lg)
                    .padding(.horizontal, 14)
                    .background(Color.surface)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .accessibilityIdentifier("recipe.rating")
            }
            .padding(16)
        }
        .background(Color.surfaceGrouped)
    }

    // MARK: - Helpers

    private func readAloudButton(_ r: Recipe) -> some View {
        Button {
            if speaker.isSpeaking { speaker.stop() } else {
                speaker.load(r.steps)
                speaker.start(language: language)
            }
        } label: {
            Label(speaker.isSpeaking ? "Stop" : "Read steps aloud",
                  systemImage: speaker.isSpeaking ? "stop.fill" : "speaker.wave.2.fill")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Color.labelPrimary)
                .padding(.horizontal, Spacing.md)
                .frame(minHeight: 36)
                .background(Color.surfaceSecondary, in: Capsule())
                // The pill stays 36 pt; the tap area is 44.
                .frame(minHeight: 44)
                .contentShape(Rectangle())
                .contentTransition(.opacity)
        }
        .buttonStyle(ScalePressStyle())
        .accessibilityHint(speaker.isSpeaking ? "Stops reading" : "Reads the recipe steps aloud")
        .accessibilityIdentifier("recipe.readAloud")
    }

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
        // Without online AI, the offline cookbook answers instead of a dead end.
        guard AIAccountService.shared.offersOnlineAI else {
            cookbook = await Self.cookbookMatches(for: mealName)
            isLoading = false
            return
        }
        do {
            recipe = try await APIService.shared.fetchRecipe(mealName: mealName)
        } catch {
            failure = Failure(error)
            if failure == .aiOff { cookbook = await Self.cookbookMatches(for: mealName) }
            failed = true
        }
        isLoading = false
    }

    /// Recipes that use this meal's main food (and ideally its other foods): "Chicken breast
    /// with brown rice & veg" finds chicken recipes, ones with rice first.
    static func cookbookMatches(for meal: String) async -> [CookbookRecipe] {
        let prefs = Set<DietaryPreference>.load()
        return await Task.detached(priority: .userInitiated) {
            let parts = meal.lowercased()
                .replacingOccurrences(of: " with ", with: ",").replacingOccurrences(of: "&", with: ",")
                .split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty && $0 != "veg" }
            guard let main = parts.first else { return [] }
            let mainKitchen = KitchenMatcher(names: [main]), all = KitchenMatcher(names: parts)
            let scored: [(CookbookRecipe, Int)] = CookbookLibrary.recipes.compactMap { r in
                guard r.course != .sauce, r.course != .dessert, r.fits(prefs),
                      r.keyIngredients.contains(where: mainKitchen.has) else { return nil }
                return (r, r.keyIngredients.filter(all.has).count)
            }
            return scored.sorted { $0.1 != $1.1 ? $0.1 > $1.1 : $0.0.title < $1.0.title }.prefix(15).map(\.0)
        }.value
    }

    private func cookbookList(_ recipes: [CookbookRecipe]) -> some View {
        List {
            Section {
                if recipes.isEmpty {
                    Text("No cookbook recipe uses these foods yet. Browse every recipe from Add Food or My Stock.")
                        .foregroundStyle(Color.labelSecondary)
                }
                ForEach(recipes) { r in
                    NavigationLink { CookbookRecipeView(recipe: r) } label: {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(r.title).font(.subheadline.weight(.semibold))
                            Text([r.course.title, r.minutes.map { "\($0) min" }, "\(Int(r.perServing.kcal)) kcal a serving"].compactMap { $0 }.joined(separator: " · "))
                                .font(.footnote).foregroundStyle(Color.labelSecondary)
                        }
                    }
                    .accessibilityIdentifier("recipe.cookbook.\(r.id)")
                }
            } header: {
                Text("Recipes for this meal")
            } footer: {
                Text("From the Wikibooks Cookbook, with nutrition estimated from USDA data. Your plan's portions are on the meal itself.")
            }
            Section { CookbookCredit(recipe: nil) }.listRowBackground(Color.clear)
        }
        .listStyle(.insetGrouped)
        .accessibilityIdentifier("recipe.cookbook")
    }

    /// Recipes are written by the online AI, so most failures are about AI not
    /// being set up or available, not about the connection.
    enum Failure: Equatable {
        case aiOff, aiBusy(String), connection

        init(_ error: Error) {
            switch error {
            case APIError.aiConsentRequired, AIAccountError.signInRequired:
                self = .aiOff
            case let account as AIAccountError:
                self = .aiBusy(account.errorDescription ?? "Nourlo AI isn't available right now. Please try again later.")
            case APIError.unverifiedAIResponse:
                self = .aiBusy("Nourlo AI isn't available right now. Please try again later.")
            default:
                self = .connection
            }
        }

        var title: String {
            switch self {
            case .aiOff: return "Recipes need Nourlo AI"
            case .aiBusy: return "AI recipes aren't available"
            case .connection: return "Couldn't load recipe"
            }
        }

        var message: String {
            switch self {
            case .aiOff:
                return "Step-by-step recipes are written by Nourlo AI, which isn't turned on yet. Turn it on in Profile, then try again. Everything else works without it."
            case .aiBusy(let text):
                return text
            case .connection:
                return "Recipes are written by Nourlo AI, and we couldn't reach it. Check your connection and try again."
            }
        }
    }
}

#Preview("Recipe") {
    Color.surfaceGrouped
        .sheet(isPresented: .constant(true)) {
            RecipeSheet(mealName: "Buckwheat with chicken", recipe: Recipe(
                mealName: "Buckwheat with chicken", prepTime: 10, cookTime: 20, servings: 2,
                ingredients: [RecipeIngredient(name: "buckwheat", amount: "150 g"),
                              RecipeIngredient(name: "chicken breast", amount: "300 g"),
                              RecipeIngredient(name: "cucumber", amount: "1")],
                steps: ["Rinse the buckwheat and simmer it in salted water for 15 minutes.",
                        "Slice the chicken, season it and fry for 6 minutes on each side.",
                        "Serve with sliced cucumber."],
                tip: "Toast the buckwheat in a dry pan first for a nuttier taste."))
        }
}
