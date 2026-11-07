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
