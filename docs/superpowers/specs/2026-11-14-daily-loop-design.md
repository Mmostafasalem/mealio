# Nourlo daily loop: quests, streak and Nourlo's moods

Date: 2026-11-14 · Status: draft for owner approval (builder check done; calls marked "my call") · Project 1 of 3

## Why
The owner wants Nourlo to be a product people come back to every day, not a
one-time tool, inspired by Duolingo (streak, daily goals, the evening nudge)
and Finch (a character you care about). Nourlo now has the faces for this
(celebrate, worried, sleepy, love, cheeky); nothing yet ties them to how the
user is doing over days.

The three projects, in order:
1. **Daily loop (this doc):** quests, streak, streak savers, Home quest card,
   Nourlo's streak moods, the evening nudge.
2. Rewards: berries (currency), Nourlo's shelf, toppings / accessories /
   glazes drawn for the bowl. Leagues later, once accounts exist.
3. Big moments: full-screen milestone celebrations and a weekly recap.

## Decided by the owner
- **A kept day = any healthy action** (option C): logging food, finishing a
  workout, or keeping the cart within budget.
- **Fun and engaging like Duolingo**, but no childish gamification and no
  notification spam (original brief).
- **Rewards: collect now, leagues later** (option C).
- **Nudge: one evening nudge, only when the streak is at risk, only for
  users who switched on the Reminders bell** (option A).
- **Approach A:** quests and streak are worked out from data Nourlo already
  records; only claims and savers are stored.
- Order: daily loop → rewards → big moments.

## Goals
- A user opening Nourlo sees in one glance: their streak, today's three
  quests and how close each is, and how Nourlo feels about it.
- Quests tick themselves when the user acts anywhere in the app; nothing to
  tap "done".
- Users already logging food get a streak from their real history on day one.
- One missed day does not wipe a long streak (savers).

## Non-goals (this project)
- Berries, the shelf, collectibles (project 2). Quest completions are
  recorded so project 2 can pay out for them.
- Full-screen milestone celebrations, weekly recap (project 3). Here a
  milestone only triggers Nourlo's celebrate mood in the header.
- Leagues, friends, any server or account work.
- Changing how food logging, workouts, stock or the cart work.

## Anti-goals
- Guilt. Copy never scolds; a missed day shows a sleepy Nourlo, not a red X.
- Quests that push eating less. No "eat under X kcal" quest; the calorie
  quest is "land close to your target" and only offered when a target exists.
- More than one streak notification a day, or any when reminders are off.

## Approaches considered
- **A. Derive from existing data (chosen).** Quest progress and kept days are
  computed from `FoodLogStore`, `StockStore`, `WorkoutStore` and the cart.
  Only claims, savers and budget check-ins are stored. Deleting a logged meal
  un-ticks its quest automatically; history counts back.
- B. Separate progress record written by every action: duplicates the truth,
  every screen must remember to update it.
- C. Server-side progress: needs accounts and backend; blocks on work the
  app doesn't have.

## Design

### Kept day and streak
- A **day** is a local calendar day.
- A day is **kept** if any of these happened on it:
  - a food log entry (`FoodLogStore.allEntries`, which includes stock use),
  - a completed workout (`WorkoutStore.completed`),
  - a **budget check-in** recorded that day (below).
- **Streak** = number of consecutive kept-or-saved days ending yesterday,
  plus today if today is already kept. Today not yet kept never breaks it.
- History counts back: a user with 20 days of logs sees a 20-day streak.
- **Longest streak** is computed the same way over all history.

### Streak savers (Duolingo's freeze)
- Earned: one for every 7 consecutive kept days (day 7, 14, 21 …), held at
  most 2. Stored.
- Used automatically: when the streak would break on a missed day and a
  saver is held, the day is marked **saved** (stored with its date). Savers
  are applied when the app next opens, for each missed day since the last
  open, oldest first, while savers remain.
- A saved day keeps the streak but does not add to it.
- Project 2 lets users also buy savers with berries.
- **First launch of this version** (my call): the ledger stores
  `loopStarted(day)`. The streak still counts back through real history
  (rule above), but savers are only earned for kept days from that date on
  and only fill missed days after it. No retroactive savers, no back-filled
  gaps, so the first number a user sees is honest and never needs
  correcting.

### Daily quests
- Three quests per day, chosen deterministically from the date (same three
  all day, stable across launches) from the pool below, filtered by what
  applies to the user. Slot 1 is always an easy one, so "one quest" is
  always within reach.
