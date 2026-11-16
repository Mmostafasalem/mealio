#!/usr/bin/env python3
"""Build the exercise figure's 3D body (smartmarket/Resources/ExerciseBody.bin
and ExerciseBodyNormal.jpg).

The body is "Male base muscular anatomy" by Harshit Prajapati
(https://sketchfab.com/3d-models/male-base-muscular-anatomy-0954aa04666d45aab9633009318f7b66),
licensed CC BY 4.0: the app must credit the author. The download is a T-pose
mesh with no skeleton, so this script fits the app's 16-bone rig to it, works
out which bone each bit of skin follows, paints one mask per muscle group (so
the app can show the working muscles in red) and the shorts, and shapes the
hands.

Download the glTF from the page above (needs a Sketchfab login), unzip it, and run:
  scripts/build-exercise-figure.py <unzipped-folder> [preview-folder]
The preview PNGs need matplotlib; the normal map is resized with macOS `sips`.
"""
import json, struct, subprocess, sys
from pathlib import Path
import numpy as np

ROOT = Path(__file__).resolve().parent.parent
OUT = ROOT / "smartmarket" / "Resources" / "ExerciseBody.bin"
NORMAL_MAP = ROOT / "smartmarket" / "Resources" / "ExerciseBodyNormal.jpg"

# ---------- Load the model ----------

def load(folder):
    folder = Path(folder)
    doc = json.load(open(folder / "scene.gltf"))
    blob = open(folder / "scene.bin", "rb").read()
    kinds = {5126: ("<f4", 4), 5123: ("<u2", 2), 5125: ("<u4", 4), 5121: ("u1", 1)}
    widths = {"SCALAR": 1, "VEC2": 2, "VEC3": 3, "VEC4": 4}
    def accessor(i):
        a = doc["accessors"][i]; view = doc["bufferViews"][a["bufferView"]]
        dtype, size = kinds[a["componentType"]]; n = widths[a["type"]]
        start = view.get("byteOffset", 0) + a.get("byteOffset", 0)
        stride = view.get("byteStride", size * n)
        if stride == size * n:
            return np.frombuffer(blob, dtype, a["count"] * n, start).reshape(a["count"], n).astype(float)
        return np.stack([np.frombuffer(blob, dtype, n, start + i * stride) for i in range(a["count"])]).astype(float)
    def mesh(name):
        prim = next(m for m in doc["meshes"] if m["name"] == name)["primitives"][0]
        return {k: accessor(v) for k, v in prim["attributes"].items()}, accessor(prim["indices"]).astype(int).reshape(-1, 3)

    body, tris = mesh("body_low__Body_Low_SP_blinn1SG1_0")
    P, Nrm, UV, Tan = body["POSITION"], body["NORMAL"], body["TEXCOORD_0"], body["TANGENT"]
    is_eye = np.zeros(len(P), bool)
    # The eyeballs are separate meshes; add them so the sockets are not empty.
    for name in ("Eye2_Eye_0", "Eye3_Eye_0"):
        eye, eye_tris = mesh(name)
        n = len(eye["POSITION"])
        tris = np.concatenate([tris, eye_tris + len(P)])
        P = np.concatenate([P, eye["POSITION"]]); Nrm = np.concatenate([Nrm, eye["NORMAL"]])
        UV = np.concatenate([UV, np.zeros((n, 2))])
        Tan = np.concatenate([Tan, np.tile([1.0, 0, 0, 1], (n, 1))])
        is_eye = np.concatenate([is_eye, np.ones(n, bool)])
    return P, Nrm, UV, Tan, tris, is_eye, folder

# The model faces +z with y up and the figure's left at +x (about 10 cm per unit).
# The app's scene faces +x with y up, so the figure's right is at +z.
def to_scene(p):
    p = np.asarray(p)
    return np.stack([p[..., 2], p[..., 1], -p[..., 0]], axis=-1)

