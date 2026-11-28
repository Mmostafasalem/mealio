#!/bin/bash
# ./stills.sh <CompositionId> <sec> <sec> ... : renders stills and joins them into out/<id>-row.png
cd "$(dirname "$0")"
id=$1; shift
rm -f out/st-*.png
for t in "$@"; do
  f=$(python3 -c "print(round($t*30))")
  npx remotion still src/index.ts $id out/st-$t.png --frame=$f --scale=0.3 2>&1 | grep -iE "error|Error" | head -3
done
python3 -I - "$id" "$@" <<'PY'
import sys
from PIL import Image
id, ts = sys.argv[1], sys.argv[2:]
ims = [Image.open(f"out/st-{t}.png") for t in ts]
w, h = ims[0].size
row = Image.new("RGB", (len(ims) * (w + 6), h), "#888")
for i, im in enumerate(ims): row.paste(im, (i * (w + 6), 0))
row.save(f"out/{id}-row.png")
PY
