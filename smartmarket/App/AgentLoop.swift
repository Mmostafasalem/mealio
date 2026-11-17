import Foundation

@MainActor
final class AgentLoop {

    private var task: Task<Void, Never>?
    private var regenTask: Task<Void, Never>?
    private var profileTask: Task<Void, Never>?
    /// The background online request, so a user regenerate can cancel it.
    private var aiTask: Task<WeeklyMealPlan, Error>?
    /// The inputs `aiTask`'s request was built from.
    private var aiTaskInputs: PlanInputs?
    private var cartObserver: NSObjectProtocol?
    private var profileObserver: NSObjectProtocol?
    private weak var appState: AppState?
    private var dataGeneration = 0
    /// Legacy grocery-list size seen on the first tick after launch. Nil until
    /// then, so a list restored from disk never counts as "the list grew".
    private var groceryBaseline: Int?
    /// True while a tick runs, so a second `start` never cancels it mid-request.
    private var isTicking = false

    static let lastPlanDateKey = "lastMealPlanGeneratedDate"
    /// When the last background online refresh failed (backoff).
    static let lastFailureKey = "lastMealPlanRefreshFailure"
    /// Set when profile edits left an online plan due for a refresh.
    static let refreshRequestedKey = "mealPlanRefreshRequested"
    /// The `PlanInputs` the saved plan was built for.
    static let planInputsKey = "mealPlanInputs"
    /// No new background online attempt this long after a failed one.
    static let failureBackoff: TimeInterval = 60 * 60
    /// At most this many failed background online attempts a day; after that the
    /// saved plan stays until tomorrow (each attempt may use AI credits).
    static let maxFailuresPerDay = 3
    static let failureDayKey = "mealPlanFailureDay"
    static let failureCountKey = "mealPlanFailureCount"

    /// Failed background attempts recorded today.
    static func failuresToday(defaults: UserDefaults = .standard, now: Date = Date()) -> Int {
        guard let day = defaults.object(forKey: failureDayKey) as? Date,
              Calendar.current.isDate(day, inSameDayAs: now) else { return 0 }
        return defaults.integer(forKey: failureCountKey)
    }

    /// Records that today's AI plan is fresh. Call only after an online plan
    /// (`generationSource == "online"`) was saved, never for a local fallback.
    static func markPlanGeneratedToday(defaults: UserDefaults = .standard) {
        defaults.set(Calendar.current.startOfDay(for: Date()), forKey: lastPlanDateKey)
        defaults.removeObject(forKey: lastFailureKey)
        defaults.removeObject(forKey: refreshRequestedKey)
        defaults.removeObject(forKey: failureDayKey)
        defaults.removeObject(forKey: failureCountKey)
    }

    /// Starts the failure backoff: no background online attempt for an hour.
    static func noteRefreshFailed(defaults: UserDefaults = .standard, now: Date = Date()) {
        defaults.set(failuresToday(defaults: defaults, now: now) + 1, forKey: failureCountKey)
        defaults.set(Calendar.current.startOfDay(for: now), forKey: failureDayKey)
        defaults.set(now, forKey: lastFailureKey)
    }

    /// Whether a plan returned by `APIService.generateMealPlan` came from the AI
    /// (rather than the on-device fallback used when the AI call failed).
    /// Off: meal plans are built on the phone. Online AI is used for chat and recipes only.
    nonisolated static let onlineMealPlans = false

    nonisolated static func isAIPlan(_ plan: WeeklyMealPlan) -> Bool {
        plan.generationSource == "online"
    }

    // MARK: - Plan inputs

    /// What a plan was built for. A profile save or sync pull that leaves
    /// these unchanged changes nothing about the plan.
    struct PlanInputs: Codable, Equatable {
        var calorieTarget: Int
        var weightGoal: String
        var dietaryPreferences: [String]
        var favoriteFoodIDs: [String]

        /// The person's current inputs; nil before there are body stats.
        @MainActor static func current(_ appState: AppState) -> PlanInputs? {
            guard let bmr = appState.bmrData else { return nil }
            let goal = appState.userProfile.weightGoal.rawValue
            return PlanInputs(calorieTarget: bmr.calories(forGoal: goal), weightGoal: goal,
                              dietaryPreferences: Set<DietaryPreference>.load().map(\.rawValue).sorted(),
                              favoriteFoodIDs: appState.favoriteFoodIDs.sorted())
        }
    }

    static func storedPlanInputs(defaults: UserDefaults = .standard) -> PlanInputs? {
        guard let data = defaults.data(forKey: planInputsKey) else { return nil }
        return try? JSONDecoder().decode(PlanInputs.self, from: data)
    }