def smooth(x, lo, hi):
    t = np.clip((x - lo) / (hi - lo), 0, 1)
    return t * t * (3 - 2 * t)

def unit(v): return v / np.linalg.norm(v)

class Mesh:
    """Averages values over neighbouring vertices of the welded mesh."""
    def __init__(self, count, tris):
        pairs = np.concatenate([tris[:, [0, 1]], tris[:, [1, 2]], tris[:, [2, 0]]])
        pairs = np.unique(np.concatenate([pairs, pairs[:, ::-1]]), axis=0)
        pairs = pairs[pairs[:, 0] != pairs[:, 1]]
        self.a, self.b = pairs[:, 0], pairs[:, 1]
        self.degree = np.bincount(self.a, minlength=count).astype(float)
    def islands(self, keep):
        """Label the connected pieces of the mesh made of the vertices in `keep` (-1 elsewhere)."""
        label = np.where(keep, np.arange(len(keep)), -1)
        edges = keep[self.a] & keep[self.b]
        a, b = self.a[edges], self.b[edges]
        while True:
            lowest = label.copy()
            np.minimum.at(lowest, a, label[b])
            if (lowest == label).all(): return label
            label = lowest

    def blur(self, values, times=1):
        values = np.asarray(values, float)
        flat = values.ndim == 1
        if flat: values = values[:, None]
        for _ in range(times):
            total = 2 * values
            np.add.at(total, self.a, values[self.b])
            values = total / (2 + self.degree)[:, None]
        return values[:, 0] if flat else values

def vertex_normals(V, tris):
    N = np.zeros_like(V)
    fn = np.cross(V[tris[:, 1]] - V[tris[:, 0]], V[tris[:, 2]] - V[tris[:, 0]])
    for c in range(3): np.add.at(N, tris[:, c], fn)
    return N / np.maximum(np.linalg.norm(N, axis=1, keepdims=True), 1e-9)

# ---------- Rig ----------

BONES = ["pelvis", "waist", "chest", "head",
         "upperArm0", "forearm0", "thigh0", "shin0", "foot0",
         "upperArm1", "forearm1", "thigh1", "shin1", "foot1", "hand0", "hand1"]

def fit_rig(V):
    """Joint positions measured on the T-pose mesh, in scene axes (x forward, y up, z to the figure's right)."""
    x, y, z = V[:, 0], V[:, 1], V[:, 2]
    floor, crown = y.min(), y.max()
    height = crown - floor
    def centre(mask): return V[mask].mean(axis=0)

    rig = {}
    arm = centre((np.abs(z) > 0.25 * height) & (np.abs(z) < 0.35 * height))       # mid-arm: its height and depth
    crotch = y[(np.abs(z) < 0.006 * height) & (y < floor + 0.56 * height) & (y > floor + 0.4 * height)].min()
    hip_y = crotch + 0.04 * height
    ankle_y = floor + 0.043 * height
    knee_y = hip_y + 0.53 * (ankle_y - hip_y)
    reach = np.abs(z).max()                                                        # fingertip
    wrist = reach - 0.108 * height                                                 # a hand's length back from the fingertip
    knuckles = reach - 0.064 * height                                              # where the fingers leave the palm
    shoulder = 0.118 * height
    elbow = shoulder + 0.53 * (wrist - shoulder)
    for side, sign in ((0, 1), (1, -1)):
        def arm_at(r): return centre((sign * z > r - 0.01 * height) & (sign * z < r + 0.01 * height))
        def leg_at(h): return centre((sign * z > 0.005 * height) & (np.abs(y - h) < 0.012 * height) & (np.abs(z) < 0.2 * height))
        rig[f"shoulder{side}"] = np.array([arm[0] - 0.012 * height, arm[1], sign * shoulder])
        rig[f"elbow{side}"] = arm_at(elbow)
        rig[f"hand{side}"] = arm_at(wrist)
        rig[f"hip{side}"] = np.array([leg_at(hip_y - 0.03 * height)[0], hip_y, sign * 0.055 * height])
        rig[f"knee{side}"] = leg_at(knee_y)
        rig[f"foot{side}"] = leg_at(ankle_y) - np.array([0.012 * height, 0, 0])
        # Hand: the knuckle of the middle finger, and a point off the palm (palms face the floor in a T-pose).
        rig[f"middle{side}"] = arm_at(knuckles)
        rig[f"palm{side}"] = rig[f"hand{side}"] + np.array([0, -0.05 * height, 0])
    rig["top"] = (rig["shoulder0"] + rig["shoulder1"]) / 2
    rig["bottom"] = (rig["hip0"] + rig["hip1"]) / 2
    rig["mid"] = (rig["top"] + rig["bottom"]) / 2
    head = centre(y > crown - 0.11 * height)
    rig["head"] = np.array([head[0], crown - 0.07 * height, 0])
    measures = {"height": height, "crotch": crotch, "wrist": wrist, "elbow": elbow, "reach": reach, "knuckles": knuckles,
                "neck": crown - 0.155 * height}
    return rig, measures

