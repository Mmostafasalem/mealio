# Nourlo production product requirements

The owner requests a complete iPhone product connecting household stock, worldwide food search, goal-aware AI meals, and nearby market products. Existing catalog work alone does not satisfy this objective.

## Required end-to-end behavior

1. Stock: add any supported nutrition record, barcode product, saved recipe or manually described food to persistent inventory with actual amount/unit, optional expiry and purchase provenance. Shopping intentions, purchased inventory and consumed food are separate states. Users can edit, remove, replenish, and log a portion from stock without negative quantities or double deduction.
2. Catalog: share the source-backed nutrition search across logging, stock and meal ingredients. Support worldwide products and Lithuanian/Arabic search; expose source and missing information. No promise of every restaurant item or verified branch stock without evidence.
3. Goals: remaining daily calories/macros derive from consumed portions. Preserve historical logs instead of deleting yesterday. Meal suggestions respect preferences/allergies, available quantities, remaining targets, and user edits.
4. AI: a real authenticated online flow must work on the owner's phone and in release. Ground ingredient quantities and nutrition in catalog records. Do not fabricate meal macros by distributing target macros. Preserve a previous valid plan on failure, disclose estimates, and make any missing ingredient a shopping action.
5. Markets: locate real nearby stores, associate products/offers with a supported source and freshness, and distinguish chain catalog from branch inventory. Missing feeds must not silently become invented prices. Verify supported market coverage with live evidence.
6. Release: durable state and data deletion, privacy/consent, operational authentication and quotas, accessibility, regression tests, complete device user journeys, signing/distribution and deployment validation. A Personal Team phone-test installation is not production distribution.

## Current evidence and gaps (2026-11-08)

- StockStore and StockView now track source-backed food quantities, optional use-by dates, corrections/replenishment, and consumption. Stock quantities and consumption records persist together. Home and Meal Plan expose stock. Planning requests now carry grouped owned quantities and remaining intake targets separately from shopping intentions. The server prompt uses those quantities. Live authenticated planning is still unverified.
- MealPlanViewModel.computeNutritionalGaps used an arbitrary 200 g per grocery item. Changed to actual today's logged portions; simulator unit verification passed.
- Removed goal-proportional macros and kcal/2 portion grams from Models/MealPlan.swift. Online portion IDs resolve against the submitted catalog snapshots; calories/macros are calculated from those amounts. Unresolved meals retain labelled estimated calories and no invented macros. Model-composed ingredient completeness and real-world preparation still need end-to-end validation.
- FoodLogStore now preserves retained logs across days, including existing-format records, derives today's totals, and exposes Food History. Previously discarded records cannot be recovered.
- ProductCatalogService depends on protected backend and caches chain products. Map displays branch-stock disclaimers; no verified branch inventory source has been demonstrated.
- Online AI and production signing are not verified on the current phone-test build. Existing Apple account/capability dependency needs resolution without putting shared provider secrets into the app.

## Implementation sequence

Inventory persistence, shared food selection, log/consume/replenish and retained history have been implemented. Stock-aware request inputs and ingredient-based nutrition are implemented and unit tested. Activate/test secure AI end-to-end, verify quantity budgeting across the full plan, and support shopping actions for missing ingredients. Integrate verifiable market sources and remove misleading fallback claims. Then redesign navigation around Today, Stock, Meals and Nearby shopping, run full device journeys and release gates. Existing SwiftUI platform is retained. No paid purchase is implied.

Completion requires evidence for all six requirements, not simply successful compilation or expanded offline records.

## Verification for stock milestone

- Full native unit suite: 64 executed, 1 credential-gated AI test skipped, zero failures (`/tmp/nourlo-stock-tests.log`).
- Simulator UI: source-food search → add to stock → log full portion → stock empty passed (`/tmp/nourlo-stock-ui.log`).
- Final stock/goal unit and UI verification rerun after quantity editor changes: `/tmp/nourlo-stock-final.log` (inspect terminal result).
- Release helper checks: 17 passed after allowing their local HTTP test server.
- This milestone does not prove online AI, stock-aware planning, nearby retailer feeds, or production distribution.

## Planning milestone evidence

- Native suite: 67 tests executed, one credential-gated live AI test skipped, zero failures (`/tmp/nourlo-plan-grounding-final.log`).
- Final targeted grounding/stock/goal rerun passed after narrowing stock serialization to food ID/name/basis/nutrients and available quantity (`/tmp/nourlo-grounding-verified.log`); no compiler warnings.
- Full backend suite with pinned dependencies: 73 passed. Tests cover stock/shopping separation, remaining targets, malformed numeric values, and preservation of ingredient portion IDs.
- Legacy plans remain readable. Macros and grams are no longer synthesized from daily targets. A failed refresh retains the existing plan.
- Live `/healthz` returns HTTP 200; `/api/auth/config` without credentials returns HTTP 401. This is liveness/auth enforcement evidence, not successful AI operation. Render administration is not connected (Render plugin discovered as available but uninstalled).
- Backend changes are local and have not been deployed. Neither live AI operation nor production distribution is complete.

