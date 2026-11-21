// Shared by the picture (piece.html) and the soundtrack (score.mjs). Seconds.
const T = {
  dur: 16,
  hook: { start: 0.12, hit: 0.85 },
  wake: 1.45,
  lines: [
    { at: 1.75, text: ["Your whole week,", "in one bowl."] },
    { at: 4.55, text: ["Meals planned", "around you."] },
    { at: 7.3, text: ["Kept inside", "your budget."] },
    { at: 10.15, text: ["Workouts that", "fit your day."] },
  ],
  linesOut: 11.0,
  drops: [
    { kind: "fruit", show: 3.35, fall: 4.1, land: 4.55 },
    { kind: "coin", i: 0, show: 6.2, fall: 6.85, land: 7.3 },
    { kind: "coin", i: 1, show: 6.3, fall: 7.1, land: 7.55 },
    { kind: "coin", i: 2, show: 6.4, fall: 7.35, land: 7.8 },
    { kind: "dumbbell", show: 9.0, fall: 9.7, land: 10.15 },
  ],
  breath: { start: 11.0, blink: 11.75, end: 12.4 },
  payoff: { bloom: 12.5, hopLand: 13.0, word: 12.75, sub: 13.45, button: 13.8 },
};
if (typeof module !== "undefined") module.exports = T;
