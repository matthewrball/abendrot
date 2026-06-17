<!--
  DRAFT — conversion README for founder review (Lane F / §12).
  Do NOT replace the live /README.md with this until v1.0 ships and the
  flagged claims below are confirmed. Placeholders in {{ }} need real
  assets / numbers before publishing. Flags marked [FLAG] need founder eyes.
-->

<p align="center">
  <img src="docs/marketing/assets/social-preview.png" alt="Abendrot — your Mac's screen warms with the evening, on every display" width="640">
  <!-- {{ social-preview.png: 1280×640 OG banner — app icon + wordmark + tagline. From Lane C brand kit. }} -->
</p>

<h1 align="center">Abendrot</h1>

<p align="center">
  <strong>Your Mac's screen warms with the evening — on every display — so your nights stay calm and your mornings stay sharp.</strong><br>
  A free, open-source, native macOS menu-bar app for circadian screen warmth. Read every line of it.
</p>

<p align="center">
  <a href="https://github.com/matthewrball/abendrot/releases/latest"><img src="https://img.shields.io/github/v/release/matthewrball/abendrot?label=download&color=FFAB5C" alt="Latest release"></a>
  <a href="LICENSE"><img src="https://img.shields.io/badge/license-MIT-FFAB5C" alt="MIT license"></a>
  <img src="https://img.shields.io/badge/macOS-26%20Tahoe-FFAB5C" alt="macOS 26 Tahoe">
  <img src="https://img.shields.io/badge/Apple%20Silicon-native-FFAB5C" alt="Apple Silicon">
  <a href="https://github.com/matthewrball/abendrot/stargazers"><img src="https://img.shields.io/github/stars/matthewrball/abendrot?color=FFAB5C" alt="GitHub stars"></a>
</p>

<p align="center">
  <strong>Coming with v1.0:</strong> <a href="https://github.com/matthewrball/abendrot/releases">Download for macOS</a> · <code>brew install --cask abendrot</code>
  &nbsp;·&nbsp;
  <a href="https://abendrot.app">abendrot.app</a>
</p>

<p align="center"><sub>Pre-release — built in the open. Signed, notarized builds + Homebrew cask land with v1.0.</sub></p>

<!-- [FLAG] Pre-release framing: once a notarized v1.0 ships, restore the direct
     "Download for macOS →" CTA (pointing at releases/latest) and drop the
     "Coming with v1.0" qualifier. Until then, do NOT present download / brew install
     as working today. -->

<p align="center">
  <img src="docs/marketing/assets/demo.gif" alt="Abendrot warming the screen across displays, then revealing true color" width="720">
  <!-- {{ demo.gif: 15–20s, ≤8 MB. Shows the warm shift across displays + menu-bar popover + hold-to-reveal-true-color. Crafted render, not a screen-grab. From Lane C / Lane B. }} -->
</p>

---

## Why Abendrot

Most screen-warming tools were built for an older Mac. Apple's own Night Shift often does nothing on external monitors, or tints them pink. The classic gamma-based apps — f.lux and its kin — quietly stop warming the screen on the newest Apple Silicon Macs: the system reports success, but nothing on screen changes. And after the NightOwl incident in 2023, "just trust the menu-bar app" stopped being good enough.

Abendrot is the calm, auditable answer. It treats reliable warmth on **every** display as the core engineering problem — not a buried side-feature — and it lets you read every line of how it does it.

