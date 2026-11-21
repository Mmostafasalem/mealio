#!/bin/bash
# Renders the mascot's continuous performance for the all-features advert into video/public/clips/perf.
set -e
cd "$(dirname "$0")/.."
mkdir -p /tmp/mealio-run && cp video/src/ads/combo.json /tmp/mealio-run/combo.json
TEST_RUNNER_NOURLO_MASCOT_CLIPS=1 DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project smartmarket.xcodeproj -scheme smartmarket -sdk iphonesimulator \
  -destination 'platform=iOS Simulator,name=iPhone 17' test -only-testing:smartmarketTests/MascotSnapshotTests/testRenderAdvertPerformance CODE_SIGNING_ALLOWED=YES CODE_SIGN_IDENTITY=- 2>&1 | grep -E "error:|\*\* TEST" | tail -2
rm -rf video/public/clips/perf && cp -R /tmp/mealio-run/clips/perf video/public/clips/perf
echo "frames: $(ls video/public/clips/perf | wc -l)"
