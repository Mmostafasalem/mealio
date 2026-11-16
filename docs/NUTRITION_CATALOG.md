# Nourlo iOS nutrition data

## Implemented

Food logging reads a source-backed data resource instead of nutrient constants in Swift.
The bundled offline database contains 7,793 complete USDA SR Legacy records from the
April 2018 release, retaining FDC identifiers and preparation descriptions. These are
reference averages, not an up-to-date label for every European product. The original
ZIP URL and SHA-256 checksum are included in NutritionCatalog.json.

Download the official archive listed at https://fdc.nal.usda.gov/download-datasets/
and rebuild with:

    python3 scripts/import-usda-nutrition.py /path/to/FoodData_Central_sr_legacy_food_csv_2018-04.zip
    python3 -m unittest discover -s scripts -p test_nutrition_catalog.py

The importer reads USDA nutrient IDs 1008 (kcal), 1003 (protein), 1005 (carbohydrate)
and 1004 (fat), per 100 g. Incomplete/non-finite/negative records are excluded rather
than filled with category averages. FoodData Central attribution is shown in the app.
USDA's historic dataset is a stable offline baseline; future dataset releases should
be imported and reviewed explicitly, with their own identifiers and release labels.

## Packaged foods

An explicit search action calls Open Food Facts directly from iOS. Text search uses
its documented v1 full-text endpoint; barcode lookup uses v2 product lookup and must
match exactly. No profile, food log, backend app key or account credential is sent.
No AI service is involved. Product results are not allergy guarantees.

The client requests only required fields, uses a descriptive User-Agent, limits
uncached requests to one every 6.1 seconds and caches up to 30 queries in memory.
It rejects missing, boolean, non-finite, negative or implausibly ranged nutrients.
Its `_100g` fields can also mean 100 ml: a consistent package/serving mass or volume
unit must establish the basis. Conflicting or unknown units are excluded; the old
`nutrition_data_per=100g` default alone is not proof of mass. It never assumes density.
Community records may still be wrong; the detail screen links the original record
and asks the user to compare the current package label.

Up to 200 selected packaged-food snapshots persist locally for offline reuse.
Network sessions are ephemeral and cookie/credential/disk-cache disabled. Delete All
Data clears saved products and query caches. Lookup generations prevent an in-flight
response from restoring an erased cache. USDA public reference data remains bundled.

## Portions and migration

Quick-add explicitly adds 100 of the displayed unit. Detail supports 1–5,000 g/ml.
Nutrients scale from the provider's 100-unit basis; only displayed calories round
for the log, while fractional macros and the exact amount are retained. Each entry
stores the source record snapshot so later provider updates cannot change history.
Older log entries still decode and are labelled estimated/older entries.

The legacy small Food.catalog now resolves its nutrition from selected USDA IDs;
its preference identifiers are retained for compatibility. It is not the logger's
search database. AI and offline meal suggestions remain estimates and are not
accepted through a one-tap planned-meal nutrition logging shortcut; users log actual
ingredients/amounts through the sourced database. Calorie targets remain formulas.

## Verification

Automated checks cover the imported catalog, raw/cooked separation, provider field
validation, mass/volume conflicts, real zero values, fractional portions, old-log
migration, exact barcode matching, rate limits, query caching, offline persistence,
data deletion and malformed provider responses. Native UI verification exercises
search → source detail → log serving → dashboard. A bounded live OFF barcode and
text search were also parsed with the production Swift normalizer.

Verified locally on 2026-11-07: 53 native unit tests passed (one separate live AI
inference test skipped because no provider credentials were requested), the logger
UI test passed, and 16 Python release/catalog checks passed. Clean simulator Release
build completed with zero compiler warnings/errors and passed the bundle guard;
its bundled JSON contains all 7,793 source records. The live OFF check normalized
one exact barcode and 27 usable products from a 40-result name search after
excluding incomplete/ambiguous records. No physical-device or App Store release
is implied by these simulator checks.


## Global and restaurant expansion — 2026-11-08

The offline database now contains 13,588 complete records: 7,793 SR Legacy,
364 Foundation records from the official October 2026 JSON download, and 5,431
FNDDS 2021–2023 records published October 2024. Import metadata retains each ZIP
URL and SHA-256; each food retains dataset/release attribution. Foundation energy
uses USDA nutrient 1008 when present, otherwise 2048/2047 Atwater kcal. A release
label is the downloaded dataset version, not a claim about when every food was
sampled. Rebuild the SR base, then run:

    python3 scripts/expand-usda-nutrition.py /path/to/foundation.zip /path/to/survey.zip

The extra references include prepared dishes, falafel, hummus, fava beans and
restaurant-style foods. They are not verified current menus for all restaurants.
No blanket regional nutrition value is assigned to arbitrary dish names. Common
Lithuanian/Arabic ingredient aliases broaden matching while retaining the source
description/preparation. English, Lithuanian and Arabic product names are kept
as search names. User-entered Arabic/Latin recipe and restaurant names remain
searchable locally.

Online country filters apply to product search only. The filter describes where
OFF lists the product as sold, not a restaurant's cuisine or location. World-wide
barcode identity stays exact. Market, language and page are isolated in query
caches, pagination uses raw provider counts, and every page respects rate limits.
Ingredient selection uses a separate eligible-food index before applying result
limits; custom dishes cannot displace genuine ingredients.

Custom menus store all four entered nutrients per one serving, with restaurant
name and optional HTTPS source link. Fractions scale from one serving, never a
100 g denominator. The app explicitly labels these as entered by the user.
Recipes sum snapshotted ingredient portions and divide by the provided final
cooked yield to get per-100-g values. Recipe/menu records are excluded from recipe
ingredient selection to prevent ambiguous recursive recipes. Yield, amounts,
energy/macros and source URLs are validated. Recipes are estimates; discarded
cooking liquid, sauces or oil must be accounted for by the person preparing them.
Up to 200 custom dishes persist locally and can be removed individually; Delete
All Data clears them. Previously logged source snapshots are preserved when a
saved dish is removed.


Global expansion verification, 2026-11-08: 60 native unit tests passed with one
separate live-AI check skipped; source logging, recipe save/log and restaurant
per-serving save/log UI tests passed. Seventeen Python release/catalog checks
passed. Final Release and signed Personal Team phone builds completed with zero
compiler warnings/errors; bundle guards pass and the 13,588-record database is
present. UI evidence exposed and fixed nested-sheet keyboard focus and Save
reachability. Fresh review found two ingredient coverage issues (first-page-only
lookup and filtering after the result cap), both fixed and re-reviewed.

Live Lithuania lookup returned87matches: all40returned records carried Lithuania
country metadata;23had usable nutrition/units in the production parser. Egypt
search returned HTTP503 on both bounded attempts. Country request structure/cache
separation is covered by isolated transport tests, but a successful live Egypt
lookup is not claimed. Offline Arabic ingredient search and custom dishes work
independently of provider availability. Reference/menu/recipe source distinctions
remain visible in the app.

## Working product text search (2026-11-08)

Generic product searches now POST to the official
https://search.openfoodfacts.org/search service using its documented plain-text
query and taxonomy country filter. Inputs are normalized to literal words;
selected country tags are checked again on returned records. Barcode lookups
retain exact-code API v2 matching, and retailer lookups retain explicit store-tag
validation. No profile, account token or stock is sent to product search.
Live checks: Lithuania milk search returned 64 matches, 40 records on page one,
14 usable with the production nutrition parser. Egypt milk search returned 68
matches, 40 records, 8 usable. Missing/ambiguous units or macros remain excluded.
These checks establish working regional discovery, not current store inventory.
