import Foundation

@MainActor
final class AgentLoop {

    private var task: Task<Void, Never>?
    private var regenTask: Task<Void, Never>?
    private var cartObserver: NSObjectProtocol?
    private weak var appState: AppState?
    private var dataGeneration = 0
    /// Set once a live (non-fallback) deals response has been seen.
    private var hasLiveDeals = false
    /// Serialises online regenerations so one can't clear the other's flag.
    private var isRegenerating = false

    static let lastPlanDateKey = "lastMealPlanGeneratedDate"

    /// Records that today's plan is fresh. Call only after a plan was saved.
    static func markPlanGeneratedToday() {
        UserDefaults.standard.set(Calendar.current.startOfDay(for: Date()), forKey: lastPlanDateKey)
    }

    /// Invalidates responses that were requested before the user's data was erased.
    func invalidateUserData() {
        dataGeneration += 1
        hasLiveDeals = false
        regenTask?.cancel()
        regenTask = nil
    }

    func start(appState: AppState) {
        stop()
        self.appState = appState
        // Curated estimates cannot support retailer alerts. Discard any old
        // in-memory alert queue when the loop restarts.
        appState.dealNotifications = []
        task = Task { [weak appState] in
            while !Task.isCancelled {
                if let appState { await tick(appState: appState) }
                // 5-minute cadence — battery/data friendly (was 30s).
                try? await Task.sleep(for: .seconds(300))
            }
        }
        // Cart edits rebuild only the on-device plan (debounced). They never
        // call the online AI; the user regenerates an AI plan explicitly.
        cartObserver = NotificationCenter.default.addObserver(
            forName: .cartDidChange, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in self?.scheduleLocalRegen() }
        }
    }

    func stop() {
        task?.cancel(); task = nil
        regenTask?.cancel(); regenTask = nil
        if let cartObserver {
            NotificationCenter.default.removeObserver(cartObserver)
            self.cartObserver = nil
        }
    }

    /// Coalesces rapid cart edits into a single local plan rebuild.
    private func scheduleLocalRegen() {
        regenTask?.cancel()
        regenTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(1.5))
            guard !Task.isCancelled, let self, let appState = self.appState else { return }
            self.regenerateLocalPlan(appState: appState)
        }
    }

    /// Replaces only a missing or on-device plan; an AI or saved plan is kept.
    private func regenerateLocalPlan(appState: AppState) {
        guard appState.isOnboarded, let bmr = appState.bmrData else { return }
        if let current = appState.weeklyMealPlan, current.generationSource != "local" { return }
        let goal = appState.userProfile.weightGoal.rawValue
        var plan = FallbackData.mealPlan(targetKcal: bmr.calories(forGoal: goal), pantry: [])
        plan.generationSource = "local"
        appState.saveMealPlan(plan)
    }

    // MARK: - Tick

    private func tick(appState: AppState) async {
        guard appState.isOnboarded else { return }
        let generation = dataGeneration
        // 1. Refresh deals. No location is sent; nearby filtering is on-device.
        let deals = (try? await APIService.shared.getDeals()) ?? []
        let dealsAreLive = !APIService.shared.lastDealsWereFallback
        guard !Task.isCancelled, generation == dataGeneration else { return }
        if !deals.isEmpty { appState.activeDeals = deals }

        // Catalog estimates still support browsing/planning, but never generate
        // discount, proximity, availability or expiry notifications.

        // 2. Regenerate meal plan if needed. Bundled offline deals never count
        // as "deals just arrived".
        let currentCount = appState.groceryList.count
        let needsPlan = appState.weeklyMealPlan == nil
        let listGrew  = currentCount > appState.lastGroceryCount
        let needsDailyRefresh = isDueForDailyRefresh()
        let dealsJustArrived = dealsAreLive && !deals.isEmpty && !hasLiveDeals
        if dealsAreLive && !deals.isEmpty { hasLiveDeals = true }
        if needsPlan || listGrew || needsDailyRefresh || dealsJustArrived {
            appState.lastGroceryCount = currentCount
            await regenerateMealPlan(appState: appState)
        }
    }

    /// Read-only check; the date is stamped only after a plan is saved.
    private func isDueForDailyRefresh() -> Bool {
        let today = Calendar.current.startOfDay(for: Date())
        let last = UserDefaults.standard.object(forKey: Self.lastPlanDateKey) as? Date ?? .distantPast
        return last < today
    }

    // MARK: - Meal plan regeneration

    private func regenerateMealPlan(appState: AppState) async {
        guard !isRegenerating, let bmr = appState.bmrData else { return }
        let generation = dataGeneration
        isRegenerating = true
        appState.isGeneratingMealPlan = true
        defer {
            isRegenerating = false
            appState.isGeneratingMealPlan = false
        }

        let request = MealPlanRequest.current(profile: appState.userProfile, bmr: bmr)

        do {
            let plan = try await APIService.shared.generateMealPlan(request)
            guard !Task.isCancelled, generation == dataGeneration else { return }
            appState.saveMealPlan(plan)
            Self.markPlanGeneratedToday()
            appLog("[AgentLoop] meal plan regenerated successfully")
        } catch {
            appLog("[AgentLoop] meal plan generation failed:", error)
        }
    }
}
