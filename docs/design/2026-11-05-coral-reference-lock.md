# Mealio: Ink, White, Coral

Selected by the owner on 2026-11-05. iOS presentation only.

## Reference lock

Primary: Superpower, Refero style 589c0a33-a38c-4f77-a7b0-bf0c602c937d.
Preserve crisp monochrome hierarchy, generous clear space, rare action accent,
pill actions and restrained surface separation. Do not copy photographic marketing
heroes into a task-oriented nutrition dashboard.

Borrow Todoist's legible task grouping and near-flat surfaces (style
d9a3223e-d0d5-436b-aa09-0facd1805a1e). FoodNoms iOS screens
8bc196a0-58bd-4e16-8b9a-e13b9c92b695 and
4fba8767-e42b-4224-905d-6177ff5285eb inform clear meal sections,
visible Add Food entry points and readable nutritional summaries, not their rainbow.
Seed was evaluated and rejected as the dominant style after owner chose monochrome.

## Decisions

- Ink #18181B and white #FFFFFF form the canvas, typography and navigation base.
- Coral #FF7868 fills primary controls, with ink text for contrast. A deeper coral
  #B6372B supports accessible text links on white; #FF9385 supports dark surfaces.
- Gray values and subtle coral washes are tonal derivatives, not additional accents.
- Macro labels, symbols and values carry category distinction instead of hue.
- SF system typography retains native Dynamic Type. No copied proprietary fonts.
- Near-flat cards, fine separators, no glow, decorative blur or colored store chrome.
- Home's memorable move: open two-line daily heading and clean coral energy arc.
- Existing safe areas, tab identifiers, privacy consent, shopping sync, reset behavior,
  estimates/provenance and network behavior remain intact.
- Product emoji and system map cartography are content, not brand palette tokens.

## Verification

Run simulator build and UI smoke suite, inspect light/dark Home and all five tabs,
then check largest Dynamic Type layouts. Never describe this as shipped or uploaded.

### Recorded checks (2026-11-05)

- Initial dark-mode run: 4 UI checks passed (onboarding/all tabs, largest text,
  metric info touch target, custom navigation). Result: /tmp/MealioCoralUI.xcresult.
- Light-mode regression run: 23 passed, 0 failed (19 native + the same 4 UI
  checks). Result: /tmp/MealioCoralFinalLight.xcresult.
- Following screenshot review, corrected floating action clearance, store disclosure
  wrapping, secondary text contrast and large-text banner arrangement. Those final
  presentation corrections were compiled in a fresh successful Release build:
  /tmp/MealioCoralReleaseChecked.log (0 compiler warnings/errors).
- Packaged Release app passed scripts/check-ios-bundle.py; privacy/legal files
  remain present, backend and build-secret files remain excluded.
- Packaging/privacy checker regression suite: 9 passed.
- Palette contrast: ink/coral 6.87:1, light coral link/white 5.88:1,
  dark coral link/elevated surface 7.56:1.
- Final honesty grep: only purchased grocery-name completion uses strikethrough;
  no price comparisons, savings or sale claims introduced. Legacy discountPrice
  wire fields remain displayed exclusively as single estimated prices.
- No backend, models, persistence, sync or business-rule changes. No store upload.

Review previews under /Users/mmostafasalem/Mealio-Design-Previews.
