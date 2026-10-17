# HamsterPal 🐹

A tiny hamster that lives on a Mac, in the Dock or walking along the bottom of the screen. Click him and you can chat with Claude through him.

- **Chat:** answers come from the local `claude` CLI (Claude Code), so there's no API key to set up. He texts like a close friend: "hi ham" gets "hi rat 🐭".
- **Dock or desktop:** in the Dock he's an animated icon with a hamster wheel. On the desktop you can drag him around. He's a photo cut out with Apple's Vision subject lifting (`tools/cutout.swift`), with outfits to pick from (right-click → Outfit: Navy jacket or Whimsical), or a drawn hamster if you prefer.
- **Letters to the real hamster:** a hidden link in the chat lets you send an iMessage to one person, either as a plain text or as a picture of a handwritten letter (lined paper on a wooden desk, drawn with Core Graphics in Bradley Hand and HanziPen SC). Nothing is sent until you preview it and press Send, and every letter is logged locally.

## Build

Needs macOS 14+ with the Xcode command line tools, plus the `claude` CLI logged in.

```bash
./build.sh --run
```

This builds `HamsterPal.app`, installs it to `~/Applications`, and launches it. Settings live in `~/.hamsterpal/config.json`: set `garyHandle` to the phone number or iMessage email letters should go to, and `senderName` to your name.

## Layout

| File | What it does |
|---|---|
| `Sources/App.swift` | windows, Dock tile, wandering, menus |
| `Sources/Hamster.swift` | the photo and drawn hamsters and their animations |
| `Sources/Chat.swift` | chat window and the letter screens |
| `Sources/Services.swift` | settings, the Claude CLI call, iMessage sending |
| `Sources/HandLetter.swift` | the handwritten-letter renderer |
| `Sources/Letter.swift` | letter text, kaomoji, picture export |
| `Sources/Chatter.swift` | speech bubbles |
| `Sources/Theme.swift` | colors and emoji avatars |
