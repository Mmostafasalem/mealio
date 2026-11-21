import React from "react";
import { AbsoluteFill, Easing, Sequence, interpolate, random, spring, useCurrentFrame, useVideoConfig } from "remotion";
import { Bowl } from "./Bowl";
import { Wordmark } from "./parts";
import { theme, ui } from "./theme";

// The fun cut: fast scenes, colour wipes, bouncing type, flying coins, fruit rain and confetti.
// Figures and meals are examples, not a recording of the app.
const OVER = 16; // frames a scene stays on under the next one's wipe
const clamp = { extrapolateLeft: "clamp", extrapolateRight: "clamp" } as const;
const sky = "#CFE6FF", mint = "#BFF0E3", violet = "#E2D2FF", butter = "#FBE7A8";
const party = ["#D25467", "#E0A92C", "#4F5F96", "#5E9B6B", "#F08CA0", "#6FB7FF", "#C9A2FF", "#6FE0C8"];

const usePop = (at = 0, damping = 9, mass = 0.6) => {
  const frame = useCurrentFrame();
  const { fps } = useVideoConfig();
  return spring({ frame: frame - at, fps, config: { damping, mass } });
};

/** A scene revealed by a circle growing from a point, over whatever was there before. */
const Wipe: React.FC<{ background: string; from?: [number, number]; children: React.ReactNode }> = ({ background, from = [50, 85], children }) => {
  const frame = useCurrentFrame();
  const r = interpolate(frame, [0, OVER], [0, 135], { ...clamp, easing: Easing.out(Easing.cubic) });
  return (
    <AbsoluteFill style={{ background, clipPath: `circle(${r}% at ${from[0]}% ${from[1]}%)`, fontFamily: ui, alignItems: "center", overflow: "hidden" }}>
      {children}
    </AbsoluteFill>
  );
};

/** Soft shapes drifting up behind a scene. */
const Floaties: React.FC<{ colors: string[]; count?: number; seed: string; opacity?: number }> = ({ colors, count = 16, seed, opacity = 0.55 }) => {
  const frame = useCurrentFrame();
  return (
    <AbsoluteFill>
      {Array.from({ length: count }).map((_, i) => {
        const x = random(seed + "x" + i) * 1080;
        const size = 30 + random(seed + "s" + i) * 90;
        const speed = 1.2 + random(seed + "v" + i) * 2.6;
        const y = ((random(seed + "y" + i) * 2200 - frame * speed) % 2200 + 2200) % 2200 - 140;
        const kind = i % 3;
        const style: React.CSSProperties = {
          position: "absolute", left: x + Math.sin((frame + i * 20) / 22) * 26, top: y, width: size, height: size, opacity,
          background: kind === 2 ? "transparent" : colors[i % colors.length], borderRadius: kind === 0 ? "50%" : size * 0.28,
          border: kind === 2 ? `${size * 0.16}px solid ${colors[i % colors.length]}` : undefined, boxSizing: "border-box",
          transform: `rotate(${frame * (i % 2 ? 1.6 : -1.2) + i * 40}deg)`,
        };
        return <div key={i} style={style} />;
      })}
    </AbsoluteFill>
  );
};

/** Words that slam in one after another; a word in `stickers` sits on a tilted colour block. */
const Slam: React.FC<{ text: string; top: number; size?: number; at?: number; color?: string; stickers?: Record<string, string>; gap?: number }> = ({
  text, top, size = 120, at = 0, color = theme.ink, stickers = {}, gap = 4,
}) => {
  const frame = useCurrentFrame();
  const { fps } = useVideoConfig();
  return (
    <div style={{ position: "absolute", top, left: 60, right: 60, display: "flex", flexWrap: "wrap", justifyContent: "center", gap: `${size * 0.1}px ${size * 0.24}px`, fontSize: size, fontWeight: 900, letterSpacing: -3, lineHeight: 1.05, color }}>
      {text.split(" ").map((word, i) => {
        const p = spring({ frame: frame - at - i * gap, fps, config: { damping: 8, mass: 0.55 } });
        const key = word.replace(/[.,!?]/g, "").toLowerCase();
        const sticker = stickers[key];
        const tilt = sticker ? (i % 2 ? 3 : -3) : 0;
        return (
          <span key={i} style={{ display: "inline-block", opacity: Math.min(p * 3, 1), transform: `scale(${2.3 - 1.3 * p}) rotate(${(1 - p) * (i % 2 ? 10 : -10) + tilt}deg)`,
                                 background: sticker, color: sticker ? "#fff" : color, padding: sticker ? `${size * 0.04}px ${size * 0.2}px` : 0, borderRadius: size * 0.22,
                                 boxShadow: sticker ? "0 14px 0 rgba(0,0,0,0.14)" : undefined }}>
            {word}
          </span>
        );
      })}
    </div>
  );
};

