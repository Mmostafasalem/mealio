import React from "react";
import { AbsoluteFill, Easing, Img, interpolate, staticFile, useCurrentFrame } from "remotion";
import { FPS, Rings, grey, ink, line, pink, ring, sf, soft } from "../ads/kit";
import { Budget, Panel, Plan, Scan, Stock, Train, Voice } from "../ads/Combo";
import { Backdrop, Bubble, Countdown, Float, Headline, Kinetic, Listicle, Notifs, Phone, Quiz, Rain, Split as Versus, Theme, ThemeCtx, Track, dress, useTheme } from "./Styles";
import { Key, place } from "./path";

// A scripted advert (src/story/ads/<id>.json): scenes that change on the music's bar lines, and Nourlo,
// the app's real mascot, moving through them: walking between cards, jumping from one scene into the
// next, flexing at the gym. Nourlo's frames come from the app's mascot rig (video/make-stories.sh),
// which reads the same path, so its feet step and its body stretches and lands in time with the move.

export type Scene = {
  kind: string; at: number; label?: string; mark?: string[]; titleTop?: number; titleSize?: number;
  cut?: "slide" | "dissolve" | "zoom" | "rise" | "none"; [k: string]: unknown;
};
export type Overlay = { kind: "bubble" | "rain" | "float"; at: number; until?: number; [k: string]: unknown };
export type Script = { id: string; dur: number; bpm: number; scenes: Scene[]; path: Key[]; frames?: number; theme?: Theme; overlays?: Overlay[] };

const clamp = { extrapolateLeft: "clamp", extrapolateRight: "clamp" } as const;
const ease = Easing.bezier(0.22, 1, 0.36, 1);
const inOut = Easing.bezier(0.65, 0, 0.35, 1);
const useT = () => useCurrentFrame() / FPS;
export const rise = (t: number, a: number, d = 0.5) => interpolate(t, [a, a + d], [0, 1], { ...clamp, easing: ease });
const pop = (t: number, a: number) => {
  // a quick overshoot for badges and stickers
  const u = interpolate(t, [a, a + 0.45], [0, 1], clamp);
  return u === 0 ? 0 : 1 + Math.sin(u * Math.PI) * 0.18 * (1 - u) + (u < 1 ? -(1 - u) * (1 - u) * 0.6 : 0);
};

// ---------- new scenes ----------

const Workout: React.FC<{ a: number }> = ({ a }) => {
  const t = useT();
  const sets = [["Set 1", "60 kg × 8"], ["Set 2", "60 kg × 8"], ["Set 3", "62.5 kg × 8"]];
  const badge = pop(t, a + 1.75);
  return (
    <>
      <Panel top={440} at={a + 0.05} style={{ padding: "36px 44px" }}>
        <div style={{ display: "flex", justifyContent: "space-between", alignItems: "baseline" }}>
          <div style={{ fontSize: 50, fontWeight: 800 }}>Bench press</div>
          <div style={{ fontSize: 32, color: grey, fontWeight: 700 }}>Rest 1:30</div>
        </div>
        {sets.map(([n, w], i) => {
          const done = t > a + 0.55 + i * 0.4;
          return (
            <div key={n} style={{ display: "flex", alignItems: "center", gap: 24, padding: "20px 0", borderTop: `2px solid ${line}`, marginTop: i ? 0 : 18, fontSize: 42, fontWeight: 700 }}>
              <span style={{ width: 120, color: grey }}>{n}</span>
              <span style={{ flex: 1, fontVariantNumeric: "tabular-nums" }}>{w}</span>
              <span style={{ width: 62, height: 62, borderRadius: 31, background: done ? ring.protein : soft, color: "#fff", display: "flex", alignItems: "center", justifyContent: "center", fontSize: 36,
                             transform: `scale(${done ? pop(t, a + 0.55 + i * 0.4) || 1 : 1})` }}>{done ? "✓" : ""}</span>
            </div>
          );
        })}
      </Panel>
      <div style={{ position: "absolute", top: 1010, display: "flex", alignItems: "center", gap: 20, background: "#FFF6E0", border: "3px solid #F5C451", borderRadius: 60,
                    padding: "22px 40px", fontSize: 46, fontWeight: 800, color: "#8A5A00", opacity: Math.min(1, badge * 2), transform: `scale(${badge})` }}>
        🏆 New record · 62.5 kg
      </div>
    </>
  );
};

