import React from "react";
import { AbsoluteFill, Sequence, interpolate, useCurrentFrame } from "remotion";
import { Card, EndCard, FPS, Headline, Mascot, Page, Pointer, Rings, grey, ink, line, pink, ring, s, soft, useSpring } from "./kit";
import T from "./goals.json";

// After reference 4: "create from scratch with templates" becomes "start from your goal".

const clamp = { extrapolateLeft: "clamp", extrapolateRight: "clamp" } as const;
const TILES: [string, string, string][] = [
  ["⚖️", "Lose 5 kg", "#FDE2E8"], ["🏃", "First 5k", "#DDF3EC"], ["💶", "Spend less", "#FFF1CC"], ["💪", "Build muscle", "#E3ECFD"],
  ["🥗", "Eat cleaner", "#E7F6DA"], ["🌱", "Go veggie", "#EAF7E5"], ["⚡", "More energy", "#F1E8FD"], ["🍳", "Cook more", "#FDEBDD"],
];

const Tile: React.FC<{ tile: [string, string, string]; style?: React.CSSProperties }> = ({ tile, style }) => (
  <div style={{ width: 230, height: 230, borderRadius: 52, background: tile[2], display: "flex", flexDirection: "column", alignItems: "center", justifyContent: "center", gap: 8,
                boxShadow: "0 18px 40px rgba(0,0,0,0.10)", flexShrink: 0, ...style }}>
    <div style={{ fontSize: 96 }}>{tile[0]}</div><div style={{ fontSize: 32, fontWeight: 700, color: ink }}>{tile[1]}</div>
  </div>
);

/** Two rows of goal tiles drifting past, slightly turned, like the reference's template carousel. */
const Carousel: React.FC<{ at: number; out: number; picked?: number; pickAt?: number }> = ({ at, out, picked, pickAt = 99 }) => {
  const frame = useCurrentFrame();
  const t = frame / FPS;
  const gone = interpolate(t, [out - 0.35, out], [0, 1], clamp);
  const row = (y: number, dir: number, offset: number) => (
    <div style={{ position: "absolute", top: y, left: 0, display: "flex", gap: 40, transform: `translateX(${-300 + dir * ((t - at) * 120) + offset}px)`, opacity: 1 - gone }}>
      {[...TILES, ...TILES].map((tile, i) => {
        const appear = interpolate(t, [at + i * 0.04, at + i * 0.04 + 0.35], [0, 1], clamp);
        const isPick = picked !== undefined && i === picked;
        const lift = isPick ? interpolate(t, [pickAt, pickAt + 0.3], [0, 1], clamp) : 0;
        return <Tile key={i} tile={tile} style={{ transform: `rotate(${Math.sin(i * 1.7) * 9 * (1 - lift)}deg) scale(${appear * (1 + lift * 0.25)})`, outline: isPick && lift > 0 ? `6px solid ${pink}` : undefined }} />;
      })}
    </div>
  );
  return <>{row(250, 1, -600)}{row(1330, -1, 0)}</>;
};

const Typed: React.FC<{ text: string; at: number; cps?: number }> = ({ text, at, cps = 20 }) => {
  const frame = useCurrentFrame();
  const t = frame / FPS;
  const n = Math.max(0, Math.min(text.length, Math.floor((t - at) * cps)));
  const typing = t > at && n < text.length;
  return <span>{text.slice(0, n) || <span style={{ color: "#C7C7CC" }}>Type your answer</span>}{(typing || (t > at && Math.floor(t * 2.2) % 2 === 0 && t < at + text.length / cps + 0.8)) && <span style={{ display: "inline-block", width: 3, height: 44, background: ink, marginLeft: 3, verticalAlign: "-6px" }} />}</span>;
};