- Each quest has: id, title, SF Symbol, progress (current / goal), done.
- **Pool** (all derived from today's data):
  | id | Title | Done when | Slot |
  |---|---|---|---|
  | logAny | Log something you ate | ≥ 1 food entry | easy |
  | breakfast | Log breakfast | entry in `.breakfast` slot | easy |
  | threeMeals | Log 3 meals | entries in ≥ 3 distinct meal slots | 2/3 |
  | protein | Hit your protein | protein ≥ 80 % of target (from `BMRCalculator.macroTargets`) | 2/3 |
  | onTarget | Land near your calories | ≥ 2 meal slots logged and total within ±10 % of target; only after 17:00 counts as done | 2/3 |
  | workout | Move for 20 minutes | completed workouts today total ≥ 20 min | 2/3 |
  | anyWorkout | Do any workout | ≥ 1 completed workout | easy |
  | fromStock | Cook from your stock | ≥ 1 stock-use entry today | 2/3 |
  | newFood | Try something new | an entry whose food id never appeared before today | 2/3 |
  | budget | Shop within budget | cart has items and total ≤ weekly budget, checked in today | 2/3 |
- Filters: protein/onTarget need a calorie target; budget needs a cart with
  items; fromStock needs stock items; workout quests are
  offered on at most 4 days a week (so they don't dominate).
- **Perfect day** = all three quests done.
- **Budget check-in** (my call): the cart has no dated history, so a
  check-in is recorded for a day only when the user **acts on the cart** that
  day (`.cartDidChange`: add/remove/quantity, or a budget change) and
  afterwards the cart has items and its total is within the weekly budget.
  Merely opening the app with an old in-budget cart does not count, so the
  streak can't become automatic. The budget quest is offered only when the
  cart has items (the budget always has a value, 60 by default).

### What is stored (new key `progressLedger`, on this device only)
A small dated list, append-only except for deletion of personal data:
- `questDone(day, questId)` — first time a quest was seen done (drives the
  one-time celebration and project 2's payout). If the user deletes the
  entry that made it done, the quest shows undone again but the record
  stays (no clawback; project 2 pays once).
- `perfectDay(day)`
- `budgetCheckIn(day)`
- `saverEarned(day)`, `saverUsed(day)` (the day it saved)
- `loopStarted(day)`

**Not synced** (my call): the app keeps health data out of iCloud by design
(`SyncDataPolicy`: "Health data is never eligible", App Review 5.1.3(ii)),
and food logs and workouts don't sync, so another device couldn't compute
kept days anyway. The ledger stays on the device like the food log. It is
cleared by the existing "delete my data" path (`LocalDataEraser`).

### Home
- **Quest card** directly under `CalorieSummaryCard`: streak count with a
  flame-free bowl badge, the three quests with progress, a Mon–Sun row of
  dots (kept / saved / missed / today), savers held. Tapping a quest goes to
  where it is done (Log food sheet, Train, Shop, Stock).
- **Header bowl** (`HeaderBowl`) gets a small streak number badge and its
  mood from the loop:
  | Situation | Mood |
  |---|---|
  | Quest just completed (this session) | celebrate (1.8 s), then back |
  | Perfect day | love |
  | Today kept | happy |
  | Not kept yet, after 18:00, streak ≥ 1 | worried |
  | Yesterday missed and it ended a streak of ≥ 2 days (no saver) — today only | sleepy |
  | Otherwise, including brand-new users | happy (today's default) |
  Meal-plan generation still shows thinking, as now.
- Milestones 3 / 7 / 30 / 100 / 365 days: header celebrate + a one-line toast
  this project; full screen in project 3.

### Evening nudge
- Only when Reminders are enabled and the new **Streak nudge** row in
  `RemindersView` is on (default on once reminders are enabled).
- One local notification at 20:00 on a day not yet kept, when streak ≥ 1.
- Scheduling: whenever the app goes to background and whenever today
  becomes kept, remove pending streak nudges (ids prefixed `streak_`) and
  schedule one-off nudges for the next 3 evenings (skipping today if kept).
- Copy (playful, no guilt):
  - today: "Nourlo's getting sleepy… one quest keeps your N-day streak."
  - tomorrow, if today is kept: same with N+1; otherwise "Nourlo misses
    you. Log one thing to start a new streak."
  - day 3: "Nourlo saved you a spot. One quest is all it takes."
- Tapping opens Home.

### Copy and tone
Short, warm, a little cheeky. Never "you failed", "you broke", "you
missed". Examples: "3 for 3. Nourlo is thrilled.", "One quest and today
counts.", "Day saved, thanks to your streak saver."

## Constraints
- iOS 17, SwiftUI, `@Observable` `@MainActor` stores, UserDefaults only
  (CLAUDE.md conventions). No third-party code. SF Symbols only.
- Offline: everything works with no network.
- Accessibility: quest card readable by VoiceOver as "Quest, 62 of 90 grams,
  not done"; Dynamic Type up to accessibility sizes; Reduce Motion respected
  (Nourlo already handles it).
- Performance: quest and streak calculation runs on today's and history's
  entries in memory; must stay fast with a year of logs (cache per-day keys).

## Testing
- Unit tests for kept-day and streak math (gaps, savers, today not kept,
  history back-fill, time zones / midnight), quest selection determinism,
  each quest's done rule, saver earning and auto-use, nudge scheduling
  (which ids, which copy, nothing when reminders are off).
- Snapshot of the quest card; UI smoke test still passes; install on phone.

## Left to the builder
Exact card layout and styling within the Home grid, quest selection
algorithm details beyond "deterministic by date with an easy slot 1",
animation of a quest ticking, toast styling.
