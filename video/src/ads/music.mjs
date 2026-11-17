// node src/ads/music.mjs <ad> <out.wav> : a warm, musical soundtrack timed to the picture's bar lines.
// Electric piano chords, a soft bass, light drums and a mallet tune; the interface sounds are a few quiet taps.
import fs from 'fs';
import path from 'path';
import { fileURLToPath } from 'url';
const here = path.dirname(fileURLToPath(import.meta.url));
const [AD, OUT] = process.argv.slice(2);
const T = JSON.parse(fs.readFileSync(path.join(here, `${AD}.json`), 'utf8'));
const SR = 48000, N = Math.ceil(T.dur * SR);
const bus = { music: [new Float32Array(N), new Float32Array(N)], drums: [new Float32Array(N), new Float32Array(N)], fx: [new Float32Array(N), new Float32Array(N)] };
const SEND = new Float32Array(N);
const TAU = Math.PI * 2;

let seed = 7;
const rnd = () => { seed = (seed * 1664525 + 1013904223) >>> 0; return seed / 4294967296; };
const SEMI = { C: 0, 'C#': 1, Db: 1, D: 2, Eb: 3, E: 4, F: 5, 'F#': 6, G: 7, Ab: 8, A: 9, Bb: 10, B: 11 };
function hz(n) { const m = /^([A-G][#b]?)(-?\d)$/.exec(n); if (!m || SEMI[m[1]] === undefined) throw new Error('note ' + n); return 440 * 2 ** ((SEMI[m[1]] + (+m[2] + 1) * 12 - 69) / 12); }

function put(where, sig, t, gain = 1, pan = 0, send = 0.2) {
  const [L, R] = bus[where], s0 = Math.round(t * SR), gl = gain * Math.cos((pan + 1) * Math.PI / 4), gr = gain * Math.sin((pan + 1) * Math.PI / 4);
  for (let i = 0; i < sig.length; i++) {
    const j = s0 + i; if (j < 0 || j >= N) continue;
    const v = sig[i]; if (!Number.isFinite(v)) throw new Error('NaN at ' + t);
    L[j] += v * gl; R[j] += v * gr; SEND[j] += v * gain * send;
  }
}

// ---------- instruments ----------
function epiano(f, dur, vel = 1) {
  const len = Math.round((dur + 0.5) * SR), o = new Float32Array(len);
  for (let i = 0; i < len; i++) {
    const t = i / SR, rel = t < dur ? 1 : Math.max(0, 1 - (t - dur) / 0.5);
    const v = Math.sin(TAU * f * t) * Math.exp(-t * 1.1) + 0.32 * Math.sin(TAU * 2 * f * t) * Math.exp(-t * 3.2)
            + 0.1 * Math.sin(TAU * 3 * f * t) * Math.exp(-t * 6) + 0.04 * vel * Math.sin(TAU * 7 * f * t) * Math.exp(-t * 28);
    o[i] = v * Math.min(1, t / 0.004) * rel * (1 + 0.05 * Math.sin(TAU * 4.6 * t)) * (0.55 + 0.45 * vel);
  }
  return o;
}
function mallet(f, len = 1.3) {
  const n = Math.round(len * SR), o = new Float32Array(n);
  for (let i = 0; i < n; i++) { const t = i / SR; o[i] = (Math.sin(TAU * f * t) * Math.exp(-t * 4.5) + 0.22 * Math.sin(TAU * 3.98 * f * t) * Math.exp(-t * 22)) * Math.min(1, t / 0.002); }
  return o;
}
function bass(f, dur) {
  const n = Math.round((dur + 0.08) * SR), o = new Float32Array(n);
  for (let i = 0; i < n; i++) { const t = i / SR, rel = t < dur ? 1 : Math.max(0, 1 - (t - dur) / 0.08); o[i] = (Math.sin(TAU * f * t) + 0.18 * Math.sin(TAU * 2 * f * t)) * Math.min(1, t / 0.008) * Math.exp(-t * 0.9) * rel; }
  return o;
}
function pad(notes, dur) {
  const n = Math.round((dur + 1.2) * SR), o = new Float32Array(n), fs_ = notes.map(hz); let lp = 0;
  for (let i = 0; i < n; i++) {
    const t = i / SR; let v = 0;
    for (const f of fs_) for (const d of [0.997, 1.003]) v += Math.sin(TAU * f * d * t) + 0.3 * Math.sin(TAU * 2 * f * d * t + 1);
    lp += 0.05 * (v - lp);
    o[i] = lp / (fs_.length * 2) * Math.min(1, t / 1.0) * (t < dur ? 1 : Math.max(0, 1 - (t - dur) / 1.2));
  }
  return o;
}
function kick() {
  const n = Math.round(0.35 * SR), o = new Float32Array(n); let ph = 0;
  for (let i = 0; i < n; i++) { const t = i / SR; ph += TAU * (48 + 62 * Math.exp(-t * 32)) / SR; o[i] = Math.sin(ph) * Math.exp(-t * 8) * Math.min(1, t / 0.001); }
  return o;
}
function shaker() {
  const n = Math.round(0.07 * SR), o = new Float32Array(n); let lp = 0, lp2 = 0;
  for (let i = 0; i < n; i++) { const t = i / SR, x = rnd() * 2 - 1; lp += 0.5 * (x - lp); const hp = x - lp; lp2 += 0.6 * (hp - lp2); o[i] = lp2 * Math.min(1, t / 0.006) * Math.exp(-t * 45); }
  return o;
}
function snap() {
  const n = Math.round(0.12 * SR), o = new Float32Array(n); let low = 0, band = 0; const F = 2 * Math.sin(Math.PI * 2100 / SR);
  for (let i = 0; i < n; i++) { const t = i / SR, x = rnd() * 2 - 1; low += F * band; const high = x - low - 0.25 * band; band += F * high; o[i] = (band * 0.6 + 0.25 * Math.sin(TAU * 1750 * t)) * Math.exp(-t * 38); }
  return o;
}
function tap(f = 1900, g = 1) {
  const n = Math.round(0.06 * SR), o = new Float32Array(n);
  for (let i = 0; i < n; i++) { const t = i / SR; o[i] = g * (0.6 * Math.sin(TAU * f * t) * Math.exp(-t * 95) + 0.4 * Math.sin(TAU * f * 0.5 * t) * Math.exp(-t * 60)) * Math.min(1, t / 0.0015); }
  return o;
}
function swish(len = 0.45) {
  const n = Math.round(len * SR), o = new Float32Array(n); let lp = 0;
  for (let i = 0; i < n; i++) { const p = i / n, c = 0.02 + 0.12 * Math.sin(Math.PI * p); lp += c * ((rnd() * 2 - 1) - lp); o[i] = lp * Math.sin(Math.PI * p) ** 1.5; }
  return o;
}

// ---------- shared moments ----------
const fx = {
  type: (t, n, cps) => { for (let i = 0; i < n; i += 1) put('fx', tap(1600 + rnd() * 700, 0.6), t + i / cps, 0.05, (rnd() - 0.5) * 0.4, 0.05); },
  tap: t => put('fx', tap(1900), t, 0.12, 0, 0.15),
  success: t => { put('fx', mallet(hz('E6'), 1.0), t, 0.09, -0.15, 0.4); put('fx', mallet(hz('B6'), 1.0), t + 0.07, 0.08, 0.15, 0.4); },
  swish: t => put('fx', swish(), t - 0.3, 0.07, 0, 0.3),
  beep: t => { put('fx', tap(1760, 1), t, 0.07, 0, 0.1); put('fx', tap(2350, 1), t + 0.09, 0.06, 0, 0.1); },
};

// ---------- the song: 110 bpm, F major, a bar per beat of the picture ----------
function song({ bars, drumsFrom, drumsTo, endAt }) {
  const beat = 60 / T.bpm, bar = beat * 4;
  const chords = {
    Fmaj7: { bass: 'F2', keys: ['A3', 'C4', 'E4', 'G4'], tune: ['C6', 'A5', 'G5', 'E5'] },
    Am7: { bass: 'A2', keys: ['G3', 'C4', 'E4', 'A4'], tune: ['E6', 'C6', 'A5', 'G5'] },
    Dm9: { bass: 'D2', keys: ['F3', 'A3', 'C4', 'E4'], tune: ['D6', 'A5', 'F5', 'E5'] },
    Bbmaj7: { bass: 'Bb1', keys: ['F3', 'A3', 'D4', 'F4'], tune: ['D6', 'C6', 'A5', 'F5'] },
    Csus: { bass: 'C2', keys: ['G3', 'C4', 'F4', 'Bb4'], tune: ['C6', 'Bb5', 'G5', 'F5'] },
    Fadd9: { bass: 'F2', keys: ['A3', 'C4', 'F4', 'G4'], tune: ['A5', 'C6', 'F6', 'G6'] },
  };
  const kicks = [];
  bars.forEach((name, k) => {
    const c = chords[name], t0 = k * bar; if (t0 > T.dur) return;
    const last = k === bars.length - 1;
    put('music', pad(c.keys.map(n => n.replace(/\d/, d => String(+d - 1))), bar * (last ? 1.6 : 1)), t0, 0.16, 0, 0.5);
    // keys: on 1, the "and" of 2, and the "and" of 3 — a gentle push
    const hits = last ? [[0, 1]] : [[0, 1], [1.5, 0.55], [2.5, 0.45]];
    for (const [b, vel] of hits) c.keys.forEach((n, i) => put('music', epiano(hz(n), beat * (last ? 6 : 1.4), vel), t0 + b * beat + i * 0.006, 0.075 * vel, -0.3 + i * 0.2, 0.3));
    // bass
    put('music', bass(hz(c.bass), beat * (last ? 6 : 1.6)), t0, 0.32, 0, 0.05);
    if (!last) put('music', bass(hz(c.bass), beat * 0.8), t0 + 2.5 * beat, 0.2, 0, 0.05);
    // the tune: a small figure from the chord, answered every other bar
    const figure = k % 2 === 0 ? [[0.5, 0], [1, 1], [2, 2], [3, 1]] : [[0.5, 3], [1.5, 2], [2.5, 1], [3.5, 0]];
    if (!last) for (const [b, i] of figure) put('music', mallet(hz(c.tune[i])), t0 + b * beat, 0.07, 0.3, 0.45);
    else c.tune.forEach((n, i) => put('music', mallet(hz(n), 2), t0 + 0.2 + i * beat * 0.5, 0.06, -0.3 + i * 0.2, 0.55));
    // drums
    if (k >= drumsFrom && k < drumsTo) {
      for (const b of [0, 2]) { put('drums', kick(), t0 + b * beat, 0.42, 0, 0); kicks.push(t0 + b * beat); }
      for (const b of [1, 3]) put('drums', snap(), t0 + b * beat, 0.11, 0.05, 0.25);
      for (let e = 0; e < 8; e++) put('drums', shaker(), t0 + e * beat / 2 + (e % 2 ? 0.012 : 0), e % 2 ? 0.05 : 0.03, 0.35, 0.05);
    }
  });
  return { kicks, beat, bar, endAt };
}

// ---------- garage kit: sunny 2-step, original ----------
function svf(x, f, q) { // returns a band-pass of x at f
  const out = new Float32Array(x.length); let low = 0, band = 0; const F = 2 * Math.sin(Math.PI * Math.min(f, SR / 6) / SR);
  for (let i = 0; i < x.length; i++) { low += F * band; const high = x[i] - low - q * band; band += F * high; out[i] = band; }
  return out;
}
function noiseBuf(len) { const o = new Float32Array(Math.round(len * SR)); for (let i = 0; i < o.length; i++) o[i] = rnd() * 2 - 1; return o; }
function kick2() {
  const n = Math.round(0.3 * SR), o = new Float32Array(n); let ph = 0;
  for (let i = 0; i < n; i++) { const t = i / SR; ph += TAU * (50 + 110 * Math.exp(-t * 40)) / SR; o[i] = Math.tanh(1.6 * Math.sin(ph)) * Math.exp(-t * 9) * Math.min(1, t / 0.0008) + (t < 0.004 ? (rnd() - 0.5) * 0.3 * (1 - t / 0.004) : 0); }
  return o;
}
function clap() {
  const n = Math.round(0.25 * SR), raw = noiseBuf(0.25), o = svf(raw, 1300, 0.9);
  for (let i = 0; i < n; i++) { const t = i / SR; const bursts = [0, 0.009, 0.018].some(b => t >= b && t < b + 0.006) ? 1 : 0; o[i] *= (bursts * 0.9 + Math.exp(-(t - 0.02) * 22) * (t > 0.02 ? 0.7 : 0)); }
  return o;
}
function hat(open = false) {
  const len = open ? 0.18 : 0.045, raw = noiseBuf(len), o = new Float32Array(raw.length); let a = 0, b = 0;
  for (let i = 0; i < o.length; i++) { const x = raw[i]; a += 0.35 * (x - a); const h1 = x - a; b += 0.5 * (h1 - b); o[i] = (h1 - b * 0.4) * Math.exp(-i / SR * (open ? 18 : 90)); }
  return o;
}
function sub(f, dur) {
  const n = Math.round((dur + 0.05) * SR), o = new Float32Array(n);
  for (let i = 0; i < n; i++) { const t = i / SR, rel = t < dur ? 1 : Math.max(0, 1 - (t - dur) / 0.05); o[i] = Math.tanh(1.4 * Math.sin(TAU * f * t)) * Math.min(1, t / 0.006) * rel * Math.exp(-t * 0.8); }
  return o;
}
function organ(notes, dur) {
  const n = Math.round((dur + 0.08) * SR), o = new Float32Array(n), fs_ = notes.map(hz);
  for (let i = 0; i < n; i++) {
    const t = i / SR, rel = t < dur ? 1 : Math.max(0, 1 - (t - dur) / 0.08); let v = 0;
    for (const f of fs_) v += Math.sin(TAU * f * t) + 0.5 * Math.sin(TAU * 2 * f * t) + 0.25 * Math.sin(TAU * 3 * f * t) + 0.3 * Math.sin(TAU * 2 * f * t) * Math.exp(-t * 30);
    o[i] = v / fs_.length * Math.min(1, t / 0.003) * rel * (1 + 0.04 * Math.sin(TAU * 6 * t));
  }
  return o;
}
function voxLead(f, dur) { // an "ah" synth: a saw through two vowel formants
  const n = Math.round((dur + 0.15) * SR), saw = new Float32Array(n); let ph = 0;
  for (let i = 0; i < n; i++) { const t = i / SR; ph = (ph + f * (1 + 0.004 * Math.sin(TAU * 5.5 * t)) / SR) % 1; saw[i] = 2 * ph - 1; }
  const a = svf(saw, 760, 0.35), b = svf(saw, 1180, 0.4), o = new Float32Array(n);
  for (let i = 0; i < n; i++) { const t = i / SR, rel = t < dur ? 1 : Math.max(0, 1 - (t - dur) / 0.15); o[i] = (a[i] + 0.7 * b[i]) * Math.min(1, t / 0.015) * rel; }
  return o;
}

// The interface: real-feeling keys, a mouse click (press and release), whooshes.
function keyPress() {
  const raw = noiseBuf(0.03), o = svf(raw, 2600 + rnd() * 1400, 0.6), thock = 170 + rnd() * 60;
  for (let i = 0; i < o.length; i++) { const t = i / SR; o[i] = o[i] * Math.exp(-t * 160) + 0.5 * Math.sin(TAU * thock * t) * Math.exp(-t * 90); }
  return o;
}
function mouseClick() {
  const n = Math.round(0.12 * SR), o = new Float32Array(n);
  const part = (at, g) => { const s0 = Math.round(at * SR); for (let i = 0; i < SR * 0.012 && s0 + i < n; i++) { const t = i / SR; o[s0 + i] += g * ((rnd() * 2 - 1) * Math.exp(-t * 900) + 0.5 * Math.sin(TAU * 3800 * t) * Math.exp(-t * 600)); } };
  part(0, 1); part(0.075, 0.55);
  return svf(o, 3500, 1.2).map((v, i) => v + o[i] * 0.3);
}
function whoosh(len = 0.5) {
  const n = Math.round(len * SR), o = new Float32Array(n); let low = 0, band = 0;
  for (let i = 0; i < n; i++) {
    const p = i / n, f = 300 * Math.pow(12, Math.sin(Math.PI * p * 0.85)), F = 2 * Math.sin(Math.PI * f / SR);
    low += F * band; const high = (rnd() * 2 - 1) - low - 0.7 * band; band += F * high;
    o[i] = band * Math.pow(Math.sin(Math.PI * p), 1.6);
  }
  return o;
}
const ui = {
  type: (t, n, cps) => { for (let i = 0; i < n; i++) put('fx', keyPress(), t + i / cps + (rnd() - 0.5) * 0.012, 0.22 + rnd() * 0.08, (rnd() - 0.5) * 0.3, 0.06); },
  click: t => put('fx', mouseClick(), t, 0.45, 0.1, 0.08),
  whoosh: (t, len = 0.5) => { put('fx', whoosh(len), t - len * 0.62, 0.32, -0.2, 0.35); },
  success: t => { put('fx', mallet(hz('E6'), 1.0), t, 0.12, -0.15, 0.4); put('fx', mallet(hz('B6'), 1.0), t + 0.07, 0.11, 0.15, 0.4); },
  beep: t => { put('fx', tap(1760, 1), t, 0.12, 0, 0.1); put('fx', tap(2350, 1), t + 0.09, 0.1, 0, 0.1); },
};

/** Sunny 2-step garage at T.bpm: shuffled hats, skippy kick, claps on 2 and 4, organ stabs, a sub, an "ah" lead. */
function garage({ bars, drumsFrom, drumsTo }) {
  const beat = 60 / T.bpm, bar = beat * 4, six = beat / 4, swing = 0.17;
  const at16 = (t0, p) => t0 + (p + (p % 2 ? swing : 0)) * six;
  const chords = {
    Bbmaj9: { root: 'Bb1', keys: ['A3', 'C4', 'D4', 'F4'] }, Am7: { root: 'A1', keys: ['G3', 'C4', 'E4', 'A4'] },
    Gm9: { root: 'G1', keys: ['F3', 'A3', 'Bb3', 'D4'] }, C13: { root: 'C2', keys: ['Bb3', 'E4', 'A4', 'D5'] },
    Fmaj9: { root: 'F1', keys: ['A3', 'C4', 'E4', 'G4'] },
  };
  const lead = [['D5', 0, 2], ['F5', 3, 2], ['A5', 6, 3], ['G5', 10, 2], ['F5', 12, 3]];
  const lead2 = [['C5', 0, 2], ['D5', 3, 2], ['F5', 6, 4], ['E5', 11, 4]];
  const kicks = [];
  bars.forEach((name, k) => {
    const c = chords[name], t0 = k * bar; if (t0 > T.dur) return;
    const last = k === bars.length - 1, full = k >= drumsFrom && k < drumsTo;
    // a soft bed under everything
    put('music', pad(c.keys.map(n => n.replace(/\d/, d => String(+d - 1))), bar * (last ? 2 : 1)), t0, 0.12, 0, 0.5);
    // organ stabs on the skips
    const stabs = last ? [[0, 1.2]] : (full ? [[0, 0.22], [3, 0.16], [6, 0.18], [10, 0.16], [13, 0.2]] : [[0, 0.5], [6, 0.3], [11, 0.3]]);
    for (const [p, d] of stabs) put('music', organ(c.keys, d), at16(t0, p), last ? 0.13 : 0.1, 0, 0.3);
    // the sub, bouncing
    const bassHits = last ? [[0, bar * 1.5]] : [[0, 2.5], [3, 1.5], [7, 2], [10, 2.5], [14, 1]];
    for (const [p, d] of bassHits) put('music', sub(hz(c.root.replace('1', '2')) * (p === 7 ? 2 : 1), (last ? d : d * six)), at16(t0, p), 0.3, 0, 0.03);
    // the "ah" lead, every other bar, from the first full bar
    if (full && k % 2 === 1) for (const [n, p, len] of (k % 4 === 1 ? lead : lead2)) put('music', voxLead(hz(n), len * six), at16(t0, p), 0.05, 0.25, 0.45);
    // drums
    if (full) {
      for (const p of [0, 10]) { put('drums', kick2(), at16(t0, p), 0.5, 0, 0); kicks.push(at16(t0, p)); }
      if (k % 2 === 1) { put('drums', kick2(), at16(t0, 7), 0.35, 0, 0); kicks.push(at16(t0, 7)); }
      for (const p of [4, 12]) put('drums', clap(), at16(t0, p), 0.22, 0.05, 0.2);
      put('drums', snap(), at16(t0, 14), 0.07, -0.2, 0.2);
      for (let p = 0; p < 16; p++) {
        const open = p % 4 === 2;
        if (p % 4 === 0 && p !== 0) continue;
        put('drums', hat(open), at16(t0, p), open ? 0.06 : (p % 2 ? 0.07 : 0.045), 0.3, 0.05);
      }
    } else if (!last && k < drumsFrom) {
      // the intro: just the hats and a filtered pulse, so the beat drops on the first feature
      for (let p = 2; p < 16; p += 4) put('drums', hat(true), at16(t0, p), 0.04, 0.3, 0.1);
    }
  });
  return { kicks };
}

// ---------- each advert ----------
const ads = {
  combo() {
    const s = garage({ bars: ['Bbmaj9', 'Bbmaj9', 'Am7', 'Gm9', 'C13', 'Bbmaj9', 'Am7', 'Gm9', 'C13', 'Bbmaj9', 'C13', 'Fmaj9', 'Fmaj9'], drumsFrom: 1, drumsTo: 10 });
    const by = id => T.beats.find(b => b.id === id).span[0];
    T.beats.forEach(b => ui.whoosh(b.span[0])); ui.whoosh(T.outro[0]); ui.whoosh(T.end + 0.3, 0.7);
    ui.type(by('plan') + 0.15, 22, 30); ui.click(by('plan') + 1.0);
    ui.success(by('budget') + 1.3);
    ui.success(by('voice') + 1.3);
    ui.beep(by('scan') + 0.85); ui.success(by('scan') + 1.05);
    ui.success(by('stock') + 0.9);
    ui.click(by('train') + 0.85);
    ui.type(T.end + 2.4, 6, 12);
    return s;
  },
};
const { kicks } = ads[AD]();

// ---------- mix: the music leans away from each kick, a warm room, a gentle top ----------
function freeverb(input, spread) {
  const sc = SR / 44100, combs = [1116, 1188, 1277, 1356, 1422, 1491, 1557, 1617].map(d => ({ b: new Float32Array(Math.round((d + spread) * sc)), i: 0, f: 0 }));
  const alls = [556, 441, 341, 225].map(d => ({ b: new Float32Array(Math.round((d + spread) * sc)), i: 0 }));
  const out = new Float32Array(N);
  for (let n = 0; n < N; n++) {
    const x = input[n] * 0.015; let y = 0;
    for (const c of combs) { const o = c.b[c.i]; c.f = o * 0.7 + c.f * 0.3; c.b[c.i] = x + c.f * 0.82; c.i = (c.i + 1) % c.b.length; y += o; }
    for (const a of alls) { const o = a.b[a.i]; a.b[a.i] = y + o * 0.5; a.i = (a.i + 1) % a.b.length; y = o - y; }
    out[n] = y;
  }
  return out;
}
const wl = freeverb(SEND, 0), wr = freeverb(SEND, 23);
const duck = new Float32Array(N).fill(1);
for (const k of kicks) { const s0 = Math.round(k * SR); for (let i = 0; i < SR * 0.3 && s0 + i < N; i++) duck[s0 + i] = Math.min(duck[s0 + i], 1 - 0.28 * Math.exp(-i / SR * 11)); }
const outL = new Float32Array(N), outR = new Float32Array(N);
let lpL = 0, lpR = 0, peak = 0;
const fade = Math.round(0.6 * SR);
for (let i = 0; i < N; i++) {
  let l = bus.music[0][i] * duck[i] + bus.drums[0][i] + bus.fx[0][i] + wl[i] * 0.9;
  let r = bus.music[1][i] * duck[i] + bus.drums[1][i] + bus.fx[1][i] + wr[i] * 0.9;
  lpL += 0.62 * (l - lpL); lpR += 0.62 * (r - lpR);           // soften the very top
  const g = i > N - fade ? (N - i) / fade : 1;
  outL[i] = Math.tanh(lpL * 1.2) * g; outR[i] = Math.tanh(lpR * 1.2) * g;
  peak = Math.max(peak, Math.abs(outL[i]), Math.abs(outR[i]));
}
if (!(peak > 0.01)) throw new Error('silent');
const gain = 0.89 / peak;
const buf = Buffer.alloc(44 + N * 4);
buf.write('RIFF', 0); buf.writeUInt32LE(36 + N * 4, 4); buf.write('WAVE', 8); buf.write('fmt ', 12); buf.writeUInt32LE(16, 16); buf.writeUInt16LE(1, 20); buf.writeUInt16LE(2, 22);
buf.writeUInt32LE(SR, 24); buf.writeUInt32LE(SR * 4, 28); buf.writeUInt16LE(4, 32); buf.writeUInt16LE(16, 34); buf.write('data', 36); buf.writeUInt32LE(N * 4, 40);
for (let i = 0; i < N; i++) { buf.writeInt16LE(Math.round(Math.max(-1, Math.min(1, outL[i] * gain)) * 32767), 44 + i * 4); buf.writeInt16LE(Math.round(Math.max(-1, Math.min(1, outR[i] * gain)) * 32767), 46 + i * 4); }
fs.writeFileSync(OUT, buf);
console.log('music written');
