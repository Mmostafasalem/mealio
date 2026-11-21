#!/bin/bash
# ./mux-story.sh <id>: soundtrack + final mix for a story whose picture is already in out/<id>-picture.mp4
set -e
cd "$(dirname "$0")"
FF=node_modules/ffmpeg-static/ffmpeg; id=$1
node src/story/score.mjs $id out/$id.wav
$FF -y -loglevel error -i out/$id-picture.mp4 -i out/$id.wav -c:v libx264 -preset slow -crf 20 -pix_fmt yuv420p -af "loudnorm=I=-14:TP=-1.2:LRA=11" \
  -ar 48000 -c:a aac -b:a 256k -shortest -movflags +faststart out/$id.mp4
$FF -y -loglevel error -i out/$id.mp4 -vf "fps=2,scale=120:-1,tile=12x4" -frames:v 1 out/$id-strip.png
mkdir -p ~/Desktop/nourlo-ads && cp out/$id.mp4 ~/Desktop/nourlo-ads/$id.mp4
echo "done $id"
