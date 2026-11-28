import SwiftUI
import WidgetKit

/// A theme's palette as SwiftUI colours (each one adapts to light and dark mode).
struct ThemeColors {
    let accent, onAccent, progress, soft, tint, canvas, fill, hairline: Color
    let ringProtein, ringCarbs, ringFat: Color

    init(_ p: ThemePalette) {
        accent = Color(p.accent); onAccent = Color(p.onAccent); progress = Color(p.progress)
        soft = Color(p.soft); tint = Color(p.tint); canvas = Color(p.canvas)
        fill = Color(p.fill); hairline = Color(p.hairline)
        ringProtein = Color(p.ringProtein); ringCarbs = Color(p.ringCarbs); ringFat = Color(p.ringFat)
    }
}

/// The colour theme the person chose in Profile › Appearance.
///
/// The brand `Color` tokens (`Color.dullPink`, `.progress`, `.brandLight` …) read
/// `colors` from here. Because the store is `@Observable`, any view whose body drew
/// a themed token is redrawn when `theme` changes: the switch is instant, with no
/// restart and no reset of navigation or tabs.
@Observable
final class ThemeStore {
    static let shared = ThemeStore()

    var theme: AppTheme {
        didSet {
            guard theme != oldValue else { return }
            colors = Self.colors(for: theme)
            AppThemeStorage.save(theme, to: defaults)
            // The widgets read their accent from the App Group.
            AppThemeStorage.save(theme, to: sharedDefaults)
            if sharedDefaults != nil { WidgetCenter.shared.reloadAllTimelines() }
        }
    }

    private(set) var colors: ThemeColors

    @ObservationIgnored private let defaults: UserDefaults?
    @ObservationIgnored private let sharedDefaults: UserDefaults?

    init(defaults: UserDefaults? = .standard, sharedDefaults: UserDefaults? = NourloAppGroup.defaults) {
        self.defaults = defaults
        self.sharedDefaults = sharedDefaults
        let saved = AppThemeStorage.load(from: defaults)
        theme = saved
        colors = Self.colors(for: saved)
        // Keep the widgets' copy in step (an update from before themes, or a restore).
        if AppThemeStorage.load(from: sharedDefaults) != saved { AppThemeStorage.save(saved, to: sharedDefaults) }
    }

    /// UIKit's own tint (alerts, menus, anything outside SwiftUI's `.tint`): ink in
    /// light mode and the theme's pale tint in dark mode, as AccentColor is for pink.
    func applyWindowTint() {
        let soft = UIColor(rgb: theme.palette.soft.dark), ink = UIColor(rgb: 0x111111)
        let tint = UIColor { $0.userInterfaceStyle == .dark ? soft : ink }
        for case let scene as UIWindowScene in UIApplication.shared.connectedScenes {
            for window in scene.windows { window.tintColor = tint }
        }
    }

    private static var cache: [AppTheme: ThemeColors] = [:]

    static func colors(for theme: AppTheme) -> ThemeColors {
        if let hit = cache[theme] { return hit }
        let made = ThemeColors(theme.palette)
        cache[theme] = made
        return made
    }
}
