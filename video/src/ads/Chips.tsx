import React from "react";
import { AbsoluteFill, Img, Sequence, interpolate, staticFile, useCurrentFrame } from "remotion";
import { Chip, EndCard, FPS, Headline, Mascot, Page, Pointer, grey, ink, line, pink, s, soft, useP, useSpring } from "./kit";
import T from "./chips.json";

// After reference 2: food floats round a headline, a sentence with picker chips plans the week,
// dots resolve into the plan, and the list goes to the housemates' chat.

const clamp = { extrapolateLeft: "clamp", extrapolateRight: "clamp" } as const;
const FOODS = ["🥑", "🍓", "🍌", "🥚", "🍗", "🥦", "🫐", "🥕", "🧀", "🍠", "🐟", "🥛"];

const Floating: React.FC<{ until: number }> = ({ until }) => {
  const frame = useCurrentFrame();
  const t = frame / FPS;
  const gone = interpolate(t, [until - 0.3, until], [0, 1], clamp);
  return (
    <AbsoluteFill>
      {FOODS.map((e, i) => {
        const a = (i / FOODS.length) * Math.PI * 2 + t * 0.35;
        const r = 380 + (i % 3) * 70 + Math.sin(t * 1.3 + i) * 20;
        const appear = interpolate(t, [0.05 * i, 0.05 * i + 0.4], [0, 1], { ...clamp });
        const x = 540 + Math.cos(a) * r * (1 + gone * 1.6), y = 900 + Math.sin(a) * r * 1.25 * (1 + gone * 1.6);
        return <div key={i} style={{ position: "absolute", left: x - 60, top: y - 60, fontSize: 110, transform: `rotate(${Math.sin(t * 2 + i) * 14}deg) scale(${appear})`, filter: "drop-shadow(0 10px 14px rgba(0,0,0,0.15))" }}>{e}</div>;
      })}
      <div style={{ position: "absolute", left: 120 + Math.sin(t * 1.4) * 10, top: 1260, transform: `scale(${1 - gone})` }}><Mascot clip="love" at={0.2} size={330} /></div>
      <div style={{ position: "absolute", left: 640, top: 330 + Math.sin(t * 1.2) * 10, transform: `scale(${1 - gone})` }}><Mascot clip="happy" at={0.5} size={300} /></div>
    </AbsoluteFill>
  );
};

/** The sentence with its chips; which label each chip shows depends on the time. */
const Prompt: React.FC = () => {
  const frame = useCurrentFrame();
  const t = frame / FPS;
  const p = useSpring(T.prompt.at, 16);
  const days = t >= T.days.pick ? "7 days" : "5 days";
  const diet = t >= T.diet.pick ? "balanced" : "high-protein";
  const cartN = T.cart.picks.filter(x => t >= x).length;
  return (
    <div style={{ position: "absolute", top: 230, left: 80, right: 80, fontSize: 56, fontWeight: 600, lineHeight: 1.75, opacity: p, transform: `translateY(${(1 - p) * 40}px)` }}>
      Plan <Chip label={days} active={t > T.days.click && t < T.days.pick + 0.3} size={56} /> of
      <Chip label={diet} active={t > T.diet.click && t < T.diet.pick + 0.3} size={56} /> meals under <Chip label="€40" size={56} /> using
      <Chip label={cartN ? `${cartN} things I have` : "my kitchen"} active={t > T.cart.click && t < T.generate.click} size={56} />
    </div>
  );
};

const Menu: React.FC<{ at: number; until: number; top: number; left: number; items: string[]; pick: number; pickAt: number }> = ({ at, until, top, left, items, pick, pickAt }) => {
  const frame = useCurrentFrame();
  const t = frame / FPS;
  if (t < at || t > until) return null;
  const p = interpolate(t, [at, at + 0.15], [0, 1], clamp);
  return (
    <div style={{ position: "absolute", top, left, width: 380, background: "#fff", borderRadius: 30, border: `2px solid ${line}`, boxShadow: "0 24px 60px rgba(0,0,0,0.14)", padding: 10, opacity: p, transform: `scale(${0.95 + 0.05 * p})`, transformOrigin: "top left" }}>
      {items.map((it, i) => (
        <div key={it} style={{ padding: "20px 26px", borderRadius: 20, fontSize: 42, fontWeight: 600, background: i === pick && t >= pickAt ? "#FDE7EE" : "transparent", color: i === pick && t >= pickAt ? "#B3365A" : ink }}>{it}</div>
      ))}
    </div>
  );
};