const Form: React.FC = () => {
  const frame = useCurrentFrame();
  const t = frame / FPS;
  const F = T.form;
  const q = (at: number) => interpolate(t, [at, at + 0.3], [0, 1], clamp);
  const chipsOn = ["Gym", "Home", "Running", "Yoga"].map((c, i) => i === 1 ? t >= F.chips[0] : i === 2 ? t >= F.chips[1] : false);
  const press = 1 - 0.06 * Math.max(0, 1 - Math.abs(t - F.next - 0.08) * 10);
  return (
    <Card at={F.at} top={330} style={{ padding: "44px 48px" }}>
      {[[F.q1, "What's your goal?", F.a1], [F.q2, "Weekly food budget?", F.a2]].map(([at, qq, a]) => (
        <div key={qq as string} style={{ marginBottom: 40, opacity: q(at as number) }}>
          <div style={{ fontSize: 40, fontWeight: 700 }}>{qq}</div>
          <div style={{ marginTop: 16, border: `2px solid ${line}`, borderRadius: 26, padding: "22px 28px", fontSize: 42 }}><Typed text={a as string} at={(at as number) + 0.3} /></div>
        </div>
      ))}
      <div style={{ opacity: q(F.q3) }}>
        <div style={{ fontSize: 40, fontWeight: 700 }}>How do you like to train?</div>
        <div style={{ display: "flex", gap: 16, marginTop: 18, flexWrap: "wrap" }}>
          {["🏋️ Gym", "🏠 Home", "🏃 Running", "🧘 Yoga"].map((c, i) => (
            <div key={c} style={{ padding: "18px 30px", borderRadius: 40, fontSize: 38, fontWeight: 600, background: chipsOn[i] ? "#FDE7EE" : soft, border: `3px solid ${chipsOn[i] ? pink : "transparent"}`, color: chipsOn[i] ? "#B3365A" : ink }}>{c}</div>
          ))}
        </div>
      </div>
      <div style={{ marginTop: 44, height: 108, borderRadius: 54, background: ink, color: "#fff", fontSize: 42, fontWeight: 700, display: "flex", alignItems: "center", justifyContent: "center", opacity: q(F.q3 + 0.4), transform: `scale(${press})` }}>Continue</div>
    </Card>
  );
};

const STYLES: [string, string][] = [["🍽️", "Balanced"], ["🍗", "High-protein"], ["🫒", "Mediterranean"], ["🥦", "Vegetarian"]];
const Styles: React.FC = () => {
  const frame = useCurrentFrame();
  const t = frame / FPS;
  const S = T.styles;
  return (
    <AbsoluteFill style={{ alignItems: "center" }}>
      <Headline text="Pick a style" at={S.at} top={300} size={92} out={S.out - 0.2} />
      <div style={{ position: "absolute", top: 560, display: "grid", gridTemplateColumns: "1fr 1fr", gap: 30 }}>
        {STYLES.map(([e, n], i) => {
          const p = interpolate(t, [S.at + 0.15 + i * 0.08, S.at + 0.45 + i * 0.08], [0, 1], clamp);
          const on = i === 2 && t >= S.pick;
          return (
            <div key={n} style={{ width: 420, height: 420, borderRadius: 50, background: on ? "#FDE7EE" : soft, border: `6px solid ${on ? pink : "transparent"}`, boxSizing: "border-box",
                                  display: "flex", flexDirection: "column", alignItems: "center", justifyContent: "center", gap: 18, opacity: p, transform: `scale(${(0.85 + 0.15 * p) * (on ? 1.03 : 1)})` }}>
              <div style={{ fontSize: 150 }}>{e}</div><div style={{ fontSize: 42, fontWeight: 700 }}>{n}</div>
            </div>
          );
        })}
      </div>
      <div style={{ position: "absolute", top: 1500 }}><Mascot clip="thinking" at={S.at} size={360} /></div>
    </AbsoluteFill>
  );
};

/** Full-frame result cards, one after another, each on its own colour. */
const Hero: React.FC<{ i: number }> = ({ i }) => {
  const frame = useCurrentFrame();
  const t = frame / FPS;
  const at = T.heroes[i], next = T.heroes[i + 1] ?? T.grid.at;
  if (t < at || t >= next) return null;
  const bgs = ["#FDE2E8", "#DDF3EC", "#E3ECFD"];
  const zoom = interpolate(t, [at, next], [1.04, 1], clamp);
  return (
    <AbsoluteFill style={{ background: bgs[i], alignItems: "center", justifyContent: "center", transform: `scale(${zoom})` }}>
      {i === 0 && <Card at={at} width={880} style={{ textAlign: "center", padding: 60 }}>
        <div style={{ display: "flex", justifyContent: "center" }}><Rings at={at + 0.1} size={420} values={[0.78, 0.9, 0.64, 0.7]} /></div>
        <div style={{ fontSize: 40, color: grey, fontWeight: 700, marginTop: 30 }}>Your daily target</div>
        <div style={{ fontSize: 110, fontWeight: 800, letterSpacing: -3 }}>1 850 kcal</div>
        <div style={{ fontSize: 36, color: grey }}>−0.5 kg a week · 130 g protein</div>
      </Card>}
      {i === 1 && <Card at={at} width={880} style={{ padding: "50px 56px" }}>
        <div style={{ fontSize: 34, color: grey, fontWeight: 700 }}>Mediterranean · 7 days</div>
        <div style={{ fontSize: 66, fontWeight: 800, marginBottom: 20 }}>Meal plan · €46</div>
        {[["🫒", "Greek salad & feta", "430"], ["🐟", "Baked salmon, lemon potatoes", "610"], ["🍆", "Chickpea & aubergine stew", "520"], ["🥣", "Yogurt, honey & walnuts", "290"]].map(([e, n, k], j) => (
          <div key={n} style={{ display: "flex", gap: 20, alignItems: "center", padding: "20px 0", borderTop: `2px solid ${line}`, opacity: interpolate(t, [at + 0.2 + j * 0.12, at + 0.45 + j * 0.12], [0, 1], clamp) }}>
            <span style={{ fontSize: 54 }}>{e}</span><span style={{ flex: 1, fontSize: 38, fontWeight: 600 }}>{n}</span><span style={{ fontSize: 34, color: grey }}>{k}</span>
          </div>
        ))}
      </Card>}
      {i === 2 && <Card at={at} width={880} style={{ padding: "50px 56px" }}>
        <div style={{ fontSize: 34, color: grey, fontWeight: 700 }}>Home · running · 3× a week</div>
        <div style={{ fontSize: 66, fontWeight: 800, marginBottom: 20 }}>Today's workout</div>
        {[["Squats", "3 × 12"], ["Push-ups", "3 × 10"], ["Glute bridge", "3 × 15"], ["Easy run", "20 min"]].map(([n, k], j) => (
          <div key={n} style={{ display: "flex", gap: 20, alignItems: "center", padding: "22px 0", borderTop: `2px solid ${line}`, opacity: interpolate(t, [at + 0.2 + j * 0.12, at + 0.45 + j * 0.12], [0, 1], clamp) }}>
            <span style={{ width: 22, height: 22, borderRadius: 11, background: [ring.kcal, ring.protein, ring.carbs, ring.fat][j] }} />
            <span style={{ flex: 1, fontSize: 40, fontWeight: 700 }}>{n}</span><span style={{ fontSize: 36, color: grey }}>{k}</span>
          </div>
        ))}
      </Card>}
    </AbsoluteFill>
  );
};

