import AppKit
import CoreGraphics
import CoreText

func c(_ hex: UInt32, _ a: CGFloat = 1) -> CGColor {
    CGColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255, blue: CGFloat(hex & 0xFF) / 255, alpha: a)
}
let rhino: UInt32 = 0x2E4060, rhinoDeep: UInt32 = 0x24334D, rhinoLift: UInt32 = 0x3D5480
let pink: UInt32 = 0xDD8C96, pinkDeep: UInt32 = 0xC56F7C, pinkLight: UInt32 = 0xEAB0B6
let almond: UInt32 = 0xF4DAD4, cream: UInt32 = 0xF7E8D2, banana: UInt32 = 0xF6E3A8, bananaCore: UInt32 = 0xE2C676
let berry: UInt32 = 0xD25467, berryDeep: UInt32 = 0xB23F55, leaf: UInt32 = 0x6FA77A

struct Variant { let name: String; let bg: UInt32; let bgLift: UInt32; let bowl: UInt32; let bowlShade: UInt32; let rim: UInt32; let face: UInt32; let shadow: UInt32 }
// The owner picked the flat bowl on almond on 16 Nov 2026 (the navy went with the
// app's move to black), with blueberries between the banana and the strawberries,
// and then the close-up: the bowl peeking up from the bottom edge with the name above it
// in Comfortaa Bold (docs/brand/Comfortaa.ttf, SIL Open Font License), one colour a letter.
let ink: UInt32 = 0x1C1C1E
let blueberry: UInt32 = 0x4F5F96, blueberryDeep: UInt32 = 0x374573, blueberryLight: UInt32 = 0x8090C4
let variants = [
    Variant(name: "almond", bg: almond, bgLift: 0xFBEDE8, bowl: pink, bowlShade: pinkDeep, rim: pinkDeep, face: ink, shadow: 0xE3C1B9),
]