const Grid: React.FC<{ at: number; until: number; items: [string, string][]; picks: number[]; pickTimes: number[] }> = ({ at, until, items, picks, pickTimes }) => {
  const frame = useCurrentFrame();
  const t = frame / FPS;
  if (t < at || t > until) return null;
  const p = interpolate(t, [at, at + 0.2], [0, 1], clamp);
  return (
    <div style={{ position: "absolute", top: 700, left: 80, right: 80, display: "grid", gridTemplateColumns: "repeat(3, 1fr)", gap: 20, opacity: p }}>
      {items.map(([e, n], i) => {
        const k = picks.indexOf(i), on = k >= 0 && t >= pickTimes[k];
        return (
          <div key={n} style={{ aspectRatio: "1", borderRadius: 34, background: soft, display: "flex", flexDirection: "column", alignItems: "center", justifyContent: "center", gap: 8,
                                position: "relative", border: on ? `5px solid ${pink}` : `5px solid transparent`, boxSizing: "border-box" }}>
            <div style={{ fontSize: 110 }}>{e}</div><div style={{ fontSize: 32, fontWeight: 600, color: grey }}>{n}</div>
            {on && <div style={{ position: "absolute", top: 14, right: 14, width: 48, height: 48, borderRadius: 24, background: pink, color: "#fff", fontSize: 30, fontWeight: 800, display: "flex", alignItems: "center", justifyContent: "center" }}>✓</div>}
          </div>
        );
      })}
    </div>
  );
};

const Dots: React.FC = () => {
  const frame = useCurrentFrame();
  const t = frame / FPS;
  if (t < T.dots[0] || t > T.dots[1] + 0.3) return null;
  const fade = interpolate(t, [T.dots[0], T.dots[0] + 0.2, T.dots[1], T.dots[1] + 0.3], [0, 1, 1, 0], clamp);
  const dots = [];
  for (let y = 0; y < 22; y++) for (let x = 0; x < 14; x++) {
    const v = 0.5 + 0.5 * Math.sin(x * 0.7 + y * 0.5 - t * 9) * Math.cos(y * 0.3 + t * 4);
    dots.push(<div key={`${x}-${y}`} style={{ position: "absolute", left: 120 + x * 62, top: 640 + y * 52, width: 8 + v * 16, height: 8 + v * 16, borderRadius: 20, background: v > 0.6 ? pink : "#D9D9DE", opacity: 0.35 + v * 0.65 }} />);
  }
  return <div style={{ opacity: fade }}>{dots}</div>;
};

const WEEK: [string, string, string, string][] = [
  ["Mon", "🥣", "Overnight oats", "€1.20"], ["Tue", "🍗", "Chicken rice bowl", "€2.60"], ["Wed", "🍳", "Shakshuka", "€1.90"], ["Thu", "🐟", "Salmon & potatoes", "€3.90"],
  ["Fri", "🌯", "Turkey wraps", "€2.40"], ["Sat", "🍝", "Lentil bolognese", "€1.70"], ["Sun", "🥗", "Chickpea salad", "€1.80"],
];

const Plan: React.FC = () => {
  const frame = useCurrentFrame();
  const t = frame / FPS;
  if (t < T.grid || t > T.share.head) return null;
  return (
    <div style={{ position: "absolute", top: 640, left: 70, right: 70, display: "grid", gridTemplateColumns: "1fr 1fr", gap: 22 }}>
      {WEEK.map((d, i) => {
        const p = interpolate(t, [T.grid + i * 0.12, T.grid + i * 0.12 + 0.35], [0, 1], { ...clamp });
        return (
          <div key={d[0]} style={{ background: "#fff", border: `2px solid ${line}`, borderRadius: 34, padding: "26px 28px", boxShadow: "0 14px 40px rgba(0,0,0,0.07)", opacity: p, transform: `scale(${0.85 + 0.15 * p})`,
                                   gridColumn: i === 6 ? "1 / span 2" : undefined }}>
            <div style={{ display: "flex", justifyContent: "space-between", fontSize: 30, color: grey, fontWeight: 700 }}><span>{d[0]}</span><span>{d[3]}</span></div>
            <div style={{ display: "flex", alignItems: "center", gap: 16, marginTop: 10 }}><span style={{ fontSize: 70 }}>{d[1]}</span><span style={{ fontSize: 38, fontWeight: 700, lineHeight: 1.1 }}>{d[2]}</span></div>
          </div>
        );
      })}
      <div style={{ gridColumn: "1 / span 2", textAlign: "center", fontSize: 40, fontWeight: 700, marginTop: 6, opacity: interpolate(t, [T.grid + 1, T.grid + 1.3], [0, 1], clamp) }}>
        7 days · <span style={{ color: pink }}>€15.50 of €40</span> · ready to shop
      </div>
    </div>
  );
};

