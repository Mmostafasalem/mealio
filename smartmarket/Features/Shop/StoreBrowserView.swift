import SwiftUI

struct StoreBrowserView: View {

    @State private var cart = ShoppingCartService.shared
    @State private var showBudgetEditor = false
    @State private var budgetInput = ""

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(spacing: 20) {
                    budgetCard
                    storeGrid
                    if cart.itemCount > 0 { cartPreview }
                }
                .padding(.horizontal, 20)
                .padding(.top, 8)
                .padding(.bottom, 32)
            }
            .background(Color.surfaceGrouped.ignoresSafeArea())
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
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Weekly Budget")
                        .font(.subheadline).fontWeight(.semibold)
                        .foregroundStyle(.secondary)
                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        Text(String(format: "€%.2f", cart.total))
                            .font(.system(size: 28, weight: .bold, design: .rounded))
                            .foregroundStyle(cart.budgetColor)
                            .monospacedDigit()
                            .contentTransition(.numericText())
                        Text("/ \(String(format: "€%.0f", cart.weeklyBudget))")
                            .font(.subheadline).foregroundStyle(.secondary)
                    }
                }
                Spacer()
                Button {
                    budgetInput = String(format: "%.0f", cart.weeklyBudget)
                    showBudgetEditor = true
                } label: {
                    Label("Edit", systemImage: "slider.horizontal.3")
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
                        .fill(LinearGradient(
                            colors: [cart.budgetColor, cart.budgetColor.opacity(0.7)],
                            startPoint: .leading, endPoint: .trailing
                        ))
                        .frame(width: geo.size.width * cart.budgetFraction, height: 8)
                        .animation(.spring(duration: 0.5), value: cart.budgetFraction)
                }
            }
            .frame(height: 8)

            if cart.totalSavings > 0 {
                HStack {
                    Image(systemName: "tag.fill").font(.caption2).foregroundStyle(Color.brandAmber)
                    Text("Saving \(String(format: "€%.2f", cart.totalSavings)) on sales")
                        .font(.caption).foregroundStyle(Color.brandAmber)
                    Spacer()
                    Text("\(String(format: "€%.2f", max(cart.budgetRemaining, 0))) left")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
        }
        .padding(18)
        .premiumCard()
    }

    // MARK: - Store grid

    private var storeGrid: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Stores")
                .font(.headline)

            LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
                ForEach(ShopStore.all) { store in
                    NavigationLink {
                        StoreProductsView(store: store)
                    } label: {
                        StoreCard(store: store)
                    }
                    .buttonStyle(.plain)
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
                        .fill(Color(hex: ShopStore.all.first { $0.name == item.store }?.colorHex ?? "#6B7280").opacity(0.12))
                        .frame(width: 36, height: 36)
                        .overlay(
                            Text(item.store.prefix(1))
                                .font(.system(size: 14, weight: .bold))
                                .foregroundStyle(Color(hex: ShopStore.all.first { $0.name == item.store }?.colorHex ?? "#6B7280"))
                        )
                    VStack(alignment: .leading, spacing: 2) {
                        Text(item.name).font(.subheadline).fontWeight(.medium).lineLimit(1)
                        Text(item.store).font(.caption2).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text("×\(item.quantity)")
                        .font(.caption).foregroundStyle(.secondary)
                    Text(String(format: "€%.2f", item.lineTotal))
                        .font(.subheadline).fontWeight(.semibold).monospacedDigit()
                }
            }

            if cart.cartItems.count > 3 {
                Text("+ \(cart.cartItems.count - 3) more items")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding(16)
        .premiumCard()
    }

    // MARK: - Budget sheet

    private var budgetSheet: some View {
        NavigationStack {
            Form {
                Section("Weekly grocery budget") {
                    HStack {
                        Text("€")
                        TextField("60", text: $budgetInput)
                            .keyboardType(.decimalPad)
                    }
                }
                Section {
                    Text("We'll warn you as you approach your limit while shopping.")
                        .font(.caption).foregroundStyle(.secondary)
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
        .presentationDetents([.medium])
    }
}

// MARK: - Store card

private struct StoreCard: View {
    let store: ShopStore

    private var dealCount: Int {
        CatalogItem.all.filter { $0.isOnSale(for: store) }.count
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Colored header
            ZStack(alignment: .bottomLeading) {
                RoundedRectangle(cornerRadius: 0)
                    .fill(LinearGradient(
                        colors: [store.color, store.color.opacity(0.75)],
                        startPoint: .topLeading, endPoint: .bottomTrailing
                    ))
                    .frame(height: 80)

                VStack(alignment: .leading, spacing: 2) {
                    Text(store.name)
                        .font(.title3).fontWeight(.bold)
                        .foregroundStyle(.white)
                    Text("\(dealCount) on sale")
                        .font(.caption2)
                        .foregroundStyle(.white.opacity(0.75))
                }
                .padding(12)
            }

            // Tagline + arrow
            HStack {
                Text(store.tagline)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption2)
                    .foregroundStyle(Color(.tertiaryLabel))
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
        }
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .shadow(color: store.color.opacity(0.18), radius: 8, x: 0, y: 4)
        .shadow(color: .black.opacity(0.06), radius: 16, x: 0, y: 8)
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .strokeBorder(store.color.opacity(0.15), lineWidth: 1)
        )
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
                    .foregroundStyle(.white)
                    .padding(3)
                    .background(Color.brandDanger, in: Circle())
                    .offset(x: 8, y: -8)
            }
        }
        .frame(width: 32, height: 32)
    }
}

// MARK: - Cart view (full list)

struct CartView: View {
    @State private var cart = ShoppingCartService.shared
    @State private var showClearAlert = false

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
                        ForEach(group.items) { item in
                            CartItemRow(item: item)
                        }
                    }
                }

                Section {
                    VStack(spacing: 10) {
                        HStack {
                            Text("Subtotal")
                            Spacer()
                            Text(String(format: "€%.2f", cart.total)).fontWeight(.semibold).monospacedDigit()
                        }
                        if cart.totalSavings > 0 {
                            HStack {
                                Text("You save").foregroundStyle(Color.brandAmber)
                                Spacer()
                                Text(String(format: "-€%.2f", cart.totalSavings)).foregroundStyle(Color.brandAmber).monospacedDigit()
                            }
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
                    Button("Clear", role: .destructive) { showClearAlert = true }
                }
            }
        }
        .alert("Clear cart?", isPresented: $showClearAlert) {
            Button("Clear", role: .destructive) { cart.clear() }
            Button("Cancel", role: .cancel) {}
        }
    }
}

private struct CartItemRow: View {
    let item: CartItem
    @State private var cart = ShoppingCartService.shared

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(item.name).font(.subheadline).fontWeight(.medium)
                if item.isOnSale {
                    HStack(spacing: 4) {
                        Text(String(format: "€%.2f", item.price)).font(.caption).foregroundStyle(Color.brandPrimary)
                        Text(String(format: "€%.2f", item.originalPrice)).font(.caption).strikethrough().foregroundStyle(.tertiary)
                    }
                } else {
                    Text(String(format: "€%.2f", item.price)).font(.caption).foregroundStyle(.secondary)
                }
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
