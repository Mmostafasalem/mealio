import SwiftUI

// MARK: - Brand color palette
extension Color {
    /// Primary pink — buttons, active states, accents
    static let brandPrimary    = Color(hex: "#E8698A")
    /// Darker pink — navigation bars, headers
    static let brandDark       = Color(hex: "#C94E70")
    /// Amber — discounts, savings badges, warnings
    static let brandAmber      = Color(hex: "#EF9F27")
    /// Soft amber fill — chip backgrounds, amber cards
    static let brandAmberLight = Color(hex: "#FAEEDA")
    /// Danger red — calorie over-limit, error states
    static let brandDanger     = Color(hex: "#E24B4A")
}

// MARK: - Hex initialiser
extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let r, g, b: UInt64
        switch hex.count {
        case 6:
            (r, g, b) = ((int >> 16) & 0xFF, (int >> 8) & 0xFF, int & 0xFF)
        default:
            (r, g, b) = (0, 0, 0)
        }
        self.init(
            .sRGB,
            red:   Double(r) / 255,
            green: Double(g) / 255,
            blue:  Double(b) / 255,
            opacity: 1
        )
    }
}

// MARK: - Semantic shortcuts
extension Color {
    static var surface: Color          { Color(.systemBackground) }
    static var surfaceSecondary: Color { Color(.secondarySystemBackground) }
    static var surfaceGrouped: Color   { Color(.systemGroupedBackground) }
    static var labelSecondary: Color   { Color(.secondaryLabel) }
    static var labelTertiary: Color    { Color(.tertiaryLabel) }
}
