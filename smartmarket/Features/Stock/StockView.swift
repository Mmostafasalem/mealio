import SwiftUI

struct StockView: View {
    @State private var store = StockStore.shared
    @State private var logVM = HomeViewModel()
    @State private var showAdd = false
    @State private var selected: StockItem?
    @State private var errorMessage: String?
    @State private var query = ""

    private var filtered: [StockItem] {
        store.items.filter { query.isEmpty || $0.food.name.localizedStandardContains(query) }
            .sorted { ($0.expiresAt ?? .distantFuture) < ($1.expiresAt ?? .distantFuture) }
    }

    var body: some View {
        List {
            Section {
                Text("Food you have at home. Add the quantity you own, then log what you eat from here.")
                    .font(.footnote).foregroundStyle(.secondary)
                Button("Add food to stock", systemImage: "plus") { showAdd = true }
                    .accessibilityIdentifier("stock.add")
            }
            if store.items.isEmpty {
                ContentUnavailableView("Your stock starts here", systemImage: "cabinet",
                                       description: Text("Search reference foods, enter a barcode, or choose one of your saved dishes."))
            }
            ForEach(filtered) { item in
                Button { selected = item } label: {
                    VStack(alignment: .leading, spacing: 5) {
                        Text(item.food.name).foregroundStyle(.primary)
                        Text("\(item.amount.formatted()) \(item.food.basis.rawValue) available")
                            .font(.subheadline).foregroundStyle(.secondary)
                        if let expiry = item.expiresAt {
                            Text("Use by \(expiry.formatted(date: .abbreviated, time: .omitted))")
                                .font(.caption).foregroundStyle(expiry < Date() ? Color.red : Color.secondary)
                        }
                    }
                }
                .accessibilityIdentifier("stock.item." + item.food.id)
                .swipeActions {
                    Button("Remove", role: .destructive) {
                        do { try store.remove(id: item.id) } catch { errorMessage = error.localizedDescription }
                    }
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background { GrainyGradient().ignoresSafeArea() }
        .navigationTitle("My Stock")
        .navigationBarHidden(false)
        .searchable(text: $query, prompt: "Find food in your stock")
        .sheet(isPresented: $showAdd) {
            LogFoodSheet(vm: logVM, onSelect: { food, amount in
                do { try store.add(food: food, amount: amount) }
                catch { errorMessage = error.localizedDescription }
            })
        }
        .sheet(item: $selected) { item in StockItemSheet(item: item, store: store) }
        .alert("Could not update stock", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
            Button("OK") { errorMessage = nil }
        } message: { Text(errorMessage ?? "") }
    }
}

private struct StockItemSheet: View {
    let item: StockItem
    let store: StockStore
    @Environment(\.dismiss) private var dismiss
    @State private var amount = ""
    @State private var remainingAmount = ""
    @State private var slot = MealSlot.suggested()
    @State private var expiry = Date()
    @State private var hasExpiry = false
    @State private var errorMessage: String?
    private var value: Double? { Double(amount.replacingOccurrences(of: ",", with: ".")) }
    private var remainingValue: Double? { Double(remainingAmount.replacingOccurrences(of: ",", with: ".")) }

    var body: some View {
        NavigationStack {
            Form {
                Section(item.food.name) {
                    Text("\(item.amount.formatted()) \(item.food.basis.rawValue) available")
                    TextField("Amount in \(item.food.basis.rawValue)", text: $amount).keyboardType(.decimalPad)
                        .accessibilityIdentifier("stock.amount")
                    Picker("Meal", selection: $slot) { ForEach(MealSlot.allCases) { Text($0.title).tag($0) } }
                    Button("Log portion eaten") {
                        perform {
                            try store.consume(id: item.id, amount: value ?? 0, slot: slot)
                        }
                    }
                    .disabled(value == nil || (value ?? 0) <= 0 || (value ?? 0) > item.amount)
                    .accessibilityIdentifier("stock.consume")
                }
                Section("Adjust stock") {
                    Text("Correct the total quantity or update it after buying more.")
                        .font(.footnote).foregroundStyle(.secondary)
                    TextField("Total remaining in \(item.food.basis.rawValue)", text: $remainingAmount).keyboardType(.decimalPad)
                        .accessibilityIdentifier("stock.remainingAmount")
                    Toggle("Use-by date", isOn: $hasExpiry)
                    if hasExpiry { DatePicker("Date", selection: $expiry, displayedComponents: .date) }
                    Button("Save remaining amount") {
                        perform { try store.update(id: item.id, amount: remainingValue ?? 0, expiresAt: hasExpiry ? expiry : nil) }
                    }.disabled(remainingValue == nil || (remainingValue ?? 0) <= 0)
                    Button("Remove from stock", role: .destructive) { perform { try store.remove(id: item.id) } }
                }
                Section("Nutrition source") {
                    Text(item.food.sourceName)
                    Text(item.food.sourceExplanation).font(.footnote).foregroundStyle(.secondary)
                    if let url = item.food.sourceURL { Link("View source", destination: url) }
                }
                if let errorMessage { Text(errorMessage).foregroundStyle(.red) }
            }
            .navigationTitle("Stock details")
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Done") { dismiss() } } }
            .onAppear {
                amount = String(min(item.amount, item.food.defaultAmount))
                remainingAmount = String(item.amount)
                hasExpiry = item.expiresAt != nil
                expiry = item.expiresAt ?? Date()
            }
        }
    }
    private func perform(_ action: () throws -> Void) {
        do { try action(); dismiss() } catch { errorMessage = error.localizedDescription }
    }
}

struct FoodHistoryView: View {
    @State private var log = FoodLogStore.shared
    var body: some View {
        List {
            if log.allEntries.isEmpty {
                ContentUnavailableView("No food logged yet", systemImage: "clock", description: Text("Your recorded meals will appear here."))
            } else {
                Section {
                    CalorieTrendCard(entries: log.allEntries)
                        .listRowInsets(EdgeInsets())
                        .listRowBackground(Color.clear)
                }
            }
            ForEach(log.allEntries.reversed()) { entry in
                VStack(alignment: .leading, spacing: 4) {
                    Text(entry.name)
                    Text("\(entry.loggedAt.formatted(date: .abbreviated, time: .shortened)) · \(entry.slot.title)")
                        .font(.caption).foregroundStyle(.secondary)
                    Text("\(entry.amount.formatted()) \(entry.amountUnit) · \(entry.calories) kcal")
                        .font(.subheadline)
                }
                .swipeActions { Button("Delete", role: .destructive) { log.remove(entry) } }
            }
        }.navigationTitle("Food History")
        .navigationBarHidden(false)
        .onAppear { log.reload() }
    }
}