def skin(V, rig, ms, mesh):
    """Which bone each vertex follows: a hard choice by region, then blurred across the joints."""
    x, y, z = V[:, 0], V[:, 1], V[:, 2]
    az = np.abs(z)
    label = np.full(len(V), BONES.index("chest"))
    hip_y, top_y = rig["bottom"][1], rig["top"][1]
    label[y < rig["mid"][1] + 0.1 * (top_y - hip_y)] = BONES.index("waist")
    label[y < hip_y + 0.2 * (top_y - hip_y)] = BONES.index("pelvis")
    label[(y > ms["neck"]) & (az < rig["shoulder0"][2] * 0.7)] = BONES.index("head")
    # Below the crotch each leg is its own piece of mesh. Tell them apart that
    # way, not by which side of the middle a vertex is on: the thighs touch,
    # and skin given to the wrong leg tears away when the legs part.
    pieces = mesh.islands(y < ms["crotch"] - 0.004 * ms["height"])
    leg_of = np.full(len(V), -1)
    for piece in np.unique(pieces[pieces >= 0]):
        members = pieces == piece
        if members.sum() > 200: leg_of[members] = 0 if z[members].mean() > 0 else 1
    for side, sign in ((0, 1), (1, -1)):
        mine = sign * z > 0
        leg = (leg_of == side) | (mine & (leg_of < 0) & (y < ms["crotch"] + 0.012 * ms["height"]))
        label[leg] = BONES.index(f"thigh{side}")
        label[leg & (y < rig[f"knee{side}"][1])] = BONES.index(f"shin{side}")
        label[leg & (y < rig[f"foot{side}"][1])] = BONES.index(f"foot{side}")
        arm = mine & (az > abs(rig[f"shoulder{side}"][2]) * 1.04) & (y > top_y - 0.09 * ms["height"])
        label[arm] = BONES.index(f"upperArm{side}")
        label[mine & (az > ms["elbow"])] = BONES.index(f"forearm{side}")
        label[mine & (az > ms["wrist"])] = BONES.index(f"hand{side}")
    W = np.zeros((len(V), len(BONES)))
    W[np.arange(len(V)), label] = 1
    W = mesh.blur(W, 7)
    # The blur must not join the two legs where the thighs touch: skin on one
    # leg never follows the other, or it stretches between them when they part.
    for side in (0, 1):
        for bone in ("thigh", "shin", "foot"):
            W[leg_of == side, BONES.index(f"{bone}{1 - side}")] = 0
    W[W.sum(axis=1) < 1e-6, BONES.index("pelvis")] = 1
    # Fingers and toes stay rigid with the hand and foot.
    for side in (0, 1):
        for bone, rigid in ((f"hand{side}", az > ms["wrist"] + 0.02 * ms["height"]),):
            pick = rigid & ((1 if side == 0 else -1) * z > 0)
            W[pick] = 0; W[pick, BONES.index(bone)] = 1
    return W / W.sum(axis=1, keepdims=True)

