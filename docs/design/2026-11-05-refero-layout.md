# Mealio: layout refinement

Reference lock: retain the owner's approved Almond / Dull Pink / Rhino system.
Direct refinement of the existing product, not a new visual direction or journey.

Research and bounded roles:
- FoodNoms style 4c7e1e62-5c2d-4874-9640-ccbf7d88b5e8: strong hierarchy,
  readable nutrition summaries. Owner's palette overrides its rainbow colors.
- FoodNoms iOS 2eb299b0-87ab-4fab-b6ca-ceeb7f0e7f85: compact Today/date,
  distinct summary and meal log; do not duplicate its floating overlapping action.
- Crouton iOS 1a24aee7-ded0-4389-828d-f9475a033e37: clear top/content/bottom
  regions and scan-friendly grocery rows; adapt this density to store navigation.
- Flo iOS 94e81e0c-a46c-4c1e-afb0-bd86fc6e32b4: settings grouped by purpose.

Decision ledger:
- One consumed/goal ring plus remaining/above-goal readout instead of repeated
  consumed totals. Source: FoodNoms hierarchy + existing calorie data.
- Primary Log food in the summary, per-meal add retained; remove redundant floating
  action that covered meal rows. Source: observed local screenshot overlap.
- Macro rows preserve accessible 44pt explanation buttons with room for values.
- Navigation is a sibling below TabView, reserving real space on all devices.
- Suggestions join the scrolling content instead of covering dashboard controls.
- Store rows use named destinations; catalog size and estimate disclosure appear
  once, fully readable. No branch stock or current-price claims.
- Daily targets form consistent settings rows. Source: Flo grouped settings.
- Large-text meal, recipe and product details stack instead of squeezing columns.

No network, model, pricing, synchronization, permission or deletion logic changes.

## Verification

- Nineteen native tests passed in /tmp/MealioReferoLayoutUI.xcresult.
- Standard onboarding/all five tabs and largest-text onboarding/all five tabs passed.
- The first information-button test failed on floating-point conversion:
  43.99999999999994 versus 44. An assertion-only 0.001pt numerical tolerance
  retains the 44pt requirement; no production hit-target reduction was made.
- The corrected information-button and custom-navigation tests then passed on
  both iPhone 17 and iPad in /tmp/MealioReferoLayoutVerification.xcresult.
  That bundle reports two unique tests, each exercised on both destinations.
- Dedicated iPhone SE rendered for small-screen review. Light/dark screenshots
  inspected against the retained palette and compact hierarchy reference lock.
- Final Release build /tmp/MealioReferoLayoutFinal.log: zero warnings/errors.
- Release bundle guard passed; nine packaging/privacy checker regressions passed.
- No sale, savings, or price-comparison language introduced. Existing grocery
  completion strikethrough affects item names only.

Previews: /Users/mmostafasalem/Mealio-Design-Previews/refero-layout-*.png.
No publication, merge, or push performed.
