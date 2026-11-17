#!/bin/bash
# ./make-stories.sh [id ...]: renders Nourlo's performance for each scripted advert (src/story/ads/<id>.json)
# with the app's own mascot rig, then the picture and the soundtrack -> ~/Desktop/nourlo-ads/<id>.mp4
set -e
cd "$(dirname "$0")"
FF=node_modules/ffmpeg-static/ffmpeg
IDS="$*"; [ -z "$IDS" ] && IDS=$(ls src/story/ads/*.json | xargs -n1 basename | sed 's/\.json$//')
rm -rf /tmp/mealio-run/stories && mkdir -p /tmp/mealio-run/stories
for id in $IDS; do cp src/story/ads/$id.json /tmp/mealio-run/stories/; done
[ -z "$SKIP_RIG" ] && ( cd .. && TEST_RUNNER_NOURLO_MASCOT_CLIPS=1 DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project smartmarket.xcodeproj -scheme smartmarket \
  -sdk iphonesimulator -destination 'platform=iOS Simulator,name=iPhone 17' test -only-testing:smartmarketTests/MascotSnapshotTests/testRenderStories \
  CODE_SIGNING_ALLOWED=YES CODE_SIGN_IDENTITY=- 2>&1 | grep -E "error:|\*\* TEST" | tail -3 )
mkdir -p ~/Desktop/nourlo-ads out
for id in $IDS; do
  rm -rf public/clips/$id && cp -R /tmp/mealio-run/clips/$id public/clips/$id
  comp="Story-$id"
  npx remotion render src/index.ts $comp out/$id-picture.mp4 --log=error
  node src/story/score.mjs $id out/$id.wav
  $FF -y -loglevel error -i out/$id-picture.mp4 -i out/$id.wav -c:v libx264 -preset slow -crf 20 -pix_fmt yuv420p -af "loudnorm=I=-14:TP=-1.2:LRA=11" \
    -ar 48000 -c:a aac -b:a 256k -shortest -movflags +faststart out/$id.mp4
  $FF -y -loglevel error -i out/$id.mp4 -vf "fps=2,scale=120:-1,tile=12x4" -frames:v 1 out/$id-strip.png
  cp out/$id.mp4 ~/Desktop/nourlo-ads/$id.mp4
  echo "done $id"
done