## Nearby market discovery milestone

- MapKit food-market POI search replaces the five-chain restriction. Returned map records are used as actual branch locations; generic chain estimates are still distinct.
- Store details and Shop expose explicit retailer-scoped Open Food Facts lookup. Structured searches use API v2 `stores_tags`; named text search uses CGI store/country filters. Results without the selected retailer tag are discarded. There is no claim of branch-level stock or current prices.
- Product selection shows source nutrition and lets the user add purchased quantities to My Stock. The grocery budget catalog remains an estimate catalog, labelled accordingly.
- Provider reference: https://openfoodfacts.github.io/documentation/docs/Product-Opener/v2/search/get-search/ (stores_tags structured filter).
- Live Rimi/Lithuania requests to both the structured and text endpoints returned HTTP 503 on 2026-11-08. Do not count these as verified product coverage. Availability is an external limitation; transport/filtering are covered by injected-response tests.
- Authenticated read-only Render dashboard inspection is now possible through the browser. Service srv-dbnh60rrjlhs738q8fn0 is Free, deploys release/production-ai-2026-11-07 at 37c2022442c1153a1151c7e1f924aad8a83a7bf6. AI_ACCOUNTS_ENABLED is 0; GROQ_API_KEY exists; GROQ_MODEL is openai/gpt-oss-120b. No values or permissions were changed. Apple credential and durable account database configuration are absent from the listed environment variables. App production signing and live AI remain unresolved.

## Whole-meal stock logging milestone

- Source-backed planned meal entries now open an ingredient review with catalog source links, exact quantities, missing quantities and logging action. Unresolved legacy plans still open the recipe flow and cannot deduct unverified ingredient amounts.
- StockStore validates the entire meal before mutating any batch; repeated source IDs are aggregated and earliest use-by batches are consumed first. Consumption logs, remaining quantities and operation receipts persist together.
- Meal operation IDs are stable across plan reloads and distinct across dates/meal slots. Retrying a successful operation is idempotent, including after store reload. Deleting an intake record does not undo the receipt or replenish eaten stock.
- Missing quantities can be added to groceries with no invented store/price. Unknown-price status survives shopping sync; the grocery screen and shared text identify incomplete estimates.
- UI reference lock: retain Nourlo's existing native Form and source-detail styling. Adapt Crouton ingredient list quantities (https://refero.design/screens/1ccfd142-b2ea-448d-a3da-68612c4ef111) for portion hierarchy and FoodNoms meal/portion context (https://refero.design/screens/598b0c89-6038-4364-8af1-cb75cf07611a) for explicit logging context. No new visual identity or decorative assets.
- Verification: 70 native tests executed, one live AI test skipped, no failures; existing stock search/add/consume simulator UI flow passed (`/tmp/nourlo-meal-stock-final.log`). 17 sync package tests passed (`/tmp/nourlo-sync-meal-test.log`). New whole-meal screen compiles; its full rendered journey is not yet verified.
- Signed phone-test build succeeded and installed on iPhone 15 Pro. Launch was rejected because the phone was locked. This is installation evidence, not physical-device feature validation or production readiness.
- Still required: live AI/auth/storage activation, full-week stock allocation and missing-ingredient planning beyond owned candidates, allergy-safe plan validation, real retailer availability coverage, rendered whole-meal journey, release signing/distribution and complete release checks.

## Guest AI access (owner approved 2026-11-08)

- Owner chose guest access alongside Apple sign-in. Guest credentials use 32 random bytes stored in device-only Keychain. Server identity is keyed-hashed; session tokens are hashed and expire after 30 days.
- Guest recovery retains the same quota; five new guest registrations per network/UTC day and overall AI attempt limits bound abuse. Apple auth remains supported and independently configurable.
- Public auth bootstrap no longer requires the app-wide API key; protected AI and account operations still require authenticated bearer sessions. Legacy catalog/BMR API-key protection is unchanged. Durable account storage remains mandatory.
- Retained account IDs prevent guest/Apple switching from orphaning a previously retained account during Delete All Data. Signed-out and expired legacy Apple sessions are migrated conservatively. Keychain writes update existing records in place.
- Independent review found the account-switching deletion bug and two migration variants; all were fixed. Final review reported no further important regression.
- Backend suite: 77 passed (`/tmp/nourlo-guest-verified.log`). Full native suite: 73 executed, one live provider test skipped, zero failures (`/tmp/nourlo-guest-ios-final.log`); final four guest recovery/deletion/migration tests passed (`/tmp/nourlo-guest-migrations.log`).
- Private server-only activation configuration was prepared at `/Users/mmostafasalem/.config/nourlo/guest-activation-2026-11-08.env` (0600), without printing or committing secrets. It uses /var/data, guest enabled, Apple temporarily disabled until Apple server credentials exist, 30 credits/device/day and 30 global attempts/day.
- Activation procedure and remaining live proof are in docs/AI_ACCOUNTS_SETUP.md. Existing Render Free service has no durable disk. Paid resource changes have not been authorized or performed. Guest code is not evidence of live AI operation.

