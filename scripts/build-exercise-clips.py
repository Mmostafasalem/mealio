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

# name: the ExerciseMotion raw value the clip drives.
# take, first and last source frame (at the take's own rate), how it repeats:
#   'cycle'  - a stride: the best loop near `period` seconds is found inside the range
#   'rep'    - one repetition from rest back to rest
# key: where the "finish" still is taken, as a fraction of the clip.
#   climb  - the take climbs stairs: the rise is taken out too, and the step size is kept
#   rest   - 'high' starts the loop where the hips are highest (standing)
CLIPS = [
    dict(name='walk', take='35_01', rate=120, start=40, end=340, period=1.1),
    dict(name='run', take='35_17', rate=120, start=0, end=167, period=0.77),
    dict(name='stairs', take='13_35', rate=120, start=236, end=520, period=1.4, climb=True),
    dict(name='squat', take='22_14', rate=120, start=60, end=660, period=2.3, rest='high'),
    dict(name='twist', take='13_29', rate=120, start=600, end=1200, period=3.47),
    dict(name='fold', take='14_20', rate=120, start=3000, end=3560, period=2.9, rest='high'),
    dict(name='armCircle', take='42_01', rate=60, start=200, end=560, period=1.03),
    dict(name='armRaise', take='13_29', rate=120, start=1470, end=1950, period=1.23),
]


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


def features(j):
    rel = j - j[:, :1]
    return np.concatenate([rel.reshape(len(j), -1), j[:, 0, 1:2] * 3], axis=1)


def find_cycle(j, rate, period):
    """Start and length (source frames) of the most seamless loop about `period` seconds long."""
    feat = features(j)
    vel = np.gradient(feat, axis=0) * rate * 0.08
    target = period * rate
    best = None
    for length in range(int(target * 0.8), int(target * 1.25) + 1):
        for start in range(0, len(j) - length - 1):
            cost = np.linalg.norm(feat[start] - feat[start + length]) + np.linalg.norm(vel[start] - vel[start + length])
            if best is None or cost < best[0]:
                best = (cost, start, length)
    return best[1], best[2]


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
    asf, amc = fetch(spec['take'])
    p = asfamc.positions(asf, amc)
    j = asfamc.figure_joints(p)[spec['start']:spec['end'] + 1]
    j = sole_points(j)
    climb = spec.get('climb', False)
    source = j
    j, _ = canonical(source, climb)
    start, length = find_cycle(j, spec['rate'], spec['period'])
    # Cut the loop from the untouched take, so the travel measured is the real one.
    j, travel = canonical(source[start:start + length + 1], climb)
    print(f"  {spec['name']}: loop at source frame {spec['start'] + start}, {length / spec['rate']:.2f} s")
    j = close_loop(j)
    j = resample(j, spec['rate'])
    if climb:
        # Stand the lowest moment of the lower foot on the floor.
        j[..., 1] -= np.percentile(np.minimum(j[:, 9, 1], j[:, 16, 1]), 2) - 0.07
    if spec.get('rest') == 'high':
        j = np.roll(j, -int(np.argmax(j[:, 0, 1])), axis=0)
    leg = float(np.median(np.linalg.norm(j[:, 8] - j[:, 7], axis=1) + np.linalg.norm(j[:, 9] - j[:, 8], axis=1)))
    ankle_rest = float(np.percentile(np.minimum(j[:, 9, 1], j[:, 16, 1]), 5))
    # The "finish" still: the moment furthest from the first frame.
    key = float(np.argmax(np.linalg.norm((j - j[:1]).reshape(len(j), -1), axis=1)) / len(j))
    aux = [0.0, 0.0, 0.0, 0.0]
    if climb:
        # One step of the staircase (run, rise) and where a step's top sat under a planted foot at frame 0.
        step_time = len(j) / FPS / 2
        run, rise = travel[0] * spec['rate'] * step_time, travel[1] * spec['rate'] * step_time
        foot = 9 if j[0, 9, 1] < j[0, 16, 1] else 16
        aux = [float(run), float(rise), float(j[0, foot, 0] + 0.05), float(j[0, foot, 1] - ankle_rest)]
        print(f"    stairs: step run {run:.3f} m, rise {rise:.3f} m")
    return dict(name=spec['name'], frames=j, leg=leg, ankle_rest=ankle_rest, key=key, aux=aux)


def write(clips, path):
    with open(path, 'wb') as f:
        f.write(b'NCP2')
        f.write(struct.pack('<I', len(clips)))
        for c in clips:
            name = c['name'].encode()
            frames = c['frames']
            f.write(struct.pack('<B', len(name)) + name)
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
    built = [build(spec) for spec in CLIPS]
    write(built, OUT)
    if '--preview' in sys.argv:
        preview(built, sys.argv[sys.argv.index('--preview') + 1])
