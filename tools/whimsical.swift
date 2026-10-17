// Builds Assets/ham_whimsical.png from the wizard photo: lifts the hamster out with Vision, then redraws the
// magic wand (Vision drops it along with the background sparkles) plus a few gold doodle stars.
// Usage: swift tools/whimsical.swift Assets/source_whimsical.webp Assets/ham_whimsical.png
import AppKit
import CoreImage
import Vision

let args = CommandLine.arguments
let ci = CIImage(contentsOf: URL(fileURLWithPath: args[1]))!
let req = VNGenerateForegroundInstanceMaskRequest()
let handler = VNImageRequestHandler(ciImage: ci)
try handler.perform([req])
let obs = req.results!.first!
let lifted = CIImage(cvPixelBuffer: try obs.generateMaskedImage(ofInstances: obs.allInstances, from: handler,
                                                                croppedToInstancesExtent: false))
let cut = CIContext().createCGImage(lifted, from: lifted.extent)!
let W = cut.width, H = cut.height
let ctx = CGContext(data: nil, width: W, height: H, bitsPerComponent: 8, bytesPerRow: W * 4,
                    space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
// top-left coordinates, matching how the photo reads (it's 1254×1254)
ctx.translateBy(x: 0, y: CGFloat(H)); ctx.scaleBy(x: 1, y: -1)
func P(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: x * CGFloat(W) / 1254, y: y * CGFloat(H) / 1254) }
let k = CGFloat(W) / 1254
func color(_ v: UInt32, _ a: CGFloat = 1) -> CGColor {
    NSColor(srgbRed: CGFloat((v >> 16) & 0xFF) / 255, green: CGFloat((v >> 8) & 0xFF) / 255,
            blue: CGFloat(v & 0xFF) / 255, alpha: a).cgColor
}

// 1. the wand, under the hamster so his paw stays wrapped around it
ctx.setLineCap(.round)
ctx.move(to: P(858, 630)); ctx.addLine(to: P(966, 352))
ctx.setStrokeColor(color(0x151515)); ctx.setLineWidth(10 * k); ctx.strokePath()
ctx.move(to: P(966, 352)); ctx.addLine(to: P(1011, 228))
ctx.setStrokeColor(color(0xF4EAD2)); ctx.setLineWidth(7 * k); ctx.strokePath()

// 2. the hamster on top (draw flipped back since the context is top-left)
ctx.saveGState()
ctx.translateBy(x: 0, y: CGFloat(H)); ctx.scaleBy(x: 1, y: -1)
ctx.draw(cut, in: CGRect(x: 0, y: 0, width: W, height: H))
ctx.restoreGState()

// 3. glowing tip
let tip = P(1013, 220)
let glow = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                      colors: [color(0xFFFFFF, 1), color(0xFFE7A0, 0.85), color(0xFFD36B, 0)] as CFArray,
                      locations: [0, 0.35, 1])!
ctx.drawRadialGradient(glow, startCenter: tip, startRadius: 0, endCenter: tip, endRadius: 58 * k, options: [])
func sparkle(_ c: CGPoint, _ r: CGFloat, _ col: CGColor) {   // 4-point twinkle
    let p = CGMutablePath()
    p.move(to: CGPoint(x: c.x, y: c.y - r))
    p.addQuadCurve(to: CGPoint(x: c.x + r, y: c.y), control: c)
    p.addQuadCurve(to: CGPoint(x: c.x, y: c.y + r), control: c)
    p.addQuadCurve(to: CGPoint(x: c.x - r, y: c.y), control: c)
    p.addQuadCurve(to: CGPoint(x: c.x, y: c.y - r), control: c)
    ctx.addPath(p); ctx.setFillColor(col); ctx.fillPath()
}
sparkle(tip, 34 * k, color(0xFFFFFF))

// 4. a few hand-drawn gold stars around the wand
func star(_ c: CGPoint, _ r: CGFloat, _ rot: CGFloat) {
    let p = CGMutablePath()
    for i in 0..<10 {
        let a = rot + CGFloat(i) * .pi / 5 - .pi / 2
        let rr = i % 2 == 0 ? r : r * 0.45
        let q = CGPoint(x: c.x + cos(a) * rr, y: c.y + sin(a) * rr)
        i == 0 ? p.move(to: q) : p.addLine(to: q)
    }
    p.closeSubpath()
    ctx.addPath(p); ctx.setStrokeColor(color(0xF6D987)); ctx.setLineWidth(5 * k); ctx.setLineJoin(.round); ctx.strokePath()
}
star(P(1150, 125), 38 * k, 0.15)
star(P(905, 300), 20 * k, -0.2)
sparkle(P(1095, 330), 14 * k, color(0xF6D987))
sparkle(P(880, 175), 12 * k, color(0xF6D987))
// a little swirl trailing off the tip
let swirl = CGMutablePath()
swirl.move(to: P(1013, 220))
swirl.addCurve(to: P(1080, 120), control1: P(1060, 230), control2: P(1110, 170))
swirl.addCurve(to: P(1000, 110), control1: P(1060, 80), control2: P(1010, 80))
ctx.addPath(swirl)
ctx.setStrokeColor(color(0xF6D987, 0.9)); ctx.setLineWidth(4 * k); ctx.setLineDash(phase: 0, lengths: [10 * k, 8 * k]); ctx.strokePath()
ctx.setLineDash(phase: 0, lengths: [])

// 5. crop to what's actually drawn
let full = ctx.makeImage()!
let data = ctx.data!.bindMemory(to: UInt8.self, capacity: W * H * 4)
var minX = W, minY = H, maxX = 0, maxY = 0
for y in 0..<H { for x in 0..<W where data[(y * W + x) * 4 + 3] > 8 {
    minX = min(minX, x); maxX = max(maxX, x); minY = min(minY, y); maxY = max(maxY, y) } }
let crop = full.cropping(to: CGRect(x: minX, y: minY, width: maxX - minX + 1, height: maxY - minY + 1))!
try NSBitmapImageRep(cgImage: crop).representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: args[2]))
print("wrote \(args[2]) \(crop.width)x\(crop.height)")
