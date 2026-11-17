import React, { useEffect, useState } from "react";
import { Composition, continueRender, delayRender, staticFile } from "remotion";
import { Animated, animatedLength } from "./Animated";
import { BowlStory, storyLength } from "./BowlStory";
import { Footage } from "./Footage";
import { Fun, funLength } from "./Fun";
import { Real, realLength } from "./Real";
import { Notifications, notificationsLength } from "./ads/Notifications";
import { Chips, chipsLength } from "./ads/Chips";
import { Voice, voiceLength } from "./ads/Voice";
import { Goals, goalsLength } from "./ads/Goals";
import { Moods, moodsLength } from "./ads/Moods";
import { Scan, scanLength } from "./ads/Scan";
import { Receipt, receiptLength } from "./ads/Receipt";
import { Train, trainLength } from "./ads/Train";
import { Stock, stockLength } from "./ads/Stock";
import { Moods2, moods2Length } from "./ads/Moods2";
import { Combo, comboLength } from "./ads/Combo";
import { fps } from "./theme";
import { StoryCompositions } from "./story";

// The wordmark's font (SIL Open Font License), loaded before any frame is drawn.
const WithFont: React.FC<{ children: React.ReactNode }> = ({ children }) => {
  const [handle] = useState(() => delayRender("Comfortaa"));
  useEffect(() => {
    const font = new FontFace("Comfortaa", `url(${staticFile("Comfortaa.ttf")})`, { weight: "300 700" });
    font.load().then((loaded) => { document.fonts.add(loaded); continueRender(handle); }).catch(() => continueRender(handle));
  }, [handle]);
  return <>{children}</>;
};

export const Root: React.FC = () => (
  <>
    <StoryCompositions />
    <Composition id="Animated" component={() => <WithFont><Animated /></WithFont>} durationInFrames={animatedLength} fps={fps} width={1080} height={1920} />
    <Composition id="Fun" component={() => <WithFont><Fun /></WithFont>} durationInFrames={funLength} fps={fps} width={1080} height={1920} />
    <Composition id="Footage" component={Footage} durationInFrames={2970} fps={fps} width={603} height={1311} />
    <Composition id="Real" component={Real} durationInFrames={realLength} fps={fps} width={1080} height={1920} />
    <Composition id="AdNotifications" component={Notifications} durationInFrames={notificationsLength} fps={fps} width={1080} height={1920} />
    <Composition id="AdChips" component={Chips} durationInFrames={chipsLength} fps={fps} width={1080} height={1920} />
    <Composition id="AdVoice" component={Voice} durationInFrames={voiceLength} fps={fps} width={1080} height={1920} />
    <Composition id="AdGoals" component={Goals} durationInFrames={goalsLength} fps={fps} width={1080} height={1920} />
    <Composition id="AdMoods" component={Moods} durationInFrames={moodsLength} fps={fps} width={1080} height={1920} />
    <Composition id="AdScan" component={Scan} durationInFrames={scanLength} fps={fps} width={1080} height={1920} />
    <Composition id="AdReceipt" component={Receipt} durationInFrames={receiptLength} fps={fps} width={1080} height={1920} />
    <Composition id="AdTrain" component={Train} durationInFrames={trainLength} fps={fps} width={1080} height={1920} />
    <Composition id="AdStock" component={Stock} durationInFrames={stockLength} fps={fps} width={1080} height={1920} />
    <Composition id="AdMoods2" component={Moods2} durationInFrames={moods2Length} fps={fps} width={1080} height={1920} />
    <Composition id="AdCombo" component={Combo} durationInFrames={comboLength} fps={fps} width={1080} height={1920} />
    <Composition id="BowlStory" component={() => <WithFont><BowlStory /></WithFont>} durationInFrames={storyLength} fps={fps} width={1080} height={1920} />
  </>
);
