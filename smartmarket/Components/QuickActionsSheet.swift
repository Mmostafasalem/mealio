import SwiftUI

enum MealioQuickAction: String, CaseIterable, Identifiable {
    case home, meals, shop, map, profile, logFood, cart, groceries
    var id: String { rawValue }
    var title: String {
        switch self {
        case .home: return "Home"
        case .meals: return "Meal plan"
        case .shop: return "Browse groceries"
        case .map: return "Nearby stores"
        case .profile: return "Profile and settings"
        case .logFood: return "Log food"
        case .cart: return "View cart"
        case .groceries: return "Grocery checklist"
        }
    }
    var symbol: String {
        switch self {
        case .home: return "house"
        case .meals: return "fork.knife"
        case .shop: return "storefront"
        case .map: return "map"
        case .profile: return "person.crop.circle"
        case .logFood: return "plus.circle"
        case .cart: return "cart"
        case .groceries: return "checklist"
        }
    }
    var tab: Int? {
        switch self {
        case .home: return 0
        case .meals: return 1
        case .shop: return 2
        case .map: return 3
        case .profile: return 4
        default: return nil
        }
    }
    var shortcut: Character {
        switch self {
        case .home: return "1"
        case .meals: return "2"
        case .shop: return "3"
        case .map: return "4"
        case .profile: return "5"
        case .logFood: return "l"
        case .cart: return "b"
        case .groceries: return "g"
        }
    }
    static func matching(_ query: String) -> [Self] {
        let query = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return allCases }
        return allCases.filter { ($0.title + " " + $0.rawValue).localizedStandardContains(query) }
    }
}

struct ShortcutHint: View {
    let text: String
    var body: some View {
        Text(text)
            .font(.caption.monospaced())
            .foregroundStyle(Color.labelSecondary)
            .padding(.horizontal, Spacing.sm).padding(.vertical, Spacing.xs)
            .background(Color.surfaceSecondary, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
            .accessibilityHidden(true)
    }
}

/// Searches local destinations/actions only; opening the menu never calls AI.
struct QuickActionsSheet: View {
    let select: (MealioQuickAction) -> Void
    @State private var query = ""
    @FocusState private var searchFocused: Bool
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack(spacing: Spacing.sm) {
                        Image(systemName: "magnifyingglass").foregroundStyle(Color.labelSecondary)
                        TextField("Find a screen or action", text: $query)
                            .focused($searchFocused)
                            .autocorrectionDisabled()
                            .textInputAutocapitalization(.never)
                            .accessibilityIdentifier("quickActions.search")
                            .submitLabel(.go)
                            .onSubmit {
                                if let first = MealioQuickAction.matching(query).first { select(first) }
                            }
                    }
                    .frame(minHeight: 44)
                    .listRowBackground(Color.surface)
                }
                let matches = MealioQuickAction.matching(query)
                if matches.isEmpty {
                    ContentUnavailableView.search(text: query)
                } else {
                    Section("Screens and actions") {
                        ForEach(matches) { action in
                            Button { select(action) } label: {
                                HStack(spacing: Spacing.md) {
                                    Image(systemName: action.symbol)
                                        .frame(width: 24).foregroundStyle(Color.brandPrimary)
                                    Text(action.title).foregroundStyle(Color.labelPrimary)
                                    Spacer(minLength: Spacing.sm)
                                    ShortcutHint(text: "⌘" + String(action.shortcut).uppercased())
                                }
                                .frame(minHeight: 44)
                            }
                            .listRowBackground(Color.surface)
                            .keyboardShortcut(KeyEquivalent(action.shortcut), modifiers: .command)
                            .accessibilityIdentifier("quickActions." + action.rawValue)
                        }
                    }
                }
                Section {
                    Text("Use ⌘K to open Quick Actions with a keyboard. These shortcuts work without online AI.")
                        .font(.footnote).foregroundStyle(Color.labelSecondary)
                }
            }
            .scrollContentBackground(.hidden)
            .background(Color.surfaceGrouped)
            .navigationTitle("Quick Actions")
            .navigationBarTitleDisplayMode(.inline)
            .scrollDismissesKeyboard(.interactively)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                        .keyboardShortcut(.escape, modifiers: [])
                        .accessibilityIdentifier("quickActions.close")
                }
            }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .presentationCornerRadius(Radius.sheet)
        .task { searchFocused = true }
    }
}
