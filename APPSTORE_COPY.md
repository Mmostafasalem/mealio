# Nourlo — draft App Store metadata

These are reviewable drafts, not a submission. Verify every feature against the
signed TestFlight build before publishing. No live-price or promotion claims.

## App name
Nourlo

## Subtitle
Meals, calories & groceries

## Promotional text
Plan meals, log food and organise your grocery shop. Use estimated prices to
plan your budget, with optional online AI suggestions and private shopping sync.

## Description
Nourlo brings meal planning, food logging and grocery budgeting into one app.

Track your day
Log foods and see estimated calories and macros alongside your personal targets.

Plan your meals
Use local suggestions, or choose to enable online AI for personalised meal plans,
recipes and chat. Online AI uses Groq through our backend and requires your
sharing permission and optional Sign in with Apple in Profile. Personal AI
credits reset daily; overall service capacity can still limit availability.

Organise your shop
Build a cart and grocery list, set a budget and enter prices you find in-store.
Explore store locations around Vilnius. Catalog prices are estimates; they are
not live shelf prices, verified promotions or guaranteed store availability.

Choose how your data is handled
Local tracking and shopping need no Nourlo account. Online AI requires Sign in
with Apple and separate sharing consent. Optional private iCloud sync covers shopping data.
Body measurements, food logs, dietary restrictions and nutrition plans are
excluded from that sync. Delete All Data is available in Profile.

Nourlo is not a medical device and does not provide medical advice. Nutrition
and calorie values are estimates. AI suggestions can be incorrect. Check all
ingredients and allergens yourself and consult a qualified professional about
your individual dietary needs.

## Suggested keywords
meal planner,food log,calories,macros,grocery,budget,Vilnius,recipes

## Review notes draft
Local features need no login. Online AI is optional and disabled by default.
Sign in with Apple is in Profile → AI allowance; separate sharing consent is in
Profile → Privacy & Help. Shopping sync is also optional.
Default AI allowance is 30 credits per person per UTC day, shared across devices:
meal plans use 5 credits and other requests use 1. Failed provider results and
cached results do not use personal credits. Provider capacity remains shared.
Delete All Data revokes the online account before clearing local data and needs
a connection/valid sign-in if an account is retained, including after sign-out.
Today's minimal spent-credit count remains until its reset to prevent abuse.
The nutrition profile and food log remain stored locally to each device; relevant
context is transmitted only after the optional AI-sharing permission. Grocery prices
are clearly estimates and are not live retailer offers.

Before submission: activate and verify backend authentication and CloudKit
Production, confirm both features work on the submitted build, and supply working
privacy/support URLs and a verified support contact in App Store Connect.

## Screenshots to prepare from the verified build
1. Home with a realistic synthetic profile and logged foods.
2. Meals with the local/online state correctly labelled.
3. Shop with estimated prices and a representative budget.
4. Grocery list with bought/unbought items.
5. Map showing Vilnius stores without an availability/promotion claim.
6. Profile privacy controls and optional shopping sync.

Automated simulator screenshots are QA evidence. Select/re-capture final marketing
screens after account-side services and the sample content have been verified.
The app icon is the owner-selected bowl mascot (applied 2026-11-06). Confirm it
as final artwork before describing it as approved in store listings.
