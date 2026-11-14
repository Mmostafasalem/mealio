#!/usr/bin/env python3
"""Build smartmarket/Resources/ExerciseClips.bin: captured human motion for the
exercise demos, cut from the CMU Graphics Lab Motion Capture Database
(mocap.cs.cmu.edu). CMU's terms: "This data is free for use in research
projects. You may include this data in commercially-sold products, but you may
not resell this data directly, even in converted form." The app credits it
under the demo.

    python3 scripts/build-exercise-clips.py [--preview DIR]

Takes are downloaded once into ~/Library/Caches/nourlo-mocap. Each clip is cut
from a take, turned to face +x, kept in place, closed into a seamless loop and
resampled to 30 fps. Stored per frame: 20 joints (pelvis, mid-spine, neck base,
head; per side L then R: shoulder, elbow, wrist, hip, knee, ankle, sole-forward
point; then the two hands), x forward, y up, z to the figure's right, in
millimetres. The app fits them onto its own body by bone direction.
"""
import os, struct, sys, urllib.request
import numpy as np

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import mocap_asfamc as asfamc

CACHE = os.path.expanduser('~/Library/Caches/nourlo-mocap')
OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', 'smartmarket', 'Resources', 'ExerciseClips.bin')
FPS = 30

# One entry per clip. `name` is the ExerciseMotion raw value it drives.
#   src     - ('cmu', take) | ('bvh', folder, file) | ('vicon', file)
#   span    - first and last source frame to look in (None: the whole take)
#   period  - (shortest, longest) loop to look for, in seconds
#   climb   - the take climbs stairs: the rise is taken out too, and the step size is kept
#   rest    - 'high' starts the loop where the hips are highest (standing)
#   ground  - 'lowest': the body lies or crawls, so the lowest joint (not a foot) rests on the floor
#   lift    - metres the feet ride above the floor (pedals)
#   credit  - index into CREDITS (who to thank in the app)
CREDITS = ['CMU', 'ARKit-Vicon', '100STYLE', 'ACCAD', 'Cyclists']
CLIPS = [
    dict(name='walk', src=('cmu', '35_01'), span=(40, 340), period=(0.9, 1.4)),
    dict(name='run', src=('cmu', '35_17'), span=(0, 167), period=(0.6, 0.95)),
    dict(name='stairs', src=('cmu', '13_35'), span=(236, 520), period=(1.1, 1.75), climb=True),
    dict(name='squat', src=('cmu', '22_14'), span=(60, 660), period=(1.8, 2.9), rest='high'),
    dict(name='twist', src=('cmu', '13_29'), span=(600, 1200), period=(2.8, 4.2)),
    dict(name='fold', src=('cmu', '14_20'), span=(3000, 3560), period=(2.3, 3.5), rest='high'),
    dict(name='armCircle', src=('cmu', '42_01'), span=(200, 560), period=(0.8, 1.3)),
    # More from CMU.
    dict(name='windmill', src=('cmu', '13_29'), span=(1980, 2700), period=(2.0, 3.8), rest='high'),
    dict(name='kneeLift', src=('cmu', '13_29'), span=(2760, 3800), period=(1.0, 3.2)),
    dict(name='armRaise', src=('cmu', '13_29'), span=(1470, 1950), period=(0.9, 1.5), rest='hands_low'),
    dict(name='squatReach', src=('cmu', '14_20'), span=(1900, 2720), period=(2.0, 4.0), rest='high'),
    dict(name='hipCircle', src=('cmu', '42_01'), span=(600, 1040), period=(1.5, 4.5)),
    dict(name='boxing', src=('cmu', '14_01'), span=None, period=(1.2, 3.5)),
    dict(name='sideShuffle', src=('cmu', '141_33'), span=None, period=(0.7, 1.7)),
    dict(name='jumpSquat', src=('cmu', '13_39'), span=None, period=(1.0, 3.2), rest='high'),
    # Vicon exercise set (CC BY 4.0): repeated reps, the first and last seconds are setting up.
    dict(name='lateralRaise', src=('vicon', 'lateral arm raise.csv'), span=(2000, 10000), period=(2.0, 5.5), rest='hands_low', credit='ARKit-Vicon'),
    dict(name='reverseFly', src=('vicon', 'revesere fly.csv'), span=(2000, 10000), period=(2.0, 5.5), rest='hands_low', credit='ARKit-Vicon'),
    dict(name='lunge', src=('vicon', 'front lunge.csv'), span=(2000, 10500), period=(2.5, 7.5), rest='high', credit='ARKit-Vicon'),
    dict(name='singleLegDeadlift', src=('vicon', 'single leg deadlift.csv'), span=(2500, 13000), period=(2.5, 8.0), rest='high', credit='ARKit-Vicon'),
    dict(name='sideLunge', src=('vicon', 'side squat.csv'), span=(2000, 11000), period=(2.5, 8.0), rest='high', credit='ARKit-Vicon'),
    dict(name='jumpingJack', src=('vicon', 'jumping jacks.csv'), span=(1500, 6000), period=(0.6, 1.5), rest='hands_low', credit='ARKit-Vicon'),
    dict(name='crunch', src=('vicon', 'leg extension crunch.csv'), span=(2000, 8500), period=(1.5, 6.0), ground='lowest', credit='ARKit-Vicon'),
    # 100STYLE (CC BY 4.0): long walks with turns; the straightest stretch is found first.
    dict(name='highKnees', src=('bvh', '100style', 'HighKnees_FW.bvh'), straight=True, period=(0.4, 1.6), credit='100STYLE'),
    dict(name='march', src=('bvh', '100style', 'March_FW.bvh'), straight=True, period=(0.6, 1.8), credit='100STYLE'),
    dict(name='frontKick', src=('bvh', '100style', 'Kick_FW.bvh'), straight=True, period=(0.7, 2.6), credit='100STYLE'),
    dict(name='jumpRope', src=('bvh', '100style', 'TwoFootJump_FW.bvh'), straight=True, period=(0.3, 1.4), rest='high', credit='100STYLE'),
    dict(name='skip', src=('bvh', '100style', 'Skip_FW.bvh'), straight=True, period=(0.5, 1.8), credit='100STYLE'),
]


