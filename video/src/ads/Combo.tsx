import React from "react";
import { AbsoluteFill, Easing, Img, interpolate, staticFile, useCurrentFrame } from "remotion";
import { AskBar, FPS, Rings, grey, ink, line, pink, ring, s, sf, soft } from "./kit";
import T from "./combo.json";

// Every feature in one advert. One white page, one mascot that stays and changes mood, beats that
// cross-dissolve on the bar lines of the music (110 bpm), calm easing, no bounce.

const clamp = { extrapolateLeft: "clamp", extrapolateRight: "clamp" } as const;
const ease = Easing.bezier(0.22, 1, 0.36, 1);      // a long, soft settle
const inOut = Easing.bezier(0.65, 0, 0.35, 1);
const useT = () => useCurrentFrame() / FPS;
const rise = (t: number, a: number, d = 0.5) => interpolate(t, [a, a + d], [0, 1], { ...clamp, easing: ease });
const span = (id: string) => T.beats.find(b => b.id === id)!.span;

/** How present a beat is: dissolves in across its bar line and out across the next. */
const presence = (t: number, a: number, b: number) => {
  const i = interpolate(t, [a - 0.18, a + 0.32], [0, 1], { ...clamp, easing: ease });
  const o = interpolate(t, [b - 0.22, b + 0.18], [0, 1], { ...clamp, easing: inOut });
  return { in: i, out: o, alpha: i * (1 - o) };
};

const Layer: React.FC<{ a: number; b: number; children: React.ReactNode }> = ({ a, b, children }) => {
  const t = useT();
  if (t < a - 0.2 || t > b + 0.2) return null;
  const p = presence(t, a, b);
  return (
    <AbsoluteFill style={{ alignItems: "center", opacity: p.alpha, filter: `blur(${(1 - p.in) * 10 + p.out * 10}px)`,
                           transform: `translateY(${(1 - p.in) * 36 - p.out * 36}px) scale(${1 + (1 - p.in) * 0.02 - p.out * 0.02})` }}>
      {children}
    </AbsoluteFill>
  );
};

/** A label that settles in word by word; the pink word sits on a soft highlight. */
const Title: React.FC<{ text: string; at: number; top: number; size?: number; mark?: string[] }> = ({ text, at, top, size = 92, mark = [] }) => {
  const t = useT();
  return (
    <div style={{ position: "absolute", top, left: 70, right: 70, display: "flex", flexWrap: "wrap", justifyContent: "center", gap: `${size * 0.04}px ${size * 0.24}px`,
                  fontSize: size, fontWeight: 800, letterSpacing: -size * 0.032, lineHeight: 1.1, color: ink }}>
      {text.split(" ").map((w, i) => {
        const p = rise(t, at + i * 0.05, 0.6);
        const hl = mark.includes(w.replace(/[.,]/g, "").toLowerCase());
        return (
          <span key={i} style={{ position: "relative", isolation: "isolate", display: "inline-block", opacity: p, transform: `translateY(${(1 - p) * 22}px)`, color: hl ? pink : ink }}>
            {hl && <span style={{ position: "absolute", left: -8, right: -8, bottom: size * 0.06, height: size * 0.32, borderRadius: size * 0.1, background: "#FDE3EA", zIndex: -1,
                                   transform: `scaleX(${rise(t, at + 0.25 + i * 0.05, 0.5)})`, transformOrigin: "left" }} />}
            {w}
          </span>
        );
      })}
    </div>
  );
};

const Panel: React.FC<{ top: number; at: number; children: React.ReactNode; style?: React.CSSProperties }> = ({ top, at, children, style }) => {
  const t = useT();
  const p = rise(t, at, 0.6);
  return (
    <div style={{ position: "absolute", top, width: 940, boxSizing: "border-box", background: "#fff", border: `2px solid ${line}`, borderRadius: 44,
                  boxShadow: "0 24px 70px rgba(17,17,20,0.07)", padding: "40px 46px", opacity: p, transform: `translateY(${(1 - p) * 24}px)`, ...style }}>{children}</div>
  );
};

// ---------- the beats ----------

