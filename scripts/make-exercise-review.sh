#!/bin/bash
# Builds the exercise review: a numbered video of every exercise in the app and every
# captured candidate, with each one's automatic check result, and a checklist to fill in.
#
#   scripts/make-exercise-review.sh            # app exercises + candidates
#
# Output: ~/Desktop/Nourlo exercise review/{review.mp4, checklist.html, checklist.csv}
# Needs ffmpeg: $FFMPEG, or one on PATH, or the copy the Mascot Designer installed.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="$HOME/Desktop/Nourlo exercise review"
WORK=/tmp/mealio-run/review
FF="${FFMPEG:-$(command -v ffmpeg || true)}"
[ -n "$FF" ] || FF="$HOME/.mascot-designer/node_modules/ffmpeg-static/ffmpeg"
[ -x "$FF" ] || { echo "ffmpeg not found (set FFMPEG=/path/to/ffmpeg)"; exit 1; }
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
cd "$ROOT"
mkdir -p "$WORK" "$OUT"

echo "1/4 baking clips (with candidates)…"
python3 scripts/build-exercise-clips.py --candidates | tail -3

echo "2/4 rendering and checking every exercise (several minutes)…"
TEST_RUNNER_EXERCISE_REVIEW=1 xcodebuild -project smartmarket.xcodeproj -scheme smartmarket \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -only-testing:smartmarketTests/ExerciseReviewTests test CODE_SIGNING_ALLOWED=NO > "$WORK/xcodebuild.log" 2>&1 || true
grep -E "REVIEW items|error:|TEST (SUCCEEDED|FAILED)" "$WORK/xcodebuild.log" | sort -u | head -5
[ -f "$WORK/results.json" ] || { echo "no results (see $WORK/xcodebuild.log)"; exit 1; }

echo "3/4 making the video…"
"$FF" -y -loglevel error -framerate 20 -i "$WORK/frames/f%06d.jpg" -c:v libx264 -pix_fmt yuv420p -crf 23 -movflags +faststart "$OUT/review.mp4"

echo "4/4 writing the checklist…"
python3 scripts/exercise-review-checklist.py "$WORK/results.json" "$OUT"
ls -la "$OUT"
