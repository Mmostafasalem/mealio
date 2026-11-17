import React from "react";
import { AbsoluteFill, Img, Sequence, interpolate, staticFile, useCurrentFrame } from "remotion";
import { AskBar, Card, EndCard, FPS, Headline, Mascot, Page, Pointer, Rings, grey, ink, line, pink, ring, s, soft, useSpring } from "./kit";
import T from "./voice.json";

// After reference 3: "create anything with just your finger" becomes "log anything with just your voice".

const clamp = { extrapolateLeft: "clamp", extrapolateRight: "clamp" } as const;

const MenuSheet: React.FC = () => {
  const frame = useCurrentFrame();
  const t = frame / FPS;
  if (t < T.menu || t > T.pick + 0.25) return null;
  const p = interpolate(t, [T.menu, T.menu + 0.18], [0, 1], clamp);
  const items: [string, string][] = [["🍽️", "Log food"], ["🎙️", "Speak a command"], ["🔎", "Scan a barcode"], ["🏋️", "Build a workout"]];
  return (
    <div style={{ position: "absolute", top: 400, left: 70, width: 620, background: "#fff", borderRadius: 40, border: `2px solid ${line}`, boxShadow: "0 30px 70px rgba(0,0,0,0.12)", padding: 14,
                  opacity: p, transform: `translateY(${(1 - p) * 30}px)` }}>
      {items.map(([e, n], i) => (
        <div key={n} style={{ display: "flex", gap: 22, alignItems: "center", padding: "24px 26px", borderRadius: 26, fontSize: 44, fontWeight: 600,
                              background: i === 1 && t > T.pick - 0.05 ? soft : "transparent" }}><span style={{ fontSize: 46 }}>{e}</span>{n}</div>
      ))}
    </div>
  );
};

/** The listening orb with live words. */
const Listen: React.FC<{ at: number; say: number; text: string; wps: number; until: number; top?: number }> = ({ at, say, text, wps, until, top = 360 }) => {
  const frame = useCurrentFrame();
  const t = frame / FPS;
  const orb = useSpring(at, 11);
  if (t < at || t > until) return null;
  const words = text.split(" ");
  const n = Math.max(0, Math.min(words.length, Math.floor((t - say) * wps) + 1));
  const talking = t > say && t < say + words.length / wps;
  return (
    <div style={{ position: "absolute", top, left: 0, right: 0, display: "flex", flexDirection: "column", alignItems: "center", gap: 50 }}>
      <div style={{ width: 300, height: 300, position: "relative", transform: `scale(${orb})` }}>
        {[0, 1, 2].map(k => {
          const q = ((t * 1.2 + k / 3) % 1);
          return <div key={k} style={{ position: "absolute", inset: 0, borderRadius: "50%", background: pink, opacity: talking ? (1 - q) * 0.35 : 0.08, transform: `scale(${1 + q * (talking ? 0.8 : 0.2)})` }} />;
        })}
        <div style={{ position: "absolute", inset: 0, borderRadius: "50%", background: pink, display: "flex", alignItems: "center", justifyContent: "center", boxShadow: "0 20px 50px rgba(232,105,138,0.4)" }}>
          <svg width={130} height={130} viewBox="0 0 24 24" fill="none" stroke="#fff" strokeWidth={2} strokeLinecap="round"><rect x={9} y={3} width={6} height={11} rx={3} fill="#fff" /><path d="M5.5 11.5a6.5 6.5 0 0 0 13 0M12 18v3" /></svg>
        </div>
      </div>
      <div style={{ fontSize: 62, fontWeight: 700, textAlign: "center", padding: "0 80px", lineHeight: 1.2, minHeight: 150 }}>
        {t > say && words.slice(0, n).map((w, i) => {
          const p = interpolate(t, [say + i / wps, say + i / wps + 0.18], [0, 1], clamp);
          return <span key={i} style={{ opacity: p, color: i === n - 1 && talking ? pink : ink }}>{w} </span>;
        })}
      </div>
    </div>
  );
};

const Review: React.FC = () => {
  const frame = useCurrentFrame();
  const t = frame / FPS;
  if (t < T.one.card || t > T.rings) return null;
  const left = Math.max(0, Math.ceil(T.one.saved - t));
  const saved = t >= T.one.saved;
  return (
    <Card at={T.one.card} top={1080} style={{ padding: "34px 40px" }}>
      <div style={{ display: "flex", justifyContent: "space-between", alignItems: "center" }}>
        <div style={{ fontSize: 40, fontWeight: 800 }}>Log to Breakfast</div>
        <div style={{ fontSize: 34, fontWeight: 700, color: saved ? ring.protein : grey }}>{saved ? "✓ Logged" : `Saving in ${left}`}</div>
      </div>
      {[["🥚", "Egg, whole · 2", "156 kcal"], ["🍌", "Banana · 1 medium", "105 kcal"]].map(([e, n, k], i) => (
        <div key={n} style={{ display: "flex", alignItems: "center", gap: 20, padding: "20px 0", borderTop: `2px solid ${line}`, marginTop: i ? 0 : 20 }}>
          <span style={{ fontSize: 50 }}>{e}</span><span style={{ flex: 1, fontSize: 40, fontWeight: 600 }}>{n}</span><span style={{ fontSize: 36, color: grey }}>{k}</span>
        </div>
      ))}
    </Card>
  );
};