const Plan: React.FC<{ a: number }> = ({ a }) => {
  const t = useT();
  const days: [string, string, string][] = [["Mon", "🥣", "Overnight oats"], ["Tue", "🍗", "Chicken rice bowl"], ["Wed", "🍳", "Shakshuka"], ["Thu", "🐟", "Salmon & potatoes"]];
  return (
    <>
      <div style={{ position: "absolute", top: 440, width: "100%", display: "flex", justifyContent: "center" }}><AskBar text="Plan my week under €40" at={a + 0.15} cps={30} top={0} sendAt={a + 1.0} /></div>
      <div style={{ position: "absolute", top: 660, display: "grid", gridTemplateColumns: "1fr 1fr", gap: 22, width: 940 }}>
        {days.map(([d, e, n], i) => {
          const p = rise(t, a + 1.05 + i * 0.08, 0.55);
          return (
            <div key={d} style={{ background: "#fff", border: `2px solid ${line}`, borderRadius: 36, padding: "26px 28px", boxShadow: "0 14px 40px rgba(17,17,20,0.06)", opacity: p, transform: `translateY(${(1 - p) * 18}px)` }}>
              <div style={{ fontSize: 30, color: grey, fontWeight: 700 }}>{d}</div>
              <div style={{ display: "flex", alignItems: "center", gap: 14, marginTop: 8 }}><span style={{ fontSize: 66 }}>{e}</span><span style={{ fontSize: 38, fontWeight: 700, lineHeight: 1.1 }}>{n}</span></div>
            </div>
          );
        })}
      </div>
    </>
  );
};

const Budget: React.FC<{ a: number }> = ({ a }) => {
  const t = useT();
  const fill = interpolate(t, [a + 0.3, a + 1.4], [0, 38.6 / 40], { ...clamp, easing: inOut });
  const toast = rise(t, a + 1.3, 0.5);
  return (
    <>
      <Panel top={480} at={a + 0.05}>
        <div style={{ display: "flex", justifyContent: "space-between", alignItems: "baseline" }}>
          <div style={{ fontSize: 54, fontWeight: 800 }}>This week</div>
          <div style={{ fontSize: 42, color: grey, fontWeight: 600, fontVariantNumeric: "tabular-nums" }}>€{(fill * 40).toFixed(2)} of €40</div>
        </div>
        <div style={{ height: 28, borderRadius: 14, background: "#F1F1F4", marginTop: 28, overflow: "hidden" }}><div style={{ width: `${fill * 100}%`, height: "100%", background: pink, borderRadius: 14 }} /></div>
        <div style={{ display: "flex", gap: 18, marginTop: 30, fontSize: 36, fontWeight: 700 }}>
          <span style={{ background: "#E9F8F2", color: "#14805F", padding: "12px 24px", borderRadius: 30 }}>€1.40 to spare</span>
          <span style={{ background: "#FDE7EE", color: "#B3365A", padding: "12px 24px", borderRadius: 30 }}>21 meals</span>
        </div>
      </Panel>
      <div style={{ position: "absolute", top: 960, background: "#fff", border: `2px solid ${line}`, borderRadius: 50, padding: "24px 42px", fontSize: 42, fontWeight: 700,
                    boxShadow: "0 16px 40px rgba(17,17,20,0.08)", opacity: toast, transform: `translateY(${(1 - toast) * 18}px)` }}><span style={{ color: ring.protein }}>✓</span> 14 items in your cart</div>
    </>
  );
};

const Voice: React.FC<{ a: number }> = ({ a }) => {
  const t = useT();
  const words = "Two eggs and a banana".split(" ");
  const said = a + 0.3, wps = 5.5;
  const n = Math.max(0, Math.min(words.length, Math.floor((t - said) * wps) + 1));
  const talking = t > said && t < said + words.length / wps + 0.2;
  const level = talking ? 0.5 + 0.5 * Math.abs(Math.sin(t * 9)) : 0;
  const orb = rise(t, a, 0.6);
  return (
    <>
      <div style={{ position: "absolute", top: 450, width: 250, height: 250, opacity: orb, transform: `scale(${0.92 + 0.08 * orb})` }}>
        <div style={{ position: "absolute", inset: -40 * level, borderRadius: "50%", background: pink, opacity: 0.12 }} />
        <div style={{ position: "absolute", inset: -18 * level, borderRadius: "50%", background: pink, opacity: 0.18 }} />
        <div style={{ position: "absolute", inset: 0, borderRadius: "50%", background: pink, display: "flex", alignItems: "center", justifyContent: "center", boxShadow: "0 20px 50px rgba(232,105,138,0.35)" }}>
          <svg width={104} height={104} viewBox="0 0 24 24" fill="none" stroke="#fff" strokeWidth={2} strokeLinecap="round"><rect x={9} y={3} width={6} height={11} rx={3} fill="#fff" /><path d="M5.5 11.5a6.5 6.5 0 0 0 13 0M12 18v3" /></svg>
        </div>
      </div>
      <div style={{ position: "absolute", top: 770, fontSize: 62, fontWeight: 700, height: 80 }}>
        {t > said && words.slice(0, n).map((w, i) => <span key={i} style={{ opacity: rise(t, said + i / wps, 0.3) }}>{w} </span>)}
      </div>
      <Panel top={920} at={a + 1.25} style={{ display: "flex", alignItems: "center", gap: 40 }}>
        <Rings at={a + 1.3} size={260} values={[0.13, 0.12, 0.1, 0.16]} />
        <div><div style={{ fontSize: 34, color: grey, fontWeight: 700 }}>Breakfast</div><div style={{ fontSize: 86, fontWeight: 800, letterSpacing: -2 }}>261 kcal</div>
          <div style={{ fontSize: 34, color: ring.protein, fontWeight: 700 }}>✓ Logged</div></div>
      </Panel>
    </>
  );
};

