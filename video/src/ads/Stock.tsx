import React from "react";
import { AbsoluteFill, Easing, Sequence, interpolate, useCurrentFrame } from "remotion";
import { Card, EndCard, FPS, Headline, Mascot, Page, Pointer, grey, ink, line, pink, ring, s, soft } from "./kit";
import T from "./stock.json";

// My Stock: what's at home becomes tonight's dinner.

const clamp = { extrapolateLeft: "clamp", extrapolateRight: "clamp" } as const;
const ITEMS: [string, string, string][] = [["🥚", "Eggs", "6"], ["🍅", "Tomatoes", "3"], ["🧀", "Feta", "200 g"], ["🥬", "Spinach", "1 bag"], ["🍝", "Pasta", "500 g"], ["🧅", "Onion", "2"],
  ["🫑", "Pepper", "1"], ["🥛", "Milk", "1 L"], ["🍋", "Lemon", "1"]];

const Shelf: React.FC = () => {
  const frame = useCurrentFrame();
  const t = frame / FPS;
  const S = T.shelf;
  if (t < S.at || t > S.out + 0.2) return null;
  const press = 1 - 0.06 * Math.max(0, 1 - Math.abs(t - S.cook - 0.08) * 10);
  const gone = interpolate(t, [S.out, S.out + 0.2], [0, 1], clamp);
  return (
    <AbsoluteFill style={{ alignItems: "center", opacity: 1 - gone }}>
      <div style={{ position: "absolute", top: 230, fontSize: 70, fontWeight: 800 }}>My Stock</div>
      <div style={{ position: "absolute", top: 330, fontSize: 36, color: grey, fontWeight: 600 }}>9 things at home</div>
      <div style={{ position: "absolute", top: 440, display: "grid", gridTemplateColumns: "repeat(3, 290px)", gap: 22 }}>
        {ITEMS.map(([e, n, q], i) => {
          const p = interpolate(t, [S.at + 0.1 + i * 0.08, S.at + 0.4 + i * 0.08], [0, 1], { ...clamp, easing: Easing.out(Easing.back(1.6)) });
          return (
            <div key={n} style={{ height: 290, borderRadius: 40, background: soft, display: "flex", flexDirection: "column", alignItems: "center", justifyContent: "center", gap: 6, transform: `scale(${p})` }}>
              <div style={{ fontSize: 110 }}>{e}</div><div style={{ fontSize: 36, fontWeight: 700 }}>{n}</div><div style={{ fontSize: 30, color: grey }}>{q}</div>
            </div>
          );
        })}
      </div>
      <div style={{ position: "absolute", top: 1450, width: 900, height: 120, borderRadius: 60, background: ink, color: "#fff", fontSize: 46, fontWeight: 700, display: "flex", alignItems: "center", justifyContent: "center",
                    opacity: interpolate(t, [S.at + 0.9, S.at + 1.2], [0, 1], clamp), transform: `scale(${press})` }}>🍳 Cook with what I have</div>
    </AbsoluteFill>
  );
};

const RECIPES: [string, string, string, string, string][] = [["🍳", "Shakshuka with feta", "20 min · 410 kcal", "Uses 5 of your things", "🥚🍅🧅🫑🧀"],
  ["🍝", "Spinach & feta pasta", "15 min · 560 kcal", "Uses 4 of your things", "🍝🥬🧀🍋"], ["🥚", "Tomato omelette", "10 min · 320 kcal", "Uses 3 of your things", "🥚🍅🧅"]];

const Recipes: React.FC = () => {
  const frame = useCurrentFrame();
  const t = frame / FPS;
  const R = T.recipes;
  if (t < R.at || t > R.out + 0.2) return null;
  return (
    <AbsoluteFill style={{ alignItems: "center" }}>
      <div style={{ position: "absolute", top: 230, fontSize: 64, fontWeight: 800 }}>Tonight you can make</div>
      <div style={{ position: "absolute", top: 380, display: "flex", flexDirection: "column", gap: 26 }}>
        {RECIPES.map(([e, n, k, u, ic], i) => {
          const p = interpolate(t, [R.at + 0.15 + i * 0.2, R.at + 0.45 + i * 0.2], [0, 1], { ...clamp, easing: Easing.out(Easing.cubic) });
          const on = i === 0 && t >= R.pick;
          return (
            <div key={n} style={{ width: 920, borderRadius: 44, background: "#fff", border: `4px solid ${on ? pink : line}`, padding: "34px 40px", boxSizing: "border-box", display: "flex", gap: 30, alignItems: "center",
                                  boxShadow: "0 16px 40px rgba(0,0,0,0.07)", opacity: p, transform: `translateY(${(1 - p) * 60}px) scale(${on ? 1.02 : 1})` }}>
              <div style={{ width: 170, height: 170, borderRadius: 36, background: ["#FDEBDD", "#E7F6DA", "#FFF1CC"][i], display: "flex", alignItems: "center", justifyContent: "center", fontSize: 100 }}>{e}</div>
              <div style={{ flex: 1 }}>
                <div style={{ fontSize: 44, fontWeight: 800 }}>{n}</div>
                <div style={{ fontSize: 32, color: grey, marginTop: 6 }}>{k}</div>
                <div style={{ fontSize: 30, fontWeight: 700, color: "#14805F", marginTop: 10 }}>{u} <span style={{ fontSize: 34 }}>{ic}</span></div>
              </div>
            </div>
          );
        })}
      </div>
      <div style={{ position: "absolute", top: 1400 }}><Mascot clip="cheeky" at={R.at + 0.6} size={480} /></div>
    </AbsoluteFill>
  );
};

