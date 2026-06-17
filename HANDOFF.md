---
project: abendrot
project_path: /Users/ball/Documents/abendrot
created: 2026-06-16
origin_session: experiment (Documents/experiment) — planning/research session
status: planning complete · brand/design refinement next · execution not started
---

# Handoff — Abendrot

Resume in this directory (`Documents/abendrot`). This file + `docs/abendrot-plan.md` are the entry points. All research is preserved locally under `docs/research/` (the originals lived in an ephemeral `/tmp` path and are now safe here).

## What Abendrot is
A free, open-source, native macOS menu-bar app that warms screen color temperature across **every** display (built-in + external) for circadian health — the f.lux/Night Shift successor that actually works on external monitors and on M5 Macs running Tahoe (where Apple's gamma API is silently broken). Signature designer feature: **hold-to-reveal-true-color** hotkey. Beautiful Liquid Glass UI. MIT, auditable, zero-telemetry-by-default (the anti-NightOwl).

## Locked decisions
- **Name:** Abendrot (German "sunset glow"). **Domain:** `abendrot.app` (purchased) = primary; `matthewball.me/abendrot` 301-redirects to it. **Repo:** `github.com/matthewrball/abendrot` (public, create at execution kickoff).
- **Positioning:** circadian-health-first (reliability = proof). **License:** MIT.
- **Stack:** native Swift 6 (SwiftUI + AppKit), macOS 26 "Tahoe", Xcode 26. Local SPM `WarmthKit`, layered engine DDC → gamma → Metal overlay (overlay = reliable default on M5 Tahoe). Developer-ID + notarized (no MAS — private APIs), Sparkle auto-update, Homebrew cask.
- **Build scope:** fully-featured 1.0 in one push (internally milestoned M0–M6).
- **Analytics:** Aptabase, opt-in, OFF by default; downloads via GitHub/Homebrew counts.
- **Reveal hotkey:** ship both, default hold. **Schedule default:** follow system sunset (Night Shift schedule, read-only) + custom + always-on.
- **Launch:** soft pre-launch / build-in-public → coordinated Product Hunt + Show HN day → awesome-* PRs + newsletters.
- **Pricing:** free forever, optional GitHub Sponsors, never a paywall.
- **Design refs:** dopedrop.app (aesthetic + "tiny native app" boast), Wispr Flow (calm HUD/named-states/motion), Liquid Glass. Brand direction = twilight palette where warmth is default, pure white reserved for the true-color reveal; New York serif wordmark + SF Pro Text.

## Done
- 3 background research sweeps (market/UX/naming/tech/analytics/marketing/science + stack-decision/exemplar-teardowns) → synthesized.
- CCG (Claude+Codex+Gemini) name brainstorm + a real name-clearance pass (Abendrot won on ownability/empty namespace over Gloam/Ruhe/etc.).
- Studied references: fayazara/macos-app-skills (build/Sparkle/DMG/overlay patterns — reimplement, README-only-MIT license caveat), dopedrop.app, wisprflow.ai.
- Master plan written + all 8 open decisions confirmed.
- This `Documents/abendrot` home created; artifacts preserved; local git initialized.

## Next steps (in order)
1. **Brand/design refinement** (the immediate next task the founder requested): icon + wordmark concepts, palette/type tokens, Liquid Glass UI mockups (menu-bar popover, advanced mode, Settings), DMG window art, landing-page hero — produce a finished design system before code. Outputs go in `brand/`.
2. **Create the public GitHub repo** `matthewrball/abendrot` (MIT) when ready to push.
3. **Execution kickoff** via OMC `/team` across the §15 lanes (engine / UI / brand / landing / release-CI / content), dispatching heavy backend to **Opus 4.8 `/goal`** sessions; keep planning/design + the hardest engine logic in the lead session.

## Key files
- `docs/abendrot-plan.md` — the master plan (20 sections: opportunity → product → brand → architecture → build → QA → release → landing → analytics → community → science → GTM → execution orchestration → confirmed decisions → risks → roadmap → acceptance).
- `docs/research/research-sweep-main.json` — competitive landscape (20 apps), UX, naming, **tech APIs** (DDC/IOAVService, gamma, Metal overlay, CBBlueLightClient), analytics, marketing playbooks, **science citations**, synthesis.
- `docs/research/research-sweep-stack-exemplars.json` — native-Swift rationale + 14 app teardowns incl. the Wispr Flow deep-dive + top patterns/anti-patterns.
- `docs/research/naming-codex.md`, `naming-gemini.md` — name brainstorm pools.
- Memory: `~/.claude/projects/-Users-ball-Documents-experiment/memory/abendrot-app-project.md` (project memory) — note this lives under the *experiment* session's memory dir.

## Gotchas / notes
- macOS 26 APIs are recent — verify Liquid Glass (`NSGlassEffectView`/`.glassEffect`) and display behaviors against the shipping SDK before relying on them.
- Gamma (`CGSetDisplayTransferByTable`) is silently broken on M5 Tahoe → overlay is the default layer; gamma only behind a runtime self-test that MEASURES pixel change and auto-demotes.
- Private APIs (IOAVService, CBBlueLightClient) → no App Store, no sandbox; `dlopen`/`dlsym` + version-gate.
- macos-app-skills repo is README-only "MIT" with no LICENSE file → reimplement patterns, don't copy code.
- This project home (`Documents/abendrot`) is outside the original session's working dir — the founder will resume the session here directly.
