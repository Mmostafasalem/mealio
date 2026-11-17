import React from "react";
import { AbsoluteFill, Easing, Sequence, interpolate, useCurrentFrame } from "remotion";
import { Card, EndCard, FPS, Headline, Mascot, Page, Pointer, grey, ink, line, pink, ring, s, soft, useSpring } from "./kit";
import T from "./train.json";

// The Train tab: pick where, how long and what, and the session builds itself.

const clamp = { extrapolateLeft: "clamp", extrapolateRight: "clamp" } as const;

const Seg: React.FC<{ items: string[]; on: number }> = ({ items, on }) => (
  <div style={{ display: "flex", gap: 14, marginTop: 16 }}>
    {items.map((x, i) => (
      <div key={x} style={{ flex: 1, textAlign: "center", padding: "22px 0", borderRadius: 28, fontSize: 36, fontWeight: 700, background: i === on ? "#FDE7EE" : soft, border: `3px solid ${i === on ? pink : "transparent"}`, color: i === on ? "#B3365A" : ink }}>{x}</div>
    ))}
  </div>
);

const Builder: React.FC = () => {
  const frame = useCurrentFrame();
  const t = frame / FPS;
  const B = T.builder;
  const minutes = Math.round(interpolate(t, B.slide, [20, 30], { ...clamp, easing: Easing.inOut(Easing.cubic) }));
  const press = 1 - 0.06 * Math.max(0, 1 - Math.abs(t - B.build - 0.08) * 10);
  if (t < B.at || t > T.think.at) return null;
  return (
    <Card at={B.at} top={330} style={{ padding: "44px 48px" }}>
      <div style={{ fontSize: 56, fontWeight: 800 }}>Build a workout</div>
      <div style={{ fontSize: 34, color: grey, fontWeight: 700, marginTop: 30 }}>WHERE</div>
      <Seg items={["🏋️ Gym", "🏠 Home", "🏃 Cardio", "🧘 Mobility"].map(x => x.split(" ")[1])} on={t >= B.home ? 1 : 0} />
      <div style={{ fontSize: 34, color: grey, fontWeight: 700, marginTop: 40 }}>LENGTH</div>
      <div style={{ textAlign: "center", fontSize: 96, fontWeight: 800, marginTop: 10, fontVariantNumeric: "tabular-nums" }}>{minutes}<span style={{ fontSize: 44, color: grey }}> min</span></div>
      <div style={{ position: "relative", height: 90, overflow: "hidden" }}>
        <div style={{ position: "absolute", left: 420 - (minutes - 10) * 30, display: "flex", gap: 0 }}>
          {Array.from({ length: 51 }).map((_, i) => <div key={i} style={{ width: 30, display: "flex", justifyContent: "center" }}><div style={{ width: 4, height: i % 5 === 0 ? 70 : 40, background: i % 5 === 0 ? ink : "#C7C7CC", borderRadius: 2 }} /></div>)}
        </div>
        <div style={{ position: "absolute", left: 420 + 13, top: 0, width: 6, height: 90, background: pink, borderRadius: 3 }} />
      </div>
      <div style={{ fontSize: 34, color: grey, fontWeight: 700, marginTop: 34 }}>FOCUS</div>
      <Seg items={["Full body", "Upper", "Lower", "Core"]} on={t >= B.focus ? 0 : -1} />
      <div style={{ marginTop: 44, height: 112, borderRadius: 56, background: ink, color: "#fff", fontSize: 44, fontWeight: 700, display: "flex", alignItems: "center", justifyContent: "center", transform: `scale(${press})` }}>Build my workout</div>
    </Card>
  );
};

const EXERCISES: [string, string, string][] = [["Squats", "3 × 12", "Quads, glutes"], ["Push-ups", "3 × 10", "Chest, triceps"], ["Glute bridge", "3 × 15", "Glutes"], ["Plank", "3 × 40 s", "Core"], ["Jumping jacks", "3 × 30 s", "Cardio"]];

