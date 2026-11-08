import SwiftUI

/// Community retailer metadata is a discovery aid, never a branch inventory feed.
struct RetailerProductsView: View {
    let retailer: String
    @State private var storeTag = ""
    @State private var query = ""
    @State private var market = NutritionCatalogService.Market.worldwide
    @State private var products: [NutritionFood] = []
    @State private var page = 0
    @State private var hasMore = false
    @State private var loading = false
    @State private var notice: String?
    @State private var selected: NutritionFood?
    @State private var request: Task<Void, Never>?
    @State private var generation = UUID()

    var body: some View {
        List {
            Section("Find reported products") {
                TextField("Retailer tag, e.g. rimi", text: $storeTag).textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                TextField("Product name (optional)", text: $query)
                Picker("Market", selection: $market) {
                    ForEach(NutritionCatalogService.Market.allCases) { Text($0.title).tag($0) }
                }
                Text("Sends the retailer tag, optional search, market and language to Open Food Facts when you tap Search. Your location, profile and stock are not sent.")
                    .font(.footnote).foregroundStyle(.secondary)
                Button(loading ? "Searching…" : "Search products") { search() }
                    .disabled(loading || storeTag.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .accessibilityIdentifier("retailer.search")
            }
            Section {
                Text("Retailer information is reported by Open Food Facts contributors. It does not confirm stock, prices or availability at this branch. Check with the store before shopping.")
                    .font(.footnote).foregroundStyle(.secondary)
                if loading { ProgressView() }
                if let notice { Text(notice).font(.footnote) }
                ForEach(products) { food in
                    Button { selected = food } label: {
                        VStack(alignment: .leading, spacing: 5) {
                            Text(food.name).foregroundStyle(.primary)
                            Text(food.subtitle).font(.caption).foregroundStyle(.secondary)
                            Text("Reported retailers: \((food.reportedRetailers ?? []).joined(separator: ", "))")
                                .font(.caption).foregroundStyle(.secondary)
                            if let date = food.sourceDate { Text("Retrieved \(date)").font(.caption2).foregroundStyle(.secondary) }
                        }
                    }
                }
                if hasMore {
                    Button("Load more products") { search(more: true) }.disabled(loading)
                }
            } header: { Text("Reported products · \(products.count)") }
            Section {
                Link("Open Food Facts · ODbL database", destination: URL(string: "https://world.openfoodfacts.org/terms-of-use")!)
            }
        }
        .navigationTitle(retailer.isEmpty ? "Retailer Products" : retailer)
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { if storeTag.isEmpty { storeTag = retailer.lowercased().replacingOccurrences(of: " ", with: "-") } }
        .onChange(of: query) { reset() }
        .onChange(of: market) { reset() }
        .onChange(of: storeTag) { reset() }
        .onDisappear { request?.cancel() }
        .sheet(item: $selected) { food in
            NavigationStack {
                ServingDetailView(food: food, slot: .suggested(), actionTitle: "Add purchased food to stock") { amount in
                    do {
                        try StockStore.shared.add(food: food, amount: amount)
                        NutritionCatalogService.shared.remember(food)
                        selected = nil
                        notice = "Added to your stock."
                    } catch { selected = nil; notice = error.localizedDescription }
                }
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Done") { selected = nil } } }
            }
        }
    }
    private func reset() {
        generation = UUID()
        request?.cancel()
        products = []
        page = 0
        hasMore = false
        notice = nil
        loading = false
    }
    private func search(more: Bool = false) {
        let submitted = generation, tag = storeTag, text = query, selectedMarket = market
        let next = more ? page + 1 : 1
        loading = true
        notice = nil
        request = Task { @MainActor in
            do {
                let result = try await NutritionCatalogService.shared.fetchProducts(text, market: selectedMarket, page: next, retailer: tag)
                guard !Task.isCancelled, generation == submitted else { return }
                if more {
                    let ids = Set(products.map(\.id))
                    products += result.foods.filter { !ids.contains($0.id) }
                } else { products = result.foods }
                page = next
                hasMore = result.hasMore
                if result.foods.isEmpty { notice = "No complete nutrition records with this retailer tag on this page. Try another retailer tag or market, or load more if available." }
            } catch {
                guard !Task.isCancelled, generation == submitted else { return }
                notice = error.localizedDescription
            }
            loading = false
        }
    }
}
