# Nourlo — Privacy Policy

_Last updated: 2026-11-07_

Nourlo ("we", "the app") helps you estimate grocery costs, plan meals, and
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
  also stored in your private Apple CloudKit database. No Nourlo account is
  required. Profile/body measurements, BMR, food intake, dietary restrictions and
  nutrition meal plans are excluded from this app's iCloud sync.

## Optional shopping sync
Sync starts only after you enable it in Profile and requires an available iCloud
account. The app retries when opened or brought to the foreground; changes may
not appear immediately on other devices. Changes to different list items merge.
Conflicting edits to the same item use a deterministic logical-clock rule;
simultaneous quantities are not added together. Turning sync off retains existing
cloud data. Apple processes CloudKit data under its own terms and privacy policy.

## Food database and product lookup

The iOS food logger includes an offline reference catalog imported from USDA
FoodData Central (SR Legacy April 2018, Foundation October 2026 download, and
FNDDS 2021–2023). Searching these foods stays on your device.
When you explicitly search packaged products or enter a barcode, the app connects
directly to Open Food Facts and sends that search text or barcode, optional retailer tag, selected market
and language and requested result page, along with the
normal network information such as your IP address. Your name, body measurements,
food log and AI account token are not included. This lookup works independently of
AI-sharing consent; the search action explains the transfer before you submit it.
Selected product records are saved locally for offline reuse. Custom restaurant
entries and recipes, including entered menu links, ingredient snapshots and cooked
yields, are stored locally and are not sent to product search or shopping sync. Logged portions retain
a snapshot of their nutrition and source so database changes do not rewrite your
past intake. Stock quantities, optional use-by dates and portions eaten from stock
are saved locally. Food history is retained across days; daily totals count only
today's entries. Removing an intake record does not replenish stock. Delete All Data
clears stock, saved products, custom dishes and logs. Open Food Facts is a
community database; compare branded products with their current package labels.
Retailer tags are contributor reports, not current branch stock or prices. Product
lookup sends no precise location. Nearby supermarkets are found through Apple Maps.

## Information sent to our servers

Online AI features are optional and require the sharing permission in Profile.
When enabled and you generate a meal plan, ask the in-app assistant, or request a recipe, we
send the relevant inputs (e.g. age, gender, weight, height, calorie target, dietary preferences, favourite
foods, shopping list, owned food names, quantities, units and reference nutrition,
remaining daily calorie and macro totals, your message) to our backend, which uses **Groq** (an AI
provider) to generate the response. Product nutrition is looked up from **Open
Food Facts**. We send the minimum needed for the feature and do not attach your name. Online AI requests use a Nourlo session linked to
your optional Apple account. The session and Apple identifier are not included
in prompts sent to Groq. Chat text may contain personal
information that you choose to enter. Turning sharing off prevents future AI
requests; it cannot retract requests already transmitted to a provider.

We do **not**: track you across other apps or websites, sell or rent your data,
serve advertising, or use third-party analytics.

## Optional guest or Apple account for AI
Local tracking, shopping and offline plans do not require a Nourlo account.
Online AI requires a guest device session or Sign in with Apple, plus separate
AI-sharing consent. Guest access creates a random secret stored in this device's
Keychain; it is sent only to our backend to recover that guest account. The backend
stores a keyed hash of the guest identity and hashes of session tokens, not the
raw device secret. No name or email is requested for guest access. New guest
accounts are limited per network each UTC day using a daily keyed network hash
and count, removed on subsequent activity after that day. Guest access is not
anonymous: requests still include normal network information such as your IP
address. Guest allowances are per device credential, not shared across devices.
We do not request your Apple name or email. The backend stores a keyed hash of your Apple
user identifier, hashes of app session tokens, an encrypted Apple refresh grant,
account timestamps, daily request counters, and hashed request keys/fingerprints. These records provide one daily
allowance across devices, validate access and support account deletion. Apple
processes sign-in under its own terms. Signing in or continuing as a guest does not enable AI sharing.