- **Warmth that actually lands on every display.** A layered engine tries real hardware color temperature first (DDC), falls back to the system gamma path, and falls back again to a universal Metal overlay that works on built-in panels, the Studio Display, the Pro Display XDR, the LG UltraFine, and the newest Apple Silicon Macs — and it **tells you which method each display is using** instead of silently doing nothing.
- **Reveal True Color.** Hold a global hotkey and warmth lifts across every display for color-critical work; release and it eases back. Built for designers and photographers.
- **Health is the reason; reliability is the proof.** Abendrot helps you keep warmer, dimmer light in the evening. We link the circadian research rather than making medical claims about it (see [The science](#the-science)).
- **Genuinely trustworthy.** MIT-licensed, no telemetry by default, no account, runs entirely on your Mac. The anti-NightOwl.

> General wellness, not medical advice. Abendrot reduces evening blue-light exposure on a schedule. It links the science rather than making health claims.

---

## Features

| | Abendrot |
|---|---|
| Warms **every** display (built-in + external) | Layered engine: hardware DDC → gamma → universal Metal overlay |
| Tells you **how** each display is being warmed | Per-display badge: `Hardware` · `Gamma` · `Overlay` |
| Works on the newest Apple Silicon Macs | Routes around the silent gamma failure with the overlay path |
| **Reveal True Color** hotkey | Hold to restore accurate color across all displays; release to ease back |
| Follows your sunset | Reads the system Night Shift schedule when available, or runs on a custom/manual schedule |
| Simple by default, deep when you want it | One-click popover; advanced mode for per-display curves, per-app exclusions, layer override |
| Reveal during screen captures | Manual shortcut to show true color while you screenshot or record |
| Lives in the menu bar | Menu-bar only, no Dock icon — and you can hide it from the bar entirely |
| Native and tiny | Native Swift, no Electron, low idle CPU/GPU |
| Free and open source | MIT, no paywall, no account, no telemetry by default |

<!-- [FLAG] Confirm exact size/RAM/CPU numbers from a release build before baking them into copy or badges. Do not publish a number we haven't measured. -->

---

## How it compares

| | **Abendrot** | Apple Night Shift | f.lux | Redshift |
|---|---|---|---|---|
| Platform | macOS 26+ | macOS / iOS | macOS / Windows / Linux | Linux / X11 |
| Warms external monitors reliably | Yes (layered, with fallback) | Often fails or tints pink | Gamma only; unreliable on externals | X11 gamma only |
| Works on newest Apple Silicon | Yes (overlay path) | Built-in only | Gamma path can silently no-op | N/A on macOS |
| Shows which method each display uses | Yes | No | No | No |
| Per-display control | Yes | No | Limited | Per-output |
| Reveal-true-color hotkey | Yes (hold) | No | No | Toggle only |
| Open source | Yes (MIT) | No (Apple) | No (freeware, closed) | Yes (GPL) |
| Telemetry | None by default; opt-in, anonymous | Apple's | Unknown (closed-source) | None (open source) |
| Price | Free forever | Free (built in) | Free | Free |
| Native Mac app | Yes | Yes (built in) | Yes (dated UI) | No |

<!-- [FLAG] Comparison claims about competitors (Night Shift "tints pink", f.lux "silently no-ops on M-series") are sourced from our own research/testing and community reports. Keep them factual and hedged ("often", "can"); avoid absolute statements we can't substantiate. f.lux is freeware/closed-source, not open source. We do NOT assert f.lux telemetry is "None" — it is closed-source and therefore unverifiable, so the table says "Unknown (closed-source)". Apply the same honesty to any competitor cell: only state as fact what is observable/auditable. Redshift is X11-focused and effectively unmaintained on modern Linux; presented for completeness. -->

---

## Install

> **Pre-release.** Abendrot is being built in the open and isn't downloadable yet.
> Signed, notarized builds and a Homebrew cask arrive with **v1.0** — until then,
> the steps below describe how install *will* work. Watch
> [Releases](https://github.com/matthewrball/abendrot/releases) or
> [abendrot.app](https://abendrot.app) for the first build.

**Download** *(coming with v1.0)*

1. Grab the latest `.dmg` from [Releases](https://github.com/matthewrball/abendrot/releases).
2. Drag **Abendrot** to your Applications folder.
3. Launch it. It lives in the menu bar — look for the sunset arc.

**Homebrew** *(planned for v1.0)*

```sh
# Not published yet — available once the cask ships with v1.0:
brew install --cask abendrot
```

<!-- [FLAG] Until the app is signed + notarized (a v1.0 release decision — see "Trust & privacy"),
     first launch of an unsigned beta requires a Gatekeeper bypass (right-click → Open, or
     System Settings → Privacy & Security → Open Anyway). Add an explicit "Opening a beta build"
     note here for any pre-1.0 release, and REMOVE it once notarized builds ship. Do NOT print
     "signed and notarized" on a build that is not. -->

**Requirements (planned):** macOS 26 "Tahoe" or later, Apple Silicon.

---

## The science

Abendrot is built on a simple, well-supported idea: the eye has a non-visual light sensor (melanopsin in intrinsically photosensitive retinal ganglion cells, most sensitive around ~480 nm) that helps tell your brain whether it's day or night. Warmer, dimmer light in the evening means less of the short-wavelength light that signals "daytime."

We link the research rather than asserting health outcomes. A few starting points:

- The circadian system is sensitive to evening light, with most melatonin suppression occurring at modest indoor levels — [Zeitzer et al., 2000, *J Physiol*](https://pmc.ncbi.nlm.nih.gov/articles/PMC2270041/).
- It's the melanopic (short-wavelength) content that drives the effect, more than overall brightness — [Schoellhorn et al., 2023, *Communications Biology*](https://pmc.ncbi.nlm.nih.gov/articles/PMC9974389/).
- A scientific consensus on supportive light targets across the day — [Brown et al., 2022, *PLoS Biology*](https://journals.plos.org/plosbiology/article?id=10.1371/journal.pbio.3001571).
- Individual sensitivity to evening light varies more than 50-fold, so there's no single "right" setting — [Phillips et al., 2019, *PNAS*](https://www.pnas.org/doi/10.1073/pnas.1901824116).
- On eye strain: ophthalmologists find no good evidence that screen blue light damages your eyes; blinking, breaks, and the 20-20-20 habit help — [American Academy of Ophthalmology, 2024](https://www.aao.org/eye-health/tips-prevention/should-you-be-worried-about-blue-light).

Full, hedged write-ups with citations live in [`docs/marketing/science-snippets.md`](docs/marketing/science-snippets.md).

> Abendrot is a general-wellness tool, not a medical device, and makes no medical claims.

---

## Build from source

```sh
git clone https://github.com/matthewrball/abendrot.git
cd abendrot
open Abendrot.xcodeproj   # Xcode 26, macOS 26 SDK
```

Build and run the `Abendrot` scheme. The engine lives in the `WarmthKit` Swift package and has a headless test target:

```sh
swift test --package-path WarmthKit
```

See [`docs/abendrot-plan.md`](docs/abendrot-plan.md) for the full architecture.

<!-- [FLAG] Confirm the actual project filename (.xcodeproj vs .xcworkspace) and scheme name once Lane B/A scaffold lands. -->

---

## Contributing

Contributions are welcome — bug reports from real display setups are especially valuable, since the whole point is reliability on hardware we can't all test on.

- Read [`CONTRIBUTING.md`](CONTRIBUTING.md) and the [`CODE_OF_CONDUCT.md`](CODE_OF_CONDUCT.md).
- Open an issue or start a thread in [Discussions](https://github.com/matthewrball/abendrot/discussions) — especially if Abendrot misbehaves on a specific monitor or Mac.
- Security disclosures: see [`SECURITY.md`](SECURITY.md).

<!-- [FLAG] CONTRIBUTING.md, CODE_OF_CONDUCT.md, SECURITY.md are repo-hygiene files (§12) — drafted by another lane, not this one. Links assumed; confirm they exist before publishing. -->

---

## Privacy

Abendrot has **no telemetry by default**. No account, no tracking, no data leaves your Mac unless you explicitly opt in to anonymous, aggregate usage stats. Read the full, plain-language policy in [`PRIVACY.md`](PRIVACY.md).

---

## License

[MIT](LICENSE). Free forever. If Abendrot helps your evenings, you can support its maintenance via GitHub Sponsors — but it will never be behind a paywall.

---

<!--
  GitHub repository topics (set in repo settings; up to 20 — §12 intent).
  Dropped off-target picks: `dark-mode` (Abendrot warms color temperature; it is
  not a dark-mode/appearance toggle — wrong audience) and `wellness` (redundant
  with `health`). Replaced with on-target discovery terms (`flux-alternative`,
  `night-light`) per the §10 "f.lux alternative" SEO intent.
  macos, swift, swiftui, blue-light, night-shift, f-lux, flux, circadian-rhythm,
  eye-strain, screen-dimmer, color-temperature, menu-bar, sleep, health,
  open-source, productivity, ddc, apple-silicon, flux-alternative, night-light
-->
