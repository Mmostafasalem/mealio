import SwiftUI

// MARK: - Mascot figure
//
// The Nourlo bowl, drawn in one Canvas from a `MascotPose`. Everything is laid
// out in the 512-point design space of the original artwork (the character
// spans x 26…486, y 76…476) and scaled to `size`, so it is vector and crisp from
// the 36 pt chat header to the 132 pt welcome hero. The canvas is 1.5× the
// layout box and centred on it, so a hop, raised arms or a stretch can leave
// the box without being clipped or changing layout.

struct MascotFigure: View {
    let pose: MascotPose
    var size: CGFloat

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let dark = colorScheme == .dark
        Color.clear
            .frame(width: size, height: size)
            .overlay {
                Canvas { ctx, canvasSize in
                    MascotArt.draw(pose, in: &ctx, side: canvasSize.width, dark: dark)
                }
                .frame(width: size * 1.5, height: size * 1.5)
                .allowsHitTesting(false)
            }
            .accessibilityHidden(true)
    }
}

// MARK: - Palette (sampled from the original PNG)

enum MascotPalette {
    static let bodyLight = Color(hex: "#FAD8D2")
    static let body = Color(hex: "#F0C5BE")
    static let bodyShade = Color(hex: "#E2B0A9")
    static let bodyDeep = Color(hex: "#D69E98")
    static let rimLight = Color(hex: "#F09AA5")
    static let rim = Color(hex: "#E58894")
    static let rimDeep = Color(hex: "#CC6F7B")
    static let wallDark = Color(hex: "#B04A4B")
    static let wall = Color(hex: "#C8646A")
    static let oat = Color(hex: "#F4D0B0")
    static let oatLight = Color(hex: "#FBE2C8")
    static let oatShade = Color(hex: "#DDAA80")
    static let oatDeep = Color(hex: "#C99468")
    static let banana = Color(hex: "#FBDDA9")
    static let bananaLight = Color(hex: "#FFEFCB")
    static let bananaEdge = Color(hex: "#EDC183")
    static let bananaSeed = Color(hex: "#E2A65E")
    static let berry = Color(hex: "#EE7774")
    static let berryLight = Color(hex: "#F8A09A")
    static let berryShade = Color(hex: "#D85A5C")
    static let berrySeed = Color(hex: "#FBC9C0")
    static let navy = Color(hex: "#2E4060")
    static let navyLight = Color(hex: "#4A5F8C")
    static let cheek = Color(hex: "#EE8D98")
    static let tongue = Color(hex: "#E98290")
}

// MARK: - Drawing

enum MascotArt {
    private typealias P = MascotPalette

    // Geometry in design units.
    private static let rimCenter = CGPoint(x: 256, y: 160)
    private static let rimOuter = CGSize(width: 228, height: 72)
    private static let rimInnerCenter = CGPoint(x: 256, y: 157)
    private static let rimInner = CGSize(width: 210, height: 57)
    private static let ground: CGFloat = 470
    private static let eyeL = CGPoint(x: 199, y: 277)
    private static let eyeR = CGPoint(x: 315, y: 277)
    private static let mouth = CGPoint(x: 257, y: 300)
    private static let shoulderL = CGPoint(x: 100, y: 300)
    private static let shoulderR = CGPoint(x: 412, y: 300)

    static func draw(_ p: MascotPose, in ctx: inout GraphicsContext, side: CGFloat, dark: Bool) {
        let k = side / 768
        ctx.translateBy(x: 128 * k, y: 128 * k)
        ctx.scaleBy(x: k, y: k)

        drawShadow(p, in: ctx, dark: dark)

        var fig = ctx
        fig.translateBy(x: 0, y: p.altitude + p.bob)

        drawFoot(p.footL, centerX: 178, squash: p.scaleX, in: fig)
        drawFoot(p.footR, centerX: 334, squash: p.scaleX, in: fig)

        var body = fig
        // Tilt and squash about the ground point so the bowl sits on its feet.
        body.translateBy(x: 256, y: ground - 8)
        body.rotate(by: .radians(p.tilt))
        body.scaleBy(x: p.scaleX * p.breathe, y: p.scaleY * p.breathe)
        body.translateBy(x: -256, y: -(ground - 8))
        if p.stretch > 0.001 {
            // Stretch along the drag direction, thinning across it (area kept).
            let c = CGPoint(x: 256, y: 280)
            body.translateBy(x: c.x, y: c.y)
            body.rotate(by: .radians(p.stretchAngle))
            body.scaleBy(x: 1 + p.stretch, y: 1 / (1 + p.stretch))
            body.rotate(by: .radians(-p.stretchAngle))
            body.translateBy(x: -c.x, y: -c.y)
        }

        drawBowlBack(in: body)
        var contents = body
        contents.translateBy(x: p.contentX, y: p.contentY)
        contents.translateBy(x: 256, y: 170)
        contents.rotate(by: .radians(p.contentTilt))
        contents.translateBy(x: -256, y: -170)
        drawContents(p, in: contents)
        drawBowlFront(in: body)
        drawFace(p, in: body)
        drawArm(p.armL, left: true, in: body)
        drawArm(p.armR, left: false, in: body)
    }

