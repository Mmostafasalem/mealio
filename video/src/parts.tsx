import React from "react";
import { AbsoluteFill, interpolate, spring, useCurrentFrame, useVideoConfig } from "remotion";
import { Bowl } from "./Bowl";
import { theme, ui } from "./theme";

const clamp = { extrapolateLeft: "clamp", extrapolateRight: "clamp" } as const;

/** 0→1 with a soft spring, starting at `at` frames into the scene. */
export const useRise = (at = 0, damping = 14) => {
  const frame = useCurrentFrame();
  const { fps } = useVideoConfig();
  return spring({ frame: frame - at, fps, config: { damping, mass: 0.7 } });
};

/** A scene that fades in and out at its ends. */
export const Scene: React.FC<{ length: number; background?: string; children: React.ReactNode }> = ({ length, background, children }) => {
  const frame = useCurrentFrame();
  const opacity = interpolate(frame, [0, 7, length - 7, length], [0, 1, 1, 0], clamp);
  return <AbsoluteFill style={{ background, opacity, fontFamily: ui, alignItems: "center" }}>{children}</AbsoluteFill>;
};

/** A big caption whose words come up one after another. */
export const Caption: React.FC<{ text: string; top: number; size?: number; color?: string; at?: number; accent?: string[] }> = ({
  text, top, size = 92, color = theme.text, at = 0, accent = [],
}) => {
  const frame = useCurrentFrame();
  const { fps } = useVideoConfig();
  return (
    <div style={{ position: "absolute", top, left: 80, right: 80, textAlign: "center", fontSize: size, fontWeight: 800, lineHeight: 1.08, letterSpacing: -2, color }}>
      {text.split(" ").map((word, i) => {
        const p = spring({ frame: frame - at - i * 3, fps, config: { damping: 13, mass: 0.6 } });
        const plain = word.replace(/[.,!?]/g, "").toLowerCase();
        return (
          <span key={i} style={{ display: "inline-block", marginRight: size * 0.24, opacity: p, transform: `translateY(${(1 - p) * 46}px)`, color: accent.includes(plain) ? theme.rings[0] : color }}>
            {word}
          </span>
        );
      })}
    </div>
  );
};

export const Card: React.FC<{ at?: number; style?: React.CSSProperties; children: React.ReactNode }> = ({ at = 0, style, children }) => {
  const p = useRise(at);
  return (
    <div style={{ width: 900, background: theme.card, border: `2px solid ${theme.line}`, borderRadius: 44, padding: 44, color: theme.text, opacity: p,
                  transform: `translateY(${(1 - p) * 70}px) scale(${0.96 + 0.04 * p})`, boxShadow: "0 30px 80px rgba(0,0,0,0.35)", ...style }}>
      {children}
    </div>
  );
};

export const Row: React.FC<{ at: number; title: string; detail: string; right: string; dot: string }> = ({ at, title, detail, right, dot }) => {
  const p = useRise(at);
  return (
    <div style={{ display: "flex", alignItems: "center", gap: 26, padding: "22px 0", opacity: p, transform: `translateX(${(1 - p) * 60}px)` }}>
      <div style={{ width: 22, height: 22, borderRadius: 11, background: dot, flexShrink: 0 }} />
      <div style={{ flex: 1 }}>
        <div style={{ fontSize: 44, fontWeight: 700 }}>{title}</div>
        <div style={{ fontSize: 32, color: theme.dim, marginTop: 4 }}>{detail}</div>
      </div>
      <div style={{ fontSize: 38, fontWeight: 700, color: theme.dim, fontVariantNumeric: "tabular-nums" }}>{right}</div>
    </div>
  );
};

export const Check: React.FC<{ at: number; size?: number }> = ({ at, size = 60 }) => {
  const p = useRise(at, 10);
  return (
    <svg width={size} height={size} viewBox="0 0 60 60" style={{ transform: `scale(${p})`, flexShrink: 0 }}>
      <circle cx={30} cy={30} r={30} fill={theme.rings[1]} />
      <path d="M17,31 L26,40 L43,21" stroke="#0B3B32" strokeWidth={6} fill="none" strokeLinecap="round" strokeLinejoin="round" />
    </svg>
  );
};

// MARK: Feature cards (shared by both ads)

