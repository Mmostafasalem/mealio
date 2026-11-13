import SwiftUI

struct StoreBrowserView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var cart = ShoppingCartService.shared
    @State private var showBudgetEditor = false
    @State private var budgetInput = ""
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(spacing: Spacing.xl) {
                    NavigationLink { RetailerProductsView(retailer: "") } label: {
                        Label("Find reported retailer products", systemImage: "magnifyingglass")
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(Spacing.lg).premiumCard()
                    }
                    .accessibilityIdentifier("shop.retailerProducts")
                    budgetCard
                    storeGrid
                    if cart.itemCount > 0 { cartPreview }
                }
                .padding(.horizontal, Spacing.lg)
                .padding(.top, Spacing.sm)
                .padding(.bottom, Spacing.xxl)
                .animation(.snappyValue, value: cart.itemCount)
            }
            .background { GrainyGradient().ignoresSafeArea() }
            .navigationTitle("Shop")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    NavigationLink {
                        CartView()
                    } label: {
                        CartBadge(count: cart.itemCount)
                    }
                }
            }
        }
        .sheet(isPresented: $showBudgetEditor) { budgetSheet }
    }

    // MARK: - Budget card

    private var budgetCard: some View {
        VStack(spacing: 14) {
            let headerLayout = dynamicTypeSize.isAccessibilitySize
                ? AnyLayout(VStackLayout(alignment: .leading, spacing: Spacing.md))
                : AnyLayout(HStackLayout())
            headerLayout {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Weekly Budget")
                        .font(.subheadline).fontWeight(.semibold)
                        .foregroundStyle(Color.labelSecondary)
                    let amountsLayout = dynamicTypeSize.isAccessibilitySize
                        ? AnyLayout(VStackLayout(alignment: .leading, spacing: 4))
                        : AnyLayout(HStackLayout(alignment: .firstTextBaseline, spacing: 4))
                    amountsLayout {
                        Text(String(format: "€%.2f", cart.total))
                            .font(.system(.title, design: .rounded).bold())
                            .foregroundStyle(cart.budgetColor)
                            .monospacedDigit()
                            .lineLimit(1)
                            .minimumScaleFactor(0.5)
                            .contentTransition(.numericText())
                        Text("/ \(String(format: "€%.0f", cart.weeklyBudget))")
                            .font(.subheadline).foregroundStyle(Color.labelSecondary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.5)
                    }
                }
                if !dynamicTypeSize.isAccessibilitySize { Spacer() }
                Button {
                    budgetInput = String(format: "%.0f", cart.weeklyBudget)
                    showBudgetEditor = true
                } label: {
                    Label("Edit", systemImage: "slider.horizontal.3")
                        .fixedSize(horizontal: true, vertical: false)
                        .font(.caption).fontWeight(.semibold)
                        .padding(.horizontal, 12).padding(.vertical, 7)
                        .background(Color.brandLight, in: Capsule())
                        .foregroundStyle(Color.brandPrimary)
                }
            }

            // Progress bar
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color(.systemFill)).frame(height: 8)
                    Capsule()
                        .fill(Color.dullPink)
                        .frame(width: geo.size.width * cart.budgetFraction, height: 8)
                        .animation(reduceMotion ? .none : .snappyValue, value: cart.budgetFraction)
                }
            }
            .frame(height: 8)

            HStack {
                Spacer()
                Text("\(String(format: "€%.2f", max(cart.budgetRemaining, 0))) left")
                    .font(.caption).foregroundStyle(Color.labelSecondary)
            }
        }
        .padding(Spacing.lg)
        .premiumCard()
    }

    // MARK: - Store grid

    private var storeGrid: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Grocery budget catalog")
                .font(.headline)

            Text("\(CatalogItem.all.count) catalog items · estimated prices, verify in-store")
                .font(.footnote)
                .foregroundStyle(Color.labelSecondary)
                .fixedSize(horizontal: false, vertical: true)
            LazyVStack(spacing: Spacing.sm) {
                ForEach(ShopStore.all) { store in
                    NavigationLink {
                        StoreProductsView(store: store)
                    } label: {
                        StoreCard(store: store)
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("shop.store." + store.id)
                }
            }
        }
    }

    // MARK: - Cart preview

    private var cartPreview: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("In Cart")
                    .font(.headline)
                Spacer()
                NavigationLink("View all", destination: CartView())
                    .font(.subheadline).foregroundStyle(Color.brandPrimary)
            }

            ForEach(cart.cartItems.prefix(3)) { item in
                HStack(spacing: 12) {
                    Circle()
                        .fill(Color.labelPrimary.opacity(0.12))
                        .frame(width: 36, height: 36)
                        .overlay(
                            Text(item.store.prefix(1))
                                .font(.system(size: 14, weight: .bold))
                                .foregroundStyle(Color.labelPrimary)
                        )
                    VStack(alignment: .leading, spacing: 2) {
                        Text(item.name).font(.subheadline).fontWeight(.medium).lineLimit(1)
                        Text(item.store).font(.caption2).foregroundStyle(Color.labelSecondary)
                    }
                    Spacer()
                    Text("×\(item.quantity)")
                        .font(.caption).foregroundStyle(Color.labelSecondary)
                    Text(String(format: "€%.2f", item.lineTotal))
                        .font(.subheadline).fontWeight(.semibold).monospacedDigit()
                }
            }

            if cart.cartItems.count > 3 {
                Text("+ \(cart.cartItems.count - 3) more items")
                    .font(.caption).foregroundStyle(Color.labelSecondary)
            }
        }
        .padding(16)
        .premiumCard()
    }

    // MARK: - Budget sheet

    /// The slider and the text field share `budgetInput`: dragging rewrites the text,
    /// a valid typed amount glides the slider there (clamped to its 10…300 range).
    private var budgetSliderValue: Binding<Double> {
        Binding(
            get: {
                let typed = Double(budgetInput.replacingOccurrences(of: ",", with: "."))
                return min(max(typed ?? cart.weeklyBudget, 10), 300)
            },
            set: { budgetInput = String(format: "%.0f", $0) }
        )
    }

    private var budgetSheet: some View {
        NavigationStack {
            Form {
                Section("Weekly grocery budget") {
                    JellySlider(value: budgetSliderValue, in: 10...300, step: 5,
                                format: { "€\(Int($0))" }, tickLabels: [10, 50, 100, 200, 300])
                        .accessibilityLabel("Weekly budget")
                        .padding(.vertical, Spacing.xs)
                    HStack {
                        Text("€")
                        TextField("60", text: $budgetInput)
                            .keyboardType(.decimalPad)
                    }
                }
                Section {
                    Text("We'll warn you as you approach your limit while shopping.")
                        .font(.caption).foregroundStyle(Color.labelSecondary)
                }
            }
            .navigationTitle("Set Budget")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        if let val = Double(budgetInput.replacingOccurrences(of: ",", with: ".")), val > 0 {
                            cart.weeklyBudget = val
                        }
                        showBudgetEditor = false
                    }
                }
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { showBudgetEditor = false }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }
}

