import SwiftUI

struct StoreProductsView: View {

    let store: ShopStore

    @State private var cart = ShoppingCartService.shared
    @State private var searchQuery = ""
    @State private var selectedCategory: CatalogCategory? = nil
    @State private var filterTask: Task<Void, Never>?
    @State private var displayItems: [CatalogItem] = CatalogItem.all
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

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

    private var cartBar: some View {
        // Own container so the implicit animation scopes to the bar's insert/remove only.
        VStack(spacing: 0) {
            if cart.itemCount > 0 {
                cartBarContent
            }
        }
        .animation(reduceMotion ? .none : .snappyValue, value: cart.itemCount > 0)
    }

    private var cartBarContent: some View {
        Group {
            NavigationLink(destination: CartView()) {
                HStack(spacing: 14) {
                    // Item count badge
                    Text("\(cart.itemCount)")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(Color.almond)
                        .frame(width: 28, height: 28)
                        .background(Color.white.opacity(0.25), in: Circle())

                    Text("View cart")
                        .font(.headline)
                        .foregroundStyle(Color.almond)

                    Spacer()

                    VStack(alignment: .trailing, spacing: 2) {
                        Text(String(format: "€%.2f", cart.total))
                            .font(.headline).fontWeight(.bold)
                            .foregroundStyle(Color.almond)
                            .monospacedDigit()
                        if cart.budgetFraction > 0.01 {
                            Text("\(Int(cart.budgetFraction * 100))% of budget")
                                .font(.caption2)
                                .foregroundStyle(Color.almond.opacity(0.75))
                        }
                    }

                    Image(systemName: "chevron.right")
                        .font(.caption).fontWeight(.semibold)
                        .foregroundStyle(Color.almond.opacity(0.8))
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 14)
                .background(
                    Color.rhino
                )
            }
            .buttonStyle(.plain)
        }
        .transition(reduceMotion ? .opacity : .move(edge: .bottom).combined(with: .opacity))
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
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
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
                .background(isSelected ? Color.dullPink : Color.surfaceSecondary)
                .foregroundStyle(isSelected ? Color.onAccent : Color.labelPrimary)
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
        .animation(reduceMotion ? .none : .snappyValue, value: isSelected)
    }
}

// MARK: - Product row

struct ProductShopRow: View {
    let item: CatalogItem
    let store: ShopStore
    @State private var cart = ShoppingCartService.shared
    @State private var showPriceEditor = false
    @State private var priceInput = ""
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var isEstimated: Bool  { cart.isEstimated(item.id, store: store.name) }
    private var price: Double      { cart.effectivePrice(for: item, store: store) }
    private var qty: Int           { cart.quantity(of: item.id, store: store.name) }

    var body: some View {
        let rowLayout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: Spacing.md))
            : AnyLayout(HStackLayout(spacing: Spacing.md))
        rowLayout {
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
                        .fixedSize(horizontal: false, vertical: true)
                }

                // Price row — tap to enter the real price you paid
                Button {
                    priceInput = String(format: "%.2f", price)
                    showPriceEditor = true
                } label: {
                    HStack(spacing: 5) {
                        Text(String(format: "€%.2f", price)).monospacedDigit()
                            .foregroundStyle(Color.labelPrimary)
                        Text(isEstimated ? "est." : "your price")
                            .foregroundStyle(isEstimated ? Color.brandAmber : Color.labelSecondary)
                    }
                    .font(.caption)
                    .frame(minHeight: 44)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Edit price for \(item.name)")
                .accessibilityValue((isEstimated ? "Estimate " : "Your price ") + String(format: "€%.2f", price))
            }

            if !dynamicTypeSize.isAccessibilitySize { Spacer() }

            QuantityStepper(
                quantity: qty,
                onAdd:    { cart.add(item, store: store) },
                onRemove: { cart.remove(item.id, store: store.name) }
            )
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
        .listRowBackground(qty > 0 ? Color.brandPrimary.opacity(0.04) : Color.surface)
        .animation(reduceMotion ? .none : .snappyValue, value: qty)
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
                    Text("Enter the real shelf price you see in \(store.name). This replaces the estimate for this store only. Older corrections can be re-entered here for this store.")
                        .font(.caption)
                }
            }
            .navigationTitle("Set Real Price")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        if let val = Double(priceInput.replacingOccurrences(of: ",", with: ".")), val.isFinite, val > 0 {
                            cart.setRealPrice(val, for: item.id, store: store.name)
                        }
                        showPriceEditor = false
                    }
                    .keyboardShortcut("s", modifiers: .command)
                    .help("Save (⌘S)")
                }
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { showPriceEditor = false }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
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
                    .minTapTarget()
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Add to cart")
            .sensoryFeedback(.impact, trigger: quantity)
        } else {
            // Spring roll on change; stepping down from 1 removes the line (the
            // view then swaps back to "Add to cart").
            SpringStepper(
                value: Binding(
                    get: { quantity },
                    set: { new in
                        if new > quantity { onAdd() } else if new < quantity { onRemove() }
                    }
                ),
                in: 0...Self.maxQuantity,
                label: "Quantity",
                decrementLabel: "Decrease quantity",
                incrementLabel: "Increase quantity",
                font: .system(.callout, design: .rounded).weight(.bold)
            )
        }
    }

    /// Past this the plus kicks back instead of adding.
    static let maxQuantity = 99
}

#Preview {
    NavigationStack {
        StoreProductsView(store: ShopStore.all[0])
    }
}
