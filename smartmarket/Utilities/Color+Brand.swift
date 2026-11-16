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

    // Owner's supplied palette: Almond, Dull Pink, Rhino. "Quiet pantry" direction
    // (2026-11-13): Rhino ink carries text and the main button, Dull Pink marks
    // progress only, Almond tints the canvas. No gradients behind content.
    // Surface/text shades derive from these three anchors for accessible contrast.
    static let almond = Color(hex: "#F4DAD4")
    static let dullPink = Color(hex: "#DD8C96")
    static let rhino = Color(hex: "#1C1C1E")
    // Near-black ink on Dull Pink (the owner replaced the navy with black on 16 Nov 2026).
    static let onAccent = Color(hex: "#111111")
    // Pink on almond is only 1.91:1: links use Rhino, not pink text.
    static let brandPrimary = Color(light: "#111111", dark: "#F4ECE9")
    static let brandDark = Color(light: "#111111", dark: "#F4ECE9")
    static let brandMid = Color(light: "#5C5C61", dark: "#C9C0BF")
    static let brandLight = Color(light: "#F6E1E3", dark: "#3A2830")
    static let brandHeader = rhino
    static let brandHeaderMid = rhino
    // Warnings retain labels/icons; pink alone never communicates severity.
    static let brandAmber = brandPrimary
    static let brandAmberLight = brandLight
    static let brandDanger = Color(light: "#B4535F", dark: "#F0A0AA")
    static let brandDangerLight = brandLight
    static let calorieAccent = progress
    /// Dull Pink is reserved for things filling up: rings, budget bars, ticks.
    static let progress = Color(light: "#DD8C96", dark: "#E89DA6")
    /// Track behind a progress bar or ring.
    static let progressTrack = Color(light: "#EFE8E6", dark: "#2C2C2E")
    // The Home rings: pink with cool tones (mint, sky, violet), picked by the owner on 16 Nov 2026.
    static let ringCalories = progress
    static let ringProtein = Color(light: "#1FA98C", dark: "#6FE0C8")
    static let ringCarbs = Color(light: "#2F8DE4", dark: "#6FB7FF")
    static let ringFat = Color(light: "#9A6BE0", dark: "#C9A2FF")
    static let proteinAccent = labelPrimary
    static let carbsAccent = labelPrimary
    static let fatAccent = labelPrimary
    static let labelPrimary = Color(light: "#111111", dark: "#F4ECE9")
    static let labelSecondary = Color(light: "#6E6E73", dark: "#A1A1A6")
    static let labelTertiary = Color(light: "#808085", dark: "#86868B")
    static let surface = Color(light: "#FFFFFF", dark: "#151516")
    // Almond is a brand accent; its lighter tint leaves content room to breathe.
    static let surfaceGrouped = Color(light: "#F8F4F2", dark: "#000000")
    static let surfaceElevated = Color(light: "#FFFFFF", dark: "#1C1C1E")
    static let surfaceSecondary = Color(light: "#EFE8E6", dark: "#2C2C2E")
    static let hairline = Color(light: "#ECE5E2", dark: "#303033")
    // Decorative wash only; text and interactive color roles stay separate.
    static let grainBlue = Color(light: "#CFCFD4", dark: "#6E6E73")

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
