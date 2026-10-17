import AppKit
import CoreText

/// Renders a note as a photo-like handwritten letter: lined paper on a wooden desk, ink that wobbles a little,
/// fold creases, more pages when it's long. Drawn with Core Graphics so baselines sit exactly on the ruled lines.
/// Everything random is seeded from the letter, so the preview and the sent picture are identical.
enum HandLetter {
    enum Paper: String, CaseIterable { case legal, grid, cream }

    struct Style {
        var paper: Paper
        var bg: NSColor, rule: NSColor, ink: NSColor
        var spacing: CGFloat       // distance between ruled lines
        var marginX: CGFloat
        static func of(_ p: Paper) -> Style {
            switch p {
            case .legal: return Style(paper: p, bg: hex(0xFCF5CF), rule: hex(0x9DBCE0), ink: hex(0x1F2B57), spacing: 32, marginX: 92)
            case .grid: return Style(paper: p, bg: hex(0xFAFAF6), rule: hex(0xB7D0E8), ink: hex(0x22252B), spacing: 36, marginX: 54)
            case .cream: return Style(paper: p, bg: hex(0xFBF5EA), rule: hex(0xE2D3D8), ink: hex(0x3A2A4A), spacing: 32, marginX: 60)
            }
        }
    }

    static let pageSize = CGSize(width: 600, height: 800)
    static let latinFont = "BradleyHandITCTT-Bold"
    static let cjkFont = "HanziPenSC-W3"

    // MARK: entry point