    // MARK: Shadow

    private static func drawShadow(_ p: MascotPose, in ctx: GraphicsContext, dark: Bool) {
        var c = ctx
        let s = p.shadow
        c.translateBy(x: 256, y: ground + 2)
        c.scaleBy(x: 1, y: 0.11)
        let r = 160 * (0.6 + 0.4 * s)
        c.fill(Path(ellipseIn: CGRect(x: -r, y: -r, width: 2 * r, height: 2 * r)),
               with: .radialGradient(Gradient(colors: [
                    Color.black.opacity((dark ? 0.45 : 0.2) * s),
                    Color.black.opacity((dark ? 0.2 : 0.08) * s),
                    .clear,
               ]), center: .zero, startRadius: 0, endRadius: r))
    }

    // MARK: Feet

    private static func drawFoot(_ f: MascotPose.Foot, centerX: CGFloat, squash: Double, in ctx: GraphicsContext) {
        var c = ctx
        let hip = CGPoint(x: centerX, y: 396)
        c.translateBy(x: hip.x, y: hip.y - f.lift)
        c.rotate(by: .radians(f.rotation))
        c.scaleBy(x: min(1.15, max(0.9, squash)), y: 1)
        let rect = CGRect(x: -42, y: -14, width: 84, height: 88)
        let path = Path(roundedRect: rect, cornerSize: CGSize(width: 34, height: 34), style: .continuous)
        c.fill(path, with: .linearGradient(Gradient(colors: [P.navyLight, P.navy, Color(hex: "#24334F")]),
                                           startPoint: CGPoint(x: -34, y: -10), endPoint: CGPoint(x: 36, y: 74)))
        // soft top-left sheen
        c.fill(Path(ellipseIn: CGRect(x: -30, y: 10, width: 28, height: 40)),
               with: .radialGradient(Gradient(colors: [Color.white.opacity(0.16), .clear]),
                                     center: CGPoint(x: -16, y: 30), startRadius: 0, endRadius: 22))
    }

    // MARK: Bowl

    private static func ellipse(_ c: CGPoint, _ r: CGSize) -> Path {
        Path(ellipseIn: CGRect(x: c.x - r.width, y: c.y - r.height, width: 2 * r.width, height: 2 * r.height))
    }

    private static let k4: CGFloat = 0.5523

    /// Body below the rim: the lower half of the outer rim ellipse, then the bowl curve.
    private static let bodyPath: Path = {
        let c = rimCenter, r = rimOuter
        var p = Path()
        p.move(to: CGPoint(x: c.x - r.width, y: c.y))
        p.addCurve(to: CGPoint(x: c.x, y: c.y + r.height),
                   control1: CGPoint(x: c.x - r.width, y: c.y + r.height * k4),
                   control2: CGPoint(x: c.x - r.width * k4, y: c.y + r.height))
        p.addCurve(to: CGPoint(x: c.x + r.width, y: c.y),
                   control1: CGPoint(x: c.x + r.width * k4, y: c.y + r.height),
                   control2: CGPoint(x: c.x + r.width, y: c.y + r.height * k4))
        p.addCurve(to: CGPoint(x: 256, y: 414),
                   control1: CGPoint(x: 488, y: 312),
                   control2: CGPoint(x: 380, y: 414))
        p.addCurve(to: CGPoint(x: c.x - r.width, y: c.y),
                   control1: CGPoint(x: 132, y: 414),
                   control2: CGPoint(x: 24, y: 312))
        p.closeSubpath()
        return p
    }()