# ---------- Muscle masks ----------

# Order must match `Muscle` in ExerciseFigure3D.swift, followed by shorts and hair.
MASKS = ["chest", "shoulders", "traps", "lats", "lowerBack", "abs", "obliques",
         "biceps", "triceps", "forearms", "glutes", "quads", "hamstrings", "calves", "shorts", "hair"]

def paint(V, N, W, rig):
    """One 0…1 mask per muscle group, painted on the rest pose by position,
    surface direction and which bone the skin belongs to."""
    x, y, z = V[:, 0], V[:, 1], V[:, 2]
    az = np.abs(z)
    def w(*bones): return sum(W[:, BONES.index(b)] for b in bones)
    def band(v, lo, hi, soft=0.02): return smooth(v, lo - soft, lo + soft) * (1 - smooth(v, hi - soft, hi + soft))
    def along(a, b):
        """Fraction of the way from a to b, and distance from that line."""
        d = b - a; length = np.linalg.norm(d); d = d / length
        t = (V - a) @ d
        return t / length, np.linalg.norm(V - a - np.outer(t, d), axis=1)

    torso = smooth(w("pelvis", "waist", "chest", "head"), 0.45, 0.6)
    front, back = N[:, 0], -N[:, 0]
    sh, hip = rig["top"][1], rig["bottom"][1]          # shoulder line and hip line heights
    m = {name: np.zeros(len(V)) for name in MASKS}

    # Pecs: from the collarbone down to a lower edge that rises toward the armpit.
    m["chest"] = (torso * smooth(front, 0.05, 0.45) * band(y, sh - 0.2 + 0.35 * np.maximum(az - 0.1, 0), sh - 0.005)
                  * (1 - smooth(az, 0.188, 0.212)))
    m["abs"] = torso * smooth(front, 0.2, 0.6) * band(y, hip + 0.07, sh - 0.2) * (1 - smooth(az, 0.06, 0.085))
    m["obliques"] = torso * smooth(front, -0.5, -0.1) * smooth(az, 0.075, 0.1) * band(y, hip + 0.06, sh - 0.21)
    m["lowerBack"] = torso * smooth(back, 0.2, 0.6) * band(y, hip + 0.03, hip + 0.22) * (1 - smooth(az, 0.06, 0.09))
    m["lats"] = (torso * smooth(back, -0.15, 0.3) * band(y, hip + 0.13, sh - 0.07, 0.03)
                 * smooth(az, 0.02, 0.045) * (1 - m["lowerBack"]))
    # Trapezius: a diamond from the neck down the upper spine, out along the top of the shoulders.
    diamond = 1 - smooth(az, 0.03 + (y - (sh - 0.24)) * 0.55, 0.05 + (y - (sh - 0.24)) * 0.55)
    upper = smooth(np.maximum(back, N[:, 1] - 0.2), 0.0, 0.4) * band(y, sh - 0.24, sh + 0.14, 0.03) * (1 - smooth(az, 0.13, 0.17))
    m["traps"] = torso * upper * np.where(y < sh - 0.02, diamond, 1.0) * smooth(-x + rig["top"][0], -0.03, 0.02)
    m["lats"] *= 1 - m["traps"]
    m["glutes"] = (smooth(w("pelvis", "thigh0", "thigh1"), 0.3, 0.6) * smooth(back, 0.0, 0.4)
                   * band(y, hip - 0.13, hip + 0.06, 0.025))

    for side in (0, 1):
        sign = 1 if side == 0 else -1
        s, e, h = rig[f"shoulder{side}"], rig[f"elbow{side}"], rig[f"hand{side}"]
        t, dist = along(s, e)
        arm = smooth(w(f"upperArm{side}", f"forearm{side}"), 0.45, 0.7) * (dist < 0.11)
        m["biceps"] += arm * band(t, 0.3, 0.97, 0.06) * smooth(front, 0.0, 0.4)
        m["triceps"] += arm * band(t, 0.22, 0.97, 0.06) * smooth(back, 0.0, 0.4)
        # Deltoid: the cap over the shoulder joint, not the armpit below it.
        cap = np.linalg.norm(V - (s + (e - s) * 0.08), axis=1)
        outward = (V - s) @ np.array([0.0, 0.6, 0.8 * sign])
        m["shoulders"] += (1 - smooth(cap, 0.085, 0.125)) * smooth(outward, -0.03, 0.02) * (t < 0.5)
        ft, fdist = along(e, h)
        m["forearms"] += smooth(w(f"forearm{side}"), 0.5, 0.8) * band(ft, 0.02, 0.8, 0.05) * (fdist < 0.09)

        hp, kn, ft_ = rig[f"hip{side}"], rig[f"knee{side}"], rig[f"foot{side}"]
        t, dist = along(hp, kn)
        thigh = smooth(w(f"thigh{side}", f"shin{side}"), 0.5, 0.7) * (sign * z > 0)
        m["quads"] += thigh * band(t, 0.1, 0.98, 0.05) * smooth(front, -0.1, 0.3)
        m["hamstrings"] += thigh * band(t, 0.26, 0.98, 0.05) * smooth(back, 0.05, 0.4)
        t, dist = along(kn, ft_)
        m["calves"] += smooth(w(f"shin{side}"), 0.5, 0.7) * band(t, 0.04, 0.62, 0.05) * smooth(back, -0.1, 0.3)
    for name in ("chest", "traps", "lats"):
        m[name] *= 1 - np.clip(m["shoulders"], 0, 1)
    m["hamstrings"] *= 1 - m["glutes"]

    # Shorts from just under the navel to mid-thigh.
    legs = w("pelvis", "waist", "thigh0", "thigh1") > 0.5
    m["shorts"] = legs * band(y, hip - 0.19, hip + 0.085, 0.03)
    # No hair: the head stays bare, like an anatomy model. (The mask slot is kept so the file layout is stable.)
    return np.stack([np.clip(m[n], 0, 1) for n in MASKS], axis=1), MASKS

