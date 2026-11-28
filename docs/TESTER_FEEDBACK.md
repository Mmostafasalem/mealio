# TestFlight feedback on build 1.0 (4) — every comment, verbatim, with what "done" means

Source: 52 screenshots the owner sent on 27 Nov 2026 (TestFlight › Feedback, 25–26 Nov). Text is copied
exactly (dictation slips kept, meaning in brackets). Each item has an acceptance check; an item is done
only when the check is true in the running app, with a screenshot as proof.

Status: ✅ done and checked · 🔧 in progress · ⬜ not started

---

## A. Voice

**A1** (Urte) "Pridėk sausus pusryčius su pienu prie pusryčių - add cereal with milk to breakfast, it did not understand"
- Done when: saying that phrase in Lithuanian gives a review card with breakfast cereal and milk, logged to breakfast. ✅ (merged 27 Nov; UI test `testVoiceCommandInLithuanianFindsCerealAndMilk`)

**A2** (Urte) "The download failed and it did not let me try again"
- Done when: the offline model download completes, and after any failure "Try again" starts a new download. ✅ (merged 27 Nov; real cause fixed, 11 tests)

**A3** (Urte) "There should be way more languages to select from or at least the main ones like spanish, french, russian, chinese, japanese"
- Done when: Profile › Voice offers those five plus the existing four. ✅ (merged 27 Nov)

## B. Quick actions, navigation, Home

**B1** "So design of this menu does not fit service of the app. I suggest that a quick actions would be the mascot in the distinctive button next to the dock rather than being there and then if you click on that mascot, you get the quick actions and you can also add there like ask the application the checklist, explore meals or whatever, so it would be like a quick actions feature that has a lot inside it that cannot fit somewhere else, but they should also have like a godly out [good layout]. I'm thinking something like a grid where it choose like different options, also some of them more highlighted than others, like the chatting or like the voice dictation or similar features"
- Done when: (a) no quick-actions tab in the dock; (b) the mascot is a distinctive button next to the dock; (c) tapping it opens a grid; (d) Ask Nourlo (chat), checklist, explore meals are in it; (e) chat and voice tiles are visibly bigger/highlighted. ✅ (a–e merged 27 Nov) — B2 done.

