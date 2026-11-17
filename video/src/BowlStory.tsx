import React from "react";
import { AbsoluteFill, Sequence, interpolate, spring, useCurrentFrame, useVideoConfig } from "remotion";
import { Bowl } from "./Bowl";
import { Caption, EndCard, PlanCard, Scene, VoiceCard, WorkoutCard } from "./parts";
import { theme, ui } from "./theme";

// Option 3: the bowl tells it. A messy week, then Nourlo sorts it out.
export const storyLength = 630;
const paper = `radial-gradient(circle at 50% 30%, ${theme.almondLift}, ${theme.almond} 75%)`;
const clamp = { extrapolateLeft: "clamp", extrapolateRight: "clamp" } as const;

const Worry: React.FC<{ text: string; at: number; x: number; y: number; tilt: number }> = ({ text, at, x, y, tilt }) => {
  const frame = useCurrentFrame();
  const { fps } = useVideoConfig();
  const p = spring({ frame: frame - at, fps, config: { damping: 9, mass: 0.6 } });
  return (
    <div style={{ position: "absolute", left: x, top: y + Math.sin((frame + at * 3) / 11) * 10, transform: `scale(${p}) rotate(${tilt}deg)`, background: "#fff", color: theme.ink,
                  fontSize: 50, fontWeight: 800, padding: "26px 40px", borderRadius: 40, boxShadow: "0 16px 40px rgba(120,60,60,0.18)", fontFamily: ui }}>
      {text}
    </div>
  );
};

const MessyWeek: React.FC = () => {
  const frame = useCurrentFrame();
  return (
    <Scene length={120} background={paper}>
      <Caption text="Another week of…" top={210} size={104} color={theme.ink} />
      <Worry text="Takeaway. Again." at={16} x={90} y={480} tilt={-5} />
      <Worry text="“What's for dinner?”" at={32} x={440} y={690} tilt={4} />
      <Worry text="€€€ over budget" at={48} x={120} y={900} tilt={-3} />
      <Worry text="Skipped the gym" at={64} x={520} y={1090} tilt={5} />
      <div style={{ position: "absolute", bottom: -40, transform: `rotate(${Math.sin(frame / 5) * 1.5}deg)` }}>
        <Bowl width={860} mood="sad" fruit={[0, 0, 0]} look={Math.sin(frame / 14)} blink={frame % 60 > 54} />
      </div>
    </Scene>
  );
};

const Meet: React.FC = () => {
  const frame = useCurrentFrame();
  const { fps } = useVideoConfig();
  const land = (at: number) => spring({ frame: frame - at, fps, config: { damping: 12, mass: 0.8 } });
  const fruit: [number, number, number] = [land(14), land(26), land(38)];
  const hop = spring({ frame: frame - 44, fps, config: { damping: 6, mass: 0.6 } });
  const lift = interpolate(hop, [0, 0.5, 1], [0, -90, 0]);
  return (
    <Scene length={90} background={paper}>
      <Caption text="Then you meet Nourlo." top={260} size={104} color={theme.ink} />
      <div style={{ position: "absolute", top: 720 + lift }}>
        <Bowl width={900} mood={frame < 16 ? "wow" : "smile"} fruit={fruit} arms={interpolate(frame, [46, 58], [0, 1], clamp)} blink={frame > 70 && frame < 75} />
      </div>
    </Scene>
  );
};

/** A feature, with the bowl peeking up from the bottom and saying the line. */
const Tell: React.FC<{ length: number; line: string; accent: string[]; children: React.ReactNode; top?: number }> = ({ length, line, accent, children, top = 560 }) => {
  const frame = useCurrentFrame();
  return (
    <Scene length={length} background={paper}>
      <Caption text={line} top={200} size={88} color={theme.ink} accent={accent} />
      <div style={{ position: "absolute", top }}>{children}</div>
      <div style={{ position: "absolute", bottom: -120 + Math.sin(frame / 9) * 10 }}>
        <Bowl width={760} blink={frame % 75 > 70} look={Math.sin(frame / 20) * 0.6} />
      </div>
    </Scene>
  );
};

export const BowlStory: React.FC = () => (
  <AbsoluteFill style={{ background: theme.almond }}>
    <Sequence durationInFrames={120}><MessyWeek /></Sequence>
    <Sequence from={120} durationInFrames={90}><Meet /></Sequence>
    <Sequence from={210} durationInFrames={105}>
      <Tell length={105} line="I plan your meals around your budget." accent={["budget"]}><PlanCard at={12} /></Tell>
    </Sequence>
    <Sequence from={315} durationInFrames={110}>
      <Tell length={110} line="Just tell me what you ate." accent={["tell"]} top={500}><VoiceCard at={8} /></Tell>
    </Sequence>
    <Sequence from={425} durationInFrames={85}>
      <Tell length={85} line="And I'll build your workouts." accent={["workouts"]}><WorkoutCard at={8} /></Tell>
    </Sequence>
    <Sequence from={510} durationInFrames={120}><EndCard length={120} /></Sequence>
  </AbsoluteFill>
);
