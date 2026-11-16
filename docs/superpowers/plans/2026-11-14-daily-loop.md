# Daily loop Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Daily quests, a streak with savers, Nourlo's streak moods and badge on Home, and one evening streak nudge, all derived from data Nourlo already records.

**Architecture:** A pure engine (`Models/DailyLoop.swift`) takes a snapshot of food entries, stock-use ids, workouts, targets, cart facts, the stored ledger, `now` and a `Calendar`, and returns kept days, streak, quests, saver/milestone events to append, and Nourlo's mood. An `@Observable @MainActor` `DailyLoopStore` builds that snapshot from the existing stores, persists the ledger (`progressLedger`, device only), and publishes `LoopState`. UI reads the store. Nudges are built by a pure function and scheduled through the existing `ReminderScheduling` protocol.

**Tech Stack:** Swift 5, SwiftUI, Observation, UserNotifications, XCTest. iOS 17.

**Spec:** `docs/superpowers/specs/2026-11-14-daily-loop-design.md`

## Global Constraints
- A kept day = any food entry (`FoodLogStore.allEntries`, includes stock use), any `CompletedWorkout`, or a `budgetCheckIn` that day.
- Ledger key `progressLedger`, UserDefaults, **not** added to `SyncDataPolicy`. Cleared by `LocalDataEraser` (whole domain) — verify, don't add code.
- Savers: earned every 7 consecutive kept days from `loopStarted` on, max 2 held, auto-used oldest first for missed days after `loopStarted`.
- Milestones: 3, 7, 30, 100, 365.
- Nudge: 20:00, ids prefixed `streak_`, next 3 evenings, only if reminders enabled, `streakNudgeOn`, and streak ≥ 1 for the copy that names a streak. Copy exactly as in the spec.
- No guilt words in copy ("failed", "broke", "missed"). SF Symbols only. UserDefaults only.

## Review Focus
1. Midnight and time zone: an entry at 23:59 and one at 00:01 fall on different days using the injected calendar; DST day still counts once. Test in Task 1.
2. Deleting the only entry of today un-keeps today and un-ticks its quest, but the `questDone` record stays (no second celebration). Test in Task 4.
3. App opened after 5 missed days with 2 savers: exactly the first 2 missed days are saved, streak then 0. Test in Task 3.
4. Brand-new user (no history, no profile goal): quests exclude protein/onTarget, mood is happy, no crash on goal 0. Test in Task 2 and Task 1 (mood).
5. Reminders off: no streak notification is ever scheduled, and turning them off removes pending `streak_` ones. Test in Task 5.

---

### Task 1: Engine — days, kept days, streak, week row, mood

**Files:**
- Create: `smartmarket/Models/DailyLoop.swift`
- Test: `smartmarketTests/DailyLoopTests.swift`

**Interfaces:**
- Produces:
  - `struct DayKey: Hashable, Comparable, Codable { let year, month, day: Int }` with `init(_ date: Date, calendar: Calendar)`, `func date(in: Calendar) -> Date` (start of day), `func adding(days: Int, calendar: Calendar) -> DayKey`.
  - `enum LoopEvent: Codable, Equatable { case loopStarted(DayKey), questDone(DayKey, QuestID), perfectDay(DayKey), budgetCheckIn(DayKey), saverEarned(DayKey), saverUsed(DayKey), milestone(DayKey, Int) }`
  - `struct LoopInputs { var foodEntries: [FoodLogEntry]; var stockEntryIDs: Set<UUID>; var workouts: [CompletedWorkout]; var calorieGoal: Int; var proteinGoal: Int; var cartHasItems: Bool; var hasStock: Bool; var ledger: [LoopEvent]; var now: Date; var calendar: Calendar }`
  - `enum DailyLoop` statics: `keptDays(_:) -> Set<DayKey>`, `savedDays(_:) -> Set<DayKey>`, `streak(_:) -> Int`, `longestStreak(_:) -> Int`, `week(_:) -> [WeekDot]` (Mon–Sun of the current week; `enum WeekDot { case kept, saved, open, today(kept: Bool), future }` — past unkept days are `.open`, never "missed" in naming), `mood(_ inputs:, justCompleted: Bool, generating: Bool) -> MascotMood`.

