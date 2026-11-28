import React from "react";
import { AbsoluteFill, Sequence, interpolate, spring, useCurrentFrame, useVideoConfig } from "remotion";
import { Bowl } from "./Bowl";
import { Caption, EndCard, PlanCard, RingLegend, Rings, Scene, VoiceCard, WorkoutCard } from "./parts";
import { theme } from "./theme";

// Option 2: the app's screens redrawn as motion graphics. Figures are examples, not a recording.
export const animatedLength = 660;

const Hook: React.FC = () => {
  const frame = useCurrentFrame();
  const { fps } = useVideoConfig();
  const up = spring({ frame: frame - 10, fps, config: { damping: 10, mass: 0.9 } });
  return (
    <Scene length={90} background={theme.bg}>
      <Caption text="Eat well." top={330} size={150} />
      <Caption text="Stay on budget." top={500} size={118} at={12} accent={["budget"]} />
      <div style={{ position: "absolute", bottom: -120 + Math.sin(frame / 8) * 8, transform: `translateY(${(1 - up) * 900}px) rotate(${interpolate(frame, [10, 40], [-6, 0], { extrapolateRight: "clamp" })}deg)` }}>
        <Bowl width={900} blink={frame % 70 > 62} />
      </div>
    </Scene>
  );
};

/** The bowl looking on from the bottom edge, so every scene carries the character. */
const Peek: React.FC = () => {
  const frame = useCurrentFrame();
  return (
    <div style={{ position: "absolute", bottom: -70 + Math.sin(frame / 9) * 8 }}>
      <Bowl width={560} blink={frame % 75 > 70} look={Math.sin(frame / 18) * 0.7} />
    </div>
  );
};

export const Animated: React.FC = () => (
  <AbsoluteFill style={{ background: theme.bg }}>
    <Sequence durationInFrames={90}><Hook /></Sequence>
    <Sequence from={90} durationInFrames={135}>
      <Scene length={135} background={theme.bg}>
        <Caption text="Meal plans built around your budget" top={250} accent={["budget"]} />
        <div style={{ position: "absolute", top: 640 }}><PlanCard at={14} /></div>
        <Peek />
      </Scene>
    </Sequence>
    <Sequence from={225} durationInFrames={135}>
      <Scene length={135} background={theme.bg}>
        <Caption text="Log food just by saying it" top={250} accent={["saying"]} />
        <div style={{ position: "absolute", top: 600 }}><VoiceCard at={10} /></div>
        <Peek />
      </Scene>
    </Sequence>
    <Sequence from={360} durationInFrames={105}>
      <Scene length={105} background={theme.bg}>
        <Caption text="Watch your day fill up" top={250} accent={["fill"]} />
        <div style={{ position: "absolute", top: 520 }}><Rings at={8} size={620} /></div>
        <div style={{ position: "absolute", top: 1200 }}><RingLegend at={14} /></div>
        <Peek />
      </Scene>
    </Sequence>
    <Sequence from={465} durationInFrames={78}>
      <Scene length={78} background={theme.bg}>
        <Caption text="Workouts made for you" top={250} accent={["workouts"]} />
        <div style={{ position: "absolute", top: 600 }}><WorkoutCard at={8} /></div>
        <Peek />
      </Scene>
    </Sequence>
    <Sequence from={540} durationInFrames={120}><EndCard length={120} /></Sequence>
  </AbsoluteFill>
);
