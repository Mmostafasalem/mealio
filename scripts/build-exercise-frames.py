#!/usr/bin/env python3
"""Build the exercise drawings (smartmarket/Resources/ExerciseFrames.json.zlib, deflated JSON).

The drawings are from Workout Guide by Bryl Lim (https://github.com/bryllim/workout-guide),
based on Everkinetic (https://github.com/everkinetic/data), both CC BY-SA 4.0: the
app credits them under every drawing, and this adapted set is CC BY-SA 4.0 too.
Each exercise has three frames (512 x 512, white line art). This script keeps the
ones the app uses, converts each outline to absolute line/curve commands the app
draws as a vector, and turns the worked-muscle marks in
`scripts/exercise-frame-muscles.json` into red shapes drawn under the lines. Frames drawn with much heavier strokes than the rest are
re-inked along their centre lines at the usual line weight, so the drawings look even.

A mark picks areas of the body between the drawn lines (numbered on the review
sheets) and a band along the muscle; the red is where both agree, so it follows
the drawing's own muscle outlines.

  git clone --depth 1 https://github.com/bryllim/workout-guide /tmp/wg-repo
  scripts/build-exercise-frames.py /tmp/wg-repo                 # writes the resource
  scripts/build-exercise-frames.py /tmp/wg-repo --sheets DIR    # numbered-area sheets for marking
  scripts/build-exercise-frames.py /tmp/wg-repo --check DIR     # the result, red under the lines

Needs numpy, opencv-python-headless, pillow and svgelements.
"""
import json, os, re, sys, zlib, colorsys
from pathlib import Path
import numpy as np
import cv2
from PIL import Image, ImageDraw, ImageFont
from svgelements import Path as SVGPath, Move, Line, CubicBezier, QuadraticBezier, Arc, Close

ROOT = Path(__file__).resolve().parent.parent
# Raw deflate (no zlib header), which is what Apple's `NSData.decompressed(using: .zlib)` reads.
OUT = ROOT / "smartmarket" / "Resources" / "ExerciseFrames.json.zlib"
MARKS = Path(os.environ.get("EXERCISE_MARKS", ROOT / "scripts" / "exercise-frame-muscles.json"))