- [ ] **Step 1: Failing tests** (calendar: gregorian, `TimeZone(identifier: "Europe/Vilnius")`, Monday first; helper `entry(at:)` builds a `FoodLogEntry`):
  - `testEntriesAtMidnightFallOnTheirOwnDays` (23:59 vs 00:01 → 2 kept days)
  - `testStreakCountsBackThroughHistory` (kept 20 days ending yesterday, today empty → 20)
  - `testTodayKeptAddsToStreak` (… + today entry → 21)
  - `testGapBreaksStreak` (kept d-5…d-3, missed d-2, kept d-1 → 1)
  - `testSavedDayBridgesButDoesNotAdd` (kept d-3, saverUsed d-2, kept d-1 → 2)
  - `testWorkoutAndBudgetCheckInKeepADay`
  - `testLongestStreak`
  - `testWeekRowMarksTodayAndFuture`
  - `testMoodNewUserIsHappy` (no history → `.happy`)
  - `testMoodWorriedAfterSixWhenNotKept` (streak ≥ 1, 18:30, today empty → `.worried`; 17:59 → `.happy`)
  - `testMoodSleepyOnlyAfterLosingStreakOfTwo` (kept d-3, d-2, missed d-1 → `.sleepy`; kept only d-2 → `.happy`)
  - `testMoodJustCompletedCelebratesAndGeneratingThinks` (generating wins over everything)
  - `testMoodLoveOnPerfectDay` (ledger `perfectDay(today)`)
- [ ] **Step 2:** Run `-only-testing:smartmarketTests/DailyLoopTests` → compile failure.
- [ ] **Step 3:** Implement. Mood order: generating → thinking; justCompleted → celebrate; perfectDay today → love; today kept → happy; not kept, hour ≥ 18, streak ≥ 1 → worried; yesterday unkept & unsaved and the run ending the day before was ≥ 2 → sleepy; else happy.
- [ ] **Step 4:** Run → PASS.
- [ ] **Step 5:** Commit `Daily loop engine: kept days, streak, week row, mood`.

### Task 2: Quests

**Files:** Modify `smartmarket/Models/DailyLoop.swift`; Test `smartmarketTests/DailyQuestTests.swift`

**Interfaces:**
- Produces: `enum QuestID: String, Codable, CaseIterable { case logAny, breakfast, threeMeals, protein, onTarget, workout, anyWorkout, fromStock, newFood, budget }`; `enum QuestDestination { case logFood, train, shop, stock }`; `struct Quest: Identifiable, Equatable { let id: QuestID; let title: String; let symbol: String; let current: Double; let goal: Double; let unit: String; let isDone: Bool; let destination: QuestDestination }`; `DailyLoop.quests(for day: DayKey, _ inputs: LoopInputs) -> [Quest]` (always 3, slot 0 easy); `DailyLoop.isPerfect(day:_:) -> Bool`.
- Titles, done rules and filters exactly from the spec's pool table. Easy ids: logAny, breakfast, anyWorkout. Workout ids (workout, anyWorkout) offered only when `dayNumber % 7` ∈ {0, 2, 4, 5} (dayNumber = days since 2001-01-01 in the calendar). `budget` done = `budgetCheckIn(day)` in ledger. `onTarget` done for today only when hour ≥ 17. `newFood` = an entry today whose `foodId` (non-nil) never appears on an earlier day.

- [ ] **Step 1: Failing tests:**
  - `testThreeQuestsEasyFirst` (for 30 consecutive days: count 3, slot 0 ∈ easy, no duplicates)
  - `testSelectionIsStableForADay` (same inputs twice → same ids; different day → not always same over 7 days)
  - `testNewUserGetsNoTargetQuests` (calorieGoal 0 → no protein/onTarget)
  - `testBudgetNeedsCartItems`, `testFromStockNeedsStock`
  - `testWorkoutQuestsAtMostFourDaysAWeek`
  - one done-rule test per quest id: `testDone_logAny` … `testDone_budget` (10 tests, each building minimal inputs that satisfy the rule and one just short of it), incl. `testOnTargetNotDoneBeforeFive`, `testProteinProgressReports62Of90`.
  - `testPerfectDayWhenAllThreeDone`
- [ ] **Step 2:** Run `-only-testing:smartmarketTests/DailyQuestTests` → fail.
- [ ] **Step 3:** Implement. Selection: from available ids, slot 0 = easy ids sorted by `hash(dayNumber, id)`; slots 1–2 = remaining non-easy available ids sorted by the same hash; if fewer than 2 non-easy, fill with remaining easy ids. Use a stable hash (e.g. FNV-1a over `"\(dayNumber)-\(id.rawValue)"`), never `Hasher`.
- [ ] **Step 4:** Run → PASS. **Step 5:** Commit `Daily quests: pool, selection, done rules`.

### Task 3: Savers and milestones

