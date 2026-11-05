import SwiftUI

struct StoreProductsView: View {

    let store: ShopStore

    @State private var cart = ShoppingCartService.shared
    @State private var searchQuery = ""
    @State private var selectedCategory: CatalogCategory? = nil
    @State private var filterTask: Task<Void, Never>?
    @State private var displayItems: [CatalogItem] = CatalogItem.all

    var body: some View {
        VStack(spacing: 0) {
            categoryStrip
            productList
            cartBar
        }
        .background(Color.surfaceGrouped.ignoresSafeArea())
        .navigationTitle(store.name)
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(false)
        .searchable(text: $searchQuery, prompt: "Search \(store.name) products…")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                NavigationLink { CartView() } label: { CartBadge(count: cart.itemCount) }
            }
        }
        .onChange(of: searchQuery)      { _, _ in scheduleFilter() }
        .onChange(of: selectedCategory) { _, _ in scheduleFilter() }
        .onAppear { scheduleFilter() }
    }

    // MARK: - Category strip

    private var categoryStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                FilterChip(label: "All", color: .brandPrimary, isSelected: selectedCategory == nil) {
                    selectedCategory = nil
                }
                ForEach(CatalogCategory.allCases) { cat in
                    FilterChip(label: cat.displayName, color: .brandPrimary, isSelected: selectedCategory == cat) {
                        selectedCategory = (selectedCategory == cat) ? nil : cat
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
        }
        .background(Color.surface)
        .overlay(Divider(), alignment: .bottom)
    }

    // MARK: - Product list

    @ViewBuilder
    private var productList: some View {
        List {
            if displayItems.isEmpty && !searchQuery.isEmpty {
                ContentUnavailableView.search(text: searchQuery)
                    .listRowBackground(Color.clear)
            } else {
                ForEach(displayItems) { item in
                    ProductShopRow(item: item, store: store)
                }
            }
        }
        .listStyle(.plain)
        .scrollDismissesKeyboard(.immediately)
    }

    // MARK: - Sticky cart bar

    @ViewBuilder
    private var cartBar: some View {
        if cart.itemCount > 0 {
            NavigationLink(destination: CartView()) {
                HStack(spacing: 14) {
                    // Item count badge
                    Text("\(cart.itemCount)")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 28, height: 28)
                        .background(Color.white.opacity(0.25), in: Circle())

                    Text("View cart")
                        .font(.headline)
                        .foregroundStyle(.white)

                    Spacer()

                    VStack(alignment: .trailing, spacing: 2) {
                        Text(String(format: "€%.2f", cart.total))
                            .font(.headline).fontWeight(.bold)
                            .foregroundStyle(.white)
                            .monospacedDigit()
                        if cart.budgetFraction > 0.01 {
                            Text("\(Int(cart.budgetFraction * 100))% of budget")
                                .font(.caption2)
                                .foregroundStyle(.white.opacity(0.75))
                        }
                    }

                    Image(systemName: "chevron.right")
                        .font(.caption).fontWeight(.semibold)
                        .foregroundStyle(.white.opacity(0.8))
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 14)
                .background(
                    Color.ink
                )
            }
            .buttonStyle(.plain)
            .transition(.move(edge: .bottom).combined(with: .opacity))
        }
    }

    // MARK: - Filtering

    private func scheduleFilter() {
        filterTask?.cancel()
        filterTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 80_000_000)
            guard !Task.isCancelled else { return }
            var base = CatalogItem.all
            if let cat = selectedCategory { base = base.filter { $0.category == cat } }
            let q = searchQuery.lowercased()
            if !q.isEmpty { base = base.filter { $0.name.lowercased().contains(q) } }
            displayItems = base
        }
    }
}

// MARK: - Filter chip

private struct FilterChip: View {
    let label: String
    let color: Color
    let isSelected: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            Text(label)
                .font(.subheadline)
                .padding(.horizontal, 14).padding(.vertical, 6)
                .frame(minHeight: 44)
                .background(isSelected ? Color.coral : Color.surfaceSecondary)
                .foregroundStyle(isSelected ? Color.onAccent : Color.labelPrimary)
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
        .animation(.spring(duration: 0.2), value: isSelected)
    }
}

