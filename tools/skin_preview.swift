// Mockup sheet: current Ham vs. a candidate skin, big and at real on-screen sizes.
// Usage: swift tools/skin_preview.swift Assets/ham.png Assets/ham_jacket.png build/skin-preview.png
import AppKit
let a = CommandLine.arguments
let cur = NSImage(contentsOfFile: a[1])!, new = NSImage(contentsOfFile: a[2])!
func fit(_ img: NSImage, h: CGFloat) -> NSSize { NSSize(width: h * img.size.width / img.size.height, height: h) }
let sheet = NSImage(size: NSSize(width: 1100, height: 900), flipped: true) { _ in
    NSColor(srgbRed: 0.98, green: 0.96, blue: 0.93, alpha: 1).setFill(); NSRect(x: 0, y: 0, width: 1100, height: 900).fill()
    let t: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 22, weight: .bold), .foregroundColor: NSColor(white: 0.2, alpha: 1)]
    let s: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 13), .foregroundColor: NSColor(white: 0.85, alpha: 1)]
    ("now" as NSString).draw(at: NSPoint(x: 230, y: 24), withAttributes: t)
    ("jacket skin" as NSString).draw(at: NSPoint(x: 740, y: 24), withAttributes: t)
    var z = fit(cur, h: 480); cur.draw(in: NSRect(x: 260 - z.width / 2, y: 70, width: z.width, height: z.height))
    z = fit(new, h: 480); new.draw(in: NSRect(x: 800 - z.width / 2, y: 70, width: z.width, height: z.height))
    // desktop strip at real sizes
    NSColor(srgbRed: 0.16, green: 0.2, blue: 0.3, alpha: 1).setFill(); NSRect(x: 40, y: 600, width: 1020, height: 260).fill()
    ("on the desktop (50pt)" as NSString).draw(at: NSPoint(x: 70, y: 616), withAttributes: s)
    ("2× for a closer look" as NSString).draw(at: NSPoint(x: 330, y: 616), withAttributes: s)
    ("in the Dock" as NSString).draw(at: NSPoint(x: 720, y: 616), withAttributes: s)
    for (i, img) in [cur, new].enumerated() {
        var q = fit(img, h: 50); img.draw(in: NSRect(x: 90 + CGFloat(i) * 90, y: 760, width: q.width, height: q.height))
        q = fit(img, h: 100); img.draw(in: NSRect(x: 330 + CGFloat(i) * 150, y: 710, width: q.width, height: q.height))
        // Dock tile: cream squircle like Ham's icon
        let tile = NSRect(x: 720 + CGFloat(i) * 150, y: 690, width: 110, height: 110)
        NSColor(srgbRed: 1, green: 0.93, blue: 0.84, alpha: 1).setFill()
        NSBezierPath(roundedRect: tile.insetBy(dx: 7, dy: 7), xRadius: 22, yRadius: 22).fill()
        q = fit(img, h: 82); img.draw(in: NSRect(x: tile.midX - q.width / 2, y: tile.maxY - q.height - 12, width: q.width, height: q.height))
    }
    return true
}
try! NSBitmapImageRep(data: sheet.tiffRepresentation!)!.representation(using: .png, properties: [:])!
    .write(to: URL(fileURLWithPath: a[3]))
print("ok")