# ---------- Hands ----------

def turn(points, axis, degrees, pivot):
    """Rotate points about a line through `pivot`; `degrees` may differ per point."""
    a = unit(np.asarray(axis, float))
    t = np.radians(np.broadcast_to(degrees, len(points)))[:, None]
    v = points - pivot
    return pivot + v * np.cos(t) + np.cross(a, v) * np.sin(t) + a * (v @ a)[:, None] * (1 - np.cos(t))

# Degrees of bend at each finger joint, then the thumb: its swing under the palm (it lies
# alongside the fingers at rest, so it rolls about their line) and the bend of its tip.
GRIP = {"fingers": (68, 84, 46), "thumb": (118, 0)}
RELAXED = {"fingers": (14, 22, 12), "thumb": (28, 0)}

def curl_hands(V, rig, ms, shape):
    """Bend the fingers of both hands. In the T-pose they point straight out
    to the sides with the palms down and the thumbs forward, so each finger is
    a band of the hand and each joint a line across it."""
    out = V.copy()
    unit_len = ms["height"] / 1.74
    for sign in (1, -1):
        u = sign * V[:, 2]                                   # distance out along the arm
        hand = u > ms["wrist"]
        centre_x = rig["middle0" if sign == 1 else "middle1"][0]      # middle of the four fingers
        x = V[:, 0] - centre_x                               # forward of it (the thumb side)
        base = ms["knuckles"]
        thumb = hand & (x > 0.0565 * unit_len) & (u < base + 0.016 * unit_len)
        # Fingers, split at the gaps between them (index is the most forward).
        gaps = np.array([-0.2, -0.0375, -0.0015, 0.0345, 0.2]) * unit_len
        for f in range(4):
            mine = hand & ~thumb & (x > gaps[f]) & (x <= gaps[f + 1]) & (u > base - 0.02 * unit_len)
            if not mine.any(): continue
            points = out[mine]
            tip = u[mine].max()
            start = base - (0.006 if f == 0 else 0.0) * unit_len
            length = tip - start
            middle_y = V[mine & (u > start)][:, 1].mean()
            # Furthest joint first, so each bend carries everything beyond it.
            for at, degrees in zip((0.7, 0.42, 0.0), shape["fingers"][::-1]):
                joint = start + at * length
                amount = smooth(u[mine], joint - 0.006 * unit_len, joint + 0.006 * unit_len)
                pivot = np.array([0, middle_y - 0.004 * unit_len, sign * joint])
                points = turn(points, (1, 0, 0), sign * degrees * amount, pivot)
            out[mine] = points
        # Thumb: swing it down under the palm about the line of the fingers, then bend its tip.
        if thumb.any():
            points = out[thumb]
            tx = x[thumb]
            root = 0.0605 * unit_len
            tip = tx.max()
            pivot_y = V[thumb][:, 1].mean()
            wrist_x = centre_x
            amount = smooth(tx, root + 0.012 * unit_len + (tip - root) * 0.45, root + 0.024 * unit_len + (tip - root) * 0.45)
            points = turn(points, (0, 0, 1), -shape["thumb"][1] * amount,
                          np.array([wrist_x + root + (tip - root) * 0.55, pivot_y, 0]))
            amount = smooth(tx, root - 0.004 * unit_len, root + 0.012 * unit_len)
            points = turn(points, (0, 0, 1), -shape["thumb"][0] * amount, np.array([wrist_x + root, pivot_y, 0]))
            out[thumb] = points
    return out

