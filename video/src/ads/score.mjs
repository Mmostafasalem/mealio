// node src/ads/score.mjs <ad> <out.wav> : the soundtrack for one advert, timed from its timeline JSON.
import fs from 'fs';
import path from 'path';
import { fileURLToPath } from 'url';
const here = path.dirname(fileURLToPath(import.meta.url));
const [AD, OUT] = process.argv.slice(2);
const T = JSON.parse(fs.readFileSync(path.join(here, `${AD}.json`), 'utf8'));
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


// ---------- sound effects ----------
const fx = {
  notif: t => { put(bell(hz('B5'), 1.2), t, 0.16, 0.1, 0.4); put(bell(hz('E6'), 1.4), t + 0.1, 0.14, 0.1, 0.4); },
  type: (t, n, cps) => { for (let i = 0; i < n; i++) { const g = 0.12 + rnd() * 0.06; put(noise(0.03, 3000 + rnd() * 2500, 1500, 0.9, 'drop'), t + i / cps + rnd() * 0.01, g, (rnd() - 0.5) * 0.4, 0.05); } },
  click: t => { put(noise(0.035, 4000, 1800, 0.9, 'drop'), t, 0.4, 0.1, 0.1); put(blip(900, 600, 0.05), t, 0.12); },
  whoosh: (t, d = 0.35) => put(noise(d, 600, 3800, 0.6), t - d * 0.6, 0.22, 0, 0.3),
  pop: t => put(blip(380, 900, 0.1), t, 0.2, 0, 0.3),
  tick: t => put(bell(hz('A6'), 0.25), t, 0.035, 0.3, 0.3),
  chime: t => ['C6', 'E6', 'G6'].forEach((n, i) => put(bell(hz(n), 2.2), t + i * 0.05, 0.08, -0.2 + i * 0.2, 0.6)),
  shimmer: (t, d) => { for (let k = 0; t + k * 0.12 < t + d; k++) put(bell(hz(['E6', 'G6', 'B6', 'D7'][k % 4]), 0.6), t + k * 0.12, 0.03, (k % 2 ? 0.4 : -0.4), 0.7); },
  hit: t => { put(kick(), t, 0.5, 0, 0.1); put(bell(hz('C5'), 2), t, 0.08, 0, 0.6); },
};
// The end card: dot, icon, bar, typing, chime.
function endCard(at) { fx.pop(at + 0.1); fx.whoosh(at + 0.55); fx.hit(at + 0.6); fx.whoosh(at + 1.8, 0.3); fx.type(at + 2.5, 6, 12); fx.chime(at + 3.05); }

// ---------- music: a light marimba bed, I-V-vi-IV ----------
function bed(from, to, gain = 1, quiet = []) {
  const beat = 60 / 112, prog = [['C4', 'E4', 'G4', 'C5'], ['G3', 'B3', 'D4', 'G4'], ['A3', 'C4', 'E4', 'A4'], ['F3', 'A3', 'C4', 'F4']];
  const bass = ['C3', 'G2', 'A2', 'F2'];
  const isQuiet = t => quiet.some(([a, b]) => t >= a && t < b);
  for (let k = 0, t = from; t < to - 0.2; k++, t += beat / 2) {
    if (isQuiet(t)) continue;
    const bar = Math.floor(k / 8) % 4, chord = prog[bar];
    put(pluck(hz(chord[[0, 2, 1, 3, 2, 1, 3, 2][k % 8]]), 0.9, 0.62), t, 0.075 * gain, k % 2 ? 0.25 : -0.25, 0.3);
    if (k % 4 === 0) put(pluck(hz(bass[bar]), 1.4, 0.7), t, 0.12 * gain, 0, 0.15);
    if (k % 2 === 0 && t > from + beat * 8) put(kick(), t, 0.16 * gain, 0, 0.02);
    if (k % 4 === 2 && t > from + beat * 8) put(noise(0.08, 1800, 900, 0.8, 'drop'), t, 0.1 * gain, 0, 0.1);
    if (k % 2 === 1 && t > from + beat * 16) put(hat(0.03), t, 0.05 * gain, 0.3, 0.05);
  }
}

