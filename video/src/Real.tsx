import React from "react";
import { AbsoluteFill, Easing, Img, OffthreadVideo, Sequence, interpolate, staticFile, useCurrentFrame } from "remotion";
import { theme, ui } from "./theme";

// The real app, recorded in the simulator (UITests/AdFootageTests), in a plain phone frame with
// one short line per scene. Nothing on the phone is redrawn.
const clamp = { extrapolateLeft: "clamp", extrapolateRight: "clamp" } as const;

/** One cut: where it starts in the recording (seconds), how long it runs here (frames), its speed and its line. */
type Cut = { from: number; length: number; speed: number; line: string };
const cuts: Cut[] = [
  { from: 33.0, length: 66, speed: 1, line: "Your whole day,\nin one place." },
  { from: 41.2, length: 168, speed: 1.6, line: "Say what you ate.\nIt logs it." },
  { from: 50.6, length: 84, speed: 1, line: "Calories and macros\nupdate straight away." },
  { from: 66.2, length: 96, speed: 1.9, line: "A meal plan\nfor your week." },
  { from: 77.0, length: 78, speed: 1.5, line: "Shopping that fits\nyour budget." },
  { from: 89.0, length: 96, speed: 2, line: "Workouts built\nfor you." },
];
const endLength = 96;
export const realLength = cuts.reduce((sum, cut) => sum + cut.length, 0) + endLength;

const Line: React.FC<{ text: string; length: number }> = ({ text, length }) => {
  const frame = useCurrentFrame();
  const enter = interpolate(frame, [0, 10], [0, 1], { ...clamp, easing: Easing.out(Easing.cubic) });
  const exit = interpolate(frame, [length - 6, length], [1, 0], clamp);
  return (
    <div style={{ position: "absolute", top: 120, left: 60, right: 60, textAlign: "center", whiteSpace: "pre-line", color: "#fff", fontSize: 78, fontWeight: 700, lineHeight: 1.12, letterSpacing: -1.5,
                  opacity: enter * exit, transform: `translateY(${(1 - enter) * 24}px)` }}>
      {text}
    </div>
  );
};

const Phone: React.FC = () => {
  const frame = useCurrentFrame();
  const rise = interpolate(frame, [0, 26], [0, 1], { ...clamp, easing: Easing.out(Easing.cubic) });
  const width = 690, height = (width * 2622) / 1206;
  let start = 0;
  return (
    <div style={{ position: "absolute", top: 380 + (1 - rise) * 160, opacity: rise, width: width + 28, height: height + 28, borderRadius: 104, background: "#0E0E10",
                  border: "3px solid #3A3A3E", boxSizing: "border-box", padding: 11, boxShadow: "0 40px 120px rgba(221,140,150,0.16), 0 0 0 1px #000" }}>
      <div style={{ width, height, borderRadius: 90, overflow: "hidden", position: "relative", background: "#000" }}>
        {cuts.map((cut, i) => {
          const from = start;
          start += cut.length;
          const last = i === cuts.length - 1;
          return (
            <Sequence key={i} from={from} durationInFrames={cut.length + (last ? endLength : 0)} layout="none">
              <OffthreadVideo src={staticFile("app.mp4")} trimBefore={Math.round(cut.from * 30)} playbackRate={cut.speed} muted style={{ position: "absolute", width, height }} />
            </Sequence>
          );
        })}
        <div style={{ position: "absolute", top: 20, left: "50%", marginLeft: -100, width: 200, height: 56, borderRadius: 28, background: "#000" }} />
      </div>
    </div>
  );
};

const End: React.FC = () => {
  const frame = useCurrentFrame();
  const cover = interpolate(frame, [0, 14], [0, 1], { ...clamp, easing: Easing.out(Easing.cubic) });
  const show = (at: number) => interpolate(frame, [at, at + 14], [0, 1], { ...clamp, easing: Easing.out(Easing.cubic) });
  const icon = show(8), name = show(16), button = show(26);
  return (
    <AbsoluteFill style={{ background: "#000", opacity: cover, alignItems: "center", fontFamily: ui }}>
      <Img src={staticFile("icon.png")} style={{ position: "absolute", top: 520, width: 340, height: 340, borderRadius: 78, opacity: icon, transform: `scale(${0.92 + 0.08 * icon})`, boxShadow: "0 30px 90px rgba(221,140,150,0.25)" }} />
      <div style={{ position: "absolute", top: 930, color: "#fff", fontSize: 110, fontWeight: 700, letterSpacing: -2, opacity: name, transform: `translateY(${(1 - name) * 20}px)` }}>Nourlo</div>
      <div style={{ position: "absolute", top: 1080, color: theme.dim, fontSize: 48, fontWeight: 500, opacity: name }}>Meals, budget and training.</div>
      <div style={{ position: "absolute", top: 1250, background: "#fff", color: "#000", fontSize: 54, fontWeight: 700, padding: "30px 70px", borderRadius: 60, opacity: button, transform: `translateY(${(1 - button) * 20}px)` }}>
        Download on the App Store
      </div>
    </AbsoluteFill>
  );
};

export const Real: React.FC = () => {
  let start = 0;
  const shown = cuts.reduce((sum, cut) => sum + cut.length, 0);
  return (
    <AbsoluteFill style={{ background: "radial-gradient(circle at 50% 62%, #1A1214 0%, #050505 60%, #000 100%)", fontFamily: ui, alignItems: "center" }}>
      {cuts.map((cut, i) => {
        const from = start;
        start += cut.length;
        return (
          <Sequence key={i} from={from} durationInFrames={cut.length}>
            <Line text={cut.line} length={cut.length} />
          </Sequence>
        );
      })}
      <Phone />
      <Sequence from={shown} durationInFrames={endLength}><End /></Sequence>
    </AbsoluteFill>
  );
};
