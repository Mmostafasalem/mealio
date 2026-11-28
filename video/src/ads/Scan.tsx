import React from "react";
import { AbsoluteFill, Easing, Sequence, interpolate, useCurrentFrame } from "remotion";
import { Card, EndCard, FPS, Mascot, Page, Pointer, Rings, grey, ink, line, pink, ring, s, useSpring } from "./kit";
import T from "./scan.json";

// Barcode scanning: no more typing calories. Point, scan, logged.

const clamp = { extrapolateLeft: "clamp", extrapolateRight: "clamp" } as const;

const Barcode: React.FC<{ w: number; h: number }> = ({ w, h }) => {
  const bars = "1101001011101100101011011001010011011101001011001101".split("");
  return (
    <div style={{ display: "flex", width: w, height: h, gap: 0, background: "#fff", padding: "10px 16px", boxSizing: "border-box", borderRadius: 10 }}>
      {bars.map((b, i) => <div key={i} style={{ flex: 1, background: b === "1" ? ink : "transparent" }} />)}
    </div>
  );
};

const Camera: React.FC = () => {
  const frame = useCurrentFrame();
  const t = frame / FPS;
  const C = T.cam;
  if (t < C.at || t > C.out + 0.2) return null;
  const open = interpolate(t, [C.at, C.at + 0.3], [0, 1], { ...clamp, easing: Easing.out(Easing.cubic) });
  const slide = interpolate(t, [C.product, C.lock - 0.2], [1, 0], { ...clamp, easing: Easing.out(Easing.cubic) });
  const lock = interpolate(t, [C.lock, C.lock + 0.15], [0, 1], clamp);
  const scanY = 200 + ((t * 1.6) % 1) * 600;
  const shake = t > C.lock && t < C.lock + 0.2 ? Math.sin(t * 120) * 6 : 0;
  const gone = interpolate(t, [C.out, C.out + 0.2], [0, 1], clamp);
  return (
    <div style={{ position: "absolute", top: 300, width: 900, height: 1100, borderRadius: 60, overflow: "hidden", background: "linear-gradient(180deg,#3A3F48,#1E2128)",
                  transform: `scale(${0.9 + 0.1 * open}) translateX(${shake}px)`, opacity: open * (1 - gone), boxShadow: "0 30px 80px rgba(0,0,0,0.25)" }}>
      {/* the yogurt pot coming into frame */}
      <div style={{ position: "absolute", left: 230, top: 260 + slide * 700, width: 440, height: 560, borderRadius: "40px 40px 90px 90px", background: "linear-gradient(90deg,#F4F4F0,#FFFFFF 40%,#E6E6E0)",
                    display: "flex", flexDirection: "column", alignItems: "center", paddingTop: 50, boxSizing: "border-box", transform: `rotate(${slide * 12}deg)` }}>
        <div style={{ fontSize: 46, fontWeight: 900, color: "#2B5BA8", letterSpacing: 2 }}>GREEK</div>
        <div style={{ fontSize: 34, fontWeight: 700, color: "#2B5BA8" }}>yogurt 0%</div>
        <div style={{ fontSize: 120, margin: "10px 0" }}>🥛</div>
        <Barcode w={300} h={130} />
      </div>
      {/* corner brackets */}
      {[[0, 0], [1, 0], [0, 1], [1, 1]].map(([x, y], i) => (
        <div key={i} style={{ position: "absolute", left: x ? undefined : 190 - lock * 20, right: x ? 190 - lock * 20 : undefined, top: y ? undefined : 560 - lock * 20, bottom: y ? 300 - lock * 20 : undefined, width: 90, height: 90,
                              borderColor: lock > 0.5 ? "#6FE0C8" : "#fff", borderStyle: "solid", borderWidth: `${y ? 0 : 10}px ${x ? 10 : 0}px ${y ? 10 : 0}px ${x ? 0 : 10}px`, borderRadius: 18 }} />
      ))}
      {lock < 0.5 && <div style={{ position: "absolute", left: 140, right: 140, top: scanY, height: 6, background: pink, boxShadow: `0 0 30px ${pink}` }} />}
      <div style={{ position: "absolute", bottom: 60, left: 0, right: 0, textAlign: "center", color: "#fff", fontSize: 38, fontWeight: 600 }}>{lock > 0.5 ? "✓ Found it" : "Point at a barcode"}</div>
    </div>
  );
};

const Product: React.FC = () => {
  const frame = useCurrentFrame();
  const t = frame / FPS;
  const btn = useSpringSafe(T.card.at + 0.5);
  if (t < T.card.at || t > T.rings.at) return null;
  const press = 1 - 0.06 * Math.max(0, 1 - Math.abs(t - T.card.add - 0.08) * 10);
  return (
    <Card at={T.card.at} top={420} style={{ padding: "44px 48px" }}>
      <div style={{ display: "flex", alignItems: "center", gap: 26 }}>
        <div style={{ width: 150, height: 150, borderRadius: 36, background: "#EEF3FB", display: "flex", alignItems: "center", justifyContent: "center", fontSize: 90 }}>🥛</div>
        <div><div style={{ fontSize: 50, fontWeight: 800 }}>Greek yogurt 0%</div><div style={{ fontSize: 34, color: grey, marginTop: 6 }}>170 g pot · from the barcode</div></div>
      </div>
      <div style={{ display: "grid", gridTemplateColumns: "repeat(4,1fr)", gap: 16, marginTop: 36 }}>
        {[["100", "kcal", ring.kcal], ["17 g", "protein", ring.protein], ["6 g", "carbs", ring.carbs], ["0 g", "fat", ring.fat]].map(([v, k, c]) => (
          <div key={k} style={{ background: "#F7F7F9", borderRadius: 26, padding: "22px 0", textAlign: "center" }}>
            <div style={{ fontSize: 44, fontWeight: 800, color: c }}>{v}</div><div style={{ fontSize: 30, color: grey, fontWeight: 600 }}>{k}</div>
          </div>
        ))}
      </div>
      <div style={{ marginTop: 34, height: 108, borderRadius: 54, background: ink, color: "#fff", fontSize: 42, fontWeight: 700, display: "flex", alignItems: "center", justifyContent: "center", transform: `scale(${btn * press})` }}>
        {t > T.card.add + 0.1 ? "✓ Added to breakfast" : "Add to breakfast"}
      </div>
    </Card>
  );
};
// a spring that is safe to call before an early return (hooks must keep their order)
function useSpringSafe(at: number) { return useSpring(at, 13); }

