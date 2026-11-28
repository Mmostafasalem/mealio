import React, { createContext, useContext } from "react";
import { AbsoluteFill, Easing, Img, OffthreadVideo, Sequence, interpolate, staticFile, useCurrentFrame } from "remotion";
import { FPS, grey, ink, line, pink, ring, sf, soft } from "../ads/kit";
import { Key, place } from "./path";

// Looks and extra scenes for the scripted adverts: each advert picks a theme (white, dark neon, sunset,
// comic sticker, paper) and can use kinetic words, speech bubbles, a numbered list, food rain, a phone
// with the real app, lock-screen notifications, a quiz, a before/after split and a side-scrolling run.

export type Theme = "white" | "dark" | "sunset" | "sticker" | "paper";
export const ThemeCtx = createContext<{ theme: Theme; path: Key[] }>({ theme: "white", path: [] });
export const useTheme = () => useContext(ThemeCtx);

const clamp = { extrapolateLeft: "clamp", extrapolateRight: "clamp" } as const;
const ease = Easing.bezier(0.22, 1, 0.36, 1);
const inOut = Easing.bezier(0.65, 0, 0.35, 1);
const useT = () => useCurrentFrame() / FPS;
const rise = (t: number, a: number, d = 0.5) => interpolate(t, [a, a + d], [0, 1], { ...clamp, easing: ease });
/** 0 → 1 with a springy overshoot, for things that land. */
export const springIn = (t: number, a: number, d = 0.55) => {
  const u = interpolate(t, [a, a + d], [0, 1], clamp);
  if (u <= 0) return 0;
  return 1 - Math.exp(-6 * u) * Math.cos(9 * u);
};

export const textColor = (theme: Theme) => (theme === "dark" ? "#FFFFFF" : ink);
export const subColor = (theme: Theme) => (theme === "dark" ? "#A9A9B8" : grey);

/** The page behind everything. */
export const Backdrop: React.FC = () => {
  const { theme } = useTheme();
  const t = useT();
  if (theme === "dark") {
    return (
      <AbsoluteFill style={{ background: "#0B0B12" }}>
        <div style={{ position: "absolute", left: 540 - 700 + Math.sin(t * 0.5) * 120, top: 300 + Math.cos(t * 0.4) * 100, width: 1400, height: 1400, borderRadius: "50%",
                      background: "radial-gradient(circle, rgba(232,105,138,0.32), rgba(232,105,138,0) 60%)" }} />
        <div style={{ position: "absolute", left: 540 - 600 + Math.cos(t * 0.45) * 160, top: 1100 + Math.sin(t * 0.35) * 120, width: 1200, height: 1200, borderRadius: "50%",
                      background: "radial-gradient(circle, rgba(31,169,140,0.22), rgba(31,169,140,0) 60%)" }} />
      </AbsoluteFill>
    );
  }
  if (theme === "sunset") {
    const h = (t * 6) % 360;
    return <AbsoluteFill style={{ background: `linear-gradient(${160 + Math.sin(t * 0.3) * 12}deg, #FFD7C2 0%, #FFB3C6 45%, #F59AB5 70%, #C9A7F5 100%)`, filter: `hue-rotate(${Math.sin(h / 57) * 8}deg)` }} />;
  }
  if (theme === "sticker") {
    return (
      <AbsoluteFill style={{ background: "#FFE45C" }}>
        <AbsoluteFill style={{ backgroundImage: "radial-gradient(rgba(17,17,20,0.16) 3px, transparent 3.5px)", backgroundSize: "28px 28px", backgroundPosition: `${t * 20}px ${t * 20}px` }} />
      </AbsoluteFill>
    );
  }
  if (theme === "paper") {
    return (
      <AbsoluteFill style={{ background: "#FBF4E8" }}>
        <AbsoluteFill style={{ backgroundImage: "linear-gradient(rgba(17,17,20,0.045) 2px, transparent 2px)", backgroundSize: "100% 64px" }} />
      </AbsoluteFill>
    );
  }
  return <AbsoluteFill style={{ background: "#fff" }} />;
};

/** How a scene's content is dressed for the theme (sticker: tilted with a hard shadow). */
export const dress = (theme: Theme, index: number): React.CSSProperties => {
  if (theme === "sticker") return { transform: `rotate(${index % 2 ? 1.6 : -1.6}deg)`, filter: "drop-shadow(10px 10px 0 rgba(17,17,20,0.9))" };
  if (theme === "dark") return { filter: "drop-shadow(0 30px 60px rgba(232,105,138,0.18))" };
  if (theme === "paper") return { filter: "sepia(0.08)" };
  return {};
};

