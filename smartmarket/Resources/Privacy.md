# Mealio — Privacy Policy

_Last updated: 2026-10-29_

Mealio ("we", "the app") helps you estimate grocery costs, plan meals, and
track calories. This policy explains what data the app uses and why. We do not
sell your data, show ads, or use third-party analytics or tracking SDKs.

## Information the app uses

- **Location (precise), while in use.** Used only to find grocery deals and
  stores near you. Your location is sent to our backend solely to filter deals
  by proximity for that request; it is not stored or linked to your identity.
  You can deny location access — the app still works using the city centre.
- **Profile & body stats** (name, weight, height, age, gender, goals, dietary
  preferences, favourite foods). Stored **on your device** (profile and computed
  BMR in the iOS Keychain; preferences in local app storage). Used to calculate calorie targets
  and personalise meal plans.
- **Food log** (what you log, calories, macros). Stored **on your device** only.
- **Shopping cart, grocery list, budget and price corrections.** Stored locally.
  If you enable shopping sync in Profile, these and your language setting are
  also stored in your private Apple CloudKit database. No Mealio account is
  required. Profile/body measurements, BMR, food intake, dietary restrictions and
  nutrition meal plans are excluded from this app's iCloud sync.

## Optional shopping sync
Sync starts only after you enable it in Profile and requires an available iCloud
account. The app retries when opened or brought to the foreground; changes may
not appear immediately on other devices. Changes to different list items merge.
Conflicting edits to the same item use a deterministic logical-clock rule;
simultaneous quantities are not added together. Turning sync off retains existing
cloud data. Apple processes CloudKit data under its own terms and privacy policy.

## Information sent to our servers

Online AI features are optional and require the sharing permission in Profile.
When enabled and you generate a meal plan, ask the in-app assistant, or request a recipe, we
send the relevant inputs (e.g. age, gender, weight, height, calorie target, dietary preferences, favourite
foods, shopping list, your message) to our backend, which uses **Groq** (an AI
provider) to generate the response. Product nutrition is looked up from **Open
Food Facts**. We send the minimum needed for the feature and do not attach your
name or a persistent identifier to AI requests. Chat text may contain personal
information that you choose to enter. Turning sharing off prevents future AI
requests; it cannot retract requests already transmitted to a provider.

We do **not**: track you across other apps or websites, sell or rent your data,
serve advertising, or use third-party analytics.

## Data retention
Use **Profile → Delete All Data** to clear the local profile, log, cart, budget,
lists and plans and request deletion of synced shopping data. If offline, the
cloud erasure request remains pending until the app reconnects using the original
Apple Account. Other offline devices clear pre-deletion shopping data when they
next sync. A minimal reset generation remains in CloudKit to prevent restoration
of old records; it contains no previous shopping items. Deleting the app alone
does not request deletion of cloud data, and Keychain items can survive app
removal. Requests to our backend are processed transiently and not stored with
your identity.

## Third parties
- **Groq** — AI meal plans, chat, and recipes ([groq.com](https://groq.com)).
- **Open Food Facts** — product nutrition ([openfoodfacts.org](https://openfoodfacts.org)).
- **Apple** — MapKit/Maps for store locations; optional CloudKit shopping sync.

## Children
Mealio is not directed at children under 13 and should not be used to set
calorie goals for minors without medical guidance.

## Your choices
- Revoke location or notification permissions anytime in iOS Settings.
- Use "Delete All Data" in Profile to clear local data and request cloud deletion.
- Turn shopping sync off in Profile to stop future sync without deleting cloud data.

## Health disclaimer
Calorie and macro values are **estimates** and may vary by product and
preparation. Mealio is not a medical device and does not provide medical advice.
Consult a professional before making significant dietary changes.

## Contact
For questions about this pre-release build, contact the person who provided it.
A verified public support contact and hosted policy URL must be supplied before
App Store submission.
