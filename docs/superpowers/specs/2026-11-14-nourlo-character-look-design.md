# Nourlo character: brand-pink look and new expressions

Date: 2026-11-14 · Status: approved by the owner 2026-11-14

## Why
The owner wants Nourlo to feel like a character-driven product (reference: a
video arguing a mascot needs real emotions, owned colours and big celebrations,
not just a corner decoration). First step: give the existing bowl the brand
colour and the emotional range to react to the app. Wiring those emotions to
more app events is a later step.

## Decided by the owner
- Keep Nourlo as it is drawn today (`Components/Mascot/MascotFigure.swift`):
  same bowl shape, oats, banana coins, strawberries, navy feet, clay arms,
  same rig and springs (`MascotRig`). **No spoon.**
- Recolour the bowl to the brand pink (#E8698A family) and add blueberries
  (as in the approved state sheet, `~/Desktop/Mascots/Nourlo/nourlo-states.png`).
- Add faces: wink (cheeky), glance (look to one side), heart eyes (love),
  asleep (eyes closed), worried.
- Add extras: confetti (celebrate), Zzz (asleep), thought dots (thinking),
  sweat drop (worried), floating hearts (love).

## Approaches considered
- **A. Upgrade the existing code-drawn rig (chosen).** Vector, animated,
  no assets, one character everywhere.
- B. Picture poses from the Mascot Designer kit: expressions snap instead of
  blend, loses the current rig, adds image assets.
- C. Clay renders for hero moments plus code elsewhere: two looks for one
  character.

## Design
- **Palette** (`MascotPalette`): body/arms pink glaze (light #F7A5B8, base
  #E8698A, shade #D4587A, deep #BD4A6B); rim a lighter pink; inner wall deep
  rose; cheeks a lighter warm pink so blush still reads on a pink body. Feet,
  eyes and mouth stay navy. Oats, banana and strawberry unchanged.
- **Blueberries:** three small berries on the oats; they share the strawberries' jiggle
  springs (no new springs).
- **Pose channels** (`MascotPose`), each a spring like the existing face
  channels so expressions blend: `wink` (right eye becomes a ∩), `smirk`
  (lopsided smile), `hearts` (eyes become hearts), `asleep` (eyes become
  closed ⌣ arcs), `worry` (inner-up brows). Glance reuses `lookX/lookY`.
- **Extras** are drawn by `MascotFigure` from pose values, each with an
  opacity spring: `confetti`, `zzz`, `thought`, `sweat`, `hearts` (floating).
  Confetti and floating hearts drift on the rig clock; under Reduce Motion
  they show still or not at all.
- **Moods** (`MascotMood`): keep `idle, thinking, celebrate, help, happy,
  sleepy`; add `cheeky`, `worried`, `love`. Mapping:
  - thinking → existing pose + thought dots
  - celebrate → existing pose + confetti
  - help → existing raised arm + glance toward it (the "pointing" state)
  - sleepy → eyes fully closed + Zzz (was drowsy lids)
  - cheeky → wink + smirk + slight tilt, one arm up
  - worried → wide eyes, worry brows, wavy mouth, sweat drop, arms in
  - love → heart eyes, smile, small hop, floating hearts
- **Existing uses**: chat failure switches from `.help` to `.worried`.
  Everything else keeps its current mood; it now simply looks richer.
- Accessibility: `MascotGuideView` descriptions for the new moods; still
  decorative to VoiceOver apart from the guide button.

## Non-goals (this round)
- New placements (empty/error/loading screens), a speech-bubble component,
  and the shared "what is Nourlo feeling" event source. Next round.
- The app icon. It still shows the old blush bowl; matching it is a follow-up.
- Any change to features, flows, data or navigation.

## Verification
- `MascotSnapshotTests` renders every mood (light and dark, 132 pt and 36 pt);
  read the images.
- Build clean; install the phone-test build on the owner's iPhone.

## Left to the builder
Exact spring constants, extra positions and timing, dark-mode tints.