const Progress: React.FC<{ a: number }> = ({ a }) => {
  const t = useT();
  const weeks = [0.42, 0.5, 0.48, 0.61, 0.66, 0.74, 0.86, 1];
  return (
    <Panel top={440} at={a + 0.05} style={{ padding: "38px 44px" }}>
      <div style={{ fontSize: 34, color: grey, fontWeight: 700 }}>Weight lifted per week</div>
      <div style={{ display: "flex", alignItems: "flex-end", gap: 22, height: 400, marginTop: 30 }}>
        {weeks.map((h, i) => {
          const g = rise(t, a + 0.3 + i * 0.09, 0.6);
          return <div key={i} style={{ flex: 1, height: `${h * g * 100}%`, borderRadius: 16, background: i === weeks.length - 1 ? pink : "#F6C3D0" }} />;
        })}
      </div>
      <div style={{ marginTop: 26, fontSize: 46, fontWeight: 800, opacity: rise(t, a + 1.2, 0.5) }}><span style={{ color: ring.protein }}>▲ 24%</span> this month</div>
    </Panel>
  );
};

const Groceries: React.FC<{ a: number }> = ({ a }) => {
  const t = useT();
  const items: [string, string, string, number][] = [["🍗", "Chicken breast", "One of your foods", 5.49], ["🍚", "Brown rice", "For a balanced week", 1.89],
    ["🥦", "Broccoli", "For a balanced week", 1.49], ["🍌", "Bananas", "One of your foods", 1.19], ["🥛", "Greek yogurt", "One of your foods", 2.29]];
  const shown = items.filter((_, i) => t > a + 0.35 + i * 0.22).length;
  const total = items.slice(0, shown).reduce((x, it) => x + it[3], 0);
  return (
    <Panel top={420} at={a + 0.05} style={{ padding: "34px 44px" }}>
      <div style={{ display: "flex", justifyContent: "space-between", alignItems: "baseline" }}>
        <div style={{ fontSize: 46, fontWeight: 800 }}>This week's groceries</div>
        <div style={{ fontSize: 36, color: grey, fontWeight: 700, fontVariantNumeric: "tabular-nums" }}>€{total.toFixed(2)} / €40</div>
      </div>
      {items.map(([e, n, why, p], i) => {
        const r = rise(t, a + 0.35 + i * 0.22, 0.45);
        return (
          <div key={n} style={{ display: "flex", alignItems: "center", gap: 22, padding: "16px 0", borderTop: `2px solid ${line}`, marginTop: i ? 0 : 16, opacity: r, transform: `translateX(${(1 - r) * 40}px)` }}>
            <span style={{ fontSize: 58 }}>{e}</span>
            <div style={{ flex: 1 }}><div style={{ fontSize: 40, fontWeight: 700 }}>{n}</div><div style={{ fontSize: 28, color: grey, fontWeight: 600 }}>{why}</div></div>
            <span style={{ fontSize: 38, fontWeight: 700, fontVariantNumeric: "tabular-nums" }}>€{p.toFixed(2)}</span>
          </div>
        );
      })}
    </Panel>
  );
};

