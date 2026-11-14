import SwiftUI

// MARK: - Mascot extras
//
// The little things around Nourlo that say how it feels: thought dots while it
// works, confetti when it celebrates, Zzz when it sleeps, a sweat drop when
// something went wrong, hearts when it loves something. Each fades with its
// pose value, so moods blend; drift follows `pose.time`, which stops while the
// rig rests (and under Reduce Motion), leaving the extras still. Loops fade
// to nothing where they wrap, and start mid-loop so a still frame shows them.
//
// Drawn in the 512-point design space. The canvas reaches 128 points past every
// edge of the box (see `MascotFigure`), so extras may sit above the rim.

enum MascotExtras {
    private typealias P = MascotPalette

    static let heart: Path = {
        var h = Path()
        h.move(to: CGPoint(x: 0, y: 22))
        h.addCurve(to: CGPoint(x: -26, y: -8), control1: CGPoint(x: -14, y: 12), control2: CGPoint(x: -26, y: 4))
        h.addCurve(to: CGPoint(x: 0, y: -12), control1: CGPoint(x: -26, y: -26), control2: CGPoint(x: -6, y: -28))
        h.addCurve(to: CGPoint(x: 26, y: -8), control1: CGPoint(x: 6, y: -28), control2: CGPoint(x: 26, y: -26))
        h.addCurve(to: CGPoint(x: 0, y: 22), control1: CGPoint(x: 26, y: 4), control2: CGPoint(x: 14, y: 12))
        h.closeSubpath()
        return h
    }()

    static func draw(_ p: MascotPose, figure: GraphicsContext, body: GraphicsContext, dark: Bool) {
        if p.thought > 0.01 { thought(p, in: figure, dark: dark) }
        if p.zzz > 0.01 { zzz(p, in: figure, dark: dark) }
        if p.floatHearts > 0.01 { floatingHearts(p, in: figure) }
        if p.sweat > 0.01 { sweat(p, in: body) }
        if p.confetti > 0.01 { confetti(p, in: figure) }
    }

    private static func phase(_ time: Double, speed: Double, offset: Double) -> Double {
        let v = (time * speed + offset).truncatingRemainder(dividingBy: 1)
        return v < 0 ? v + 1 : v
    }

    // Three dots rising up-left, like a thought bubble trail.
    private static func thought(_ p: MascotPose, in ctx: GraphicsContext, dark: Bool) {
        var c = ctx
        c.opacity = motionClamp(p.thought, 0, 1)
        let tint = dark ? Color(hex: "#8E84A8") : P.navy.opacity(0.4)
        for (i, (x, y, r)) in [(CGFloat(132), CGFloat(78), CGFloat(11)), (96, 34, 16), (52, -24, 23)].enumerated() {
            let bob = CGFloat(sin(p.time * 2 * .pi * 0.8 + Double(i) * 1.1)) * 4
            c.fill(Path(ellipseIn: CGRect(x: x - r, y: y - r + bob, width: 2 * r, height: 2 * r)), with: .color(tint))
        }
    }

    // z z Z drifting up to the right.
    private static func zzz(_ p: MascotPose, in ctx: GraphicsContext, dark: Bool) {
        let tint = dark ? Color(hex: "#B9B0E0") : P.navy.opacity(0.7)
        let letters: [(String, CGFloat, CGFloat, CGFloat)] = [("z", 392, 60, 40), ("z", 432, 8, 54), ("Z", 476, -54, 70)]
        for (i, (letter, x, y, size)) in letters.enumerated() {
            let u = phase(p.time, speed: 0.35, offset: 0.2 + Double(i) * 0.3)
            var c = ctx
            c.opacity = motionClamp(p.zzz, 0, 1) * sin(.pi * u)
            c.draw(Text(letter).font(.system(size: size, weight: .heavy, design: .rounded)).foregroundColor(tint),
                   at: CGPoint(x: x + CGFloat(u) * 6, y: y - CGFloat(u) * 22))
        }
    }