// ---------- each advert ----------
const ads = {
  notifications() {
    bed(0.3, T.end, 1, [[T.earlier - 0.1, T.ask.at]]);
    T.before.concat(T.afterList).forEach(n => fx.notif(n.at));
    fx.whoosh(T.earlier); fx.whoosh(T.after); fx.whoosh(T.punch.at); fx.whoosh(T.end);
    fx.type(T.ask.at, T.ask.text.length, T.ask.cps); fx.click(T.ask.sent); fx.whoosh(T.ask.sent + 0.35);
    fx.shimmer(T.ask.sent + 0.3, T.plan.at - T.ask.sent - 0.3);
    T.plan.days.forEach((_, i) => fx.tick(T.plan.at + 0.45 + i * 0.16));
    fx.pop(T.plan.button); fx.click(T.plan.click); fx.chime(T.plan.toast);
    fx.pop(T.mascot); fx.chime(T.mascot + 0.3);
    fx.type(T.punch.at + 0.15, T.punch.text.length, T.punch.cps);
    endCard(T.end);
  },
  chips() {
    bed(0.2, T.end, 1);
    for (let i = 0; i < 12; i++) put(blip(500 + i * 40, 900 + i * 40, 0.06), 0.05 * i + 0.1, 0.06, (i % 2 ? 0.4 : -0.4), 0.3);
    fx.whoosh(T.intro.out); fx.whoosh(T.prompt.at + 0.1);
    [T.days.click, T.days.pick, T.diet.click, T.diet.pick, T.cart.click, ...T.cart.picks, T.generate.click].forEach(fx.click);
    fx.pop(T.generate.show); fx.shimmer(T.dots[0], T.dots[1] - T.dots[0]); fx.chime(T.grid);
    for (let i = 0; i < 7; i++) fx.tick(T.grid + i * 0.12);
    fx.whoosh(T.share.head); fx.whoosh(T.chat.at);
    [T.chat.them, T.chat.card, T.chat.reply].forEach(t => put(noise(0.12, 1200, 3000, 0.7), t - 0.05, 0.18, 0, 0.2));
    fx.notif(T.chat.reply); fx.pop(T.chat.mascot);
    endCard(T.end);
  },
  voice() {
    bed(0.2, T.end, 1, [[T.one.say - 0.1, T.one.card], [T.two.say - 0.1, T.two.card], [T.three.say - 0.1, T.three.card]]);
    fx.click(T.plus); fx.pop(T.menu); fx.click(T.pick);
    for (const k of ['one', 'two', 'three']) {
      const v = T[k], words = v.text.split(' ').length;
      fx.pop(v.at); put(bell(hz('E6'), 0.8), v.at + 0.05, 0.08, 0, 0.5);              // listening
      for (let i = 0; i < words; i++) put(blip(700 + (i % 3) * 120, 900 + (i % 3) * 120, 0.05), v.say + i / v.wps, 0.06, (i % 2 ? 0.3 : -0.3), 0.3);
      fx.whoosh(v.card); fx.chime(v.card + 0.15);
    }
    fx.chime(T.one.saved); fx.whoosh(T.rings); for (let i = 0; i < 4; i++) fx.tick(T.rings + 0.25 + i * 0.1);
    fx.whoosh(T.head.at); put(noise(0.7, 2500, 4500, 0.8), T.head.at + 0.5, 0.12, 0.2, 0.2);  // the pen
    fx.pop(T.two.card + 0.2); fx.whoosh(T.final.at); fx.pop(T.final.at + 0.1);
    endCard(T.end);
  },
  goals() {
    bed(0.2, T.end, 1);
    for (let i = 0; i < 16; i++) put(blip(450 + (i % 8) * 50, 800 + (i % 8) * 50, 0.05), i * 0.04 + 0.05, 0.05, (i % 2 ? 0.4 : -0.4), 0.3);
    fx.whoosh(T.intro.out); fx.whoosh(T.form.at);
    fx.type(T.form.q1 + 0.3, T.form.a1.length, 20); fx.type(T.form.q2 + 0.3, T.form.a2.length, 20);
    T.form.chips.forEach(fx.click); fx.click(T.form.next);
    fx.whoosh(T.styles.at); for (let i = 0; i < 4; i++) fx.tick(T.styles.at + 0.2 + i * 0.08); fx.click(T.styles.pick);
    T.heroes.forEach(t => { fx.whoosh(t); fx.hit(t + 0.05); });
    fx.whoosh(T.grid.at); for (let i = 0; i < 9; i++) fx.tick(T.grid.at + i * 0.05);
    fx.whoosh(T.outro.at); fx.chime(T.outro.at + 0.6);
    endCard(T.end);
  },
  moods() {
    bed(0.2, T.end, 1.1);
    T.beats.forEach((b, i) => {
      const at = 0.3 + i * T.beat;
      fx.whoosh(at, 0.3); fx.pop(at + 0.6);
      const mood = b[1];
      if (mood === 'celebrate') { fx.chime(at + 0.3); fx.shimmer(at + 0.4, 0.8); }
      if (mood === 'love') for (let k = 0; k < 4; k++) put(bell(hz(['C6', 'E6', 'G6', 'C7'][k]), 0.8), at + 0.3 + k * 0.15, 0.06, 0, 0.6);
      if (mood === 'worried') put(sweep(700, 380, 0.5, 2), at + 0.3, 0.12);
      if (mood === 'sleepy') put(noise(1.2, 300, 200, 0.9), at + 0.3, 0.1, 0, 0.3);
      if (mood === 'cheeky') put(blip(600, 1400, 0.15), at + 0.5, 0.15);
      if (mood === 'hello' || mood === 'happy') put(blip(500, 1000, 0.12), at + 0.3, 0.14);
    });
    fx.whoosh(T.outro); fx.chime(T.outro + 0.3);
    endCard(T.end);
  },
  scan() {
    bed(0.2, T.end, 1);
    fx.whoosh(T.head.at); put(noise(0.3, 2000, 3500, 0.8), T.head.strike, 0.18, 0, 0.2);
    fx.whoosh(T.cam.at); fx.whoosh(T.cam.product + 0.4, 0.5);
    put(noise(T.cam.lock - T.cam.product, 1200, 1300, 0.95), T.cam.product, 0.05, 0, 0.1);      // the scan hum
    put(blip(1800, 1800, 0.08), T.cam.lock, 0.3, 0, 0.2); put(blip(2400, 2400, 0.08), T.cam.lock + 0.1, 0.25, 0, 0.2);  // beep beep
    fx.whoosh(T.card.at); fx.click(T.card.add); fx.chime(T.card.add + 0.1);
    fx.whoosh(T.rings.at); for (let i = 0; i < 4; i++) fx.tick(T.rings.at + 0.2 + i * 0.1);
    T.rapid.forEach(t => { put(blip(1800, 1800, 0.06), t, 0.25); put(blip(2400, 2400, 0.06), t + 0.08, 0.2); fx.pop(t + 0.15); });
    fx.pop(T.rapid[2] + 0.2);
    T.words.forEach((t, i) => { put(kick(), t, 0.45); put(bell(hz(['C5', 'E5', 'G5'][i]), 1.5), t, 0.1, 0, 0.5); });
    endCard(T.end);
  },
  receipt() {
    bed(0.2, T.end, 1, [[T.before.at, T.before.stamp + 0.1]]);
    const printer = (at, n, lps) => { for (let i = 0; i < n; i++) put(noise(0.12, 900, 700, 0.9), at + i / lps, 0.12, 0, 0.05); };
    printer(T.before.at, 12, T.before.lps); printer(T.after.at, 15, T.after.lps);
    put(kick(), T.before.stamp, 0.7); put(sweep(400, 120, 0.5, 3), T.before.stamp, 0.25);      // a sad thud
    fx.whoosh(T.before.out); fx.whoosh(T.then.at); fx.whoosh(T.then.out);
    put(kick(), T.after.stamp, 0.6); fx.chime(T.after.stamp + 0.05);
    fx.whoosh(T.after.out); fx.whoosh(T.budget.at); fx.pop(T.budget.at + 0.2);
    fx.whoosh(T.line.at); fx.chime(T.line.at + 0.5);
    endCard(T.end);
  },
  train() {
    bed(0.2, T.end, 1, [[T.think.at, T.think.out]]);
    fx.whoosh(T.head.out); fx.whoosh(T.builder.at);
    fx.click(T.builder.home); for (let i = 0; i < 10; i++) fx.tick(T.builder.slide[0] + i * (T.builder.slide[1] - T.builder.slide[0]) / 10);
    fx.click(T.builder.focus); fx.click(T.builder.build);
    fx.shimmer(T.think.at, T.think.out - T.think.at); fx.whoosh(T.session.at); fx.chime(T.session.at + 0.1);
    for (let i = 0; i < 5; i++) fx.tick(T.session.at + 0.3 + i * 0.13);
    fx.click(T.session.start); fx.whoosh(T.timer.at);
    for (let k = 0; k < 6; k++) put(blip(1000, 1000, 0.04), T.timer.at + 0.3 + k * 0.5, 0.08);        // the timer ticking
    put(kick(), T.timer.out - 0.4, 0.5); fx.chime(T.timer.out - 0.4);
    fx.whoosh(T.line.at); fx.pop(T.line.at + 0.4);
    endCard(T.end);
  },
  stock() {
    bed(0.2, T.end, 1, [[T.think.at, T.think.out]]);
    fx.whoosh(T.head.out); for (let i = 0; i < 9; i++) fx.pop(T.shelf.at + 0.15 + i * 0.08);
    fx.click(T.shelf.cook); fx.shimmer(T.think.at, T.think.out - T.think.at);
    fx.whoosh(T.recipes.at); for (let i = 0; i < 3; i++) fx.tick(T.recipes.at + 0.2 + i * 0.2); fx.click(T.recipes.pick);
    fx.whoosh(T.detail.at); for (let i = 0; i < 4; i++) { put(blip(800, 1300, 0.06), T.detail.at + 0.9 + i * 0.55, 0.12); }
    fx.whoosh(T.line.at); fx.chime(T.line.at + 0.5);
    endCard(T.end);
  },
};
ads.combo = () => {
  const B = T.beats;
  bed(0.2, T.end, 1);
  for (let i = 0; i < 10; i++) put(blip(500 + i * 40, 900 + i * 40, 0.06), 0.04 * i + 0.05, 0.05, (i % 2 ? 0.4 : -0.4), 0.3);
  Object.values(B).forEach(([a]) => fx.whoosh(a, 0.3));
  fx.type(B.plan[0] + 0.15, 22, 32); fx.click(B.plan[0] + 1.0); for (let i = 0; i < 4; i++) fx.tick(B.plan[0] + 1.1 + i * 0.1);
  for (let i = 0; i < 5; i++) fx.tick(B.budget[0] + 0.25 + i * 0.2); fx.chime(B.budget[0] + 1.25);
  fx.pop(B.voice[0] + 0.05); for (let i = 0; i < 5; i++) put(blip(700 + (i % 3) * 120, 900 + (i % 3) * 120, 0.05), B.voice[0] + 0.3 + i / 6, 0.06); fx.chime(B.voice[0] + 1.3);
  put(blip(1800, 1800, 0.08), B.scan[0] + 0.9, 0.3); put(blip(2400, 2400, 0.08), B.scan[0] + 1.0, 0.25); fx.pop(B.scan[0] + 1.1);
  for (let i = 0; i < 6; i++) fx.pop(B.stock[0] + 0.1 + i * 0.07); fx.chime(B.stock[0] + 0.9);
  for (let k = 0; k < 3; k++) put(blip(1000, 1000, 0.04), B.train[0] + 1.0 + k * 0.4, 0.08);
  put(kick(), B.cheer[0], 0.5); fx.chime(B.cheer[0] + 0.1); fx.shimmer(B.cheer[0] + 0.2, 0.9);
  fx.whoosh(T.outro); ['C5', 'E5', 'G5', 'C6'].forEach((n, i) => { put(kick(), T.outro + 0.1 + i * 0.12, 0.25); put(bell(hz(n), 1.4), T.outro + 0.1 + i * 0.12, 0.08, 0, 0.5); });
  endCard(T.end);
};
ads.moods2 = ads.moods;
ads[AD]();

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
fs.writeFileSync(OUT, out);
console.log('score written, peak before normalising', peak.toFixed(3));
