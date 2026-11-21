#!/bin/bash
# ./make-ad.sh <CompositionId> <timeline name> <output name>: picture + score -> ~/Desktop/<output>.mp4
set -e
cd "$(dirname "$0")"
FF=node_modules/ffmpeg-static/ffmpeg
npx remotion render src/index.ts $1 out/$3-picture.mp4 --log=error
if [ -f src/ads/$2.music ]; then node src/ads/music.mjs $2 out/$3.wav; else node src/ads/score.mjs $2 out/$3.wav; fi
$FF -y -loglevel error -i out/$3-picture.mp4 -i out/$3.wav -c:v libx264 -preset slow -crf 20 -pix_fmt yuv420p -af "loudnorm=I=-14:TP=-1.2:LRA=11" -ar 48000 -c:a aac -b:a 256k -shortest -movflags +faststart out/$3.mp4
$FF -y -loglevel error -i out/$3.mp4 -vf "fps=2,scale=120:-1,tile=13x4" -frames:v 1 out/$3-strip.png
mkdir -p ~/Desktop/nourlo-ads && cp out/$3.mp4 ~/Desktop/nourlo-ads/
echo "done $3"
