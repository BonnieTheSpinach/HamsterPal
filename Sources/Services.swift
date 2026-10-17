import Foundation

// MARK: - Config (~/.hamsterpal/config.json)

struct HamConfig: Codable {
    var garyHandle = ""        // Gary's iMessage phone number (+1...) or Apple ID email
    var senderName = "Bonnie"
    var model = "sonnet"       // any `claude --model` alias: haiku / sonnet / opus
    var claudePath = ""        // auto-detected when empty
    var skin = "photo"         // "photo" or "drawn"
    var jacket = false         // photo Ham wears the navy jacket
    var chattiness = "quiet"   // "quiet" (just says hi), "normal" or "chatty"
    var dockIconX: Double?     // remembered from clicks on the Dock icon, for speech bubbles
    var dockIconY: Double?
    var home = "dock"          // "dock" (lives in the Dock icon) or "desktop" (walks along the bottom)

    init() {}
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        garyHandle = try c.decodeIfPresent(String.self, forKey: .garyHandle) ?? ""
        senderName = try c.decodeIfPresent(String.self, forKey: .senderName) ?? "Bonnie"
        model = try c.decodeIfPresent(String.self, forKey: .model) ?? "sonnet"
        claudePath = try c.decodeIfPresent(String.self, forKey: .claudePath) ?? ""
        skin = try c.decodeIfPresent(String.self, forKey: .skin) ?? "photo"
        jacket = try c.decodeIfPresent(Bool.self, forKey: .jacket) ?? false
        chattiness = try c.decodeIfPresent(String.self, forKey: .chattiness) ?? "quiet"
        dockIconX = try c.decodeIfPresent(Double.self, forKey: .dockIconX)
        dockIconY = try c.decodeIfPresent(Double.self, forKey: .dockIconY)
        home = try c.decodeIfPresent(String.self, forKey: .home) ?? "dock"
    }
}

enum Paths {
    static let dir: URL = {
        let u = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".hamsterpal")
        try? FileManager.default.createDirectory(at: u, withIntermediateDirectories: true)
        return u
    }()
    static let config = dir.appendingPathComponent("config.json")
    static let letters = dir.appendingPathComponent("letters_to_gary.jsonl")
}

enum ConfigStore {
    static func load() -> HamConfig {
        if let d = try? Data(contentsOf: Paths.config),
           let c = try? JSONDecoder().decode(HamConfig.self, from: d) { return c }
        let c = HamConfig()
        save(c)
        return c
    }

    static func save(_ c: HamConfig) {
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        try? enc.encode(c).write(to: Paths.config)
    }
}

struct ChatMessage: Identifiable, Equatable {
    enum Role { case user, ham }
    let id = UUID()
    let role: Role
    let text: String
}

// MARK: - Claude, via the local `claude` CLI (uses Bonnie's existing Claude Code login)

enum ClaudeService {
    struct Failure: LocalizedError { let errorDescription: String? }

    static func findClaude(_ cfg: HamConfig) -> String? {
        let fm = FileManager.default
        if !cfg.claudePath.isEmpty, fm.isExecutableFile(atPath: cfg.claudePath) { return cfg.claudePath }
        let home = fm.homeDirectoryForCurrentUser.path
        var candidates = ["\(home)/.local/bin/claude", "\(home)/.claude/local/claude",
                          "/opt/homebrew/bin/claude", "/usr/local/bin/claude"]
        let nvm = "\(home)/.nvm/versions/node"
        if let versions = try? fm.contentsOfDirectory(atPath: nvm) {
            candidates += versions.sorted().reversed().map { "\(nvm)/\($0)/bin/claude" }
        }
        return candidates.first { fm.isExecutableFile(atPath: $0) }
    }

    static func persona(_ cfg: HamConfig) -> String {
        let today = DateFormatter.localizedString(from: Date(), dateStyle: .full, timeStyle: .none)
        return """
        You are Ham, a little hamster living on \(cfg.senderName)'s MacBook, powered by Claude. \(cfg.senderName) texts you \
        like a close friend: sometimes just to say hi, sometimes with a real question (facts, explanations, writing, \
        translation, advice, code).
        Text back the way a close friend would:
        - Match the length and energy of the message. A greeting gets a greeting: "hi ham" → "hi rat 🐭". \
        A one-liner gets a one-liner. Only go longer when the question genuinely needs it, and even then keep it tight.
        - No performing. Don't narrate hamster things you're "doing" (stuffing cheeks, squeaking, running on a wheel), \
        don't list what you can help with, don't tack on "what's on your mind?" style questions.
        - Casual, warm and a bit dry is good. An occasional 🐹 or 🐭 is fine; nothing forced.
        - Real questions get real, accurate answers. Plain text, no markdown headers or tables (it's a small chat bubble).
        - Reply in the language \(cfg.senderName) uses (English or 中文), mirroring their casual tone.
        Inside joke: \(cfg.senderName) is the little grey rat and Gary is the real hamster; you're Gary's tiny stand-in. \
        Call \(cfg.senderName) "rat" when it fits. Use 🐭 for \(cfg.senderName), never 🐀.
        You cannot browse the web or see files; if something needs live information, say so briefly.
        Today is \(today).
        """
    }