def draw_hand(path, V, tris, N, ms):
    """The right hand from above, below and the front."""
    import matplotlib
    matplotlib.use("Agg")
    import matplotlib.pyplot as plt
    from matplotlib.collections import PolyCollection
    T = tris[V[tris].mean(axis=1)[:, 2] > ms["wrist"] - 0.03]
    fig, axes = plt.subplots(1, 3, figsize=(15, 5))
    for ax, (a, b, depth, sign) in zip(axes, ((2, 0, 1, 1), (2, 0, 1, -1), (2, 1, 0, 1))):
        mid = V[T].mean(axis=1); facing = sign * N[T].mean(axis=1)[:, depth]
        order = [i for i in np.argsort(sign * mid[:, depth]) if facing[i] > 0]
        tone = 0.3 + 0.65 * np.clip(facing, 0, 1)
        ax.add_collection(PolyCollection(V[T][:, :, [a, b]][order], facecolors=np.repeat(tone[order, None], 3, axis=1),
                                         edgecolors="none"))
        ax.set_aspect("equal"); ax.autoscale(); ax.axis("off")
    fig.tight_layout(); fig.savefig(path, dpi=60); plt.close(fig)

# ---------- Build ----------

def build(folder, preview=None):
    P, Nrm, UV, Tan, tris, is_eye, folder = load(folder)
    P, Nrm = to_scene(P), to_scene(Nrm)
    Tan = np.concatenate([to_scene(Tan[:, :3]), Tan[:, 3:]], axis=1)

    # Scale to the app's figure and stand it on the floor, centred.
    floor = P[:, 1].min()
    height = P[:, 1].max() - floor
    k = 1.74 / height
    P = (P - np.array([0, floor, 0])) * k

    # The mesh is split along texture seams; do the surface maths on a welded copy.
    _, first, weld = np.unique(np.round(P, 5), axis=0, return_index=True, return_inverse=True)
    weld = weld.reshape(-1)
    V = P[first]
    welded_tris = weld[tris]
    welded_tris = welded_tris[(welded_tris[:, 0] != welded_tris[:, 1]) & (welded_tris[:, 1] != welded_tris[:, 2])
                              & (welded_tris[:, 2] != welded_tris[:, 0])]
    mesh = Mesh(len(V), welded_tris)
    N = vertex_normals(V, welded_tris)
    eye = is_eye[first]

    rig, ms = fit_rig(V[~eye])
    V = V - np.array([rig["bottom"][0], 0, 0]); P = P - np.array([rig["bottom"][0], 0, 0])
    rig, ms = fit_rig(V[~eye])
    W = skin(V, rig, ms, mesh)
    W[eye] = 0; W[eye, BONES.index("head")] = 1
    order = np.argsort(-W, axis=1)[:, :4]
    top = np.take_along_axis(W, order, axis=1)
    top /= top.sum(axis=1, keepdims=True)

    # Paint with the broad lie of the surface, not every crease: a muscle is
    # one solid area, and the grooves between its bundles must not cut it up.
    broad = mesh.blur(N, 14)
    broad /= np.maximum(np.linalg.norm(broad, axis=1, keepdims=True), 1e-9)
    masks, names = paint(V, broad, W, rig)
    masks[eye] = 0
    # Soften every mask across neighbouring vertices, so the edge the app draws
    # (where a mask crosses one half) is a smooth curve and not a staircase of mesh edges.
    # (Not the shorts: their waist and hems are level lines already.)
    blurred = mesh.blur(masks, 6)
    blurred[:, MASKS.index("shorts")] = masks[:, MASKS.index("shorts")]
    masks = blurred
    # The shorts are a garment, not paint: smooth away the anatomy under them
    # and lift the cloth a little off the skin, so the waistband and hems stand proud.
    cloth = smooth(masks[:, MASKS.index("shorts")], 0.42, 0.58)[:, None]
    covered = mesh.blur(V, 10)
    covered_normals = vertex_normals(covered, welded_tris)
    V = V * (1 - cloth) + (covered + covered_normals * 0.016) * cloth
    N = vertex_normals(V, welded_tris)
    P = V[weld]
    in_cloth = cloth[weld][:, 0] > 0.05
    Nrm = np.where(in_cloth[:, None], N[weld], Nrm)

    # Shading that brings out the muscles: darken the skin where the surface dips between them.
    dip = np.einsum("ij,ij->i", V - mesh.blur(V, 4), N) * 30 + np.einsum("ij,ij->i", V - mesh.blur(V, 20), N) * 8
    shade = mesh.blur(np.clip(1 + dip, 0.6, 1.0), 2)
    shade[eye] = 1
    shade = shade * (1 - cloth[:, 0]) + cloth[:, 0]
    masks = np.concatenate([masks, shade[:, None]], axis=1)
    names = names + ["shade"]

    # Hand shapes: closed around a bar, and loosely relaxed. The mesh's own
    # hands (fingers straight) are the third, for a palm flat on the floor.
    variants = []
    for shape in (GRIP, RELAXED):
        curled = curl_hands(V, rig, ms, shape)
        curled_normals = vertex_normals(curled, welded_tris)
        moved = (np.abs(curled - V).max(axis=1) > 1e-6) | (np.abs(curled_normals - N).max(axis=1) > 1e-4)
        index = np.where(moved[weld])[0]
        # Keep each split vertex's own normal where the surface did not turn.
        turned = curled_normals[weld[index]] - N[weld[index]]
        norms = Nrm[index] + turned
        norms /= np.maximum(np.linalg.norm(norms, axis=1, keepdims=True), 1e-9)
        variants.append((index, curled[weld[index]], norms))
        if preview: draw_hand(Path(preview) / f"hand-{len(variants)}.png", curled, welded_tris, curled_normals, ms)

    if preview:
        draw_preview(Path(preview), V, welded_tris, N, masks, names, rig)

    # Back to the split vertices for the file.
    rig_names = ["top", "mid", "bottom", "head"] + [f"{j}{s}" for s in (0, 1)
                 for j in ("shoulder", "elbow", "hand", "hip", "knee", "foot")]
    rig_names += [f"{j}{s}" for s in (0, 1) for j in ("middle", "palm")]
    OUT.parent.mkdir(parents=True, exist_ok=True)
    with open(OUT, "wb") as f:
        f.write(struct.pack("<4sIIII", b"NFG2", len(P), len(tris), len(names), len(rig_names)))
        f.write(P.astype("<f4").tobytes())
        f.write(Nrm.astype("<f4").tobytes())
        f.write(UV.astype("<f4").tobytes())
        f.write(Tan.astype("<f4").tobytes())
        f.write(order[weld].astype("<u2").tobytes())
        f.write(top[weld].astype("<f4").tobytes())
        f.write(np.clip(masks[weld] * 255, 0, 255).astype("u1").tobytes())     # vertex-major
        f.write(tris.astype("<u2").tobytes())
        f.write(np.array([rig[n] for n in rig_names]).astype("<f4").tobytes())
        f.write(struct.pack("<I", len(variants)))
        for index, positions, norms in variants:
            f.write(struct.pack("<I", len(index)))
            f.write(index.astype("<u2").tobytes())
            f.write(positions.astype("<f4").tobytes())
            f.write(norms.astype("<f4").tobytes())
    # The normal map carries the fine muscle detail; 1024 px is plenty on a phone.
    source = next((folder / "textures").glob("*normal*"))
    subprocess.run(["sips", "-s", "format", "jpeg", "-s", "formatOptions", "82", "-Z", "1024", str(source),
                    "--out", str(NORMAL_MAP)], check=True, capture_output=True)
    print(f"{OUT.relative_to(ROOT)}: {len(P)} vertices, {len(tris)} triangles, {OUT.stat().st_size // 1024} KB; "
          f"normal map {NORMAL_MAP.stat().st_size // 1024} KB")
    for n in ("top", "bottom", "head", "shoulder0", "elbow0", "hand0", "middle0", "hip0", "knee0", "foot0"):
        print(f"  {n:10s}", np.round(rig[n], 3))