const Confetti: React.FC<{ at: number; x: number; y: number; count?: number; seed: string }> = ({ at, x, y, count = 70, seed }) => {
  const frame = useCurrentFrame();
  const t = frame - at;
  if (t < 0) return null;
  return (
    <AbsoluteFill>
      {Array.from({ length: count }).map((_, i) => {
        const angle = random(seed + "a" + i) * Math.PI * 2;
        const speed = 16 + random(seed + "p" + i) * 34;
        const px = x + Math.cos(angle) * speed * t * 0.9;
        const py = y + Math.sin(angle) * speed * t * 0.9 - 14 * t + 0.75 * t * t;
        const size = 16 + random(seed + "z" + i) * 22;
        return (
          <div key={i} style={{ position: "absolute", left: px, top: py, width: size, height: size * (i % 2 ? 0.45 : 1), background: party[i % party.length], borderRadius: i % 3 === 0 ? "50%" : 5,
                                transform: `rotate(${t * (12 + (i % 7) * 4)}deg)`, opacity: interpolate(t, [40, 70], [1, 0], clamp) }} />
        );
      })}
    </AbsoluteFill>
  );
};

/** The bowl with squash and stretch; `hop` 0→1 is one jump. */
const Bouncy: React.FC<{ width: number; hop?: number; height?: number; children?: never } & React.ComponentProps<typeof Bowl>> = ({ hop = 0, height = 160, ...bowl }) => {
  const air = Math.sin(Math.min(Math.max(hop, 0), 1) * Math.PI);
  const squash = hop <= 0 || hop >= 1 ? 0 : (1 - air) * 0.12;
  return (
    <div style={{ transform: `translateY(${-air * height}px) scale(${1 + squash - air * 0.05}, ${1 - squash + air * 0.07})`, transformOrigin: "50% 100%" }}>
      <Bowl {...bowl} />
    </div>
  );
};

const Pill: React.FC<{ at: number; from: "left" | "right"; top: number; dot: string; title: string; right: string }> = ({ at, from, top, dot, title, right }) => {
  const p = usePop(at, 10, 0.7);
  const side = from === "left" ? -1 : 1;
  return (
    <div style={{ position: "absolute", top, width: 860, background: "#fff", borderRadius: 60, padding: "30px 44px", display: "flex", alignItems: "center", gap: 26, color: theme.ink,
                  boxShadow: "0 12px 0 rgba(0,0,0,0.10)", transform: `translateX(${(1 - p) * side * 1100}px) rotate(${(1 - p) * side * 14}deg)` }}>
      <div style={{ width: 44, height: 44, borderRadius: 22, background: dot }} />
      <div style={{ flex: 1, fontSize: 50, fontWeight: 800 }}>{title}</div>
      <div style={{ fontSize: 46, fontWeight: 800, opacity: 0.55 }}>{right}</div>
    </div>
  );
};

// MARK: 1. The problem

const Hook: React.FC = () => {
  const frame = useCurrentFrame();
  const shake = (at: number) => { const t = frame - at; return t < 0 || t > 10 ? 0 : Math.sin(t * 2.4) * (10 - t) * 2.2; };
  const x = shake(0) + shake(34) + shake(50);
  return (
    <AbsoluteFill style={{ background: theme.ink, fontFamily: ui, alignItems: "center", overflow: "hidden", transform: `translateX(${x}px)` }}>
      <Floaties colors={["#3A3A3E", "#4A4A50"]} seed="hook" opacity={0.7} />
      <Slam text="What's for dinner?!" top={230} size={170} color="#fff" stickers={{ dinner: "#D25467" }} gap={5} />
      <Slam text="Takeaway. Again." top={800} size={96} at={34} color="#fff" stickers={{ again: "#E0A92C" }} />
      <Slam text="Budget? Gone." top={1010} size={96} at={50} color="#fff" stickers={{ gone: "#4F5F96" }} />
      <div style={{ position: "absolute", bottom: -40, transform: `rotate(${Math.sin(frame / 3) * 2.5}deg)` }}>
        <Bowl width={760} mood="sad" fruit={[0, 0, 0]} look={Math.sin(frame / 7)} blink={frame % 40 > 35} />
      </div>
    </AbsoluteFill>
  );
};

