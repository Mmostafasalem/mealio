// node score.mjs score.wav : synthesises the soundtrack from the same timeline as the picture.
import fs from 'fs';
import { createRequire } from 'module';
const require = createRequire(import.meta.url);
const T = require('./timeline.js');

const SR = 48000, N = Math.ceil(T.dur * SR);
const L = new Float32Array(N), R = new Float32Array(N), SEND = new Float32Array(N);

// ---------- notes ----------
const SEMI = { C: 0, 'C#': 1, Db: 1, D: 2, 'D#': 3, Eb: 3, E: 4, F: 5, 'F#': 6, Gb: 6, G: 7, 'G#': 8, Ab: 8, A: 9, 'A#': 10, Bb: 10, B: 11 };
function hz(name) {
  const m = /^([A-G][#b]?)(-?\d)$/.exec(name);
  if (!m || SEMI[m[1]] === undefined) throw new Error('Unknown note ' + name);
  return 440 * Math.pow(2, (SEMI[m[1]] + (+m[2] + 1) * 12 - 69) / 12);
}
let seed = 1;
const rnd = () => { seed = (seed * 1664525 + 1013904223) >>> 0; return seed / 4294967296; };

/** Mixes a mono signal into the stereo bus at `start` seconds. */
function put(sig, start, gain = 1, pan = 0, send = 0.25) {
  const s0 = Math.round(start * SR), gl = gain * Math.cos((pan + 1) * Math.PI / 4), gr = gain * Math.sin((pan + 1) * Math.PI / 4);
  for (let i = 0; i < sig.length; i++) {
    const j = s0 + i; if (j < 0 || j >= N) continue;
    const v = sig[i]; if (!Number.isFinite(v)) throw new Error('NaN in signal at ' + start);
    L[j] += v * gl; R[j] += v * gr; SEND[j] += v * gain * send;
  }
}

// ---------- instruments ----------
function pluck(f, dur = 1.6, bright = 0.5) {
  const n = Math.round(dur * SR), p = Math.max(2, Math.round(SR / f)), buf = new Float32Array(p), out = new Float32Array(n);
  for (let i = 0; i < p; i++) buf[i] = rnd() * 2 - 1;
  let prev = 0;
  for (let i = 0; i < n; i++) {
    const k = i % p, v = buf[k]; out[i] = v;
    const next = buf[(k + 1) % p]; buf[k] = (v * bright + next * (1 - bright)) * 0.996; prev = v;
  }
  return out;
}
function bell(f, dur = 2.5) {
  const n = Math.round(dur * SR), out = new Float32Array(n), parts = [[1, 1, 1.2], [2.76, 0.5, 2], [5.4, 0.25, 3.2], [8.93, 0.12, 5]];
  for (let i = 0; i < n; i++) { const t = i / SR; let v = 0; for (const [r, a, d] of parts) v += a * Math.sin(2 * Math.PI * f * r * t) * Math.exp(-d * t); out[i] = v * Math.min(1, t * 400) * 0.5; }
  return out;
}
function pad(notes, dur, attack = 0.7, release = 1.0) {
  const n = Math.round(dur * SR), out = new Float32Array(n), fs_ = notes.map(hz);
  let lp = 0;
  for (let i = 0; i < n; i++) {
    const t = i / SR; let v = 0;
    for (const f of fs_) for (const d of [0.996, 1, 1.004]) v += Math.sin(2 * Math.PI * f * d * t) + 0.25 * Math.sin(4 * Math.PI * f * d * t);
    const env = Math.min(1, t / attack) * Math.min(1, (dur - t) / release);
    lp += 0.08 * (v - lp); out[i] = lp * env / (fs_.length * 3);
  }
  return out;
}
/** Filtered noise with a gliding band: whooshes, risers, brush swishes. */
function noise(dur, f0, f1, q = 0.7, shape = 'arc') {
  const n = Math.round(dur * SR), out = new Float32Array(n); let low = 0, band = 0;
  for (let i = 0; i < n; i++) {
    const p = i / n, fc = f0 * Math.pow(f1 / f0, p), F = 2 * Math.sin(Math.PI * Math.min(fc, SR / 6) / SR);
    const x = rnd() * 2 - 1; low += F * band; const high = x - low - q * band; band += F * high;
    const env = shape === 'arc' ? Math.sin(Math.PI * p) : shape === 'up' ? Math.pow(p, 2) : Math.exp(-6 * p);
    out[i] = band * env;
  }
  return out;
}
function sweep(f0, f1, dur, decay = 6) {
  const n = Math.round(dur * SR), out = new Float32Array(n); let ph = 0;
  for (let i = 0; i < n; i++) { const p = i / n, f = f0 * Math.pow(f1 / f0, p); ph += 2 * Math.PI * f / SR; out[i] = Math.sin(ph) * Math.exp(-decay * p) * Math.min(1, i / 60); }
  return out;
}
const kick = () => sweep(130, 42, 0.42, 5);
function hat(dur = 0.05) { const n = Math.round(dur * SR), out = new Float32Array(n); let prev = 0; for (let i = 0; i < n; i++) { const x = rnd() * 2 - 1; out[i] = (x - prev) * Math.exp(-i / n * 5); prev = x; } return out; }
const blip = (f0, f1, d = 0.09) => sweep(f0, f1, d, 3);

// ---------- the score ----------
const H = T.hook;
put(noise(H.hit - H.start + 0.05, 5000, 500, 0.4), H.start, 0.55, 0, 0.3);           // the falling light
put(bell(hz('A6'), 1.0), H.start, 0.06, 0, 0.5);
put(kick(), H.hit, 0.9, 0, 0.1); put(sweep(90, 32, 0.9, 4), H.hit, 0.5, 0, 0.1);      // it lands
put(bell(hz('A5'), 3.0), H.hit, 0.22, 0, 0.6); put(noise(0.5, 6000, 2500, 0.5, 'drop'), H.hit, 0.25, 0, 0.4);

const sections = [
  [H.hit, T.drops[0].land, ['D3', 'A3', 'F4', 'C5']],
  [T.drops[0].land, T.drops[1].land, ['Bb2', 'F3', 'D4', 'A4']],
  [T.drops[1].land, T.drops[4].land, ['G2', 'D3', 'Bb3', 'F4']],
  [T.drops[4].land, T.breath.start + 0.4, ['A2', 'E3', 'C#4', 'G4']],
  [T.payoff.bloom, T.dur, ['D3', 'A3', 'F#4', 'A4', 'D5']],
];
for (const [a, b, notes] of sections) put(pad(notes, b - a + 0.6, a === H.hit ? 1.2 : 0.25, 0.9), a, 0.5, 0, 0.5);

put(blip(500, 1100), T.wake, 0.22, -0.3); put(blip(600, 1300), T.wake + 0.1, 0.2, 0.3);   // eyes open
const blinks = [3.0, 8.6, T.breath.blink, 14.6];
for (const bt of blinks) put(blip(1800, 2600, 0.03), bt + 0.08, 0.08);

// a soft pluck for each word as it appears
const scales = [['D4', 'F4', 'A4', 'C5', 'D5', 'F5'], ['D4', 'F4', 'A4', 'Bb4', 'D5', 'F5'], ['D4', 'G4', 'Bb4', 'D5', 'F5', 'G5'], ['E4', 'A4', 'C#5', 'E5', 'G5', 'A5']];
T.lines.forEach((line, li) => {
  const start = line.at + (li > 0 ? 0.22 : 0), words = line.text.join(' ').split(' ');
  words.forEach((_, wi) => put(pluck(hz(scales[li][wi % 6]), 1.2, 0.45), start + wi * 0.07, 0.13, (wi % 2 ? 0.25 : -0.25), 0.35));
});

// drops: a shimmer as each appears, a whoosh as it falls, a landing sound
for (const d of T.drops) {
  put(bell(hz(d.kind === 'coin' ? ['E6', 'G6', 'B6'][d.i] : 'D6'), 1.2), d.show, 0.07, 0, 0.6);
  put(noise(0.6, 900, 4000, 0.6), d.show, 0.12, 0, 0.4);
  put(noise(d.land - d.fall + 0.05, 3500, 400, 0.45), d.fall, 0.35, 0, 0.25);
  if (d.kind === 'fruit') {
    put(kick(), d.land, 0.55); for (const [k, n] of ['D4', 'F4', 'A4', 'D5'].entries()) put(pluck(hz(n), 1.8, 0.5), d.land + k * 0.035, 0.22, -0.3 + k * 0.2, 0.35);
    put(noise(0.25, 2500, 1200, 0.6, 'drop'), d.land, 0.25);
  } else if (d.kind === 'coin') {
    put(bell(2350 + d.i * 260, 0.9), d.land, 0.18, 0.4, 0.4); put(bell(3520 + d.i * 300, 0.5), d.land + 0.012, 0.1, 0.4, 0.4); put(hat(0.04), d.land, 0.25, 0.4);
  } else {
    put(kick(), d.land, 1.0, 0, 0.1); put(sweep(70, 28, 1.0, 3.5), d.land, 0.6, 0, 0.1); put(pluck(hz('D2'), 2, 0.6), d.land, 0.4, 0, 0.2);
    put(noise(0.4, 1800, 300, 0.5, 'drop'), d.land, 0.35);
  }
}

// a light pulse from the first landing to the breath, busier with each section
const beat = 0.6;
for (let t = T.drops[0].land, k = 0; t < T.breath.start - 0.05; t += beat / 2, k++) {
  if (k % 2 === 0 && Math.abs(t - T.drops[4].land) > 0.1) put(kick(), t, 0.32, 0, 0.05);
  else put(hat(), t, 0.16, 0.3, 0.1);
  if (t > T.drops[1].land) put(hat(0.03), t + beat / 4, 0.08, -0.3, 0.1);
}

// breath: silence, the blink tick, then a riser into the payoff
put(noise(T.payoff.bloom - 11.9, 300, 7000, 0.35, 'up'), 11.9, 0.5, 0, 0.3);

const P = T.payoff;
put(kick(), P.bloom, 1.0, 0, 0.1); put(sweep(110, 30, 1.2, 3), P.bloom, 0.55, 0, 0.1);
for (const [k, n] of ['D5', 'F#5', 'A5', 'D6'].entries()) put(bell(hz(n), 3.5), P.bloom + k * 0.03, 0.12, -0.3 + k * 0.2, 0.7);
put(noise(0.35, 600, 3000, 0.6), P.bloom, 0.18);                                    // the hop
put(kick(), P.hopLand, 0.6); put(noise(0.3, 2000, 800, 0.6, 'drop'), P.hopLand, 0.2);
['D5', 'E5', 'F#5', 'A5', 'B5', 'D6'].forEach((n, i) => put(pluck(hz(n), 1.6, 0.5), P.word + i * 0.08, 0.2, -0.4 + i * 0.16, 0.4));
put(noise(0.6, 2400, 4200, 0.8), P.word + 0.35, 0.16, 0.2, 0.2);                       // brush under the name
put(pluck(hz('A4'), 1.4, 0.5), P.sub, 0.14, 0, 0.4);
put(blip(520, 980, 0.12), P.button, 0.3); put(bell(hz('D6'), 2.5), P.button + 0.02, 0.1, 0, 0.6);

// ---------- reverb (Freeverb style) ----------
function freeverb(input, spread) {
  const sc = SR / 44100, combs = [1116, 1188, 1277, 1356, 1422, 1491, 1557, 1617].map(d => ({ b: new Float32Array(Math.round((d + spread) * sc)), i: 0, f: 0 }));
  const alls = [556, 441, 341, 225].map(d => ({ b: new Float32Array(Math.round((d + spread) * sc)), i: 0 }));
  const out = new Float32Array(N), fb = 0.84, damp = 0.25;
  for (let n = 0; n < N; n++) {
    const x = input[n] * 0.015; let y = 0;
    for (const c of combs) { const o = c.b[c.i]; c.f = o * (1 - damp) + c.f * damp; c.b[c.i] = x + c.f * fb; c.i = (c.i + 1) % c.b.length; y += o; }
    for (const a of alls) { const o = a.b[a.i]; a.b[a.i] = y + o * 0.5; a.i = (a.i + 1) % a.b.length; y = o - y; }
    out[n] = y;
  }
  return out;
}
const wl = freeverb(SEND, 0), wr = freeverb(SEND, 23);
let peak = 0;
for (let i = 0; i < N; i++) { L[i] = Math.tanh((L[i] + wl[i]) * 1.1); R[i] = Math.tanh((R[i] + wr[i]) * 1.1); peak = Math.max(peak, Math.abs(L[i]), Math.abs(R[i])); }
if (!(peak > 0.01)) throw new Error('The score is silent');
const g = 0.89 / peak;

// ---------- WAV ----------
const out = Buffer.alloc(44 + N * 4);
out.write('RIFF', 0); out.writeUInt32LE(36 + N * 4, 4); out.write('WAVE', 8); out.write('fmt ', 12);
out.writeUInt32LE(16, 16); out.writeUInt16LE(1, 20); out.writeUInt16LE(2, 22); out.writeUInt32LE(SR, 24); out.writeUInt32LE(SR * 4, 28); out.writeUInt16LE(4, 32); out.writeUInt16LE(16, 34);
out.write('data', 36); out.writeUInt32LE(N * 4, 40);
for (let i = 0; i < N; i++) { out.writeInt16LE(Math.round(Math.max(-1, Math.min(1, L[i] * g)) * 32767), 44 + i * 4); out.writeInt16LE(Math.round(Math.max(-1, Math.min(1, R[i] * g)) * 32767), 46 + i * 4); }
fs.writeFileSync(process.argv[2] || 'score.wav', out);
console.log('score written, peak before normalising', peak.toFixed(3));
