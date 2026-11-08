# Grainy gradient surface treatment

Reference lock: retain Nourlo's Almond, Dull Pink and Rhino palette, native typography, card radii, navigation and content hierarchy. Adapt the user's IMG_3153 grainy-gradient reference as static color washes with fine monochrome grain. BlueYard's diffuse blush/cream atmosphere supplies the background treatment; Recess supplies pastel transitions anchored by dark, legible text. Their website typography, sharp cards and CTA colors are not adopted.

| Decision | Source and role |
| --- | --- |
| Static fine grain and softly overlapping gradients | User's visual reference; decorative background only |
| Blush/cream wash, cooler blue at the opposite edge | BlueYard atmosphere and existing Nourlo palette |
| Stronger calorie-summary wash, quieter supporting cards | Recess key-section gradients and product UI color restraint |
| Keep text, progress indicators and controls separate from texture | Existing native design system and accessibility contrast |

Implementation: `GrainyGradient` draws opaque brand surfaces with three radial washes and a cached 256×256 monochrome noise tile. No remote assets, animated noise or per-frame random work. Decoration ignores touches and accessibility. Increased Contrast uses the original opaque base surface. Floating navigation remains neutral.

Applied to Home, Meals, Shop, Profile, Stock and Welcome; shared cards receive a lighter treatment, and the calorie card uses the hero variation. Both light and dark appearance have independent wash strengths.

References: https://www.blueyard.com and https://takearecess.com, reviewed through Refero. This is a visual-only change; the earlier AI work remains paused.
