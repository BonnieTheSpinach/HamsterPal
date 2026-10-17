import SwiftUI
import AppKit

final class ChatModel: ObservableObject {
    enum Screen: Equatable { case chat, letter, confirm, sending, sent, failed(String) }

    @Published var messages = [ChatMessage(role: .ham, text: "hi rat 🐭")]
    @Published var input = ""
    @Published var busy = false { didSet { onBusy?(busy) } }
    @Published var screen: Screen = .chat
    @Published var letter = ""
    @Published var draft: Letter?             // set on Preview; exactly what gets sent
    @Published var draftPicture: NSImage?
    enum SendAs { case text, letter }
    @Published var sendAs: SendAs = .text           // exactly one of the two is sent, never both
    @Published var secretFound = false
    @Published var focusTick = 0

    var config: () -> HamConfig = { HamConfig() }
    var onBusy: ((Bool) -> Void)?
    var onReply: (() -> Void)?
    var onClose: (() -> Void)?

    func send() {
        let text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !busy else { return }
        input = ""
        messages.append(ChatMessage(role: .user, text: text))
        busy = true
        ClaudeService.ask(messages, cfg: config()) { [weak self] result in
            guard let self else { return }
            switch result {
            case .success(let reply): self.messages.append(ChatMessage(role: .ham, text: reply))
            case .failure(let e): self.messages.append(ChatMessage(role: .ham, text: "*trips over a seed* something broke: \(e.localizedDescription)"))
            }
            self.busy = false
            self.secretFound = true
            self.onReply?()
        }
    }

    func preview() {
        setDraft(Letter.random(letter, cfg: config()))
        screen = .confirm
    }

    func reroll() { if let d = draft { setDraft(d.rerolled()) } }
    func nextPaper() { if let d = draft { setDraft(d.nextPaper()) } }

    private func setDraft(_ d: Letter) {
        draft = d
        draftPicture = d.picture().map { NSImage(cgImage: $0, size: NSSize(width: $0.width / 2, height: $0.height / 2)) }
    }

    func sendLetter() {
        guard let d = draft else { return }
        screen = .sending
        GaryService.send(d, as: sendAs, cfg: config()) { [weak self] result in
            guard let self else { return }
            switch result {
            case .success: self.letter = ""; self.screen = .sent
            case .failure(let e): self.screen = .failed(e.localizedDescription)
            }
        }
    }
}

struct ChatView: View {
    @ObservedObject var m: ChatModel
    @FocusState private var focused: Bool

