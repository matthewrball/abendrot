---
project: abendrot
project_path: /Users/ball/Documents/abendrot
created: 2026-06-16
origin_session: experiment (Documents/experiment) — planning/research session
status: SESSION 5 COMPLETE (2026-06-17) — §25 warming overhaul DONE + verified on real hardware (gamma is now the universal true-warm path). LIVE SOURCE OF TRUTH = RESUME-PROMPT.md (rewritten as the Session-5→6 handoff) + docs/abendrot-plan.md §25. This HANDOFF.md is the earlier full-context/decisions doc; durable decisions below still hold, but the current state + next steps (incl. the circadian-health "optimal max warmth" research) are in RESUME-PROMPT.md.
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
- **Brand picks (provisional, 2026-06-16):** accent = **Ember amber** `#FFAB5C`; icon = **Sunset arc**. Tokens in `brand/brand-direction.md`. NOT final — a dedicated iterate-en-masse brand-refinement exercise comes next (plan §5.5).
- **Open decision (CCG audit §21.6):** precede the polished 1.0 with signed public betas (0.1→0.9) for hardware validation? **✅ CONFIRMED 2026-06-16 — staged betas adopted** (0.1 overlay → 0.2 DDC opt-in → 0.3 Sparkle → 1.0 branded launch after the hardware matrix passes); DDC opt-in-per-display until restore tooling proven. Full audit in `docs/research/plan-audit-ccg.md`; accepted improvements folded into plan **§21**.

## Done
- 3 background research sweeps (market/UX/naming/tech/analytics/marketing/science + stack-decision/exemplar-teardowns) → synthesized.
- CCG (Claude+Codex+Gemini) name brainstorm + a real name-clearance pass (Abendrot won on ownability/empty namespace over Gloam/Ruhe/etc.).
- Studied references: fayazara/macos-app-skills (build/Sparkle/DMG/overlay patterns — reimplement, README-only-MIT license caveat), dopedrop.app, wisprflow.ai.
- Master plan written + all 8 open decisions confirmed.
- This `Documents/abendrot` home created; artifacts preserved; local git initialized.
- Brand exploration page built (`brand/explorations/index.html`); founder chose **Ember amber + Sunset arc** as the working direction (provisional). Working tokens captured in `brand/brand-direction.md`.

## Next steps (in order)
1. **Brand-refinement exercise (iterate en masse — the immediate next task):** starting from the Ember amber + Sunset arc direction, generate many parallel variations of the icon (`.icns` ramp + 16/18px menu-bar template, light/dark) and the key screens, review side-by-side, founder-led selection; finalize tokens/type/motion; then Liquid Glass UI mockups (menu-bar popover, advanced mode, Settings, landing hero) and mirror to Figma. Brand is locked only on sign-off (plan §5.5). Outputs go in `brand/`.
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

## Session continuity — preserve on /clear (ephemeral / conversation-only context)
Things that live only in the dying session or in ephemeral `/tmp`, and how to recover them:
- **Localhost exploration server is ephemeral** (was on port 8733; dies on session end/reboot). The page itself is committed — re-serve with: `python3 -m http.server 8733 --directory /Users/ball/Documents/abendrot/brand/explorations` then open `http://localhost:8733`.
- **Background task outputs live in `/private/tmp/.../tasks/*.output` and are ephemeral.** All important ones are already copied into `docs/research/` (research sweeps, naming pools, plan-audit). If resuming mid-audit, re-run the audit rather than hunting `/tmp`.
- **CCG advisor artifacts** are written under `Documents/experiment/.omc/artifacts/ask/` (the OLD session dir), NOT this repo. The ones that matter are copied into `docs/research/`.
- **Canonical plan = `docs/abendrot-plan.md`.** A stale snapshot exists at `Documents/experiment/.omc/plans/abendrot-plan.md` — ignore it; only edit the one in this repo.
- **Project memory** is at `~/.claude/projects/-Users-ball-Documents-experiment/memory/abendrot-app-project.md` (note: under the *experiment* session path; it auto-loads). Update it there.
- **Local git identity** for this repo is set to personal: `Matthew Ball <matthew.robert.ball@gmail.com>` (GitHub `matthewrball`), NOT the OnrampBitcoin email. Public repo not yet created (held until push-ready).
- **Build-critical reference detail** that was only in chat is now saved: `docs/research/reference-macos-app-skills.md` (NSPanel/Sparkle/Settings-glass/DMG patterns + gaps), `docs/research/name-clearance.md` (why Abendrot), `brand/brand-direction.md` (tokens + DopeDrop Liquid-Glass CSS recipe). Wispr Flow deep-dive + DopeDrop sit in `docs/research/research-sweep-stack-exemplars.json`.
- **Plan audit (CCG, 2026-06-16):** the Codex+Gemini full-plan audit and the improvements applied from it are recorded in plan + `docs/research/plan-audit-ccg.md` (see that file for the raw advisor findings).

