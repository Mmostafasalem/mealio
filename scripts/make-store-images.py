#!/usr/bin/env python3
"""App Store screenshots: one brand colour, word-chip headlines, Nourlo bursting across slides.

    python3 scripts/make-store-images.py ~/Desktop/nourlo-store-screenshots

Inputs:
  <dir>/iphone-6.9/store-*.png, <dir>/ipad-13/store-*.png   (StoreScreenshotTests)
  /tmp/mealio-run/mascot/store-<pose>.png                     (MascotSnapshotTests.testRenderStorePoses)
Writes <dir>/final/iphone-6.9/01-home.png … and <dir>/final/ipad-13/…, at the capture's
size (1320 × 2868 and 2064 × 2752), RGB with no alpha.

The six slides are drawn on one wide strip and cut apart, so Nourlo on the first slide
reaches into the second, the way the store shows them side by side. One idea a slide;
every headline and sticker must describe what the build really does.
"""
import os
import sys

from PIL import Image, ImageDraw, ImageFilter, ImageFont

ROUNDED = "/System/Library/Fonts/SFNSRounded.ttf"
POSES = "/tmp/mealio-run/mascot"

PINK_TOP, PINK_BOTTOM = (240, 128, 160), (222, 92, 128)
INK = (28, 26, 32)
NAVY = (36, 48, 82)          # Nourlo's feet
WHITE = (255, 255, 255)

# capture, output, headline words (a word in *stars* sits on a navy chip), Nourlo pose, sticker
SLIDES = [
    (None, "01-home", ["eat", "well,", "shop", "smart,", "*get*", "*strong*"], "flex", None),
    ("store-2-voice", "02-voice", ["just", "*say*", "what", "you", "ate"], None, "“two eggs and a banana”"),
    ("store-3-meals", "03-meals", ["meals", "from", "*your*", "*kitchen*"], "love", None),
    ("store-4-cook", "04-cook", ["*1,500*", "recipes", "for", "what", "you", "have"], "thinking", "works offline"),
    ("store-5-shop", "05-shop", ["a", "week", "of", "groceries", "*on*", "*budget*"], "happy", "€42.88 left"),
    ("store-6-train", "06-train", ["workouts", "that", "*fit*", "*your*", "*day*"], "jump", "gym · home · cardio"),
]
HOME_CAPTURE = "store-1-home"


def font(size, weight="Bold"):
    f = ImageFont.truetype(ROUNDED, size)
    f.set_variation_by_name(weight)
    return f


def pose(name):
    im = Image.open(os.path.join(POSES, "store-%s.png" % name)).convert("RGBA")
    return im.crop(im.getbbox())


def scaled(im, width):
    return im.resize((round(width), round(im.height * width / im.width)), Image.LANCZOS)


def chips(draw_layer, words, cx, top, max_width, size):
    """Word chips, wrapped and centred on cx. Returns the bottom edge."""
    f = font(size, "Heavy")
    pad_x, pad_y, gap, line_gap = size * 0.34, size * 0.2, size * 0.2, size * 0.24
    items = []
    for w in words:
        hi = w.startswith("*")
        text = w.strip("*")
        tw = draw_layer.textlength(text, font=f)
        items.append((text, hi, tw + 2 * pad_x))
    lines, line, width = [], [], 0
    for it in items:
        need = it[2] + (gap if line else 0)
        if line and width + need > max_width:
            lines.append((line, width)); line, width = [], 0; need = it[2]
        line.append(it); width += need
    lines.append((line, width))
    asc, desc = f.getmetrics()
    h = asc + desc * 0.4 + 2 * pad_y
    y = top
    for line, width in lines:
        x = cx - width / 2
        for text, hi, w in line:
            draw_layer.rounded_rectangle([x, y, x + w, y + h], radius=h * 0.32, fill=NAVY if hi else WHITE)
            draw_layer.text((x + pad_x, y + pad_y), text, font=f, fill=WHITE if hi else INK)
            x += w + gap
        y += h + line_gap
    return y - line_gap