export const PlanCard: React.FC<{ at?: number }> = ({ at = 0 }) => {
  const frame = useCurrentFrame();
  const fill = interpolate(frame, [at + 12, at + 50], [0, 0.7], { ...clamp, easing: (t) => 1 - Math.pow(1 - t, 3) });
  const spent = (fill * 60).toFixed(2);
  return (
    <Card at={at}>
      <div style={{ display: "flex", justifyContent: "space-between", alignItems: "baseline" }}>
        <div style={{ fontSize: 40, fontWeight: 700 }}>This week's budget</div>
        <div style={{ fontSize: 36, color: theme.dim, fontVariantNumeric: "tabular-nums" }}>€{spent} of €60</div>
      </div>
      <div style={{ height: 26, borderRadius: 13, background: theme.line, marginTop: 24, overflow: "hidden" }}>
        <div style={{ width: `${fill * 100}%`, height: "100%", borderRadius: 13, background: theme.rings[0] }} />
      </div>
      <div style={{ height: 2, background: theme.line, margin: "34px 0 10px" }} />
      <Row at={at + 22} title="Oats and berries" detail="Breakfast" right="420 kcal" dot={theme.rings[1]} />
      <Row at={at + 30} title="Chicken rice bowl" detail="Lunch" right="610 kcal" dot={theme.rings[2]} />
      <Row at={at + 38} title="Salmon and broccoli" detail="Dinner" right="540 kcal" dot={theme.rings[3]} />
    </Card>
  );
};

export const VoiceCard: React.FC<{ at?: number }> = ({ at = 0 }) => {
  const frame = useCurrentFrame();
  const said = "Two eggs and a slice of toast";
  const typed = said.slice(0, Math.max(0, Math.floor((frame - at - 14) * 0.9)));
  const pulse = (k: number) => {
    const t = ((frame - at + k * 14) % 42) / 42;
    return { transform: `scale(${1 + t * 0.9})`, opacity: (1 - t) * 0.45 };
  };
  const orb = useRise(at, 11);
  return (
    <div style={{ display: "flex", flexDirection: "column", alignItems: "center", gap: 46 }}>
      <div style={{ width: 230, height: 230, position: "relative", transform: `scale(${orb})` }}>
        {[0, 1, 2].map((k) => (
          <div key={k} style={{ position: "absolute", inset: 0, borderRadius: "50%", background: theme.rings[0], ...pulse(k) }} />
        ))}
        <div style={{ position: "absolute", inset: 0, borderRadius: "50%", background: theme.rings[0], display: "flex", alignItems: "center", justifyContent: "center" }}>
          <svg width={110} height={110} viewBox="0 0 24 24" fill="none" stroke="#fff" strokeWidth={2} strokeLinecap="round">
            <rect x={9} y={3} width={6} height={11} rx={3} fill="#fff" />
            <path d="M5.5 11.5a6.5 6.5 0 0 0 13 0M12 18v3" />
          </svg>
        </div>
      </div>
      <div style={{ fontSize: 46, fontWeight: 600, color: theme.dim, height: 60 }}>{typed ? `“${typed}”` : ""}</div>
      <Card at={at + 52} style={{ padding: "26px 44px" }}>
        <div style={{ display: "flex", alignItems: "center", gap: 20 }}>
          <div style={{ flex: 1 }}><Row at={at + 56} title="Egg × 2" detail="Breakfast" right="156 kcal" dot={theme.rings[1]} /></div>
          <Check at={at + 70} />
        </div>
        <div style={{ display: "flex", alignItems: "center", gap: 20 }}>
          <div style={{ flex: 1 }}><Row at={at + 62} title="Toast, 1 slice" detail="Breakfast" right="80 kcal" dot={theme.rings[2]} /></div>
          <Check at={at + 76} />
        </div>
      </Card>
    </div>
  );
};

export const Rings: React.FC<{ at?: number; size?: number }> = ({ at = 0, size = 640 }) => {
  const frame = useCurrentFrame();
  const targets = [0.68, 0.8, 0.55, 0.62];
  return (
    <svg width={size} height={size} viewBox="0 0 640 640" style={{ transform: "rotate(-90deg)" }}>
      {targets.map((target, i) => {
        const r = 286 - i * 62;
        const c = 2 * Math.PI * r;
        const p = interpolate(frame, [at + i * 5, at + 55 + i * 5], [0, target], { ...clamp, easing: (t) => 1 - Math.pow(1 - t, 3) });
        return (
          <g key={i} fill="none" strokeWidth={48} strokeLinecap="round">
            <circle cx={320} cy={320} r={r} stroke={theme.rings[i]} opacity={0.18} />
            <circle cx={320} cy={320} r={r} stroke={theme.rings[i]} strokeDasharray={`${c * p} ${c}`} />
          </g>
        );
      })}
    </svg>
  );
};