// MARK: 2. Meet Nourlo

const FruitRain: React.FC = () => {
  const frame = useCurrentFrame();
  const colors = ["#F6E3A8", "#4F5F96", "#D25467", "#6FA77A"];
  return (
    <AbsoluteFill>
      {Array.from({ length: 22 }).map((_, i) => {
        const start = random("fr" + i) * 50;
        const t = frame - start;
        if (t < 0) return null;
        const size = 46 + random("fs" + i) * 60;
        return (
          <div key={i} style={{ position: "absolute", left: random("fx" + i) * 1000, top: -160 + t * (16 + random("fv" + i) * 14) + t * t * 0.25, width: size, height: size * (i % 4 === 0 ? 0.82 : 1),
                                borderRadius: "50%", background: colors[i % 4], transform: `rotate(${t * 9}deg)`, opacity: 0.9 }} />
        );
      })}
    </AbsoluteFill>
  );
};

const Meet: React.FC = () => {
  const frame = useCurrentFrame();
  const { fps } = useVideoConfig();
  const land = (at: number) => spring({ frame: frame - at, fps, config: { damping: 11, mass: 0.7 } });
  const hop = interpolate(frame % 30, [0, 22], [0, 1], clamp);
  const small = usePop(8);
  return (
    <Wipe background={`radial-gradient(circle at 50% 30%, ${theme.almondLift}, ${theme.almond} 75%)`} from={[50, 80]}>
      <FruitRain />
      <div style={{ position: "absolute", top: 250, fontSize: 96, fontWeight: 900, color: theme.ink, transform: `scale(${small}) rotate(-4deg)` }}>Meet</div>
      <div style={{ position: "absolute", top: 380 }}><Wordmark size={250} at={14} /></div>
      <div style={{ position: "absolute", top: 860 }}>
        <Bouncy width={880} hop={frame > 44 ? hop : 0} mood={frame < 20 ? "wow" : "smile"} fruit={[land(18), land(26), land(34)]} arms={interpolate(frame, [40, 50], [0, 1], clamp)} blink={frame % 45 > 41} />
      </div>
      <Confetti at={40} x={540} y={900} seed="meet" />
    </Wipe>
  );
};

// MARK: 3. Budget meal plans