const Day: React.FC<{ a: number }> = ({ a }) => {
  const t = useT();
  const k = interpolate(t, [a + 0.3, a + 1.6], [0, 1840], { ...clamp, easing: inOut });
  return (
    <Panel top={440} at={a + 0.05} style={{ display: "flex", alignItems: "center", gap: 44, padding: "40px 44px" }}>
      <Rings at={a + 0.3} size={330} values={[0.88, 0.8, 0.72, 0.66]} />
      <div>
        <div style={{ fontSize: 34, color: grey, fontWeight: 700 }}>Today</div>
        <div style={{ fontSize: 96, fontWeight: 800, letterSpacing: -2, fontVariantNumeric: "tabular-nums" }}>{Math.round(k).toLocaleString("en")}</div>
        <div style={{ fontSize: 34, color: grey, fontWeight: 700 }}>of 2,100 kcal</div>
      </div>
    </Panel>
  );
};

const Recipe: React.FC<{ a: number }> = ({ a }) => {
  const t = useT();
  const lines = ["4 eggs", "4 tomatoes", "1 onion", "100 g feta"];
  const press = t > a + 1.55 && t < a + 1.75;
  const logged = rise(t, a + 1.75, 0.4);
  return (
    <Panel top={420} at={a + 0.05} style={{ padding: "36px 44px" }}>
      <div style={{ display: "flex", gap: 26, alignItems: "center" }}>
        <div style={{ width: 130, height: 130, borderRadius: 30, background: "#FDEBDD", display: "flex", alignItems: "center", justifyContent: "center", fontSize: 80 }}>🍳</div>
        <div><div style={{ fontSize: 50, fontWeight: 800 }}>Shakshuka</div><div style={{ fontSize: 32, color: grey, fontWeight: 600 }}>Wikibooks · 410 kcal a serving</div></div>
      </div>
      {lines.map((l, i) => (
        <div key={l} style={{ display: "flex", alignItems: "center", gap: 20, padding: "14px 0", fontSize: 40, fontWeight: 600, opacity: rise(t, a + 0.25 + i * 0.12, 0.4) }}>
          <span style={{ color: ring.protein, fontSize: 40, transform: `scale(${pop(t, a + 0.45 + i * 0.15) || 0})` }}>✓</span>{l}
        </div>
      ))}
      <div style={{ marginTop: 18, height: 104, borderRadius: 52, background: logged > 0.5 ? ring.protein : ink, color: "#fff", display: "flex", alignItems: "center", justifyContent: "center",
                    fontSize: 42, fontWeight: 800, transform: `scale(${press ? 0.95 : 1})` }}>{logged > 0.5 ? "✓ Logged 1 serving" : "🍴  I cooked this"}</div>
    </Panel>
  );
};

const Split: React.FC<{ a: number }> = ({ a }) => {
  const t = useT();
  const parts: [string, number, string][] = [["Breakfast", 25, "#F6B26B"], ["Lunch", 35, pink], ["Dinner", 30, "#8E7CC3"], ["Snack", 10, ring.protein]];
  return (
    <Panel top={440} at={a + 0.05} style={{ padding: "38px 44px" }}>
      <div style={{ fontSize: 34, color: grey, fontWeight: 700 }}>Your day, your way</div>
      <div style={{ display: "flex", height: 90, borderRadius: 45, overflow: "hidden", marginTop: 26 }}>
        {parts.map(([n, p, c], i) => <div key={n} style={{ width: `${p * rise(t, a + 0.3 + i * 0.15, 0.6)}%`, background: c }} />)}
      </div>
      {parts.map(([n, p, c], i) => (
        <div key={n} style={{ display: "flex", justifyContent: "space-between", fontSize: 42, fontWeight: 700, padding: "14px 0", opacity: rise(t, a + 0.5 + i * 0.12, 0.4) }}>
          <span><span style={{ display: "inline-block", width: 26, height: 26, borderRadius: 13, background: c, marginRight: 18 }} />{n}</span><span style={{ color: grey }}>{p}%</span>
        </div>
      ))}
    </Panel>
  );
};