const Chat: React.FC = () => {
  const frame = useCurrentFrame();
  const t = frame / FPS;
  if (t < T.chat.at) return null;
  const bubble = (at: number) => interpolate(t, [at, at + 0.25], [0, 1], { ...clamp });
  const them = bubble(T.chat.them), card = bubble(T.chat.card), reply = bubble(T.chat.reply);
  return (
    <AbsoluteFill style={{ background: "#fff", padding: "0 60px" }}>
      <div style={{ position: "absolute", top: 120, left: 0, right: 0, textAlign: "center", fontSize: 34, color: grey, fontWeight: 600 }}>Housemates 🏠</div>
      <div style={{ position: "absolute", top: 260, left: 60, maxWidth: 700, background: "#E9E9EB", borderRadius: 44, padding: "26px 36px", fontSize: 44, opacity: them, transform: `scale(${0.8 + 0.2 * them})`, transformOrigin: "left bottom" }}>
        what are we eating this week??
      </div>
      <div style={{ position: "absolute", top: 440, right: 60, width: 720, background: "#fff", border: `2px solid ${line}`, borderRadius: 44, padding: 34, boxShadow: "0 16px 40px rgba(0,0,0,0.08)",
                    opacity: card, transform: `scale(${0.8 + 0.2 * card})`, transformOrigin: "right top" }}>
        <div style={{ display: "flex", alignItems: "center", gap: 18 }}><Img src={staticFile("icon.png")} style={{ width: 70, height: 70, borderRadius: 16 }} /><div style={{ fontSize: 40, fontWeight: 800 }}>This week's list</div></div>
        {["🍗 Chicken breast · 600 g", "🥚 Eggs · 12", "🍠 Potatoes · 1 kg", "🥬 Spinach", "🫘 Chickpeas · 2 cans", "🥛 Greek yogurt · 500 g"].map((x, i) => (
          <div key={x} style={{ fontSize: 36, padding: "12px 0", borderTop: `2px solid ${line}`, marginTop: i ? 0 : 20, opacity: interpolate(t, [T.chat.card + 0.2 + i * 0.1, T.chat.card + 0.4 + i * 0.1], [0, 1], clamp) }}>{x}</div>
        ))}
        <div style={{ marginTop: 14, fontSize: 36, fontWeight: 800 }}>Total €15.50</div>
      </div>
      <div style={{ position: "absolute", top: 1240, left: 60, maxWidth: 760, background: "#E9E9EB", borderRadius: 44, padding: "26px 36px", fontSize: 44, opacity: reply, transform: `scale(${0.8 + 0.2 * reply})`, transformOrigin: "left bottom" }}>
        ok you're officially the chef 👩‍🍳
      </div>
      {t > T.chat.mascot && <div style={{ position: "absolute", top: 1420, right: 80 }}><Mascot clip="cheeky" at={T.chat.mascot} size={420} /></div>}
    </AbsoluteFill>
  );
};

export const chipsLength = s(T.dur);

export const Chips: React.FC = () => {
  const frame = useCurrentFrame();
  const t = frame / FPS;
  const cartItems: [string, string][] = [["🍗", "Chicken"], ["🥚", "Eggs"], ["🍠", "Potatoes"], ["🥬", "Spinach"], ["🫘", "Chickpeas"], ["🥛", "Yogurt"], ["🍝", "Pasta"], ["🧀", "Feta"], ["🍌", "Bananas"]];
  return (
    <AbsoluteFill>
      <Page>
        {t < T.intro.out + 0.3 && <><Floating until={T.intro.out} /><Headline text="Plan meals around your budget" at={T.intro.head} top={780} size={104} mark={["budget"]} out={T.intro.out} /></>}
        {t >= T.prompt.at && t < T.share.head && (
          <>
            <Prompt />
            <Menu at={T.days.menu} until={T.days.pick + 0.25} top={420} left={240} items={["3 days", "5 days", "7 days"]} pick={2} pickAt={T.days.pick} />
            <Menu at={T.diet.menu} until={T.diet.pick + 0.25} top={520} left={120} items={["high-protein", "vegetarian", "balanced", "halal"]} pick={2} pickAt={T.diet.pick} />
            <Grid at={T.cart.menu} until={T.generate.click + 0.2} items={cartItems} picks={[0, 1, 2, 4]} pickTimes={T.cart.picks} />
            {t >= T.generate.show && t < T.dots[0] && (
              <div style={{ position: "absolute", top: 1640, background: ink, color: "#fff", fontSize: 44, fontWeight: 700, padding: "30px 80px", borderRadius: 60,
                            transform: `scale(${1 - 0.08 * Math.max(0, 1 - Math.abs(t - T.generate.click - 0.08) * 10)})` }}>Generate</div>
            )}
            <Dots />
            <Plan />
          </>
        )}
        {t >= T.share.head && t < T.chat.at && <Headline text="Send the list to your housemates" at={T.share.head} top={800} size={100} mark={["housemates"]} />}
        <Chat />
      </Page>
      <Pointer show={[T.days.click - 0.6, T.generate.click + 0.3]} stops={[
        [T.days.click - 0.6, 900, 1300], [T.days.click, 380, 330, true], [T.days.pick, 330, 625, true], [T.diet.click, 260, 440, true], [T.diet.pick, 260, 780, true],
        [T.cart.click, 700, 540, true], [T.cart.picks[0], 230, 820, true], [T.cart.picks[1], 520, 820, true], [T.cart.picks[2], 820, 820, true], [T.cart.picks[3], 520, 1120, true],
        [T.generate.click, 540, 1680, true]]} />
      <Sequence from={s(T.end)}><EndCard at={0} /></Sequence>
    </AbsoluteFill>
  );
};
