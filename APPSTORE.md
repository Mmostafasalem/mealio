# Mealio — App Store submission checklist

A practical list of what's done and what you must complete in App Store Connect /
Xcode before submitting. Simulator compilation is not release certification;
signed-device and TestFlight checks remain required.

## Already done (in code)
- Bundle ID `com.mostafa.mealio`, display name **Mealio**, iOS 17 deployment target.
- App icon present (1024×1024, no alpha) — **placeholder art; replace before launch**.
- `PrivacyInfo.xcprivacy` declares: precise location + health/fitness (not linked,
  not for tracking), UserDefaults reason `CA92.1`, no tracking domains.
- `ITSAppUsesNonExemptEncryption = false` (no export-compliance prompt).
- Location usage string set (`NSLocationWhenInUseUsageDescription`).
- Optional private shopping sync implemented; health/profile/intake/meal-plan
  data excluded under App Review 5.1.3(ii). See `ICLOUD_SETUP.md` for activation
  and live acceptance checks. CloudKit production readiness is not yet verified.

## You must do
1. **Apple Developer Program** membership; register the App ID `com.mostafa.mealio`.
2. **Signing**: set your team + automatic signing in Xcode (Release config).
3. **Real app icon** (replace the placeholder in `Assets.xcassets/AppIcon`).
4. **Screenshots** for required device sizes (6.7" / 6.5" iPhone at minimum).
5. **Privacy Policy URL** — host `PRIVACY.md` (e.g. GitHub Pages / your site) and
   put the URL in App Store Connect.
6. **Support URL** — host `SUPPORT.md` and add the URL.
7. **App Privacy "nutrition label"** in App Store Connect — declare:
   - Location (Precise): App Functionality; **not** linked to identity; not used for tracking.
   - Health & Fitness (your logged calories/macros): App Functionality; not linked; not tracking.
   - No other collection (no analytics/ads/tracking).
8. **Category**: Health & Fitness (or Food & Drink). **Age rating** questionnaire.
9. **Backend deployed** (Render) and reachable over HTTPS; set `API_BASE_URL` and,
   if you enable auth, `API_KEY` in `Info.plist` (must match Render's `APP_API_KEY`).

## Recommended before launch
- Replace sample `deals_data.json` with a real/curated weekly feed (or a data partnership).
- Decide on the nutrition-accuracy disclaimer placement (already shown on the meal plan).
- Add the Xcode unit-test target (see `smartmarketTests/README.md`).
- Consider per-device auth tokens instead of the shared `API_KEY` (see README notes).

## Health-app review note
Apple scrutinises calorie/health apps. The in-app "values are estimates"
disclaimer and this policy help; avoid medical claims in your store copy.
