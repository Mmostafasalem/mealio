import React from "react";
import { AbsoluteFill, Easing, Img, interpolate, spring, staticFile, useCurrentFrame, useVideoConfig } from "remotion";

// Shared pieces for the Nourlo adverts, in the clean white product-story style of the references:
// big centred headlines, a typing bar, a pointer, cards, and one end card.

export const FPS = 30;
export const sf = '-apple-system, "SF Pro Display", "SF Pro Text", system-ui, sans-serif';
export const ink = "#111114";
export const grey = "#8E8E93";
export const line = "#E5E5EA";
export const soft = "#F4F4F6";
export const pink = "#E8698A";
export const ring = { kcal: "#E8698A", protein: "#1FA98C", carbs: "#2F8DE4", fat: "#9A6BE0" };
const clamp = { extrapolateLeft: "clamp", extrapolateRight: "clamp" } as const;
export const s = (sec: number) => Math.round(sec * FPS);

/** 0→1 between two times (seconds), eased. */
export const useP = (from: number, to: number, ease: (t: number) => number = Easing.out(Easing.cubic)) => {
  const frame = useCurrentFrame();
  return interpolate(frame / FPS, [from, to], [0, 1], { ...clamp, easing: ease });
};
export const useSpring = (at: number, damping = 14, mass = 0.7) => {
  const frame = useCurrentFrame();
  const { fps } = useVideoConfig();
  return spring({ frame: frame - s(at), fps, config: { damping, mass } });
};

export const Page: React.FC<{ children: React.ReactNode; bg?: string }> = ({ children, bg = "#FFFFFF" }) => (
  <AbsoluteFill style={{ background: bg, fontFamily: sf, color: ink, alignItems: "center" }}>{children}</AbsoluteFill>
);

/** The app's own mascot, played from frames its rig rendered (see MascotSnapshotTests). */
export const Mascot: React.FC<{ clip: string; at?: number; size: number; loop?: boolean; length?: number; style?: React.CSSProperties }> = ({
  clip, at = 0, size, loop = true, length, style,
}) => {
  const frame = useCurrentFrame();
  const counts: Record<string, number> = { idle: 90, happy: 75, celebrate: 90, love: 90, help: 90, thinking: 90, worried: 90, sleepy: 90, cheeky: 75, hello: 75 };
  const n = length ?? counts[clip] ?? 90;
  let i = Math.max(0, frame - s(at));
  // loop the settled part, not the entrance
  if (i >= n) i = loop ? Math.floor(n * 0.4) + ((i - n) % Math.ceil(n * 0.6)) : n - 1;
  return <Img src={staticFile(`clips/${clip}/f${String(i).padStart(3, "0")}.png`)} style={{ width: size, height: size, ...style }} />;
};

/** A headline whose words rise in one after another; `mark` words sit on a pink sticker. */
export const Headline: React.FC<{ text: string; at: number; top: number; size?: number; mark?: string[]; out?: number; hand?: Record<string, string> }> = ({
  text, at, top, size = 96, mark = [], out, hand = {},
}) => {
  const frame = useCurrentFrame();
  const { fps } = useVideoConfig();
  const t = frame / FPS;
  const gone = out === undefined ? 0 : interpolate(t, [out, out + 0.25], [0, 1], clamp);
  return (
    <div style={{ position: "absolute", top, left: 70, right: 70, display: "flex", flexWrap: "wrap", justifyContent: "center", gap: `${size * 0.06}px ${size * 0.26}px`,
                  fontSize: size, fontWeight: 800, letterSpacing: -size * 0.03, lineHeight: 1.08, opacity: 1 - gone, transform: `translateY(${-gone * 30}px)` }}>
      {text.split(" ").map((word, i) => {
        const p = spring({ frame: frame - s(at) - i * 3, fps, config: { damping: 15, mass: 0.6 } });
        const key = word.replace(/[.,!?]/g, "").toLowerCase();
        const sticker = mark.includes(key);
        const script = hand[key];
        if (script) return <HandWord key={i} word={word} at={at + i * 0.1} size={size * 1.25} color={script} />;
        return (
          <span key={i} style={{ display: "inline-block", opacity: p, transform: `translateY(${(1 - p) * size * 0.4}px) ${sticker ? `rotate(${-2 + (1 - p) * -8}deg) scale(${0.8 + 0.2 * p})` : ""}`,
                                 ...(sticker ? { background: pink, color: "#fff", padding: `0 ${size * 0.18}px`, borderRadius: size * 0.22, border: "6px solid #fff",
                                                 boxShadow: "0 10px 28px rgba(232,105,138,0.35), 0 0 0 2px rgba(0,0,0,0.04)" } : {}) }}>
            {word}
          </span>
        );
      })}
    </div>
  );
};