const Today: React.FC = () => {
  const frame = useCurrentFrame();
  const t = frame / FPS;
  if (t < T.rings || t > T.head.at) return null;
  const kcal = Math.round(interpolate(t, [T.rings + 0.2, T.rings + 1.3], [0, 261], clamp));
  return (
    <AbsoluteFill style={{ alignItems: "center" }}>
      <Card at={T.rings} top={420} style={{ display: "flex", alignItems: "center", gap: 40, padding: "44px 50px" }}>
        <Rings at={T.rings + 0.2} size={330} values={[0.13, 0.12, 0.1, 0.16]} />
        <div>
          <div style={{ fontSize: 34, color: grey, fontWeight: 700 }}>Today</div>
          <div style={{ fontSize: 96, fontWeight: 800, fontVariantNumeric: "tabular-nums", letterSpacing: -2 }}>{kcal}</div>
          <div style={{ fontSize: 34, color: grey, fontWeight: 600 }}>kcal logged · breakfast</div>
        </div>
      </Card>
      <div style={{ position: "absolute", top: 1000 }}><Mascot clip="happy" at={T.rings + 0.2} size={560} /></div>
    </AbsoluteFill>
  );
};

const Result: React.FC<{ at: number; until: number; children: React.ReactNode }> = ({ at, until, children }) => {
  const frame = useCurrentFrame();
  const t = frame / FPS;
  if (t < at || t > until) return null;
  return <Card at={at} top={1080} style={{ padding: "34px 40px" }}>{children}</Card>;
};

export const voiceLength = s(T.dur);

export const Voice: React.FC = () => {
  const frame = useCurrentFrame();
  const t = frame / FPS;
  return (
    <AbsoluteFill>
      <Page>
        {t < T.one.at && <div style={{ position: "absolute", top: 860, width: "100%", display: "flex", justifyContent: "center" }}><AskBar text="" at={99} top={0} placeholder="Ask Nourlo" /></div>}
        <MenuSheet />
        <Listen at={T.one.at} say={T.one.say} text={T.one.text} wps={T.one.wps} until={T.rings} />
        <Review />
        <Today />
        {t >= T.head.at && t < T.two.at && <Headline text="Log anything with just your voice" at={T.head.at} top={760} size={110} hand={{ voice: pink }} out={T.head.out} />}
        <Listen at={T.two.at} say={T.two.say} text={T.two.text} wps={T.two.wps} until={T.three.at} />
        <Result at={T.two.card} until={T.three.at}>
          <div style={{ display: "flex", alignItems: "center", gap: 28 }}>
            <span style={{ fontSize: 90 }}>🏃</span>
            <div style={{ flex: 1 }}><div style={{ fontSize: 44, fontWeight: 800 }}>Run · 5 km</div><div style={{ fontSize: 34, color: grey, marginTop: 6 }}>about 30 min · 320 kcal</div></div>
            <div style={{ fontSize: 34, fontWeight: 700, color: ring.protein }}>✓ Saved</div>
          </div>
        </Result>
        {t >= T.two.card + 0.2 && t < T.three.at && <div style={{ position: "absolute", top: 1360 }}><Mascot clip="celebrate" at={T.two.card + 0.2} size={500} /></div>}
        <Listen at={T.three.at} say={T.three.say} text={T.three.text} wps={T.three.wps} until={T.final.at} />
        <Result at={T.three.card} until={T.final.at}>
          <div style={{ fontSize: 40, fontWeight: 800, marginBottom: 16 }}>Added to your cart</div>
          {[["🥛", "Milk · 1 L", "€1.09"], ["🥚", "Eggs · 10", "€2.39"]].map(([e, n, p]) => (
            <div key={n} style={{ display: "flex", alignItems: "center", gap: 20, padding: "18px 0", borderTop: `2px solid ${line}` }}>
              <span style={{ fontSize: 50 }}>{e}</span><span style={{ flex: 1, fontSize: 40, fontWeight: 600 }}>{n}</span><span style={{ fontSize: 36, color: grey }}>{p}</span>
            </div>
          ))}
        </Result>
        {t >= T.final.at && (
          <>
            <Headline text="Just say it." at={T.final.at} top={700} size={130} />
            <div style={{ position: "absolute", top: 1000 }}><Mascot clip="hello" at={T.final.at + 0.1} size={600} /></div>
          </>
        )}
      </Page>
      <Pointer show={[0.2, T.pick + 0.3]} stops={[[0.2, 700, 1200], [T.plus, 120, 900, true], [T.pick, 330, 600, true]]} />
      <Sequence from={s(T.end)}><EndCard at={0} /></Sequence>
      <span style={{ display: "none" }}><Img src={staticFile("icon.png")} /></span>
    </AbsoluteFill>
  );
};