const Budget: React.FC = () => {
  const frame = useCurrentFrame();
  const coins = 9, flight = 16;
  const landed = Array.from({ length: coins }).filter((_, i) => frame >= 22 + i * 5 + flight).length;
  const fill = (landed / coins) * 0.72;
  const card = usePop(10, 11, 0.8);
  const stamp = usePop(76, 7, 0.5);
  return (
    <Wipe background={mint} from={[50, 60]}>
      <Floaties colors={["#8FDCC8", "#fff"]} seed="budget" />
      <Slam text="Meals planned around your budget" top={190} size={112} stickers={{ budget: "#D25467" }} />
      <div style={{ position: "absolute", top: 700, width: 900, background: "#fff", borderRadius: 56, padding: "44px 50px", color: theme.ink, boxShadow: "0 16px 0 rgba(0,0,0,0.10)", transform: `scale(${card}) rotate(${(1 - card) * -8}deg)` }}>
        <div style={{ display: "flex", justifyContent: "space-between", alignItems: "baseline" }}>
          <div style={{ fontSize: 44, fontWeight: 800 }}>This week</div>
          <div style={{ fontSize: 60, fontWeight: 900, fontVariantNumeric: "tabular-nums", transform: `scale(${1 + (frame % 5 === 0 && landed < coins && landed > 0 ? 0.06 : 0)})` }}>€{(fill * 60).toFixed(0)}<span style={{ opacity: 0.4 }}> / €60</span></div>
        </div>
        <div style={{ height: 44, borderRadius: 22, background: "#EEE7E4", marginTop: 26, overflow: "hidden" }}>
          <div style={{ width: `${fill * 100}%`, height: "100%", borderRadius: 22, background: "#D25467" }} />
        </div>
      </div>
      {Array.from({ length: coins }).map((_, i) => {
        const t = (frame - 22 - i * 5) / flight;
        if (t < 0 || t >= 1) return null;
        const sx = 100 + random("cx" + i) * 880, tx = 150 + (i / coins) * 0.72 * 800;
        const x = sx + (tx - sx) * t, y = 1950 + (872 - 1950) * t - Math.sin(t * Math.PI) * 260;
        return (
          <div key={i} style={{ position: "absolute", left: x - 45, top: y - 45, width: 90, height: 90, borderRadius: 45, background: "#E0A92C", border: "8px solid #C48F1C", boxSizing: "border-box",
                                color: "#7A5A0E", fontSize: 50, fontWeight: 900, display: "flex", alignItems: "center", justifyContent: "center", transform: `rotate(${t * 360}deg) scale(${1 - t * 0.35})` }}>€</div>
        );
      })}
      <Pill at={48} from="left" top={1010} dot="#E0A92C" title="Oats and berries" right="€1.20" />
      <Pill at={56} from="right" top={1150} dot="#4F5F96" title="Chicken rice bowl" right="€2.60" />
      <Pill at={64} from="left" top={1290} dot="#5E9B6B" title="Salmon and broccoli" right="€3.90" />
      <div style={{ position: "absolute", top: 1440, right: 50, width: 250, height: 250, borderRadius: "50%", background: "#5E9B6B", color: "#fff", display: "flex", alignItems: "center", justifyContent: "center", textAlign: "center",
                    fontSize: 46, fontWeight: 900, lineHeight: 1.05, border: "10px dashed rgba(255,255,255,0.7)", boxSizing: "border-box", transform: `scale(${stamp * 1}) rotate(${14 + (1 - stamp) * 60}deg)`, boxShadow: "0 12px 0 rgba(0,0,0,0.12)" }}>
        Under<br />budget!
      </div>
      <div style={{ position: "absolute", bottom: -90 + Math.sin(frame / 8) * 8 }}>
        <Bowl width={560} look={Math.sin(frame / 12)} blink={frame % 50 > 46} mood={frame > 76 && frame < 96 ? "wow" : "smile"} />
      </div>
    </Wipe>
  );
};

// MARK: 4. Voice

const Voice: React.FC = () => {
  const frame = useCurrentFrame();
  const said = "Two eggs and toast";
  const typed = said.slice(0, Math.max(0, Math.floor((frame - 16) * 0.8)));
  const bubble = usePop(12, 9);
  const badge = usePop(74, 7, 0.5);
  const talking = frame > 14 && frame < 46;
  return (
    <Wipe background={sky} from={[50, 75]}>
      <Floaties colors={["#9CC8F5", "#fff"]} seed="voice" />
      <Slam text="Just say it." top={200} size={170} stickers={{ say: "#4F5F96" }} gap={6} />
      <div style={{ position: "absolute", top: 520, display: "flex", alignItems: "center", gap: 18, height: 240 }}>
        {Array.from({ length: 13 }).map((_, i) => {
          const h = talking ? 50 + Math.abs(Math.sin(frame / 2.2 + i * 1.3)) * 190 * (0.5 + random("b" + i) * 0.5) : 30;
          return <div key={i} style={{ width: 34, height: h, borderRadius: 17, background: i % 2 ? "#4F5F96" : "#D25467" }} />;
        })}
      </div>
      <div style={{ position: "absolute", top: 820, background: "#fff", color: theme.ink, fontSize: 64, fontWeight: 800, padding: "36px 56px", borderRadius: 60, boxShadow: "0 14px 0 rgba(0,0,0,0.10)", transform: `scale(${bubble}) rotate(-2deg)`, minWidth: 300, textAlign: "center" }}>
        “{typed}”
        <div style={{ position: "absolute", bottom: -34, left: "50%", marginLeft: -30, width: 60, height: 60, background: "#fff", transform: "rotate(45deg)", borderRadius: 10 }} />
      </div>
      <Pill at={50} from="left" top={1040} dot="#E0A92C" title="Egg × 2" right="156 kcal" />
      <Pill at={58} from="right" top={1180} dot="#5E9B6B" title="Toast" right="80 kcal" />
      <div style={{ position: "absolute", top: 960, right: 50, background: "#D25467", color: "#fff", fontSize: 54, fontWeight: 900, padding: "22px 38px", borderRadius: 50, transform: `scale(${badge}) rotate(${10 - badge * 2}deg)`, boxShadow: "0 10px 0 rgba(0,0,0,0.14)" }}>
        Logged!
      </div>
      <div style={{ position: "absolute", bottom: -60 + Math.sin(frame / 8) * 8 }}>
        <Bowl width={620} mood={talking && frame % 8 < 4 ? "wow" : "smile"} blink={frame % 55 > 51} />
      </div>
    </Wipe>
  );
};