## Session 2 — execution state (2026-06-16, RESUME HERE)
Execution kicked off. Large verified body of work committed on branch **`build`** (commit `7a7fb7e`, **local only — NOT pushed**). The full `WarmthKit` package **builds + 41 unit tests pass on Xcode 26.5**.

**Built (all on `build`):**
- `WarmthKit/` — engine package: frozen contract (`docs/engine/warmthkit-api-contract.md`), real `WarmthCore` (Kelvin↔gain, schedule resolver, `LayerResolver`, schedule-degrade policy); overlay/DDC/gamma/NightShift backends **stubbed** (= the M0/M2 milestones — no real pixel warming yet).
- `App/` — menu-bar app UI (`MenuBarExtra`, popover, advanced, programmatic Liquid Glass Settings, onboarding) against the contract; `project.yml` (XcodeGen → `xcodegen generate`).
- `brand/` — Ember-amber tokens + Liquid Glass components + 3-3-1 icon explorations. **PROVISIONAL — founder selection still pending** (serve: `python3 -m http.server 8733 --directory brand`; recommendation: app icon **B3** + 18px menu-bar **A1** glyph + Ember amber).
- `landing/` — cinematic Vite site (PREVIEW ONLY, never deployed). `../abendrot-site/` — minimal coming-soon placeholder (sibling dir, not deployed).
- `scripts/` + `.github/` — two-mode release/CI; `docs/qa/`, `docs/marketing/`, `PRIVACY.md` — QA suite + content/GTM.

**CCG review applied + verified:** engine coordination bugs (B1 can't-resume-warming, B2 default-never-warms→evening-fallback, kill-switch + DDC-opt-in enforcement, AsyncStream actor-isolation), release/CI integrity, app quit/login/Sparkle, landing a11y. Full task list persists in-session.

**Session-2 decisions (plan §22):** signing **DEFERRED** (no $99 Apple account yet — build/test local unsigned; mode-A signed pipeline gated on later-supplied creds); binaries → **GitHub Releases**; landing on **abendrot.app**.

**Xcode MCP:** native `xcrun mcpbridge` registered at **user scope**, Intelligence-pane toggle ON, **connected**. Tools load at session START → after a restart the new session can build/launch/diagnose the app live.

**Next:** (1) founder brand selection; (2) **M0** — implement the real `OverlayRenderer` Metal veil (first actual pixel warming) + **M7** hotplug observer; then **M2** DDC. (3) Still founder-gated: create public repo, push to remote, live deploy, external posts.

## Session 3 — state (2026-06-17): icon, brand pivot, engine system layers, public repo
**→ See `RESUME-PROMPT.md` for the full, paste-able handoff.** Deltas since Session 2:
- **Public repo is LIVE:** github.com/matthewrball/abendrot (PUBLIC, MIT, **clean single-commit history — all planning scrubbed/hidden**). CI is **GREEN**. It is **BEHIND** this private repo (no icon / sunset palette / M7 yet) → a **re-publish is needed** (founder push gate). Clean export dir: `../abendrot-public`.
- **Engine system layers landed + verified — `swift test` = 53 tests pass:** M0 overlay (real; alpha-tint, true-multiply = §18 future), **M7** hotplug/wake re-baseline, **real Night Shift follower** (`CBBlueLightClient`), **gamma classification**. **DDC (`HardwareDDC`) is STILL the stub → M2 is the next milestone** (IOAVService + EDID snapshot/verify/restore + emergency restore; needs real external monitors to verify).
- **App icon shipped + baked into the built `.app`:** founder art `assets/abendrot-iteration3.png` → masked `assets/abendrot.png` → iconset/`.icns`/`AppIcon.appiconset`. Reproducible: `python3 scripts/icon/build-icons.py`.
- **Brand pivoted to the icon's SUNSET palette** (founder: "maybe temporary"): grounds `#160A12`/`#221019`/`#341320`, accent `#FD9228`/`#FFC061`/`#C2310A`, `--sunset-sky` gradient — applied + build-verified across `brand/tokens.{css,json}`, the app's `Colors.xcassets` (19 colorsets), the landing page, and the coming-soon site.
- **Env:** full **Xcode 26.5** installed (license agreed) — `swift build`/`swift test`/`xcodebuild` all work; Xcode **MCP** registered (user scope) — loads after a session restart. Tools: xcodegen/Pillow/sips/iconutil.
- **Next:** **M2 (DDC)** + a real-hardware pass; re-publish the public repo; then live QA/hardware-matrix runs, motion polish, landing deploy — all founder-gated.