const Rapid: React.FC = () => {
  const frame = useCurrentFrame();
  const t = frame / FPS;
  if (t < T.rapid[0] || t > T.words[0]) return null;
  const items: [string, string, string][] = [["🍫", "Protein bar", "210 kcal"], ["🥛", "Oat milk, 250 ml", "115 kcal"], ["🥣", "Granola, 45 g", "198 kcal"]];
  return (
    <AbsoluteFill style={{ alignItems: "center" }}>
      {items.map(([e, n, k], i) => {
        const at = T.rapid[i];
        const flash = interpolate(t, [at, at + 0.08, at + 0.3], [0, 0.8, 0], clamp);
        const p = interpolate(t, [at + 0.1, at + 0.4], [0, 1], { ...clamp, easing: Easing.out(Easing.back(1.4)) });
        return (
          <React.Fragment key={n}>
            <div style={{ position: "absolute", inset: 0, background: "#fff", opacity: flash, zIndex: 5 }} />
            <div style={{ position: "absolute", top: 420 + i * 230, width: 900, background: "#fff", border: `2px solid ${line}`, borderRadius: 40, padding: "30px 40px", display: "flex", alignItems: "center", gap: 24,
                          boxShadow: "0 16px 40px rgba(0,0,0,0.08)", opacity: p, transform: `translateY(${(1 - p) * 60}px)` }}>
              <span style={{ fontSize: 70 }}>{e}</span><span style={{ flex: 1, fontSize: 42, fontWeight: 700 }}>{n}</span><span style={{ fontSize: 36, color: grey }}>{k}</span>
              <span style={{ fontSize: 40, color: ring.protein, fontWeight: 800 }}>✓</span>
            </div>
          </React.Fragment>
        );
      })}
      <div style={{ position: "absolute", top: 1180 }}><Mascot clip="celebrate" at={T.rapid[2] + 0.2} size={620} /></div>
    </AbsoluteFill>
  );
};

export const scanLength = s(T.dur);

export const Scan: React.FC = () => {
  const frame = useCurrentFrame();
  const t = frame / FPS;
  const strike = interpolate(t, [T.head.strike, T.head.strike + 0.3], [0, 1], clamp);
  const head = useSpring(T.head.at, 15);
  const headOut = interpolate(t, [T.head.out, T.head.out + 0.2], [0, 1], clamp);
  return (
    <AbsoluteFill>
      <Page>
        {t < T.head.out + 0.25 && (
          <div style={{ position: "absolute", top: 760, width: "100%", textAlign: "center", fontSize: 112, fontWeight: 800, letterSpacing: -3, lineHeight: 1.1, opacity: head * (1 - headOut), transform: `translateY(${(1 - head) * 40}px)` }}>
            No more<br /><span style={{ position: "relative", display: "inline-block" }}>typing calories
              <span style={{ position: "absolute", left: -10, top: "52%", height: 14, width: `${strike * 104}%`, background: pink, borderRadius: 7 }} /></span>
          </div>
        )}
        <Camera />
        <Product />
        {t >= T.rings.at && t < T.rings.out && (
          <Card at={T.rings.at} top={560} style={{ display: "flex", alignItems: "center", gap: 40, padding: "44px 50px" }}>
            <Rings at={T.rings.at + 0.1} size={330} values={[0.3, 0.42, 0.18, 0.2]} />
            <div><div style={{ fontSize: 34, color: grey, fontWeight: 700 }}>Today</div>
              <div style={{ fontSize: 96, fontWeight: 800, letterSpacing: -2 }}>{Math.round(interpolate(t, [T.rings.at + 0.1, T.rings.at + 1], [520, 620], clamp))}</div>
              <div style={{ fontSize: 34, color: grey, fontWeight: 600 }}>kcal · +17 g protein</div></div>
          </Card>
        )}
        <Rapid />
        {t >= T.words[0] && (
          <AbsoluteFill style={{ background: "#fff", alignItems: "center", justifyContent: "center", gap: 10 }}>
            {["Point.", "Scan.", "Logged."].map((w, i) => {
              const p = interpolate(t, [T.words[i], T.words[i] + 0.25], [0, 1], { ...clamp, easing: Easing.out(Easing.back(1.5)) });
              return <div key={w} style={{ fontSize: 170, fontWeight: 800, letterSpacing: -5, lineHeight: 1.05, opacity: p, transform: `scale(${0.7 + 0.3 * p})`, color: i === 2 ? pink : ink }}>{w}</div>;
            })}
          </AbsoluteFill>
        )}
      </Page>
      <Pointer show={[T.card.add - 0.7, T.card.add + 0.5]} stops={[[T.card.add - 0.7, 900, 1500], [T.card.add, 540, 1090, true]]} />
      <Sequence from={s(T.end)}><EndCard at={0} /></Sequence>
    </AbsoluteFill>
  );
};
