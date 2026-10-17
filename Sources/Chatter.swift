import AppKit
import SwiftUI

/// Everything Ham says on his own, outside the chat.
enum Chatter {
    enum Moment { case greet, idle, wake, sleepTalk, dragStart, drop, caught, wheel, replyReady }

    private static var recent: [String] = []

    static func line(_ m: Moment, sender: String) -> String {
        let pool = lines(m, sender: sender)
        let fresh = pool.filter { !recent.contains($0) }
        let pick = (fresh.isEmpty ? pool : fresh).randomElement()!
        recent.append(pick)
        if recent.count > 16 { recent.removeFirst() }
        return pick
    }

    /// Seconds until the next unprompted line, by chattiness; nil means only react to things.
    static func gap(_ chattiness: String) -> Double? {
        switch chattiness {
        case "quiet": return nil   // no unprompted lines at all
        case "normal": return .random(in: 60...150)
        default: return .random(in: 25...60)   // "chatty"
        }
    }

    private static func lines(_ m: Moment, sender b: String) -> [String] {
        switch m {
        case .greet:
            return timeOfDay(b) + ["hi \(b)! 🐭", "Ham reporting for duty 🐹", "我来啦～"]
        case .idle:
            // a third of idle lines follow the clock
            return Double.random(in: 0..<1) < 0.33 ? timeOfDay(b) : general(b)
        case .wake:
            return ["*yawn*", "睡饱了！", "was I snoring?", "dreamt of a giant sunflower 🌻", "…what did I miss?"]
        case .sleepTalk:
            return ["…mm…seeds…", "zz…five more minutes…", "…\(b)…snack…", "…瓜子…"]
        case .dragStart:
            return ["whoa—", "去哪儿呀～", "put me dooown", "I'm flying!", "wheee—"]
        case .drop:
            return ["wheee!", "again!", "hmph.", "🌻?", "safe landing ✨", "放我下来啦", "10/10 flight"]
        case .caught:
            return ["♡ caught you!", "抓到你了", "hi hi hi", "your cursor smells like seeds"]
        case .wheel:
            return ["cardio day 💪", "Mouse's Health said 5 miles today", "running running running", "跑起来！",
                    "wheel goes brrr"]
        case .replyReady:
            return ["answer's ready! click me 🐹", "答案好啦～点我看看", "I figured it out! come see"]
        }
    }

    private static func general(_ b: String) -> [String] {
        ["squeak!", "*nibble nibble*", "cheeks: 80% full", "reading Mouse's Health… page 7: cheek day 💪",
         "need anything? I'm right here", "fun fact: hamsters can run miles a night (in the wheel)",
         "我在呢，有问题随时戳我", "今天也要好好吃饭哦 🐭", "drink some water, little rat 💧", "stretch break? 伸个懒腰～",
         "I believe in you (and in sunflower seeds) 🌻", "you're doing great, \(b)", "ask me anything! small but smart",
         "*rearranges bedding*", "hmm… thinking about seeds", "存了一颗瓜子给你 🌻", "is it snack o'clock?", "嘿嘿",
         "*washes face very seriously*", "the real hamster says hi (probably)", "squeak if you need me",
         "我刚刚学会了一个新单词: cheek pouch", "everything ok over there?", "*peeks at your screen* ooh"]
    }

    private static func timeOfDay(_ b: String) -> [String] {
        switch Calendar.current.component(.hour, from: Date()) {
        case 5..<11: return ["good morning \(b) ☀️", "早上好！吃早饭了吗", "coffee for you, seeds for me", "早起的仓鼠有瓜子吃"]
        case 11..<14: return ["lunch time? 午饭吃什么", "I recommend sunflower seeds for lunch", "饿了吗 🍜"]
        case 14..<18: return ["afternoon slump? 来颗瓜子提提神", "tea break? 🍵", "下午也要加油呀"]
        case 18..<23: return ["晚上好～今天辛苦啦", "dinner? 🍜", "evening = hamster prime time 🌙", "today was a good day, right?"]
        default: return ["it's late… rats need sleep too 🐭💤", "还不睡吗？明天再弄吧", "I'm nocturnal, but you're not",
                         "go to bed \(b)! I'll guard the laptop"]
        }
    }
}

/// A speech bubble in its own tiny window. It ignores the mouse, so it never blocks what's under it.
final class BubbleController {
    private let panel: NSPanel
    private let host = NSHostingView(rootView: SpeechBubble(text: "", width: 40))
    private var generation = 0
    var isShowing: Bool { panel.isVisible }

    init() {
        panel = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.ignoresMouseEvents = true
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle, .stationary]
        panel.contentView = host
    }

    /// `anchor` is where the bubble's tail points (screen coordinates).
    func show(_ text: String, at anchor: NSPoint, for seconds: Double) {
        generation += 1
        let g = generation
        host.rootView = SpeechBubble(text: text, width: SpeechBubble.width(for: text))
        panel.setContentSize(host.fittingSize)
        move(to: anchor)
        panel.alphaValue = 0
        panel.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { $0.duration = 0.18; panel.animator().alphaValue = 1 }
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds) { [weak self] in
            if self?.generation == g { self?.hide() }
        }
    }

    func move(to anchor: NSPoint) {
        let size = panel.frame.size
        var o = NSPoint(x: anchor.x - size.width / 2, y: anchor.y)
        if let s = (NSScreen.screens.first { $0.frame.contains(anchor) } ?? NSScreen.main)?.frame {
            o.x = min(max(o.x, s.minX + 4), s.maxX - size.width - 4)
            o.y = min(o.y, s.maxY - size.height)
        }
        panel.setFrameOrigin(o)
    }

    func hide() {
        let g = generation
        NSAnimationContext.runAnimationGroup({ $0.duration = 0.25; panel.animator().alphaValue = 0 }) { [weak self] in
            if self?.generation == g { self?.panel.orderOut(nil) }
        }
    }
}

struct SpeechBubble: View {
    var text: String
    var width: CGFloat
    static let font = NSFont.systemFont(ofSize: 11.5, weight: .medium)

    /// One line when it fits, wrapping at 190pt otherwise.
    static func width(for text: String) -> CGFloat {
        let w = (text as NSString).size(withAttributes: [.font: font]).width
        return min(ceil(w) + 6, 190)
    }

    var body: some View {
        VStack(spacing: 0) {
            Text(text)
                .font(.system(size: 11.5, weight: .medium, design: .rounded))
                .foregroundColor(Theme.ink)
                .multilineTextAlignment(.center)
                .frame(width: width)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 10).padding(.vertical, 6)
                .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.white))
                .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(Theme.hairline))
            Tail().fill(Color.white).frame(width: 12, height: 6).offset(y: -0.5)
        }
        .padding(.horizontal, 6).padding(.top, 4).padding(.bottom, 2)
        .shadow(color: .black.opacity(0.16), radius: 3, y: 1)
    }
}

private struct Tail: Shape {
    func path(in r: CGRect) -> Path {
        Path { p in
            p.move(to: CGPoint(x: r.minX, y: r.minY))
            p.addLine(to: CGPoint(x: r.midX, y: r.maxY))
            p.addLine(to: CGPoint(x: r.maxX, y: r.minY))
            p.closeSubpath()
        }
    }
}