Account records and allowance counters are stored in our private Neon Postgres
database. It stores the account metadata described above, not your food log,
profile or chat bodies. Database connections use certificate-verified encryption.

Credits reset at midnight UTC. The app displays the reset in your time zone.
Personal allowances still share our provider's overall capacity. Failed AI
calls and cached responses do not spend personal credits.

Duplicate-request safeguards retain hashed request keys and keyed input
fingerprints for 24 hours, removed on subsequent activity or account deletion.
They contain no request or response text. To replay a retried response without
calling AI again, the backend temporarily holds up to 128 responses in memory,
with a three-minute replay window. This may include generated nutrition or chat
content. Expired entries are removed on subsequent replay activity, evicted as
new entries arrive, cleared on account deletion in that process, or lost on
restart. They are never written to the account database or backed up.

## Data retention
Use **Profile → Delete All Data** to clear the local profile, log, cart, budget,
lists and plans and request deletion of synced shopping data. If offline, the
cloud erasure request remains pending until the app reconnects using the original
Apple Account. Other offline devices clear pre-deletion shopping data when they
next sync. A minimal reset generation remains in CloudKit to prevent restoration
of old records; it contains no previous shopping items. Deleting the app alone
does not request deletion of cloud data, and Keychain items can survive app
removal. Nourlo's backend has no user-profile or food-log database. Apple AI account records
remain until deleted. Guest account records without any unexpired session are
removed after 30 days from their initial creation, on subsequent service activity;
recovering a guest session extends its session expiry. App sessions expire after 30 days, pending sign-in
challenges after five minutes, and abandoned request reservations after three
minutes. Personal spending counters retain only the current UTC day; aggregate service
attempt counters retain the current day plus two previous days. Expired rows are
removed on subsequent service activity. Cleanup is activity-driven.

If an AI account is saved on this device, Delete All Data first requires a
connection and valid sign-in to revoke any Apple grant and erase its server
account and sessions. A keyed subject hash and today’s spent-credit count are
retained solely to prevent deletion/recreation from resetting the daily allowance;
they expire at the next UTC day and are removed on subsequent service activity. If that step fails, the app reports the
failure and keeps local data so deletion can be retried. Signing out keeps a minimal on-device marker that an online account may remain
and clears the device session; it does not delete the account. If guest and Apple
accounts have both been used, the app retains their identifiers securely and requires
each retained account to be handled before reporting complete deletion. To delete after sign-out,
sign in again and use Delete All Data. Unlinked aggregate daily service attempt
counts may remain until routine cleanup. Operator-managed backups must follow
the published retention policy before launch. Chat may
contain identifying content. Service providers may retain operational metadata
or submitted content under their own retention policies; clearing local data
does not automatically erase provider records.

## Third parties
- **Groq** — AI meal plans, chat, and recipes ([groq.com](https://groq.com)).
- **Neon** — private account and allowance database ([neon.com](https://neon.com/privacy-policy)).
- **Open Food Facts** — product nutrition ([openfoodfacts.org](https://openfoodfacts.org)).
- **Apple** — MapKit/Maps for store locations; optional CloudKit shopping sync.

## Children
Nourlo is not directed at children under 13 and should not be used to set
calorie goals for minors without medical guidance.

## Your choices
- Revoke location or notification permissions anytime in iOS Settings.
- Use "Delete All Data" in Profile to clear local data and request cloud deletion.
- Turn shopping sync off in Profile to stop future sync without deleting cloud data.

## Health disclaimer
Calorie and macro values are **estimates** and may vary by product and
preparation. Nourlo is not a medical device and does not provide medical advice.
Consult a professional before making significant dietary changes.

## Contact
For questions about this pre-release build, contact the person who provided it.
A verified public support contact and hosted policy URL must be supplied before
App Store submission.