// MARK: - Product row

struct ProductShopRow: View {
    let item: CatalogItem
    let store: ShopStore
    @State private var cart = ShoppingCartService.shared
    @State private var showPriceEditor = false
    @State private var priceInput = ""

    private var isEstimated: Bool  { cart.isEstimated(item.id) }
    private var price: Double      { cart.effectivePrice(for: item, store: store) }
    private var qty: Int           { cart.quantity(of: item.id, store: store.name) }

    var body: some View {
        HStack(spacing: 14) {
            // Category icon
            Circle()
                .fill(Color.brandPrimary.opacity(0.12))
                .frame(width: 40, height: 40)
                .overlay(
                    Image(systemName: item.category.symbol)
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(Color.brandPrimary)
                )

            // Name + price
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(item.name)
                        .font(.subheadline).fontWeight(.medium)
                        .lineLimit(1)
                }

                // Price row — tap to enter the real price you paid
                Button {
                    priceInput = String(format: "%.2f", price)
                    showPriceEditor = true
                } label: {
                    HStack(spacing: 5) {
                        Text(String(format: "€%.2f", price))
                            .foregroundStyle(.primary)
                        if isEstimated {
                            Text("est.")
                                .foregroundStyle(Color.brandAmber)
                        }
                    }
                    .font(.caption)
                }
                .buttonStyle(.plain)
            }

            Spacer()

            QuantityStepper(
                quantity: qty,
                onAdd:    { cart.add(item, store: store) },
                onRemove: { cart.remove(item.id, store: store.name) }
            )
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
        .listRowBackground(qty > 0 ? Color.brandPrimary.opacity(0.04) : Color.surface)
        .animation(.spring(duration: 0.2), value: qty)
        .sheet(isPresented: $showPriceEditor) { priceEditorSheet }
    }

    private var priceEditorSheet: some View {
        NavigationStack {
            Form {
                Section {
                    HStack {
                        Text("€")
                        TextField("0.00", text: $priceInput)
                            .keyboardType(.decimalPad)
                    }
                } header: {
                    Text(item.name)
                } footer: {
                    Text("Enter the real shelf price you see in \(store.name). This replaces the estimate.")
                        .font(.caption)
                }
            }
            .navigationTitle("Set Real Price")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        if let val = Double(priceInput.replacingOccurrences(of: ",", with: ".")), val > 0 {
                            cart.setRealPrice(val, for: item.id)
                        }
                        showPriceEditor = false
                    }
                }
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { showPriceEditor = false }
                }
            }
        }
        .presentationDetents([.height(260)])
    }
}

// MARK: - Quantity stepper (shared)

struct QuantityStepper: View {
    let quantity: Int
    let onAdd: () -> Void
    let onRemove: () -> Void

    var body: some View {
        if quantity == 0 {
            Button(action: onAdd) {
                Image(systemName: "plus.circle.fill")
                    .font(.system(size: 28))
                    .foregroundStyle(Color.brandPrimary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Add to cart")
            .sensoryFeedback(.impact, trigger: quantity)
        } else {
            HStack(spacing: 12) {
                Button(action: onRemove) {
                    Image(systemName: "minus.circle.fill")
                        .font(.system(size: 22))
                        .foregroundStyle(quantity == 1 ? Color.brandDanger : Color.brandPrimary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Decrease quantity")

                Text("\(quantity)")
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .frame(minWidth: 20, alignment: .center)
                    .contentTransition(.numericText())

                Button(action: onAdd) {
                    Image(systemName: "plus.circle.fill")
                        .font(.system(size: 22))
                        .foregroundStyle(Color.brandPrimary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Increase quantity")
            }
            .sensoryFeedback(.selection, trigger: quantity)
        }
    }
}

#Preview {
    NavigationStack {
        StoreProductsView(store: ShopStore.all[0])
    }
}
