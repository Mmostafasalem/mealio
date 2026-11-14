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
    static let rhino = Color(hex: "#2E4060")
    // Rhino's darker text shade gives 4.99:1 contrast on exact Dull Pink.
    static let onAccent = Color(hex: "#24334D")
    // Pink on almond is only 1.91:1: links use Rhino, not pink text.
    static let brandPrimary = Color(light: "#1E2A40", dark: "#F4ECE9")
    static let brandDark = Color(light: "#1E2A40", dark: "#F4ECE9")
    static let brandMid = Color(light: "#52617A", dark: "#C9C0BF")
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
    static let progressTrack = Color(light: "#EFE8E6", dark: "#243042")
    static let proteinAccent = labelPrimary
    static let carbsAccent = labelPrimary
    static let fatAccent = labelPrimary
    static let labelPrimary = Color(light: "#1E2A40", dark: "#F4ECE9")
    static let labelSecondary = Color(light: "#6B7385", dark: "#9AA3B5")
    static let labelTertiary = Color(light: "#7E8494", dark: "#7F899C")
    static let surface = Color(light: "#FFFFFF", dark: "#19212E")
    // Almond is a brand accent; its lighter tint leaves content room to breathe.
    static let surfaceGrouped = Color(light: "#F8F4F2", dark: "#10161F")
    static let surfaceElevated = Color(light: "#FFFFFF", dark: "#1E2736")
    static let surfaceSecondary = Color(light: "#EFE8E6", dark: "#243042")
    static let hairline = Color(light: "#ECE5E2", dark: "#2A3443")
    // Decorative wash only; text and interactive color roles stay separate.
    static let grainBlue = Color(light: "#B6C8DF", dark: "#6C83AA")

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
