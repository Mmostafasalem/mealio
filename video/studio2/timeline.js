// Shared by the picture (piece.html) and the soundtrack (score.mjs). Seconds.
const T = {
  dur: 13,
  hopLand: 0.45,
  blinks: [1.25, 5.9, 10.0],
  notice: 1.85,          // someone noticed: eyes widen, the pink glow starts
  pinkFull: 2.9,
  squint: 2.35,          // eyes squeeze shut, shy
  cover: [2.75, 3.25],   // hands come up over the mouth
  sparkle: 3.35,         // eyes open wide and shiny, the blush comes in
  lookAway: [4.6, 5.4],
  recover: [7.0, 7.7],   // hands back down, blush fades
  white: [7.0, 7.9],     // the pink drains away
  morph: [8.1, 8.8],     // the bowl becomes the app icon, the screen goes dark
  iconUp: [8.8, 9.3],
  name: 9.2,
  bar: [9.5, 9.95],
  type: [10.05, 10.6],
  store: 10.8,
};
if (typeof module !== "undefined") module.exports = T;