    private static let ringPath: Path = {
        var p = ellipse(rimCenter, rimOuter)
        p.addPath(ellipse(rimInnerCenter, rimInner))
        return p
    }()

    private static func drawBowlBack(in ctx: GraphicsContext) {
        var c = ctx
        // Whole rim ring (the back half stays visible behind the oats).
        c.fill(ringPath, with: .linearGradient(Gradient(colors: [P.rimLight, P.rim, P.rimDeep]),
                                               startPoint: CGPoint(x: 256, y: 88), endPoint: CGPoint(x: 256, y: 232)),
               style: FillStyle(eoFill: true))
        // Inner wall, darkest at the back with an inner shadow under the lip.
        let hole = ellipse(rimInnerCenter, rimInner)
        c.fill(hole, with: .linearGradient(Gradient(colors: [P.wallDark, P.wall, P.rim]),
                                           startPoint: CGPoint(x: 256, y: 100), endPoint: CGPoint(x: 256, y: 200)))
        c.clip(to: hole)
        c.stroke(ellipse(CGPoint(x: rimInnerCenter.x, y: rimInnerCenter.y - 6), rimInner),
                 with: .color(Color.black.opacity(0.12)), lineWidth: 8)
    }

    private static func drawBowlFront(in ctx: GraphicsContext) {
        let c = ctx
        c.fill(bodyPath, with: .radialGradient(Gradient(stops: [
            .init(color: P.bodyLight, location: 0),
            .init(color: P.body, location: 0.35),
            .init(color: P.bodyShade, location: 0.75),
            .init(color: P.bodyDeep, location: 1),
        ]), center: CGPoint(x: 190, y: 235), startRadius: 0, endRadius: 330))

        // Soft shade the rim casts on the bowl, and a bottom-right core shadow.
        c.drawLayer { layer in
            layer.clip(to: bodyPath)
            layer.addFilter(.blur(radius: 10))
            var lip = Path()
            lip.move(to: CGPoint(x: 30, y: 172))
            lip.addQuadCurve(to: CGPoint(x: 482, y: 172), control: CGPoint(x: 256, y: 300))
            layer.stroke(lip, with: .color(P.rimDeep.opacity(0.28)), lineWidth: 16)
            layer.fill(Path(ellipseIn: CGRect(x: 300, y: 300, width: 220, height: 160)),
                       with: .color(P.bodyDeep.opacity(0.35)))
        }

        // Front rim band over the oats.
        var band = c
        band.clip(to: Path(CGRect(x: 0, y: rimInnerCenter.y, width: 512, height: 120)))
        band.fill(ringPath, with: .linearGradient(Gradient(colors: [P.rimLight, P.rim, P.rimDeep]),
                                                  startPoint: CGPoint(x: 256, y: 170), endPoint: CGPoint(x: 256, y: 232)),
                  style: FillStyle(eoFill: true))
        // Rounded lip highlight along the top edge of the band.
        var lipTop = Path()
        let r = rimInner, ic = rimInnerCenter
        lipTop.move(to: CGPoint(x: ic.x - r.width + 4, y: ic.y + 8))
        lipTop.addCurve(to: CGPoint(x: ic.x, y: ic.y + r.height + 4),
                        control1: CGPoint(x: ic.x - r.width + 4, y: ic.y + 8 + r.height * k4),
                        control2: CGPoint(x: ic.x - r.width * k4, y: ic.y + r.height + 4))
        lipTop.addCurve(to: CGPoint(x: ic.x + r.width - 4, y: ic.y + 8),
                        control1: CGPoint(x: ic.x + r.width * k4, y: ic.y + r.height + 4),
                        control2: CGPoint(x: ic.x + r.width - 4, y: ic.y + 8 + r.height * k4))
        band.stroke(lipTop, with: .color(Color.white.opacity(0.22)), style: StrokeStyle(lineWidth: 4, lineCap: .round))
    }

    // MARK: Contents