/** A headline in the theme's type: settles word by word; marked words get the accent. */
export const Headline: React.FC<{ text: string; at: number; top: number; size?: number; mark?: string[] }> = ({ text, at, top, size = 92, mark = [] }) => {
  const { theme } = useTheme();
  const t = useT();
  const serif = theme === "paper";
  const accent = theme === "sticker" ? "#E8285E" : pink;
  return (
    <div style={{ position: "absolute", top, left: 60, right: 60, display: "flex", flexWrap: "wrap", justifyContent: "center", gap: `${size * 0.04}px ${size * 0.24}px`,
                  fontSize: size, fontWeight: serif ? 700 : 900, letterSpacing: serif ? -size * 0.01 : -size * 0.035, lineHeight: 1.08, color: textColor(theme),
                  fontFamily: serif ? '"New York", "Iowan Old Style", Georgia, serif' : sf, textTransform: theme === "sticker" ? "uppercase" : "none" }}>
      {text.split(" ").map((w, i) => {
        const p = theme === "sticker" ? springIn(t, at + i * 0.07) : rise(t, at + i * 0.05, 0.6);
        const hl = mark.includes(w.replace(/[.,!?]/g, "").toLowerCase());
        const style: React.CSSProperties = theme === "sticker"
          ? { color: hl ? accent : ink, WebkitTextStroke: hl ? undefined : "0px", textShadow: "5px 5px 0 #fff, -2px -2px 0 #fff, 2px -2px 0 #fff, -2px 2px 0 #fff", transform: `scale(${p}) rotate(${(1 - Math.min(1, p)) * -12}deg)` }
          : theme === "dark"
            ? { color: hl ? pink : "#fff", textShadow: hl ? `0 0 28px rgba(232,105,138,${0.6 * p})` : undefined, opacity: p, transform: `translateY(${(1 - p) * 22}px)` }
            : { color: hl ? (serif ? "#C2410C" : accent) : textColor(theme), fontStyle: serif && hl ? "italic" : "normal", opacity: p, transform: `translateY(${(1 - p) * 22}px)` };
        return <span key={i} style={{ display: "inline-block", ...style }}>{w}</span>;
      })}
    </div>
  );
};

// ---------- extra scenes ----------

/** Big words, one at a time, on the beat: slam in, hold, get pushed out by the next. */
export const Kinetic: React.FC<{ a: number; words: string[]; every: number; colors?: string[] }> = ({ a, words, every, colors }) => {
  const { theme } = useTheme();
  const t = useT();
  const i = Math.min(words.length - 1, Math.max(0, Math.floor((t - a) / every)));
  const local = t - a - i * every;
  const s = springIn(local, 0, 0.5);
  const w = words[i];
  const big = w.length <= 4 ? 300 : w.length <= 7 ? 220 : 160;
  const color = colors?.[i % colors.length] ?? textColor(theme);
  return (
    <AbsoluteFill style={{ alignItems: "center", justifyContent: "center" }}>
      <div style={{ fontSize: big, fontWeight: 900, letterSpacing: -big * 0.05, color, transform: `scale(${0.4 + 0.6 * s}) rotate(${(i % 2 ? 4 : -4) * (1 - Math.min(1, s))}deg)`,
                    textShadow: theme === "dark" ? `0 0 40px ${color}55` : theme === "sticker" ? "8px 8px 0 #fff" : undefined, marginTop: -260, textAlign: "center", lineHeight: 0.95, maxWidth: 1000 }}>{w}</div>
    </AbsoluteFill>
  );
};