const Shuffle: React.FC<{ a: number }> = ({ a }) => {
  const t = useT();
  const before = ["Chicken & rice", "Salmon & potatoes", "Lentil soup"], after = ["Beef & broccoli", "Chicken & spinach", "Egg fried rice"];
  const flip = (i: number) => interpolate(t, [a + 1.1 + i * 0.12, a + 1.4 + i * 0.12], [0, 1], { ...clamp, easing: inOut });
  return (
    <>
      <div style={{ position: "absolute", top: 440, width: 940, display: "flex", flexDirection: "column", gap: 20 }}>
        {before.map((b, i) => {
          const f = flip(i);
          return (
            <div key={b} style={{ background: "#fff", border: `2px solid ${line}`, borderRadius: 36, padding: "30px 36px", fontSize: 44, fontWeight: 700, boxShadow: "0 14px 40px rgba(17,17,20,0.06)",
                                  opacity: rise(t, a + 0.1 + i * 0.08, 0.5), transform: `rotateX(${(f < 0.5 ? f : f - 1) * 180}deg)` }}>
              <span style={{ color: grey, fontSize: 32, marginRight: 22 }}>{["Lunch", "Dinner", "Mon"][i]}</span>{f < 0.5 ? b : after[i]}
            </div>
          );
        })}
      </div>
      <div style={{ position: "absolute", top: 980, height: 110, padding: "0 56px", borderRadius: 55, background: pink, color: "#fff", display: "flex", alignItems: "center", gap: 18, fontSize: 44, fontWeight: 800,
                    opacity: rise(t, a + 0.4, 0.5), transform: `scale(${t > a + 0.95 && t < a + 1.12 ? 0.94 : 1})` }}>↻ Regenerate plan</div>
    </>
  );
};

const Lines: React.FC<{ a: number; items: string[] }> = ({ a, items }) => {
  const t = useT();
  return (
    <div style={{ position: "absolute", top: 520, display: "flex", flexDirection: "column", gap: 26, alignItems: "center" }}>
      {items.map((x, i) => {
        const r = rise(t, a + 0.35 + i * 0.25, 0.5);
        return <div key={x} style={{ fontSize: 58, fontWeight: 800, opacity: r, transform: `translateY(${(1 - r) * 20}px)`, background: soft, padding: "18px 40px", borderRadius: 40 }}>{x}</div>;
      })}
    </div>
  );
};

/** The end: the page darkens, the icon arrives, the name and "Download on the App Store". */
const End: React.FC<{ a: number }> = ({ a }) => {
  const t = useT() - a;
  if (t < 0) return null;
  const dark = interpolate(t, [0, 0.6], [0, 1], { ...clamp, easing: inOut });
  const icon = rise(t, 0.25, 0.7), name = rise(t, 0.7, 0.6), cta = rise(t, 1.05, 0.6);
  return (
    <AbsoluteFill style={{ background: `rgba(14,14,21,${dark})`, alignItems: "center", fontFamily: sf }}>
      <Img src={staticFile("icon.png")} style={{ position: "absolute", top: 520, width: 260, height: 260, borderRadius: 58, opacity: icon, transform: `scale(${0.85 + 0.15 * icon})`, boxShadow: "0 24px 70px rgba(232,105,138,0.3)" }} />
      <div style={{ position: "absolute", top: 820, color: "#fff", fontSize: 96, fontWeight: 800, letterSpacing: -2, opacity: name, transform: `translateY(${(1 - name) * 16}px)` }}>Nourlo</div>
      <div style={{ position: "absolute", top: 960, display: "flex", alignItems: "center", gap: 18, background: "#fff", color: ink, borderRadius: 60, padding: "24px 48px", fontSize: 42, fontWeight: 800, opacity: cta, transform: `scale(${0.9 + 0.1 * cta})` }}>
         Download on the App Store
      </div>
    </AbsoluteFill>
  );
};

