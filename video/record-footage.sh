#!/bin/bash
# Records the simulator while AdFootageTests walks the app -> video/public/app2.mp4, and the marks
# (seconds into the recording) -> video/public/app2-marks.txt
set -e
cd "$(dirname "$0")/.."
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
SIM="iPhone 17"
xcrun simctl boot "$SIM" 2>/dev/null || true
xcodebuild build-for-testing -project smartmarket.xcodeproj -scheme smartmarket -sdk iphonesimulator -destination "platform=iOS Simulator,name=$SIM" \
  CODE_SIGNING_ALLOWED=YES CODE_SIGN_IDENTITY=- 2>&1 | grep -E "error:|BUILD" | tail -2
rm -f /tmp/app2.mov
xcrun simctl io "$SIM" recordVideo --codec h264 --force /tmp/app2.mov 2>/dev/null &
REC=$!
sleep 2
START=$(python3 -c 'import time; print(time.time())')
TEST_RUNNER_NOURLO_AD_FOOTAGE=1 xcodebuild test-without-building -project smartmarket.xcodeproj -scheme smartmarket -sdk iphonesimulator \
  -destination "platform=iOS Simulator,name=$SIM" -only-testing:smartmarketUITests/AdFootageTests CODE_SIGNING_ALLOWED=YES CODE_SIGN_IDENTITY=- 2>&1 \
  | grep -E "AD-MARK|\*\* TEST" > /tmp/app2-marks.log || true
kill -INT $REC; wait $REC 2>/dev/null || true
python3 - "$START" <<'PY'
import re, sys
start = float(sys.argv[1]) - 2.0   # the recording began two seconds before START
out = []
for line in open('/tmp/app2-marks.log'):
    m = re.search(r'AD-MARK (\S+) \S+ epoch (\S+)', line)
    if m: out.append(f"{m.group(1)} {float(m.group(2)) - start:.2f}")
open('video/public/app2-marks.txt', 'w').write("\n".join(out) + "\n")
print("\n".join(out))
PY
video/node_modules/ffmpeg-static/ffmpeg -y -loglevel error -i /tmp/app2.mov -r 30 -c:v libx264 -crf 18 -pix_fmt yuv420p -an video/public/app2.mp4
tail -1 /tmp/app2-marks.log