const Scan: React.FC<{ a: number }> = ({ a }) => {
  const t = useT();
  const lock = interpolate(t, [a + 0.85, a + 1.05], [0, 1], { ...clamp, easing: ease });
  const bars = "1101001011101100101011011001010011011101001011".split("");
  const sweep = interpolate(t, [a + 0.1, a + 0.85], [0, 1], { ...clamp, easing: inOut });
  return (
    <>
      <div style={{ position: "absolute", top: 440, width: 760, height: 560, borderRadius: 54, background: "linear-gradient(180deg,#3A3F48,#1E2128)", overflow: "hidden", opacity: rise(t, a, 0.5) }}>
        <div style={{ position: "absolute", left: 160, top: 150, width: 440, height: 210, background: "#fff", borderRadius: 18, display: "flex", padding: "20px 26px", boxSizing: "border-box" }}>
          {bars.map((x, i) => <div key={i} style={{ flex: 1, background: x === "1" ? ink : "transparent" }} />)}
        </div>
        {[[0, 0], [1, 0], [0, 1], [1, 1]].map(([x, y], i) => {
          const pull = 20 * lock;
          return <div key={i} style={{ position: "absolute", left: x ? undefined : 120 + pull, right: x ? 120 + pull : undefined, top: y ? undefined : 110 + pull, bottom: y ? 170 + pull : undefined, width: 70, height: 70,
                                       borderColor: lock > 0.5 ? "#6FE0C8" : "#fff", borderStyle: "solid", borderWidth: `${y ? 0 : 8}px ${x ? 8 : 0}px ${y ? 8 : 0}px ${x ? 0 : 8}px`, borderRadius: 14 }} />;
        })}
        <div style={{ position: "absolute", left: 130, right: 130, top: 130 + sweep * 250, height: 4, background: pink, opacity: (1 - lock) * 0.9, boxShadow: `0 0 22px ${pink}` }} />
        <div style={{ position: "absolute", bottom: 46, left: 0, right: 0, textAlign: "center", color: "#fff", fontSize: 34, fontWeight: 600 }}>{lock > 0.5 ? "Found it" : "Point at a barcode"}</div>
      </div>
      <Panel top={1050} at={a + 1.0} style={{ display: "flex", alignItems: "center", gap: 26, padding: "32px 40px" }}>
        <span style={{ fontSize: 78 }}>🥛</span>
        <div style={{ flex: 1 }}><div style={{ fontSize: 44, fontWeight: 800 }}>Greek yogurt 0%</div><div style={{ fontSize: 32, color: grey }}>100 kcal · 17 g protein</div></div>
        <span style={{ fontSize: 40, color: ring.protein, fontWeight: 800 }}>✓</span>
      </Panel>
    </>
  );
};

