import AppKit
import SwiftUI

@main
enum HamsterPalApp {
    static let delegate = AppDelegate()
    static func main() {
        if let dir = ProcessInfo.processInfo.environment["HAM_RENDER"] { MainActor.assumeIsolated { Renderer.renderAll(to: dir) }; return }
        let app = NSApplication.shared
        app.delegate = delegate
        app.run()
    }
}

final class KeyPanel: NSPanel {
    override var canBecomeKey: Bool { true }
}

/// The chat is an ordinary window: it goes behind other apps when you switch to them.
final class ChatWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

/// Transparent overlay on the pet that turns mouse input into click / drag / right-click.
final class DragView: NSView {
    var onClick: (() -> Void)?
    var onDragStart: (() -> Void)?
    var onDragEnd: (() -> Void)?
    var onRightClick: ((NSEvent) -> Void)?
    private var startMouse = NSPoint.zero, startOrigin = NSPoint.zero, moved = false

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func hitTest(_ point: NSPoint) -> NSView? {
        // only the hamster's body is grabbable, not the empty corners of the window
        let p = convert(point, from: superview)
        let r = NSRect(x: bounds.midX - 23, y: 0, width: 46, height: 52)
        return NSBezierPath(ovalIn: r).contains(p) ? self : nil
    }

    override func mouseDown(with e: NSEvent) {
        startMouse = NSEvent.mouseLocation
        startOrigin = window?.frame.origin ?? .zero
        moved = false
    }

    override func mouseDragged(with e: NSEvent) {
        let p = NSEvent.mouseLocation
        let dx = p.x - startMouse.x, dy = p.y - startMouse.y
        if !moved && hypot(dx, dy) > 3 { moved = true; onDragStart?() }
        if moved { window?.setFrameOrigin(NSPoint(x: startOrigin.x + dx, y: startOrigin.y + dy)) }
    }

    override func mouseUp(with e: NSEvent) { moved ? onDragEnd?() : onClick?() }
    override func rightMouseDown(with e: NSEvent) { onRightClick?(e) }
}

enum Home: String { case dock, desktop }

final class AppDelegate: NSObject, NSApplicationDelegate {
    let state = PetState()
    let chat = ChatModel()
    var cfg = ConfigStore.load()
    var home: Home = .dock
    var petPanel: KeyPanel!
    var chatPanel: ChatWindow!
    var activatedAt = Date.distantPast
    var dockHost: NSHostingView<DockTileView>?
    var timer: Timer?
    var frame = 0

    var target: CGPoint?
    var modeUntil = Date().addingTimeInterval(3)
    var wanderEnabled = true
    var bubbleUntil = Date.distantPast
    let bubble = BubbleController()
    var nextChatter = Date().addingTimeInterval(20)
    var prevMode: PetMode = .idle
    var chatAnchor = NSPoint.zero

    let petSize = DesktopPetView.windowSize
    let chatSize = NSSize(width: 340, height: 460)

    func applicationDidFinishLaunching(_ n: Notification) {
        makePetPanel()
        makeChatPanel()
        chat.config = { [unowned self] in self.cfg }
        chat.onBusy = { [unowned self] busy in
            self.state.mode = busy ? .thinking : .idle
            self.modeUntil = Date().addingTimeInterval(3)
        }
        chat.onReply = { [unowned self] in
            if !(self.chatPanel.isVisible && self.chatPanel.isKeyWindow) {
                NSApp.dockTile.badgeLabel = "1"
                self.speak(.replyReady, for: 4)
            }
        }
        chat.onClose = { [unowned self] in self.hideChat() }
        state.photo = cfg.skin != "drawn"
        state.outfit = cfg.outfit
        setHome(Home(rawValue: cfg.home) ?? .dock, save: false)
        timer = Timer(timeInterval: 1.0 / 30, repeats: true) { [unowned self] _ in self.tick() }
        RunLoop.main.add(timer!, forMode: .common)
        if let q = ProcessInfo.processInfo.environment["HAM_SELFTEST"] { selfTest(q) }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { self.speak(.greet, for: 3.5) }
    }