def draw_preview(folder, V, tris, N, masks, names, rig):
    """Front and back of the rest pose with every mask in its own colour, cut off at one half as the app does."""
    import matplotlib
    matplotlib.use("Agg")
    import matplotlib.pyplot as plt
    from matplotlib.collections import PolyCollection
    folder.mkdir(parents=True, exist_ok=True)
    palette = plt.cm.tab20(np.linspace(0, 1, 20))[:, :3]
    colour = np.full((len(V), 3), 0.82)
    for i, name in enumerate(names[:-1]):
        colour[masks[:, i] > 0.5] = palette[i]
    colour *= masks[:, -1:]
    fig, axes = plt.subplots(1, 2, figsize=(22, 20))
    for ax, sign in zip(axes, (1, -1)):
        centre = V[tris].mean(axis=1)
        facing = sign * N[tris].mean(axis=1)[:, 0]
        order = [i for i in np.argsort(sign * centre[:, 0]) if facing[i] > 0]
        shade = 0.5 + 0.5 * np.clip(facing, 0, 1)
        fc = colour[tris].mean(axis=1) * shade[:, None]
        pts = V[tris][:, :, [2, 1]].copy()
        pts[:, :, 0] *= -sign
        ax.add_collection(PolyCollection(pts[order], facecolors=fc[order], edgecolors="none"))
        for p in rig.values(): ax.plot(-sign * p[2], p[1], "k+", markersize=12)
        ax.set_aspect("equal"); ax.autoscale(); ax.axis("off")
    for i, name in enumerate(names[:-1]):
        fig.text(0.01 + 0.06 * i, 0.01, name, color=palette[i], fontsize=15, weight="bold")
    fig.tight_layout(); fig.savefig(folder / "body.png", dpi=50); plt.close(fig)

if __name__ == "__main__":
    if len(sys.argv) < 2: sys.exit(__doc__)
    build(sys.argv[1], sys.argv[2] if len(sys.argv) > 2 else None)
