import SwiftUI

// MARK: - Design tokens
//
// A single source of truth for spacing, corner radii, elevation and typography.
// Views should reference these instead of scattering magic numbers, so every
// card, chip and gap reads consistently across the app. Colours live in
// `Color+Brand.swift`; card/press surfaces live in `ViewModifiers.swift`.

/// 4-pt spacing scale. Use for padding, stack spacing and insets everywhere.
enum Spacing {
    /// 4
    static let xs: CGFloat = 4
    /// 8
    static let sm: CGFloat = 8
    /// 12
    static let md: CGFloat = 12
    /// 16 — default screen / card padding.
    static let lg: CGFloat = 16
    /// 24 — section separation.
    static let xl: CGFloat = 24
    /// 32 — large hero spacing.
    static let xxl: CGFloat = 32
}

/// Corner radii. Kept in sync with `premiumCard(radius: Radius.card)` so surfaces match.
enum Radius {
    /// 12 — chips, small controls, badges.
    static let chip: CGFloat = 12
    /// 16 — inner tiles, secondary cards.
    static let tile: CGFloat = 16
    /// 20 — primary cards (matches `premiumCard`).
    static let card: CGFloat = 20
    /// 28 — sheets and large containers.
    static let sheet: CGFloat = 28
    /// Fully rounded (pills / circular buttons).
    static let pill: CGFloat = 999
}

/// Soft elevation presets — a consistent shadow language.
enum Elevation {
    struct Shadow {
        let color: Color
        let radius: CGFloat
        let y: CGFloat
    }
    /// Subtle lift for chips / small controls.
    static let low  = Shadow(color: .black.opacity(0.04), radius: 3,  y: 1)
    /// Standard card elevation.
    static let card = Shadow(color: .black.opacity(0.04), radius: 3, y: 2)
    /// Floating overlays, banners, sheets.
    static let high = Shadow(color: .black.opacity(0.10), radius: 16, y: 6)
}

extension View {
    /// Applies an `Elevation` preset as a shadow.
    func elevation(_ shadow: Elevation.Shadow) -> some View {
        self.shadow(color: shadow.color, radius: shadow.radius, x: 0, y: shadow.y)
    }

    /// Standard minimum 44×44pt hit target for small icon buttons.
    func minTapTarget() -> some View {
        self.frame(minWidth: 44, minHeight: 44)
    }
}

// MARK: - Typography
//
// Always Dynamic-Type-driven text styles (never fixed sizes that clip at large
// accessibility settings). These are semantic roles, not sizes.

extension Font {
    /// Screen / hero titles.
    static let screenTitle    = Font.largeTitle.weight(.bold)
    /// Card + section titles.
    static let sectionTitle   = Font.title3.weight(.semibold)
    /// Emphasised numeric readouts (calories, prices).
    static let statValue      = Font.title2.weight(.bold).monospacedDigit()
    /// Standard body copy.
    static let bodyText       = Font.body
    /// Secondary / caption copy.
    static let captionText    = Font.footnote
}

// MARK: - Motion
//
// A shared, restrained motion vocabulary. Prefer these over ad-hoc timings so
// state changes feel consistent (150–300ms, spring/ease only).

extension Animation {
    /// Quick, snappy response for value changes (numbers, toggles).
    static let snappyValue = Animation.spring(response: 0.28, dampingFraction: 0.82)
    /// Gentle card / section transitions.
    static let smoothCard  = Animation.spring(response: 0.42, dampingFraction: 0.85)
    /// Reduce Motion: keep a short fade so state changes stay readable, drop movement.
    static let reducedFade = Animation.easeOut(duration: 0.2)
}