func draw(_ v: Variant, size: Int = 1024, zoom: CGFloat = 1.16, rimAt: CGFloat = 468, face: CGFloat = 1, faceUp: CGFloat = 0, shadow: Bool = true, fruit: Bool = true, fruitLeft: CGFloat = 0, arms: Bool = false, word: Bool = false) -> CGImage {
    let ctx = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0,
                        space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
    let s = CGFloat(size) / 1024
    ctx.scaleBy(x: s, y: -s); ctx.translateBy(x: 0, y: -1024)   // top-left origin, 1024 design units

    // background: soft light from the top
    ctx.setFillColor(c(v.bg)); ctx.fill(CGRect(x: 0, y: 0, width: 1024, height: 1024))
    let g = CGGradient(colorsSpace: nil, colors: [c(v.bgLift), c(v.bg)] as CFArray, locations: [0, 1])!
    ctx.drawRadialGradient(g, startCenter: CGPoint(x: 512, y: 300), startRadius: 0, endCenter: CGPoint(x: 512, y: 380), endRadius: 720, options: [])

    ctx.saveGState()
    ctx.translateBy(x: 512, y: rimAt); ctx.scaleBy(x: zoom, y: zoom); ctx.translateBy(x: -512, y: -470)
    // ground shadow
    if shadow { ctx.setFillColor(c(v.shadow, 0.55)); ctx.fillEllipse(in: CGRect(x: 262, y: 838, width: 500, height: 62)) }

    // arms raised at the sides, behind the bowl: a rounded stub each, a touch darker underneath
    if arms {
        for side in [-1.0, 1.0] as [CGFloat] {
            let from = CGPoint(x: 512 + side * 292, y: 540), to = CGPoint(x: 512 + side * 338, y: 356)
            ctx.setLineCap(.round)
            ctx.setStrokeColor(c(v.bowlShade)); ctx.setLineWidth(92)
            ctx.move(to: from); ctx.addLine(to: to); ctx.strokePath()
            ctx.setStrokeColor(c(v.bowl)); ctx.setLineWidth(78)
            ctx.move(to: from); ctx.addLine(to: CGPoint(x: to.x - side * 4, y: to.y + 2)); ctx.strokePath()
            ctx.setStrokeColor(c(0xFFFFFF, 0.18)); ctx.setLineWidth(22)
            ctx.move(to: CGPoint(x: from.x - side * 14, y: from.y - 40)); ctx.addLine(to: CGPoint(x: to.x - side * 16, y: to.y + 10)); ctx.strokePath()
        }
    }
    // bowl body
    let rimY: CGFloat = 470, left: CGFloat = 170, right: CGFloat = 854, bottom: CGFloat = 832
    let body = CGMutablePath()
    body.move(to: CGPoint(x: left, y: rimY))
    body.addCurve(to: CGPoint(x: 512, y: bottom), control1: CGPoint(x: left + 4, y: 712), control2: CGPoint(x: 340, y: bottom))
    body.addCurve(to: CGPoint(x: right, y: rimY), control1: CGPoint(x: 684, y: bottom), control2: CGPoint(x: right - 4, y: 712))
    body.closeSubpath()
    ctx.addPath(body); ctx.setFillColor(c(v.bowl)); ctx.fillPath()
    // shade on the lower right, clipped to the bowl
    ctx.saveGState(); ctx.addPath(body); ctx.clip()
    let shade = CGGradient(colorsSpace: nil, colors: [c(0xFFFFFF, 0.16), c(v.bowl, 0), c(v.bowlShade, 0.75)] as CFArray, locations: [0, 0.42, 1])!
    ctx.drawLinearGradient(shade, start: CGPoint(x: left, y: 600), end: CGPoint(x: right, y: 700), options: [])
    let under = CGGradient(colorsSpace: nil, colors: [c(v.bowlShade, 0), c(v.bowlShade, 0.45)] as CFArray, locations: [0, 1])!
    ctx.drawLinearGradient(under, start: CGPoint(x: 512, y: 640), end: CGPoint(x: 512, y: bottom), options: [])
    ctx.restoreGState()

    // rim + oats
    ctx.setFillColor(c(v.rim)); ctx.fillEllipse(in: CGRect(x: left, y: rimY - 74, width: right - left, height: 148))
    ctx.setFillColor(c(cream)); ctx.fillEllipse(in: CGRect(x: left + 34, y: rimY - 58, width: right - left - 68, height: 112))

    ctx.saveGState(); ctx.translateBy(x: -fruitLeft, y: 0)
    if fruit {
    // banana coins
    for (x, y, r) in [(380.0, 418.0, 66.0), (482.0, 448.0, 58.0)] as [(CGFloat, CGFloat, CGFloat)] {
        ctx.setFillColor(c(banana)); ctx.fillEllipse(in: CGRect(x: x - r, y: y - r * 0.82, width: r * 2, height: r * 1.64))
        ctx.setFillColor(c(bananaCore))
        for k in 0..<5 {
            let a = CGFloat(k) / 5 * .pi * 2 - .pi / 2
            ctx.fillEllipse(in: CGRect(x: x + cos(a) * r * 0.32 - 7, y: y + sin(a) * r * 0.27 - 5, width: 14, height: 10))
        }
    }
    // strawberries
    func berryAt(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ tilt: CGFloat) {
        ctx.saveGState(); ctx.translateBy(x: x, y: y); ctx.rotate(by: tilt)
        let p = CGMutablePath()
        p.move(to: CGPoint(x: 0, y: w * 0.95))
        p.addCurve(to: CGPoint(x: -w * 0.62, y: -w * 0.25), control1: CGPoint(x: -w * 0.35, y: w * 0.7), control2: CGPoint(x: -w * 0.66, y: w * 0.2))
        p.addCurve(to: CGPoint(x: w * 0.62, y: -w * 0.25), control1: CGPoint(x: -w * 0.55, y: -w * 0.72), control2: CGPoint(x: w * 0.55, y: -w * 0.72))
        p.addCurve(to: CGPoint(x: 0, y: w * 0.95), control1: CGPoint(x: w * 0.66, y: w * 0.2), control2: CGPoint(x: w * 0.35, y: w * 0.7))
        ctx.addPath(p); ctx.setFillColor(c(berry)); ctx.fillPath()
        ctx.setFillColor(c(berryDeep, 0.5)); ctx.fillEllipse(in: CGRect(x: w * 0.05, y: -w * 0.1, width: w * 0.5, height: w * 0.8))
        ctx.setFillColor(c(banana))
        for (sx, sy) in [(-0.25, 0.0), (0.2, 0.05), (-0.05, 0.35), (0.28, 0.4), (-0.3, 0.38), (0.02, -0.2)] as [(CGFloat, CGFloat)] {
            ctx.fillEllipse(in: CGRect(x: sx * w - 6, y: sy * w - 8, width: 12, height: 16))
        }
        ctx.setFillColor(c(leaf))
        for a in [-0.9, -0.3, 0.3, 0.9] as [CGFloat] {
            ctx.saveGState(); ctx.translateBy(x: 0, y: -w * 0.42); ctx.rotate(by: a)
            ctx.fillEllipse(in: CGRect(x: -10, y: -w * 0.42, width: 20, height: w * 0.42)); ctx.restoreGState()
        }
        ctx.restoreGState()
    }
    berryAt(668, 408, 84, 0.18)
    berryAt(758, 438, 68, -0.25)
    // blueberries, a cluster of three between the banana and the strawberries (which sit a little
    // further right than before to make room); drawn last, so they stand in front
    for (x, y, r) in [(578.0, 418.0, 31.0), (548.0, 466.0, 29.0), (608.0, 472.0, 30.0)] as [(CGFloat, CGFloat, CGFloat)] {
        ctx.setFillColor(c(blueberry)); ctx.fillEllipse(in: CGRect(x: x - r, y: y - r * 0.92, width: r * 2, height: r * 1.84))
        ctx.setFillColor(c(blueberryDeep, 0.55)); ctx.fillEllipse(in: CGRect(x: x - r * 0.1, y: y - r * 0.2, width: r * 1.0, height: r * 1.05))
        ctx.setFillColor(c(blueberryLight, 0.8)); ctx.fillEllipse(in: CGRect(x: x - r * 0.62, y: y - r * 0.62, width: r * 0.5, height: r * 0.4))
        // the little crown on top
        ctx.setFillColor(c(blueberryDeep))
        for k in 0..<5 {
            let a = CGFloat(k) / 5 * .pi * 2 - .pi / 2
            ctx.fillEllipse(in: CGRect(x: x + r * 0.12 + cos(a) * r * 0.2 - 3, y: y - r * 0.3 + sin(a) * r * 0.17 - 2.5, width: 6, height: 5))
        }
    }

    }
    ctx.restoreGState()
    // face, scaled about its own middle and moved up into the part of the bowl that shows
    ctx.saveGState(); ctx.translateBy(x: 512, y: 652 - faceUp); ctx.scaleBy(x: face, y: face); ctx.translateBy(x: -512, y: -652)
    ctx.setFillColor(c(v.face))
    ctx.fillEllipse(in: CGRect(x: 400, y: 594, width: 56, height: 62))
    ctx.fillEllipse(in: CGRect(x: 568, y: 594, width: 56, height: 62))
    ctx.setFillColor(c(0xFFFFFF, 0.85))
    ctx.fillEllipse(in: CGRect(x: 424, y: 604, width: 16, height: 16))
    ctx.fillEllipse(in: CGRect(x: 592, y: 604, width: 16, height: 16))
    ctx.setStrokeColor(c(v.face)); ctx.setLineWidth(22); ctx.setLineCap(.round)
    ctx.addArc(center: CGPoint(x: 512, y: 666), radius: 58, startAngle: .pi * 0.2, endAngle: .pi * 0.8, clockwise: false)
    ctx.strokePath()
    // cheeks
    ctx.setFillColor(c(pinkLight, 0.75))
    ctx.fillEllipse(in: CGRect(x: 326, y: 670, width: 64, height: 36))
    ctx.fillEllipse(in: CGRect(x: 634, y: 670, width: 64, height: 36))
    ctx.restoreGState()
    ctx.restoreGState()
    if word { drawWord(ctx) }
    return ctx.makeImage()!
}

