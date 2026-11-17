import React from "react";
import { AbsoluteFill, OffthreadVideo, staticFile } from "remotion";

/** The raw simulator recording, for finding cut points. */
export const Footage: React.FC = () => (
  <AbsoluteFill style={{ background: "#000" }}>
    <OffthreadVideo src={staticFile("app.mp4")} style={{ width: "100%", height: "100%" }} muted />
  </AbsoluteFill>
);
