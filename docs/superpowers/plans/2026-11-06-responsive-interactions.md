# Responsive iOS interactions

## Reference lock
User's ten screenshots define interaction behavior, not a new visual skin.
Preserve Almond #F4DAD4, Dull Pink #DD8C96, Rhino #2E4060, existing semantic
surfaces/type, 44pt controls and native SwiftUI sheets. Refero's motion craft:
short, interruptible feedback, no decorative loops with Reduce Motion enabled.

## Decisions and work
- Skeletons: recipe content shaped placeholders; shared shimmer pauses for Reduce
  Motion, background scenes and Low Power Mode. Preserve existing meal skeletons.
- Optimistic updates: keep synchronous durable local cart/log/checklist updates;
  CloudKit retries separately. Never fabricate AI, account or deletion success.
- Command menu: searchable Quick Actions sheet for screens and local actions,
  accessible in bottom navigation, with Command-K on a hardware keyboard.
- Shortcut hints: visible in the menu, actual shortcuts on the tab controls and
  Save actions. Touch interaction remains primary, including on iPad.
- Undo: replace routine cart/checked-list confirmation with an eight-second undo;
  restore deleted cart quantities and bought flags without erasing newer edits.
  Cancelled expiry tasks cannot hide a newer undo. Privacy deletion stays confirmed.
- Stale while revalidate: preserve Home data and meal plans during refresh; show
  an Updating cue instead of replacing usable content with skeletons. Load saved
  product catalog before network and do not mark a failed refresh as fresh.
- Pre-rendering: native equivalent is prepare local screen/search data, no extra
  AI/API calls to prefetch destinations. Keep tab and search transitions responsive.
- Blurry images: no remote images exist in this app. Do not invent imagery, fake
  network delays, dead image components or blur readable cached content.
- View transitions: consistent short fades/value transitions, Reduce Motion-aware.
- Swipe to dismiss: native drag handles/detents for read-only and quick-action
  sheets, with explicit Done/Close for accessibility. Keep appropriate large log UI.

## Verification
Regression tests for cart/manual undo, quantity merge, cancelled expiry and account
reset invalidation; native tests and UI checks for Quick Actions/search, sheet
close and tab navigation; Release build, privacy/package tests and visual QA.
No new dependencies, palette change, AI requests, backend work or deployments.

## Second reference batch (added while implementing)
- Preserve interruptible spring retargeting; do not gate taps behind animations.
- Keep native NavigationStack edge-swipe back rather than an Android-style fake
  predictive-back overlay. Verify a store/product push can swipe back.
- Expand small quantity, log and dismissal controls to 44pt; retain safeAreaInset
  for fixed CTAs/toasts and real layout space for bottom navigation.
- Apple sign-in has no SMS entry field: do not invent OTP authentication.
- Extend monospaced digits to remaining prices/account counters; continuous
  rounded rectangles on shared surfaces. Balance multi-line onboarding copy.
- Add per-person, payload-bound AI idempotency keys: duplicate transport requests
  cannot re-run a provider call or charge credits twice. Store short-lived hashed
  request metadata, with no health/chat bodies persisted to disk. Replay availability is
  limited to a bounded in-memory response cache; durable claims prevent reruns
  after worker restarts. Test concurrency, conflicts, restart and expiry.
- No hover submenus exist: use direct touch navigation; no synthetic safe triangle.

Implemented and locally verified. See ../../design/2026-11-06-responsive-interactions.md
for per-pattern coverage, reproduced failures, fixes and remaining activation limits.