// MARK: 5. Rings

const RingsScene: React.FC = () => {
  const frame = useCurrentFrame();
  const targets = [0.74, 0.86, 0.6, 0.68];
  const kcal = Math.round(interpolate(frame, [12, 62], [0, 1560], { ...clamp, easing: Easing.out(Easing.cubic) }));
  const zoom = usePop(6, 10, 0.9);
  return (
    <Wipe background={theme.ink} from={[50, 50]}>
      <Floaties colors={theme.rings} seed="rings" count={12} opacity={0.25} />
      <Slam text="Watch your day fill up" top={200} size={116} color="#fff" stickers={{ fill: "#F08CA0" }} />
      <div style={{ position: "absolute", top: 610, transform: `scale(${zoom}) rotate(${-90 + (1 - zoom) * -120}deg)`, filter: "drop-shadow(0 0 40px rgba(240,140,160,0.35))" }}>
        <svg width={760} height={760} viewBox="0 0 640 640">
          {targets.map((target, i) => {
            const r = 286 - i * 62, c = 2 * Math.PI * r;
            const p = interpolate(frame, [12 + i * 4, 60 + i * 4], [0, target], { ...clamp, easing: Easing.out(Easing.back(1.6)) });
            return (
              <g key={i} fill="none" strokeWidth={48} strokeLinecap="round">
                <circle cx={320} cy={320} r={r} stroke={theme.rings[i]} opacity={0.18} />
                <circle cx={320} cy={320} r={r} stroke={theme.rings[i]} strokeDasharray={`${c * Math.max(p, 0)} ${c}`} />
              </g>
            );
          })}
        </svg>
      </div>
      <div style={{ position: "absolute", top: 1430, color: "#fff", fontSize: 130, fontWeight: 900, fontVariantNumeric: "tabular-nums", letterSpacing: -3 }}>
        {kcal.toLocaleString("en-US").replace(",", " ")}<span style={{ fontSize: 60, opacity: 0.6 }}> kcal</span>
      </div>
      {[["Protein", 1], ["Carbs", 2], ["Fat", 3]].map(([name, i], k) => {
        const p = spring({ frame: frame - 40 - k * 6, fps: 30, config: { damping: 9, mass: 0.6 } });
        return <div key={name} style={{ position: "absolute", top: 1610, left: 130 + k * 290, width: 250, textAlign: "center", background: theme.rings[i as number], color: theme.ink, fontSize: 44, fontWeight: 900, padding: "18px 0", borderRadius: 40, transform: `scale(${p}) rotate(${k === 1 ? 0 : k ? 4 : -4}deg)` }}>{name}</div>;
      })}
    </Wipe>
  );
};

// MARK: 6. Workouts