const Collage: React.FC = () => {
  const frame = useCurrentFrame();
  const t = frame / FPS;
  if (t < T.grid.at || t > T.grid.out) return null;
  const cells: [string, string, string][] = [["#FDE2E8", "🎯", "1 850 kcal"], ["#DDF3EC", "🫒", "Meal plan"], ["#E3ECFD", "🏃", "Workout"], ["#FFF1CC", "💶", "€46 / week"],
    ["#F1E8FD", "🛒", "Shopping list"], ["#E7F6DA", "🥗", "Recipes"], ["#FDEBDD", "📈", "−0.5 kg / wk"], ["#FDE2E8", "⏰", "Reminders"], ["#DDF3EC", "🎙️", "Voice log"]];
  const pan = interpolate(t, [T.grid.at, T.grid.out], [80, -80], clamp);
  return (
    <AbsoluteFill style={{ background: "#fff", alignItems: "center", justifyContent: "center" }}>
      <div style={{ display: "grid", gridTemplateColumns: "repeat(3, 300px)", gap: 24, transform: `translateY(${pan}px)` }}>
        {cells.map(([bg, e, n], i) => {
          const p = interpolate(t, [T.grid.at + i * 0.05, T.grid.at + i * 0.05 + 0.3], [0, 1], clamp);
          return <div key={i} style={{ height: 380, borderRadius: 40, background: bg, display: "flex", flexDirection: "column", alignItems: "center", justifyContent: "center", gap: 14, opacity: p, transform: `scale(${0.8 + 0.2 * p})` }}>
            <div style={{ fontSize: 110 }}>{e}</div><div style={{ fontSize: 34, fontWeight: 700 }}>{n}</div></div>;
        })}
      </div>
    </AbsoluteFill>
  );
};

export const goalsLength = s(T.dur);

export const Goals: React.FC = () => {
  const frame = useCurrentFrame();
  const t = frame / FPS;
  return (
    <AbsoluteFill>
      <Page>
        {t < T.intro.out + 0.1 && <><Carousel at={0} out={T.intro.out} picked={9} pickAt={T.intro.pick} /><Headline text="Start from your goal" at={T.intro.head} top={760} size={118} out={T.intro.out - 0.2} /></>}
        {t >= T.form.at && t < T.styles.at && <Form />}
        {t >= T.styles.at && t < T.styles.out && <Styles />}
        {[0, 1, 2].map(i => <Hero key={i} i={i} />)}
        <Collage />
        {t >= T.outro.at && <><Carousel at={T.outro.at} out={T.end + 1} /><Headline text="Bring your goals to life with Nourlo" at={T.outro.at + 0.1} top={680} size={104} mark={["nourlo"]} /></>}
      </Page>
      <Pointer show={[T.form.q3 + 0.1, T.styles.pick + 0.3]} stops={[[T.form.q3 + 0.1, 900, 1500], [T.form.chips[0], 470, 1190, true], [T.form.chips[1], 760, 1190, true], [T.form.next, 540, 1400, true],
        [T.styles.pick - 0.4, 600, 1300], [T.styles.pick, 320, 1240, true]]} />
      <Sequence from={s(T.end)}><EndCard at={0} /></Sequence>
    </AbsoluteFill>
  );
};
