import Foundation

// MARK: - Colour themes, shared by the app and its widgets
//
// Plain values only (sRGB hex numbers), so both targets can read them. The app turns
// them into its `Color` tokens in `Utilities/Color+Brand.swift`; the widgets in
// `NourloWidgets/WidgetTheme.swift`.

/// One colour with its light- and dark-mode values, as 0xRRGGBB.
nonisolated struct ThemeHex: Equatable, Sendable {
    var light: UInt32
    var dark: UInt32

    init(_ light: UInt32, _ dark: UInt32) { self.light = light; self.dark = dark }
    /// The same value in both modes.
    init(_ both: UInt32) { self.init(both, both) }
}

/// Everything a theme changes. Text ink, danger red and the Rhino surfaces stay the
/// same in every theme; only the accent and its tints move.
nonisolated struct ThemePalette: Equatable, Sendable {
    /// The accent fill: main buttons, selected chips, badges ("dullPink" in code).
    var accent: ThemeHex
    /// Text and icons drawn on `accent` (WCAG AA ≥ 4.5:1 against it, both modes).
    var onAccent: ThemeHex
    /// Rings, bars and ticks filling up.
    var progress: ThemeHex
    /// A pale tint of the accent, drawn on dark Rhino (toasts, the welcome title).
    var soft: ThemeHex
    /// The light chip or selection background behind ink text.
    var tint: ThemeHex
    /// The grouped canvas behind cards.
    var canvas: ThemeHex
    /// Secondary fills and the track behind a bar or ring.
    var fill: ThemeHex
    /// Thin separators.
    var hairline: ThemeHex
    /// The Home macro rings. They change only where a macro would match the accent.
    var ringProtein: ThemeHex
    var ringCarbs: ThemeHex
    var ringFat: ThemeHex
}