export const RingLegend: React.FC<{ at?: number }> = ({ at = 0 }) => {
  const frame = useCurrentFrame();
  const kcal = Math.round(interpolate(frame, [at, at + 55], [0, 1420], { ...clamp, easing: (t) => 1 - Math.pow(1 - t, 3) }));
  const items = [["Calories", `${kcal.toLocaleString("en-US").replace(",", " ")} / 2 100`], ["Protein", "96 g"], ["Carbs", "148 g"], ["Fat", "44 g"]];
  return (
    <div style={{ display: "grid", gridTemplateColumns: "1fr 1fr", gap: 22, width: 900 }}>
      {items.map(([name, value], i) => (
        <Card key={name} at={at + 8 + i * 5} style={{ width: "auto", padding: "26px 32px", borderRadius: 34 }}>
          <div style={{ display: "flex", alignItems: "center", gap: 16, fontSize: 32, color: theme.dim }}>
            <div style={{ width: 20, height: 20, borderRadius: 10, background: theme.rings[i] }} />{name}
          </div>
          <div style={{ fontSize: 46, fontWeight: 800, marginTop: 8, fontVariantNumeric: "tabular-nums" }}>{value}</div>
        </Card>
      ))}
    </div>
  );
};

export const WorkoutCard: React.FC<{ at?: number }> = ({ at = 0 }) => (
  <Card at={at}>
    <div style={{ fontSize: 40, fontWeight: 700 }}>Today's workout</div>
    <div style={{ fontSize: 34, color: theme.dim, marginTop: 8 }}>30 min · Home · Full body</div>
    <div style={{ height: 2, background: theme.line, margin: "30px 0 10px" }} />
    {[["Squats", "3 × 12"], ["Push-ups", "3 × 10"], ["Plank", "3 × 40 s"]].map(([name, sets], i) => (
      <div key={name} style={{ display: "flex", alignItems: "center", gap: 20 }}>
        <div style={{ flex: 1 }}><Row at={at + 14 + i * 8} title={name} detail={sets} right="" dot={theme.rings[(i + 1) % 4]} /></div>
        <Check at={at + 30 + i * 9} />
      </div>
    ))}
  </Card>
);

// MARK: End card

export const Wordmark: React.FC<{ size: number; at?: number }> = ({ size, at = 0 }) => {
  const frame = useCurrentFrame();
  const { fps } = useVideoConfig();
  return (
    <div style={{ fontFamily: "Comfortaa", fontWeight: 700, fontSize: size, lineHeight: 1, display: "flex" }}>
      {[..."nourlo"].map((letter, i) => {
        const p = spring({ frame: frame - at - i * 3, fps, config: { damping: 9, mass: 0.6 } });
        return <span key={i} style={{ color: theme.word[i], display: "inline-block", transform: `translateY(${(1 - p) * 80}px) scale(${0.6 + 0.4 * p})`, opacity: Math.min(p * 2, 1) }}>{letter}</span>;
      })}
    </div>
  );
};

export const EndCard: React.FC<{ length: number }> = ({ length }) => {
  const frame = useCurrentFrame();
  const { fps } = useVideoConfig();
  const up = spring({ frame: frame - 4, fps, config: { damping: 11, mass: 0.9 } });
  const bob = Math.sin(frame / 9) * 10;
  const button = useRise(34, 10);
  const line = useRise(24);
  const fade = interpolate(frame, [0, 8], [0, 1], clamp);
  return (
    <AbsoluteFill style={{ background: `radial-gradient(circle at 50% 30%, ${theme.almondLift}, ${theme.almond} 75%)`, opacity: fade, alignItems: "center", fontFamily: ui }}>
      <div style={{ position: "absolute", top: 300 }}><Wordmark size={230} at={8} /></div>
      <div style={{ position: "absolute", top: 590, fontSize: 54, fontWeight: 700, color: theme.ink, opacity: line, transform: `translateY(${(1 - line) * 30}px)`, textAlign: "center", lineHeight: 1.25 }}>
        Meals, budget and workouts.<br />One happy bowl.
      </div>
      <div style={{ position: "absolute", top: 830, background: theme.ink, color: "#fff", borderRadius: 60, padding: "34px 84px", textAlign: "center", transform: `scale(${button * (1 + Math.sin(frame / 6) * 0.015)})` }}>
        <div style={{ fontSize: 62, fontWeight: 800, letterSpacing: -1 }}>Download now</div>
        <div style={{ fontSize: 30, opacity: 0.7, marginTop: 4 }}>Search “Nourlo” on the App Store</div>
      </div>
      <div style={{ position: "absolute", bottom: -150 + bob, transform: `translateY(${(1 - up) * 900}px)` }}>
        <Bowl width={980} blink={frame % 80 < 4} arms={interpolate(frame, [30, 44], [0, 1], clamp)} />
      </div>
    </AbsoluteFill>
  );
};