const Stock: React.FC<{ a: number }> = ({ a }) => {
  const t = useT();
  const items = ["🥚", "🍅", "🧀", "🥬", "🧅", "🫑"];
  return (
    <>
      <div style={{ position: "absolute", top: 440, display: "grid", gridTemplateColumns: "repeat(3, 250px)", gap: 20 }}>
        {items.map((e, i) => {
          const p = rise(t, a + 0.05 + i * 0.06, 0.5);
          return <div key={i} style={{ height: 200, borderRadius: 36, background: soft, display: "flex", alignItems: "center", justifyContent: "center", fontSize: 104, opacity: p, transform: `translateY(${(1 - p) * 16}px)` }}>{e}</div>;
        })}
      </div>
      <Panel top={910} at={a + 0.85} style={{ display: "flex", gap: 28, alignItems: "center", border: `3px solid ${pink}`, padding: "32px 40px" }}>
        <div style={{ width: 150, height: 150, borderRadius: 34, background: "#FDEBDD", display: "flex", alignItems: "center", justifyContent: "center", fontSize: 88 }}>🍳</div>
        <div><div style={{ fontSize: 46, fontWeight: 800 }}>Shakshuka with feta</div><div style={{ fontSize: 32, color: grey, marginTop: 6 }}>20 min · 410 kcal</div>
          <div style={{ fontSize: 32, color: "#14805F", fontWeight: 700, marginTop: 8 }}>Uses 5 of your things</div></div>
      </Panel>
    </>
  );
};

const Train: React.FC<{ a: number }> = ({ a }) => {
  const t = useT();
  const p = interpolate(t, [a + 0.9, a + 2.1], [0, 0.6], { ...clamp, easing: Easing.linear });
  const r = 140, c = 2 * Math.PI * r;
  return (
    <>
      <Panel top={440} at={a + 0.05} style={{ padding: "34px 44px" }}>
        <div style={{ fontSize: 32, color: grey, fontWeight: 700 }}>Home · 30 min · Full body</div>
        {[["Squats", "3 × 12"], ["Push-ups", "3 × 10"], ["Plank", "3 × 40 s"]].map(([n, k], i) => (
          <div key={n} style={{ display: "flex", justifyContent: "space-between", padding: "20px 0", borderTop: i ? `2px solid ${line}` : "none", marginTop: i ? 0 : 8, fontSize: 42, fontWeight: 700, opacity: rise(t, a + 0.2 + i * 0.08, 0.5) }}>
            <span>{n}</span><span style={{ color: grey }}>{k}</span>
          </div>
        ))}
      </Panel>
      <div style={{ position: "absolute", top: 960, display: "flex", alignItems: "center", gap: 46, opacity: rise(t, a + 0.8, 0.5) }}>
        <svg width={330} height={330} viewBox="0 0 330 330" style={{ transform: "rotate(-90deg)" }}>
          <circle cx={165} cy={165} r={r} fill="none" stroke={ring.protein} strokeOpacity={0.15} strokeWidth={26} />
          <circle cx={165} cy={165} r={r} fill="none" stroke={ring.protein} strokeWidth={26} strokeLinecap="round" strokeDasharray={`${c * (1 - p)} ${c}`} />
        </svg>
        <div style={{ fontSize: 124, fontWeight: 800, fontVariantNumeric: "tabular-nums" }}>0:{String(Math.max(0, Math.ceil(40 - p * 40))).padStart(2, "0")}</div>
      </div>
    </>
  );
};

/** The one mascot, performing the whole advert in one take; the page only moves it to say hello and goodbye. */
const Bowl: React.FC = () => {
  const t = useT();
  const frame = useCurrentFrame();
  // big in the middle for the hook, small at the foot of the page for the features,
  // bigger again for the cheer, then it gives way to the icon at the end
  const toFoot = interpolate(t, [T.hook[1] - 0.35, T.hook[1] + 0.35], [0, 1], { ...clamp, easing: inOut });
  const cheer = interpolate(t, [span("cheer")[0] - 0.3, span("cheer")[0] + 0.4], [0, 1], { ...clamp, easing: inOut })
              * (1 - interpolate(t, [T.outro[0] - 0.25, T.outro[0] + 0.35], [0, 1], { ...clamp, easing: inOut }));
  const leave = interpolate(t, [T.end - 0.1, T.end + 0.6], [0, 1], { ...clamp, easing: inOut });
  const small = { y: 1450, size: 480 }, big = { y: 900, size: 820 }, mid = { y: 980, size: 680 };
  let y = big.y + (small.y - big.y) * toFoot, size = big.size + (small.size - big.size) * toFoot;
  y += (mid.y - y) * cheer; size += (mid.size - size) * cheer;
  if (t >= T.outro[0]) { const q = interpolate(t, [T.outro[0], T.outro[0] + 0.6], [0, 1], { ...clamp, easing: inOut }); y += (1100 - y) * q; size += (560 - size) * q; }
  // one continuous performance rendered from the app's mascot rig against this timeline (video/make-performance.sh)
  const src = staticFile(`clips/perf/f${String(Math.min(588, frame)).padStart(4, "0")}.png`);
  const breathe = 0; // the rig breathes on its own
  return (
    <div style={{ position: "absolute", left: 540 - size / 2, top: y - size / 2 + breathe, width: size, height: size, opacity: 1 - leave, transform: `scale(${1 - leave * 0.4})` }}>
      <Img src={src} style={{ position: "absolute", width: size, height: size }} />
    </div>
  );
};

