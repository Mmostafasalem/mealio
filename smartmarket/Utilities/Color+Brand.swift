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

extension UIColor {
    /// From 0xRRGGBB.
    convenience init(rgb: UInt32) {
        self.init(red: CGFloat(rgb >> 16 & 0xFF) / 255, green: CGFloat(rgb >> 8 & 0xFF) / 255,
                  blue: CGFloat(rgb & 0xFF) / 255, alpha: 1)
    }
}

extension Color {

    // Owner's supplied palette: Almond, Dull Pink, Rhino. "Quiet pantry" direction
    // (2026-11-13): Rhino ink carries text and the main button, Dull Pink marks
    // progress only, Almond tints the canvas. No gradients behind content.
    // Surface/text shades derive from these three anchors for accessible contrast.
    //
    // 27 Nov 2026: the accent and its tints follow the colour theme chosen in
    // Profile › Appearance (`AppTheme` in Shared/NourloTheme.swift, `ThemeStore`).
    // Each themed token reads `ThemeStore.shared`, which is @Observable, so a view
    // that draws one redraws the moment the theme changes. Nourlo Pink is the
    // default and keeps the original values exactly. Ink, Rhino and danger red
    // are the same in every theme.

    /// The pale accent tint (Almond in Nourlo Pink), drawn on Rhino.
    static var almond: Color { ThemeStore.shared.colors.soft }
    /// The accent fill (Dull Pink in Nourlo Pink): main buttons, selected chips, badges.
    static var dullPink: Color { ThemeStore.shared.colors.accent }
    static let rhino = Color(hex: "#1C1C1E")
    /// Ink on the accent: near-black on mid-tone accents, white on deep ones
    /// (Graphite, Royal Purple and Berry Red in light mode). Always ≥ 4.5:1.
    static var onAccent: Color { ThemeStore.shared.colors.onAccent }
    // Pink on almond is only 1.91:1: links use Rhino, not pink text.
    static let brandPrimary = Color(light: "#111111", dark: "#F4ECE9")
    static let brandDark = Color(light: "#111111", dark: "#F4ECE9")
    static let brandMid = Color(light: "#5C5C61", dark: "#C9C0BF")
    /// The light chip or selection background behind ink text.
    static var brandLight: Color { ThemeStore.shared.colors.tint }
    static let brandHeader = rhino
    static let brandHeaderMid = rhino
    // Warnings retain labels/icons; pink alone never communicates severity.
    static let brandAmber = brandPrimary
    static var brandAmberLight: Color { brandLight }
    static let brandDanger = Color(light: "#B4535F", dark: "#F0A0AA")
    static var brandDangerLight: Color { brandLight }
    static var calorieAccent: Color { progress }
    /// The accent is reserved for things filling up: rings, budget bars, ticks.
    static var progress: Color { ThemeStore.shared.colors.progress }
    /// Track behind a progress bar or ring.
    static var progressTrack: Color { ThemeStore.shared.colors.fill }
    // The Home rings: the accent with cool tones (mint, sky, violet), picked by the
    // owner on 16 Nov 2026. A macro ring moves only in a theme whose accent would
    // match it (see `AppTheme.palette`).
    static var ringCalories: Color { progress }
    static var ringProtein: Color { ThemeStore.shared.colors.ringProtein }
    static var ringCarbs: Color { ThemeStore.shared.colors.ringCarbs }
    static var ringFat: Color { ThemeStore.shared.colors.ringFat }
    static let proteinAccent = labelPrimary
    static let carbsAccent = labelPrimary
    static let fatAccent = labelPrimary
    static let labelPrimary = Color(light: "#111111", dark: "#F4ECE9")
    static let labelSecondary = Color(light: "#6E6E73", dark: "#A1A1A6")
    static let labelTertiary = Color(light: "#808085", dark: "#86868B")
    static let surface = Color(light: "#FFFFFF", dark: "#151516")
    // A light tint of the accent leaves content room to breathe.
    static var surfaceGrouped: Color { ThemeStore.shared.colors.canvas }
    static let surfaceElevated = Color(light: "#FFFFFF", dark: "#1C1C1E")
    static var surfaceSecondary: Color { ThemeStore.shared.colors.fill }
    static var hairline: Color { ThemeStore.shared.colors.hairline }
    // Decorative wash only; text and interactive color roles stay separate.
    static let grainBlue = Color(light: "#CFCFD4", dark: "#6E6E73")

    // MARK: - Adaptive convenience initialisers

    /// A colour with a theme's light and dark values.
    init(_ hex: ThemeHex) {
        let light = UIColor(rgb: hex.light), dark = UIColor(rgb: hex.dark)
        self = Color(UIColor { traits in traits.userInterfaceStyle == .dark ? dark : light })
    }

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