/** A speech bubble from Nourlo: follows Nourlo along its path, types its words. */
export const Bubble: React.FC<{ a: number; text: string; until: number; side?: "left" | "right" }> = ({ a, text, until, side = "right" }) => {
  const { theme, path } = useTheme();
  const t = useT();
  if (t < a || t > until + 0.3) return null;
  const p = place(path, t);
  const s = springIn(t, a, 0.45) * (1 - interpolate(t, [until, until + 0.25], [0, 1], clamp));
  const n = Math.floor(interpolate(t, [a + 0.1, a + 0.1 + text.length / 28], [0, text.length], clamp));
  const w = 560;
  const left = side === "right" ? Math.min(1080 - w - 30, p.x + p.size * 0.18) : Math.max(30, p.x - p.size * 0.18 - w);
  const top = p.y - p.size * 0.42 - 170;
  const dark = theme === "dark";
  return (
    <div style={{ position: "absolute", left, top, width: w, transform: `scale(${s})`, transformOrigin: side === "right" ? "0% 100%" : "100% 100%", zIndex: 5 }}>
      <div style={{ background: dark ? "#fff" : theme === "sticker" ? "#fff" : ink, color: dark || theme === "sticker" ? ink : "#fff", borderRadius: 40, padding: "28px 36px", fontSize: 44, fontWeight: 800,
                    lineHeight: 1.15, border: theme === "sticker" ? `5px solid ${ink}` : undefined, minHeight: 60 }}>{text.slice(0, n)}<span style={{ opacity: 0 }}>{text.slice(n)}</span></div>
      <div style={{ position: "absolute", [side === "right" ? "left" : "right"]: 60, bottom: -26, width: 0, height: 0, borderLeft: "22px solid transparent", borderRight: "22px solid transparent",
                    borderTop: `30px solid ${dark || theme === "sticker" ? "#fff" : ink}` } as React.CSSProperties} />
    </div>
  );
};

/** "3 reasons": a big number and its line, one after another. */
export const Listicle: React.FC<{ a: number; items: [string, string][]; every: number }> = ({ a, items, every }) => {
  const { theme } = useTheme();
  const t = useT();
  return (
    <div style={{ position: "absolute", top: 440, width: 960, display: "flex", flexDirection: "column", gap: 34 }}>
      {items.map(([emoji, text], i) => {
        const at = a + 0.2 + i * every;
        const s = springIn(t, at), r = rise(t, at + 0.1, 0.5);
        return (
          <div key={i} style={{ display: "flex", alignItems: "center", gap: 34, opacity: Math.min(1, r * 1.5) }}>
            <div style={{ width: 150, height: 150, borderRadius: 44, background: theme === "dark" ? "#1C1C26" : "#fff", border: `3px solid ${theme === "dark" ? "#2C2C3A" : line}`,
                          display: "flex", alignItems: "center", justifyContent: "center", fontSize: 84, transform: `scale(${s})`, boxShadow: "0 18px 40px rgba(17,17,20,0.08)" }}>{emoji}</div>
            <div style={{ flex: 1 }}>
              <div style={{ fontSize: 30, fontWeight: 800, color: pink }}>{String(i + 1).padStart(2, "0")}</div>
              <div style={{ fontSize: 54, fontWeight: 800, color: textColor(theme), lineHeight: 1.08, transform: `translateX(${(1 - r) * 40}px)` }}>{text}</div>
            </div>
          </div>
        );
      })}
    </div>
  );
};

/** Food falls; Nourlo (moving along its path) catches each piece. */
export const Rain: React.FC<{ a: number; items: string[]; every: number }> = ({ a, items, every }) => {
  const { path } = useTheme();
  const t = useT();
  return (
    <>
      {items.map((e, i) => {
        const land = a + 0.9 + i * every;           // when it reaches the bowl
        if (t < land - 1.0 || t > land + 0.35) return null;
        const p = place(path, land);
        const u = interpolate(t, [land - 1.0, land], [0, 1], clamp);
        const y = -120 + (p.y - p.size * 0.22 + 120) * u * u;
        const caught = t > land;
        const s = caught ? 1 - interpolate(t, [land, land + 0.3], [0, 1], clamp) : 1;
        return <div key={i} style={{ position: "absolute", left: p.x - 60, top: y - 60, fontSize: 120, transform: `rotate(${u * 360 * (i % 2 ? 1 : -1)}deg) scale(${s})`, zIndex: 6 }}>{e}</div>;
      })}
    </>
  );
};

/** A phone with the real app on it. */
export const Phone: React.FC<{ a: number; from: number; top?: number; scale?: number; tilt?: number }> = ({ a, from, top = 380, scale = 0.82, tilt = 0 }) => {
  const t = useT();
  const s = rise(t, a, 0.7);
  const w = 1206 * 0.5 * scale, h = 2622 * 0.5 * scale;
  return (
    <div style={{ position: "absolute", top, left: 540 - w / 2 - 22, width: w + 44, height: h + 44, borderRadius: 96 * scale, background: "#111114", padding: 22, boxSizing: "border-box",
                  boxShadow: "0 40px 90px rgba(17,17,20,0.35)", opacity: s, transform: `translateY(${(1 - s) * 120}px) rotate(${tilt * (1 - s * 0.4)}deg)` }}>
      <div style={{ width: w, height: h, borderRadius: 76 * scale, overflow: "hidden", background: "#000" }}>
        {/* the clip starts with the scene (a little before, so it is already moving as the scene arrives) */}
        <Sequence from={Math.max(0, Math.round(a * FPS) - 18)} layout="none">
          <OffthreadVideo src={staticFile("app2.mp4")} startFrom={Math.max(0, Math.round(from * FPS) - 18)} muted style={{ width: w, height: h, objectFit: "cover" }} />
        </Sequence>
      </div>
    </div>
  );
};