def rate_of(spec):
    if spec['src'][0] == 'cmu':
        import json
        return 60 if spec['src'][1].split('_')[0] in ('42', '79') else 120
    return None


def load(spec):
    """(frames, 20, 3) joints in metres, y up, and the capture rate."""
    kind = spec['src'][0]
    if kind == 'cmu':
        asf, amc = fetch(spec['src'][1])
        return asfamc.figure_joints(asfamc.positions(asf, amc)), rate_of(spec)
    if kind == 'vicon':
        return asfamc.figure_joints_vicon(os.path.join(CACHE, 'vicon', spec['src'][1]))
    if kind == 'bvh':
        span = spec.get('span')
        p, frame_time = asfamc.read_bvh(os.path.join(CACHE, spec['src'][1], spec['src'][2]),
                                        span[0] if span else 0, span[1] + 1 if span else None)
        j = asfamc.figure_joints_any_bvh(p)
        spec = dict(spec); spec['_cut'] = True
        return j, round(1 / frame_time)
    raise ValueError(kind)


def fetch(take):
    os.makedirs(CACHE, exist_ok=True)
    subject = take.split('_')[0]
    paths = []
    for name, url in [(f'{subject}.asf', f'http://mocap.cs.cmu.edu/subjects/{subject}/{subject}.asf'),
                      (f'{take}.amc', f'http://mocap.cs.cmu.edu/subjects/{subject}/{take}.amc')]:
        path = os.path.join(CACHE, name)
        if not os.path.exists(path):
            print('downloading', url)
            urllib.request.urlretrieve(url, path)
        paths.append(path)
    return paths


