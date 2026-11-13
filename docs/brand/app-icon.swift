import AppKit
import CoreGraphics

func c(_ hex: UInt32, _ a: CGFloat = 1) -> CGColor {
    CGColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255, blue: CGFloat(hex & 0xFF) / 255, alpha: a)
}
let rhino: UInt32 = 0x2E4060, rhinoDeep: UInt32 = 0x24334D, rhinoLift: UInt32 = 0x3D5480
let pink: UInt32 = 0xDD8C96, pinkDeep: UInt32 = 0xC56F7C, pinkLight: UInt32 = 0xEAB0B6
let almond: UInt32 = 0xF4DAD4, cream: UInt32 = 0xF7E8D2, banana: UInt32 = 0xF6E3A8, bananaCore: UInt32 = 0xE2C676
let berry: UInt32 = 0xD25467, berryDeep: UInt32 = 0xB23F55, leaf: UInt32 = 0x6FA77A

struct Variant { let name: String; let bg: UInt32; let bgLift: UInt32; let bowl: UInt32; let bowlShade: UInt32; let rim: UInt32; let face: UInt32; let shadow: UInt32 }
let variants = [
    Variant(name: "A-navy", bg: rhino, bgLift: rhinoLift, bowl: pink, bowlShade: pinkDeep, rim: pinkDeep, face: rhino, shadow: rhinoDeep),
    Variant(name: "B-almond", bg: almond, bgLift: 0xFBEDE8, bowl: rhino, bowlShade: rhinoDeep, rim: rhinoDeep, face: almond, shadow: 0xE3C1B9),
    Variant(name: "C-pink", bg: pink, bgLift: pinkLight, bowl: almond, bowlShade: 0xE6C3BB, rim: 0xE6C3BB, face: rhino, shadow: pinkDeep),
]

func draw(_ v: Variant, size: Int = 1024) -> CGImage {
    let ctx = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0,
                        space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
    let s = CGFloat(size) / 1024
    ctx.scaleBy(x: s, y: -s); ctx.translateBy(x: 0, y: -1024)   // top-left origin, 1024 design units

    // background: soft light from the top
    ctx.setFillColor(c(v.bg)); ctx.fill(CGRect(x: 0, y: 0, width: 1024, height: 1024))
    let g = CGGradient(colorsSpace: nil, colors: [c(v.bgLift), c(v.bg)] as CFArray, locations: [0, 1])!
    ctx.drawRadialGradient(g, startCenter: CGPoint(x: 512, y: 300), startRadius: 0, endCenter: CGPoint(x: 512, y: 380), endRadius: 720, options: [])

    ctx.saveGState()
    ctx.translateBy(x: 512, y: 520); ctx.scaleBy(x: 1.16, y: 1.16); ctx.translateBy(x: -512, y: -560)
    // ground shadow
    ctx.setFillColor(c(v.shadow, 0.55)); ctx.fillEllipse(in: CGRect(x: 262, y: 838, width: 500, height: 62))

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
    berryAt(626, 412, 86, 0.18)
    berryAt(722, 440, 70, -0.25)

    // face
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
    ctx.setFillColor(c(v.name == "A-navy" ? pinkLight : pink, 0.75))
    ctx.fillEllipse(in: CGRect(x: 326, y: 670, width: 64, height: 36))
    ctx.fillEllipse(in: CGRect(x: 634, y: 670, width: 64, height: 36))
    ctx.restoreGState()
    return ctx.makeImage()!
}

func save(_ img: CGImage, _ path: String) {
    let rep = NSBitmapImageRep(cgImage: img)
    try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: path))
}

// full-size masters + a contact sheet at real sizes (mask to iOS squircle-ish rounded rect)
var sheetImages: [(String, CGImage)] = []
for v in variants { let img = draw(v); save(img, "icon-\(v.name).png"); sheetImages.append((v.name, img)) }
let W = 1400, H = 900
let sheet = CGContext(data: nil, width: W, height: H, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
sheet.setFillColor(c(0xE9E9EE)); sheet.fill(CGRect(x: 0, y: 0, width: W, height: H))
for (i, (_, img)) in sheetImages.enumerated() {
    let x = CGFloat(60 + i * 450)
    for (size, y) in [(360, 440), (120, 230), (60, 120), (40, 40)] as [(CGFloat, CGFloat)] {
        let r = CGRect(x: x, y: y, width: size, height: size)
        sheet.saveGState()
        sheet.addPath(CGPath(roundedRect: r, cornerWidth: size * 0.225, cornerHeight: size * 0.225, transform: nil)); sheet.clip()
        sheet.interpolationQuality = .high; sheet.draw(img, in: r); sheet.restoreGState()
    }
}
save(sheet.makeImage()!, "sheet.png")
print("ok")