/** A handwritten word that writes itself left to right. */
export const HandWord: React.FC<{ word: string; at: number; size: number; color: string }> = ({ word, at, size, color }) => {
  const p = useP(at, at + 0.7, Easing.inOut(Easing.quad));
  return (
    <span style={{ display: "inline-block", fontFamily: '"Bradley Hand", "Noteworthy", cursive', fontWeight: 700, fontSize: size, color, lineHeight: 1,
                   clipPath: `inset(-20% ${100 - p * 100}% -20% -5%)`, transform: "rotate(-3deg) translateY(6px)" }}>
      {word}
    </span>
  );
};

/** The ask bar: "+", text typed at `cps`, a caret, then mic and send buttons. */
export const AskBar: React.FC<{ text: string; at: number; cps?: number; top: number; placeholder?: string; width?: number; sendAt?: number }> = ({
  text, at, cps = 22, top, placeholder = "Ask Nourlo", width = 940, sendAt,
}) => {
  const frame = useCurrentFrame();
  const t = frame / FPS;
  const n = Math.max(0, Math.min(text.length, Math.floor((t - at) * cps)));
  const typed = text.slice(0, n);
  const caret = Math.floor(t * 2.2) % 2 === 0 || (t > at && n < text.length);
  const done = n >= text.length;
  const btn = useSpring(at + text.length / cps, 12);
  const press = sendAt === undefined ? 1 : 1 - 0.12 * Math.max(0, 1 - Math.abs(t - sendAt) * 8);
  return (
    <div style={{ position: "absolute", top, width, minHeight: 128, borderRadius: 64, background: "#fff", border: `2px solid ${line}`,
                  boxShadow: "0 18px 50px rgba(0,0,0,0.08)", display: "flex", alignItems: "center", padding: "18px 22px 18px 34px", gap: 22, boxSizing: "border-box" }}>
      <div style={{ fontSize: 58, fontWeight: 300, color: ink, width: 44, textAlign: "center", flexShrink: 0 }}>+</div>
      <div style={{ flex: 1, fontSize: 44, lineHeight: 1.25, color: typed ? ink : grey, fontWeight: 500 }}>
        {typed || placeholder}
        {caret && <span style={{ display: "inline-block", width: 3, height: 50, background: ink, marginLeft: 4, verticalAlign: "-8px" }} />}
      </div>
      {done && (
        <div style={{ display: "flex", gap: 16, alignItems: "center", transform: `scale(${btn})` }}>
          <svg width={44} height={44} viewBox="0 0 24 24" fill="none" stroke={ink} strokeWidth={2} strokeLinecap="round"><rect x={9} y={3} width={6} height={11} rx={3} /><path d="M5.5 11.5a6.5 6.5 0 0 0 13 0M12 18v3" /></svg>
          <div style={{ width: 88, height: 88, borderRadius: 44, background: ink, display: "flex", alignItems: "center", justifyContent: "center", transform: `scale(${press})` }}>
            <svg width={40} height={40} viewBox="0 0 24 24" fill="none" stroke="#fff" strokeWidth={2.6} strokeLinecap="round" strokeLinejoin="round"><path d="M12 19V5M5 12l7-7 7 7" /></svg>
          </div>
        </div>
      )}
    </div>
  );
};

/** A macOS-style pointer that glides between stops and clicks. stops: [time, x, y, click?] */
export const Pointer: React.FC<{ stops: [number, number, number, boolean?][]; show: [number, number] }> = ({ stops, show }) => {
  const frame = useCurrentFrame();
  const t = frame / FPS;
  if (t < show[0] || t > show[1]) return null;
  let x = stops[0][1], y = stops[0][2], press = 0;
  for (let i = 0; i < stops.length; i++) {
    const [st, sx, sy, click] = stops[i];
    const prev = stops[i - 1];
    if (prev && t >= prev[0] && t < st) {
      const p = Easing.inOut(Easing.cubic)((t - prev[0]) / (st - prev[0]));
      x = prev[1] + (sx - prev[1]) * p; y = prev[2] + (sy - prev[2]) * p;
    } else if (t >= st) { x = sx; y = sy; }
    if (click && Math.abs(t - st - 0.08) < 0.1) press = 1 - Math.abs(t - st - 0.08) / 0.1;
  }
  const fade = interpolate(t, [show[0], show[0] + 0.2, show[1] - 0.2, show[1]], [0, 1, 1, 0], clamp);
  return (
    <svg width={64} height={84} viewBox="0 0 16 21" style={{ position: "absolute", left: x, top: y, opacity: fade, transform: `scale(${1 - press * 0.15})`, transformOrigin: "0 0", filter: "drop-shadow(0 4px 6px rgba(0,0,0,0.3))", zIndex: 50 }}>
      <path d="M1 1 L1 17 L5 13 L8 20 L11 19 L8 12 L14 12 Z" fill="#111" stroke="#fff" strokeWidth={1.2} strokeLinejoin="round" />
    </svg>
  );
};