def canonical(j, climb=False):
    """Turn to face +x (one turn for the whole clip), y up, z to the right; pelvis kept over the origin.
    Returns the joints and the travel taken out per frame (x, y, z)."""
    f = asfamc.facing(j).mean(axis=0)
    f[1] = 0
    f /= np.linalg.norm(f)
    r = np.cross(f, np.array([0.0, 1.0, 0.0]))
    out = np.stack([j @ f, j[..., 1], j @ r], axis=-1)
    # In place: take out the straight-line travel of the pelvis, keep its sway.
    n = len(out)
    t = np.arange(n)
    travel = np.zeros(3)
    for axis in ((0, 1, 2) if climb else (0, 2)):
        root = out[:, 0, axis]
        slope, intercept = np.polyfit(t, root, 1) if n > 1 else (0.0, root[0])
        travel[axis] = slope
        # Going up stairs only the climb is taken out, not the height itself.
        out[..., axis] -= (slope * t + (0 if axis == 1 else intercept))[:, None]
    return out, travel


def sole_points(j):
    """Replace each toe joint with a point straight ahead of the ankle along the sole, so
    the app can lay the foot flat when the source foot was flat."""
    out = j.copy()
    for ankle, toe in ((9, 10), (16, 17)):
        v = j[:, toe] - j[:, ankle]
        length = np.linalg.norm(v, axis=1)
        horizontal = np.linalg.norm(v[:, [0, 2]], axis=1)
        slope = np.arctan2(-v[:, 1], horizontal)                 # how far the toe sits below the ankle
        planted = j[:, ankle, 1] < np.percentile(j[:, ankle, 1], 30) + 0.01
        rest = np.median(slope[planted]) if planted.any() else np.median(slope)
        # Tilt every frame up by the resting slope, about the foot's own sideways axis.
        side = np.cross(v, np.array([0.0, 1.0, 0.0]))
        side /= np.maximum(np.linalg.norm(side, axis=1, keepdims=True), 1e-6)
        c, s = np.cos(rest), np.sin(rest)
        rotated = v * c + np.cross(side, v) * s + side * (np.einsum('ij,ij->i', side, v) * (1 - c))[:, None]
        out[:, toe] = j[:, ankle] + rotated / np.maximum(length, 1e-6)[:, None] * 0.15
    return out


def straight_span(j, rate, seconds=5.0):
    """The stretch of at least `seconds` where the walker holds one heading best and keeps moving."""
    f = asfamc.facing(j)
    yaw = np.unwrap(np.arctan2(f[:, 2], f[:, 0]))
    n = int(seconds * rate)
    step = max(int(rate / 10), 1)
    best = None
    for a in range(int(4 * rate), len(j) - n - int(2 * rate), step):
        window = yaw[a:a + n]
        travel = np.linalg.norm(j[a + n, 0, [0, 2]] - j[a, 0, [0, 2]])
        score = np.std(window) - 0.05 * travel
        if best is None or score < best[0]:
            best = (score, a)
    return best[1], best[1] + n


def features(j):
    rel = j - j[:, :1]
    return np.concatenate([rel.reshape(len(j), -1), j[:, 0, 1:2] * 3], axis=1)


