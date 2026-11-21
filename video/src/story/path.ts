// Where Nourlo is at time t: the same easing as MascotSnapshotTests.place (the rig reads the same keys,
// so walking steps the feet and a jump lifts, stretches and lands the body in time with the picture).
export type Key = { t: number; x: number; y: number; size: number; move?: "walk" | "jump" | "glide"; arc?: number; behind?: boolean };

export function place(keys: Key[], t: number) {
  const first = keys[0];
  if (!first || t <= first.t) return { x: first?.x ?? 540, y: first?.y ?? 1400, size: first?.size ?? 480, ground: first?.y ?? 1400, moving: undefined as Key["move"], u: 0, key: first, prev: first };
  for (let i = 1; i < keys.length; i++) {
    const a = keys[i - 1], b = keys[i];
    if (t < b.t) {
      const u = (t - a.t) / Math.max(0.001, b.t - a.t);
      const e = u * u * (3 - 2 * u);
      const move = b.move ?? "glide";
      const lift = move === "jump" ? -4 * (b.arc ?? 220) * u * (1 - u) : 0;
      const still = a.x === b.x && a.y === b.y;
      const y = a.y + (b.y - a.y) * e;
      return { x: a.x + (b.x - a.x) * e, y: y + lift, ground: y, size: a.size + (b.size - a.size) * e, moving: still ? undefined : move, u, key: b, prev: a };
    }
  }
  const last = keys[keys.length - 1];
  return { x: last.x, y: last.y, ground: last.y, size: last.size, moving: undefined as Key["move"], u: 1, key: last, prev: last };
}
