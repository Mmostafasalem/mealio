"""Read CMU motion capture (ASF skeleton + AMC motion) into joint positions.

Positions come out in metres, y up, as arrays of shape (frames, 3) per bone
name; a bone's position is the far end of that bone ("lfemur" is the knee).
"""
import numpy as np

SCALE = (1.0 / 0.45) * 2.54 / 100.0   # ASF length units -> metres


def _rot(rx, ry, rz):
    """Rz * Ry * Rx, angles in degrees."""
    x, y, z = np.radians([rx, ry, rz])
    cx, sx, cy, sy, cz, sz = np.cos(x), np.sin(x), np.cos(y), np.sin(y), np.cos(z), np.sin(z)
    Rx = np.array([[1, 0, 0], [0, cx, -sx], [0, sx, cx]])
    Ry = np.array([[cy, 0, sy], [0, 1, 0], [-sy, 0, cy]])
    Rz = np.array([[cz, -sz, 0], [sz, cz, 0], [0, 0, 1]])
    return Rz @ Ry @ Rx


def read_asf(path):
    lines = open(path).read().split('\n')
    i = 0
    bones = {'root': dict(name='root', direction=np.zeros(3), length=0.0, axis=np.zeros(3), dof=[], children=[])}
    while not lines[i].startswith(':bonedata'):
        i += 1
    i += 1
    while not lines[i].startswith(':hierarchy'):
        if lines[i].strip() == 'begin':
            b = dict(dof=[], children=[])
            i += 1
            while lines[i].strip() != 'end':
                t = lines[i].split()
                if t[0] == 'name': b['name'] = t[1]
                elif t[0] == 'direction': b['direction'] = np.array([float(v) for v in t[1:4]])
                elif t[0] == 'length': b['length'] = float(t[1])
                elif t[0] == 'axis': b['axis'] = np.array([float(v) for v in t[1:4]])
                elif t[0] == 'dof': b['dof'] = t[1:]
                i += 1
            bones[b['name']] = b
        i += 1
    i += 2  # ':hierarchy', 'begin'
    while lines[i].strip() != 'end':
        t = lines[i].split()
        bones[t[0]]['children'] = t[1:]
        for c in t[1:]:
            bones[c]['parent'] = t[0]
        i += 1
    for b in bones.values():
        b['C'] = _rot(*b['axis'])
        b['Cinv'] = np.linalg.inv(b['C'])
    return bones


def read_amc(path):
    frames = []
    cur = None
    for line in open(path):
        t = line.split()
        if not t or line[0] in '#:':
            continue
        if len(t) == 1 and t[0].isdigit():
            cur = {}
            frames.append(cur)
        elif cur is not None:
            cur[t[0]] = [float(v) for v in t[1:]]
    return frames


def positions(asf_path, amc_path, every=1):
    """dict bone -> (frames, 3) positions in metres; also 'R_<bone>' -> (frames, 3, 3) rotations for root."""
    bones = read_asf(asf_path)
    frames = read_amc(amc_path)[::every]
    order = []
    stack = ['root']
    while stack:
        n = stack.pop(0)
        order.append(n)
        stack = bones[n]['children'] + stack
    out = {n: np.zeros((len(frames), 3)) for n in order}
    for f, frame in enumerate(frames):
        mats = {}
        root = frame['root']
        out['root'][f] = np.array(root[:3]) * SCALE
        b = bones['root']
        mats['root'] = b['C'] @ _rot(*root[3:6]) @ b['Cinv']
        for n in order[1:]:
            b = bones[n]
            r = dict(rx=0.0, ry=0.0, rz=0.0)
            for k, v in zip(b['dof'], frame.get(n, [])):
                r[k] = v
            mats[n] = mats[b['parent']] @ b['C'] @ _rot(r['rx'], r['ry'], r['rz']) @ b['Cinv']
            out[n][f] = out[b['parent']][f] + (b['length'] * SCALE) * (mats[n] @ b['direction'])
    return out