export const Card: React.FC<{ at: number; top?: number; width?: number; style?: React.CSSProperties; children: React.ReactNode; from?: number }> = ({ at, top, width = 940, style, children, from = 60 }) => {
  const p = useSpring(at, 16, 0.8);
  return (
    <div style={{ position: top === undefined ? "relative" : "absolute", top, width, boxSizing: "border-box", background: "#fff", borderRadius: 44, border: `2px solid ${line}`,
                  boxShadow: "0 24px 70px rgba(0,0,0,0.08)", padding: 40, opacity: Math.min(1, p * 1.5), transform: `translateY(${(1 - p) * from}px) scale(${0.97 + 0.03 * p})`, ...style }}>
      {children}
    </div>
  );
};

/** One iOS-style notification. */
export const Notice: React.FC<{ at: number; app: string; title: string; body: string; icon?: string; avatar?: string; initial?: string; dark?: boolean; time?: string }> = ({
  at, app, title, body, icon, avatar, initial, dark = true, time = "now",
}) => {
  const p = useSpring(at, 15, 0.7);
  return (
    <div style={{ width: 960, borderRadius: 44, padding: "26px 30px", boxSizing: "border-box", display: "flex", gap: 24, alignItems: "center",
                  background: dark ? "rgba(255,255,255,0.32)" : "rgba(255,255,255,0.92)", backdropFilter: "blur(30px)", color: dark ? "#fff" : ink,
                  boxShadow: "0 10px 30px rgba(0,0,0,0.12)", opacity: Math.min(1, p * 1.4), transform: `translateY(${(1 - p) * -40}px) scale(${0.9 + 0.1 * p})` }}>
      <div style={{ width: 92, height: 92, borderRadius: avatar ? 46 : 22, overflow: "hidden", flexShrink: 0, background: avatar ?? "#fff", display: "flex", alignItems: "center", justifyContent: "center", fontSize: 52 }}>
        {icon ? <Img src={staticFile(icon)} style={{ width: 92, height: 92 }} /> : <span style={{ color: "#fff", fontSize: 44, fontWeight: 700 }}>{initial}</span>}
      </div>
      <div style={{ flex: 1, minWidth: 0 }}>
        <div style={{ display: "flex", justifyContent: "space-between", fontSize: 34 }}>
          <span style={{ fontWeight: 700 }}>{title}</span><span style={{ opacity: 0.7, fontSize: 30 }}>{time}</span>
        </div>
        <div style={{ fontSize: 36, marginTop: 4, opacity: 0.95, whiteSpace: "nowrap", overflow: "hidden", textOverflow: "ellipsis" }}>{body}</div>
      </div>
      <span style={{ display: "none" }}>{app}</span>
    </div>
  );
};

export const LockScreen: React.FC<{ children?: React.ReactNode }> = ({ children }) => (
  <AbsoluteFill style={{ background: "linear-gradient(170deg, #2C5BD8 0%, #3E8FD8 38%, #6FC1D6 70%, #A9E0D8 100%)", fontFamily: sf, alignItems: "center", color: "#fff" }}>
    <div style={{ position: "absolute", top: 150, fontSize: 44, fontWeight: 600, opacity: 0.9 }}>Tuesday, 17 November</div>
    <div style={{ position: "absolute", top: 190, fontSize: 230, fontWeight: 700, letterSpacing: -6 }}>9:41</div>
    <div style={{ position: "absolute", top: 560, display: "flex", flexDirection: "column", gap: 18, alignItems: "center" }}>{children}</div>
  </AbsoluteFill>
);

/** "Option ⌄" picker chip inside a sentence. */
export const Chip: React.FC<{ label: string; active?: boolean; size?: number }> = ({ label, active, size = 50 }) => (
  <span style={{ display: "inline-flex", alignItems: "center", gap: 10, padding: `${size * 0.08}px ${size * 0.3}px`, margin: `0 ${size * 0.1}px`, borderRadius: size * 0.3,
                 background: active ? "#FDE7EE" : soft, border: `2px solid ${active ? pink : line}`, color: active ? "#B3365A" : ink, fontWeight: 600 }}>
    {label}<svg width={size * 0.4} height={size * 0.4} viewBox="0 0 12 12"><path d="M3 4.5 L6 7.5 L9 4.5" stroke="currentColor" strokeWidth={1.6} fill="none" strokeLinecap="round" /></svg>
  </span>
);

