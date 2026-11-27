import SwiftUI
import TipKit

struct StoreBrowserView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var cart = ShoppingCartService.shared
    @State private var showBudgetEditor = false
    @State private var budgetInput = ""
    @State private var budgetError: String?
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    private let budgetTip = WeeklyBudgetTip()

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(spacing: Spacing.xl) {
                    budgetCard
                    // Inline under the card, so it never covers the Edit button.
                    TipView(budgetTip, arrowEdge: .top)
                    // Right under the budget: what these prices are and which currency.
                    aboutPrices
                    WeeklyGroceryCard()
                    storeGrid
                    if cart.itemCount > 0 { cartPreview }
                }
                .padding(.horizontal, Spacing.lg)
                .padding(.top, Spacing.sm)
                .padding(.bottom, Spacing.xxl)
                .animation(reduceMotion ? nil : .snappyValue, value: cart.itemCount)
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
        .task(id: cart.weeklyBudget) {
            WeeklyBudgetTip.hasCustomBudget = cart.weeklyBudget != 60  // ShoppingCartService's default budget
        }
    }

    // MARK: - Budget card

    private var budgetCard: some View {
        VStack(spacing: 14) {
            let headerLayout = dynamicTypeSize.isAccessibilitySize
                ? AnyLayout(VStackLayout(alignment: .leading, spacing: Spacing.md))
                : AnyLayout(HStackLayout())
            headerLayout {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Weekly budget")
                        .font(.subheadline).fontWeight(.semibold)
                        .foregroundStyle(Color.labelSecondary)
                    let amountsLayout = dynamicTypeSize.isAccessibilitySize
                        ? AnyLayout(VStackLayout(alignment: .leading, spacing: 4))
                        : AnyLayout(HStackLayout(alignment: .firstTextBaseline, spacing: 4))
                    amountsLayout {
                        Text(Money.format(eur: cart.total))
                            .font(.system(.title, design: .rounded).bold())
                            .foregroundStyle(cart.budgetColor)
                            .monospacedDigit()
                            .lineLimit(1)
                            .minimumScaleFactor(0.5)
                            .contentTransition(.numericText())
                        Text("/ \(Money.format(eur: cart.weeklyBudget))")
                            .font(.subheadline).foregroundStyle(Color.labelSecondary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.5)
                    }
                }
                if !dynamicTypeSize.isAccessibilitySize { Spacer() }
                Button {
                    budgetInput = Money.inputText(eur: cart.weeklyBudget)
                    budgetError = nil
                    showBudgetEditor = true
                } label: {
                    Label("Edit", systemImage: "slider.horizontal.3")
                        .fixedSize(horizontal: true, vertical: false)
                        .font(.caption).fontWeight(.semibold)
                        .padding(.horizontal, 12).padding(.vertical, 7)
                        .background(Color.brandLight, in: Capsule())
                        .foregroundStyle(Color.brandPrimary)
                        // The pill stays small; the tap area is 44 pt.
                        .frame(minWidth: 44, minHeight: 44)
                        .contentShape(Rectangle())
                }
                .accessibilityLabel("Edit weekly budget")
                .accessibilityIdentifier("shop.editBudget")
            }

            // Progress bar
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color(.systemFill)).frame(height: 8)
                    Capsule()
                        // Red from 90% of the budget, as the budget sheet says.
                        .fill(cart.budgetFraction >= 0.9 ? Color.brandDanger : Color.dullPink)
                        .frame(width: geo.size.width * cart.budgetFraction, height: 8)
                        .animation(reduceMotion ? .none : .snappyValue, value: cart.budgetFraction)
                }
            }
            .frame(height: 8)
            .accessibilityElement()
            .accessibilityLabel("Weekly budget")
            .accessibilityValue(Money.spoken(eur: cart.total) + " of " + Money.spoken(eur: cart.weeklyBudget) + " spent")

            HStack {
                Spacer()
                Text(cart.budgetRemaining < 0 ? "\(Money.format(eur: -cart.budgetRemaining)) over" : "\(Money.format(eur: cart.budgetRemaining)) left")
                    .font(.caption).foregroundStyle(Color.labelSecondary)
            }
        }
        .padding(Spacing.lg)
        .premiumCard()
    }

    // MARK: - About prices

    /// What the prices are (estimates, not live) and the currency they are in.
    private var aboutPrices: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            AboutPricesNote(compact: true)
            NavigationLink {
                CurrencySettingsView()
            } label: {
                HStack {
                    Text("Prices in \(Money.current.name) (\(Money.current.code))" as String)
                        .font(.footnote.weight(.semibold))
                    Spacer(minLength: Spacing.sm)
                    Text("Change").font(.footnote.weight(.semibold))
                    Image(systemName: "chevron.right").font(.caption.weight(.semibold))
                }
                .foregroundStyle(Color.brandPrimary)
                .frame(minHeight: 44)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("shop.currency")
        }
        .padding(Spacing.lg)
        .frame(maxWidth: .infinity, alignment: .leading)
        .premiumCard(radius: Radius.tile)
    }

    // MARK: - Catalogue and stock

    private var storeGrid: some View {
        VStack(spacing: Spacing.sm) {
            NavigationLink {
                StoreProductsView(store: .catalog)
            } label: {
                ShopLinkCard(symbol: "basket.fill", title: "Product catalogue",
                             detail: "\(CatalogItem.all.count) items · estimated prices")
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("shop.catalog")

            NavigationLink {
                StockView()
            } label: {
                ShopLinkCard(symbol: "cabinet.fill", title: "My Stock",
                             detail: "Food you have at home · add your own")
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("shop.stock")
        }
    }

    // MARK: - Cart preview

    private var cartPreview: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("In Cart")
                    .font(.headline)
                Spacer()
                NavigationLink {
                    CartView()
                } label: {
                    Text("View all")
                        .font(.subheadline).foregroundStyle(Color.brandPrimary)
                        .frame(minWidth: 44, minHeight: 44, alignment: .trailing)
                        .contentShape(Rectangle())
                }
            }

            ForEach(cart.cartItems.prefix(3)) { item in
                HStack(spacing: 12) {
                    Circle()
                        .fill(Color.labelPrimary.opacity(0.12))
                        .frame(width: 36, height: 36)
                        .overlay(
                            Image(systemName: (CatalogCategory(rawValue: item.category) ?? .snacks).symbol)
                                .font(.system(size: 14, weight: .medium))
                                .foregroundStyle(Color.labelPrimary)
                        )
                    Text(item.name).font(.subheadline).fontWeight(.medium).lineLimit(1)
                    Spacer()
                    Text("×\(item.quantity)" as String)
                        .font(.caption).foregroundStyle(Color.labelSecondary)
                    Text(Money.format(eur: item.lineTotal))
                        .font(.subheadline).fontWeight(.semibold).monospacedDigit()
                }
            }

            if cart.cartItems.count > 3 {
                Text("+ \(cart.cartItems.count - 3) more items" as String)
                    .font(.caption).foregroundStyle(Color.labelSecondary)
            }
        }
        .padding(16)
        .premiumCard()
    }

    // MARK: - Budget sheet

    /// The ruler and the text field share `budgetInput`: dragging rewrites the text,
    /// a valid typed amount glides the ruler there. The ruler covers the whole
    /// allowed budget range, and only a drag to another tick writes, so opening
    /// or touching it never changes a typed amount like €7 or €500.
    /// The ruler works in the chosen currency (in steps of 5, or 500 for yen);
    /// the budget is kept in euros like every price.
    private var budgetRulerStep: Double { Money.niceStep() }

    private var budgetRulerRange: ClosedRange<Double> {
        let local = Money.localRange(ShoppingCartService.budgetRange)
        let step = budgetRulerStep
        let lo = max((local.lowerBound / step).rounded(.up) * step, step)
        let hi = max((local.upperBound / step).rounded(.down) * step, lo + step)
        return lo...hi
    }

    private var budgetSliderValue: Binding<Double> {
        Binding(
            get: {
                let range = budgetRulerRange
                let typed = Money.parseLocal(budgetInput)
                return min(max(typed ?? Money.local(fromEUR: cart.weeklyBudget), range.lowerBound), range.upperBound)
            },
            set: { budgetInput = String(format: "%.0f", $0) }
        )
    }

    private var budgetSheet: some View {
        NavigationStack {
            Form {
                Section("Weekly grocery budget in \(Money.current.code)" as String) {
                    RulerPicker(value: budgetSliderValue, range: budgetRulerRange, step: budgetRulerStep,
                                majorEvery: 10, midEvery: 2, spacing: 12,
                                tickLabel: { Money.formatLocalWhole($0) },
                                accessibilityName: "Weekly budget",
                                spokenValue: { "\(Int($0)) \(Money.current.code)" })
                        .frame(height: 96)
                        .padding(.vertical, Spacing.xs)
                    HStack {
                        Text(Money.symbol())
                        TextField(Money.inputText(eur: 60), text: $budgetInput)
                            .keyboardType(.decimalPad)
                            .accessibilityLabel("Weekly budget in \(Money.current.name)")
                            .accessibilityIdentifier("shop.budgetInput")
                            .onChange(of: budgetInput) { _, _ in budgetError = nil }
                    }
                    if let budgetError {
                        Text(budgetError)
                            .font(.footnote).foregroundStyle(Color.brandDanger)
                            .accessibilityIdentifier("shop.budgetError")
                    }
                }
                Section {
                    Text("The budget bar fills as your cart grows and turns red once you have used 90% of the budget. Under it you see how much is left.")
                        .font(.caption).foregroundStyle(Color.labelSecondary)
                    AboutPricesNote(compact: true)
                }
            }
            .navigationTitle("Set budget")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        // Typed in the chosen currency, kept in euros like every price.
                        let range = ShoppingCartService.budgetRange
                        switch Money.validateLocal(budgetInput, eurRange: range) {
                        case .success(let eur):
                            cart.weeklyBudget = min(max(eur, range.lowerBound), range.upperBound)
                            budgetTip.invalidate(reason: .actionPerformed)
                            showBudgetEditor = false
                        case .failure(let problem):
                            budgetError = Money.message(for: problem, example: Money.inputText(eur: 60))
                            UIAccessibility.post(notification: .announcement, argument: budgetError)
                        }
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

// MARK: - Link card

private struct ShopLinkCard: View {
    let symbol: String
    let title: String
    let detail: String

    var body: some View {
        HStack(spacing: Spacing.md) {
            Image(systemName: symbol)
                .font(.title3)
                .foregroundStyle(Color.labelPrimary)
                .frame(width: 44, height: 44)
                .background(Color.surfaceSecondary, in: RoundedRectangle(cornerRadius: Radius.chip))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: Spacing.xs) {
                Text(title).font(.headline).foregroundStyle(Color.labelPrimary)
                Text(detail)
                    .font(.footnote).foregroundStyle(Color.labelSecondary)
                    .fixedSize(horizontal: false, vertical: true)
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
                Text("\(min(count, 99))" as String)
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
    /// Created once on appear: a `@State` initial value would be rebuilt (storage
    /// load and a notification task) every time the parent re-renders.
    @State private var undo: GroceryListViewModel?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        List {
            if cart.cartItems.isEmpty {
                ContentUnavailableView(
                    "Your cart is empty",
                    systemImage: "cart",
                    description: Text("Browse the catalogue and add items to get started.")
                )
                .listRowBackground(Color.clear)
            } else {
                Section {
                    ForEach(cart.cartItems, content: CartItemRow.init)
                }

                Section {
                    VStack(spacing: 10) {
                        HStack {
                            Text("Subtotal")
                            Spacer()
                            Text(Money.format(eur: cart.total)).fontWeight(.semibold).monospacedDigit()
                        }
                        HStack {
                            Text(cart.budgetRemaining < 0 ? "Over budget" : "Budget remaining")
                            Spacer()
                            Text(cart.budgetRemaining < 0
                                 ? (Money.format(eur: -cart.budgetRemaining) + " over budget")
                                 : Money.format(eur: cart.budgetRemaining))
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
                    Button("Clear", role: .destructive) { undoModel.clearCart() }
                        .accessibilityIdentifier("cart.clear")
                }
            }
        }
        .safeAreaInset(edge: .bottom) {
            if let message = undo?.undoMessage {
                UndoToast(message: message) { undo?.undoDelete() }
                    .padding(.vertical, Spacing.sm)
                    .transition(reduceMotion ? .opacity : .move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(reduceMotion ? .none : .snappyValue, value: undo?.undoMessage)
        .onAppear { if undo == nil { undo = GroceryListViewModel() } }
    }

    private var undoModel: GroceryListViewModel {
        if let undo { return undo }
        let model = GroceryListViewModel()
        undo = model
        return model
    }
}

private struct CartItemRow: View {
    let item: CartItem
    @State private var cart = ShoppingCartService.shared

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(item.name).font(.subheadline).fontWeight(.medium)
                Text((cart.isEstimated(item.catalogId, store: item.store) ? "est. " : "your price ") + Money.format(eur: item.price)).font(.caption).foregroundStyle(Color.labelSecondary)
            }
            Spacer()
            QuantityStepper(quantity: item.quantity, name: item.name,
                            onAdd:    { cart.add(CatalogItem(id: item.catalogId, name: item.name, category: CatalogCategory(rawValue: item.category) ?? .snacks),
                                                 store: .catalog) },
                            onRemove: { cart.remove(item.catalogId, store: item.store) })
            Text(Money.format(eur: item.lineTotal))
                .font(.subheadline).fontWeight(.semibold).monospacedDigit()
                .lineLimit(1)
                .fixedSize()
        }
    }
}

#Preview { StoreBrowserView() }
