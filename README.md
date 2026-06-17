# Abendrot

> Your Mac's screen warms with the evening — on every display — so your nights stay calm and your mornings stay sharp.

**Abendrot** (German: *the red glow of sunset*) is a free, open-source, native macOS menu-bar app that warms your screen's color temperature across **every** display — built-in *and* external — to support your circadian rhythm in the evening. It has an instant **Reveal True Color** hotkey for color-critical work and a Liquid Glass interface, and you can read every line of it.

It aims to be the f.lux / Night Shift successor that actually works on external monitors and on the newest Apple Silicon Macs — where the incumbents quietly stop warming — without tracking you.

> **Status: pre-release, in active development.** Built in public. There is no downloadable build yet; you can build it from source today (see below). The first signed release will land here when it's ready.

## Why

- **Warmth on *every* display.** A layered engine tries the best available method per display and **tells you which one each display is using** — never a silent no-op.
- **Reveal True Color.** Hold a global hotkey to momentarily restore accurate color across all displays for design and photo work; release to ease warmth back.
- **Calm, not clinical.** A general-wellness take on evening light — evidence-honest, never alarmist, never a medical claim.
- **Genuinely private and open.** MIT-licensed, no telemetry by default, no account. Audit the code.

## How it works

Warmth is applied per display by a layered engine that picks the best working method and reports it in the UI:

| Layer | What it is | Notes |
|---|---|---|
| **Overlay** | A per-screen Metal/CoreAnimation veil | The universal, reliable default — works on every display type |
| **Hardware (DDC)** | Real panel RGB-gain over DDC/CI | Opt-in per display; the best result where a monitor supports it |
| **Gamma** | The system gamma table | Best-effort; classified per device/OS, off where it's known to be unreliable |

Each connected display shows a small badge — `Overlay` / `Hardware` / `Gamma` — so you always know what's actually happening.

> Implementation status: the overlay layer is implemented; the hardware (DDC) and gamma layers are in progress. The engine, schedule logic, and color math are covered by unit tests.

## Build from source

Requires **macOS 26 "Tahoe"**, **Xcode 26**, and [XcodeGen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`).

```sh
# Engine package — builds and tests headlessly, no app bundle needed
cd WarmthKit
swift test

# The app
xcodegen generate          # generates Abendrot.xcodeproj from project.yml
open Abendrot.xcodeproj     # then build & run in Xcode
```

## Tech

Native **Swift 6** (SwiftUI + AppKit), **macOS 26 "Tahoe"**, Apple Silicon. No Electron, no bundled runtime. The warmth engine lives in a standalone, unit-tested Swift package (`WarmthKit`); the app is a small menu-bar agent.

## Privacy

No telemetry by default. No account, no identifiers, nothing leaves your Mac unless you explicitly opt in to anonymous, aggregate usage stats later. See [`PRIVACY.md`](PRIVACY.md).

## Contributing

Issues and pull requests are welcome — see [`CONTRIBUTING.md`](CONTRIBUTING.md). Security reports: [`SECURITY.md`](SECURITY.md).

## License

[MIT](LICENSE) © Matthew Ball.

---

*General wellness, not medical advice. Abendrot reduces evening blue-light exposure on a schedule; it links the science rather than making health claims.*