    /// Deterministic oat grains inside the bowl opening.
    private static let grains: [(CGPoint, CGFloat)] = {
        var out: [(CGPoint, CGFloat)] = []
        var row = 0
        var y: CGFloat = 122
        while y < 222 {
            let dy = (y - 172) / 54
            let half = 214 * sqrt(max(0, 1 - dy * dy))
            var x = 256 - half + (row % 2 == 0 ? 6 : 16)
            var i = 0
            while x < 256 + half - 4 {
                let j = sin(Double(row * 31 + i * 17)) * 0.5 + 0.5
                out.append((CGPoint(x: x, y: y + CGFloat(j * 4 - 2)), 10 + CGFloat(j) * 3))
                x += 21 + CGFloat(j) * 3
                i += 1
            }
            y += 13
            row += 1
        }
        return out
    }()

    private static func drawContents(_ p: MascotPose, in ctx: GraphicsContext) {
        var oats = ctx
        oats.clip(to: ellipse(rimInnerCenter, CGSize(width: rimInner.width - 2, height: rimInner.height + 40)))
        oats.clip(to: Path(CGRect(x: 0, y: 0, width: 512, height: 240)))
        // Mound base
        let mound = ellipse(CGPoint(x: 256, y: 174), CGSize(width: 214, height: 60))
        oats.fill(mound, with: .linearGradient(Gradient(colors: [P.oat, P.oatShade, P.oatDeep]),
                                               startPoint: CGPoint(x: 256, y: 120), endPoint: CGPoint(x: 256, y: 230)))
        oats.clip(to: mound)
        for (c, r) in grains {
            let rect = CGRect(x: c.x - r, y: c.y - r * 0.85, width: 2 * r, height: 1.7 * r)
            oats.fill(Path(ellipseIn: rect), with: .radialGradient(
                Gradient(colors: [P.oatLight, P.oat, P.oatShade]),
                center: CGPoint(x: c.x - r * 0.35, y: c.y - r * 0.4), startRadius: 0, endRadius: r * 1.3))
        }

        // Bananas: back coin first, then the two in front.
        let bananas: [(Int, CGPoint, CGSize, Double)] = [
            (1, CGPoint(x: 190, y: 114), CGSize(width: 45, height: 35), 0.1),
            (0, CGPoint(x: 122, y: 152), CGSize(width: 46, height: 38), -0.15),
            (2, CGPoint(x: 200, y: 170), CGSize(width: 49, height: 39), -0.05),
        ]
        for (i, c, r, rot) in bananas {
            drawBanana(at: CGPoint(x: c.x, y: c.y + p.fruitY[i]), radius: r, rotation: rot + p.fruitRotation[i], in: ctx)
        }
        let berries: [(Int, CGPoint, CGFloat, Double)] = [
            (3, CGPoint(x: 326, y: 98), 1.18, -0.05),
            (4, CGPoint(x: 384, y: 144), 1.14, 0.2),
            (5, CGPoint(x: 304, y: 154), 1.22, -0.18),
        ]
        for (i, c, s, rot) in berries {
            drawBerry(at: CGPoint(x: c.x, y: c.y + p.fruitY[i]), scale: s, rotation: rot + p.fruitRotation[i], in: ctx)
        }
    }

    private static func drawBanana(at c: CGPoint, radius r: CGSize, rotation: Double, in ctx: GraphicsContext) {
        var g = ctx
        g.translateBy(x: c.x, y: c.y)
        g.rotate(by: .radians(rotation))
        // contact shadow on the oats
        g.fill(Path(ellipseIn: CGRect(x: -r.width + 2, y: -r.height + 7, width: 2 * r.width, height: 2 * r.height)),
               with: .color(P.oatDeep.opacity(0.35)))
        // side (thickness) then face
        g.fill(Path(ellipseIn: CGRect(x: -r.width, y: -r.height + 4, width: 2 * r.width, height: 2 * r.height)),
               with: .color(P.bananaEdge))
        let face = Path(ellipseIn: CGRect(x: -r.width, y: -r.height, width: 2 * r.width, height: 2 * r.height))
        g.fill(face, with: .radialGradient(Gradient(colors: [P.bananaLight, P.banana, Color(hex: "#F3CF92")]),
                                           center: CGPoint(x: -r.width * 0.3, y: -r.height * 0.35),
                                           startRadius: 0, endRadius: r.width * 1.3))
        // five-petal seed pattern
        for i in 0..<5 {
            let a = Double(i) * 2 * .pi / 5 - .pi / 2
            var petal = g
            petal.rotate(by: .radians(a + .pi / 2))
            petal.fill(Path(ellipseIn: CGRect(x: -2.6, y: -r.height * 0.52, width: 5.2, height: r.height * 0.36)),
                       with: .color(P.bananaSeed.opacity(0.85)))
        }
        g.fill(Path(ellipseIn: CGRect(x: -2.5, y: -2.5, width: 5, height: 5)), with: .color(P.bananaSeed.opacity(0.7)))
    }