## Live provider proof and free-storage choice (2026-11-08)

- Owner explicitly authorized private download of existing Render settings and AI verification. Settings were moved to `/Users/mmostafasalem/.config/nourlo/render-provider.env` with mode 0600; no credential values were printed or committed.
- Existing Groq key and configured openai/gpt-oss-120b passed a real synthetic provider response.
- A synthetic request through the guest Flask API returned an online AI response, charged one credit, retained the 29-credit allowance after reopening the account store, and rejected the session after deletion. This was a local integration test; it is not proof of live hosted guest activation.
- Guest backend 8b02bb8 deployed successfully as Render deployment dep-dbo7bknf3r2c73acjki0. Live checks: /healthz 200; /api/auth/config 200 with enabled/guestEnabled/appleEnabled false; /api/ai/usage 503; protected /api/products 401. Latest guest-capable iPhone build installed successfully.
- Owner questioned the paid Render plan. No paid change was made; Render still shows Free. The paid-disk handoff is superseded by a free Neon Postgres approach, which requires adapting the account persistence implementation.
- Neon Free was selected explicitly via Vercel CLI (free_v3, pdx1, no built-in Neon auth/realtime, resource name nourlo-accounts). CLI reports integration_terms_acceptance_required. The browser signed in to the correct Vercel account but still shows account verification/2FA reminder and Accept & Install pending. Owner was shown the page to complete this final legal/account step. Do not claim the database exists or write/migrate against a mock connection.

## Free database and working regional search

- Neon terms accepted in Vercel. Resource store_sXHeXZsqicB2CuyK / nourlo-accounts / dawn-river-72271199 is ready on free_v3, region pdx1. It is privately connected to the existing Vercel web project's development environment under NOURLO; no paid resources were selected. Credentials are stored only in private local configuration.
- AccountStorage supports SQLite and Postgres. The latter uses psycopg 3.3.8, verified TLS, bound values and a transaction-scoped advisory lock. Independent review found no actionable issue. SQLite backend regression: 77 passed. Three actual Postgres contracts passed in an isolated disposable schema (restart persistence, refunds/deletion, concurrent reservation limits), log /tmp/nourlo-live-postgres-tests.log.
- Corrected Postgres upsert ambiguity found by the real tests; no production account data existed before this change.
- Open Food Facts' newer search service works where legacy text lookup returned 503. Production parser accepted 14 of 40 returned Lithuanian products and 8 of 40 Egyptian products. Missing nutrition/units are not guessed. Final nutrition lookup/catalog tests passed in /tmp/nourlo-product-search-verified.log.
- Activation remains off on live Render until the new backend is deployed and the prepared free-database settings are imported. No claim of live hosted AI operation or complete production release is made by this milestone.

## Live free guest AI activation and source-backed plan proof

This section supersedes earlier statements that activation is pending/off or requires a paid Render disk.

- Owner authorized importing the private Neon connection and stable account secrets into the existing Render service, preserving existing Groq/app keys. Import and deployment completed on Free Render + Neon free_v3. No paid hosting change was made.
- Public `/api/auth/config` reports enabled/guestEnabled true and appleEnabled false. Real hosted guest chat returned HTTP 200/online and charged exactly one credit. Unauthenticated AI is rejected with 401.
- The same synthetic session and exact remaining balance survived backend redeployment. Deleting the synthetic account returned 204 and its old session was rejected with 401.
- The first real weekly plan was rejected because the provider emitted `trečiadienis`; the alias is now normalized and regression-tested. A later online plan omitted source portions. The prompt now provides the complete portion schema and permits repeats to prioritize actual stock. Deployed 4f339dc returned 28 online meals with valid IDs/amounts for all 28; a separate real provider response also stayed within submitted aggregate quantities. This is observed proof, not a guarantee for future model output.
- Chat now sends actual saved calorie goals, today's consumed/remaining nutrition, grouped owned food quantities, dietary exclusions/allergies and selected language. It omits body measurements/name/contact fields. It retains the existing explicit consent/authentication gates. Incompatible nutrition/unit snapshots sharing one ID are omitted, while metadata-only refreshes still combine.
- Backend: 87 passed, three optional real-Postgres tests skipped in the normal run (the three real Postgres contracts passed separately). Native suite: 76 executed, one retired owner-connection test skipped, zero failures. Final three goal/context/grouping regressions passed after compatibility review. Independent review findings were fixed and rechecked.
- Physical iPhone currently appears unavailable. Updated phone build and isolated live guest UI verification are in progress. The first UI attempt stopped during onboarding before creating a guest account; off-screen destination handling was corrected.
- Production gaps remain: physical device flow and distribution signing, Apple capability/server credentials, deterministic whole-week inventory allocation and dietary validation, missing-ingredient reference coverage, verifiable retailer feeds/current branch products/prices, and complete release operations. Guest activation alone does not satisfy the complete production objective.
