# Abendrot

> Your Mac's screen warms with the evening — on every display — so your nights stay calm and your mornings stay sharp.

**Abendrot** (German: *the red glow of sunset*) is a free, open-source, native macOS menu-bar app that warms your screen's color temperature across **every** display — built-in *and* external — to support your circadian rhythm, with an instant **Reveal True Color** hotkey for designers and a beautiful Liquid Glass interface.

It's the f.lux / Night Shift successor that actually works on external monitors and on the newest Apple Silicon Macs — where the incumbents silently fail — and you can read every line of it.

- **Free & open source** (MIT) · **native Swift** · **menu-bar only** · **no Electron** · **zero telemetry by default**
- Real warmth on **all** displays via a layered engine (hardware DDC → gamma → universal Metal overlay) that *tells you which method each display uses*
- **Reveal True Color**: hold a hotkey to momentarily restore accurate color across every display for color-critical work
- Follows your sunset schedule, or run it manually — simple by default, with an advanced mode
- **Scriptable**: an `abendrot` CLI drives the running app from your terminal — and lets AI assistants (Claude Code, Codex, Cursor) control it too *(in development)*

**Status:** Planning complete; brand/design and build in progress. Not yet released.

- Website: https://abendrot.app *(coming soon)*
- Plan & docs: [`docs/abendrot-plan.md`](docs/abendrot-plan.md)
- Built for macOS 26 "Tahoe", Apple Silicon.

> General wellness, not medical advice. Abendrot reduces evening blue-light exposure on a schedule; it links the science rather than making health claims.

---

## Scripting & AI control

Abendrot ships a command-line tool, `abendrot`, that drives the **running app** — so you can script screen warmth from a shell, a keybinding, a `launchd`/`cron` job, or hand the same commands to an AI coding assistant like **Claude Code, Codex, or Cursor**. It's the same auditable engine the menu bar drives, now with a command surface you can read and automate.

```sh
abendrot set warmth 0.8        # warm the screen to 80%
abendrot status --json         # read live state as JSON — pipe it anywhere
abendrot reveal --hold 10      # momentary true-color peek, then ease back
```

**Trust boundary, stated honestly:** `abendrot` talks to the app as the **same macOS user, in your local session**, and changes **visual state only**. There's no network listener and no privileged helper — an AI assistant "controlling Abendrot" is just running the same `abendrot` command you could type yourself, and it can't reach any further than you can.

> The CLI is **in development** (v1 command surface below). An official Abendrot **MCP server is a planned fast-follow** ("MCP coming") — until then, the AI integration is this CLI.

### Install (draft)

The Homebrew cask ships the CLI inside the app bundle and symlinks it onto your `PATH`:

```sh
brew install --cask abendrot   # draft — not yet published
```

`abendrot --version` and `abendrot --help` confirm it's wired up.

### Automation

Common tasks → commands (v1 surface). Run `abendrot --help` for the full list.

| Task | Command |
|---|---|
| Set warmth (0–1, or by Kelvin) | `abendrot set warmth 0.8` · `abendrot set warmth --kelvin 2700` |
| Read live status as JSON | `abendrot status --json` |
| Read one configured setting | `abendrot get warmth` |
| Turn warming on / off | `abendrot on` · `abendrot off` |
| Set the schedule mode | `abendrot set mode sunset` *(or `always-on` / `off`)* |
| Set the warmest point the slider maps to | `abendrot set max-warmth 1900` |
| Choose hold vs toggle for reveal | `abendrot set reveal-mode hold` *(or `toggle`)* |
| Set location for the sunset schedule | `abendrot set location --auto` *(or `<lat> <lon>`)* |
| Exclude an app from warming | `abendrot exclude add com.apple.FinalCut` |
| List / remove exclusions | `abendrot exclude list` · `abendrot exclude remove <bundle-id>` |
| Momentary true-color reveal | `abendrot reveal --hold 8` |

---

*This README is a stub; the full marketing README (demo GIF, badges, comparison table, install) ships with v1.0 — see plan §12.*