const Workout: React.FC = () => {
  const frame = useCurrentFrame();
  const cycle = 22;
  const t = (frame - 14) / cycle;
  const rep = Math.max(0, Math.min(3, Math.floor(t + 0.5)));
  const lift = frame < 14 ? 0 : 0.55 + 0.45 * Math.abs(Math.sin(Math.max(t, 0) * Math.PI));
  const squat = frame < 14 ? 0 : (1 - Math.abs(Math.sin(Math.max(t, 0) * Math.PI))) * 0.08;
  const pop = spring({ frame: (frame - 14 + cycle / 2) % cycle, fps: 30, config: { damping: 7, mass: 0.4 } });
  return (
    <Wipe background={violet} from={[50, 70]}>
      <Floaties colors={["#C4A8F5", "#fff"]} seed="workout" />
      <Slam text="Workouts made for you" top={200} size={124} stickers={{ workouts: "#4F5F96" }} />
      <div style={{ position: "absolute", top: 640, right: 90, width: 260, height: 260, borderRadius: "50%", background: "#E0A92C", color: "#fff", fontSize: 170, fontWeight: 900, display: "flex", alignItems: "center", justifyContent: "center",
                    transform: `scale(${rep > 0 ? 0.7 + 0.3 * pop : 0}) rotate(8deg)`, boxShadow: "0 12px 0 rgba(0,0,0,0.12)" }}>{rep}</div>
      <div style={{ position: "absolute", top: 700, left: 80, background: "#fff", color: theme.ink, fontSize: 50, fontWeight: 900, padding: "24px 40px", borderRadius: 50, transform: `scale(${usePop(20)}) rotate(-5deg)`, boxShadow: "0 10px 0 rgba(0,0,0,0.10)" }}>30 min · Home</div>
      <div style={{ position: "absolute", top: 980, transform: `scale(${1 + squat}, ${1 - squat})`, transformOrigin: "50% 100%" }}>
        <Bowl width={900} arms={lift} barbell mood={lift > 0.9 ? "wow" : "smile"} blink={frame % 44 > 40} />
      </div>
    </Wipe>
  );
};

// MARK: 7. Download

const End: React.FC = () => {
  const frame = useCurrentFrame();
  const hop = interpolate(frame % 34, [0, 24], [0, 1], clamp);
  const line = usePop(22, 12);
  const button = usePop(32, 7, 0.6);
  const arrow = Math.abs(Math.sin(frame / 5)) * 26;
  return (
    <Wipe background={`radial-gradient(circle at 50% 30%, ${theme.almondLift}, ${theme.almond} 75%)`} from={[50, 55]}>
      <Floaties colors={[butter, "#F3B9C0", "#fff"]} seed="end" />
      <div style={{ position: "absolute", top: 250 }}><Wordmark size={250} at={6} /></div>
      <div style={{ position: "absolute", top: 560, fontSize: 58, fontWeight: 800, color: theme.ink, textAlign: "center", lineHeight: 1.22, opacity: line, transform: `translateY(${(1 - line) * 40}px)` }}>
        Meals, budget and workouts.<br />One happy bowl.
      </div>
      <div style={{ position: "absolute", top: 760 - arrow, fontSize: 90, fontWeight: 900, color: "#D25467", opacity: button }}>↓</div>
      <div style={{ position: "absolute", top: 880, background: theme.ink, color: "#fff", borderRadius: 70, padding: "38px 90px", textAlign: "center", transform: `scale(${button * (1 + Math.sin(frame / 4) * 0.03)}) rotate(-2deg)`, boxShadow: "0 16px 0 rgba(0,0,0,0.18)" }}>
        <div style={{ fontSize: 76, fontWeight: 900, letterSpacing: -2 }}>Download now</div>
        <div style={{ fontSize: 32, opacity: 0.75, marginTop: 6 }}>Search “Nourlo” on the App Store</div>
      </div>
      <div style={{ position: "absolute", bottom: -120 }}>
        <Bouncy width={940} hop={frame > 20 ? hop : 0} height={110} arms={interpolate(frame, [20, 32], [0, 1], clamp)} blink={frame % 50 > 46} />
      </div>
      <Confetti at={30} x={540} y={980} seed="end1" count={90} />
      <Confetti at={64} x={260} y={1100} seed="end2" count={50} />
      <Confetti at={76} x={820} y={1100} seed="end3" count={50} />
    </Wipe>
  );
};

const scenes: [React.FC, number][] = [[Hook, 78], [Meet, 84], [Budget, 108], [Voice, 96], [RingsScene, 84], [Workout, 84], [End, 126]];
export const funLength = scenes.reduce((sum, [, length]) => sum + length, 0);

export const Fun: React.FC = () => {
  let from = 0;
  return (
    <AbsoluteFill style={{ background: theme.ink }}>
      {scenes.map(([SceneComponent, length], i) => {
        const start = from;
        from += length;
        const last = i === scenes.length - 1;
        return (
          <Sequence key={i} from={start} durationInFrames={length + (last ? 0 : OVER)}>
            <SceneComponent />
          </Sequence>
        );
      })}
    </AbsoluteFill>
  );
};