    // Clicking the Dock icon toggles the chat.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        // a Dock click that just brought Ham forward should reveal a buried chat, not close it
        rememberDockIcon()
        let chatOnTop = chatPanel.isVisible && Date().timeIntervalSince(activatedAt) > 0.6
        if chatOnTop { hideChat() } else { showChat(anchor: home == .dock ? NSEvent.mouseLocation : nil) }
        return false
    }

    func applicationWillBecomeActive(_ n: Notification) { activatedAt = Date() }

    func applicationDockMenu(_ sender: NSApplication) -> NSMenu? {
        rememberDockIcon()
        return menu(includeQuit: false)
    }

    /// Ham can't see where his Dock icon is, so he remembers where you last clicked it (for speech bubbles).
    private func rememberDockIcon() {
        let p = NSEvent.mouseLocation
        if cfg.dockIconX != Double(p.x) || cfg.dockIconY != Double(p.y) {
            cfg.dockIconX = Double(p.x); cfg.dockIconY = Double(p.y)
            ConfigStore.save(cfg)
        }
    }

    /// Dev-only: open the chat and ask `q` (never sends letters).
    private func selfTest(_ q: String) {
        let s = screenFrame
        showChat(anchor: NSPoint(x: s.midX, y: s.minY))
        if ProcessInfo.processInfo.environment["HAM_SELFTEST_COMPOSE"] != nil {
            chat.letter = q; chat.screen = .letter
        } else if ProcessInfo.processInfo.environment["HAM_SELFTEST_LETTER"] != nil {
            chat.letter = q; chat.preview()
        } else {
            chat.input = q; chat.send()
        }
    }

    // MARK: home: Dock icon or desktop pet

    func setHome(_ h: Home, save: Bool = true) {
        home = h
        if save { cfg.home = h.rawValue; ConfigStore.save(cfg) }
        hideChat()
        target = nil
        state.mode = chat.busy ? .thinking : .idle
        if h == .dock {
            petPanel.orderOut(nil)
            NSApp.setActivationPolicy(.regular)
            let host = NSHostingView(rootView: DockTileView(s: state))
            host.frame = NSRect(origin: .zero, size: NSApp.dockTile.size)
            dockHost = host
            NSApp.dockTile.contentView = host
            NSApp.dockTile.display()
        } else {
            NSApp.dockTile.contentView = nil
            dockHost = nil
            // stays a regular Dock app so right-clicking the Dock icon still shows Ham's menu
            NSApp.setActivationPolicy(.regular)
            let s = screenFrame
            let x = min(max(NSEvent.mouseLocation.x - petSize.width / 2, s.minX), s.maxX - petSize.width)
            petPanel.setFrameOrigin(NSPoint(x: x, y: s.minY))
            petPanel.orderFrontRegardless()
        }
        modeUntil = Date().addingTimeInterval(3)
    }

    // MARK: windows

    private func makePetPanel() {
        petPanel = KeyPanel(contentRect: NSRect(origin: .zero, size: petSize),
                            styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        petPanel.isOpaque = false
        petPanel.backgroundColor = .clear
        petPanel.hasShadow = false
        petPanel.level = .floating
        petPanel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]

        let container = NSView(frame: NSRect(origin: .zero, size: petSize))
        let host = NSHostingView(rootView: DesktopPetView(s: state))
        host.frame = container.bounds
        host.autoresizingMask = [.width, .height]
        let drag = DragView(frame: container.bounds)
        drag.autoresizingMask = [.width, .height]
        drag.onClick = { [unowned self] in
            let chatOnTop = self.chatPanel.isVisible && NSApp.isActive && self.chatPanel.isKeyWindow
            chatOnTop ? self.hideChat() : self.showChat()
        }
        drag.onDragStart = { [unowned self] in self.state.mode = .dragged; self.speak(.dragStart, for: 1.5) }
        drag.onDragEnd = { [unowned self] in
            self.clampPetOnScreen()
            self.state.mode = self.chat.busy ? .thinking : .idle
            self.speak(.drop, for: 2)
            self.modeUntil = Date().addingTimeInterval(2.5)
        }
        drag.onRightClick = { [unowned self] e in NSMenu.popUpContextMenu(self.menu(includeQuit: true), with: e, for: drag) }
        container.addSubview(host)
        container.addSubview(drag)
        petPanel.contentView = container
    }

    private func makeChatPanel() {
        chatPanel = ChatWindow(contentRect: NSRect(origin: .zero, size: chatSize),
                               styleMask: [.borderless], backing: .buffered, defer: false)
        chatPanel.isReleasedWhenClosed = false
        chatPanel.isMovableByWindowBackground = true
        chatPanel.isOpaque = false
        chatPanel.backgroundColor = .clear
        chatPanel.hasShadow = true
        chatPanel.level = .normal
        // fixed size: without this a growing text box could stretch the window to the whole screen
        let host = NSHostingView(rootView: ChatView(m: chat).environment(\.colorScheme, .light))
        host.sizingOptions = []
        host.frame = NSRect(origin: .zero, size: chatSize)
        chatPanel.contentView = host
        chatPanel.setContentSize(chatSize)
    }

    func showChat(anchor: NSPoint? = nil) {
        if let a = anchor { chatAnchor = a }
        target = nil
        if state.mode != .thinking { state.mode = .idle }
        bubble.hide()
        NSApp.dockTile.badgeLabel = nil
        if !chatPanel.isVisible { positionChat() }   // keep wherever you dragged it
        NSApp.activate(ignoringOtherApps: true)
        chatPanel.makeKeyAndOrderFront(nil)
        chat.focusTick += 1
    }

    func hideChat() {
        chatPanel.orderOut(nil)
        modeUntil = Date().addingTimeInterval(1.5)
    }

    private func positionChat() {
        let screen = screenFrame
        var x: CGFloat, y: CGFloat
        if home == .desktop {
            let pet = petPanel.frame
            x = pet.midX - chatSize.width / 2
            y = pet.maxY - 12
            if y + chatSize.height > screen.maxY { y = pet.minY - chatSize.height + 10 }
        } else {
            // sits just above the Dock icon that was clicked (clamping handles a side Dock too)
            x = chatAnchor.x - chatSize.width / 2
            y = chatAnchor.y - chatSize.height / 2
        }
        x = min(max(x, screen.minX + 8), screen.maxX - chatSize.width - 8)
        y = min(max(y, screen.minY + 6), screen.maxY - chatSize.height - 8)
        if chatPanel.frame.origin != NSPoint(x: x, y: y) { chatPanel.setFrameOrigin(NSPoint(x: x, y: y)) }
    }

    private func menu(includeQuit: Bool) -> NSMenu {
        let m = NSMenu()
        func add(_ title: String, _ action: @escaping () -> Void) {
            m.addItem(ClosureMenuItem(title: title, action: action))
        }
        add("Chat with Ham") { [unowned self] in
            self.showChat(anchor: self.home == .dock ? NSEvent.mouseLocation : nil)
        }
        if home == .dock {
            add("Let Ham out on the desktop") { [unowned self] in self.setHome(.desktop) }
        } else {
            add("Back into the Dock") { [unowned self] in self.setHome(.dock) }
            add(wanderEnabled ? "Stay put" : "Wander around") { [unowned self] in
                self.wanderEnabled.toggle(); self.target = nil; self.state.mode = .idle
            }
        }
        add(state.photo ? "Switch to drawn Ham" : "Switch to photo Ham") { [unowned self] in
            self.state.photo.toggle()
            self.cfg.skin = self.state.photo ? "photo" : "drawn"
            ConfigStore.save(self.cfg)
            NSApp.dockTile.display()
        }
        if state.photo {
            let outfit = NSMenuItem(title: "Outfit", action: nil, keyEquivalent: "")
            let looks = NSMenu()
            for (label, value) in [("None", "none"), ("Navy jacket", "jacket"), ("Whimsical", "whimsical")] {
                let item = ClosureMenuItem(title: label) { [unowned self] in
                    self.state.outfit = value
                    self.cfg.outfit = value
                    ConfigStore.save(self.cfg)
                    NSApp.dockTile.display()
                }
                item.state = state.outfit == value ? .on : .off
                looks.addItem(item)
            }
            outfit.submenu = looks
            m.addItem(outfit)
        }
        let talk = NSMenuItem(title: "Chattiness", action: nil, keyEquivalent: "")
        let sub = NSMenu()
        for (label, value) in [("Chatty", "chatty"), ("Normal", "normal"), ("Quiet (just says hi)", "quiet")] {
            let item = ClosureMenuItem(title: label) { [unowned self] in
                self.cfg.chattiness = value; ConfigStore.save(self.cfg)
                self.nextChatter = Date().addingTimeInterval(Chatter.gap(value) ?? 0)
                self.say(value == "quiet" ? "ok, I'll be quiet 🤐" : "yay, more talking!", for: 2)
            }
            item.state = cfg.chattiness == value ? .on : .off
            sub.addItem(item)
        }
        talk.submenu = sub
        m.addItem(talk)
        add("Nap time") { [unowned self] in
            self.target = nil; self.state.mode = .sleeping; self.modeUntil = Date().addingTimeInterval(40)
        }
        m.addItem(.separator())
        add("Open settings file") { [unowned self] in
            ConfigStore.save(self.cfg); NSWorkspace.shared.open(Paths.config)
        }
        add("Reload settings") { [unowned self] in self.cfg = ConfigStore.load(); self.say("got it!", for: 1.5) }
        add("Show letters folder") { NSWorkspace.shared.activateFileViewerSelecting([Paths.dir]) }
        if includeQuit {
            m.addItem(.separator())
            add("Quit Ham") { NSApp.terminate(nil) }
        }
        return m
    }

    // MARK: behaviour

    func speak(_ moment: Chatter.Moment, for seconds: Double = 3.5) {
        // quiet (the default) means Ham only says hi when he starts
        if moment == .greet { say("hi \(cfg.senderName)! 🐭", for: seconds); return }
        guard cfg.chattiness != "quiet" else { return }
        say(Chatter.line(moment, sender: cfg.senderName), for: seconds)
    }

    func say(_ text: String, for seconds: Double) {
        bubbleUntil = Date().addingTimeInterval(seconds)
        if let a = bubbleAnchor() { bubble.show(text, at: a, for: seconds) }
    }

    /// Where the bubble's tail points: above the desktop pet, or above the remembered Dock icon.
    private func bubbleAnchor() -> NSPoint? {
        if home == .desktop {
            let f = petPanel.frame
            return NSPoint(x: f.midX, y: f.minY + (state.photo ? DesktopPetView.photoHeight : 44) + 2)
        }
        guard let x = cfg.dockIconX, let y = cfg.dockIconY else { return nil }
        let p = NSPoint(x: x, y: y)
        let vf = (NSScreen.screens.first { $0.frame.contains(p) } ?? NSScreen.main ?? NSScreen.screens[0]).visibleFrame
        if p.y < vf.minY { return NSPoint(x: p.x, y: vf.minY + 2) }                 // Dock at the bottom
        return NSPoint(x: min(max(p.x, vf.minX + 100), vf.maxX - 100), y: p.y + 30)   // side Dock
    }

    private var screenFrame: NSRect {
        ((home == .desktop ? petPanel.screen : nil) ?? NSScreen.main ?? NSScreen.screens[0]).visibleFrame
    }

    private func clampPetOnScreen() {
        let s = screenFrame
        var o = petPanel.frame.origin
        o.x = min(max(o.x, s.minX - 10), s.maxX - petSize.width + 10)
        o.y = min(max(o.y, s.minY - 4), s.maxY - petSize.height)
        petPanel.setFrameOrigin(o)
    }

    private func tick() {
        frame += 1
        state.phase += 1.0 / 30 * 6
        if !state.blinking && Double.random(in: 0..<1) < 0.006 {
            state.blinking = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.14) { self.state.blinking = false }
        }
        if state.happy && Date() > bubbleUntil { state.happy = false }
        if home == .desktop && bubble.isShowing, let a = bubbleAnchor() { bubble.move(to: a) }

        let busy = (chatPanel.isKeyWindow && NSApp.isActive) || chat.busy
        switch state.mode {
        case .walking:
            if busy { state.mode = .idle; target = nil } else { step(speed: 1.2) }
        case .chasing:
            let m = NSEvent.mouseLocation
            target = CGPoint(x: m.x - petSize.width / 2, y: max(m.y - 30, screenFrame.minY))
            if busy || Date() > modeUntil { state.mode = .idle; modeUntil = Date().addingTimeInterval(2) }
            else if step(speed: 2.2) {
                state.mode = .idle; state.happy = true; speak(.caught, for: 2)
                modeUntil = Date().addingTimeInterval(3)
            }
        case .running:
            if busy || Date() > modeUntil { state.mode = .idle; modeUntil = Date().addingTimeInterval(.random(in: 2...5)) }
        case .idle, .sleeping:
            if !busy && wanderEnabled && Date() > modeUntil { home == .dock ? pickNextInDock() : pickNextOnDesktop() }
        case .dragged, .thinking:
            break
        }

        // reactions to mode changes, and unprompted chatter
        if prevMode == .sleeping && state.mode != .sleeping && state.mode != .dragged && Double.random(in: 0..<1) < 0.5 {
            speak(.wake, for: 2.5)
        } else if prevMode != .running && state.mode == .running && Double.random(in: 0..<1) < 0.4 {
            speak(.wheel, for: 2.5)
        }
        prevMode = state.mode
        if Date() > nextChatter {
            if let gap = Chatter.gap(cfg.chattiness) {
                if !busy && state.mode != .dragged && !bubble.isShowing {
                    if state.mode != .sleeping { speak(.idle) }
                    else if Double.random(in: 0..<1) < 0.35 { speak(.sleepTalk, for: 2.5) }
                }
                nextChatter = Date().addingTimeInterval(gap)
            } else {
                nextChatter = Date().addingTimeInterval(60)
            }
        }

        if home == .dock {
            // the Dock tile only redraws when asked; animate smoothly only while something moves
            let lively = state.mode == .running || state.mode == .thinking
            if frame % (lively ? 2 : 5) == 0 { NSApp.dockTile.display() }
        }
    }

    /// Moves toward `target`; returns true on arrival.
    @discardableResult
    private func step(speed: CGFloat) -> Bool {
        guard let t = target else { state.mode = .idle; return true }
        let o = petPanel.frame.origin
        let dx = t.x - o.x, dy = t.y - o.y
        let d = hypot(dx, dy)
        if abs(dx) > 1 { state.facingRight = dx > 0 }
        if d <= speed {
            petPanel.setFrameOrigin(t)
            target = nil
            if state.mode == .walking { state.mode = .idle; modeUntil = Date().addingTimeInterval(.random(in: 2...6)) }
            return true
        }
        petPanel.setFrameOrigin(NSPoint(x: o.x + dx / d * speed, y: o.y + dy / d * speed))
        return false
    }

    private func pickNextInDock() {
        state.facingRight = true
        let r = Double.random(in: 0..<1)
        if r < 0.35 {
            state.mode = .running
            modeUntil = Date().addingTimeInterval(.random(in: 4...9))
        } else if r < 0.75 {
            state.mode = .idle
            modeUntil = Date().addingTimeInterval(.random(in: 3...8))
        } else {
            state.mode = .sleeping
            modeUntil = Date().addingTimeInterval(.random(in: 15...30))
        }
    }

    private func pickNextOnDesktop() {
        let s = screenFrame
        let r = Double.random(in: 0..<1)
        if r < 0.5 {
            // stays in a low strip along the bottom of the screen so it doesn't sit on what you're reading
            target = CGPoint(x: .random(in: s.minX...(s.maxX - petSize.width)), y: s.minY + .random(in: 0...16))
            state.mode = .walking
        } else if r < 0.58 {
            state.mode = .chasing
            modeUntil = Date().addingTimeInterval(5)
        } else if r < 0.85 {
            state.mode = .idle
            modeUntil = Date().addingTimeInterval(.random(in: 3...7))
        } else {
            state.mode = .sleeping
            modeUntil = Date().addingTimeInterval(.random(in: 12...25))
        }
    }
}

