#!/usr/bin/env python3
"""App Store product page header: Nourlo, the name and a tagline in the centre (the part
every crop keeps), real app screens on both sides.

    python3 scripts/make-store-header.py ~/Desktop/nourlo-store-screenshots

reads <dir>/iphone-6.9/store-*.png (StoreScreenshotTests) and writes
<dir>/final/header-5244x2950.png and header-3840x1646.png, the two sizes
App Store Connect accepts for the header asset.
"""
import os
import sys

from PIL import Image, ImageDraw, ImageFilter, ImageFont

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
FONT = "/System/Library/Fonts/SFNS.ttf"
MASCOT = os.path.join(ROOT, "smartmarket/Assets.xcassets/BowlMascotCelebrate.imageset/mascot.png")
INK, SUB = (26, 24, 28), (104, 92, 98)
TOP, BOTTOM = (251, 246, 240), (247, 218, 226)
FRAME = (24, 22, 26)
# Outer left, inner left, inner right, outer right.
SCREENS = ["store-4-cook", "store-1-home", "store-3-meals", "store-6-train"]
TITLE = "Nourlo"
TAGLINE = ["Meal plans and calorie tracking,", "budget groceries and workouts"]


def font(size, weight):
    f = ImageFont.truetype(FONT, size)
    f.set_variation_by_name(weight)
    return f


def fit(draw, text, size, weight, max_width):
    f = font(size, weight)
    while draw.textlength(text, font=f) > max_width and size > 10:
        size -= 4
        f = font(size, weight)
    return f


def phone(shot, height):
    w = round(shot.width * height / shot.height)
    screen = shot.resize((w, height), Image.LANCZOS)
    bezel, radius = round(w * 0.035), round(w * 0.13)
    framed = Image.new("RGBA", (w + 2 * bezel, height + 2 * bezel), (0, 0, 0, 0))
    mask = Image.new("L", framed.size, 0)
    ImageDraw.Draw(mask).rounded_rectangle([0, 0, framed.width - 1, framed.height - 1], radius=radius + bezel, fill=255)
    framed.paste(Image.new("RGBA", framed.size, FRAME + (255,)), (0, 0), mask)
    inner = Image.new("L", screen.size, 0)
    ImageDraw.Draw(inner).rounded_rectangle([0, 0, w - 1, height - 1], radius=radius, fill=255)
    framed.paste(screen, (bezel, bezel), inner)
    return framed


def make(base, W, H, out):
    canvas = Image.new("RGB", (W, H))
    d = ImageDraw.Draw(canvas)
    for y in range(H):
        t = y / (H - 1)
        d.line([(0, y), (W, y)], fill=tuple(round(a + (b - a) * t) for a, b in zip(TOP, BOTTOM)))

    # Phones on both sides, the outer pair lower, with a soft shadow.
    ph = round(H * 0.74)
    phones = [phone(Image.open(os.path.join(base, "iphone-6.9", s + ".png")).convert("RGB"), ph) for s in SCREENS]
    pw = phones[0].width
    column = W * 0.19                        # half the width kept clear for the title
    gap = round(pw * 0.08)
    inner = column + pw / 2
    outer = inner + pw + gap
    centres = [W / 2 - outer, W / 2 - inner, W / 2 + inner, W / 2 + outer]
    tops = [H * 0.24, H * 0.16, H * 0.16, H * 0.24]
    shadow = Image.new("L", (W, H), 0)
    sd = ImageDraw.Draw(shadow)
    for cx, top in zip(centres, tops):
        x = round(cx - pw / 2)
        sd.rounded_rectangle([x, round(top + H * 0.02), x + pw, round(top + H * 0.02) + phones[0].height],
                             radius=round(pw * 0.16), fill=80)
    shadow = shadow.filter(ImageFilter.GaussianBlur(round(H * 0.025)))
    canvas.paste(Image.new("RGB", (W, H), (120, 70, 90)), (0, 0), shadow)
    for img, cx, top in zip(phones, centres, tops):
        canvas.paste(img, (round(cx - pw / 2), round(top)), img)

    # The centre: Nourlo, the name, the tagline.
    max_w = column * 2 * 0.92
    mascot = Image.open(MASCOT).convert("RGBA")
    mascot.thumbnail((round(H * 0.30), round(H * 0.30)), Image.LANCZOS)
    title = fit(d, TITLE, round(H * 0.15), "Heavy", max_w)
    tag_size = min(fit(d, line, round(H * 0.042), "Medium", max_w).size for line in TAGLINE)
    tag = font(tag_size, "Medium")
    title_h = title.getbbox(TITLE)[3]
    block = mascot.height + round(H * 0.02) + title_h + round(H * 0.035) + len(TAGLINE) * round(tag_size * 1.3)
    y = (H - block) / 2
    canvas.paste(mascot, (round((W - mascot.width) / 2), round(y)), mascot)
    y += mascot.height + round(H * 0.02)
    d.text(((W - d.textlength(TITLE, font=title)) / 2, y), TITLE, font=title, fill=INK)
    y += title_h + round(H * 0.035)
    for line in TAGLINE:
        d.text(((W - d.textlength(line, font=tag)) / 2, y), line, font=tag, fill=SUB)
        y += round(tag_size * 1.3)

    canvas.save(out, "PNG", optimize=True)
    print(os.path.basename(out), "%d x %d" % canvas.size)


def main():
    base = os.path.expanduser(sys.argv[1] if len(sys.argv) > 1 else "~/Desktop/nourlo-store-screenshots")
    os.makedirs(os.path.join(base, "final"), exist_ok=True)
    for W, H in ((5244, 2950), (3840, 1646)):
        make(base, W, H, os.path.join(base, "final", "header-%dx%d.png" % (W, H)))


if __name__ == "__main__":
    main()