def find_cycle(j, rate, period):
    """Start and length (source frames) of the most seamless loop between `period[0]` and
    `period[1]` seconds. A loop has to contain real movement (standing still loops perfectly),
    so the seam is judged against how much the body moves inside it. Among loops nearly as
    good as the best, the shortest wins (one rep, not two)."""
    step = max(int(round(rate / 60)), 1)
    feat = features(j)[::step]
    vel = np.gradient(feat, axis=0) * (rate / step) * 0.08
    speed = np.concatenate([[0.0], np.cumsum(np.linalg.norm(np.diff(feat, axis=0), axis=1))])
    found = []
    for length in range(int(period[0] * rate / step), min(int(period[1] * rate / step), len(feat) - 2) + 1):
        seam = np.linalg.norm(feat[:-length] - feat[length:], axis=1) + np.linalg.norm(vel[:-length] - vel[length:], axis=1)
        moved = speed[length:] - speed[:-length]                     # path length of the pose inside the loop
        score = (seam + 0.05) / np.maximum(moved, 1e-6)
        score[moved < 1.5] = np.inf                                  # barely moving: not a rep
        start = int(np.argmin(score))
        if np.isfinite(score[start]):
            found.append((float(score[start]), start * step, length * step, float(seam[start])))
    if not found:
        raise ValueError('no moving loop in this span')
    best = min(found)[0]
    good = [f for i, f in enumerate(found) if f[0] <= best * 1.35
            and (i == 0 or f[0] <= found[i - 1][0]) and (i == len(found) - 1 or f[0] <= found[i + 1][0])]
    _, start, length, seam = min(good or [min(found)], key=lambda f: f[2])
    return start, length, seam


def close_loop(j):
    """Spread the gap between the last and first frames across the clip, so it repeats without a jump.
    The last frame is the same pose as the first and is dropped."""
    n = len(j) - 1
    gap = j[-1] - j[0]
    ramp = (np.arange(n + 1) / n)[:, None, None]
    return (j - gap[None] * ramp)[:-1]


def resample(j, rate, loop=True):
    n = len(j)
    count = max(int(round(n / rate * FPS)), 2)
    out = np.zeros((count,) + j.shape[1:])
    for i in range(count):
        x = i * n / count
        a = int(np.floor(x)) % n
        b = (a + 1) % n if loop else min(a + 1, n - 1)
        w = x - np.floor(x)
        out[i] = j[a] * (1 - w) + j[b] * w
    return out


def build(spec):
    j, rate = load(spec)
    if spec['src'][0] != 'bvh' and spec.get('span'):
        j = j[spec['span'][0]:spec['span'][1] + 1]
    if spec.get('straight'):
        a, b = straight_span(j, rate)
        j = j[a:b + 1]
    # Whatever the source's units, work in metres for a person with an 0.85 m leg.
    leg = float(np.median(np.linalg.norm(j[:, 8] - j[:, 7], axis=1) + np.linalg.norm(j[:, 9] - j[:, 8], axis=1)))
    j = j * (0.85 / leg)
    j = sole_points(j)
    climb = spec.get('climb', False)
    source = j
    j, _ = canonical(source, climb)
    start, length, cost = find_cycle(j, rate, spec['period'])
    # Cut the loop from the untouched take, so the travel measured is the real one.
    j, travel = canonical(source[start:start + length + 1], climb)
    j = close_loop(j)
    j = resample(j, rate)
    lying = spec.get('ground') == 'lowest'
    if climb:
        # Stand the lowest moment of the lower foot on the floor.
        j[..., 1] -= np.percentile(np.minimum(j[:, 9, 1], j[:, 16, 1]), 2) - 0.07
    if spec.get('rest') == 'high':
        j = np.roll(j, -int(np.argmax(j[:, 0, 1])), axis=0)
    elif spec.get('rest') == 'low':
        j = np.roll(j, -int(np.argmin(j[:, 0, 1])), axis=0)
    elif spec.get('rest') == 'hands_low':
        j = np.roll(j, -int(np.argmin(j[:, 6, 1] + j[:, 13, 1])), axis=0)
    leg = float(np.median(np.linalg.norm(j[:, 8] - j[:, 7], axis=1) + np.linalg.norm(j[:, 9] - j[:, 8], axis=1)))
    ankle_rest = float(np.percentile(np.minimum(j[:, 9, 1], j[:, 16, 1]), 5)) - spec.get('lift', 0.0)
    # The "finish" still: the moment furthest from the first frame.
    key = float(np.argmax(np.linalg.norm((j - j[:1]).reshape(len(j), -1), axis=1)) / len(j))
    aux = [0.0, 0.0, 0.0, 0.0]
    note = ''
    if climb:
        # One step of the staircase (run, rise) and where a step's top sat under a planted foot at frame 0.
        step_time = len(j) / FPS / 2
        run, rise = travel[0] * rate * step_time, travel[1] * rate * step_time
        foot = 9 if j[0, 9, 1] < j[0, 16, 1] else 16
        aux = [float(run), float(rise), float(j[0, foot, 0] + 0.05), float(j[0, foot, 1] - ankle_rest)]
        note = f', step {run:.2f} x {rise:.2f} m'
    if spec['name'] == 'jumpRope':
        # How many hops the loop holds, so the rope can go round once per hop.
        y = j[:, 0, 1]
        hops = sum(1 for i in range(len(y)) if y[i] > y[i - 1] and y[i] >= y[(i + 1) % len(y)] and y[i] > y.mean())
        aux = [float(max(hops, 1)), 0.0, 0.0, 0.0]
        note = f', {hops} hops'
    print(f"  {spec['name']:16s} {len(j) / FPS:.2f} s  seam {cost:.2f}  from frame {(spec.get('span') or (0,))[0] + start}{note}")
    return dict(name=spec['name'], frames=j, leg=leg, ankle_rest=ankle_rest, key=key, aux=aux,
                flags=1 if lying else 0, credit=CREDITS.index(spec.get('credit', 'CMU')))