def device(shot, width, ipad):
    screen = scaled(shot, width)
    bezel = round(width * (0.022 if ipad else 0.034))
    radius = round(width * (0.05 if ipad else 0.13))
    out = Image.new("RGBA", (screen.width + 2 * bezel, screen.height + 2 * bezel), (0, 0, 0, 0))
    m = Image.new("L", out.size, 0)
    ImageDraw.Draw(m).rounded_rectangle([0, 0, out.width - 1, out.height - 1], radius=radius + bezel, fill=255)
    out.paste(Image.new("RGBA", out.size, WHITE + (255,)), (0, 0), m)
    s = Image.new("L", screen.size, 0)
    ImageDraw.Draw(s).rounded_rectangle([0, 0, screen.width - 1, screen.height - 1], radius=radius, fill=255)
    out.paste(screen, (bezel, bezel), s)
    return out, radius + bezel


def shadow(canvas, box, radius, blur, strength=95):
    sh = Image.new("L", canvas.size, 0)
    ImageDraw.Draw(sh).rounded_rectangle(box, radius=radius, fill=strength)
    sh = sh.filter(ImageFilter.GaussianBlur(blur))
    canvas.paste(Image.new("RGB", canvas.size, (120, 30, 60)), (0, 0), sh)


def sticker(canvas, text, x, y, size, angle, tail="left"):
    """A white speech-bubble sticker, slightly turned, centred on (x, y)."""
    f = font(size, "Heavy")
    probe = ImageDraw.Draw(Image.new("RGB", (1, 1)))
    tw = probe.textlength(text, font=f)
    pad_x, pad_y = size * 0.6, size * 0.42
    asc, desc = f.getmetrics()
    w, h = tw + 2 * pad_x, asc + desc * 0.4 + 2 * pad_y
    tail_h = size * 0.55
    im = Image.new("RGBA", (round(w + 40), round(h + tail_h + 40)), (0, 0, 0, 0))
    d = ImageDraw.Draw(im)
    d.rounded_rectangle([20, 20, 20 + w, 20 + h], radius=h * 0.45, fill=WHITE + (255,))
    tx = 20 + (w * 0.22 if tail == "left" else w * 0.78)
    d.polygon([(tx - size * 0.35, 20 + h - 2), (tx + size * 0.35, 20 + h - 2), (tx - size * 0.1 if tail == "left" else tx + size * 0.1, 20 + h + tail_h)],
              fill=WHITE + (255,))
    d.text((20 + pad_x, 20 + pad_y), text, font=f, fill=INK)
    im = im.rotate(angle, resample=Image.BICUBIC, expand=True)
    sh = Image.new("L", canvas.size, 0)
    sh.paste(im.split()[3].point(lambda a: a * 0.35), (round(x - im.width / 2), round(y - im.height / 2 + size * 0.25)))
    canvas.paste(Image.new("RGB", canvas.size, (120, 30, 60)), (0, 0), sh.filter(ImageFilter.GaussianBlur(size * 0.3)))
    canvas.paste(im, (round(x - im.width / 2), round(y - im.height / 2)), im)


