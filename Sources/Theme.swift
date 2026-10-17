import SwiftUI

/// Chat palette: Gary the caramel hamster × Bonnie the grey fancy rat.
enum Theme {
    // hamster side (Gary / Ham)
    static let caramel = Color(hex: 0xE7A86C)
    static let caramelDeep = Color(hex: 0xC98B52)
    static let hamCream = Color(hex: 0xFFF3E4)
    // rat side (Bonnie)
    static let ratGrey = Color(hex: 0xA9A5B0)
    static let ratGreyDeep = Color(hex: 0x8C8794)
    static let ratMist = Color(hex: 0xF0EEF3)
    // shared: the pink of ears, noses and tails
    static let pink = Color(hex: 0xF2A9B6)
    static let pinkDeep = Color(hex: 0xE58A9C)

    static let paper = Color(hex: 0xFCFAF7)
    static let ink = Color(hex: 0x3B3236)
    static let inkSoft = Color(hex: 0x3B3236, opacity: 0.55)
    static let hairline = Color(hex: 0x3B3236, opacity: 0.08)

    static let headerWash = LinearGradient(colors: [Color(hex: 0xFFEEDC), Color(hex: 0xF6F1EE), Color(hex: 0xECEAF0)],
                                           startPoint: .leading, endPoint: .trailing)
    static let ratBubble = LinearGradient(colors: [Color(hex: 0xB4B0BA), Color(hex: 0x9C97A3)],
                                          startPoint: .top, endPoint: .bottom)
}

/// Emoji avatar in a soft tinted circle: 🐭 for Bonnie, 🐹 for Ham/Gary.
struct EmojiAvatar: View {
    var emoji: String
    var tint: Color
    var size: CGFloat = 24
    static func rat(_ size: CGFloat = 24) -> EmojiAvatar { EmojiAvatar(emoji: "🐭", tint: Theme.ratMist, size: size) }
    static func ham(_ size: CGFloat = 24) -> EmojiAvatar { EmojiAvatar(emoji: "🐹", tint: Theme.hamCream, size: size) }
    var body: some View {
        Text(emoji).font(.system(size: size * 0.66))
            .frame(width: size, height: size)
            .background(Circle().fill(tint))
            .overlay(Circle().stroke(Theme.hairline))
    }
}

/// 🐹 and 🐭 side by side with a tiny heart.
struct EmojiPair: View {
    var size: CGFloat = 26
    var body: some View {
        ZStack {
            EmojiAvatar.ham(size).offset(x: -size * 0.38)
            EmojiAvatar.rat(size).offset(x: size * 0.38)
            Image(systemName: "heart.fill").font(.system(size: size * 0.26))
                .foregroundColor(Theme.pinkDeep).offset(y: -size * 0.55)
        }
        .frame(width: size * 1.8, height: size * 1.2)
    }
}

/// A faint row of alternating hamster/rat paw prints, used as a divider.
struct PawTrail: View {
    var body: some View {
        HStack(spacing: 7) {
            ForEach(0..<9) { i in
                Image(systemName: "pawprint.fill").font(.system(size: 6.5))
                    .foregroundColor(i % 2 == 0 ? Theme.caramel : Theme.ratGrey)
                    .rotationEffect(.degrees(i % 2 == 0 ? -15 : 15))
                    .offset(y: i % 2 == 0 ? -1.5 : 1.5)
            }
        }
        .opacity(0.45)
    }
}
