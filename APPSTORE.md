# Nourlo — App Store submission checklist

A practical list of what's done and what you must complete in App Store Connect /
Xcode before submitting. Simulator compilation is not release certification;
signed-device and TestFlight checks remain required.

## Already done (in code)
- Bundle ID `com.mostafa.mealio`, display name **Nourlo**, iOS 17 deployment target.
- App icon (1024×1024, opaque): flat bowl mascot on Rhino navy, final as of 2026-11-13. Source: `docs/brand/app-icon.swift`.
- `PrivacyInfo.xcprivacy` declares precise location, separate Health and Fitness
  categories, and Other User Content for optional chat/private shopping sync.
  Online health/fitness and user content are conservatively marked linked;
  free-form chat can identify its author and private sync uses an Apple Account.
  No tracking domains; UserDefaults reason `CA92.1` remains declared. User ID and Product Interaction
  are linked for optional Apple AI accounts and usage limits; not tracking.
- `ITSAppUsesNonExemptEncryption = false` (no export-compliance prompt).
- Location usage string set (`NSLocationWhenInUseUsageDescription`).
- Optional private shopping sync implemented; health/profile/intake/meal-plan
  data excluded under App Review 5.1.3(ii). See `ICLOUD_SETUP.md` for activation
  and live acceptance checks. CloudKit production readiness is not yet verified.

## You must do
1. **Apple Developer Program** membership; register the App ID `com.mostafa.mealio`.
2. **Signing**: set your team + automatic signing in Xcode (Release config).
3. **App icon**: done (flat bowl mascot on navy).
4. **Screenshots** for the iPhone and iPad sizes required in App Store Connect.
   This target supports both device families; iPhone-only QA is insufficient.
5. **Privacy Policy URL** — host `PRIVACY.md` (e.g. GitHub Pages / your site) and
   put the URL in App Store Connect.
6. **Support URL** — host `SUPPORT.md` and add the URL.
7. **App Privacy "nutrition label"** in App Store Connect — declare:
   - Location (Precise): App Functionality; **not** linked to identity; not used for tracking.
   - Health and Fitness: App Functionality; linked for optional online context;
     not tracking. Data kept solely on-device is not transmitted by that fact alone.
   - Other User Content: optional chat and private shopping content; linked;
     App Functionality; not tracking.
   - Review provider retention and the final submitted build before confirming
     answers. No analytics/ads/tracking does not mean no user-content collection.
8. **Category**: Health & Fitness (or Food & Drink). **Age rating** questionnaire.
9. **Backend deployed** (Render) and reachable over HTTPS; set `API_BASE_URL` and,
   activate auth before public release. Inject `API_KEY` through the gitignored
   local configuration; it must match Render's `APP_API_KEY`.

## Recommended before launch
- Pricing launch scope: curated estimates with user-entered corrections. Never advertise live prices, promotions or verified stock without a verified source.
- Decide on the nutrition-accuracy disclaimer placement (already shown on the meal plan).
- Native unit/UI targets are present; execute the release checks and review results.
- Activate and verify per-person Apple AI authentication in addition to the shared app key.

## Health-app review note
Apple scrutinises calorie/health apps. The in-app "values are estimates"
disclaimer and this policy help; avoid medical claims in your store copy.

## Personal AI account release gate
Sign in with Apple and daily credits are implemented locally; real-device testing
needs Apple capability/provisioning and durable backend activation. Follow
[the setup checklist](docs/AI_ACCOUNTS_SETUP.md). App Privacy must include linked
User ID and Product Interaction for functionality. Give App Review working sign-in,
AI consent and account deletion instructions. Do not claim live AI availability
before device and provider checks pass.
