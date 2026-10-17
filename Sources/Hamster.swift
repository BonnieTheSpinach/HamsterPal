import SwiftUI

enum PetMode { case idle, walking, chasing, running, sleeping, dragged, thinking }

final class PetState: ObservableObject {
    @Published var mode: PetMode = .idle
    @Published var facingRight = true
    @Published var phase: Double = 0
    @Published var blinking = false
    @Published var happy = false
    @Published var bubble: String?
    @Published var photo = true   // photo Ham (cut out of Bonnie's picture) vs the drawn one
}

extension Color {
    init(hex: UInt32, opacity: Double = 1) {
        self.init(red: Double((hex >> 16) & 0xFF) / 255, green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255, opacity: opacity)
    }
    static let furTop = Color(hex: 0xF6BE7A)
    static let furLow = Color(hex: 0xEDA05A)
    static let outline = Color(hex: 0xB8743A)
    static let belly = Color(hex: 0xFFF9F0)
    static let blush = Color(hex: 0xFF9AA2)
    static let paw = Color(hex: 0xFFD3CF)
    static let ink = Color(hex: 0x2E1D13)
}

/// The hamster itself, drawn in a 100×100 design space (facing right) and scaled to `size`.
struct HamsterFigure: View {
    @ObservedObject var s: PetState
    var size: CGFloat
    var speed: Double = 1   // leg speed multiplier (wheel running is faster)

    var body: some View {
        let moving = [.walking, .chasing, .running].contains(s.mode)
        let dragged = s.mode == .dragged
        let bob = moving ? -abs(sin(s.phase * 2 * speed)) * 2.5
                         : s.mode == .sleeping ? sin(s.phase * 0.5) * 1.2 : sin(s.phase * 0.7) * 0.6
        let step = moving ? sin(s.phase * 4 * speed) * 2.6 : dragged ? sin(s.phase * 9) * 3 : 0

        ZStack {
            // feet
            foot.offset(x: -17 + step, y: 40 + (dragged ? 4 : 0))
            foot.offset(x: 17 - step, y: 40 + (dragged ? 4 : 0))
            // ears, behind the body
            ear.offset(x: -17, y: -19)
            ear.offset(x: 15, y: -22)
            // body with white underside and face patch
            ZStack {
                Ellipse().fill(LinearGradient(colors: [.furTop, .furLow], startPoint: .top, endPoint: .bottom))
                Ellipse().fill(Color.belly).frame(width: 66, height: 46).offset(x: 4, y: 22)
                Ellipse().fill(Color.belly).frame(width: 46, height: 32).offset(x: 8, y: 6)
            }
            .frame(width: 78, height: 66)
            .clipShape(Ellipse())
            .overlay(Ellipse().stroke(Color.outline, lineWidth: 1.6))
            .offset(y: 9)
            // face
            eye(left: true).offset(x: -3, y: 3)
            eye(left: false).offset(x: 19, y: 2)
            Ellipse().fill(Color.blush.opacity(0.55)).frame(width: 11, height: 6).offset(x: -11, y: 11)
            Ellipse().fill(Color.blush.opacity(0.55)).frame(width: 11, height: 6).offset(x: 27, y: 10)
            Ellipse().fill(Color(hex: 0xF27D8C)).frame(width: 4.5, height: 3.4).offset(x: 8, y: 8)
            mouth.stroke(Color.ink.opacity(0.75), style: StrokeStyle(lineWidth: 1.1, lineCap: .round))
                .frame(width: 8, height: 4).offset(x: 8, y: 12.5)
            // little front paws held at the chest
            paw.offset(x: 1, y: 27 + (moving ? step * 0.4 : 0))
            paw.offset(x: 15, y: 27 - (moving ? step * 0.4 : 0))
        }
        .frame(width: 100, height: 100)
        .offset(y: bob)
        .rotationEffect(.degrees(dragged ? sin(s.phase * 3) * 8 : 0), anchor: .top)
        .scaleEffect(x: s.facingRight ? 1 : -1, y: 1)
        .scaleEffect(size / 100)
        .frame(width: size, height: size)
    }

    private var foot: some View {
        Ellipse().fill(Color.paw).frame(width: 13, height: 7)
            .overlay(Ellipse().stroke(Color.outline.opacity(0.7), lineWidth: 1))
    }

    private var paw: some View {
        Ellipse().fill(Color.paw).frame(width: 8, height: 6)
            .overlay(Ellipse().stroke(Color.outline.opacity(0.7), lineWidth: 0.9))
    }

