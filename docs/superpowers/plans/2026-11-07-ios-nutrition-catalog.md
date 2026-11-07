# iOS nutrition catalog implementation plan

Goal: Replace the logger's small fixed nutrition list with source-backed offline USDA foods and optional live Open Food Facts product lookup.

Architecture: Import USDA SR Legacy CSV into a versioned JSON resource with FDC IDs and source metadata. A separate nutrition model preserves fractional nutrients, gram/millilitre basis, source and retrieval dates. iOS searches the bundled records locally; explicit product searches and barcodes call Open Food Facts directly without sending profile or logged intake. Selected products persist locally for offline reuse. Existing logs retain snapshots; generated meal entries remain clearly marked estimates.

Constraints: No paid service or API key; no guessed missing macros; no gram-to-volume conversion; no search-as-you-type network calls; no changes to web. Keep old log decoding and account/data deletion working.

- [x] Import a reproducible, checksum-recorded USDA dataset; test source totals, IDs, completeness and raw/cooked distinction.
- [x] Test and implement provider normalization, source metadata, portion calculation, exact barcode lookup, bounded cache and explicit-request rate limits.
- [x] Replace logger search and serving detail with source-backed records; persist log provenance and cached recents; preserve legacy logs; update privacy/support disclosures.
- [x] Run model/network/persistence tests, native unit/UI tests, Release build and bundle guard; perform bounded live provider checks; save reviewable changes to GitHub.

Review focus: missing or non-finite nutrients; 100 ml versus 100 g; zero-calorie records; cancelled/stale search responses; offline reuse and deletion; source snapshots after database updates.

Verification record: first importer assertion failed before the resource existed; native provider tests exposed missing types and later malformed success/boolean/unit validation failures. Final targeted reruns passed after fixes. The first UI run selected an offscreen virtualized result; a narrow source-record query fixed the test, and its full logging flow passed. A fresh reviewer found three actionable issues, all corrected and re-reviewed without further findings. Final Release/bundle and test outputs are recorded in docs/NUTRITION_CATALOG.md.
