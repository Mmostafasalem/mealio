# Nourlo character look Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Recolour the existing Nourlo bowl to brand pink with blueberries, and add wink, glance, heart-eye, asleep and worried faces plus confetti, Zzz, thought dots, sweat drop and floating hearts, driven by three new moods.

**Architecture:** Everything stays inside the existing rig: `MascotRig` gains spring channels for the new face parts and extras and composes them from `MascotMood`; `MascotPose` carries them; `MascotFigure`/`MascotArt` draws them. No new views, no assets.

**Tech Stack:** SwiftUI Canvas, Observation, XCTest. iOS 17.

**Spec:** `docs/superpowers/specs/2026-11-14-nourlo-character-look-design.md`

## Global Constraints
- Keep the current bowl shape, oats, banana coins, strawberries, navy feet; no spoon.
- Body/arms pink: light #F7A5B8, base #E8698A, shade #D4587A, deep #BD4A6B.
- New moods: `cheeky`, `worried`, `love`; existing moods keep their names.
- SF Symbols only, no image assets. No behaviour change outside the mascot except chat failure → `.worried`.
- Reduce Motion: no drifting/looping extras; extras still cross-fade in and show still.

## Review Focus
1. Reduce Motion on: every new mood still shows its face and extras (static). Test in Task 1.
2. Mood switch blends: from `.celebrate` to `.idle` the confetti fades to 0. Test in Task 1.
3. 36 pt chat header / 44 pt Home header: extras must not clip or cover the face. Checked visually in Task 2 snapshots (36 pt render per mood).
4. Dark mode: pink body and extras readable on near-black. Snapshots light + dark in Task 2.
5. Idle battery: `.sleepy`, `.love`, `.worried` must still let the clock rest after the entry life (no endless 30 fps). Test in Task 1 (`clockRests…`).

---

### Task 1: Rig — new moods, face channels and extras

**Files:**
- Modify: `smartmarket/Components/Mascot/MascotRig.swift`
- Modify: `smartmarket/Components/MascotGuideView.swift` (enum `MascotMood` + descriptions)
- Test: `smartmarketTests/MascotMoodTests.swift` (new)

**Interfaces:**
- Produces on `MascotPose` (all `Double`, 0…1 unless noted): `wink`, `smirk`, `hearts`, `asleep`, `worry`, `confetti`, `zzz`, `thought`, `sweat`, `floatHearts`, and `time: Double` (rig seconds, frozen while loops are off; drives drift in Task 2).
- `MascotMood` gains `.cheeky, .worried, .love`.
- `MascotRig.isLively: Bool` (read-only, for the battery test; mirrors the private `lively`).

- [ ] **Step 1: Write failing tests** in `MascotMoodTests` (`@MainActor`), helper `settled(_ mood:, reduceMotion:) -> MascotPose` = new rig, set reduceMotion, `set(mood:)`, `setActive(true)`, `stop()`, `simulate(seconds: 1.5)`:
  - `testCheekyWinksAndSmirks`: wink > 0.9, smirk > 0.9, smile < 0.1
  - `testWorriedShowsBrowsAndSweat`: worry > 0.9, sweat > 0.9, wavy > 0.9, wide > 0.9
  - `testLoveHasHeartEyes`: hearts > 0.9, floatHearts > 0.9
  - `testSleepyClosesEyesWithZzz`: asleep > 0.9, zzz > 0.9, sleepy < 0.1
  - `testCelebrateConfettiAndThinkingDots`: celebrate → confetti > 0.9; thinking → thought > 0.9
  - `testHelpGlancesTowardRaisedArm`: help → lookX > 0.4
  - `testIdleHasNoExtras`: all ten new channels < 0.05
  - `testReduceMotionStillShowsFaces`: with reduceMotion true, cheeky wink > 0.9, love hearts > 0.9, sleepy zzz > 0.9
  - `testConfettiFadesWhenMoodChanges`: celebrate settled, then `set(mood: .idle)`, simulate 1.5 → confetti < 0.05
  - `testCalmMoodsRestAfterEntry`: for `.sleepy, .love, .worried`: setActive(true), set(mood:), simulate(seconds: 10) → `isLively == false`

- [ ] **Step 2: Run, expect compile failure**
  `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project smartmarket.xcodeproj -scheme smartmarket -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:smartmarketTests/MascotMoodTests test CODE_SIGNING_ALLOWED=NO`