# The joints the app's figure uses, from CMU bone ends.
def figure_joints(p):
    """(frames, 21, 3): pelvis, mid, top, head, then per side (L, R):
    shoulder, elbow, wrist, hip, knee, ankle, toe; then per side hand."""
    head = (p['upperneck'] + p['head']) / 2
    cols = [p['root'], p['upperback'], p['thorax'], head]
    for s in 'lr':
        cols += [p[s + 'clavicle'], p[s + 'humerus'], p[s + 'radius'], p[s + 'hipjoint'], p[s + 'femur'], p[s + 'tibia'], p[s + 'foot']]
    for s in 'lr':
        cols += [p[s + 'hand']]
    return np.stack(cols, axis=1)


JOINTS = ['pelvis', 'mid', 'top', 'head',
          'lshoulder', 'lelbow', 'lwrist', 'lhip', 'lknee', 'lankle', 'ltoe',
          'rshoulder', 'relbow', 'rwrist', 'rhip', 'rknee', 'rankle', 'rtoe', 'lhand', 'rhand']
BONES = [(0, 1), (1, 2), (2, 3), (2, 4), (4, 5), (5, 6), (6, 18), (2, 11), (11, 12), (12, 13), (13, 19),
         (0, 7), (7, 8), (8, 9), (9, 10), (0, 14), (14, 15), (15, 16), (16, 17)]


def facing(j):
    """Unit forward vector per frame (horizontal), from the hips and shoulders."""
    right = (j[:, 14] - j[:, 7]) + (j[:, 11] - j[:, 4])
    right[:, 1] = 0
    fwd = np.cross(np.array([0.0, 1.0, 0.0]), right)   # up x right
    n = np.linalg.norm(fwd, axis=1, keepdims=True)
    return fwd / np.maximum(n, 1e-6)


# ---------------------------------------------------------------------------
# BVH (100STYLE and others): joint positions by forward kinematics.

def read_bvh(path, start=0, end=None):
    """dict joint -> (frames, 3) positions in metres (source units are centimetres), y up.
    End sites are named '<parent>_end'. Returns (positions, frame_time)."""
    with open(path) as f:
        lines = f.read().split('\n')
    joints = []            # name, parent index, offset, channels
    stack = []
    i = 0
    while not lines[i].startswith('MOTION'):
        t = lines[i].split()
        if t and t[0] in ('ROOT', 'JOINT'):
            joints.append(dict(name=t[1], parent=stack[-1] if stack else -1, channels=[]))
            pending = len(joints) - 1
        elif t and t[0] == 'End':
            joints.append(dict(name=joints[stack[-1]]['name'] + '_end', parent=stack[-1], channels=[]))
            pending = len(joints) - 1
        elif t and t[0] == '{':
            stack.append(pending)
        elif t and t[0] == '}':
            stack.pop()
        elif t and t[0] == 'OFFSET':
            joints[stack[-1]]['offset'] = np.array([float(v) for v in t[1:4]])
        elif t and t[0] == 'CHANNELS':
            joints[stack[-1]]['channels'] = t[2:]
        i += 1
    count = int(lines[i + 1].split()[1])
    frame_time = float(lines[i + 2].split()[2])
    end = count if end is None else min(end, count)
    data = np.array([[float(v) for v in lines[i + 3 + k].split()] for k in range(start, end)])
    n = len(data)

    def axis_rot(axis, deg):
        a = np.radians(deg)
        c, s = np.cos(a), np.sin(a)
        R = np.zeros((n, 3, 3))
        if axis == 'X':
            R[:, 0, 0] = 1; R[:, 1, 1] = c; R[:, 1, 2] = -s; R[:, 2, 1] = s; R[:, 2, 2] = c
        elif axis == 'Y':
            R[:, 1, 1] = 1; R[:, 0, 0] = c; R[:, 0, 2] = s; R[:, 2, 0] = -s; R[:, 2, 2] = c
        else:
            R[:, 2, 2] = 1; R[:, 0, 0] = c; R[:, 0, 1] = -s; R[:, 1, 0] = s; R[:, 1, 1] = c
        return R

    out, rots = {}, []
    column = 0
    for j in joints:
        R = np.tile(np.eye(3), (n, 1, 1))
        translation = np.zeros((n, 3))
        for ch in j['channels']:
            v = data[:, column]; column += 1
            if ch.endswith('position'):
                translation[:, 'XYZ'.index(ch[0])] = v
            else:
                R = R @ axis_rot(ch[0], v)
        if j['parent'] < 0:
            pos = translation + j['offset']
            G = R
        else:
            P = rots[j['parent']]
            pos = out[joints[j['parent']]['name']] * 100 + np.einsum('nij,j->ni', P, j['offset']) + np.einsum('nij,nj->ni', P, translation)
            G = P @ R
        rots.append(G)
        out[j['name']] = pos / 100.0
    return out, frame_time