# App exercise id -> Workout Guide drawing.
DRAWING = {
    "back-squat": "squat", "goblet-squat": "goblet-squat", "romanian-deadlift": "romanian-deadlift", "leg-press": "leg-press",
    "walking-lunge": "walking-lunge", "bench-press": "bench-press", "dumbbell-bench-press": "dumbbell-bench-press",
    "overhead-press": "overhead-press", "lat-pulldown": "lat-pulldown", "seated-row": "seated-row",
    "dumbbell-row": "one-arm-dumbbell-row", "cable-woodchop": "cable-woodchop", "hanging-knee-raise": "hanging-knee-raise",
    "bodyweight-squat": "bodyweight-squat", "reverse-lunge": "reverse-lunge", "glute-bridge": "glute-bridge", "step-up": "step-up",
    "push-up": "push-up", "pike-push-up": "pike-push-up", "chair-dip": "chair-dip", "superman": "superman", "plank": "plank",
    "dead-bug": "dead-bug", "mountain-climber": "mountain-climber", "burpee": "burpee",
    "brisk-walk": "walking", "easy-run": "running", "run-intervals": "running", "cycling": "cycling", "rowing": "rowing",
    "jump-rope": "jump-rope", "stair-climb": "stair-climber", "swimming": "swimming", "cat-cow": "cat-cow-stretch",
    "worlds-greatest-stretch": "worlds-greatest-stretch", "hip-flexor-stretch": "kneeling-hip-flexor-stretch",
    "hamstring-stretch": "hamstring-stretch", "thoracic-rotation": "torso-twist-stretch", "shoulder-circles": "arm-circles",
    "childs-pose": "childs-pose", "lateral-raise": "lateral-raise", "reverse-fly": "bent-over-rear-delt-raise",
    "single-leg-deadlift": "single-leg-romanian-deadlift", "side-lunge": "lateral-lunge", "jump-squat": "jump-squat",
    "leg-extension-crunch": "seated-knee-tuck", "windmill-toe-touch": "toe-touch", "jumping-jack": "jumping-jack",
    "high-knees": "high-knees", "side-shuffle": "lateral-shuffle",
    # Exercises added with the drawings: the catalogue id is the drawing's own name.
    "incline-dumbbell-press": "incline-dumbbell-press", "dumbbell-fly": "dumbbell-fly", "cable-fly": "cable-fly", "pec-deck": "pec-deck",
    "close-grip-bench-press": "close-grip-bench-press", "barbell-row": "barbell-row", "face-pull": "face-pull", "pull-up": "pull-up",
    "chin-up": "chin-up", "straight-arm-pulldown": "straight-arm-pulldown", "arnold-press": "arnold-press", "front-raise": "front-raise",
    "upright-row": "upright-row", "shrug": "shrug", "bicep-curl": "bicep-curl", "hammer-curl": "hammer-curl",
    "preacher-curl": "preacher-curl", "tricep-pushdown": "tricep-pushdown", "skull-crusher": "skull-crusher", "overhead-tricep-extension": "overhead-tricep-extension",
    "deadlift": "deadlift", "front-squat": "front-squat", "bulgarian-split-squat": "bulgarian-split-squat", "hip-thrust": "hip-thrust",
    "leg-extension": "leg-extension", "lying-leg-curl": "lying-leg-curl", "standing-calf-raise": "standing-calf-raise", "kettlebell-swing": "kettlebell-swing",
    "diamond-push-up": "diamond-push-up", "incline-push-up": "incline-push-up", "wall-sit": "wall-sit", "side-plank": "side-plank",
    "bicycle-crunch": "bicycle-crunch", "russian-twist": "russian-twist", "crunch": "crunch", "lying-leg-raise": "lying-leg-raise",
    "bird-dog": "bird-dog", "inverted-row": "inverted-row", "donkey-kick": "donkey-kick", "v-up": "v-up",
    "battle-ropes": "battle-ropes", "bear-crawl": "bear-crawl", "skater-hop": "skater-hop", "plank-jack": "plank-jack",
    "elliptical": "elliptical", "doorway-chest-stretch": "doorway-chest-stretch", "standing-quad-stretch": "standing-quad-stretch", "butterfly-stretch": "butterfly-stretch",
    "cross-body-shoulder-stretch": "cross-body-shoulder-stretch", "inchworm": "inchworm",
    # The rest of the library, added in full.
    "incline-bench-press": "incline-bench-press", "decline-bench-press": "decline-bench-press", "machine-chest-press": "machine-chest-press", "weighted-push-up": "weighted-push-up",
    "seated-dumbbell-press": "seated-dumbbell-press", "cable-lateral-raise": "cable-lateral-raise", "rear-delt-fly": "rear-delt-fly", "reverse-pec-deck": "reverse-pec-deck",
    "t-bar-row": "t-bar-row", "dumbbell-bent-over-row": "dumbbell-bent-over-row", "chest-supported-row": "chest-supported-row", "machine-row": "machine-row",
    "close-grip-lat-pulldown": "close-grip-lat-pulldown", "assisted-pull-up": "assisted-pull-up", "weighted-pull-up": "weighted-pull-up", "hack-squat": "hack-squat",
    "leg-curl": "leg-curl", "seated-leg-curl": "seated-leg-curl", "good-morning": "good-morning", "seated-calf-raise": "seated-calf-raise",
    "cable-curl": "cable-curl", "reverse-curl": "reverse-curl", "wrist-curl": "wrist-curl", "dip": "dip",
    "assisted-dip": "assisted-dip", "hanging-leg-raise": "hanging-leg-raise", "cable-crunch": "cable-crunch", "ab-wheel": "ab-wheel",
    "incline-cable-fly": "incline-cable-fly", "decline-dumbbell-press": "decline-dumbbell-press", "smith-machine-bench-press": "smith-machine-bench-press", "landmine-press": "landmine-press",
    "chest-dip": "chest-dip", "weighted-dip": "weighted-dip", "machine-shoulder-press": "machine-shoulder-press", "standing-dumbbell-press": "standing-dumbbell-press",
    "push-press": "push-press", "machine-lateral-raise": "machine-lateral-raise", "cable-front-raise": "cable-front-raise", "plate-front-raise": "plate-front-raise",
    "cable-rear-delt-fly": "cable-rear-delt-fly", "pendlay-row": "pendlay-row", "meadows-row": "meadows-row", "single-arm-cable-row": "single-arm-cable-row",
    "wide-grip-lat-pulldown": "wide-grip-lat-pulldown", "neutral-grip-pull-up": "neutral-grip-pull-up", "assisted-chin-up": "assisted-chin-up", "weighted-chin-up": "weighted-chin-up",
    "rack-pull": "rack-pull", "back-extension": "back-extension", "dumbbell-shrug": "dumbbell-shrug", "smith-machine-squat": "smith-machine-squat",
    "belt-squat": "belt-squat", "sumo-deadlift": "sumo-deadlift", "trap-bar-deadlift": "trap-bar-deadlift", "nordic-hamstring-curl": "nordic-hamstring-curl",
    "split-squat": "split-squat", "cable-kickback": "cable-kickback", "hip-abduction-machine": "hip-abduction-machine", "single-leg-glute-bridge": "single-leg-glute-bridge",
    "barbell-glute-bridge": "barbell-glute-bridge", "dumbbell-glute-bridge": "dumbbell-glute-bridge", "dumbbell-hip-thrust": "dumbbell-hip-thrust", "smith-machine-hip-thrust": "smith-machine-hip-thrust",
    "smith-machine-romanian-deadlift": "smith-machine-romanian-deadlift", "dumbbell-romanian-deadlift": "dumbbell-romanian-deadlift", "kettlebell-romanian-deadlift": "kettlebell-romanian-deadlift", "cable-pull-through": "cable-pull-through",
    "machine-glute-kickback": "machine-glute-kickback", "cable-standing-hip-abduction": "cable-standing-hip-abduction", "cable-standing-hip-adduction": "cable-standing-hip-adduction", "hip-adduction-machine": "hip-adduction-machine",
    "smith-machine-bulgarian-split-squat": "smith-machine-bulgarian-split-squat", "smith-machine-reverse-lunge": "smith-machine-reverse-lunge", "smith-machine-split-squat": "smith-machine-split-squat", "heel-elevated-goblet-squat": "heel-elevated-goblet-squat",
    "dumbbell-sumo-squat": "dumbbell-sumo-squat", "dumbbell-sumo-deadlift": "dumbbell-sumo-deadlift", "front-foot-elevated-split-squat": "front-foot-elevated-split-squat", "deficit-reverse-lunge": "deficit-reverse-lunge",
    "dumbbell-lateral-lunge": "dumbbell-lateral-lunge", "dumbbell-curtsy-lunge": "dumbbell-curtsy-lunge", "landmine-squat": "landmine-squat", "landmine-romanian-deadlift": "landmine-romanian-deadlift",
    "glute-focused-back-extension": "glute-focused-back-extension", "reverse-hyperextension": "reverse-hyperextension", "donkey-calf-raise": "donkey-calf-raise", "leg-press-calf-raise": "leg-press-calf-raise",
    "incline-dumbbell-curl": "incline-dumbbell-curl", "concentration-curl": "concentration-curl", "ez-bar-curl": "ez-bar-curl", "spider-curl": "spider-curl",
    "rope-hammer-curl": "rope-hammer-curl", "drag-curl": "drag-curl", "rope-tricep-pushdown": "rope-tricep-pushdown", "dumbbell-skull-crusher": "dumbbell-skull-crusher",
    "single-dumbbell-skullcrusher": "single-dumbbell-skullcrusher", "dumbbell-overhead-tricep-extension": "dumbbell-overhead-tricep-extension", "single-arm-dumbbell-tricep-extension": "single-arm-dumbbell-tricep-extension", "bench-dip": "bench-dip",
    "tricep-kickback": "tricep-kickback", "wrist-extension": "wrist-extension", "farmer-carry": "farmer-carry", "reverse-crunch": "reverse-crunch",
    "pallof-press": "pallof-press", "half-kneeling-pallof-press": "half-kneeling-pallof-press", "cable-pallof-hold": "cable-pallof-hold", "captains-chair-knee-raise": "captains-chair-knee-raise",
    "decline-sit-up": "decline-sit-up", "weighted-crunch": "weighted-crunch", "weighted-russian-twist": "weighted-russian-twist", "dumbbell-side-bend": "dumbbell-side-bend",
    "assault-bike": "assault-bike", "skierg": "skierg", "hiking": "hiking", "treadmill-incline-walk": "treadmill-incline-walk",
    "knee-push-up": "knee-push-up", "wide-push-up": "wide-push-up", "decline-push-up": "decline-push-up", "feet-elevated-pike-push-up": "feet-elevated-pike-push-up",
    "archer-push-up": "archer-push-up", "typewriter-push-up": "typewriter-push-up", "explosive-push-up": "explosive-push-up", "hindu-push-up": "hindu-push-up",
    "scapular-push-up": "scapular-push-up", "push-up-shoulder-tap": "push-up-shoulder-tap", "wall-push-up": "wall-push-up", "wall-walk": "wall-walk",
    "wall-handstand-push-up": "wall-handstand-push-up", "handstand-push-up": "handstand-push-up", "doorway-row": "doorway-row", "towel-row": "towel-row",
    "prone-y-raise": "prone-y-raise", "prone-t-raise": "prone-t-raise", "superman-hold": "superman-hold", "reverse-snow-angel": "reverse-snow-angel",
    "dead-hang": "dead-hang", "active-hang": "active-hang", "scapular-pull-up": "scapular-pull-up", "negative-pull-up": "negative-pull-up",
    "commando-pull-up": "commando-pull-up", "l-sit-pull-up": "l-sit-pull-up", "towel-pull-up": "towel-pull-up", "pistol-squat": "pistol-squat",
    "assisted-pistol-squat": "assisted-pistol-squat", "shrimp-squat": "shrimp-squat", "cossack-squat": "cossack-squat", "sissy-squat": "sissy-squat",
    "forward-lunge": "forward-lunge", "curtsy-lunge": "curtsy-lunge", "skater-squat": "skater-squat", "single-leg-box-squat": "single-leg-box-squat",
    "step-down": "step-down", "calf-raise": "calf-raise", "single-leg-calf-raise": "single-leg-calf-raise", "glute-bridge-march": "glute-bridge-march",
    "frog-pump": "frog-pump", "fire-hydrant": "fire-hydrant", "clamshell": "clamshell", "hip-airplane": "hip-airplane",
    "side-lying-hip-abduction": "side-lying-hip-abduction", "side-lying-leg-raise": "side-lying-leg-raise", "lying-hamstring-walkout": "lying-hamstring-walkout", "towel-hamstring-curl": "towel-hamstring-curl",
    "stability-ball-hamstring-curl": "stability-ball-hamstring-curl", "banded-glute-bridge": "banded-glute-bridge", "banded-hip-thrust": "banded-hip-thrust", "banded-frog-pump": "banded-frog-pump",
    "banded-clamshell": "banded-clamshell", "banded-lateral-walk": "banded-lateral-walk", "banded-monster-walk": "banded-monster-walk", "banded-squat": "banded-squat",
    "banded-donkey-kick": "banded-donkey-kick", "banded-fire-hydrant": "banded-fire-hydrant", "banded-kickback": "banded-kickback", "banded-standing-hip-abduction": "banded-standing-hip-abduction",
    "banded-seated-hip-abduction": "banded-seated-hip-abduction", "band-pull-apart": "band-pull-apart", "banded-face-pull": "banded-face-pull", "banded-row": "banded-row",
    "banded-lat-pulldown": "banded-lat-pulldown", "banded-pallof-press": "banded-pallof-press", "banded-woodchop": "banded-woodchop", "banded-dead-bug": "banded-dead-bug",
    "hollow-body-hold": "hollow-body-hold", "hollow-rock": "hollow-rock", "flutter-kick": "flutter-kick", "heel-tap": "heel-tap",
    "plank-shoulder-tap": "plank-shoulder-tap", "bear-plank": "bear-plank", "crab-walk": "crab-walk", "l-sit-hold": "l-sit-hold",
    "side-plank-hip-dip": "side-plank-hip-dip", "copenhagen-plank": "copenhagen-plank", "dragon-flag": "dragon-flag", "half-burpee": "half-burpee",
    "squat-thrust": "squat-thrust", "fast-feet": "fast-feet", "sprawl": "sprawl", "seal-jack": "seal-jack",
    "leg-swings-stretch": "leg-swings-stretch", "seated-forward-fold-stretch": "seated-forward-fold-stretch", "wall-calf-stretch": "wall-calf-stretch",
}