/** Notifications dropping onto a lock screen. */
export const Notifs: React.FC<{ a: number; items: [string, string, string][] }> = ({ a, items }) => {
  const t = useT();
  return (
    <AbsoluteFill style={{ alignItems: "center" }}>
      <div style={{ position: "absolute", top: 230, fontSize: 210, fontWeight: 700, color: "#fff", letterSpacing: -6, opacity: rise(t, a, 0.6) }}>7:30</div>
      <div style={{ position: "absolute", top: 520, width: 960, display: "flex", flexDirection: "column", gap: 22 }}>
        {items.map(([title, body, emoji], i) => {
          const s = springIn(t, a + 0.5 + i * 0.6, 0.6);
          return (
            <div key={i} style={{ display: "flex", gap: 26, alignItems: "center", background: "rgba(255,255,255,0.72)", backdropFilter: "blur(30px)", borderRadius: 46, padding: "28px 32px",
                                  opacity: Math.min(1, s), transform: `translateY(${(1 - Math.min(1, s)) * -80}px) scale(${0.9 + 0.1 * s})` }}>
              <Img src={staticFile("icon.png")} style={{ width: 96, height: 96, borderRadius: 24 }} />
              <div style={{ flex: 1 }}>
                <div style={{ display: "flex", justifyContent: "space-between", fontSize: 32, fontWeight: 700, color: ink }}><span>Nourlo</span><span style={{ color: grey, fontWeight: 500 }}>now</span></div>
                <div style={{ fontSize: 38, fontWeight: 800, color: ink }}>{emoji} {title}</div>
                <div style={{ fontSize: 34, color: "#3A3A44" }}>{body}</div>
              </div>
            </div>
          );
        })}
      </div>
    </AbsoluteFill>
  );
};

/** A two-choice quiz: the right answer gets picked. */
export const Quiz: React.FC<{ a: number; options: [string, string][]; pick: number; at: number }> = ({ a, options, pick, at }) => {
  const { theme } = useTheme();
  const t = useT();
  const chosen = t > a + at;
  return (
    <div style={{ position: "absolute", top: 560, width: 960, display: "flex", gap: 30 }}>
      {options.map(([emoji, label], i) => {
        const s = springIn(t, a + 0.3 + i * 0.15);
        const win = chosen && i === pick, lose = chosen && i !== pick;
        return (
          <div key={i} style={{ flex: 1, height: 560, borderRadius: 54, background: win ? "#E9F8F2" : theme === "dark" ? "#1C1C26" : "#fff",
                                border: `5px solid ${win ? ring.protein : theme === "dark" ? "#2C2C3A" : line}`, display: "flex", flexDirection: "column", alignItems: "center", justifyContent: "center",
                                gap: 26, transform: `scale(${s * (win ? 1.04 : lose ? 0.94 : 1)})`, opacity: lose ? 0.45 : 1, boxShadow: "0 24px 60px rgba(17,17,20,0.1)" }}>
            <div style={{ fontSize: 170 }}>{emoji}</div>
            <div style={{ fontSize: 46, fontWeight: 800, color: win ? "#14805F" : textColor(theme), textAlign: "center", padding: "0 20px" }}>{label}</div>
            {win && <div style={{ fontSize: 60, color: ring.protein, transform: `scale(${springIn(t, a + at)})` }}>✓</div>}
          </div>
        );
      })}
    </div>
  );
};