final class ClosureMenuItem: NSMenuItem {
    private let handler: () -> Void
    init(title: String, action: @escaping () -> Void) {
        handler = action
        super.init(title: title, action: #selector(fire), keyEquivalent: "")
        target = self
    }
    required init(coder: NSCoder) { fatalError() }
    @objc private func fire() { handler() }
}

/// `HAM_RENDER=<dir>`: writes the app icon set and a preview sheet, then exits (used by build.sh).
@MainActor
enum Renderer {
    static func renderAll(to dir: String) {
        let url = URL(fileURLWithPath: dir)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        let iconset = url.appendingPathComponent("AppIcon.iconset")
        try? FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)
        let still = PetState()
        still.photo = PhotoHamster.image != nil
        for (px, name) in [(16, "16x16"), (32, "16x16@2x"), (32, "32x32"), (64, "32x32@2x"), (128, "128x128"),
                           (256, "128x128@2x"), (256, "256x256"), (512, "256x256@2x"), (512, "512x512"),
                           (1024, "512x512@2x")] {
            write(DockTileView(s: still).frame(width: CGFloat(px), height: CGFloat(px)),
                  to: iconset.appendingPathComponent("icon_\(name).png"))
        }
        // preview sheet of every state, for eyeballing changes
        func st(_ m: PetMode, _ f: (PetState) -> Void = { _ in }) -> PetState {
            let s = PetState(); s.mode = m; s.phase = 0.4; f(s); return s
        }
        func drawn(_ p: PetState) -> PetState {
            let s = PetState(); s.mode = p.mode; s.phase = p.phase; s.facingRight = p.facingRight
            s.happy = p.happy; s.bubble = p.bubble; s.photo = false; return s
        }
        let states: [(String, PetState)] = [("idle", st(.idle)), ("walk", st(.walking)),
                                            ("left", st(.walking) { $0.facingRight = false }),
                                            ("happy", st(.idle) { $0.happy = true; $0.bubble = "♡" }),
                                            ("dragged", st(.dragged)), ("sleep", st(.sleeping)),
                                            ("thinking", st(.thinking))]
        let sheet = VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                ForEach(0..<states.count, id: \.self) { i in
                    VStack { DesktopPetView(s: states[i].1); Text(states[i].0).font(.caption) }
                }
            }
            HStack(spacing: 14) {
                ForEach([st(.idle), st(.running), st(.sleeping), st(.thinking)].indices, id: \.self) { i in
                    DockTileView(s: [st(.idle), st(.running) { $0.phase = 0.6 }, st(.sleeping), st(.thinking)][i])
                        .frame(width: 128, height: 128)
                }
                DockTileView(s: st(.idle)).frame(width: 48, height: 48)
            }
            HStack(spacing: 6) {
                ForEach(0..<states.count, id: \.self) { i in
                    VStack { DesktopPetView(s: drawn(states[i].1)); Text(states[i].0).font(.caption) }
                }
            }
            HStack(spacing: 18) {
                EmojiPair(size: 60); EmojiAvatar.rat(40); EmojiAvatar.ham(40); EmojiPair(size: 28); PawTrail()
            }
        }
        .padding(16).background(Color(hex: 0xDDE3EA))
        write(sheet, to: url.appendingPathComponent("preview.png"))
        // handwritten-letter tests with long text
        let en = """
        A lot has happened since I last wrote you. The weather finally turned and I wore the scarf you left here, the grey one, which still smells a little like your shampoo. Don't laugh.

        Work has been a lot. I spent most of Tuesday arguing with a spreadsheet and lost, but I won on Wednesday, so I think we're even. I found a tiny noodle place near the library that looks like it was built for hamsters; the stools are so low you'd love it.

        I miss you more than I say. Write back soon, or at least send a picture of whatever you're eating.
        """
        let zh = """
        好久没给你写信了。这周终于降温了，我把你落下的那条灰色围巾翻出来戴上，上面还有一点点你的味道，不许笑我。

        最近忙得团团转，周二跟一张表格吵了一整天，输了；周三又赢回来了，算打平。图书馆旁边新开了一家小面馆，凳子矮矮的，像是给仓鼠准备的，你肯定喜欢。

        比起说出口的，我其实更想你一点。记得回信，或者至少拍一张你在吃什么给我看。
        """
        let d = Date()
        for (name, note, paper) in [("hand-en-legal", en, HandLetter.Paper.legal), ("hand-zh-grid", zh, .grid),
                                    ("hand-zh-cream", zh + "\n\n" + zh, .cream)] {
            if let cg = HandLetter.render(note: note, sender: "Bonnie", kaomoji: "ฅ(•ㅅ•❀)ฅ", date: d, paper: paper) {
                try? NSBitmapImageRep(cgImage: cg).representation(using: .png, properties: [:])?
                    .write(to: url.appendingPathComponent("\(name).png"))
            }
        }
    }

    private static func write<V: View>(_ view: V, to url: URL) {
        let r = ImageRenderer(content: view)
        r.scale = 1
        if !url.path.contains("iconset") { r.scale = 2 }
        guard let cg = r.cgImage else { return }
        let rep = NSBitmapImageRep(cgImage: cg)
        try? rep.representation(using: .png, properties: [:])?.write(to: url)
    }
}
