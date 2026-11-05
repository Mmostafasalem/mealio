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

    // Owner's supplied palette: Almond, Dull Pink, Rhino.
    // Surface/text shades derive from these three anchors for accessible contrast.
    static let almond = Color(hex: "#F4DAD4")
    static let dullPink = Color(hex: "#DD8C96")
    static let rhino = Color(hex: "#2E4060")
    // Rhino's darker text shade gives 4.99:1 contrast on exact Dull Pink.
    static let onAccent = Color(hex: "#24334D")
    // Pink on almond is only 1.91:1: links use Rhino, not pink text.
    static let brandPrimary = Color(light: "#2E4060", dark: "#F4DAD4")
    static let brandDark = Color(light: "#24334D", dark: "#F4DAD4")
    static let brandMid = Color(light: "#52617A", dark: "#D8C7C6")
    static let brandLight = Color(light: "#EAC0C1", dark: "#48516D")
    static let brandHeader = rhino
    static let brandHeaderMid = rhino
    // Warnings retain labels/icons; pink alone never communicates severity.
    static let brandAmber = brandPrimary
    static let brandAmberLight = brandLight
    static let brandDanger = brandPrimary
    static let brandDangerLight = brandLight
    static let calorieAccent = brandPrimary
    static let proteinAccent = labelPrimary
    static let carbsAccent = labelPrimary
    static let fatAccent = labelPrimary
    static let labelPrimary = Color(light: "#2E4060", dark: "#F4DAD4")
    static let labelSecondary = Color(light: "#52617A", dark: "#D8C7C6")
    static let labelTertiary = Color(light: "#58637A", dark: "#C9BABB")
    static let surface = Color(light: "#FCF3F0", dark: "#24334D")
    static let surfaceGrouped = Color(light: "#F4DAD4", dark: "#1E2B42")
    static let surfaceElevated = Color(light: "#FCF3F0", dark: "#2E4060")
    static let surfaceSecondary = Color(light: "#EED0CD", dark: "#3A4966")
    static let hairline = Color(light: "#C6B4B8", dark: "#617089")

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