/** Small rings like the Home card. */
export const Rings: React.FC<{ at: number; size: number; values?: number[] }> = ({ at, size, values = [0.72, 0.84, 0.6, 0.66] }) => {
  const p = useP(at, at + 1.2);
  const cols = [ring.kcal, ring.protein, ring.carbs, ring.fat];
  return (
    <svg width={size} height={size} viewBox="0 0 200 200" style={{ transform: "rotate(-90deg)" }}>
      {values.map((v, i) => {
        const r = 88 - i * 21, c = 2 * Math.PI * r;
        return (
          <g key={i} fill="none" strokeWidth={15} strokeLinecap="round">
            <circle cx={100} cy={100} r={r} stroke={cols[i]} opacity={0.15} />
            <circle cx={100} cy={100} r={r} stroke={cols[i]} strokeDasharray={`${c * v * p} ${c}`} />
          </g>
        );
      })}
    </svg>
  );
};

/** The ending: a dot, the icon, then a dark card with a search bar that types "Nourlo". */
export const EndCard: React.FC<{ at: number }> = ({ at }) => {
  const frame = useCurrentFrame();
  const t = frame / FPS - at;
  if (t < 0) return null;
  const dot = interpolate(t, [0, 0.25, 0.55], [0, 1, 0.8], clamp);
  const icon = spring({ frame: frame - s(at + 0.5), fps: FPS, config: { damping: 11, mass: 0.7 } });
  const dark = t >= 1.6;
  if (!dark) {
    return (
      <AbsoluteFill style={{ background: "#fff", alignItems: "center", justifyContent: "center" }}>
        {t < 0.6 ? <div style={{ width: 46 * dot, height: 46 * dot, borderRadius: 23, background: "#F5C542" }} />
          : <Img src={staticFile("icon.png")} style={{ width: 260, height: 260, borderRadius: 58, transform: `scale(${icon}) rotate(${(1 - icon) * -90}deg)`, boxShadow: "0 20px 60px rgba(232,105,138,0.3)" }} />}
      </AbsoluteFill>
    );
  }
  const u = t - 1.6;
  const grow = interpolate(u, [0.2, 0.55], [0, 1], { ...clamp, easing: Easing.out(Easing.cubic) });
  const open = interpolate(u, [0.5, 0.8], [0, 1], { ...clamp, easing: Easing.inOut(Easing.cubic) });
  const word = "Nourlo", k = Math.floor(interpolate(u, [0.9, 1.4], [0, word.length], clamp));
  const w = 680 * grow, h = 16 + 88 * open;
  return (
    <AbsoluteFill style={{ background: "#0E0E15", alignItems: "center", fontFamily: sf }}>
      <Img src={staticFile("icon.png")} style={{ position: "absolute", top: 620, width: 230, height: 230, borderRadius: 52 }} />
      <div style={{ position: "absolute", top: 890, color: "#fff", fontSize: 84, fontWeight: 800, letterSpacing: -1 }}>Nourlo</div>
      <div style={{ position: "absolute", top: 1060 - h / 2, width: w, height: h, borderRadius: h / 2, padding: 6, boxSizing: "border-box",
                    background: `linear-gradient(90deg, ${ring.protein}, #fff 50%, ${pink})` }}>
        <div style={{ width: "100%", height: "100%", borderRadius: h / 2, background: open > 0.5 ? "#fff" : `rgba(255,255,255,${open * 2})`, display: "flex", alignItems: "center", gap: 18, paddingLeft: 34, boxSizing: "border-box" }}>
          {open > 0.9 && <>
            <svg width={40} height={40} viewBox="0 0 24 24" fill="none" stroke="#6E6E78" strokeWidth={2.6} strokeLinecap="round"><circle cx={10.5} cy={10.5} r={6.5} /><path d="M15.5 15.5 L21 21" /></svg>
            <span style={{ fontSize: 46, fontWeight: 700, color: ink }}>{word.slice(0, k)}</span>
            <span style={{ width: 4, height: 50, background: pink, opacity: Math.floor(u * 2.2) % 2 === 0 || k < word.length ? 1 : 0 }} />
          </>}
        </div>
      </div>
      <div style={{ position: "absolute", top: 1180, color: "#9A9AA0", fontSize: 40, fontWeight: 600, opacity: interpolate(u, [1.4, 1.8], [0, 1], clamp) }}>Download on the App Store</div>
    </AbsoluteFill>
  );
};
