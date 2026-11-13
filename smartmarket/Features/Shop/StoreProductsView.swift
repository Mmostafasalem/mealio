import SwiftUI

struct StoreProductsView: View {

    let store: ShopStore

    @State private var cart = ShoppingCartService.shared
    @State private var searchQuery = ""
    @State private var selectedCategory: CatalogCategory? = nil
    @State private var filterTask: Task<Void, Never>?
    @State private var displayItems: [CatalogItem] = CatalogItem.all
    /// Items that match category + search, before the price filter (for "12 of 40 products").
    @State private var matchingCount = CatalogItem.all.count
    @State private var showPriceFilter = false
    /// `nil` = no limit on that side.
    @State private var minPrice: Double?
    @State private var maxPrice: Double?
    @State private var priceBounds: ClosedRange<Double> = 0...1
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Slider step: ten cents.
    private static let priceStep = 0.1

    var body: some View {
        VStack(spacing: 0) {
            categoryStrip
            priceFilter
            productList
            cartBar
        }
        .background(Color.surfaceGrouped.ignoresSafeArea())
        .navigationTitle("Catalogue")
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(false)
        .searchable(text: $searchQuery, prompt: "Search products…")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                NavigationLink { CartView() } label: { CartBadge(count: cart.itemCount) }
            }
        }
        .onChange(of: searchQuery)      { _, _ in scheduleFilter() }
        .onChange(of: selectedCategory) { _, _ in scheduleFilter() }
        .onChange(of: minPrice)         { _, _ in scheduleFilter() }
        .onChange(of: maxPrice)         { _, _ in scheduleFilter() }
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

    // MARK: - Price filter

    /// Cheapest to dearest product in the catalogue, widened to the 10-cent grid.
    private func computePriceBounds() -> ClosedRange<Double> {
        let prices = CatalogItem.all.map { cart.effectivePrice(for: $0, store: store) }.filter { $0.isFinite && $0 > 0 }
        guard let lo = prices.min(), let hi = prices.max() else { return 0...1 }
        let step = Self.priceStep
        let a = (lo / step).rounded(.down) * step
        let b = max((hi / step).rounded(.up) * step, a + step)
        return ((a * 100).rounded() / 100)...((b * 100).rounded() / 100)
    }

    private var isPriceFiltered: Bool { minPrice != nil || maxPrice != nil }

    private func euro(_ v: Double) -> String { String(format: "€%.2f", v) }

    private var priceSummary: String {
        let b = priceBounds
        guard isPriceFiltered else { return "Any price" }
        return euro(max(minPrice ?? b.lowerBound, b.lowerBound)) + "–" + euro(min(maxPrice ?? b.upperBound, b.upperBound))
    }

    private var priceFilter: some View {
        let b = priceBounds
        let low = Binding<Double>(
            get: { motionClamp(minPrice ?? b.lowerBound, b.lowerBound, b.upperBound) },
            set: { minPrice = $0 <= b.lowerBound + 0.001 ? nil : $0 }
        )
        let high = Binding<Double>(
            get: { motionClamp(maxPrice ?? b.upperBound, b.lowerBound, b.upperBound) },
            set: { maxPrice = $0 >= b.upperBound - 0.001 ? nil : $0 }
        )
        return VStack(alignment: .leading, spacing: 0) {
            Button {
                showPriceFilter.toggle()
            } label: {
                HStack(spacing: Spacing.sm) {
                    Image(systemName: "eurosign.circle")
                        .foregroundStyle(Color.labelSecondary)
                    Text("Price")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(Color.labelPrimary)
                    Spacer(minLength: Spacing.sm)
                    Text(priceSummary)
                        .font(.subheadline)
                        .monospacedDigit()
                        .foregroundStyle(isPriceFiltered ? Color.labelPrimary : Color.labelSecondary)
                    Image(systemName: "chevron.down")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Color.labelTertiary)
                        .rotationEffect(.degrees(showPriceFilter ? 180 : 0))
                }
                .frame(minHeight: 44)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Price filter")
            .accessibilityValue(priceSummary)
            .accessibilityHint(showPriceFilter ? "Hides the price range" : "Shows a price range for catalogue products")
            .accessibilityAddTraits(showPriceFilter ? .isSelected : [])
            .accessibilityIdentifier("shop.priceFilter")

            if showPriceFilter {
                VStack(alignment: .leading, spacing: Spacing.sm) {
                    RangeSlider(lower: low, upper: high, in: b, step: Self.priceStep,
                                lowerLabel: "Minimum price", upperLabel: "Maximum price", format: euro)
                        .padding(.horizontal, Spacing.xs)
                    HStack {
                        Text("\(displayItems.count) of \(matchingCount) products")
                            .font(.caption)
                            .monospacedDigit()
                            .foregroundStyle(Color.labelSecondary)
                            .accessibilityIdentifier("shop.priceFilterCount")
                        Spacer()
                        if isPriceFiltered {
                            Button("Clear filter") { minPrice = nil; maxPrice = nil }
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(Color.brandPrimary)
                                .frame(minHeight: 44)
                                .accessibilityIdentifier("shop.priceFilterClear")
                        }
                    }
                    .frame(minHeight: 44)
                }
                .transition(.opacity)
            }
        }
        .padding(.horizontal, 16)
        .background(Color.surface)
        .overlay(Divider(), alignment: .bottom)
        .animation(reduceMotion ? .none : .snappyValue, value: showPriceFilter)
        .animation(reduceMotion ? .none : .snappyValue, value: isPriceFiltered)
    }

    // MARK: - Product list

    @ViewBuilder
    private var productList: some View {
        List {
            if displayItems.isEmpty && !searchQuery.isEmpty {
                ContentUnavailableView.search(text: searchQuery)
                    .listRowBackground(Color.clear)
            } else if displayItems.isEmpty && isPriceFiltered {
                ContentUnavailableView {
                    Label("No products in this price range", systemImage: "eurosign.circle")
                } description: {
                    Text("Widen the range or clear the price filter.")
                } actions: {
                    Button("Clear filter") { minPrice = nil; maxPrice = nil }
                }
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
            let bounds = computePriceBounds()
            if bounds != priceBounds { priceBounds = bounds }
            var base = CatalogItem.all
            if let cat = selectedCategory { base = base.filter { $0.category == cat } }
            let q = searchQuery.lowercased()
            if !q.isEmpty { base = base.filter { $0.name.lowercased().contains(q) } }
            matchingCount = base.count
            if minPrice != nil || maxPrice != nil {
                let lo = minPrice ?? -.infinity, hi = maxPrice ?? .infinity
                // a cent of slack so a €2.40 limit keeps a €2.40 product
                base = base.filter {
                    let p = cart.effectivePrice(for: $0, store: store)
                    return p >= lo - 0.005 && p <= hi + 0.005
                }
            }
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
                    Text("Enter the price you actually pay. It replaces the estimate everywhere in the app.")
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
        StoreProductsView(store: .catalog)
    }
}