    // Three hearts rising from behind the bowl.
    private static func floatingHearts(_ p: MascotPose, in ctx: GraphicsContext) {
        let spots: [(CGFloat, CGFloat, CGFloat, Double)] = [(70, 120, 0.55, -0.3), (440, 70, 0.8, 0.25), (488, 180, 0.45, 0.15)]
        for (i, (x, y, k, a)) in spots.enumerated() {
            let u = phase(p.time, speed: 0.4, offset: 0.15 + Double(i) * 0.33)
            var c = ctx
            c.opacity = motionClamp(p.floatHearts, 0, 1) * sin(.pi * u)
            c.translateBy(x: x, y: y - CGFloat(u) * 34)
            c.rotate(by: .radians(a))
            c.scaleBy(x: k, y: k)
            c.fill(heart, with: .linearGradient(Gradient(colors: [Color(hex: "#FF8DA0"), P.body]),
                                                startPoint: CGPoint(x: 0, y: -26), endPoint: CGPoint(x: 0, y: 24)))
        }
    }

    // A sweat drop by the right brow, sliding down a little.
    private static func sweat(_ p: MascotPose, in ctx: GraphicsContext) {
        let u = phase(p.time, speed: 0.5, offset: 0.5)
        let o = CGPoint(x: 372, y: 226 + CGFloat(u) * 10)
        var d = Path()
        d.move(to: CGPoint(x: o.x, y: o.y - 24))
        d.addQuadCurve(to: CGPoint(x: o.x + 12, y: o.y + 5), control: CGPoint(x: o.x + 12, y: o.y - 8))
        d.addArc(center: CGPoint(x: o.x, y: o.y + 5), radius: 12, startAngle: .zero, endAngle: .degrees(180), clockwise: false)
        d.addQuadCurve(to: CGPoint(x: o.x, y: o.y - 24), control: CGPoint(x: o.x - 12, y: o.y - 8))
        var c = ctx
        c.opacity = motionClamp(p.sweat, 0, 1) * min(1, u * 5) * min(1, (1 - u) * 5)
        c.fill(d, with: .linearGradient(Gradient(colors: [Color(hex: "#D6EEFF"), Color(hex: "#6FB6F0")]),
                                        startPoint: CGPoint(x: o.x, y: o.y - 24), endPoint: CGPoint(x: o.x, y: o.y + 17)))
        c.fill(Path(ellipseIn: CGRect(x: o.x - 6, y: o.y - 2, width: 5, height: 8)), with: .color(.white.opacity(0.8)))
    }

    // Brand-coloured bits falling and spinning around the bowl.
    private static let confettiBits: [(x: CGFloat, start: Double, spin: Double, color: String)] = [
        (24, 0.05, 1.0, "#E8698A"), (86, 0.55, -1.3, "#EF9F27"), (150, 0.25, 0.8, "#7FD1B9"),
        (214, 0.8, -0.9, "#6C8CF5"), (300, 0.4, 1.2, "#E8698A"), (362, 0.1, -1.1, "#F2C14E"),
        (428, 0.65, 0.9, "#7FD1B9"), (488, 0.3, -1.4, "#EF9F27"),
    ]

    private static func confetti(_ p: MascotPose, in ctx: GraphicsContext) {
        for (i, bit) in confettiBits.enumerated() {
            let u = phase(p.time, speed: 0.45, offset: bit.start)
            let y = -110 + CGFloat(u) * 250
            let sway = CGFloat(sin(p.time * 3 + Double(i))) * 8
            var c = ctx
            // Fade in at the top and out before reaching the bowl's face.
            c.opacity = motionClamp(p.confetti, 0, 1) * min(1, u * 6) * min(1, (1 - u) * 3)
            c.translateBy(x: bit.x + sway, y: y)
            c.rotate(by: .radians(bit.spin * (p.time * 3 + Double(i))))
            c.fill(Path(roundedRect: CGRect(x: -11, y: -5, width: 22, height: 10), cornerRadius: 3),
                   with: .color(Color(hex: bit.color)))
        }
    }
}