    static func ask(_ history: [ChatMessage], cfg: HamConfig, completion: @escaping (Result<String, Error>) -> Void) {
        DispatchQueue.global(qos: .userInitiated).async {
            let result = Result { try run(history, cfg: cfg) }
            DispatchQueue.main.async { completion(result) }
        }
    }

    private static func run(_ history: [ChatMessage], cfg: HamConfig) throws -> String {
        guard let claude = findClaude(cfg) else {
            throw Failure(errorDescription: "I can't find the `claude` CLI. Set \"claudePath\" in ~/.hamsterpal/config.json.")
        }
        let name = cfg.senderName
        let turns = history.suffix(20).map { "\($0.role == .user ? name : "Ham"): \($0.text)" }
        let prompt = "Conversation so far:\n\n" + turns.joined(separator: "\n\n") + "\n\nWrite Ham's next reply only."

        let p = Process()
        p.executableURL = URL(fileURLWithPath: claude)
        p.arguments = ["-p", "--model", cfg.model, "--tools", "", "--strict-mcp-config",
                       "--setting-sources", "", "--no-session-persistence",
                       "--output-format", "text", "--system-prompt", persona(cfg)]
        var env = ProcessInfo.processInfo.environment
        let binDir = (claude as NSString).deletingLastPathComponent
        env["PATH"] = "\(binDir):/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:" + (env["PATH"] ?? "")
        p.environment = env
        p.currentDirectoryURL = Paths.dir
        let inPipe = Pipe(), outPipe = Pipe(), errPipe = Pipe()
        p.standardInput = inPipe
        p.standardOutput = outPipe
        p.standardError = errPipe
        try p.run()
        inPipe.fileHandleForWriting.write(prompt.data(using: .utf8)!)
        try? inPipe.fileHandleForWriting.close()

        let timeout = DispatchWorkItem { if p.isRunning { p.terminate() } }
        DispatchQueue.global().asyncAfter(deadline: .now() + 120, execute: timeout)
        let out = outPipe.fileHandleForReading.readDataToEndOfFile()
        let err = errPipe.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        timeout.cancel()

        let text = String(decoding: out, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        if p.terminationStatus != 0 || text.isEmpty {
            let detail = (text.isEmpty ? String(decoding: err, as: UTF8.self) : text)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            throw Failure(errorDescription: detail.isEmpty ? "claude exited with status \(p.terminationStatus)" : detail)
        }
        return text
    }
}

// MARK: - Letters to Gary (iMessage via Messages.app), every attempt logged

enum GaryService {
    static func letterCount() -> Int {
        guard let s = try? String(contentsOf: Paths.letters, encoding: .utf8) else { return 0 }
        return s.split(separator: "\n").count
    }

    /// Sends either the text line or the handwritten-letter picture, never both.
    static func send(_ letter: Letter, as kind: ChatModel.SendAs, cfg: HamConfig, completion: @escaping (Result<Void, Error>) -> Void) {
        let image = kind == .letter ? letter.renderPNG() : nil
        DispatchQueue.global(qos: .userInitiated).async {
            let result = Result {
                if kind == .letter && image == nil { throw ClaudeService.Failure(errorDescription: "couldn't draw the letter") }
                try deliver(kind == .text ? letter.textLine : "", image: image, to: cfg.garyHandle)
            }
            var status = "sent"
            if case .failure(let e) = result { status = "failed: \(e.localizedDescription)" }
            log(["time": ISO8601DateFormatter().string(from: Date()), "to": cfg.garyHandle,
                 "note": letter.note, "message": letter.textLine, "sent_as": kind == .text ? "text" : "letter", "picture": image?.path ?? "none",
                 "status": status])
            DispatchQueue.main.async { completion(result) }
        }
    }

    private static func deliver(_ message: String, image: URL?, to handle: String) throws {
        guard !handle.isEmpty else {
            throw ClaudeService.Failure(errorDescription: "Gary's iMessage handle isn't set in ~/.hamsterpal/config.json")
        }
        let script = """
        on run argv
            set theHandle to item 1 of argv
            set theMessage to item 2 of argv
            -- resolve the picture here, outside the Messages block: Messages can't resolve POSIX paths itself (-1728)
            set thePicture to missing value
            if (count of argv) > 2 then set thePicture to (POSIX file (item 3 of argv)) as alias
            tell application "Messages"
                set svc to 1st account whose service type = iMessage
                set gary to participant theHandle of svc
                if theMessage is not "" then send theMessage to gary
                if thePicture is not missing value then send thePicture to gary
            end tell
        end run
        """
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        p.arguments = ["-e", script, handle, message] + (image.map { [$0.path] } ?? [])
        let errPipe = Pipe()
        p.standardError = errPipe
        p.standardOutput = Pipe()
        try p.run()
        let err = errPipe.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        if p.terminationStatus != 0 {
            throw ClaudeService.Failure(errorDescription: String(decoding: err, as: UTF8.self)
                .trimmingCharacters(in: .whitespacesAndNewlines))
        }
    }

    private static func log(_ entry: [String: String]) {
        guard let d = try? JSONSerialization.data(withJSONObject: entry, options: [.sortedKeys]) else { return }
        let line = d + Data("\n".utf8)
        if let h = try? FileHandle(forWritingTo: Paths.letters) {
            h.seekToEndOfFile()
            h.write(line)
            try? h.close()
        } else {
            try? line.write(to: Paths.letters)
        }
    }
}
