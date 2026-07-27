<p align="center">
  <img src="assets/abendrot-icon.png" alt="Abendrot" width="140" height="140">
</p>

<h1 align="center">Abendrot</h1>

<p align="center">
  <strong>The macOS app for your circadian rhythm</strong><br>
  <br>
  Grounded in peer-reviewed light research, Abendrot warms your entire workspace around sunset because staring at bright blue light at night is suboptimal.<sup><a href="https://abendrot.app/#references">[1,4-6,8]</a></sup><br>
  <strong>Free and open source, forever. No ads, no in-app purchases, no paywall.</strong>
</p>

<p align="center">
  <a href="LICENSE"><img src="https://img.shields.io/badge/license-MIT-FD9228" alt="MIT license"></a>
  <img src="https://img.shields.io/badge/macOS-26%20Tahoe-FD9228" alt="macOS 26 Tahoe">
  <img src="https://img.shields.io/badge/architecture-universal-FD9228" alt="Universal Apple Silicon and Intel">
  <img src="https://img.shields.io/badge/status-pre--release-C2310A" alt="Pre-release">
  <a href="https://github.com/matthewrball/abendrot/stargazers"><img src="https://img.shields.io/github/stars/matthewrball/abendrot?color=FD9228" alt="GitHub stars"></a>
</p>

<p align="center">
  <sub>Built in the open · <a href="https://abendrot.app">abendrot.app</a> · MIT licensed</sub>
</p>

---

**Abendrot** is the f.lux / Night Shift successor built to do the thing the incumbents quietly fail at: reliably warm **external monitors** and the **buttonless Apple displays** — Studio Display, Pro Display XDR, LG UltraFine — and keep working on the newest Apple Silicon Macs, where the classic gamma trick silently stops warming. Without tracking you.

## Install

> [!IMPORTANT]
> **Pre-release:** signed/notarized distribution and the final physical-display release matrix are still pending. The install options below become available with v1.0; contributors can use the [development setup](CONTRIBUTING.md#getting-set-up) today.

### Homebrew

```sh
brew install --cask abendrot
```

### Direct download

Download the latest signed `.dmg` from [GitHub Releases](https://github.com/matthewrball/abendrot/releases/latest).

Requires macOS 26 "Tahoe" or later. Universal for Apple Silicon and Intel.

> Abendrot is free and open source under the MIT License. If it is useful to you, please [star the repository](https://github.com/matthewrball/abendrot/stargazers).

## Why Abendrot

- **Warmth that actually lands on every display.** A layered engine warms each display with the best true-warming method available — and **tells you which one each display is using**, never a silent no-op.
- **Reveal True Color.** Hold a global hotkey and warmth lifts across every display for color-critical work; release and it eases back. Built for designers and photographers.
- **Scriptable & AI-controllable.** An `abendrot` CLI drives the running app from your terminal — or from an AI assistant like Claude Code, Codex, or Cursor. Read live state as JSON, set warmth, trigger a reveal. *(see [Scripting & AI control](#scripting--ai-control))*
- **Health is the reason; reliability is the proof.** Abendrot helps you keep warmer, lower-blue light in the evening, and links the circadian research instead of making medical claims.
- **Genuinely trustworthy.** MIT-licensed, no telemetry, no account, runs entirely on your Mac. The anti-NightOwl.

## How it works

Warmth is applied per display by a layered engine that picks the best working method and reports it in the UI:

| Layer | What it is | Role |
|---|---|---|
| **Gamma** | The system display transfer table (`CGSetDisplayTransferByTable`) | **The universal true-warm default** — works OS-level on built-in *and* external displays, including buttonless Apple displays. Chip/OS-aware: used where it genuinely warms, never where it would silently no-op. |
| **Hardware (DDC)** | Real panel RGB-gain over DDC/CI | Opt-in per display — a hardware upgrade where a monitor exposes gain control. |
| **Overlay** | A per-screen Metal veil | The universal floor — works on every display type, always available as a fallback. |

Each connected display shows a small badge — `Gamma` / `Hardware` / `Overlay` — so you always know what's actually happening. The schedule follows your system Night Shift window when available, or a custom/manual schedule.

## Scripting & AI control

Abendrot ships a command-line tool, `abendrot`, that drives the **running app** — so you can script screen warmth from a shell, a keybinding, a `launchd`/`cron` job, or hand the same commands to an AI coding assistant like **Claude Code, Codex, or Cursor**. It's the same auditable engine the menu bar drives, now with a command surface you can read and automate.

```sh
abendrot set warmth 0.8        # warm the screen to 80%
abendrot status --json         # read live state as JSON — pipe it anywhere
abendrot reveal --hold 10      # momentary true-color peek, then ease back
```

**Trust boundary, stated honestly:** `abendrot` talks to the app as the **same macOS user, in your local session**, and changes **visual state only** — no network listener, no privileged helper. An AI assistant "controlling Abendrot" is just running the same `abendrot` command you could type yourself, and it can't reach any further than you can. When you install the app, the binary ships inside the bundle and the Homebrew cask symlinks it onto your `PATH`.

Every command supports `--json`, with scriptable exit codes. See [`AGENTS.md`](AGENTS.md) for the complete CLI and agent-control reference.

## Research and comparisons

- [Research and supporting references](https://abendrot.app/#science)
- [How Abendrot compares with Night Shift and f.lux](https://abendrot.app/#vs)

These pages are maintained on abendrot.app so claims, citations, and comparison data stay current in one place.

> General wellness, not medical advice. Abendrot reduces evening blue-light exposure; it is not a medical device and makes no claim to treat or improve any condition.

## Tech

Native **Swift 6** (SwiftUI + AppKit), **macOS 26 "Tahoe"**, distributed as a
universal Apple Silicon + Intel app. No Electron, no bundled runtime. The warmth
engine lives in a standalone, unit-tested Swift package (`WarmthKit`); the app
is a small menu-bar agent; the `abendrot` CLI is a separate thin client that
talks to the running app.

## Privacy

No telemetry. No analytics SDK, account, or identifiers. Settings and usage statistics stay on your Mac; only update checks contact the release host. See [`PRIVACY.md`](PRIVACY.md).

## Contributing

Issues and pull requests are welcome — bug reports from real display setups are especially valuable, since the whole point is reliability on hardware we can't all test on. See [`CONTRIBUTING.md`](CONTRIBUTING.md) for the local build and test setup. Security disclosures: [`SECURITY.md`](SECURITY.md).

## License

[MIT](LICENSE) © Matthew Ball. Free forever — never behind a paywall. If Abendrot helps your evenings, you can support its maintenance via GitHub Sponsors.

---

<p align="center"><sub>Soften into the evening.</sub></p>
