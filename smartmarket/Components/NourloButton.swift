import SwiftUI

// MARK: - Nourlo, the quick-actions button
//
// Owner, 28 Nov 2026: "make the Nourlo on top the quick action button and remove
// that one down on the right". The animated bowl at the top right of Home (and of
// Meals, Shop and Train) is the one way into the quick actions. It looks and moves
// exactly as the old header bowl did: it breathes and blinks, strikes a pose every
// few seconds, thinks while a meal plan is being written, celebrates a logged meal
// and shows the streak badge. Tapping it makes it hop and drops the action pills
// down from under it (`QuickActionsMenu`); tapping it again closes them.

/// Whether the quick-actions pills are open, and where the Nourlo that opened them is.
@MainActor
@Observable
final class QuickActionsCenter {
    static let shared = QuickActionsCenter()

    /// The pills are on screen (or animating away).
    private(set) var isOpen = false
    /// The tapped Nourlo's frame in global coordinates; the pills hang under it.
    private(set) var anchor: CGRect = .zero
    /// Bumped to ask the open menu to play its closing animation.
    private(set) var closeRequests = 0
    /// Bumped each time the menu opens (haptic, Nourlo's hop).
    private(set) var opens = 0
    /// Where the visible Nourlo is, for an opening that doesn't come from a tap (the tour).
    @ObservationIgnored private var lastAnchor: CGRect = .zero

    func toggle(from frame: CGRect) {
        if isOpen { requestClose() } else { open(from: frame) }
    }

    func open(from frame: CGRect? = nil) {
        guard !isOpen else { return }
        let source = frame ?? lastAnchor
        anchor = source == .zero ? Self.fallbackAnchor : source
        isOpen = true
        opens &+= 1
    }

    /// Plays the closing animation; the menu calls `didClose` when it is done.
    func requestClose() {
        guard isOpen else { return }
        closeRequests &+= 1
    }

    func didClose() { isOpen = false }

    func report(_ frame: CGRect) {
        guard frame.width > 1 else { return }
        lastAnchor = frame
        // Follows Nourlo while it settles (the tour scrolls Home to the top as the pills open).
        if isOpen, frame != anchor { anchor = frame }
    }

    /// The top right corner, for the rare opening before any Nourlo was laid out.
    private static var fallbackAnchor: CGRect {
        let width = UIScreen.main.bounds.width
        return CGRect(x: width - 72, y: 60, width: 56, height: 44)
    }
}

/// The animated Nourlo that opens the quick actions. Home puts it in its header;
/// Meals, Shop and Train put it in their navigation bar (`NourloToolbarItem`).
struct NourloButton: View {
    @State private var pose = 0
    @State private var celebrating = false
    @State private var loop = DailyLoopStore.shared
    @State private var center = QuickActionsCenter.shared
    @State private var frame: CGRect = .zero
    @State private var owner = UUID()
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Writing a meal plan wins, then the open menu, then a fresh win, then how the streak is doing.
    private var mood: MascotMood {
        if AppState.shared.isGeneratingMealPlan { return .thinking }
        if center.isOpen { return .happy }
        if celebrating { return .celebrate }
        return loop.state.mood
    }

    private func celebrate() {
        celebrating = true
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(1.8))
            celebrating = false
        }
    }

    var body: some View {
        MascotGuideView(mood: mood, size: 44, onTap: {
            center.toggle(from: frame)
        }, trigger: pose,
           hint: center.isOpen ? "Closes quick actions" : "Opens chat, voice commands, shortcuts and the tour",
           label: "Quick actions",
           identifier: "navigation.quickActions")
            // The character's own padding makes a 68 pt button; keep the row at 44.
            .frame(width: 56, height: 44)
            .accessibilityValue(center.isOpen ? "Open" : "")
            .overlay(alignment: .bottomTrailing) {
                if loop.state.streak > 0 && !center.isOpen {
                    Text("\(loop.state.streak)" as String)
                        .font(.system(.caption2, design: .rounded).weight(.heavy).monospacedDigit())
                        .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
                        .foregroundStyle(Color.onAccent)
                        .padding(.horizontal, 5)
                        .frame(minWidth: 18, minHeight: 18)
                        .background(Color.progress, in: Capsule())
                        .overlay(Capsule().strokeBorder(Color.surfaceGrouped, lineWidth: 2))
                        .contentTransition(.numericText())
                        .offset(x: 2, y: 2)
                        .accessibilityLabel("\(loop.state.streak)-day streak" as String)
                        .accessibilityIdentifier("home.streakBadge")
                        .allowsHitTesting(false)
                        .transition(.scale.combined(with: .opacity))
                }
            }
            .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { new in
                frame = new
                center.report(new)
                GuidedTour.shared.report(.nourlo, frame: new, owner: owner)
            }
            .onDisappear { GuidedTour.shared.remove(.nourlo, owner: owner) }
            // A happy hop as the pills drop out of it.
            .onChange(of: center.opens) { _, _ in pose += 1 }
            .onChange(of: FoodLogStore.shared.entries.count) { old, new in
                guard new > old else { return }
                celebrate()
            }
            .onChange(of: loop.lastCompletion) { _, _ in celebrate() }
            .onChange(of: loop.pendingMilestone) { _, days in if days != nil { celebrate() } }
            .task {
                // A fresh pose now and then; it rests in between.
                guard !reduceMotion else { return }
                while !Task.isCancelled {
                    try? await Task.sleep(for: .seconds(7))
                    guard !Task.isCancelled else { return }
                    if !center.isOpen { pose += 1 }
                }
            }
    }
}

/// Nourlo at the trailing end of a tab's navigation bar, without the iOS 26 glass
/// bubble, so it looks the same as on Home.
struct NourloToolbarItem: ToolbarContent {
    var body: some ToolbarContent {
        if #available(iOS 26.0, *) {
            ToolbarItem(placement: .topBarTrailing) { NourloButton() }
                .sharedBackgroundVisibility(.hidden)
        } else {
            ToolbarItem(placement: .topBarTrailing) { NourloButton() }
        }
    }
}