const Detail: React.FC = () => {
  const frame = useCurrentFrame();
  const t = frame / FPS;
  const D = T.detail;
  if (t < D.at || t > D.out + 0.2) return null;
  const steps = ["Soften the onion and pepper", "Add the tomatoes, simmer 8 min", "Crack in the eggs, cover", "Crumble the feta over"];
  return (
    <AbsoluteFill style={{ alignItems: "center" }}>
      <Card at={D.at} top={260} style={{ padding: "44px 48px" }}>
        <div style={{ fontSize: 100, textAlign: "center" }}>🍳</div>
        <div style={{ fontSize: 60, fontWeight: 800, textAlign: "center" }}>Shakshuka with feta</div>
        <div style={{ display: "flex", justifyContent: "center", gap: 16, marginTop: 22 }}>
          {[["410", "kcal", ring.kcal], ["24 g", "protein", ring.protein], ["20", "min", ring.carbs]].map(([v, k, c]) => (
            <div key={k} style={{ background: "#F7F7F9", borderRadius: 26, padding: "16px 30px", textAlign: "center" }}><div style={{ fontSize: 42, fontWeight: 800, color: c }}>{v}</div><div style={{ fontSize: 28, color: grey }}>{k}</div></div>
          ))}
        </div>
        <div style={{ marginTop: 30 }}>
          {steps.map((x, i) => {
            const done = t > D.at + 0.9 + i * 0.55;
            return (
              <div key={x} style={{ display: "flex", gap: 22, alignItems: "center", padding: "20px 0", borderTop: `2px solid ${line}` }}>
                <div style={{ width: 52, height: 52, borderRadius: 26, border: `4px solid ${done ? ring.protein : "#D1D1D6"}`, background: done ? ring.protein : "transparent", color: "#fff", fontSize: 30, fontWeight: 800, display: "flex", alignItems: "center", justifyContent: "center", boxSizing: "border-box" }}>{done ? "✓" : ""}</div>
                <div style={{ fontSize: 38, fontWeight: 600, color: done ? grey : ink, textDecoration: done ? "line-through" : "none" }}>{x}</div>
              </div>
            );
          })}
        </div>
      </Card>
    </AbsoluteFill>
  );
};

export const stockLength = s(T.dur);

export const Stock: React.FC = () => {
  const frame = useCurrentFrame();
  const t = frame / FPS;
  return (
    <AbsoluteFill>
      <Page>
        {t < T.head.out + 0.25 && <Headline text="What's for dinner?" at={T.head.at} top={800} size={130} out={T.head.out} />}
        <Shelf />
        {t >= T.think.at && t < T.think.out && (
          <AbsoluteFill style={{ alignItems: "center", justifyContent: "center" }}>
            <Mascot clip="thinking" at={T.think.at} size={640} />
            <div style={{ fontSize: 44, fontWeight: 700, color: grey }}>Looking at your stock{".".repeat(1 + (Math.floor(t * 4) % 3))}</div>
          </AbsoluteFill>
        )}
        <Recipes />
        <Detail />
        {t >= T.line.at && <Headline text="Cook from what you already have." at={T.line.at} top={720} size={110} mark={["already"]} />}
      </Page>
      <Pointer show={[T.shelf.cook - 0.7, T.recipes.pick + 0.3]} stops={[[T.shelf.cook - 0.7, 900, 1300], [T.shelf.cook, 540, 1500, true], [T.recipes.pick - 0.6, 800, 900], [T.recipes.pick, 600, 520, true]]} />
      <Sequence from={s(T.end)}><EndCard at={0} /></Sequence>
    </AbsoluteFill>
  );
};