    private static let berryPath: Path = {
        var p = Path()
        p.move(to: CGPoint(x: 0, y: -34))
        p.addCurve(to: CGPoint(x: 29, y: 4), control1: CGPoint(x: 16, y: -34), control2: CGPoint(x: 30, y: -16))
        p.addCurve(to: CGPoint(x: 0, y: 31), control1: CGPoint(x: 28, y: 22), control2: CGPoint(x: 14, y: 31))
        p.addCurve(to: CGPoint(x: -29, y: 4), control1: CGPoint(x: -14, y: 31), control2: CGPoint(x: -28, y: 22))
        p.addCurve(to: CGPoint(x: 0, y: -34), control1: CGPoint(x: -30, y: -16), control2: CGPoint(x: -16, y: -34))
        p.closeSubpath()
        return p
    }()

    private static let berrySeeds: [CGPoint] = [
        CGPoint(x: -9, y: -18), CGPoint(x: 6, y: -20),
        CGPoint(x: -16, y: -4), CGPoint(x: -2, y: -6), CGPoint(x: 13, y: -6),
        CGPoint(x: -19, y: 10), CGPoint(x: -6, y: 9), CGPoint(x: 7, y: 9), CGPoint(x: 19, y: 10),
        CGPoint(x: -9, y: 21), CGPoint(x: 5, y: 22),
    ]

    private static func drawBerry(at c: CGPoint, scale s: CGFloat, rotation: Double, in ctx: GraphicsContext) {
        var g = ctx
        g.translateBy(x: c.x, y: c.y)
        g.rotate(by: .radians(rotation))
        g.scaleBy(x: s, y: s)
        var shadow = g
        shadow.translateBy(x: 3, y: 6)
        shadow.fill(berryPath, with: .color(Color(hex: "#9E4A42").opacity(0.3)))
        g.fill(berryPath, with: .radialGradient(Gradient(colors: [P.berryLight, P.berry, P.berryShade]),
                                                center: CGPoint(x: -10, y: -12), startRadius: 0, endRadius: 44))
        for seed in berrySeeds {
            g.fill(Path(ellipseIn: CGRect(x: seed.x - 2, y: seed.y - 3, width: 4, height: 6)),
                   with: .color(P.berrySeed.opacity(0.9)))
        }
    }

    // MARK: Face

    private static func drawFace(_ p: MascotPose, in ctx: GraphicsContext) {
        var c = ctx
        let lookShift = CGPoint(x: p.lookX * 3, y: p.lookY * 2)
        c.translateBy(x: lookShift.x, y: lookShift.y)

        // Cheeks
        if p.blush > 0.01 {
            for x in [168.0, 346.0] {
                let r = CGSize(width: 22, height: 12)
                let center = CGPoint(x: x, y: 305)
                var cheek = c
                cheek.translateBy(x: center.x, y: center.y)
                cheek.scaleBy(x: 1, y: r.height / r.width)
                cheek.fill(Path(ellipseIn: CGRect(x: -r.width, y: -r.width, width: 2 * r.width, height: 2 * r.width)),
                           with: .radialGradient(Gradient(colors: [P.cheek.opacity(0.7 * p.blush), P.cheek.opacity(0)]),
                                                 center: .zero, startRadius: 0, endRadius: r.width))
            }
        }

        // Eyes
        let eyeOffset = CGPoint(x: p.lookX * 7, y: p.lookY * 6)
        for e in [eyeL, eyeR] {
            drawEye(at: CGPoint(x: e.x + eyeOffset.x, y: e.y + eyeOffset.y), p, in: c)
        }

        // Brows (raised for help/surprise)
        if p.brows > 0.01 {
            for (e, tilt) in [(eyeL, -1.0), (eyeR, 1.0)] {
                var brow = Path()
                let y = e.y - 34 - p.brows * 5 + eyeOffset.y * 0.5
                brow.move(to: CGPoint(x: e.x - 11, y: y + 3 + tilt * 1.5))
                brow.addQuadCurve(to: CGPoint(x: e.x + 11, y: y + 3 - tilt * 1.5), control: CGPoint(x: e.x, y: y - 4))
                var b = c
                b.opacity = p.brows
                b.stroke(brow, with: .color(P.navy), style: StrokeStyle(lineWidth: 5, lineCap: .round))
            }
        }

        drawMouth(p, in: c)
    }

