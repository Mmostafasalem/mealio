#!/bin/bash
# Renders a few frames of each ad and lays them side by side for a quick look.
cd "$(dirname "$0")" && rm -f out/a-*.png out/s-*.png
for spec in "Animated a 40" "Animated a 160" "Animated a 330" "Animated a 440" "Animated a 520" "Animated a 630" "BowlStory s 100" "BowlStory s 190" "BowlStory s 290" "BowlStory s 400" "BowlStory s 490"; do
  set -- $spec
  npx remotion still src/index.ts $1 out/$2-$3.png --frame=$3 --scale=0.3 2>&1 | grep -iE "error" | head -2
done
python3 -I - <<'PY'
from PIL import Image
import glob
for prefix in ("a", "s"):
    files = sorted(glob.glob(f"out/{prefix}-*.png"), key=lambda p: int(p.split("-")[1].split(".")[0]))
    ims = [Image.open(f) for f in files]
    w, h = ims[0].size
    sheet = Image.new("RGB", (w * len(ims) + 10 * (len(ims) - 1), h), "#888")
    for i, im in enumerate(ims):
        sheet.paste(im, (i * (w + 10), 0))
    sheet.save(f"out/sheet-{prefix}.png")
    print(prefix, len(ims), sheet.size)
PY