def build(base, folder, ipad):
    shots = {}
    for capture in [HOME_CAPTURE] + [s[0] for s in SLIDES if s[0]]:
        shots[capture] = Image.open(os.path.join(base, folder, capture + ".png")).convert("RGB")
    W, H = shots[HOME_CAPTURE].size
    N = len(SLIDES)
    strip = Image.new("RGB", (W * N, H))
    d = ImageDraw.Draw(strip)
    for y in range(H):
        t = y / (H - 1)
        d.line([(0, y), (W * N, y)], fill=tuple(round(a + (b - a) * t) for a, b in zip(PINK_TOP, PINK_BOTTOM)))
    # Big soft circles that run across the joins, so the strip reads as one piece.
    glow = Image.new("L", strip.size, 0)
    gd = ImageDraw.Draw(glow)
    for i in range(N + 1):
        cx, cy, r = i * W + (W * 0.15 if i % 2 else -W * 0.1), H * (0.3 if i % 2 else 0.75), W * 0.55
        gd.ellipse([cx - r, cy - r, cx + r, cy + r], fill=46)
    strip.paste(Image.new("RGB", strip.size, WHITE), (0, 0), glow.filter(ImageFilter.GaussianBlur(W * 0.12)))
    d = ImageDraw.Draw(strip)

    head_size = round(W * (0.062 if ipad else 0.088))
    top = round(H * 0.06)
    for i, (capture, _, words, pose_name, sticker_text) in enumerate(SLIDES):
        ox = i * W
        cx = ox + W / 2
        if capture is None:
            # The hero: the name, the headline, and Nourlo flexing, reaching into slide 2.
            name_font = font(round(head_size * 0.62), "Heavy")
            d.text((cx - d.textlength("Nourlo", font=name_font) / 2, top), "Nourlo", font=name_font, fill=WHITE)
            bottom = chips(d, words, cx, top + head_size * 1.15, W * 0.86, head_size)
            sub = font(round(head_size * 0.42), "Semibold")
            line = "Meal plans · calories · groceries · workouts"
            d.text((cx - d.textlength(line, font=sub) / 2, bottom + head_size * 0.5), line, font=sub, fill=WHITE)
            continue
        bottom = chips(d, words, cx, top, W * 0.86, head_size)
        dev, radius = device(shots[capture], W * (0.78 if ipad else 0.74), ipad)
        x, y = round(cx - dev.width / 2), round(bottom + H * 0.045)
        shadow(strip, [x, y + H * 0.012, x + dev.width, y + dev.height], radius, W * 0.035)
        strip.paste(dev, (x, y), dev)
        if pose_name:
            m = scaled(pose(pose_name), W * (0.3 if ipad else 0.42))
            # Bottom right, inside its own slide, leaning on the phone.
            mx = ox + W - m.width * 1.01
            my = H - m.height * (0.97 if pose_name != "jump" else 1.1)
            strip.paste(m, (round(mx), round(my)), m)
        if sticker_text:
            # Top right, over the status-bar icons (never over the clock or the content).
            sticker(strip, sticker_text, x + dev.width * 0.68, y + dev.height * 0.045, round(head_size * 0.42),
                    4 if i % 2 else -3, "right")

    # Nourlo on the hero, last so it sits over the join into slide 2.
    # Big, low, and just over the join: an arm and a bit of the bowl reach into slide 2.
    hero = scaled(pose("flex"), W * (0.82 if ipad else 1.04))
    hx = W * 1.06 - hero.width
    hy = H * (0.36 if ipad else 0.42)
    foot = hy + hero.height
    shadow(strip, [hx + hero.width * 0.25, foot - H * 0.02, hx + hero.width * 0.75, foot + H * 0.015], hero.width * 0.2, W * 0.03, 70)
    strip.paste(hero, (round(hx), round(hy)), hero)

    out_dir = os.path.join(base, "final", folder)
    os.makedirs(out_dir, exist_ok=True)
    for i, slide in enumerate(SLIDES):
        strip.crop((i * W, 0, (i + 1) * W, H)).save(os.path.join(out_dir, slide[1] + ".png"), "PNG", optimize=True)
        print(folder, slide[1], "%d x %d" % (W, H))
    strip.resize((W * N // 6, H // 6)).save(os.path.join(base, "final", folder + "-strip.png"))


def main():
    base = os.path.expanduser(sys.argv[1] if len(sys.argv) > 1 else "~/Desktop/nourlo-store-screenshots")
    for folder, ipad in (("iphone-6.9", False), ("ipad-13", True)):
        build(base, folder, ipad)


if __name__ == "__main__":
    main()
