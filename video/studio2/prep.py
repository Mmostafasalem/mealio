# Splits the real mascot render into layers the animation can move:
# the bowl without eyes or hands, and each hand on its own. Run: python3 -I prep.py
import base64, json
import cv2
import numpy as np

SRC = "../../smartmarket/Assets.xcassets/BowlMascot.imageset/mascot.png"
im = cv2.imread(SRC, cv2.IMREAD_UNCHANGED).astype(np.float32)  # BGRA
H, W = im.shape[:2]
bgr, alpha = im[..., :3], im[..., 3]

HANDS = [((81.5, 329.5), (41.5, 29.5)), ((428.5, 329.5), (41.5, 29.5))]
EYES = [(200, 278), (317, 278)]

def ellipse_mask(center, axes, grow=0.0):
    m = np.zeros((H, W), np.uint8)
    cv2.ellipse(m, (int(round(center[0] * 4)), int(round(center[1] * 4))), (int((axes[0] + grow) * 4), int((axes[1] + grow) * 4)), 0, 0, 360, 255, -1, cv2.LINE_AA, 2)
    return m

# 1. The hands, each cut out on its own with a soft edge.
hands = []
for center, axes in HANDS:
    m = cv2.GaussianBlur(ellipse_mask(center, axes, 0.5).astype(np.float32), (0, 0), 1.0) / 255.0
    x0, y0 = int(center[0] - axes[0] - 6), int(center[1] - axes[1] - 6)
    x1, y1 = int(center[0] + axes[0] + 6), int(center[1] + axes[1] + 6)
    sprite = im[y0:y1, x0:x1].copy()
    sprite[..., 3] = sprite[..., 3] * m[y0:y1, x0:x1]
    hands.append({"sprite": sprite, "cx": center[0] - x0, "cy": center[1] - y0, "x": center[0], "y": center[1]})

# 2. The bowl's own edge where the hands were, from the rows above and below them.
rows_left, rows_right = [], []
for y in list(range(250, 296)) + list(range(366, 392)):
    xs = np.where(alpha[y] > 128)[0]
    if len(xs):
        rows_left.append((y, xs[0])); rows_right.append((y, xs[-1]))
fit_l = np.polyfit([r[0] for r in rows_left], [r[1] for r in rows_left], 2)
fit_r = np.polyfit([r[0] for r in rows_right], [r[1] for r in rows_right], 2)

# 3. Paint out the eyes and the hands with the bowl's own surface.
hole = np.zeros((H, W), np.uint8)
for e in EYES:
    cv2.circle(hole, e, 22, 255, -1)
for center, axes in HANDS:
    hole |= ellipse_mask(center, axes, 10)
    # Clear pixels near a hand carry black from the background: fill those from the bowl too.
    x0, y0 = int(center[0] - axes[0] - 14), int(center[1] - axes[1] - 14)
    x1, y1 = int(center[0] + axes[0] + 14), int(center[1] + axes[1] + 14)
    box = np.zeros((H, W), bool); box[y0:y1, x0:x1] = True
    hole[box & (alpha < 250)] = 255
# First carry the bowl's colours out over the clear background, so nothing black can bleed in.
clear = (alpha < 250).astype(np.uint8) * 255
solid = cv2.inpaint(np.clip(bgr, 0, 255).astype(np.uint8), clear, 3, cv2.INPAINT_TELEA)
filled = cv2.inpaint(solid, hole, 9, cv2.INPAINT_TELEA).astype(np.float32)
# The clay has a fine grain: borrow it from a clean patch so the filled parts don't look smooth.
patch = bgr[330:390, 200:320]
grain = patch - cv2.GaussianBlur(patch, (0, 0), 3)
tile = np.tile(grain, (H // grain.shape[0] + 1, W // grain.shape[1] + 1, 1))[:H, :W]
soft = cv2.GaussianBlur(hole.astype(np.float32), (0, 0), 2) / 255.0
out_bgr = bgr * (1 - soft[..., None]) + (filled + tile * 0.9) * soft[..., None]

# Where a hand stuck out past the bowl, the bowl's edge now decides what is solid.
new_alpha = alpha.copy()
for (center, axes), fit in zip(HANDS, (fit_l, fit_r)):
    left = fit is fit_l
    y0, y1 = int(center[1] - axes[1] - 6), int(center[1] + axes[1] + 6)
    for y in range(y0, y1):
        edge = np.polyval(fit, y)
        xs = np.arange(W, dtype=np.float32)
        inside = np.clip((xs - edge + 0.5) if left else (edge - xs + 0.5), 0, 1) * 255
        region = ellipse_mask(center, axes, 4)[y] > 0
        new_alpha[y, region] = inside[region]

base = np.dstack([np.clip(out_bgr, 0, 255), new_alpha]).astype(np.uint8)
cv2.imwrite("bowl-base.png", base)
for i, h in enumerate(hands):
    cv2.imwrite(f"hand-{i}.png", np.clip(h["sprite"], 0, 255).astype(np.uint8))

# A check image: base, then base with hands put back where they were.
check = np.full((H, W * 2, 3), 236, np.float32)
def over(dst, src, x, y):
    h_, w_ = src.shape[:2]; a = src[..., 3:4] / 255.0
    dst[y:y + h_, x:x + w_] = dst[y:y + h_, x:x + w_] * (1 - a) + src[..., :3] * a
over(check, base.astype(np.float32), 0, 0)
over(check, base.astype(np.float32), W, 0)
for h in hands:
    over(check, h["sprite"], W + int(h["x"] - h["cx"]), int(h["y"] - h["cy"]))
cv2.imwrite("check.png", check.astype(np.uint8))

# Layers as data URLs, so the page can read them without file access rules.
def data(path):
    return "data:image/png;base64," + base64.b64encode(open(path, "rb").read()).decode()
meta = {"base": data("bowl-base.png"), "hands": [{"src": data(f"hand-{i}.png"), "cx": h["cx"], "cy": h["cy"], "x": h["x"], "y": h["y"]} for i, h in enumerate(hands)],
        "icon": data("../../smartmarket/Assets.xcassets/AppIcon.appiconset/icon_1024.png")}
open("layers.js", "w").write("const LAYERS = " + json.dumps(meta) + ";\n")
print("ok", base.shape, [h["sprite"].shape for h in hands])
