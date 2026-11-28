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
        // A price correction moves the product within (or out of) the price range.
        .onChange(of: cart.priceOverrides) { _, _ in scheduleFilter() }
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

    /// Cheapest to dearest catalogue estimate, widened to the 10-cent grid.
    /// Prices the user entered don't stretch the slider: a thumb left at either
    /// end leaves that side open (nil), so an entered price outside the bounds
    /// still shows unless the user moves that thumb.
    private func computePriceBounds() -> ClosedRange<Double> {
        let prices = CatalogItem.all.map { $0.estimatedPrice(for: store) }.filter { $0.isFinite && $0 > 0 }
        guard let lo = prices.min(), let hi = prices.max() else { return 0...1 }
        let step = Self.priceStep
        let a = (lo / step).rounded(.down) * step
        let b = max((hi / step).rounded(.up) * step, a + step)
        return ((a * 100).rounded() / 100)...((b * 100).rounded() / 100)
    }

    private var isPriceFiltered: Bool { minPrice != nil || maxPrice != nil }

    private func euro(_ v: Double) -> String { Money.format(eur: v) }

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
                    Image(systemName: "tag")
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
                        Text("\(displayItems.count) of \(matchingCount) products" as String)
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
                    Label("No products in this price range", systemImage: "tag")
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
        // Floats over the list; the inset lets the last rows scroll clear of it.
        .safeAreaInset(edge: .bottom, spacing: 0) { CartToast() }
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
        .accessibilityAddTraits(isSelected ? .isSelected : [])
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
    @State private var priceError: String?
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
                    priceInput = Money.inputText(eur: price)
                    priceError = nil
                    showPriceEditor = true
                } label: {
                    HStack(spacing: 5) {
                        Text(Money.format(eur: price)).monospacedDigit()
                            .foregroundStyle(Color.labelPrimary)
                        Text(isEstimated ? "est." : "your price")
                            .foregroundStyle(isEstimated ? Color.brandAmber : Color.labelSecondary)
                    }
                    .font(.caption)
                    .frame(minHeight: 44)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Edit price for \(item.name)" as String)
                .accessibilityValue((isEstimated ? "Estimate " : "Your price ") + Money.format(eur: price))
            }

            if !dynamicTypeSize.isAccessibilitySize { Spacer() }

            QuantityStepper(
                quantity: qty,
                name: item.name,
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
                        Text(Money.symbol())
                        TextField("0.00", text: $priceInput)
                            .keyboardType(.decimalPad)
                            .accessibilityLabel("Price in \(Money.current.name)")
                            .accessibilityIdentifier("shop.priceInput")
                            .onChange(of: priceInput) { _, _ in priceError = nil }
                    }
                    if let priceError {
                        Text(priceError)
                            .font(.footnote).foregroundStyle(Color.brandDanger)
                            .accessibilityIdentifier("shop.priceError")
                    }
                } header: {
                    Text(item.name)
                } footer: {
                    Text("Enter the price you actually pay. It replaces the estimate everywhere in the app.")
                        .font(.caption)
                }
            }
            .navigationTitle("Set real price")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        // Typed in the chosen currency, kept in euros like every price.
                        let range = ShoppingCartService.priceRange
                        switch Money.validateLocal(priceInput, eurRange: range) {
                        case .success(let eur):
                            cart.setRealPrice(min(max(eur, range.lowerBound), range.upperBound), for: item.id, store: store.name)
                            showPriceEditor = false
                        case .failure(let problem):
                            priceError = Money.message(for: problem, example: Money.inputText(eur: 2.5))
                            UIAccessibility.post(notification: .announcement, argument: priceError)
                        }
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
    /// Item name, spoken by VoiceOver.
    var name: String = "item"
    let onAdd: () -> Void
    let onRemove: () -> Void

    var body: some View {
        // "Add +" that opens in place into "− n +".
        CartButton(quantity: quantity, max: Self.maxQuantity, name: name, onAdd: onAdd, onRemove: onRemove)
    }

    /// Past this the plus kicks back instead of adding.
    static let maxQuantity = 99
}

#Preview {
    NavigationStack {
        StoreProductsView(store: .catalog)
    }
}
