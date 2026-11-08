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

- StockStore and StockView now track source-backed food quantities, optional use-by dates, corrections/replenishment, and consumption. Stock quantities and consumption records persist together. Home and Meal Plan expose stock. MealPlanViewModel still sends ShoppingCartService.planDeals as pantry: planning integration remains incomplete.
- MealPlanViewModel.computeNutritionalGaps used an arbitrary 200 g per grocery item. Changed to actual today's logged portions; simulator unit verification passed.
- Models/MealPlan.swift fabricates macro estimates from goal proportions and portion grams from kcal/2. Must replace with source-backed ingredient calculations.
- FoodLogStore now preserves retained logs across days, including existing-format records, derives today's totals, and exposes Food History. Previously discarded records cannot be recovered.
- ProductCatalogService depends on protected backend and caches chain products. Map displays branch-stock disclaimers; no verified branch inventory source has been demonstrated.
- Online AI and production signing are not verified on the current phone-test build. Existing Apple account/capability dependency needs resolution without putting shared provider secrets into the app.

## Implementation sequence

Inventory persistence, shared food selection, log/consume/replenish and retained history have been implemented. Replace planning inputs and nutrition calculations with explicit inventory and recorded intake. Activate/test secure AI end-to-end. Integrate verifiable market sources and remove misleading fallback claims. Then redesign navigation around Today, Stock, Meals and Nearby shopping, run full device journeys and release gates. Existing SwiftUI platform is retained. No paid purchase is implied.

Completion requires evidence for all six requirements, not simply successful compilation or expanded offline records.

## Verification for stock milestone

- Full native unit suite: 64 executed, 1 credential-gated AI test skipped, zero failures (`/tmp/nourlo-stock-tests.log`).
- Simulator UI: source-food search → add to stock → log full portion → stock empty passed (`/tmp/nourlo-stock-ui.log`).
- Final stock/goal unit and UI verification rerun after quantity editor changes: `/tmp/nourlo-stock-final.log` (inspect terminal result).
- Release helper checks: 17 passed after allowing their local HTTP test server.
- This milestone does not prove online AI, stock-aware planning, nearby retailer feeds, or production distribution.