    private static func drawEye(at e: CGPoint, _ p: MascotPose, in ctx: GraphicsContext) {
        let open = 1 - motionClamp(p.squint, 0, 1)
        if open > 0.01 {
            var c = ctx
            c.opacity = open
            let wide = 1 + 0.14 * p.wide
            let r = CGSize(width: 15 * wide, height: 19 * wide)
            c.translateBy(x: e.x, y: e.y)
            // Sleepy: the upper lid comes down to about a third.
            let lid = 1 - 0.62 * motionClamp(p.sleepy, 0, 1)
            let lidY = r.height - 2 * r.height * lid
            if lid < 0.999 { c.clip(to: lidPath(width: r.width, y: lidY)) }
            c.scaleBy(x: 1, y: max(0.1, p.blink))
            let eye = Path(ellipseIn: CGRect(x: -r.width, y: -r.height, width: 2 * r.width, height: 2 * r.height))
            c.fill(eye, with: .linearGradient(Gradient(colors: [Color(hex: "#3A4F78"), P.navy, Color(hex: "#24334F")]),
                                              startPoint: CGPoint(x: 0, y: -r.height), endPoint: CGPoint(x: 0, y: r.height)))
            if p.blink > 0.5 {
                c.fill(Path(ellipseIn: CGRect(x: 2, y: -r.height + 4, width: 8, height: 8)), with: .color(.white.opacity(0.95)))
                c.fill(Path(ellipseIn: CGRect(x: -8, y: r.height * 0.35, width: 4, height: 4)), with: .color(.white.opacity(0.35)))
            }
            if lid < 0.999 {
                var lidLine = Path()
                lidLine.move(to: CGPoint(x: -r.width - 1, y: lidY + 4))
                lidLine.addQuadCurve(to: CGPoint(x: r.width + 1, y: lidY + 4), control: CGPoint(x: 0, y: lidY - 6))
                var line = ctx
                line.translateBy(x: e.x, y: e.y)
                line.opacity = open * motionClamp(p.sleepy, 0, 1)
                line.stroke(lidLine, with: .color(P.navy), style: StrokeStyle(lineWidth: 5, lineCap: .round))
            }
        }
        if p.squint > 0.01 {
            // Happy squint: a thick ∩.
            var c = ctx
            c.opacity = motionClamp(p.squint, 0, 1)
            var arc = Path()
            arc.move(to: CGPoint(x: e.x - 15, y: e.y + 6))
            arc.addQuadCurve(to: CGPoint(x: e.x + 15, y: e.y + 6), control: CGPoint(x: e.x, y: e.y - 18))
            c.stroke(arc, with: .color(P.navy), style: StrokeStyle(lineWidth: 7, lineCap: .round))
        }
    }