    /// Stores what the saved plan was built for (nil removes it).
    static func recordPlanInputs(_ inputs: PlanInputs?, defaults: UserDefaults = .standard) {
        guard let inputs, let data = try? JSONEncoder().encode(inputs) else {
            defaults.removeObject(forKey: planInputsKey)
            return
        }
        defaults.set(data, forKey: planInputsKey)
    }

    /// Invalidates responses that were requested before the user's data was erased.
    func invalidateUserData() {
        dataGeneration += 1
        groceryBaseline = nil
        regenTask?.cancel(); regenTask = nil
        profileTask?.cancel(); profileTask = nil
        aiTask?.cancel()
    }

    /// Stops the background online request so a user-started one replaces it.
    func cancelBackgroundRegeneration() {
        aiTask?.cancel()
    }

    func start(appState: AppState) {
        // Already running for this state (onboarding and the app root both
        // start it): tick again now, but never cancel a tick that is under way,
        // or the first plan request would be dropped.
        if task != nil, self.appState === appState {
            if !isTicking { startTicking(appState: appState) }
            return
        }
        stop()
        self.appState = appState
        // Curated estimates cannot support retailer alerts. Discard any old
        // in-memory alert queue when the loop restarts.
        appState.dealNotifications = []
        // A plan saved before inputs were recorded: take today's as its baseline,
        // so the next unrelated sync doesn't count as a profile change.
        if appState.weeklyMealPlan != nil, Self.storedPlanInputs() == nil {
            Self.recordPlanInputs(PlanInputs.current(appState))
        }
        startTicking(appState: appState)
        // Cart edits rebuild only the on-device plan (debounced). They never
        // call the online AI; the user regenerates an AI plan explicitly.
        cartObserver = NotificationCenter.default.addObserver(
            forName: .cartDidChange, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in self?.scheduleLocalRegen() }
        }
        // Profile edits (body stats, goal, pace, diet, favourites) change the
        // calorie target and the foods allowed, so the plan follows them.
        profileObserver = NotificationCenter.default.addObserver(
            forName: .personalDataDidChange, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in self?.scheduleProfileRebuild() }
        }
    }

    /// (Re)starts the 5-minute loop with an immediate tick.
    private func startTicking(appState: AppState) {
        task?.cancel()
        task = Task { [weak appState] in
            while !Task.isCancelled {
                if let appState { await tick(appState: appState) }
                // 5-minute cadence — battery/data friendly (was 30s).
                try? await Task.sleep(for: .seconds(300))
            }
        }
    }

    func stop() {
        task?.cancel(); task = nil
        regenTask?.cancel(); regenTask = nil
        profileTask?.cancel(); profileTask = nil
        aiTask?.cancel()
        if let cartObserver {
            NotificationCenter.default.removeObserver(cartObserver)
            self.cartObserver = nil
        }
        if let profileObserver {
            NotificationCenter.default.removeObserver(profileObserver)
            self.profileObserver = nil
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

    /// Coalesces a burst of profile saves into one plan update.
    private func scheduleProfileRebuild() {
        profileTask?.cancel()
        profileTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(1.5))
            guard !Task.isCancelled, let self, let appState = self.appState else { return }
            self.applyProfileChange(appState: appState)
        }
    }

    /// Runs only when the plan's inputs (target, goal, diet, favourites)
    /// changed; a sync pull or save that changes none of them does nothing.
    /// An on-device plan is rebuilt right away. An online plan is kept while it
    /// still fits the new target and is marked due for a refresh on the next
    /// eligible tick; one that no longer fits is rebuilt on the device.
    private func applyProfileChange(appState: AppState) {
        guard appState.isOnboarded, let bmr = appState.bmrData,
              let inputs = PlanInputs.current(appState) else { return }
        let target = bmr.calories(forGoal: appState.userProfile.weightGoal.rawValue)
        let builtFor = Self.storedPlanInputs()
        let action = Self.profileChangeAction(for: appState.weeklyMealPlan, target: target,
                                              builtFor: builtFor, current: inputs)
        if action == .keep {
            // A plan from before inputs were recorded adopts the current ones.
            if builtFor == nil { Self.recordPlanInputs(inputs) }
            // Edits that were undone leave the plan fitting again: no refresh due.
            else { UserDefaults.standard.removeObject(forKey: Self.refreshRequestedKey) }
            return
        }
        // A background request built from other inputs must not land later.
        if aiTask != nil, aiTaskInputs != inputs { cancelBackgroundRegeneration() }
        switch action {
        case .rebuildLocally:
            saveLocalPlan(target: target, appState: appState)
        case .requestRefresh:
            UserDefaults.standard.set(true, forKey: Self.refreshRequestedKey)
        case .keep:
            break
        }
    }

    enum ProfileChangeAction: Equatable { case keep, rebuildLocally, requestRefresh }

    static func profileChangeAction(for plan: WeeklyMealPlan?, target: Int) -> ProfileChangeAction {
        guard let plan, plan.generationSource != "local" else { return .rebuildLocally }
        return plan.isOnTarget(target) ? .requestRefresh : .rebuildLocally
    }

    /// Like `profileChangeAction(for:target:)`, but a saved plan is kept when
    /// it was built for the current inputs, or when they were never recorded.
    static func profileChangeAction(for plan: WeeklyMealPlan?, target: Int,
                                    builtFor: PlanInputs?, current: PlanInputs) -> ProfileChangeAction {
        if plan != nil, builtFor == nil || builtFor == current { return .keep }
        return profileChangeAction(for: plan, target: target)
    }

    /// Replaces only a missing or on-device plan; an AI or saved plan is kept.
    private func regenerateLocalPlan(appState: AppState) {
        guard appState.isOnboarded, let bmr = appState.bmrData else { return }
        if let current = appState.weeklyMealPlan, current.generationSource != "local" { return }
        saveLocalPlan(target: bmr.calories(forGoal: appState.userProfile.weightGoal.rawValue), appState: appState)
    }

    /// Saves the on-device plan for `target` unless it is the plan already shown.
    private func saveLocalPlan(target: Int, appState: AppState) {
        // Built from the current profile, whether or not it is saved again.
        Self.recordPlanInputs(PlanInputs.current(appState))
        let plan = Self.localPlan(target: target)
        guard plan != appState.weeklyMealPlan else { return }
        appState.saveMealPlan(plan)
    }

    private static func localPlan(target: Int) -> WeeklyMealPlan {
        var plan = FallbackData.mealPlan(targetKcal: target, pantry: [])
        plan.generationSource = "local"
        return plan
    }

    // MARK: - Tick

    private func tick(appState: AppState) async {
        isTicking = true
        defer { isTicking = false }
        guard appState.isOnboarded else { return }
        let generation = dataGeneration
        // 1. Refresh deals for browsing. No location is sent. The catalogue is
        // static estimates, so deals never trigger a plan regeneration.
        let result = await APIService.shared.fetchDeals()
        guard !Task.isCancelled, generation == dataGeneration else { return }
        if !result.deals.isEmpty { appState.activeDeals = result.deals }

        // 2. A saved plan that misses the calorie target is replaced on the
        // device (no network, so no metered AI call on every tick).
        let target = appState.bmrData?.calories(forGoal: appState.userProfile.weightGoal.rawValue) ?? 0
        if let replacement = Self.replacement(for: appState.weeklyMealPlan, target: target,
                                              build: { Self.localPlan(target: target) }) {
            appState.saveMealPlan(replacement)
            Self.recordPlanInputs(PlanInputs.current(appState))
        }

        // 3. Online refresh only for no plan, the daily refresh, a growing list
        // or a profile change, with consent, outside the failure backoff.
        let defaults = UserDefaults.standard
        let count = appState.groceryList.count
        let inputs = RegenerationInputs(
            hasPlan: appState.weeklyMealPlan != nil,
            groceryCount: count,
            groceryBaseline: groceryBaseline,
            dueForDailyRefresh: Self.isDueForDailyRefresh(defaults: defaults),
            refreshRequested: defaults.bool(forKey: Self.refreshRequestedKey),
            // Meal plans are always built on the phone; online AI is only for chat and recipes.
            hasAIConsent: Self.onlineMealPlans && APIService.shared.hasAIConsent,
            lastFailure: defaults.object(forKey: Self.lastFailureKey) as? Date,
            now: Date(),
            failuresToday: Self.failuresToday(defaults: defaults))
        if Self.shouldAttemptOnlineRegeneration(inputs),
           let bmr = appState.bmrData,
           let ticket = appState.beginMealPlanRequest(.background) {
            // The growing list is consumed only once a request really starts.
            groceryBaseline = count
            appState.lastGroceryCount = count
            await regenerateMealPlan(appState: appState, bmr: bmr, ticket: ticket)
        } else {
            // The first tick only records the baseline; a shrinking list moves it
            // down. A list that grew stays pending until a request can start.
            if groceryBaseline == nil || count < (groceryBaseline ?? 0) {
                groceryBaseline = count
                appState.lastGroceryCount = count
            }
            // No online attempt (no consent, backing off, or another request
            // runs): keep a local plan unless a request may still supply one.
            if appState.weeklyMealPlan == nil, !appState.isGeneratingMealPlan {
                regenerateLocalPlan(appState: appState)
            }
        }
    }

    struct RegenerationInputs {
        var hasPlan: Bool
        var groceryCount: Int
        var groceryBaseline: Int?
        var dueForDailyRefresh: Bool
        var refreshRequested: Bool
        var hasAIConsent: Bool
        var lastFailure: Date?
        var now: Date
        var failuresToday: Int = 0
    }

    /// The tick's decision to make a (metered) online meal-plan request.
    static func shouldAttemptOnlineRegeneration(_ i: RegenerationInputs) -> Bool {
        let listGrew = i.groceryBaseline.map { i.groceryCount > $0 } ?? false
        guard !i.hasPlan || listGrew || i.dueForDailyRefresh || i.refreshRequested else { return false }
        guard i.hasAIConsent else { return false }
        if let failed = i.lastFailure, i.now.timeIntervalSince(failed) < failureBackoff { return false }
        // A plan with no saved plan at all may still try; otherwise stop for the day.
        if i.hasPlan, i.failuresToday >= maxFailuresPerDay { return false }
        return true
    }

    /// A saved plan whose days miss the calorie target (see `WeeklyMealPlan.isOnTarget`).
    nonisolated static func savedPlanNeedsReplacing(_ plan: WeeklyMealPlan?, target: Int) -> Bool {
        guard let plan, target > 0 else { return false }
        return !plan.isOnTarget(target)
    }

    /// The plan to save in place of an off-target one, or nil to keep it. Never
    /// re-saves the same plan, and never swaps an online plan for a local one
    /// that misses the target too, so an off-target plan can't loop.
    static func replacement(for plan: WeeklyMealPlan?, target: Int,
                            build: () -> WeeklyMealPlan) -> WeeklyMealPlan? {
        guard savedPlanNeedsReplacing(plan, target: target) else { return nil }
        let candidate = build()
        if candidate == plan { return nil }
        if !candidate.isOnTarget(target) && plan?.generationSource != "local" { return nil }
        return candidate
    }

    /// Read-only check; the date is stamped only after a plan is saved.
    static func isDueForDailyRefresh(defaults: UserDefaults = .standard, now: Date = Date()) -> Bool {
        let today = Calendar.current.startOfDay(for: now)
        let last = defaults.object(forKey: lastPlanDateKey) as? Date ?? .distantPast
        return last < today
    }

    // MARK: - Meal plan regeneration

    /// Runs one background online request on a slot the caller already claimed.
    private func regenerateMealPlan(appState: AppState, bmr: BMRResponse,
                                    ticket: AppState.MealPlanRequestTicket) async {
        let generation = dataGeneration
        let builtFor = PlanInputs.current(appState)
        let request = MealPlanRequest.current(profile: appState.userProfile, bmr: bmr)
        let work = Task { try await APIService.shared.generateMealPlan(request) }
        aiTask = work
        aiTaskInputs = builtFor
        defer {
            appState.endMealPlanRequest(ticket)
            if aiTask == work { aiTask = nil; aiTaskInputs = nil }
        }
        // A user regenerate, a data reset or a profile change took over: drop this result.
        func superseded() -> Bool {
            work.isCancelled || Task.isCancelled || generation != dataGeneration
                || !appState.ownsMealPlanRequest(ticket)
                || PlanInputs.current(appState) != builtFor
        }

        do {
            let plan = try await work.value
            guard !superseded() else { return }
            appState.saveMealPlan(plan)
            Self.recordPlanInputs(builtFor)
            if Self.isAIPlan(plan) {
                Self.markPlanGeneratedToday()
                appLog("[AgentLoop] meal plan regenerated successfully")
            } else {
                // The AI call failed and there was no plan: an on-device plan is
                // shown, but the day isn't stamped and the backoff starts.
                Self.noteRefreshFailed()
                appLog("[AgentLoop] online meal plan unavailable; saved an on-device plan")
            }
        } catch {
            guard !superseded() else { return }
            // Back off so a failing service isn't retried on every tick.
            Self.noteRefreshFailed()
            appLog("[AgentLoop] meal plan generation failed:", error)
        }
    }
}
