import React from "react";
import { Composition } from "remotion";
import { FPS } from "../ads/kit";
import { Script, Story } from "./Story";
import gym from "./ads/gym.json";
import kitchen from "./ads/kitchen.json";
import budget from "./ads/budget.json";
import voice from "./ads/voice.json";
import plan from "./ads/plan.json";
import day from "./ads/day.json";
import buddy from "./ads/buddy.json";
import morning from "./ads/morning.json";

// Every scripted advert; ./make-stories.sh renders "Story-<id>".
export const scripts = [gym, kitchen, budget, voice, plan, day, buddy, morning] as unknown as Script[];

export const StoryCompositions: React.FC = () => (
  <>
    {scripts.map(s => (
      <Composition key={s.id} id={`Story-${s.id}`} component={() => <Story script={s} />}
                   durationInFrames={Math.round(s.dur * FPS)} fps={FPS} width={1080} height={1920} />
    ))}
  </>
);