const PIECES: Record<string, React.FC<{ a: number; s: Scene }>> = {
  plan: ({ a }) => <Plan a={a} />, budget: ({ a }) => <Budget a={a} />, voice: ({ a }) => <Voice a={a} />, scan: ({ a }) => <Scan a={a} />,
  stock: ({ a }) => <Stock a={a} />, timer: ({ a }) => <Train a={a} />, workout: ({ a }) => <Workout a={a} />, progress: ({ a }) => <Progress a={a} />,
  groceries: ({ a }) => <Groceries a={a} />, day: ({ a }) => <Day a={a} />, recipe: ({ a }) => <Recipe a={a} />, split: ({ a }) => <Split a={a} />,
  shuffle: ({ a }) => <Shuffle a={a} />, lines: ({ a, s }) => <Lines a={a} items={(s.items as string[]) ?? []} />, title: () => null, end: () => null,
  kinetic: ({ a, s }) => <Kinetic a={a} words={s.words as string[]} every={s.every as number} colors={s.colors as string[] | undefined} />,
  listicle: ({ a, s }) => <Listicle a={a} items={s.items as [string, string][]} every={s.every as number} />,
  phone: ({ a, s }) => <Phone a={a} from={s.from as number} top={s.top as number | undefined} scale={s.scale as number | undefined} tilt={s.tilt as number | undefined} />,
  notifs: ({ a, s }) => <Notifs a={a} items={s.items as [string, string, string][]} />,
  quiz: ({ a, s }) => <Quiz a={a} options={s.options as [string, string][]} pick={s.pick as number} at={s.pickAt as number} />,
  versus: ({ a, s }) => <Versus a={a} left={s.left as string[]} right={s.right as string[]} />,
  track: ({ a, s }) => <Track a={a} until={s.until as number} items={s.items as string[]} speed={s.speed as number} y={s.y as number} />,
  countdown: ({ a, s }) => <Countdown a={a} every={s.every as number} then={s.then as string | undefined} />,
};

/** A scene on screen from its start to the next one's, entering and leaving with its cut. */
const SceneLayer: React.FC<{ s: Scene; next?: Scene; until: number; index: number }> = ({ s, next, until, index }) => {
  const t = useT();
  const { theme } = useTheme();
  const a = s.at, b = until;
  if (t < a - 0.6 || t > b + 0.6) return null;
  const inCut = s.cut ?? "dissolve", outCut = next?.cut ?? "dissolve";
  const d = 0.55;
  const i = a === 0 ? 1 : interpolate(t, [a - d / 2, a + d / 2], [0, 1], { ...clamp, easing: inOut });
  const o = next ? interpolate(t, [b - d / 2, b + d / 2], [0, 1], { ...clamp, easing: inOut }) : 0;
  let x = 0, y = 0, sc = 1, op = 1, blur = 0;
  // arriving
  if (inCut === "slide") x += (1 - i) * 1080;
  if (inCut === "rise") y += (1 - i) * 1920;
  if (inCut === "zoom") { sc *= 1.18 - 0.18 * i; op *= i; }
  if (inCut === "dissolve") { op *= i; blur += (1 - i) * 10; y += (1 - i) * 30; }
  if (inCut === "none") op *= i > 0 ? 1 : 0;
  // leaving, the way the next scene arrives
  if (outCut === "slide") x -= o * 1080;
  if (outCut === "rise") { y -= o * 500; op *= 1 - o; }
  if (outCut === "zoom") { sc *= 1 - 0.1 * o; op *= 1 - o; }
  if (outCut === "dissolve") { op *= 1 - o; blur += o * 10; y -= o * 30; }
  if (outCut === "none") op *= o < 1 ? 1 : 0;
  const Piece = PIECES[s.kind];
  if (!Piece) throw new Error("unknown scene " + s.kind);
  return (
    <AbsoluteFill style={{ alignItems: "center", opacity: op, filter: blur > 0.2 ? `blur(${blur}px)` : undefined, transform: `translate(${x}px, ${y}px) scale(${sc})` }}>
      {s.kind === "notifs" && <AbsoluteFill style={{ background: "linear-gradient(170deg, #2C5BD8 0%, #3E8FD8 38%, #6FC1D6 70%, #A9E0D8 100%)" }} />}
      {s.label && <Headline text={s.label} at={a + 0.05} top={s.titleTop ?? (s.kind === "title" ? 300 : 200)} size={s.titleSize ?? (s.kind === "title" ? 120 : 92)} mark={s.mark ?? []} />}
      <AbsoluteFill style={{ alignItems: "center", ...dress(theme, index) }}><Piece a={a} s={s} /></AbsoluteFill>
    </AbsoluteFill>
  );
};