/// "nourlo" across the top, centred, each letter in one of the fruit colours and the last in ink.
func drawWord(_ ctx: CGContext) {
    let url = URL(fileURLWithPath: "docs/brand/Comfortaa.ttf")
    guard let descriptors = CTFontManagerCreateFontDescriptorsFromURL(url as CFURL) as? [CTFontDescriptor], let first = descriptors.first else {
        fatalError("docs/brand/Comfortaa.ttf is missing: run from the repo root")
    }
    let size: CGFloat = 200
    let wght = NSNumber(value: 0x77676874)   // the variable font's weight axis
    let bold = CTFontDescriptorCreateCopyWithVariation(first, wght, 700)
    let font = CTFontCreateWithFontDescriptor(bold, size, nil)
    let colours: [UInt32] = [berry, 0xE0A92C, blueberry, 0x5E9B6B, 0xC4576B, ink]
    let lines = zip("nourlo", colours).map { letter, colour in
        CTLineCreateWithAttributedString(NSAttributedString(string: String(letter), attributes: [
            NSAttributedString.Key(kCTFontAttributeName as String): font,
            NSAttributedString.Key(kCTForegroundColorAttributeName as String): c(colour),
        ]))
    }
    let widths = lines.map { CGFloat(CTLineGetTypographicBounds($0, nil, nil, nil)) }
    var x = (1024 - widths.reduce(0, +)) / 2
    let baseline: CGFloat = 242
    ctx.saveGState(); ctx.translateBy(x: 0, y: baseline); ctx.scaleBy(x: 1, y: -1)
    for (line, width) in zip(lines, widths) {
        ctx.textPosition = CGPoint(x: x, y: 0)
        CTLineDraw(line, ctx)
        x += width
    }
    ctx.restoreGState()
}

func save(_ img: CGImage, _ path: String) {
    let rep = NSBitmapImageRep(cgImage: img)
    try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: path))
}

// The 1024 master for the app icon (close-up with the name) and the 288 companion for the
// welcome screen (the whole bowl, no name: the app writes "Nourlo" beside it).
// Run from the repo root:  swiftc -O docs/brand/app-icon.swift -o /tmp/app-icon && /tmp/app-icon
let master = draw(variants[0], zoom: 1.9, rimAt: 580, face: 1.12, faceUp: 66, shadow: false, fruitLeft: 50, word: true)
save(master, "smartmarket/Assets.xcassets/AppIcon.appiconset/icon_1024.png")
save(draw(variants[0], size: 288), "smartmarket/Assets.xcassets/BrandLogo.imageset/brand-logo.png")
print("ok")
