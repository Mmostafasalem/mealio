import SwiftUI

/// Opaque, static brand color washes. The cached grain sits behind content and
/// never participates in touch handling or the accessibility tree.
struct GrainyGradient: View {
    enum Surface { case canvas, card, hero, welcome }
    var surface: Surface = .canvas
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.colorSchemeContrast) private var contrast

    private var dark: Bool { colorScheme == .dark || surface == .welcome }
    private var base: Color {
        switch surface {
        case .canvas: return .surfaceGrouped
        case .card, .hero: return .surfaceElevated
        case .welcome: return .rhino
        }
    }
    private var strength: Double {
        switch surface {
        case .canvas: return dark ? 0.09 : 0.22
        case .card: return dark ? 0.06 : 0.10
        case .hero: return dark ? 0.14 : 0.30
        case .welcome: return 0.22
        }
    }

    /// Flat canvas in the "Quiet pantry" palette (2026-11-13): the colour washes
    /// and grain are retired so the colours match the approved mockup.
    var body: some View {
        base
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}

private enum GrainTexture {
    /// A small, deterministic monochrome tile generated once, with no network
    /// assets, animation loop, or per-frame random-number generation.
    static let image: CGImage = {
        let size = 256
        var seed: UInt32 = 0x4E4F5552
        let pixels = (0..<(size * size)).map { _ -> UInt8 in
            seed ^= seed << 13
            seed ^= seed >> 17
            seed ^= seed << 5
            return UInt8(truncatingIfNeeded: seed)
        }
        let provider = CGDataProvider(data: Data(pixels) as CFData)!
        return CGImage(width: size, height: size, bitsPerComponent: 8, bitsPerPixel: 8,
                       bytesPerRow: size, space: CGColorSpaceCreateDeviceGray(),
                       bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.none.rawValue),
                       provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent)!
    }()
}