/** Without Nourlo (grey, messy) against with Nourlo (calm, done): a divider wipes across. */
export const Split: React.FC<{ a: number; left: string[]; right: string[] }> = ({ a, left, right }) => {
  const t = useT();
  const wipe = interpolate(t, [a + 0.9, a + 1.6], [1080, 540], { ...clamp, easing: inOut });
  return (
    <AbsoluteFill>
      <div style={{ position: "absolute", left: 0, top: 380, width: 540, height: 1100, padding: "0 40px", boxSizing: "border-box" }}>
        <div style={{ fontSize: 46, fontWeight: 900, color: "#8E8E93", marginBottom: 30 }}>Without</div>
        {left.map((x, i) => (
          <div key={i} style={{ fontSize: 40, fontWeight: 700, color: "#6E6E78", padding: "18px 24px", marginBottom: 18, background: "#ECECEF", borderRadius: 26,
                                transform: `rotate(${[-3, 2, -2, 3][i % 4]}deg)`, opacity: rise(t, a + 0.2 + i * 0.12, 0.4) }}>{x}</div>
        ))}
      </div>
      <div style={{ position: "absolute", left: wipe, top: 0, width: 1080 - 540, height: 1920, background: "#FFF5F8", overflow: "hidden" }}>
        <div style={{ position: "absolute", left: 0, top: 380, width: 540, padding: "0 40px", boxSizing: "border-box" }}>
          <div style={{ fontSize: 46, fontWeight: 900, color: pink, marginBottom: 30 }}>With Nourlo</div>
          {right.map((x, i) => (
            <div key={i} style={{ fontSize: 40, fontWeight: 700, color: ink, padding: "18px 24px", marginBottom: 18, background: "#fff", border: `2px solid ${line}`, borderRadius: 26,
                                  opacity: rise(t, a + 1.5 + i * 0.12, 0.4) }}><span style={{ color: ring.protein }}>✓</span> {x}</div>
          ))}
        </div>
      </div>
      <div style={{ position: "absolute", left: wipe - 3, top: 360, width: 6, height: 1150, background: pink, borderRadius: 3 }} />
    </AbsoluteFill>
  );
};

/** A side-scrolling run: food platforms slide past; the path makes Nourlo jump from one to the next. */
export const Track: React.FC<{ a: number; until: number; items: string[]; speed: number; y: number }> = ({ a, until, items, speed, y }) => {
  const { theme } = useTheme();
  const t = useT();
  const shift = (t - a) * speed;
  return (
    <>
      <div style={{ position: "absolute", left: 0, right: 0, top: y + 150, height: 8, background: theme === "dark" ? "#2C2C3A" : line }} />
      {items.map((e, i) => {
        const x = 1180 + i * 360 - shift;
        if (x < -300 || x > 1400 || t > until + 0.6) return null;
        return (
          <div key={i} style={{ position: "absolute", left: x - 110, top: y - 10, width: 220, height: 160, borderRadius: 40, background: theme === "dark" ? "#1C1C26" : "#fff",
                                border: `3px solid ${theme === "dark" ? "#2C2C3A" : line}`, display: "flex", alignItems: "center", justifyContent: "center", fontSize: 100, boxShadow: "0 16px 40px rgba(17,17,20,0.08)" }}>{e}</div>
        );
      })}
    </>
  );
};

/** 3, 2, 1. */
export const Countdown: React.FC<{ a: number; every: number; from?: number; then?: string }> = ({ a, every, from = 3, then }) => {
  const { theme } = useTheme();
  const t = useT();
  const k = Math.floor((t - a) / every);
  const label = k < from ? String(from - k) : then ?? "";
  const s = springIn(t - a - k * every, 0, 0.45);
  return (
    <AbsoluteFill style={{ alignItems: "center", justifyContent: "center" }}>
      <div style={{ fontSize: label.length > 2 ? 200 : 520, fontWeight: 900, color: k < from ? textColor(theme) : pink, transform: `scale(${s})`, marginTop: -300, letterSpacing: -10 }}>{label}</div>
    </AbsoluteFill>
  );
};

/** Floating food behind a scene, drifting with depth. */
export const Float: React.FC<{ items: string[] }> = ({ items }) => {
  const t = useT();
  return (
    <AbsoluteFill style={{ pointerEvents: "none" }}>
      {items.map((e, i) => {
        const depth = 0.5 + ((i * 37) % 10) / 10;
        const x = ((i * 233 + t * 30 * depth) % 1300) - 110;
        const y = 300 + ((i * 397) % 1400) + Math.sin(t * depth + i) * 30;
        return <div key={i} style={{ position: "absolute", left: x, top: y, fontSize: 70 * depth, opacity: 0.25 + 0.25 * depth, filter: `blur(${(1.5 - depth) * 3}px)`, transform: `rotate(${Math.sin(t + i) * 12}deg)` }}>{e}</div>;
      })}
    </AbsoluteFill>
  );
};

export { soft };