def figure_joints_bvh(p):
    """The app's 20 joints from a 100STYLE-style skeleton."""
    head = (p['Head'] + p['Head_end']) / 2
    cols = [p['Hips'], p['Chest2'], p['Neck'], head]
    for s in ('Left', 'Right'):
        cols += [p[s + 'Shoulder'], p[s + 'Elbow'], p[s + 'Wrist'], p[s + 'Hip'], p[s + 'Knee'], p[s + 'Ankle'], p[s + 'Toe']]
    for s in ('Left', 'Right'):
        cols += [p[s + 'Wrist_end']]
    return np.stack(cols, axis=1)


# ---------------------------------------------------------------------------
# Vicon Plug-in-Gait "Model Outputs" CSV (joint centres and segment origins, mm, z up).

def figure_joints_vicon(path):
    """(frames, 20, 3) in metres, y up, plus the capture rate. Cached beside the CSV as .npy."""
    import csv, os
    cache = path + '.joints.npy'
    with open(path, encoding='utf-8', errors='replace') as f:
        reader = csv.reader(f)
        header = [next(reader) for _ in range(5)]
        rate = float(header[1][0])
        if os.path.exists(cache):
            return np.load(cache), rate
        names, comps = header[2], header[3]
        groups, current = {}, None
        for i, c in enumerate(comps):
            n = names[i] if i < len(names) else ''
            if n:
                current = n.split(':')[1]
            if current and i >= 2:
                groups.setdefault(current, {}).setdefault(c, i)

        def columns(group):
            g = groups[group]
            return [g['TX'], g['TY'], g['TZ']] if 'TX' in g else [g['X'], g['Y'], g['Z']]
        order = ['PEL', None, 'TRX', 'HED',
                 'LSJC', 'LEJC', 'LWJC', 'LHJC', 'LKJC', 'LAJC', 'LFO',
                 'RSJC', 'REJC', 'RWJC', 'RHJC', 'RKJC', 'RAJC', 'RFO', 'LHN', 'RHN']
        cols = [columns(g) if g else None for g in order]
        frames = []
        for row in reader:
            if len(row) < 10 or not row[0].strip().isdigit():
                continue
            try:
                frame = [[float(row[i]) for i in c] if c else [0.0, 0.0, 0.0] for c in cols]
            except ValueError:
                frame = None                      # a gap in the capture
            frames.append(frame)
    # Fill gaps from the nearest good frame.
    last = next(f for f in frames if f is not None)
    for i, f in enumerate(frames):
        if f is None:
            frames[i] = last
        else:
            last = f
    raw = np.array(frames) / 1000.0
    j = np.stack([raw[..., 0], raw[..., 2], -raw[..., 1]], axis=-1)     # z up -> y up, still right-handed
    j[:, 1] = j[:, 0] * 0.45 + j[:, 2] * 0.55                           # mid-spine between pelvis and thorax
    np.save(cache, j)
    return j, rate


def figure_joints_any_bvh(p):
    """The app's 20 joints from whichever BVH naming the file uses (100STYLE or ACCAD/CMU-style)."""
    if 'Chest2' in p:
        return figure_joints_bvh(p)
    def end(name, fallback):
        return p.get(name + '_end', p[fallback])
    head = (p['Head'] + end('Head', 'Head')) / 2
    mid = p['Spine1'] if 'Spine1' in p else p['Spine']
    cols = [p['Hips'], mid, p['Neck'], head]
    for s in ('Left', 'Right'):
        cols += [p[s + 'Arm'], p[s + 'ForeArm'], p[s + 'Hand'], p[s + 'UpLeg'], p[s + 'Leg'], p[s + 'Foot'], p[s + 'ToeBase']]
    for s in ('Left', 'Right'):
        cols += [end(s + 'Hand', s + 'Hand')]
    return np.stack(cols, axis=1)