    static func render(note: String, sender: String, recipient: String = "Gary", kaomoji: String,
                       date: Date, paper: Paper, scale: CGFloat = 2) -> CGImage? {
        let style = Style.of(paper)
        var rng = SeededRNG(seed: fnv(note + kaomoji + paper.rawValue + "\(Int(date.timeIntervalSince1970 / 60))"))
        let (pages, lastLine) = layout(note: note, sender: sender, recipient: recipient, kaomoji: kaomoji, date: date,
                                       style: style, rng: &rng)
        // a last page that's mostly empty gets trimmed, like a half sheet
        let top: CGFloat = style.paper == .legal ? 112 : 96
        let lastH = min(pageSize.height, max(380, top + CGFloat(lastLine + 1) * style.spacing + 150))
        let heights = pages.indices.map { $0 == pages.count - 1 ? lastH : pageSize.height }

        // pages stacked down a wooden desk, each slightly askew
        let gap: CGFloat = 26, pad: CGFloat = 44
        let canvas = CGSize(width: pageSize.width + pad * 2,
                            height: heights.reduce(0, +) + CGFloat(pages.count - 1) * gap + pad * 2)
        guard let ctx = CGContext(data: nil, width: Int(canvas.width * scale), height: Int(canvas.height * scale),
                                  bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        ctx.scaleBy(x: scale, y: scale)
        // flip to top-left origin, which is easier to think in; text undoes it locally
        ctx.translateBy(x: 0, y: canvas.height)
        ctx.scaleBy(x: 1, y: -1)

        drawDesk(ctx, size: canvas, rng: &rng)
        var y = pad
        for (i, page) in pages.enumerated() {
            let size = CGSize(width: pageSize.width, height: heights[i])
            ctx.saveGState()
            ctx.translateBy(x: pad + size.width / 2, y: y + size.height / 2)
            ctx.rotate(by: CGFloat.random(in: -1.3...1.3, using: &rng) * .pi / 180)
            ctx.translateBy(x: -size.width / 2, y: -size.height / 2)
            drawPaper(ctx, size: size, style: style, rng: &rng)
            for item in page { item.draw(ctx, style: style) }
            if i == 0 { drawSticker(ctx) }
            y += size.height + gap
            ctx.restoreGState()
        }
        return ctx.makeImage()
    }

    // MARK: layout

    /// Something placed on a page.
    enum Item {
        case text(String, font: String, size: CGFloat, x: CGFloat, baseline: CGFloat, angle: CGFloat, alpha: CGFloat)
        case heart(x: CGFloat, baseline: CGFloat)

        func draw(_ ctx: CGContext, style: Style) {
            switch self {
            case let .text(s, font, size, x, baseline, angle, alpha):
                let f = CTFontCreateWithName(font as CFString, size, nil)
                let color = style.ink.withAlphaComponent(alpha)
                let attr = NSAttributedString(string: s, attributes: [.font: f, .foregroundColor: color])
                let line = CTLineCreateWithAttributedString(attr)
                ctx.saveGState()
                ctx.translateBy(x: x, y: baseline)
                ctx.rotate(by: angle)
                ctx.scaleBy(x: 1, y: -1)   // Core Text wants y-up
                ctx.textPosition = .zero
                CTLineDraw(line, ctx)
                ctx.restoreGState()
            case let .heart(x, baseline):
                let p = CGMutablePath()
                let s: CGFloat = 9, y = baseline - 7
                p.move(to: CGPoint(x: x, y: y + s * 0.9))
                p.addCurve(to: CGPoint(x: x, y: y), control1: CGPoint(x: x - s * 1.3, y: y + s * 0.1),
                           control2: CGPoint(x: x - s * 0.6, y: y - s * 0.9))
                p.addCurve(to: CGPoint(x: x, y: y + s * 0.9), control1: CGPoint(x: x + s * 0.6, y: y - s * 0.9),
                           control2: CGPoint(x: x + s * 1.3, y: y + s * 0.1))
                ctx.addPath(p)
                ctx.setStrokeColor(style.ink.withAlphaComponent(0.85).cgColor)
                ctx.setLineWidth(1.6)
                ctx.setLineCap(.round)
                ctx.strokePath()
            }
        }
    }

    private struct Token {
        enum Kind { case word, cjk, emoji, space, newline }
        var kind: Kind
        var text: String
    }

    private static func tokenize(_ s: String) -> [Token] {
        var out: [Token] = []
        var word = ""
        func flush() { if !word.isEmpty { out.append(Token(kind: .word, text: word)); word = "" } }
        for ch in s {
            if ch.isNewline { flush(); out.append(Token(kind: .newline, text: "\n")) }
            else if ch == " " || ch == "\t" { flush(); out.append(Token(kind: .space, text: " ")) }
            else if isCJK(ch) { flush(); out.append(Token(kind: .cjk, text: String(ch))) }
            else if isEmoji(ch) { flush(); out.append(Token(kind: .emoji, text: String(ch))) }
            else { word.append(ch) }
        }
        flush()
        return out
    }

    private static func layout(note: String, sender: String, recipient: String, kaomoji: String, date: Date,
                               style: Style, rng: inout SeededRNG) -> (pages: [[Item]], lastLine: Int) {
        let top: CGFloat = style.paper == .legal ? 112 : 96
        let right = pageSize.width - 44
        let linesPerPage = Int((pageSize.height - top - 40) / style.spacing)
        let latin: CGFloat = 20, cjk: CGFloat = 21
        let anyCJK = note.contains { isCJK($0) }

        var pages: [[Item]] = [[]]
        var line = 0
        var x = style.marginX
        var drift: CGFloat = 0   // each line wanders a hair up or down

        func baseline() -> CGFloat { top + CGFloat(line) * style.spacing - 4 + drift }
        func newLine(indent: CGFloat = 0) {
            line += 1
            if line >= linesPerPage { pages.append([]); line = 0 }
            x = style.marginX + indent + CGFloat.random(in: -2...3, using: &rng)
            drift = CGFloat.random(in: -1.2...1.2, using: &rng)
        }
        /// Places one word/character with a little wobble; returns the width it actually took.
        @discardableResult
        func put(_ s: String, font: String, size: CGFloat, at px: CGFloat, wobble: CGFloat = 1) -> CGFloat {
            let sz = size * CGFloat.random(in: 0.96...1.05, using: &rng)
            pages[pages.count - 1].append(.text(s, font: font, size: sz, x: px,
                                                baseline: baseline() + CGFloat.random(in: -1...1, using: &rng) * wobble,
                                                angle: CGFloat.random(in: -1.6...1.6, using: &rng) * wobble * .pi / 180,
                                                alpha: CGFloat.random(in: 0.82...1, using: &rng)))
            return width(s, font: font, size: sz)
        }

        // date, top right of page 1
        let df = DateFormatter()
        df.dateFormat = anyCJK ? "yyyy年M月d日" : "EEE. d MMM yy"
        let dateText = df.string(from: date)
        let dateFont = anyCJK ? cjkFont : latinFont
        put(dateText, font: dateFont, size: anyCJK ? 19 : 19,
            at: right - width(dateText, font: dateFont, size: 19) - 6)
        newLine()
        put(anyCJK ? "亲爱的 \(recipient)：" : "Dear \(recipient) —", font: anyCJK ? cjkFont : latinFont, size: anyCJK ? cjk + 1 : latin + 1, at: x)
        newLine(indent: 32)

        // body
        let tokens = tokenize(note.trimmingCharacters(in: .whitespacesAndNewlines))
        let closers: Set<String> = ["，", "。", "！", "？", "、", "；", "：", "」", "』", "）", "…", "”", "’", ",", "."]
        var lineHasText = false
        var i = 0
        while i < tokens.count {
            let t = tokens[i]
            switch t.kind {
            case .newline:
                // consecutive newlines become a single paragraph break
                while i + 1 < tokens.count && tokens[i + 1].kind == .newline { i += 1 }
                newLine(indent: 32); lineHasText = false
            case .space:
                if lineHasText { x += width(" ", font: latinFont, size: latin) * CGFloat.random(in: 0.9...1.3, using: &rng) }
            case .word, .cjk, .emoji:
                let font = t.kind == .cjk ? cjkFont : t.kind == .emoji ? "AppleColorEmoji" : latinFont
                let size = t.kind == .cjk ? cjk : t.kind == .emoji ? 17 : latin
                let w = width(t.text, font: font, size: size)
                // wrap, but let closing punctuation hang off the edge instead of starting a line
                if lineHasText && x + w > right && !closers.contains(t.text) { newLine(); lineHasText = false }
                let used = put(t.text, font: font, size: size, at: x, wobble: t.kind == .word ? 0.7 : 1)
                x += used + (t.kind == .cjk ? CGFloat.random(in: -0.6...1.2, using: &rng) : 1.5)
                lineHasText = true
            }
            i += 1
        }

        // sign-off: "love," then the name with a little heart and the kaomoji.
        // squeeze it onto this page rather than leaving it alone on a fresh one
        let left = linesPerPage - 1 - line
        let love = anyCJK ? "爱你的，" : "love,"
        let loveFont = anyCJK ? cjkFont : latinFont
        var signX = pageSize.width * 0.52
        // the bottom margin still has ruled lines; the sign-off may borrow one rather than go to a new page
        let canBorrow = left <= 0 && top + CGFloat(line + 1) * style.spacing <= pageSize.height - 14
        if left >= 3 { newLine(); newLine() } else if canBorrow { line += 1 } else { newLine() }
        if left == 1 || canBorrow {
            signX = pageSize.width * 0.42
            put(love, font: loveFont, size: latin + 1, at: signX)
            signX += width(love, font: loveFont, size: latin + 1) - 14
        } else {
            put(love, font: loveFont, size: latin + 1, at: signX)
            newLine()
        }
        let name = sender
        let nameW = put(name, font: latinFont, size: latin + 4, at: signX + 22)
        let nameEnd = signX + 22 + nameW
        pages[pages.count - 1].append(.heart(x: nameEnd + 14, baseline: baseline()))
        put(kaomoji, font: latinFont, size: 15, at: nameEnd + 30, wobble: 0.5)
        return (pages, line)
    }

    // MARK: drawing pieces

    private static func drawDesk(_ ctx: CGContext, size: CGSize, rng: inout SeededRNG) {
        let wood = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                              colors: [hex(0x8E5B3B).cgColor, hex(0x6F4329).cgColor, hex(0x80512F).cgColor] as CFArray,
                              locations: [0, 0.55, 1])!
        ctx.drawLinearGradient(wood, start: .zero, end: CGPoint(x: size.width, y: size.height), options: [])
        // grain
        for _ in 0..<Int(size.height / 5) {
            let y = CGFloat.random(in: 0...size.height, using: &rng)
            let p = CGMutablePath()
            p.move(to: CGPoint(x: 0, y: y))
            var cx: CGFloat = 0
            while cx < size.width {
                cx += 60
                p.addQuadCurve(to: CGPoint(x: cx, y: y + CGFloat.random(in: -3...3, using: &rng)),
                               control: CGPoint(x: cx - 30, y: y + CGFloat.random(in: -4...4, using: &rng)))
            }
            ctx.addPath(p)
            let dark = Bool.random(using: &rng)
            ctx.setStrokeColor((dark ? NSColor.black : NSColor.white).withAlphaComponent(dark ? 0.07 : 0.035).cgColor)
            ctx.setLineWidth(CGFloat.random(in: 0.5...2.2, using: &rng))
            ctx.strokePath()
        }
    }

