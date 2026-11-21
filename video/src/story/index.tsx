import React from "react";
import { Composition } from "remotion";
import { FPS } from "../ads/kit";
import { Script, Story } from "./Story";
import ad_buddy from "./ads/buddy.json";
import ad_budget from "./ads/budget.json";
import ad_catch from "./ads/catch.json";
import ad_challenge from "./ads/challenge.json";
import ad_cookbook from "./ads/cookbook.json";
import ad_countdown from "./ads/countdown.json";
import ad_day from "./ads/day.json";
import ad_gym from "./ads/gym.json";
import ad_hello from "./ads/hello.json";
import ad_kitchen from "./ads/kitchen.json";
import ad_morning from "./ads/morning.json";
import ad_neon from "./ads/neon.json";
import ad_plan from "./ads/plan.json";
import ad_pov from "./ads/pov.json";
import ad_quiz from "./ads/quiz.json";
import ad_reasons from "./ads/reasons.json";
import ad_runner from "./ads/runner.json";
import ad_tour from "./ads/tour.json";
import ad_versus from "./ads/versus.json";
import ad_voice from "./ads/voice.json";
import ad_wake from "./ads/wake.json";

// Every scripted advert; ./make-stories.sh renders "Story-<id>".
export const scripts = [ad_buddy, ad_budget, ad_catch, ad_challenge, ad_cookbook, ad_countdown, ad_day, ad_gym, ad_hello, ad_kitchen, ad_morning, ad_neon, ad_plan, ad_pov, ad_quiz, ad_reasons, ad_runner, ad_tour, ad_versus, ad_voice, ad_wake] as unknown as Script[];

export const StoryCompositions: React.FC = () => (
  <>
    {scripts.map(s => (
      <Composition key={s.id} id={`Story-${s.id}`} component={() => <Story script={s} />}
                   durationInFrames={Math.round(s.dur * FPS)} fps={FPS} width={1080} height={1920} />
    ))}
  </>
);