/** Nourlo: the rig's frames, placed on the path, leaning into the move, with a shadow on the ground. */
const Nourlo: React.FC<{ id: string; path: Key[]; frames: number; endAt: number }> = ({ id, path, frames, endAt }) => {
  const t = useT();
  const frame = useCurrentFrame();
  const p = place(path, t), q = place(path, t + 1 / FPS);
  const vx = (q.x - p.x) * FPS;
  const lean = p.moving === "jump" ? 0 : Math.max(-9, Math.min(9, vx / 90));
  const height = Math.max(0, p.ground - p.y);
  const leave = interpolate(t, [endAt - 0.1, endAt + 0.5], [0, 1], { ...clamp, easing: inOut });
  const src = staticFile(`clips/${id}/f${String(Math.min(frames - 1, frame)).padStart(4, "0")}.png`);
  const shadowW = p.size * 0.42 * (1 - Math.min(0.6, height / 600));
  return (
    <div style={{ position: "absolute", inset: 0, opacity: 1 - leave }}>
      <div style={{ position: "absolute", left: p.x - shadowW / 2, top: p.ground + p.size * 0.33, width: shadowW, height: shadowW * 0.16, borderRadius: "50%",
                    background: "rgba(17,17,20,0.10)", filter: "blur(6px)" }} />
      <Img src={src} style={{ position: "absolute", left: p.x - p.size / 2, top: p.y - p.size / 2, width: p.size, height: p.size,
                              transform: `rotate(${lean}deg) scale(${1 - leave * 0.3})`, transformOrigin: "50% 80%" }} />
    </div>
  );
};

export const Story: React.FC<{ script: Script }> = ({ script }) => {
  const t = useT();
  const { scenes, path, id, dur } = script;
  const overlays = script.overlays ?? [];
  const end = scenes.find(s => s.kind === "end");
  const behind = place(path, t).key?.behind;
  const frames = Math.round((dur + 0.5) * FPS);
  const nourlo = <Nourlo id={id} path={path} frames={frames} endAt={end ? end.at + 0.35 : dur + 1} />;
  return (
    <ThemeCtx.Provider value={{ theme: script.theme ?? "white", path }}>
      <AbsoluteFill style={{ fontFamily: sf, color: ink }}>
        <Backdrop />
        {overlays.filter(o => o.kind === "float").map((o, i) => <Float key={i} items={o.items as string[]} />)}
        {behind && nourlo}
        {scenes.filter(s => s.kind !== "end").map((s, i, list) => (
          <SceneLayer key={i} index={i} s={s} next={list[i + 1] ?? end} until={(list[i + 1] ?? end)?.at ?? dur + 1} />
        ))}
        {!behind && nourlo}
        {overlays.filter(o => o.kind === "rain").map((o, i) => <Rain key={i} a={o.at} items={o.items as string[]} every={o.every as number} />)}
        {overlays.filter(o => o.kind === "bubble").map((o, i) => <Bubble key={i} a={o.at} until={o.until ?? o.at + 2} text={o.text as string} side={o.side as "left" | "right" | undefined} />)}
        {end && <End a={end.at} />}
      </AbsoluteFill>
    </ThemeCtx.Provider>
  );
};