**Files:** Modify `smartmarket/Models/DailyLoop.swift`; Test `smartmarketTests/StreakSaverTests.swift`

**Interfaces:**
- Produces: `DailyLoop.saverEvents(_ inputs: LoopInputs) -> [LoopEvent]` (new `saverEarned`/`saverUsed` events to append, idempotent: running again after appending returns []), `DailyLoop.saversHeld(_:) -> Int`, `DailyLoop.milestoneEvent(_:) -> LoopEvent?` (today kept and streak ∈ {3,7,30,100,365} and no `milestone(today, n)` yet).
- Algorithm: walk days from `loopStarted` to yesterday in order with `run` (consecutive kept since loopStarted) and `held` (ledger earned so far − used so far). Day with `saverUsed` in ledger → saved, run unchanged. Kept → run += 1; if run % 7 == 0: if `saverEarned(day)` in ledger → held += 1, else if held < 2 → emit earned, held += 1. Not kept, not saved → if (run > 0 or previous day saved) and held > 0 → emit used, held −= 1; else run = 0.

- [ ] **Step 1: Failing tests:** `testEarnsOneSaverPerSevenKeptDays`, `testHoldsAtMostTwo`, `testSaverFillsMissedDay`, `testFiveMissedDaysWithTwoSaversSavesFirstTwo` (streak afterwards 0), `testNoSaversBeforeLoopStarted` (history before start earns nothing), `testSaverEventsAreIdempotent`, `testMilestoneOnceAtSeven`, `testNoMilestoneWhenTodayNotKept`.
- [ ] **Step 2:** Run → fail. **Step 3:** Implement. **Step 4:** Run → PASS. **Step 5:** Commit `Streak savers and milestones`.

### Task 4: DailyLoopStore

**Files:** Create `smartmarket/Services/DailyLoopStore.swift`; Test `smartmarketTests/DailyLoopStoreTests.swift`

**Interfaces:**
- Consumes: Tasks 1–3.
- Produces: `@MainActor @Observable final class DailyLoopStore { static let shared; init(defaults: UserDefaults = .standard, inputs: @escaping @MainActor () -> LoopInputsSource = .live); private(set) var state: LoopState; private(set) var lastCompletion: Date?; private(set) var pendingMilestone: Int?; func refresh(now: Date = Date()); func cartChanged(now: Date = Date()); func consumeMilestone() }` where `struct LoopState: Equatable { var streak: Int; var longest: Int; var quests: [Quest]; var week: [WeekDot]; var saversHeld: Int; var todayKept: Bool; var perfectToday: Bool }` and `LoopInputsSource` returns everything in `LoopInputs` except `ledger/now/calendar` (`.live` reads `FoodLogStore.shared.allEntries`, `StockStore.shared.logs` ids, `StockStore.shared.items`, `WorkoutStore.shared.completed`, `AppState.shared.userProfile.dailyCalorieGoal`, `AppState.shared.bmrData?.macros.protein ?? 0`, `ShoppingCartService.shared` items/total/weeklyBudget).
- `refresh`: load ledger; if no `loopStarted`, append `loopStarted(today)`; append `saverEvents`; for each today quest done without a `questDone(today,id)` → append it and set `lastCompletion = now`; perfect day → append `perfectDay(today)` once; milestone → append and set `pendingMilestone`; persist; recompute `state`.
- `cartChanged`: if cart has items and total ≤ weeklyBudget and no `budgetCheckIn(today)` → append, then `refresh`.
- Ledger persisted as JSON `[LoopEvent]` under `progressLedger`, loaded with `ResilientStorage.loadArray`.

- [ ] **Step 1: Failing tests** (fresh `UserDefaults(suiteName:)` per test, a stub source):
  - `testFirstRefreshStartsLoopOnce`
  - `testQuestCompletionRecordedOnceAndSetsLastCompletion` (refresh twice → one `questDone`, `lastCompletion` set only the first time)
  - `testDeletingEntryUnticksQuestButKeepsRecord` (Review Focus 2)
  - `testCartCheckInOnlyAfterCartChange` (refresh with in-budget cart → no check-in; `cartChanged` → check-in, today kept)
  - `testOverBudgetCartDoesNotCheckIn`
  - `testLedgerSurvivesReload` (new store on same defaults sees same streak)
  - `testMilestonePendingThenConsumed`
- [ ] **Step 2:** fail. **Step 3:** Implement. **Step 4:** PASS. **Step 5:** Commit `DailyLoopStore: ledger, refresh, budget check-in`.

### Task 5: Evening nudge