SIZE = 512

# ---------- Areas of the body ----------

def body_masks(assets, slug, i):
    """Line pixels, and the body (inside the outline, small gaps in the outline closed)."""
    a = np.asarray(Image.open(assets / slug / f"frame-{i}.png").convert("RGBA").resize((SIZE, SIZE)))[:, :, 3]
    line = (a > 90).astype(np.uint8)
    k = cv2.getStructuringElement(cv2.MORPH_ELLIPSE, (9, 9))
    free = (1 - cv2.dilate(line, k)).astype(np.uint8)
    big = np.ones((SIZE + 2, SIZE + 2), np.uint8)
    big[1:-1, 1:-1] = free
    cv2.floodFill(big, np.zeros((SIZE + 4, SIZE + 4), np.uint8), (0, 0), 2)
    body = cv2.erode((big[1:-1, 1:-1] != 2).astype(np.uint8), k)
    return line.astype(bool), np.maximum(body, line).astype(bool)

def areas(assets, slug, i):
    """The body split into numbered areas by the drawn lines, numbered top to bottom, left to right."""
    line, body = body_masks(assets, slug, i)
    walls = cv2.dilate(line.astype(np.uint8), cv2.getStructuringElement(cv2.MORPH_ELLIPSE, (5, 5))).astype(bool)
    n, labels, stats, centres = cv2.connectedComponentsWithStats((body & ~walls).astype(np.uint8), connectivity=4)
    keep = [r for r in range(1, n) if stats[r, cv2.CC_STAT_AREA] >= 60]
    keep.sort(key=lambda r: (int(centres[r][1] // 24), centres[r][0]))
    numbered = np.zeros_like(labels)
    spots = {}
    for number, r in enumerate(keep, start=1):
        mine = labels == r
        numbered[mine] = number
        inside = cv2.distanceTransform(mine.astype(np.uint8), cv2.DIST_L2, 3)
        y, x = np.unravel_index(np.argmax(inside), inside.shape)
        spots[number] = (int(x), int(y))
    return line, body, numbered, spots

def muscle_mask(assets, slug, i, marks):
    line, body, numbered, _ = areas(assets, slug, i)
    red = np.zeros((SIZE, SIZE), np.uint8)
    grow = cv2.getStructuringElement(cv2.MORPH_ELLIPSE, (7, 7))
    for picked, x1, y1, x2, y2, width in marks:
        band = np.zeros((SIZE, SIZE), np.uint8)
        cv2.line(band, (int(x1), int(y1)), (int(x2), int(y2)), 1, int(width))
        cv2.circle(band, (int(x1), int(y1)), int(width) // 2, 1, -1)
        cv2.circle(band, (int(x2), int(y2)), int(width) // 2, 1, -1)
        if picked:
            # The areas, grown back under the lines around them.
            chosen = cv2.dilate(np.isin(numbered, picked).astype(np.uint8), grow)
        else:
            chosen = body.astype(np.uint8)
        red |= band & chosen
    red &= body.astype(np.uint8)
    # Smooth the edge a little so the outline is a clean curve.
    red = (cv2.GaussianBlur(red.astype(np.float32), (5, 5), 0) > 0.5).astype(np.uint8)
    return red, line

def polygons(mask):
    contours, hierarchy = cv2.findContours(mask, cv2.RETR_CCOMP, cv2.CHAIN_APPROX_NONE)
    out = []
    for c in contours:
        if cv2.contourArea(c) < 12: continue
        c = cv2.approxPolyDP(c, 0.8, True)
        out.append([round(float(v), 1) for p in c[:, 0, :] for v in p])
    return out

# ---------- Outlines ----------

def outline(svg_file):
    """The drawing's path as compact relative commands: m dx dy, l dx dy, c (three relative points), z.
    Numbers are rounded to tenths of a pixel; a minus sign also separates numbers."""
    d = re.search(r' d="([^"]+)"', svg_file.read_text()).group(1)
    out = []
    pen = [0.0, 0.0]          # where the rounded output has got to, so rounding never drifts
    start = [0.0, 0.0]        # where the current subpath began, in the same terms
    def num(v):
        t = f"{v:.1f}".rstrip("0").rstrip(".")
        return "0" if t in ("-0", "") else t
    def nums(values):
        text = ""
        for v in values:
            t = num(v)
            text += t if (not text or t.startswith("-")) else " " + t
        return text
    def rel(x, y):
        dx, dy = round(x - pen[0], 1), round(y - pen[1], 1)
        return dx, dy
    def cubic(c1, c2, e):
        a1 = rel(c1[0], c1[1]); a2 = rel(c2[0], c2[1]); a3 = rel(e[0], e[1])
        out.append("c" + nums([*a1, *a2, *a3]))
        pen[0] += a3[0]; pen[1] += a3[1]
    for seg in SVGPath(d):
        if isinstance(seg, Move):
            dx, dy = rel(seg.end.x, seg.end.y)
            out.append("m" + nums([dx, dy])); pen[0] += dx; pen[1] += dy
            start[0], start[1] = pen[0], pen[1]
        elif isinstance(seg, Close):
            out.append("z")
            # After z the pen is back at the start of the subpath, which the next m is relative to.
            pen[0], pen[1] = start[0], start[1]
        elif isinstance(seg, Line):
            dx, dy = rel(seg.end.x, seg.end.y)
            out.append("l" + nums([dx, dy])); pen[0] += dx; pen[1] += dy
        elif isinstance(seg, CubicBezier):
            cubic((seg.control1.x, seg.control1.y), (seg.control2.x, seg.control2.y), (seg.end.x, seg.end.y))
        elif isinstance(seg, QuadraticBezier):
            st, c, e = seg.start, seg.control, seg.end
            cubic((st.x + 2 / 3 * (c.x - st.x), st.y + 2 / 3 * (c.y - st.y)), (e.x + 2 / 3 * (c.x - e.x), e.y + 2 / 3 * (c.y - e.y)), (e.x, e.y))
        elif isinstance(seg, Arc):
            for cub in seg.as_cubic_curves():
                cubic((cub.control1.x, cub.control1.y), (cub.control2.x, cub.control2.y), (cub.end.x, cub.end.y))
    return "".join(out)

# ---------- Even line weight ----------

TARGET_WIDTH = 4.4        # px at 512: the usual stroke in these drawings
HEAVY = 5.2               # frames drawn heavier than this are re-inked at TARGET_WIDTH
SCALE = 4                 # work at 2048 px so the traced outline stays smooth

def stroke_width(assets, slug, i):
    """Typical stroke width of a frame: twice the distance from a stroke's middle to its edge."""
    a = np.asarray(Image.open(assets / slug / f"frame-{i}.png").convert("RGBA"))[:, :, 3]
    line = (a > 90).astype(np.uint8)
    d = cv2.distanceTransform(line, cv2.DIST_L2, 5)
    ridge = (d >= cv2.dilate(d, np.ones((3, 3), np.uint8))) & (d > 0.5)
    return float(2 * np.median(d[ridge])) if ridge.any() else TARGET_WIDTH

def thinned(svg_file, width):
    """The frame re-inked at the usual weight, as relative polygon commands: the
    drawn strokes are smoothed, reduced to their centre lines, and those lines
    redrawn TARGET_WIDTH wide. (Shaving the strokes instead breaks the uneven
    brush lines of the heavy frames into dashes.)"""
    from skimage.morphology import skeletonize
    d = re.search(r' d="([^"]+)"', svg_file.read_text()).group(1)
    big = SIZE * SCALE
    mask = np.zeros((big, big), np.uint8)
    # Fill even-odd: each closed piece flips the pixels it covers.
    for sub in SVGPath(d).as_subpaths():
        sub = SVGPath(sub)
        points = []
        for seg in sub:
            if isinstance(seg, Move):
                continue
            n = 2 if isinstance(seg, (Line, Close)) else 12
            points += [(p.x * SCALE, p.y * SCALE) for p in (seg.point(t / n) for t in range(n + 1)) if p is not None]
        if len(points) >= 3:
            piece = np.zeros_like(mask)
            cv2.fillPoly(piece, [np.round(np.array(points)).astype(np.int32)], 1)
            mask ^= piece
    def smooth(m, sigma):
        return (cv2.GaussianBlur(m.astype(np.float32), (0, 0), sigma) > 0.5).astype(np.uint8)
    # Smooth the rough brush edges so the centre lines have few side spurs.
    mask = smooth(mask, 0.9 * SCALE)
    centre = skeletonize(mask.astype(bool)).astype(np.uint8)
    # Drop specks: centre-line pieces shorter than a few pixels.
    n, pieces, stats, _ = cv2.connectedComponentsWithStats(centre, connectivity=8)
    for k in range(1, n):
        if stats[k, cv2.CC_STAT_AREA] < 3 * SCALE: centre[pieces == k] = 0
    r = int(round(TARGET_WIDTH / 2 * SCALE))
    mask = cv2.dilate(centre, cv2.getStructuringElement(cv2.MORPH_ELLIPSE, (2 * r + 1, 2 * r + 1)))
    mask = smooth(mask, 0.5 * SCALE)
    contours, _ = cv2.findContours(mask, cv2.RETR_CCOMP, cv2.CHAIN_APPROX_NONE)
    out, pen = [], [0.0, 0.0]
    def num(v):
        t = f"{v:.1f}".rstrip("0").rstrip(".")
        return "0" if t in ("-0", "") else t
    def nums(values):
        text = ""
        for v in values:
            t = num(v)
            text += t if (not text or t.startswith("-")) else " " + t
        return text
    for c in contours:
        if cv2.contourArea(c) < 4 * SCALE * SCALE: continue
        c = cv2.approxPolyDP(c, 0.7, True)[:, 0, :] / SCALE
        first = True
        for x, y in c:
            dx, dy = round(x - pen[0], 1), round(y - pen[1], 1)
            out.append(("m" if first else "l") + nums([dx, dy]))
            pen[0] += dx; pen[1] += dy
            if first: start = (pen[0], pen[1]); first = False
        out.append("z"); pen[0], pen[1] = start
    return "".join(out)

# ---------- Build ----------

def build(repo):
    assets = Path(repo) / "packages" / "workout-guide" / "assets"
    manifest = {e["slug"]: e for e in json.load(open(Path(repo) / "packages" / "workout-guide" / "manifest.json"))}
    marks = json.load(open(MARKS))
    drawings, evened = {}, []
    for slug in sorted(set(DRAWING.values())):
        frames = []
        for i in (1, 2, 3):
            red, _ = muscle_mask(assets, slug, i, marks.get(slug, {}).get(str(i), []))
            width = stroke_width(assets, slug, i)
            svg = assets / slug / f"frame-{i}.svg"
            if width > HEAVY:
                path = thinned(svg, width); evened.append(f"{slug} {i} ({width:.1f}px)")
            else:
                path = outline(svg)
            frames.append({"path": path, "muscles": polygons(red)})
        drawings[slug] = {"name": manifest[slug]["name"], "frames": frames}
    data = {
        "credit": "Drawings: Workout Guide by Bryl Lim, based on Everkinetic · CC BY-SA 4.0",
        "link": "https://github.com/bryllim/workout-guide",
        "size": SIZE,
        "byExercise": DRAWING,
        "drawings": drawings,
    }
    packer = zlib.compressobj(9, zlib.DEFLATED, -15)
    OUT.write_bytes(packer.compress(json.dumps(data, separators=(",", ":")).encode()) + packer.flush())
    old_json = OUT.with_suffix("")
    if old_json.exists(): old_json.unlink()
    unmarked = [s for s in drawings if s not in marks]
    print(f"{OUT.relative_to(ROOT)}: {len(drawings)} drawings, {OUT.stat().st_size // 1024} KB; not marked yet: {len(unmarked)}")
    print(f"thinned {len(evened)} heavy frames: " + ", ".join(evened))

def sheets(repo, folder, only=None):
    """Numbered areas on a grid, two drawings (three frames each) per sheet, for marking."""
    assets = Path(repo) / "packages" / "workout-guide" / "assets"
    folder = Path(folder); folder.mkdir(parents=True, exist_ok=True)
    slugs = [s for s in dict.fromkeys(DRAWING.values()) if not only or s in only]
    bold = ImageFont.truetype("/System/Library/Fonts/Supplemental/Arial Bold.ttf", 15)
    small = ImageFont.truetype("/System/Library/Fonts/Supplemental/Arial.ttf", 12)
    title = ImageFont.truetype("/System/Library/Fonts/Supplemental/Arial Bold.ttf", 22)
    def tile(slug, i):
        line, body, numbered, spots = areas(assets, slug, i)
        rgb = np.full((SIZE, SIZE, 3), 255, np.uint8)
        rgb[body] = (235, 235, 235)
        for r in spots:
            rgb[numbered == r] = [int(c * 255) for c in colorsys.hsv_to_rgb((r * 0.61803) % 1, 0.35, 1.0)]
        rgb[line] = (40, 40, 40)
        im = Image.fromarray(rgb); d = ImageDraw.Draw(im)
        for v in range(0, SIZE + 1, 32):
            c = (150, 180, 255) if v % 64 == 0 else (215, 225, 255)
            d.line([(v, 0), (v, SIZE - 1)], fill=c); d.line([(0, v), (SIZE - 1, v)], fill=c)
        for v in range(64, SIZE, 64):
            d.text((v + 2, 1), str(v), fill=(0, 80, 220), font=small); d.text((1, v + 1), str(v), fill=(0, 80, 220), font=small)
        for r, (x, y) in spots.items():
            t = str(r); w = d.textlength(t, font=bold)
            d.rectangle([x - w / 2 - 2, y - 9, x + w / 2 + 2, y + 9], fill=(255, 255, 255))
            d.text((x - w / 2, y - 9), t, fill=(0, 0, 160), font=bold)
        d.text((440, 492), f"frame {i}", fill=(0, 0, 0), font=bold)
        return im
    for n in range(0, len(slugs), 2):
        sheet = Image.new("RGB", (SIZE * 3, 1100), "white"); d = ImageDraw.Draw(sheet)
        for r, slug in enumerate(slugs[n:n + 2]):
            d.text((6, r * 550 + 4), slug, fill=(200, 0, 0), font=title)
            for i in (1, 2, 3): sheet.paste(tile(slug, i), ((i - 1) * SIZE, r * 550 + 36))
        sheet.save(folder / f"areas-{n // 2:02d}.png")

def check(repo, folder, only=None):
    """The finished frames: red under dark lines, three frames per row."""
    assets = Path(repo) / "packages" / "workout-guide" / "assets"
    folder = Path(folder); folder.mkdir(parents=True, exist_ok=True)
    marks = json.load(open(MARKS))
    slugs = [s for s in dict.fromkeys(DRAWING.values()) if s in marks and (not only or s in only)]
    font = ImageFont.truetype("/System/Library/Fonts/Supplemental/Arial Bold.ttf", 18)
    for n in range(0, len(slugs), 4):
        group = slugs[n:n + 4]
        T = 340
        sheet = Image.new("RGB", (3 * T, len(group) * T), "white"); d = ImageDraw.Draw(sheet)
        for r, slug in enumerate(group):
            for i in (1, 2, 3):
                red, line = muscle_mask(assets, slug, i, marks[slug].get(str(i), []))
                rgb = np.full((SIZE, SIZE, 3), 255, np.uint8)
                rgb[red.astype(bool)] = (226, 75, 74)
                rgb[line] = (30, 42, 64)
                sheet.paste(Image.fromarray(rgb).resize((T, T), Image.LANCZOS), ((i - 1) * T, r * T))
            d.text((4, r * T + 2), slug, fill=(0, 0, 0), font=font)
        sheet.save(folder / f"check-{n // 4:02d}.png")

if __name__ == "__main__":
    if len(sys.argv) < 2: sys.exit(__doc__)
    repo = sys.argv[1]
    if len(sys.argv) > 3 and sys.argv[2] == "--sheets": sheets(repo, sys.argv[3], sys.argv[4:] or None)
    elif len(sys.argv) > 3 and sys.argv[2] == "--check": check(repo, sys.argv[3], sys.argv[4:] or None)
    else: build(repo)