    private var ear: some View {
        ZStack {
            Circle().fill(Color.furLow).overlay(Circle().stroke(Color.outline, lineWidth: 1.5))
            Circle().fill(Color.blush.opacity(0.8)).frame(width: 9, height: 9)
        }
        .frame(width: 18, height: 18)
    }

    /// "ω" mouth
    private var mouth: Path {
        Path { p in
            p.move(to: CGPoint(x: 0, y: 0))
            p.addQuadCurve(to: CGPoint(x: 4, y: 1), control: CGPoint(x: 1.5, y: 4))
            p.addQuadCurve(to: CGPoint(x: 8, y: 0), control: CGPoint(x: 6.5, y: 4))
        }
    }

    @ViewBuilder private func eye(left: Bool) -> some View {
        let line = StrokeStyle(lineWidth: 1.8, lineCap: .round, lineJoin: .round)
        if s.mode == .sleeping || (s.blinking && s.mode != .dragged) {
            Path { p in   // closed: ‿
                p.move(to: CGPoint(x: 0, y: 1)); p.addQuadCurve(to: CGPoint(x: 8, y: 1), control: CGPoint(x: 4, y: 5))
            }.stroke(Color.ink, style: line).frame(width: 8, height: 6)
        } else if s.happy {
            Path { p in   // happy: ^
                p.move(to: CGPoint(x: 0, y: 5)); p.addQuadCurve(to: CGPoint(x: 8, y: 5), control: CGPoint(x: 4, y: -2))
            }.stroke(Color.ink, style: line).frame(width: 8, height: 6)
        } else if s.mode == .dragged {
            Path { p in   // > <
                let a: CGFloat = left ? 0 : 7, b: CGFloat = left ? 7 : 0
                p.move(to: CGPoint(x: a, y: 0)); p.addLine(to: CGPoint(x: b, y: 3.5)); p.addLine(to: CGPoint(x: a, y: 7))
            }.stroke(Color.ink, style: line).frame(width: 7, height: 7)
        } else {
            ZStack {
                Ellipse().fill(Color.ink).frame(width: 8, height: 9)
                Circle().fill(Color.white).frame(width: 3.2, height: 3.2).offset(x: 1.4, y: -1.8)
                Circle().fill(Color.white.opacity(0.8)).frame(width: 1.4, height: 1.4).offset(x: -1.6, y: 2)
            }
        }
    }
}

/// Desktop pet: hamster + speech bubble.
struct DesktopPetView: View {
    @ObservedObject var s: PetState
    static let hamsterSize: CGFloat = 62
    static let windowSize = CGSize(width: 104, height: 78)
    static let photoHeight: CGFloat = 50
    private var figureTop: CGFloat { s.photo ? Self.photoHeight : 40 }

    var body: some View {
        ZStack(alignment: .bottom) {
            Ellipse().fill(Color.black.opacity(s.mode == .dragged ? 0.06 : 0.14))
                .frame(width: s.mode == .dragged ? 20 : 32, height: 5).offset(y: -2)
            PetFigure(s: s, drawnSize: 44, photoHeight: Self.photoHeight).offset(y: s.mode == .dragged ? -4 : 0)
            if s.mode == .sleeping {
                Text("z z").font(.system(size: 10, weight: .bold, design: .rounded))
                    .foregroundColor(.ink.opacity(0.5))
                    .offset(x: 22, y: -figureTop + 4 + sin(s.phase * 0.6) * 2)
            }
            if let b = s.bubble ?? (s.mode == .thinking ? thinkingDots(s.phase) : nil) {
                BubbleText(text: b).offset(y: -figureTop - 2)
            }
        }
        .frame(width: Self.windowSize.width, height: Self.windowSize.height, alignment: .bottom)
    }
}

/// Dock tile: a little icon card with a hamster wheel the hamster sometimes runs in.
struct DockTileView: View {
    @ObservedObject var s: PetState
    var body: some View {
        GeometryReader { g in
            let k = min(g.size.width, g.size.height) / 100
            ZStack {
                RoundedRectangle(cornerRadius: 19, style: .continuous)
                    .fill(LinearGradient(colors: [Color(hex: 0xFFF6E6), Color(hex: 0xFFE2C2)],
                                         startPoint: .top, endPoint: .bottom))
                    .overlay(RoundedRectangle(cornerRadius: 19, style: .continuous)
                        .stroke(Color(hex: 0xE9B98A), lineWidth: 1))
                    .frame(width: 84, height: 84)
                    .shadow(color: .black.opacity(0.18), radius: 2, y: 1.5)
                Wheel(angle: s.mode == .running ? s.phase * 70 : 0).frame(width: 66, height: 66).offset(y: -4).opacity(0.75)
                PetFigure(s: s, drawnSize: 50, photoHeight: 56, speed: 1.8).offset(x: 0, y: s.photo ? 9 : 12)
                if s.mode == .sleeping {
                    Text("z z").font(.system(size: 11, weight: .heavy, design: .rounded))
                        .foregroundColor(.ink.opacity(0.55)).offset(x: 24, y: -26 + sin(s.phase * 0.6) * 2)
                }
                if s.mode == .thinking {
                    BubbleText(text: thinkingDots(s.phase), size: 12).offset(x: 20, y: -30)
                }
            }
            .frame(width: 100, height: 100)
            .scaleEffect(k)
            .frame(width: g.size.width, height: g.size.height)
        }
    }
}