/** The end: the page darkens, the icon arrives where the bowl was, the name and a search bar settle in. */
const End: React.FC = () => {
  const t = useT() - T.end;
  if (t < 0) return null;
  const dark = interpolate(t, [0, 0.7], [0, 1], { ...clamp, easing: inOut });
  const icon = rise(t, 0.3, 0.8);
  const iconY = interpolate(t, [1.0, 1.7], [1100, 700], { ...clamp, easing: inOut });
  const name = rise(t, 1.45, 0.6);
  const bar = interpolate(t, [1.75, 2.35], [0, 1], { ...clamp, easing: inOut });
  const word = "Nourlo", k = Math.floor(interpolate(t, [2.4, 2.9], [0, word.length], clamp));
  const store = rise(t, 3.0, 0.6);
  return (
    <AbsoluteFill style={{ background: `rgba(14,14,21,${dark})`, alignItems: "center", fontFamily: sf }}>
      <Img src={staticFile("icon.png")} style={{ position: "absolute", top: iconY - 125, width: 250, height: 250, borderRadius: 56, opacity: icon, transform: `scale(${0.9 + 0.1 * icon})`, boxShadow: "0 24px 70px rgba(232,105,138,0.25)" }} />
      <div style={{ position: "absolute", top: 900, color: "#fff", fontSize: 86, fontWeight: 800, letterSpacing: -1.5, opacity: name, transform: `translateY(${(1 - name) * 14}px)` }}>Nourlo</div>
      <div style={{ position: "absolute", top: 1036, width: 680, height: 104, borderRadius: 52, background: "#fff", opacity: bar, transform: `scaleX(${0.6 + 0.4 * bar})`, display: "flex", alignItems: "center", gap: 18, paddingLeft: 34, boxSizing: "border-box" }}>
        <svg width={40} height={40} viewBox="0 0 24 24" fill="none" stroke="#6E6E78" strokeWidth={2.6} strokeLinecap="round"><circle cx={10.5} cy={10.5} r={6.5} /><path d="M15.5 15.5 L21 21" /></svg>
        <span style={{ fontSize: 46, fontWeight: 700, color: ink }}>{word.slice(0, k)}</span>
        <span style={{ width: 4, height: 50, background: pink, opacity: k < word.length || Math.floor(t * 2) % 2 === 0 ? 1 : 0 }} />
      </div>
      <div style={{ position: "absolute", top: 1190, color: "#9A9AA0", fontSize: 40, fontWeight: 600, opacity: store }}>Download on the App Store</div>
    </AbsoluteFill>
  );
};

export const comboLength = s(T.dur);

export const Combo: React.FC = () => {
  const t = useT();
  const pieces: Record<string, React.FC<{ a: number }>> = { plan: Plan, budget: Budget, voice: Voice, scan: Scan, stock: Stock, train: Train };
  const marks: Record<string, string[]> = { plan: ["week"], budget: ["budget"], voice: ["voice"], scan: ["scan"], stock: ["have"], train: ["anywhere"], cheer: ["cheers"] };
  return (
    <AbsoluteFill style={{ background: "#fff", fontFamily: sf, color: ink }}>
      <Layer a={0} b={T.hook[1]}>
        <Title text="Your whole day, in one app" at={0.15} top={250} size={112} mark={["one"]} />
      </Layer>
      {T.beats.map(b => {
        const Piece = pieces[b.id];
        return (
          <Layer key={b.id} a={b.span[0]} b={b.id === "cheer" ? T.outro[0] : b.span[1]}>
            <Title text={b.label} at={b.span[0] + 0.05} top={b.id === "cheer" ? 300 : 230} size={b.id === "cheer" ? 104 : 92} mark={marks[b.id]} />
            {Piece && <Piece a={b.span[0]} />}
          </Layer>
        );
      })}
      <Layer a={T.outro[0]} b={T.end + 0.3}>
        <Title text="Meals. Budget. Training. One bowl." at={T.outro[0] + 0.05} top={420} size={112} mark={["one", "bowl"]} />
      </Layer>
      {t < T.end + 0.8 && <Bowl />}
      <End />
    </AbsoluteFill>
  );
};