    private static func drawPaper(_ ctx: CGContext, size: CGSize, style: Style, rng: inout SeededRNG) {
        let pageSize = size
        let r = CGRect(origin: .zero, size: pageSize)
        ctx.saveGState()
        ctx.setShadow(offset: CGSize(width: 0, height: 6), blur: 14, color: NSColor.black.withAlphaComponent(0.35).cgColor)
        ctx.setFillColor(style.bg.cgColor)
        ctx.fill(r)
        ctx.restoreGState()

        ctx.saveGState()
        ctx.clip(to: r)
        // rules
        ctx.setStrokeColor(style.rule.withAlphaComponent(style.paper == .grid ? 0.55 : 0.8).cgColor)
        switch style.paper {
        case .grid:
            ctx.setLineWidth(0.6)
            var v: CGFloat = 18
            while v < pageSize.width { ctx.move(to: CGPoint(x: v, y: 0)); ctx.addLine(to: CGPoint(x: v, y: pageSize.height)); v += 18 }
            v = 6
            while v < pageSize.height { ctx.move(to: CGPoint(x: 0, y: v)); ctx.addLine(to: CGPoint(x: pageSize.width, y: v)); v += 18 }
            ctx.strokePath()
        case .legal, .cream:
            ctx.setLineWidth(0.8)
            var y: CGFloat = style.paper == .legal ? 112 : 96
            while y < pageSize.height - 10 {
                ctx.move(to: CGPoint(x: 0, y: y)); ctx.addLine(to: CGPoint(x: pageSize.width, y: y)); y += style.spacing
            }
            ctx.strokePath()
            if style.paper == .legal {   // the red double margin
                ctx.setStrokeColor(hex(0xE59A9A).withAlphaComponent(0.85).cgColor)
                ctx.setLineWidth(0.9)
                for mx in [style.marginX - 14, style.marginX - 10] as [CGFloat] {
                    ctx.move(to: CGPoint(x: mx, y: 0)); ctx.addLine(to: CGPoint(x: mx, y: pageSize.height))
                }
                ctx.strokePath()
            }
        }
        // paper grain
        for _ in 0..<1400 {
            let p = CGPoint(x: CGFloat.random(in: 0...pageSize.width, using: &rng),
                            y: CGFloat.random(in: 0...pageSize.height, using: &rng))
            ctx.setFillColor(NSColor.black.withAlphaComponent(CGFloat.random(in: 0.015...0.05, using: &rng)).cgColor)
            ctx.fillEllipse(in: CGRect(x: p.x, y: p.y, width: 1.1, height: 1.1))
        }
        // fold creases at thirds
        for f in [CGFloat(1) / 3, CGFloat(2) / 3] {
            let y = pageSize.height * f + CGFloat.random(in: -4...4, using: &rng)
            let g = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                               colors: [NSColor.black.withAlphaComponent(0).cgColor,
                                        NSColor.black.withAlphaComponent(0.07).cgColor,
                                        NSColor.white.withAlphaComponent(0.25).cgColor,
                                        NSColor.white.withAlphaComponent(0).cgColor] as CFArray,
                               locations: [0, 0.48, 0.52, 1])!
            ctx.drawLinearGradient(g, start: CGPoint(x: 0, y: y - 6), end: CGPoint(x: 0, y: y + 6), options: [])
        }
        // light falloff toward the edges, like a photo
        let vignette = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                                  colors: [NSColor.white.withAlphaComponent(0.06).cgColor,
                                           NSColor.black.withAlphaComponent(0.09).cgColor] as CFArray,
                                  locations: [0, 1])!
        ctx.drawRadialGradient(vignette, startCenter: CGPoint(x: pageSize.width * 0.45, y: pageSize.height * 0.4),
                               startRadius: 0, endCenter: CGPoint(x: pageSize.width / 2, y: pageSize.height / 2),
                               endRadius: pageSize.height * 0.75, options: [.drawsAfterEndLocation])
        ctx.restoreGState()
    }

    /// Ham as a die-cut sticker in the empty top-left corner of the first page, clear of the writing.
    private static func drawSticker(_ ctx: CGContext) {
        guard let img = PhotoHamster.image, var cg = img.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return }
        let h: CGFloat = 70, w = h * CGFloat(cg.width) / CGFloat(cg.height)
        let r = CGRect(x: 26, y: 10, width: w, height: h)
        ctx.saveGState()
        ctx.translateBy(x: r.midX, y: r.midY)
        ctx.rotate(by: -9 * .pi / 180)
        ctx.scaleBy(x: 1, y: -1)
        let local = CGRect(x: -w / 2, y: -h / 2, width: w, height: h)
        // white outline: the silhouette stamped around in a ring, then the photo on top
        if let mask = whiteSilhouette(cg) {
            ctx.setShadow(offset: CGSize(width: 0, height: -2), blur: 4, color: NSColor.black.withAlphaComponent(0.3).cgColor)
            for a in stride(from: 0.0, to: 360.0, by: 30.0) {
                let d: CGFloat = 4
                ctx.draw(mask, in: local.offsetBy(dx: d * cos(a * .pi / 180), dy: d * sin(a * .pi / 180)))
            }
            ctx.setShadow(offset: .zero, blur: 0, color: nil)
        }
        cg = cg.copy() ?? cg
        ctx.draw(cg, in: local)
        ctx.restoreGState()
    }

    private static func whiteSilhouette(_ img: CGImage) -> CGImage? {
        let w = img.width, h = img.height
        guard let c = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                                space: CGColorSpaceCreateDeviceRGB(),
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        let r = CGRect(x: 0, y: 0, width: w, height: h)
        c.clip(to: r, mask: img)
        c.setFillColor(NSColor.white.cgColor)
        c.fill(r)
        return c.makeImage()
    }

    // MARK: helpers

    private static var widthCache: [String: CGFloat] = [:]
    static func width(_ s: String, font: String, size: CGFloat) -> CGFloat {
        let key = "\(font)|\(size)|\(s)"
        if let w = widthCache[key] { return w }
        let f = CTFontCreateWithName(font as CFString, size, nil)
        let line = CTLineCreateWithAttributedString(NSAttributedString(string: s, attributes: [.font: f]))
        let w = CGFloat(CTLineGetTypographicBounds(line, nil, nil, nil))
        widthCache[key] = w
        return w
    }

    private static func isCJK(_ ch: Character) -> Bool {
        guard let v = ch.unicodeScalars.first?.value else { return false }
        return (0x2E80...0x9FFF).contains(v) || (0xF900...0xFAFF).contains(v) || (0xFF00...0xFFEF).contains(v)
            || (0x3000...0x303F).contains(v) || (0x20000...0x2FA1F).contains(v) || v == 0x201C || v == 0x201D
    }

    private static func isEmoji(_ ch: Character) -> Bool {
        guard let s = ch.unicodeScalars.first else { return false }
        return s.properties.isEmojiPresentation || (s.properties.isEmoji && ch.unicodeScalars.count > 1)
    }

    private static func fnv(_ s: String) -> UInt64 {
        var h: UInt64 = 0xcbf29ce484222325
        for b in s.utf8 { h = (h ^ UInt64(b)) &* 0x100000001b3 }
        return h
    }

    static func hex(_ v: UInt32) -> NSColor {
        NSColor(srgbRed: CGFloat((v >> 16) & 0xFF) / 255, green: CGFloat((v >> 8) & 0xFF) / 255,
                blue: CGFloat(v & 0xFF) / 255, alpha: 1)
    }
}

/// Small deterministic RNG (SplitMix64) so a given letter always renders the same way.
struct SeededRNG: RandomNumberGenerator {
    var state: UInt64
    init(seed: UInt64) { state = seed }
    mutating func next() -> UInt64 {
        state &+= 0x9E3779B97F4A7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
        z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
        return z ^ (z >> 31)
    }
}
