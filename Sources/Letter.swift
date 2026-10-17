import AppKit

/// What actually goes to Gary: one iMessage text line plus a letter-looking picture.
struct Letter {
    var note: String
    var sender: String
    var kaomoji: String
    var date = Date()
    var paper: HandLetter.Paper = .legal

    static let kaomojis = ["(っ˘ω˘ς )", "ฅ(•ㅅ•❀)ฅ", "(๑•̀ㅂ•́)و✧", "(〃ω〃)", "ʕ•ᴥ•ʔ", "(=^･ω･^=)",
                           "٩(◕‿◕｡)۶", "(｡•̀ᴗ-)✧", "(ﾉ◕ヮ◕)ﾉ*:･ﾟ✧", "( ˘ ³˘)♥", "(•ө•)♡", "(*˘︶˘*).｡.:*♡",
                           "(ง •̀_•́)ง", "(｡･ω･｡)ﾉ♡", "ヾ(•ω•`)o"]

    static func random(_ note: String, cfg: HamConfig) -> Letter {
        Letter(note: note.trimmingCharacters(in: .whitespacesAndNewlines), sender: cfg.senderName,
               kaomoji: kaomojis.randomElement()!, paper: HandLetter.Paper.allCases.randomElement()!)
    }

    func rerolled() -> Letter {
        var l = self
        l.kaomoji = Self.kaomojis.filter { $0 != kaomoji }.randomElement()!
        return l
    }

    func nextPaper() -> Letter {
        var l = self
        let all = HandLetter.Paper.allCases
        l.paper = all[(all.firstIndex(of: paper)! + 1) % all.count]
        return l
    }

    func picture() -> CGImage? {
        HandLetter.render(note: note, sender: sender, kaomoji: kaomoji, date: date, paper: paper)
    }

    /// The text bubble Gary sees (also shows in his notification preview).
    var textLine: String {
        "🐹💌 according to Ham in \(sender)'s laptop, \(sender) wants to tell you: \(note) \(kaomoji)"
    }

    /// Renders the handwritten letter to ~/Pictures/HamsterPal Letters/ (Messages reliably attaches files from Pictures).
    func renderPNG() -> URL? {
        let dir = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Pictures/HamsterPal Letters")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd_HHmmss"
        let url = dir.appendingPathComponent("letter_\(f.string(from: date)).png")
        guard let cg = picture(),
              let png = NSBitmapImageRep(cgImage: cg).representation(using: .png, properties: [:]),
              (try? png.write(to: url)) != nil else { return nil }
        return url
    }
}
