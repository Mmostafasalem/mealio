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