    /// The visible part of a drowsy eye: below a lid that bows up slightly.
    private static func lidPath(width w: CGFloat, y: CGFloat) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: -w - 4, y: y + 4))
        p.addQuadCurve(to: CGPoint(x: w + 4, y: y + 4), control: CGPoint(x: 0, y: y - 6))
        p.addLine(to: CGPoint(x: w + 4, y: 60))
        p.addLine(to: CGPoint(x: -w - 4, y: 60))
        p.closeSubpath()
        return p
    }

    private static func drawMouth(_ p: MascotPose, in ctx: GraphicsContext) {
        let m = mouth
        if p.smile > 0.01 {
            var c = ctx
            c.opacity = motionClamp(p.smile, 0, 1)
            var s = Path()
            s.move(to: CGPoint(x: m.x - 21, y: m.y - 3))
            s.addQuadCurve(to: CGPoint(x: m.x + 21, y: m.y - 3), control: CGPoint(x: m.x, y: m.y + 17))
            c.stroke(s, with: .color(P.navy), style: StrokeStyle(lineWidth: 6.5, lineCap: .round))
        }
        if p.ooh > 0.01 {
            var c = ctx
            c.opacity = motionClamp(p.ooh, 0, 1)
            let small = 1 - 0.4 * motionClamp(p.sleepy, 0, 1)
            let r = CGSize(width: (9 + 2 * p.ooh) * small, height: (10 + 3 * p.ooh) * small)
            c.fill(Path(ellipseIn: CGRect(x: m.x - r.width, y: m.y + 6 - r.height, width: 2 * r.width, height: 2 * r.height)),
                   with: .color(P.navy))
        }
        if p.wavy > 0.01 {
            var c = ctx
            c.opacity = motionClamp(p.wavy, 0, 1)
            var w = Path()
            let x0 = m.x - 21, width: CGFloat = 42
            w.move(to: CGPoint(x: x0, y: m.y + 4))
            for i in 1...24 {
                let u = CGFloat(i) / 24
                w.addLine(to: CGPoint(x: x0 + u * width, y: m.y + 4 + sin(u * 3 * .pi) * 3.5))
            }
            c.stroke(w, with: .color(P.navy), style: StrokeStyle(lineWidth: 5.5, lineCap: .round, lineJoin: .round))
        }
        if p.grin > 0.01 {
            var c = ctx
            c.opacity = motionClamp(p.grin, 0, 1)
            var g = Path()
            g.move(to: CGPoint(x: m.x - 24, y: m.y - 4))
            g.addQuadCurve(to: CGPoint(x: m.x + 24, y: m.y - 4), control: CGPoint(x: m.x, y: m.y))
            g.addCurve(to: CGPoint(x: m.x - 24, y: m.y - 4),
                       control1: CGPoint(x: m.x + 24, y: m.y + 30), control2: CGPoint(x: m.x - 24, y: m.y + 30))
            g.closeSubpath()
            c.fill(g, with: .color(P.navy))
            var t = c
            t.clip(to: g)
            t.fill(Path(ellipseIn: CGRect(x: m.x - 13, y: m.y + 10, width: 26, height: 16)), with: .color(P.tongue))
        }
    }

    // MARK: Arms

    private static func drawArm(_ a: MascotPose.Arm, left: Bool, in ctx: GraphicsContext) {
        let shoulder = left ? shoulderL : shoulderR
        let base = left ? CGPoint(x: shoulder.x + a.reach, y: shoulder.y + a.lift)
                        : CGPoint(x: shoulder.x - a.reach, y: shoulder.y + a.lift)
        // At rest the arm hangs out and down (40°); raising swings it up and out.
        let angle = left ? .pi - 0.7 + a.raise : 0.7 - a.raise
        let dir = CGPoint(x: cos(angle), y: sin(angle))
        let center = CGPoint(x: base.x + dir.x * 34, y: base.y + dir.y * 34)
        // Keep the ellipse's local frame within ±90° so the light stays top-left.
        var orient = atan2(dir.y, dir.x)
        if orient > .pi / 2 { orient -= .pi } else if orient < -.pi / 2 { orient += .pi }
        orient *= 0.6 // the clay blob stays fairly level, like the original
        let r = CGSize(width: 44, height: 33)
        let shape = Path(ellipseIn: CGRect(x: -r.width, y: -r.height, width: 2 * r.width, height: 2 * r.height))

        var shadow = ctx
        shadow.translateBy(x: center.x + 3, y: center.y + 7)
        shadow.rotate(by: .radians(orient))
        shadow.fill(shape, with: .color(P.bodyDeep.opacity(0.35)))

        var c = ctx
        c.translateBy(x: center.x, y: center.y)
        c.rotate(by: .radians(orient))
        // light from the top-left in world space, expressed in the arm's frame
        let lw = CGPoint(x: -14, y: -14)
        let light = CGPoint(x: lw.x * cos(-orient) - lw.y * sin(-orient), y: lw.x * sin(-orient) + lw.y * cos(-orient))
        c.fill(shape, with: .radialGradient(Gradient(colors: [P.bodyLight, P.body, P.bodyShade]),
                                            center: light, startRadius: 0, endRadius: 52))
    }
}
