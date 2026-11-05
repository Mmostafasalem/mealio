# Mealio palette override: Almond / Dull Pink / Rhino

The owner supplied a screenshot and explicitly selected this palette instead of
Ink / White / Coral on 2026-11-05. This is the new color reference lock; existing
Refero-informed layout and interaction choices remain in place.

Exact anchors:
- Almond #F4DAD4: light canvas and foreground on Rhino.
- Dull Pink #DD8C96: action fills, progress, selected-control highlights.
- Rhino #2E4060: primary light-mode text, featured surfaces, dark-mode cards.

Tonal derivatives separate surfaces without additional accent hues. Small links
use Rhino on Almond (7.84:1), not Dull Pink on Almond (1.91:1). Filled pink controls
use deeper Rhino #24334D for small labels (4.99:1). Dark-mode small text uses Almond
on Rhino (7.84:1); the exact pink remains a fill/progress accent.

Shared controls, surfaces, native navigation titles, onboarding, profile settings,
map controls, meals, grocery and shopping presentation adopt these roles. Source
models, networking, pricing, permissions, sync and data deletion are unchanged.

Verification: nine packaging/privacy checker tests pass. Final Release build log:
/tmp/MealioAlmondFinal.log. Simulator previews are saved under
/Users/mmostafasalem/Mealio-Design-Previews/almond-pink-rhino-{light,dark}.png.
The previous full UI suite was not rerun for this color-only change; rendered
light/dark previews and palette contrast were checked directly.
