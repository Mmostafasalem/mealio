# Global iOS food catalog expansion

Goal: broaden source-backed food coverage for Lithuania, Egypt and worldwide use without inventing nutrition or equating a regional dish with an unrelated generic food.

Approach: add current USDA Foundation and survey foods to the offline reference database; retain dataset-specific provenance and existing IDs. Add English/Lithuanian/Arabic ingredient aliases, product name translations and explicit Worldwide/Lithuania/Egypt online search. Preserve exact barcode lookup worldwide. Provide a way to save a missing dish from its weighed source-backed ingredients and cooked yield, so regional/home recipes do not need made-up standard calories.

- [x] Import checksum-pinned official datasets with complete energy/protein/carbs/fat; keep every record's dataset/date/source ID and backward-compatible snapshots.
- [x] Test and implement multilingual ingredient search, regional packaged product filters and pagination with cache isolation and rate limits.
- [x] Implement saved ingredient-based recipes with source snapshots, portion yield validation, local persistence/deletion and transparent recipe attribution.
- [x] Verify model/network/persistence tests and native logging UI; build and update the connected phone-test app; save reviewable GitHub changes.

Constraints: no paid APIs, no search-as-you-type network calls, no missing-macro guesses, no gram/ml density assumptions, no fabricated regional-dish matches. Food log and profile data never go to the product search API. A finite catalog cannot promise every food; recipes cover local variants through their actual ingredients.

Verification 2026-11-08: 60 native unit tests passed, one independent live-AI test skipped; raw logger, recipe-builder and menu-serving UI cases passed in targeted runs. Recipe focus and Save-button accessibility were corrected from failing UI evidence. Seventeen Python catalog/release checks pass. Final Release and signed phone builds pass; bundle guard confirms the sourced database and excludes backend/build secrets. Read-only review findings about ingredient pagination and pre-limit filtering were fixed and re-reviewed. Lithuania live lookup returned87matches/40raw/23usable records with correct countrytags; Egypt returned503 on two attempts and remains an external availability limitation. No claim of all current restaurant menus is made.