- [ ] **Step 3: Implement.**
  - `Expression` gains `wink, smirk, hearts, asleep, worry` and `confetti, zzz, thought, sweat, floatHearts`. Mood table: thinking + thought 1; celebrate + confetti 1; help unchanged; happy unchanged; sleepy = `asleep 1, zzz 1, ooh 0.6` (drop `sleepy`); cheeky = `wink 1, smirk 1, blush 0.7`; worried = `wide 1, wavy 1, worry 1, sweat 1, blush 0.3`; love = `hearts 1, smile 1, floatHearts 1, blush 0.9`.
  - Ten new `S` cases, all `isExpression` (preset k 900 c 60 for face parts; `MotionTokens.fade` for the five extras).
  - Arms/body: cheeky `l raise 0.2, r raise 1.3 lift -4`, tilt −0.06; worried arms `raise 1.0, reach 40` (in toward the face), tilt +0.04; love arms `raise 0.9`, entry `hop()`; help eyes `look (0.7, 0)`.
  - `set(mood:)` entry: cheeky → `wave()` is not used; give a squash pulse like happy. love → `hop()`.
  - `publish()` fills the new pose fields and `time = t`.
  - `MascotMood` descriptions: cheeky "Has an idea", worried "Something went wrong", love "Loves this".

- [ ] **Step 4: Run tests, expect PASS** (same command).
- [ ] **Step 5: Commit** `Mascot rig: cheeky, worried and love moods with extras`

### Task 2: Figure — brand pink, blueberries, new faces and extras

**Files:**
- Modify: `smartmarket/Components/Mascot/MascotFigure.swift`
- Modify: `smartmarketTests/MascotSnapshotTests.swift` (output dir → `/tmp/mealio-run/mascot`; add a 36 pt render per mood)

**Interfaces:**
- Consumes: Task 1 pose fields.

- [ ] **Step 1: Palette** — `MascotPalette` body/arm colours from Global Constraints; rim light #F8B3C3 / rim #F09AAE / rimDeep #D9768F; wall #B9415E, wallDark #9C3350; cheek #FFB3C1.
- [ ] **Step 2: Blueberries** — three berries (radius ~15, #8C9CE8 → #4A5AB5 → #2E3780) on the oats right of the strawberries, sharing fruit springs 3–5 for jiggle (no new springs).
- [ ] **Step 3: Faces** — in `drawEye`/`drawFace`/`drawMouth`: wink turns the right eye into the ∩ arc (left stays open); asleep turns both eyes into ⌣ arcs; hearts replace eyes with red hearts (#FF6B81 → #D63352, white glint); worry draws inner-up brows (separate from `brows`); smirk draws the lopsided smile with a dimple. Each fades by its value, like the existing channels.
- [ ] **Step 4: Extras** — drawn in figure space (unclipped canvas is 1.5× the box): thought dots up-left of the rim; Zzz up-right (rounded heavy font, rhino #2E4060 at 70%, drifting up with `time`); sweat drop beside the right brow; confetti (8 brand-colour bits falling and spinning on `time`, wrapping); floating hearts (3, rising and fading on `time`). Opacity = channel value; with `time` frozen they sit still.
- [ ] **Step 5: Snapshots** — run `-only-testing:smartmarketTests/MascotSnapshotTests` and read every PNG in `/tmp/mealio-run/mascot` (each mood, light/dark, 132 and 36 pt). Fix anything clipped, muddy or covering the face.
- [ ] **Step 6: Commit** `Nourlo: brand pink glaze, blueberries, new faces and extras`

### Task 3: Wire, verify, ship to phone

**Files:**
- Modify: `smartmarket/Features/Home/AgentChatSheet.swift:145` (`.help` → `.worried`)

- [ ] **Step 1:** Change the chat-failure mood.
- [ ] **Step 2:** Full build (CLAUDE.md command) — 0 errors, 0 warnings.
- [ ] **Step 3:** Run `MascotMoodTests`, `MascotSnapshotTests` and `ReleaseSmokeTests/testOnboardingAndAllTabs` — pass.
- [ ] **Step 4:** Commit `Chat: Nourlo looks worried when a reply fails`, then `scripts/install-phone-test.sh` and report it is on the phone.
