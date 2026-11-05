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

    // Ink + White + Coral. Neutral values are tonal derivatives, not extra accents.
    // Coral is reserved for interaction, progress and explicit warning states.
    static let ink = Color(hex: "#18181B")
    static let paper = Color(hex: "#FFFFFF")
    static let coral = Color(hex: "#FF7868")
    static let onAccent = ink
    static let brandPrimary = Color(light: "#B6372B", dark: "#FF9385")
    static let brandDark = Color(light: "#992C23", dark: "#FF9385")
    static let brandMid = Color(light: "#626268", dark: "#B7B7BD")
    static let brandLight = Color(light: "#F8E8E5", dark: "#382624")
    static let brandHeader = ink
    static let brandHeaderMid = ink
    // Warnings always retain labels and icons; color is never the only signal.
    static let brandAmber = brandPrimary
    static let brandAmberLight = brandLight
    static let brandDanger = brandPrimary
    static let brandDangerLight = brandLight
    static let calorieAccent = brandPrimary
    // Macro names, symbols and values distinguish categories without a rainbow.
    static let proteinAccent = labelPrimary
    static let carbsAccent = labelPrimary
    static let fatAccent = labelPrimary
    static let labelPrimary = Color(light: "#18181B", dark: "#FAFAFA")
    static let labelSecondary = Color(light: "#626268", dark: "#B7B7BD")
    static let labelTertiary = Color(light: "#717178", dark: "#A1A1AA")
    static let surface = Color(light: "#FFFFFF", dark: "#18181B")
    static let surfaceGrouped = Color(light: "#F6F6F7", dark: "#111113")
    static let surfaceElevated = Color(light: "#FFFFFF", dark: "#202023")
    static let surfaceSecondary = Color(light: "#F0F0F2", dark: "#29292D")
    static let hairline = Color(light: "#E4E4E7", dark: "#3A3A40")

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