// MARK: - Store card

private struct StoreCard: View {
    let store: ShopStore
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        HStack(spacing: Spacing.md) {
            Text(store.name.prefix(1))
                .font(.title3.weight(.bold))
                .foregroundStyle(Color.almond)
                .frame(width: 44, height: 44)
                .background(Color.rhino, in: RoundedRectangle(cornerRadius: Radius.chip))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: Spacing.xs) {
                Text(store.name).font(.headline)
                Text("Browse catalog")
                    .font(.footnote).foregroundStyle(Color.labelSecondary)
            }
            Spacer(minLength: Spacing.sm)
            Image(systemName: "chevron.right")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(Color.labelSecondary)
        }
        .padding(Spacing.lg)
        .frame(maxWidth: .infinity, alignment: .leading)
        .premiumCard(radius: Radius.tile)
        .contentShape(Rectangle())
    }
}

// MARK: - Cart badge

struct CartBadge: View {
    let count: Int
    var body: some View {
        ZStack(alignment: .topTrailing) {
            Image(systemName: "cart.fill")
                .font(.system(size: 18))
                .foregroundStyle(Color.brandPrimary)
            if count > 0 {
                Text("\(min(count, 99))")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(Color.onAccent)
                    .padding(3)
                    .background(Color.dullPink, in: Circle())
                    .offset(x: 8, y: -8)
            }
        }
        .frame(width: 32, height: 32)
    }
}