**B2** "Quick actions could be just like a button on the right of the bottom dock. that's in a unique color and just opens those four or five different actions in a menu"
- Done when: the button is on the right of the dock AND in a unique colour (the theme's accent, not black/grey like other controls). ✅ (merged 28 Nov: theme-coloured button with Nourlo (screens /tmp/r2-home b2-*, b4-home-top)) The merged button is dark glass (ink colour), not a unique colour.

**B3** "This quick actions button should be more visible, should be a distinctive from every other button. I think there's a lot of buttons in the application that are just disorganized, like my stock. this could go somewhere else because it's hard to find it and you have to go to the main page to get there, similar to like ask or chatting or quick actions, so there might be a better rearrangement there"
- Done when: (a) the quick-actions button is the most visible control on screen (accent colour, mascot, shadow); (b) My Stock is reachable from where food is used — Meals (header) and Shop — and from quick actions, not only Home; (c) Home's top row is no longer a row of look-alike buttons (My Stock / mic / History). ✅ (merged 28 Nov: My Stock in quick actions, Meals header, Shop, Home groceries; old button row gone (UI test testMyStockIsReachableFromQuickActionsMealsAndShop))

**B4** "I also don't like how everything here looks the same, does not give like more emphasis on one part over the other, and then it just should clarify which part belongs to which, maybe more colors more icons, more charts, some call to action buttons, I don't know, it just a lot of things that look the same in one place" (screen: Home — Today's meals, This week's groceries, Activity today, Grocery estimates)
- Done when: Home has a clear hierarchy — one hero (calories today) at the top, then sections that look different from each other with their own colour/icon (meals, groceries/budget, activity), at least one small chart (e.g. 7-day calories or budget bar), and a call-to-action button per section (Log food, Open plan, Shop, Start workout). The "Grocery estimates" product cards no longer take a full section on Home. ✅ (merged 28 Nov: calories hero with 7-day chart, coloured meals/groceries/training sections with their own buttons, price cards removed (UI test testHomeHasOneHeroColouredSectionsAndNoBell))

**B5** "Could go to the settings instead of sitting in the homepage" (screen: Reminders, reached from the bell on Home)
- Done when: the bell is gone from Home's header; Reminders is under Profile/settings (Notifications). ✅ (merged 28 Nov: bell removed from Home; Profile › Notifications › Reminders)

**B6** "Guided tour" (screen: Home)
- Done when: a guided tour runs once after onboarding (spotlights the main parts: calories, meals, quick-actions button, Shop, Train) and can be replayed from Profile › Help. ✅ (merged 28 Nov: 5-step tour once after onboarding; Profile › Help & legal › Replay the tour (UI test testGuidedTourRunsOnceThroughTheMainParts))

**B7** "I cannot find where to see my calories insights history. Also the application is not…" (cut off in the screenshot)
- Done when: Home has an obvious entry (e.g. tapping the calorie card or an "Insights" button) to a history page with daily calories vs target over 7/30 days, macros and streak. ✅ (merged 28 Nov: Insights from the calorie card, 7/30 days vs target, macros, streak (UI test testCalorieInsightsOpenFromHome))

## C. Meals

**C1** "The animation effect between today and this week is not good. I also understand why it's like today and this week as in taps, so a bit early out [layout] could be more intuitive and also more frictionless."
- Done when: no Today/This week segmented switch; days are picked directly (day strip) with a smooth change. ✅ (merged 27 Nov)

**C2** "I think the spacing to details here are off. Again, it's also in problem about colors and layout where too much and too little space makes it cluttered and you have to read on a scroll through a lot" (screen: This Week list)
- Done when: one day's meals fit with consistent spacing and less scrolling. ✅ (merged 28 Nov with C3: shorter cards, day strip)

**C3** (no text; red circle around an expanded Breakfast card: header "Breakfast 826 kcal", then a summary line repeating the ingredients with grams and "Not in your stock: …", then an "Ingredients" list repeating the same three foods, macro pills, "Review recipe and log", "Add missing ingredients to checklist")
- Done when: an expanded meal shows each fact once — name and kcal once, ingredients once (with grams), missing items once, then the actions. ✅ (merged 28 Nov: expanded card shows name, ingredients with grams (missing marked inline), macros once, then actions)

## D. Shop and prices

**D1** "I don't like the design for this view card. It could be a toast similar to how you'd be like DoorDash or Uber eats or similar apps where it's a toast just like a bottom banner"
- Done when: View cart is a floating rounded banner above the dock that slides in. ✅ (merged 27 Nov)

**D2** "Local currency? I am in canada? What are the prices based on?"
- Done when: (a) a currency setting (default from the phone's region, e.g. CAD in Canada) and all prices shown in it; (b) a visible "About prices" note: average estimated prices, not live store prices, converted at a fixed rate with its date. ✅ (merged 28 Nov: Profile › Currency & prices, region default, 22 currencies, About prices note under the budget (fixed rates of 27 Nov — owner to check))

## E. Appearance

**E1** (Urte) "I would like there to be more themes to choose from in terms of appearance because i think the pink color, without being able to change it the app can be more appealing only to girls"
- Done when: Profile › Appearance offers several colour themes that recolour the whole app. ✅ (merged 27 Nov, 8 themes)

## F. Profile and settings

**F1** "I think some settings could be lumped together into categories which can be opened to display those new settings or, like, subcategories or whatever. Because now it takes so long to scroll through this page that it makes it tedious"
- Done when: Profile's first screen is short (fits about one screen): your card + a list of categories (e.g. Goals & targets, Food & diet, Features, Appearance, Voice, Notifications, AI & account, Data & iCloud, Help & legal), each opening its own page. ✅ (merged 28 Nov: short Profile of 10 categories, each its own page (UI test in ProfileReviewUITests))

**F2** "How can i change my name and picture, etc"
- Done when: tapping the profile card opens Edit profile: first name, surname, and a photo (choose from Photos, take a photo, remove); the avatar shows the photo everywhere. ✅ (merged 28 Nov: Edit profile with name, surname, photo from Photos / camera / remove; photo on Home and Profile (keychain save across relaunch: check on a signed phone build))

**F3** "I cannot change mt [my] targets"
- Done when: Daily goal (kcal) and protein / carbs / fat targets can be edited and saved, with "Use recommended" to go back; Home uses the edited targets. ✅ (merged 28 Nov: Daily targets editor with Use recommended; Home and plan use them)

**F4** "Why send me a notification to train if i choose that i dont work out during onboarding?"
- Done when: no reminder of a turned-off feature is scheduled or shown. ✅ (fixed 27 Nov, commit 1a9f731, unit test)

## G. Logging and stock

**G1** "I should be able to take a picture of the food and clarify later rather than having to describe every item. This should be also an option to upload a recipe i am following and then just look calculated from there plus, also like ask for how many servings are if I am duplicating or reducing the amounts shown in the recipe"
- Done when: (a) Snap a meal works without describing; if not reviewed now, the photo is saved as "To clarify" (on Home/log) and can be finished later; (b) "Add a recipe" accepts pasted text, a link or a photo of a recipe, calculates nutrition from the ingredients, asks how many servings the recipe makes and how many you ate, and lets you scale the amounts up or down. ✅ (merged 28 Nov: photo saved to clarify later (Home and Add food), works without AI; Add a recipe from text/link/photo with servings and ×0.5/×1/×2/custom)

**G2** "The stock doesn't decrease. Also it doesn't show which items in my stock the app refers to when i describe what i ate."
- Done when: (a) logging a food that is in My Stock (by voice, search, photo, plan) takes the amount out of stock; (b) the review card shows, per food, "From your stock: <item> (x g left)" or "Not in stock". ✅ (merged 28 Nov: every logging path takes from My Stock with undo; 'From your stock: … (x g left after this)' on review cards)

**G3** "Is Churchill [it should show] the quantity from each item that I had alongside its weight, I think, and also its number of calories" (screen: voice card "Veggie burger, on bun 220 g · 493 kcal" for "2 veggie burgers")
- Done when: each row on the review card shows count × unit, grams and kcal, e.g. "2 × veggie burger · 220 g · 493 kcal", and the count can be changed. ✅ (merged 28 Nov: '2 × veggie burger · 220 g · 493 kcal' with an editable count)

**G4** "There should be something to indicate how many minutes [pieces] are each item, for example, how many slices or how many samosas or how many cans or whatever, are each item so that it can divide the number of calories and weight accurately"
- Done when: a stock/food item can have "pieces per package" (slices, samosas, cans …), filled from the barcode data when available, and food can be logged by pieces with grams and kcal divided accordingly. ✅ (merged 28 Nov: pieces in package, log by slices/pieces)

**G5** "Serving is the wrong word choice here. It should be something like total amount available or what the package comes with, but also through the barcode, it should be able to find the actual size of the item and its serving size without having not making it easier having to write it themselves because it's already provided in the QR code. Also, some of the nutrition facts are slightly off" (screen: Add to stock, "Serving · Amount in grams", "Per 100 g … Carbs 22.727273 g")
- Done when: (a) the Add-to-stock amount is labelled "Amount in package"/"Total amount"; (b) a scanned barcode fills the package size and serving size from Open Food Facts (`product_quantity`, `serving_size`); (c) numbers are rounded (1 decimal); (d) values match the product's label data (per 100 g vs per serving read correctly). ✅ (merged 28 Nov: 'Amount in package', package and serving size from the barcode, rounded values, kJ/per-serving reading fixed)

**G6** "Remove should be in red" (screen: My Stock swipe action)
- Done when: the swipe Remove button is red. ✅ (fixed 27 Nov, 1a9f731)

## H. Onboarding

**H1** "So instead of making the user select every food they buy, especially did they have already selected their diet and algorithm a model or a rulebook Can Zen [can then] just give them a predefined list of what they are most likely to be buying or consuming, and then the user can just deselect modify delete star or favourite, whatever they are buying, especially that in some categories some items are not theirs that They are not buying, for example, like soy milk and dairy, especially that doesn't make sense for someone who choose like vegan, for example, or ovo vegetarian to be given an option to choose dairy because there is out of the game in this case"
- Done when: (a) "Pick your foods" opens with a ready, pre-selected list built from the chosen diet and goal; (b) the person can deselect, add and star; (c) foods and whole categories that the diet rules out are not offered at all (no Dairy category for vegans; plant milks offered instead). ✅ (merged 28 Nov: ready list from diet and goal, stars, diet-excluded foods and sections hidden (vegan: Plant milk, no Dairy/Meat/Fish/Eggs))

**H2** "Add select more after choosing the foods within specific category"
- Done when: inside a category in onboarding there are "Select all" / "Select more" controls (like Profile › Favourite foods). ✅ (merged 28 Nov: Select all per section and per group, 'Select more foods')

**H3** "Once the keyboard autofills the first box, it should move to the second"
- Done when: choosing an AutoFill name suggestion in First name moves the cursor to Surname. ✅ (fixed 27 Nov, 1a9f731)

**H4** "The animation could be faster" (screen: Welcome)
- Done when: the welcome animation finishes noticeably sooner. ✅ (fixed 27 Nov, 1a9f731)

---

## Owner's own list (22 Nov), already in build 3 — re-check only
Typing your own amount and kcal; smooth meal expand; one "Review recipe and log" button; recipes show missing ingredients; weekly groceries fill the budget; workout programmes; Pilates and HYROX; exercises by muscle; choose features in onboarding.