def write(clips, path):
    with open(path, 'wb') as f:
        f.write(b'NCP3')
        f.write(struct.pack('<I', len(clips)))
        for c in clips:
            name = c['name'].encode()
            frames = c['frames']
            f.write(struct.pack('<B', len(name)) + name)
            f.write(struct.pack('<BB', c['flags'], c['credit']))
            f.write(struct.pack('<ffffffffII', FPS, c['leg'], c['ankle_rest'], c['key'], *c['aux'], frames.shape[0], frames.shape[1]))
            f.write(np.clip(np.round(frames * 1000), -32767, 32767).astype('<i2').tobytes())
    print('wrote', os.path.relpath(path), os.path.getsize(path), 'bytes,', len(clips), 'clips')


def preview(clips, folder):
    from PIL import Image, ImageDraw
    os.makedirs(folder, exist_ok=True)
    for c in clips:
        j = c['frames']
        cols = min(len(j), 24)
        idx = [int(i * len(j) / cols) for i in range(cols)]
        cell = 150
        img = Image.new('RGB', (cols * cell, cell * 2), 'white')
        d = ImageDraw.Draw(img)
        s = cell / 2.1
        for k, fi in enumerate(idx):
            for view, axis in enumerate((0, 2)):
                ox, oy = k * cell + cell / 2, view * cell + cell - 8
                pts = [(ox + q[axis] * s, oy - q[1] * s) for q in j[fi]]
                d.line([(k * cell + 4, oy), (k * cell + cell - 4, oy)], fill=(210, 210, 210))
                for a, b in asfamc.BONES:
                    left = 4 <= a <= 10 or 4 <= b <= 10 or b == 18
                    right = 11 <= a <= 17 or 11 <= b <= 17 or b == 19
                    d.line([pts[a], pts[b]], fill=(40, 90, 220) if left else (220, 60, 50) if right else (30, 30, 30), width=2)
            d.text((k * cell + 3, 2), str(fi), fill=(0, 0, 0))
        img.save(os.path.join(folder, c['name'] + '.png'))


if __name__ == '__main__':
    only = [a for a in sys.argv[1:] if not a.startswith('--') and not a.startswith('/')]
    built = []
    for spec in CLIPS:
        try:
            built.append(build(spec))
        except Exception as error:                      # one bad take must not stop the rest
            print(f"  {spec['name']:16s} FAILED: {error}")
    write(built, OUT)
    if '--preview' in sys.argv:
        preview(built, sys.argv[sys.argv.index('--preview') + 1])