private struct Wheel: View {
    var angle: Double
    var body: some View {
        ZStack {
            // stand
            Path { p in
                p.move(to: CGPoint(x: 32, y: 32)); p.addLine(to: CGPoint(x: 20, y: 64))
                p.move(to: CGPoint(x: 32, y: 32)); p.addLine(to: CGPoint(x: 44, y: 64))
            }.stroke(Color(hex: 0xA7B8C8), style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
            ZStack {
                Circle().stroke(Color(hex: 0x9FB4C7), lineWidth: 3)
                Circle().stroke(Color(hex: 0xC9D7E3), lineWidth: 1).padding(4)
                ForEach(0..<8) { i in
                    Rectangle().fill(Color(hex: 0xBFCFDC)).frame(width: 1.2, height: 58)
                        .rotationEffect(.degrees(Double(i) * 22.5))
                }
                Circle().fill(Color(hex: 0x9FB4C7)).frame(width: 5, height: 5)
            }
            .rotationEffect(.degrees(angle))
        }
    }
}

struct BubbleText: View {
    var text: String
    var size: CGFloat = 10
    var body: some View {
        Text(text).font(.system(size: size, weight: .semibold, design: .rounded))
            .foregroundColor(.ink).lineLimit(1).fixedSize()
            .padding(.horizontal, 6).padding(.vertical, 2.5)
            .background(Capsule().fill(Color.white).shadow(color: .black.opacity(0.15), radius: 1.5, y: 1))
    }
}

func thinkingDots(_ phase: Double) -> String { String(repeating: "•", count: Int(phase * 1.2) % 3 + 1) }

/// Picks the photo or the drawn hamster.
struct PetFigure: View {
    @ObservedObject var s: PetState
    var drawnSize: CGFloat
    var photoHeight: CGFloat
    var speed: Double = 1
    var body: some View {
        if s.photo, PhotoHamster.image != nil {
            PhotoHamster(s: s, height: photoHeight, speed: speed)
        } else {
            HamsterFigure(s: s, size: drawnSize, speed: speed)
        }
    }
}

/// The cut-out photo (Assets/ham.png), animated by hopping, leaning and breathing.
/// It's never mirrored, so the little magazine never reads backwards; it leans toward where it walks instead.
struct PhotoHamster: View {
    @ObservedObject var s: PetState
    var height: CGFloat
    var speed: Double = 1
    static let image: NSImage? = Bundle.main.url(forResource: "ham", withExtension: "png").flatMap { NSImage(contentsOf: $0) }

    var body: some View {
        let moving = [.walking, .chasing, .running].contains(s.mode)
        let t = s.phase * speed
        let hop = moving ? -abs(sin(t * 2)) * height * 0.08 : s.happy ? -abs(sin(s.phase * 3)) * height * 0.06 : 0
        let squash = moving ? 1 - (1 - abs(sin(t * 2))) * 0.05 : 1
        let breathe = s.mode == .sleeping ? sin(s.phase * 0.5) * 0.02 : sin(s.phase * 0.8) * 0.012
        let lean: Double
        switch s.mode {
        case .dragged: lean = sin(s.phase * 3) * 10
        case .sleeping: lean = 8
        case .thinking: lean = sin(s.phase * 0.8) * 3
        case .walking, .chasing, .running: lean = (s.facingRight ? 5 : -5) + sin(t * 4) * 2
        default: lean = 0
        }
        return Image(nsImage: Self.image!)
            .resizable().interpolation(.high).aspectRatio(contentMode: .fit)
            .frame(height: height)
            .scaleEffect(x: 1 + (1 - squash) * 0.6, y: squash * (1 + breathe), anchor: .bottom)
            .rotationEffect(.degrees(lean), anchor: s.mode == .dragged ? .top : .bottom)
            .saturation(s.mode == .sleeping ? 0.75 : 1)
            .offset(y: hop)
            .shadow(color: .black.opacity(0.12), radius: 1, y: 1)
    }
}
