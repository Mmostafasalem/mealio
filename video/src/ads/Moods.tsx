import React from "react";
import { AbsoluteFill, Easing, Sequence, interpolate, useCurrentFrame } from "remotion";
import { EndCard, FPS, Headline, Mascot, Page, grey, ink, line, s } from "./kit";
import T from "./moods.json";

// "Nourlo when you…": the app's own mascot, in its real moods, one beat each, scrolled like a feed.

const clamp = { extrapolateLeft: "clamp", extrapolateRight: "clamp" } as const;

const Beat: React.FC<{ i: number }> = ({ i }) => {
  const frame = useCurrentFrame();
  const t = frame / FPS;
  const [action, clip, emoji, chip, bg] = T.beats[i] as string[];
  const at = 0.3 + i * T.beat, next = at + T.beat;
  if (t < at - 0.4 || t > next + 0.4) return null;
  // each beat scrolls in from below and out the top, like flicking a feed
  const inP = interpolate(t, [at - 0.3, at], [1, 0], { ...clamp, easing: Easing.out(Easing.cubic) });
  const outP = i === T.beats.length - 1 ? 0 : interpolate(t, [next - 0.3, next], [0, 1], { ...clamp, easing: Easing.in(Easing.cubic) });
  const y = (inP - outP) * 1920;
  const word = interpolate(t, [at + 0.05, at + 0.35], [0, 1], clamp);
  const pill = interpolate(t, [at + 0.5, at + 0.8], [0, 1], { ...clamp, easing: Easing.out(Easing.back(1.6)) });
  return (
    <AbsoluteFill style={{ background: bg, alignItems: "center", transform: `translateY(${y}px)` }}>
      <div style={{ position: "absolute", top: 250, fontSize: 54, fontWeight: 700, color: grey }}>Nourlo when you</div>
      <div style={{ position: "absolute", top: 330, left: 70, right: 70, textAlign: "center", fontSize: 104, fontWeight: 800, letterSpacing: -3, lineHeight: 1.05, color: ink,
                    opacity: word, transform: `translateY(${(1 - word) * 30}px)` }}>{action}</div>
      <div style={{ position: "absolute", top: 640 }}><Mascot clip={clip} at={at} size={900} /></div>
      <div style={{ position: "absolute", top: 1560, background: "#fff", border: `2px solid ${line}`, borderRadius: 60, padding: "26px 44px", fontSize: 42, fontWeight: 700,
                    boxShadow: "0 18px 40px rgba(0,0,0,0.08)", display: "flex", gap: 16, alignItems: "center", transform: `scale(${pill})` }}>
        <span style={{ fontSize: 48 }}>{emoji}</span>{chip}
      </div>
    </AbsoluteFill>
  );
};

export const moodsLength = s(T.dur);

export const Moods: React.FC = () => {
  const frame = useCurrentFrame();
  const t = frame / FPS;
  return (
    <AbsoluteFill>
      <Page>
        {T.beats.map((_, i) => <Beat key={i} i={i} />)}
        {t >= T.outro && (
          <AbsoluteFill style={{ background: "#fff", alignItems: "center" }}>
            <Headline text="Your bowl has feelings." at={T.outro} top={500} size={112} mark={["feelings"]} />
            <div style={{ position: "absolute", top: 860 }}><Mascot clip="love" at={T.outro} size={760} /></div>
          </AbsoluteFill>
        )}
      </Page>
      <Sequence from={s(T.end)}><EndCard at={0} /></Sequence>
    </AbsoluteFill>
  );
};