const Session: React.FC = () => {
  const frame = useCurrentFrame();
  const t = frame / FPS;
  const S = T.session;
  const btn = useSpring(S.at + 1.2, 13);
  if (t < S.at || t > T.timer.at) return null;
  const press = 1 - 0.06 * Math.max(0, 1 - Math.abs(t - S.start - 0.08) * 10);
  return (
    <>
      <Card at={S.at} top={300} style={{ padding: "40px 46px" }}>
        <div style={{ fontSize: 34, color: grey, fontWeight: 700 }}>Home · 30 min · Full body</div>
        <div style={{ fontSize: 60, fontWeight: 800, marginBottom: 16 }}>Today's session</div>
        {EXERCISES.map(([n, k, m], i) => {
          const p = interpolate(t, [S.at + 0.25 + i * 0.13, S.at + 0.5 + i * 0.13], [0, 1], clamp);
          return (
            <div key={n} style={{ display: "flex", alignItems: "center", gap: 22, padding: "22px 0", borderTop: `2px solid ${line}`, opacity: p, transform: `translateX(${(1 - p) * 40}px)` }}>
              <div style={{ width: 70, height: 70, borderRadius: 20, background: [ring.kcal, ring.protein, ring.carbs, ring.fat, "#F5B942"][i] + "33", display: "flex", alignItems: "center", justifyContent: "center", fontSize: 34, fontWeight: 800, color: [ring.kcal, ring.protein, ring.carbs, ring.fat, "#C98A12"][i] }}>{i + 1}</div>
              <div style={{ flex: 1 }}><div style={{ fontSize: 42, fontWeight: 700 }}>{n}</div><div style={{ fontSize: 30, color: grey }}>{m}</div></div>
              <div style={{ fontSize: 38, fontWeight: 700, color: grey }}>{k}</div>
            </div>
          );
        })}
        <div style={{ marginTop: 26, height: 112, borderRadius: 56, background: pink, color: "#fff", fontSize: 44, fontWeight: 800, display: "flex", alignItems: "center", justifyContent: "center", transform: `scale(${btn * press})` }}>▶ Start workout</div>
      </Card>
      <div style={{ position: "absolute", top: 1430 }}><Mascot clip="help" at={S.at + 0.3} size={480} /></div>
    </>
  );
};

const Timer: React.FC = () => {
  const frame = useCurrentFrame();
  const t = frame / FPS;
  const M = T.timer;
  if (t < M.at || t > M.out + 0.2) return null;
  const p = interpolate(t, [M.at + 0.3, M.out - 0.4], [0, 1], clamp);
  const secs = Math.max(0, Math.ceil(40 - p * 40));
  const done = t > M.out - 0.4;
  const r = 300, c = 2 * Math.PI * r;
  return (
    <AbsoluteFill style={{ alignItems: "center" }}>
      <div style={{ position: "absolute", top: 220, fontSize: 40, color: grey, fontWeight: 700 }}>Set 1 of 3</div>
      <div style={{ position: "absolute", top: 280, fontSize: 92, fontWeight: 800 }}>Plank</div>
      <svg width={700} height={700} viewBox="0 0 700 700" style={{ position: "absolute", top: 450, transform: "rotate(-90deg)" }}>
        <circle cx={350} cy={350} r={r} fill="none" stroke={ring.protein} strokeOpacity={0.15} strokeWidth={36} />
        <circle cx={350} cy={350} r={r} fill="none" stroke={ring.protein} strokeWidth={36} strokeLinecap="round" strokeDasharray={`${c * (1 - p)} ${c}`} />
      </svg>
      <div style={{ position: "absolute", top: 700, fontSize: 200, fontWeight: 800, fontVariantNumeric: "tabular-nums", letterSpacing: -6 }}>{done ? "✓" : `0:${String(secs).padStart(2, "0")}`}</div>
      <div style={{ position: "absolute", top: 1240 }}><Mascot clip={done ? "celebrate" : "idle"} at={done ? M.out - 0.4 : M.at} size={560} /></div>
    </AbsoluteFill>
  );
};

export const trainLength = s(T.dur);

export const Train: React.FC = () => {
  const frame = useCurrentFrame();
  const t = frame / FPS;
  return (
    <AbsoluteFill>
      <Page>
        {t < T.head.out + 0.25 && <Headline text="A workout in 5 seconds" at={T.head.at} top={780} size={120} mark={["5", "seconds"]} out={T.head.out} />}
        <Builder />
        {t >= T.think.at && t < T.think.out && (
          <AbsoluteFill style={{ alignItems: "center", justifyContent: "center" }}>
            <Mascot clip="thinking" at={T.think.at} size={640} />
            <div style={{ fontSize: 44, fontWeight: 700, color: grey }}>Building your session{".".repeat(1 + (Math.floor(t * 4) % 3))}</div>
          </AbsoluteFill>
        )}
        <Session />
        <Timer />
        {t >= T.line.at && <><Headline text="Your coach fits in your pocket." at={T.line.at} top={720} size={112} mark={["pocket"]} /></>}
      </Page>
      <Pointer show={[T.builder.home - 0.6, T.session.start + 0.3]} stops={[[T.builder.home - 0.6, 900, 1500], [T.builder.home, 420, 600, true], [T.builder.slide[0], 620, 960],
        [T.builder.slide[1], 340, 960], [T.builder.focus, 220, 1210, true], [T.builder.build, 540, 1420, true], [T.session.start - 0.5, 700, 1380], [T.session.start, 540, 1310, true]]} />
      <Sequence from={s(T.end)}><EndCard at={0} /></Sequence>
    </AbsoluteFill>
  );
};
