# SmartMarket Agent — Bug Fix Prompt

Paste this into Claude Code. Apply all fixes exactly as described. Do not rewrite or restructure files — only change the specific lines listed.

---

## Fix 1 — DietaryPreferencesView.swift (CRITICAL CRASH)

**File:** `Features/Onboarding/DietaryPreferencesView.swift`

**Problem:** The file uses `_VariadicView` and `_VariadicView_MultiViewRoot`, which are private Apple APIs. These cause a crash when the user navigates to this screen.

**Step 1:** Find this block in `body`:
```swift
FlowLayout(spacing: 10)
    .callAsFunction {
        ForEach(DietaryPreference.allCases) { pref in
            DietChipView(
                preference: pref,
                isSelected: vm.selectedPreferences.contains(pref)
            ) {
                vm.togglePreference(pref)
            }
        }
    }
    .padding(.horizontal, 24)
```
Replace it with:
```swift
FlowLayout(spacing: 10) {
    ForEach(DietaryPreference.allCases) { pref in
        DietChipView(
            preference: pref,
            isSelected: vm.selectedPreferences.contains(pref)
        ) {
            vm.togglePreference(pref)
        }
    }
}
.padding(.horizontal, 24)
```

**Step 2:** Delete the entire block at the bottom of the file (everything between `// MARK: - FlowLayout callAsFunction bridge` and the `#Preview`):
```swift
// MARK: - FlowLayout callAsFunction bridge
extension FlowLayout {
    func callAsFunction<Content: View>(@ViewBuilder _ content: () -> Content) -> some View { ... }
    func callAsFunction<Content: View>(_ content: Content) -> some View { ... }
}
private struct FlowLayoutRoot: _VariadicView_MultiViewRoot { ... }
```
Delete all of it. The `#Preview` block stays.

---

## Fix 2 — EditDietaryPrefsView.swift (CRITICAL CRASH)

**File:** `Features/Profile/EditDietaryPrefsView.swift`

**Problem:** Same `callAsFunction` pattern.

Find:
```swift
FlowLayout(spacing: 10)
    .callAsFunction {
        ForEach(DietaryPreference.allCases) { pref in
            DietChipView(
                preference: pref,
                isSelected: vm.selectedPreferences.contains(pref)
            ) {
                vm.togglePreference(pref)
            }
        }
    }
    .padding(.horizontal, 16)
```
Replace with:
```swift
FlowLayout(spacing: 10) {
    ForEach(DietaryPreference.allCases) { pref in
        DietChipView(
            preference: pref,
            isSelected: vm.selectedPreferences.contains(pref)
        ) {
            vm.togglePreference(pref)
        }
    }
}
.padding(.horizontal, 16)
```

---

## Fix 3 — GoalSelectionView.swift (UIKit import)

**File:** `Features/Onboarding/GoalSelectionView.swift`

**Problem:** File imports UIKit and manually creates `UISelectionFeedbackGenerator`. This is unnecessary — `GoalCard` already has `.sensoryFeedback(.selection, trigger: isSelected)`.

**Step 1:** Remove line 2:
```swift
import UIKit
```

**Step 2:** Find the action closure in the `ForEach(WeightGoal.allCases)` loop:
```swift
) {
    let generator = UISelectionFeedbackGenerator()
    generator.selectionChanged()
    withAnimation(.spring(duration: 0.3, bounce: 0.2)) {
        vm.weightGoal = goal
    }
}
```
Replace with:
```swift
) {
    withAnimation(.spring(duration: 0.3, bounce: 0.2)) {
        vm.weightGoal = goal
    }
}
```

---

## Fix 4 — APIService.swift (missing timeout)

**File:** `Services/APIService.swift`

**Problem:** `URLRequest.timeoutInterval` is not set on either POST request. The app can hang indefinitely waiting for the backend.

In `generateMealPlan`, after `var request = URLRequest(url: url)`, add:
```swift
request.timeoutInterval = 15
```

In `fetchRecommendations`, after `var request = URLRequest(url: url)`, add:
```swift
request.timeoutInterval = 15
```

Both POST functions should now start with:
```swift
var request = URLRequest(url: url)
request.httpMethod = "POST"
request.timeoutInterval = 15
request.setValue("application/json", forHTTPHeaderField: "Content-Type")
```

---

## Fix 5 — AgentMessageCardView.swift (conflicting animations)

**File:** `Components/AgentMessageCardView.swift`

**Problem:** `TypingDotsView` has two competing mechanisms both trying to animate `phase` at the same time:
- `.onAppear` uses `withAnimation(.repeatForever)` which locks `phase` in a perpetual tween toward `2`
- `.task` loop manually increments `phase` every 450ms

These fight each other and produce a glitchy dot animation.

Find the `TypingDotsView` body and replace the `.onAppear` + `.task` section:
```swift
.onAppear {
    guard !reduceMotion else { return }
    withAnimation(.easeInOut(duration: 0.45).repeatForever(autoreverses: true)) {
        phase = 2
    }
}
.task {
    guard !reduceMotion else { return }
    while !Task.isCancelled {
        try? await Task.sleep(nanoseconds: 450_000_000)
        withAnimation(.easeInOut(duration: 0.45)) {
            phase = (phase + 1) % 3
        }
    }
}
```
With only the `.task` loop (delete `.onAppear` entirely):
```swift
.task {
    guard !reduceMotion else { return }
    while !Task.isCancelled {
        try? await Task.sleep(nanoseconds: 450_000_000)
        guard !Task.isCancelled else { return }
        withAnimation(.easeInOut(duration: 0.35)) {
            phase = (phase + 1) % 3
        }
    }
}
```

---

## After all fixes

Run **Cmd+B** in Xcode. The build must complete with zero errors. If any error mentions `_VariadicView` or `callAsFunction`, check that the entire extension block was deleted from `DietaryPreferencesView.swift`.
