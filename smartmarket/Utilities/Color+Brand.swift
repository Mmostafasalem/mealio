import SwiftUI

// MARK: - Adaptive color helper

private extension UIColor {
    convenience init(hex: String) {
        let h = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: h).scanHexInt64(&int)
        let r, g, b: UInt64
        switch h.count {
        case 6: (r, g, b) = (int >> 16, int >> 8 & 0xFF, int & 0xFF)
        default: (r, g, b) = (0, 0, 0)
        }
        self.init(red: CGFloat(r) / 255, green: CGFloat(g) / 255, blue: CGFloat(b) / 255, alpha: 1)
    }
}

extension Color {

    // MARK: - Brand palette
    //
    // Base hue: #4b5760  (H 206 · S 12 · L 34) — cool blue-gray slate
    //
    // Light-mode colours are dark enough to work on white.
    // Dark-mode colours are light enough to work on near-black.

    /// Primary interactive colour — buttons, rings, active tab, links.
    /// Vibrant green for a premium "on black" feel.
    static let brandPrimary = Color(light: "#1A9E48", dark: "#1ED760")

    /// Darker pressed / gradient shade.
    static let brandDark = Color(light: "#15803D", dark: "#17B84F")

    /// Lighter secondary accent — icons, sub-headings.
    static let brandMid = Color(light: "#6b7d87", dark: "#a8bfc7")

    /// Soft tint — chip backgrounds, subtle row fills.
    static let brandLight = Color(light: "#e2e8ec", dark: "#2a3840")

    /// Hero header gradient — deepest dark (start).
    static let brandHeader = Color(light: "#1a2127", dark: "#0d1519")

    /// Hero header gradient — mid-point.
    static let brandHeaderMid = Color(light: "#2c3a42", dark: "#192430")

    // MARK: - Functional colours (unchanged — they carry semantic meaning)

    /// Amber — discount badges, warnings, "good but not there yet".
    static let brandAmber = Color(light: "#d97706", dark: "#f5a623")

    /// Soft amber fill — badge backgrounds.
    static let brandAmberLight = Color(light: "#fef3c7", dark: "#3d2d10")

    /// Red — over-limit calories, errors, destructive actions.
    static let brandDanger = Color(light: "#dc2626", dark: "#ff6b6b")

    /// Soft red fill.
    static let brandDangerLight = Color(light: "#fee2e2", dark: "#3d1010")

    // MARK: - Semantic nutrition tokens (calorie + macros)
    //
    // Distinct, accessible hues so Protein / Carbs / Fat are instantly
    // distinguishable on the dashboard, tuned for both light and dark mode.

    /// Energetic green — calories / remaining energy.
    static let calorieAccent = Color(light: "#16a34a", dark: "#4ade80")

    /// Vibrant orange — protein.
    static let proteinAccent = Color(light: "#ea580c", dark: "#fb923c")

    /// Amber — carbohydrates.
    static let carbsAccent = Color(light: "#d97706", dark: "#fbbf24")

    /// Violet — fat.
    static let fatAccent = Color(light: "#7c3aed", dark: "#a78bfa")

    // MARK: - Neutral text (resolved by the system — always correct)

    static let labelPrimary   = Color(.label)
    static let labelSecondary = Color(.secondaryLabel)
    static let labelTertiary  = Color(.tertiaryLabel)

    // MARK: - Surfaces (resolved by the system — always correct)

    static let surface          = Color(.systemBackground)
    static let surfaceGrouped   = Color(.systemGroupedBackground)
    static let surfaceElevated  = Color(.secondarySystemBackground)
    static let surfaceSecondary = Color(.secondarySystemBackground)

    // MARK: - Adaptive convenience initialiser

    private init(light lightHex: String, dark darkHex: String) {
        self = Color(UIColor { traits in
            traits.userInterfaceStyle == .dark
                ? UIColor(hex: darkHex)
                : UIColor(hex: lightHex)
        })
    }

    // MARK: - Hex initialiser (non-adaptive, for one-off colours)

    init(hex: String) {
        let h = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: h).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch h.count {
        case 3:
            (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6:
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8:
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (255, 0, 0, 0)
        }
        self.init(
            .sRGB,
            red:     Double(r) / 255,
            green:   Double(g) / 255,
            blue:    Double(b) / 255,
            opacity: Double(a) / 255
        )
    }
}