    var body: some View {
        VStack(spacing: 0) {
            header
            switch m.screen {
            case .chat: chat
            case .letter: letterEditor
            case .confirm, .sending: confirm
            case .sent: result(title: "Delivered to Gary!", detail: "Tucked into Ham's letters log too.", ok: true)
            case .failed(let why): result(title: "Couldn't deliver it", detail: "\(why)\n\nIt's saved in the letters log, so nothing is lost.", ok: false)
            }
        }
        .foregroundColor(Theme.ink)
        .background(Theme.paper)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).stroke(Theme.hairline))
        .padding(4)
        .onChange(of: m.focusTick) { _ in focused = true }
        .onExitCommand { m.onClose?() }
    }

    private var inPostOffice: Bool { m.screen != .chat }

    private var header: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                EmojiPair(size: 28)
                VStack(alignment: .leading, spacing: 1) {
                    Text(inPostOffice ? "Bonnie → Gary" : "Ham")
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                    Text(inPostOffice ? "a letter for the real hamster" : "a tiny Claude, from one rodent to another")
                        .font(.system(size: 10, design: .rounded)).foregroundColor(Theme.inkSoft)
                }
                Spacer()
                Button { m.onClose?() } label: {
                    Image(systemName: "xmark").font(.system(size: 9.5, weight: .bold)).foregroundColor(Theme.inkSoft)
                        .frame(width: 22, height: 22).background(Circle().fill(Color.white.opacity(0.7)))
                }.buttonStyle(.plain)
            }
            .padding(.horizontal, 14).padding(.top, 11).padding(.bottom, 8)
            PawTrail().padding(.bottom, 5)
        }
        .background(Theme.headerWash)
    }

    // MARK: chat

    private var chat: some View {
        VStack(spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 9) {
                        ForEach(m.messages) { row($0).id($0.id) }
                        if m.busy {
                            HStack(alignment: .bottom, spacing: 6) {
                                EmojiAvatar.ham(22)
                                Text("stuffing cheeks with thoughts…").font(.system(size: 11, design: .rounded))
                                    .italic().foregroundColor(Theme.inkSoft)
                                    .padding(.horizontal, 10).padding(.vertical, 6)
                                    .background(Capsule().fill(Theme.hamCream))
                            }
                            .id("typing")
                        }
                    }.padding(12)
                }
                .onChange(of: m.messages.count) { _ in
                    withAnimation { proxy.scrollTo(m.messages.last?.id, anchor: .bottom) }
                }
                .onChange(of: m.busy) { busy in if busy { withAnimation { proxy.scrollTo("typing") } } }
            }
            HStack(spacing: 8) {
                TextField("ask Ham…", text: $m.input)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13, design: .rounded))
                    .padding(.horizontal, 12).padding(.vertical, 8)
                    .background(Capsule().fill(Color.white))
                    .overlay(Capsule().stroke(focused ? Theme.pink.opacity(0.7) : Theme.hairline, lineWidth: 1))
                    .focused($focused)
                    .onSubmit { m.send() }
                Button { m.send() } label: {
                    Image(systemName: "arrow.up").font(.system(size: 12, weight: .bold)).foregroundColor(.white)
                        .frame(width: 30, height: 30)
                        .background(Circle().fill(LinearGradient(colors: [Theme.pink, Theme.pinkDeep],
                                                                  startPoint: .top, endPoint: .bottom)))
                        .opacity(m.busy ? 0.4 : 1)
                }.buttonStyle(.plain).disabled(m.busy)
            }
            .padding(.horizontal, 12).padding(.top, 6)
            // the hidden door: only appears after Ham has answered once, and it's quiet on purpose
            HStack {
                if m.secretFound {
                    Button { m.screen = .letter } label: {
                        Text("btw… do u wanna talk to the real hamster?")
                            .font(.system(size: 9.5, design: .rounded)).foregroundColor(Theme.ink.opacity(0.32))
                    }.buttonStyle(.plain)
                }
                Spacer()
            }
            .frame(height: 16).padding(.horizontal, 16).padding(.vertical, 5)
        }
    }

    private func row(_ msg: ChatMessage) -> some View {
        let mine = msg.role == .user
        return HStack(alignment: .bottom, spacing: 6) {
            if mine { Spacer(minLength: 36) } else { EmojiAvatar.ham(22) }
            Text(msg.text)
                .font(.system(size: 13, design: .rounded))
                .lineSpacing(1.5)
                .textSelection(.enabled)
                .foregroundColor(mine ? .white : Theme.ink)
                .padding(.horizontal, 11).padding(.vertical, 8)
                .background(
                    Group {
                        if mine {
                            BubbleShape(mine: true).fill(Theme.ratBubble)
                        } else {
                            BubbleShape(mine: false).fill(Theme.hamCream)
                                .overlay(BubbleShape(mine: false).stroke(Theme.caramel.opacity(0.35), lineWidth: 1))
                        }
                    }
                )
            if mine { EmojiAvatar.rat(22) } else { Spacer(minLength: 36) }
        }
    }

    // MARK: letters to Gary

    private var letterEditor: some View {
        let cfg = m.config()
        return VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 8) {
                EmojiAvatar.ham(24)
                Text("The real hamster is Gary. Write him something and I'll carry it over in my cheeks (via iMessage). Nothing goes out until you check it and press Send.")
                    .font(.system(size: 12, design: .rounded)).fixedSize(horizontal: false, vertical: true)
            }
            // grows with what you write (3 to 12 lines), then scrolls
            TextField("tell Gary…", text: $m.letter, axis: .vertical)
                .lineLimit(3...12)
                .textFieldStyle(.plain)
                .font(.system(size: 13, design: .rounded))
                .padding(.horizontal, 12).padding(.vertical, 10)
                .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color.white))
                .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(Theme.hairline))
            VStack(alignment: .leading, spacing: 4) {
                Picker("", selection: $m.sendAs) {
                    Text("💬 Text").tag(ChatModel.SendAs.text)
                    Text("✍️ Handwritten letter").tag(ChatModel.SendAs.letter)
                }
                .pickerStyle(.segmented).labelsHidden()
                Text(m.sendAs == .text ? "sent as a normal iMessage text" : "sent as a picture of a handwritten letter")
                    .font(.system(size: 10, design: .rounded)).foregroundColor(Theme.ink.opacity(0.4))
            }
            Spacer(minLength: 0)
            if cfg.garyHandle.isEmpty {
                Text("Gary's iMessage number isn't set yet. Right-click Ham → Open settings file, fill in \"garyHandle\", then Reload settings.")
                    .font(.system(size: 10.5, design: .rounded)).foregroundColor(Theme.pinkDeep)
                    .fixedSize(horizontal: false, vertical: true)
            }
            HStack {
                Button("← back to chat") { m.screen = .chat }.buttonStyle(.plain)
                    .font(.system(size: 12, design: .rounded)).foregroundColor(Theme.inkSoft)
                Spacer()
                Text("\(GaryService.letterCount()) sent before").font(.system(size: 10, design: .rounded))
                    .foregroundColor(Theme.ink.opacity(0.35))
                pill("Preview →", enabled: !m.letter.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) {
                    m.preview()
                }
            }
        }
        .padding(14)
    }

    private var confirm: some View {
        let cfg = m.config()
        return VStack(alignment: .leading, spacing: 10) {
            Picker("", selection: $m.sendAs) {
                Text("💬 Text").tag(ChatModel.SendAs.text)
                Text("✍️ Handwritten letter").tag(ChatModel.SendAs.letter)
            }
            .pickerStyle(.segmented).labelsHidden().disabled(m.screen == .sending)
            HStack(spacing: 6) {
                Text("Gary will get exactly this:").font(.system(size: 12, weight: .semibold, design: .rounded))
                Spacer()
                if m.sendAs == .letter { chip("📄 paper") { m.nextPaper() } }
                chip("🎲 face") { m.reroll() }
            }
            ScrollView {
                Group {
                    if m.sendAs == .text {
                        Text(m.draft?.textLine ?? "")
                            .font(.system(size: 12, design: .rounded)).foregroundColor(.white)
                            .padding(.horizontal, 11).padding(.vertical, 7)
                            .background(BubbleShape(mine: true).fill(Color(hex: 0x3A8DFF)))
                            .frame(maxWidth: .infinity, alignment: .trailing)
                            .padding(.leading, 30)
                    } else if let pic = m.draftPicture {
                        Image(nsImage: pic).resizable().interpolation(.high).aspectRatio(contentMode: .fit)
                            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    }
                }
                .padding(8)
            }
            .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color.white))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(Theme.hairline))
            HStack(spacing: 6) {
                EmojiAvatar.rat(16)
                Image(systemName: "arrow.right").font(.system(size: 8, weight: .bold)).foregroundColor(Theme.inkSoft)
                EmojiAvatar.ham(16)
                Text("\(cfg.garyHandle.isEmpty ? "(not set)" : cfg.garyHandle) · iMessage · saved to letters log")
                    .font(.system(size: 10.5, design: .rounded)).foregroundColor(Theme.inkSoft)
            }
            HStack {
                Button("← edit") { m.screen = .letter }.buttonStyle(.plain)
                    .font(.system(size: 12, design: .rounded)).foregroundColor(Theme.inkSoft)
                    .disabled(m.screen == .sending)
                Spacer()
                pill(m.screen == .sending ? "sending…" : "Send to Gary",
                     enabled: m.screen != .sending && !cfg.garyHandle.isEmpty) { m.sendLetter() }
            }
        }
        .padding(14)
    }

    private func result(title: String, detail: String, ok: Bool) -> some View {
        VStack(spacing: 10) {
            Spacer()
            EmojiPair(size: 46).saturation(ok ? 1 : 0.4)
            Text(title).font(.system(size: 15, weight: .bold, design: .rounded))
            Text(detail).font(.system(size: 11.5, design: .rounded)).foregroundColor(Theme.inkSoft)
                .multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
            Spacer()
            HStack {
                Button("back to chat") { m.screen = .chat }.buttonStyle(.plain)
                    .font(.system(size: 12, design: .rounded)).foregroundColor(Theme.inkSoft)
                Spacer()
                pill("write another", enabled: true) { m.screen = .letter }
            }
        }
        .padding(14)
    }

    private func chip(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title).font(.system(size: 10.5, design: .rounded)).foregroundColor(Theme.inkSoft)
                .padding(.horizontal, 8).padding(.vertical, 3).background(Capsule().fill(Theme.ratMist))
        }
        .buttonStyle(.plain).disabled(m.screen == .sending)
    }

    private func pill(_ title: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title).font(.system(size: 12, weight: .semibold, design: .rounded)).foregroundColor(.white)
                .padding(.horizontal, 14).padding(.vertical, 7)
                .background(Capsule().fill(LinearGradient(colors: [Theme.pink, Theme.pinkDeep],
                                                          startPoint: .top, endPoint: .bottom)))
                .opacity(enabled ? 1 : 0.4)
        }
        .buttonStyle(.plain).disabled(!enabled)
    }
}

/// Rounded bubble with the corner nearest the speaker's avatar tucked in.
struct BubbleShape: Shape {
    var mine: Bool
    func path(in r: CGRect) -> Path {
        let big: CGFloat = 14, small: CGFloat = 5
        return Path(roundedRect: r, cornerRadii: RectangleCornerRadii(
            topLeading: big, bottomLeading: mine ? big : small,
            bottomTrailing: mine ? small : big, topTrailing: big), style: .continuous)
    }
}