/// The colour themes offered in Profile › Appearance. Raw values are stored.
nonisolated enum AppTheme: String, CaseIterable, Codable, Identifiable, Sendable {
    case pink, ocean, forest, graphite, sunset, purple, teal, berry

    static let `default`: AppTheme = .pink
    /// `UserDefaults` key, in the app's own defaults and in the App Group.
    static let storageKey = "appTheme_v1"

    var id: String { rawValue }

    var name: String {
        switch self {
        case .pink: return "Nourlo Pink"
        case .ocean: return "Ocean Blue"
        case .forest: return "Forest Green"
        case .graphite: return "Graphite"
        case .sunset: return "Sunset Orange"
        case .purple: return "Royal Purple"
        case .teal: return "Teal"
        case .berry: return "Berry Red"
        }
    }

    // Macro ring defaults (mint, sky, violet), and the replacements where they'd clash.
    private static let mint = ThemeHex(0x1FA98C, 0x6FE0C8)
    private static let sky = ThemeHex(0x2F8DE4, 0x6FB7FF)
    private static let violet = ThemeHex(0x9A6BE0, 0xC9A2FF)
    private static let gold = ThemeHex(0xD99A1E, 0xF2C14E)
    private static let rose = ThemeHex(0xDD8C96, 0xE89DA6)

    // Dark mode keeps the same neutral surfaces in every theme.
    private static func surfaces(canvas: UInt32, fill: UInt32, hairline: UInt32) -> (ThemeHex, ThemeHex, ThemeHex) {
        (ThemeHex(canvas, 0x000000), ThemeHex(fill, 0x2C2C2E), ThemeHex(hairline, 0x303033))
    }

    var palette: ThemePalette {
        switch self {
        case .pink:
            // The original palette, value for value.
            let s = Self.surfaces(canvas: 0xF8F4F2, fill: 0xEFE8E6, hairline: 0xECE5E2)
            return ThemePalette(accent: ThemeHex(0xDD8C96), onAccent: ThemeHex(0x111111),
                                progress: ThemeHex(0xDD8C96, 0xE89DA6), soft: ThemeHex(0xF4DAD4),
                                tint: ThemeHex(0xF6E1E3, 0x3A2830), canvas: s.0, fill: s.1, hairline: s.2,
                                ringProtein: Self.mint, ringCarbs: Self.sky, ringFat: Self.violet)
        case .ocean:
            let s = Self.surfaces(canvas: 0xF3F6FA, fill: 0xE6ECF3, hairline: 0xE2E8EF)
            return ThemePalette(accent: ThemeHex(0x4F92E3, 0x6FA9F0), onAccent: ThemeHex(0x0A0A0A),
                                progress: ThemeHex(0x4F92E3, 0x6FA9F0), soft: ThemeHex(0xD6E6FA),
                                tint: ThemeHex(0xDDEAF9, 0x1E2E44), canvas: s.0, fill: s.1, hairline: s.2,
                                ringProtein: Self.mint, ringCarbs: Self.gold, ringFat: Self.violet)
        case .forest:
            let s = Self.surfaces(canvas: 0xF3F7F4, fill: 0xE5EDE7, hairline: 0xE1E9E3)
            return ThemePalette(accent: ThemeHex(0x4E9F68, 0x69B985), onAccent: ThemeHex(0x0A0A0A),
                                progress: ThemeHex(0x4E9F68, 0x69B985), soft: ThemeHex(0xD5EBDC),
                                tint: ThemeHex(0xDCEFE2, 0x1F3527), canvas: s.0, fill: s.1, hairline: s.2,
                                ringProtein: Self.rose, ringCarbs: Self.sky, ringFat: Self.violet)
        case .graphite:
            let s = Self.surfaces(canvas: 0xF4F4F6, fill: 0xE8E8EC, hairline: 0xE4E4E8)
            return ThemePalette(accent: ThemeHex(0x2C2C2E, 0xD1D1D6), onAccent: ThemeHex(0xFFFFFF, 0x111111),
                                progress: ThemeHex(0x3A3A3C, 0xD1D1D6), soft: ThemeHex(0xE5E5EA),
                                tint: ThemeHex(0xE6E6EA, 0x2E2E31), canvas: s.0, fill: s.1, hairline: s.2,
                                ringProtein: Self.mint, ringCarbs: Self.sky, ringFat: Self.violet)
        case .sunset:
            let s = Self.surfaces(canvas: 0xF9F5F1, fill: 0xF0E8E1, hairline: 0xEDE4DC)
            return ThemePalette(accent: ThemeHex(0xEE8A4E, 0xF49C64), onAccent: ThemeHex(0x111111),
                                progress: ThemeHex(0xEE8A4E, 0xF49C64), soft: ThemeHex(0xFBE0CC),
                                tint: ThemeHex(0xFCE6D6, 0x3D2A1C), canvas: s.0, fill: s.1, hairline: s.2,
                                ringProtein: Self.mint, ringCarbs: Self.sky, ringFat: Self.violet)
        case .purple:
            let s = Self.surfaces(canvas: 0xF6F4FA, fill: 0xEAE6F3, hairline: 0xE6E1EF)
            return ThemePalette(accent: ThemeHex(0x7D5BD3, 0xB39CF2), onAccent: ThemeHex(0xFFFFFF, 0x111111),
                                progress: ThemeHex(0x7D5BD3, 0xB39CF2), soft: ThemeHex(0xE3DAFA),
                                tint: ThemeHex(0xE7DFFA, 0x2C2342), canvas: s.0, fill: s.1, hairline: s.2,
                                ringProtein: Self.mint, ringCarbs: Self.sky, ringFat: Self.rose)
        case .teal:
            let s = Self.surfaces(canvas: 0xF2F7F7, fill: 0xE3EDEC, hairline: 0xDFE9E8)
            return ThemePalette(accent: ThemeHex(0x2AA19C, 0x4BC0BA), onAccent: ThemeHex(0x0A0A0A),
                                progress: ThemeHex(0x2AA19C, 0x4BC0BA), soft: ThemeHex(0xD3EEEC),
                                tint: ThemeHex(0xD8F0EE, 0x173533), canvas: s.0, fill: s.1, hairline: s.2,
                                ringProtein: Self.rose, ringCarbs: Self.sky, ringFat: Self.violet)
        case .berry:
            let s = Self.surfaces(canvas: 0xF9F3F4, fill: 0xF0E5E7, hairline: 0xECE0E2)
            return ThemePalette(accent: ThemeHex(0xC0354D, 0xEE7C8C), onAccent: ThemeHex(0xFFFFFF, 0x111111),
                                progress: ThemeHex(0xC0354D, 0xEE7C8C), soft: ThemeHex(0xF6D5DA),
                                tint: ThemeHex(0xF8DDE2, 0x3D1D24), canvas: s.0, fill: s.1, hairline: s.2,
                                ringProtein: Self.mint, ringCarbs: Self.sky, ringFat: Self.violet)
        }
    }
}

/// Reads and writes the chosen theme. The app keeps its own copy and mirrors it into
/// the App Group, where the widgets read it. A missing or unknown value is pink.
nonisolated enum AppThemeStorage {
    static func load(from defaults: UserDefaults?) -> AppTheme {
        defaults?.string(forKey: AppTheme.storageKey).flatMap(AppTheme.init(rawValue:)) ?? .default
    }

    static func save(_ theme: AppTheme, to defaults: UserDefaults?) {
        defaults?.set(theme.rawValue, forKey: AppTheme.storageKey)
    }

    /// The theme for the widgets: the App Group copy.
    static var shared: AppTheme { load(from: NourloAppGroup.defaults) }
}

// MARK: - Contrast (WCAG 2.x relative luminance)

nonisolated enum ThemeContrast {
    static func luminance(_ hex: UInt32) -> Double {
        func channel(_ v: UInt32) -> Double {
            let c = Double(v) / 255
            return c <= 0.04045 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * channel(hex >> 16 & 0xFF) + 0.7152 * channel(hex >> 8 & 0xFF) + 0.0722 * channel(hex & 0xFF)
    }

    static func ratio(_ a: UInt32, _ b: UInt32) -> Double {
        let la = luminance(a), lb = luminance(b)
        return (max(la, lb) + 0.05) / (min(la, lb) + 0.05)
    }
}
