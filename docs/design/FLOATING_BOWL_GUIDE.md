# Mealio floating bowl guide

Design lock, 2026-11-07. Requested by the owner: replace the bowl's separate
help destination with a floating companion, useful pathways and onboarding.

## References and roles
- Headspace style c73224da-e583-4833-bf39-3f414c317474:
  https://headspace.com — friendly illustrated guidance, ample spacing, clear
  primary actions and lightly separated rounded surfaces. Adapt structure and
  tone; retain Mealio's owner-selected palette rather than copying its blue.
- Loowner iOS flow 6595: https://refero.design/flows/6595 — short contextual
  first-use tour, visible progress, one step at a time, easy completion.
- Loowner coach mark: https://refero.design/screens/570f0d5f-e4dc-414a-bbf6-f9690548ac6c
  — explain the next useful action at the point of use.
- Ahead technique selection: https://refero.design/screens/65fc6ad4-8830-4567-9c25-2fd497c8006d
  — compact contextual explanation followed by clear actionable choices.

## Decisions
- Existing Almond #F4DAD4, Pink #DD8C96 and Rhino #2E4060 remain anchors.
  Large canvases use a lighter Almond tint; pink identifies actions and accents.
  Semantic dark surfaces and high-contrast text remain adaptive.
- Full, approved bowl artwork floats above navigation on all five main tabs.
  No new tab, help page, chat invocation or generated guidance on tap.
- The initial invitation is quiet and dismissible. Opening reveals three real
  pathways: food logging, grocery checklist and meals. AI chat is separate.
- A replayable three-step tour visits Home, Shop and Meals. Next/Finish/Skip
  never silently logs food, adds groceries, changes consent or spends AI credits.
- Long press offers side switching, replay and hiding. Profile restores visibility.
- A reserved footprint protects bottom content. The panel has a bounded scroll
  area for short displays and large text; close and navigation remain reachable.
- Pose changes use finite, cancellable springs; Reduce Motion is respected.
  A successful food addition can trigger a short celebration. There is no
  persistent typing animation or claim that local guidance is online AI.
- Remove the redundant Home guide card and old full-page mascot-help experience.
- Shared card borders are lighter, surfaces quieter, navigation text semantic.

## Verification gates
Build and interact with the actual SwiftUI app. Check pathways, tour progress,
close/skip, each tab, large Dynamic Type, dark mode and real phone installation.
Do not equate presentation polish with App Store readiness: production Apple
capabilities, durable AI allowances and external release checks remain separate.