// MARK: - Cart view (full list)

struct CartView: View {
    @State private var cart = ShoppingCartService.shared
    @State private var undo = GroceryListViewModel()
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        List {
            if cart.cartItems.isEmpty {
                ContentUnavailableView(
                    "Your cart is empty",
                    systemImage: "cart",
                    description: Text("Browse stores and add items to get started.")
                )
                .listRowBackground(Color.clear)
            } else {
                ForEach(GroupedStore.group(cart.cartItems), id: \.store) { group in
                    Section(group.store) {
                        ForEach(group.items, content: CartItemRow.init)
                    }
                }

                Section {
                    VStack(spacing: 10) {
                        HStack {
                            Text("Subtotal")
                            Spacer()
                            Text(String(format: "€%.2f", cart.total)).fontWeight(.semibold).monospacedDigit()
                        }
                        HStack {
                            Text("Budget remaining")
                            Spacer()
                            Text(String(format: "€%.2f", max(cart.budgetRemaining, 0)))
                                .foregroundStyle(cart.budgetColor).monospacedDigit()
                        }
                    }
                    .font(.subheadline)
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("My Cart")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if !cart.cartItems.isEmpty {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Clear", role: .destructive) { undo.clearCart() }
                        .accessibilityIdentifier("cart.clear")
                }
            }
        }
        .safeAreaInset(edge: .bottom) {
            if let message = undo.undoMessage {
                UndoToast(message: message) { undo.undoDelete() }
                    .padding(.vertical, Spacing.sm)
                    .transition(reduceMotion ? .opacity : .move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(reduceMotion ? .none : .snappyValue, value: undo.undoMessage)

    }
}

private struct CartItemRow: View {
    let item: CartItem
    @State private var cart = ShoppingCartService.shared

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(item.name).font(.subheadline).fontWeight(.medium)
                Text(String(format: cart.isEstimated(item.catalogId, store: item.store) ? "est. €%.2f" : "your price €%.2f", item.price)).font(.caption).foregroundStyle(Color.labelSecondary)
            }
            Spacer()
            QuantityStepper(quantity: item.quantity,
                            onAdd:    { cart.add(CatalogItem(id: item.catalogId, name: item.name, category: CatalogCategory(rawValue: item.category) ?? .snacks),
                                                 store: ShopStore.all.first { $0.name == item.store } ?? ShopStore.all[0]) },
                            onRemove: { cart.remove(item.catalogId, store: item.store) })
            Text(String(format: "€%.2f", item.lineTotal))
                .font(.subheadline).fontWeight(.semibold).monospacedDigit()
                .frame(width: 52, alignment: .trailing)
        }
    }
}

private struct GroupedStore {
    let store: String
    let items: [CartItem]

    static func group(_ items: [CartItem]) -> [GroupedStore] {
        let stores = items.map(\.store).removingDuplicates()
        return stores.map { s in GroupedStore(store: s, items: items.filter { $0.store == s }) }
    }
}

private extension Array where Element: Equatable {
    func removingDuplicates() -> [Element] {
        reduce([]) { $0.contains($1) ? $0 : $0 + [$1] }
    }
}

#Preview { StoreBrowserView() }