**Files:** Create `smartmarket/Services/StreakNudge.swift`; Modify `smartmarket/Services/ReminderStore.swift` (persisted `streakNudgeOn: Bool`, default true, `func setStreakNudge(_:) async`), `smartmarket/Features/Profile/RemindersView.swift` (row "Streak nudge" with subtitle "One evening note if today doesn't count yet", SF Symbol `bolt.heart`), `smartmarket/App/SmartMarketAgentApp.swift` (on `.background`: schedule; on `.active`: `DailyLoopStore.shared.refresh()`); Test `smartmarketTests/StreakNudgeTests.swift`

**Interfaces:**
- Produces: `enum StreakNudge { static func plan(now: Date, todayKept: Bool, streak: Int, calendar: Calendar) -> [(id: String, fire: Date, body: String)]; static func reschedule(store: ReminderStore, loop: LoopState, scheduler: ReminderScheduling, now: Date) async }` — `reschedule` removes all pending `streak_` ids, then adds the plan only if `store.isEnabled && store.streakNudgeOn`. Ids `streak_yyyy-MM-dd`. Title "Nourlo". Bodies verbatim from spec (today / tomorrow kept-or-not / day 3). Days whose 20:00 has passed are skipped.
- `DailyLoopStore.refresh` calls `StreakNudge.reschedule` when `todayKept` flips to true.

- [ ] **Step 1: Failing tests:** `testPlanSkipsTodayWhenKept`, `testPlanTodayNamesStreak` (body contains "12-day"), `testTomorrowCopyWhenTodayNotKept` ("Nourlo misses you…"), `testThirdEveningCopy`, `testNoStreakCopyWhenStreakZero` (today body is the "misses you" copy), `testAfterEightSkipsToday`, `testRescheduleRemovesAndAddsNothingWhenRemindersOff` (fake scheduler records calls; Review Focus 5), `testRescheduleAddsThreeWhenOn`.
- [ ] **Step 2:** fail. **Step 3:** Implement. **Step 4:** PASS. **Step 5:** Commit `Evening streak nudge`.

### Task 6: Home — quest card, Nourlo badge and moods, milestone toast

**Files:** Create `smartmarket/Features/Home/Sections/DailyQuestCard.swift`; Modify `smartmarket/Features/Home/HomeView.swift` (card after `CalorieSummaryCard`; `refresh()` on appear and on change of `FoodLogStore.shared.entries.count`, `WorkoutStore.shared.completed.count`; milestone toast), `smartmarket/Features/Home/Sections/HomeHeaderView.swift` (`HeaderBowl` mood from `DailyLoop.mood`, celebrate 1.8 s when `lastCompletion` changes; streak number badge, accessibility "12-day streak"), `smartmarket/Services/ShoppingCartService.swift` call site or an observer of `.cartDidChange` → `DailyLoopStore.shared.cartChanged()`, `smartmarket/Utilities/Constants.swift` (`static let openShop`), `smartmarket/App/MainTabView.swift` (handle `.openShop` → selection 2); Test: render `DailyQuestCard` in `smartmarketTests/MascotSnapshotTests.swift`-style snapshot to `/tmp/mealio-run/loop/`.

- Card: header "🔥"-free — Nourlo-free too (the bowl is in the header); title "Today's quests", trailing "N-day streak" + savers as `shield.fill` count; three rows (symbol, title, progress text like "62 / 90 g" or a check, thin progress bar, done rows struck through softly in `brandPrimary`); Mon–Sun dots. Rows are buttons: logFood → `vm.openLog()`, train → post `.openTrain`, shop → post `.openShop`, stock → push `StockView` if Home can, else `.openShop`. Accessibility id `home.quests`, row ids `quest.<id>`; label "Quest, <title>, <current> of <goal>, done/not done".
- Milestone toast: reuse the style of `UndoToast` without the undo button, text "N-day streak! Nourlo is proud of you.", 3 s, then `consumeMilestone()`; header celebrates.

- [ ] **Step 1:** Write `testRenderQuestCard` snapshot (light/dark, one done row, one partial) — runs and writes files.
- [ ] **Step 2:** Implement UI; full build 0 warnings.
- [ ] **Step 3:** Read the snapshots; fix layout.
- [ ] **Step 4:** Run all loop tests + `ReleaseSmokeTests/testOnboardingAndAllTabs`; check the smoke test still finds its ids (the new card must not push required controls out of reach).
- [ ] **Step 5:** Commit `Home: daily quests, streak badge and Nourlo's moods`; `scripts/install-phone-test.sh`.
