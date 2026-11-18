#!/usr/bin/env python3
"""App Store images: each raw capture from StoreScreenshotTests, framed, with a headline.

    python3 scripts/make-store-images.py ~/Desktop/nourlo-store-screenshots

reads <dir>/iphone-6.9/store-*.png and <dir>/ipad-13/store-*.png and writes
<dir>/final/iphone-6.9/01-home.png … at the exact size of the capture
(1320 × 2868 and 2064 × 2752, the sizes App Store Connect asks for), RGB with no alpha.
Every headline must describe what the build really does.
"""
import os
import sys

from PIL import Image, ImageDraw, ImageFilter, ImageFont

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
FONT = "/System/Library/Fonts/SFNS.ttf"
MASCOT = os.path.join(ROOT, "smartmarket/Assets.xcassets/BowlMascotCelebrate.imageset/mascot.png")

INK = (26, 24, 28)
SUB = (104, 92, 98)
TOP = (251, 246, 240)       # app background cream
BOTTOM = (247, 218, 226)    # soft brand pink
FRAME = (24, 22, 26)

# (capture, output name, headline, subline)
SLIDES = [
    ("store-1-home", "01-home", "Your day at a glance", "Calories and macros against your own targets"),
    ("store-2-voice", "02-voice", "Just say what you ate", "Voice logging, recognised on your device"),
    ("store-3-meals", "03-meals", "Meals from your kitchen", "A daily plan built from the food you have"),
    ("store-4-cook", "04-cook", "Cook with what you have", "About 1,500 recipes, matched to your stock"),
    ("store-5-shop", "05-shop", "Shop to your budget", "A balanced week of groceries, within budget"),
    ("store-6-train", "06-train", "Workouts that fit your day", "Gym, home, cardio or mobility, sized to your time"),
]


def font(size, weight):
    f = ImageFont.truetype(FONT, size)
    f.set_variation_by_name(weight)
    return f


def gradient(w, h):
    img = Image.new("RGB", (w, h))
    px = ImageDraw.Draw(img)
    for y in range(h):
        t = y / (h - 1)
        px.line([(0, y), (w, y)], fill=tuple(round(a + (b - a) * t) for a, b in zip(TOP, BOTTOM)))
    return img


def rounded(img, radius):
    mask = Image.new("L", img.size, 0)
    ImageDraw.Draw(mask).rounded_rectangle([0, 0, img.width - 1, img.height - 1], radius=radius, fill=255)
    return mask


def centred_text(draw, text, f, y, w, colour, max_width):
    # Shrink until it fits on one line.
    size = f.size
    while draw.textlength(text, font=f) > max_width and size > 10:
        size -= 2
        f = font(size, "Bold" if colour == INK else "Regular")
    x = (w - draw.textlength(text, font=f)) / 2
    draw.text((x, y), text, font=f, fill=colour)
    return f.getbbox(text)[3]


def make(capture_path, out_path, headline, subline, ipad, mascot):
    shot = Image.open(capture_path).convert("RGB")
    w, h = shot.size
    canvas = gradient(w, h)
    draw = ImageDraw.Draw(canvas)

    top = round(h * (0.05 if ipad else 0.055))
    head = font(round(w * (0.058 if ipad else 0.078)), "Bold")
    sub = font(round(w * (0.030 if ipad else 0.040)), "Regular")
    used = centred_text(draw, headline, head, top, w, INK, w * 0.9)
    centred_text(draw, subline, sub, top + used + round(h * 0.018), w, SUB, w * 0.9)

    # The device: the capture inside a dark frame, sized to fill what's left.
    text_bottom = top + used + round(h * 0.018) + sub.size + round(h * 0.04)
    scale = 0.80 if ipad else 0.80
    sw = round(w * scale)
    sh = round(shot.height * sw / shot.width)
    if text_bottom + sh > h - round(h * 0.03):          # keep a margin at the bottom
        sh = h - round(h * 0.03) - text_bottom
        sw = round(shot.width * sh / shot.height)
    screen = shot.resize((sw, sh), Image.LANCZOS)
    bezel = round(sw * (0.022 if ipad else 0.035))
    radius = round(sw * (0.045 if ipad else 0.13))
    fw, fh = sw + 2 * bezel, sh + 2 * bezel
    fx, fy = (w - fw) // 2, text_bottom

    shadow = Image.new("L", (w, h), 0)
    ImageDraw.Draw(shadow).rounded_rectangle([fx, fy + bezel, fx + fw, fy + fh + bezel], radius=radius + bezel, fill=90)
    shadow = shadow.filter(ImageFilter.GaussianBlur(round(w * 0.025)))
    canvas.paste(Image.new("RGB", (w, h), (120, 70, 90)), (0, 0), shadow)

    frame = Image.new("RGB", (fw, fh), FRAME)
    canvas.paste(frame, (fx, fy), rounded(frame, radius + bezel))
    canvas.paste(screen, (fx + bezel, fy + bezel), rounded(screen, radius))

    if mascot is not None:
        m = mascot.copy()
        size = round(w * (0.13 if ipad else 0.17))
        m.thumbnail((size, size), Image.LANCZOS)
        # Sitting on the frame's top-right corner, clear of the subline.
        canvas.paste(m, (fx + fw - round(m.width * 0.78), fy - round(m.height * 0.45)), m)

    canvas.save(out_path, "PNG", optimize=True)
    return canvas.size


def main():
    base = os.path.expanduser(sys.argv[1] if len(sys.argv) > 1 else "~/Desktop/nourlo-store-screenshots")
    mascot = Image.open(MASCOT).convert("RGBA") if os.path.exists(MASCOT) else None
    for device, ipad in (("iphone-6.9", False), ("ipad-13", True)):
        out_dir = os.path.join(base, "final", device)
        os.makedirs(out_dir, exist_ok=True)
        for i, (capture, name, headline, subline) in enumerate(SLIDES):
            src = os.path.join(base, device, capture + ".png")
            if not os.path.exists(src):
                print("missing", src)
                continue
            size = make(src, os.path.join(out_dir, name + ".png"), headline, subline, ipad, mascot if i == 0 else None)
            print(device, name, "%d x %d" % size)


if __name__ == "__main__":
    main()
