# Abendrot — Launch Tracker

**Abendrot** is a free, open-source (MIT), native macOS menu-bar app that warms display color temperature across **every** display — built-in *and* external — to support circadian health in the evening, with a hold-to-"Reveal True Color" hotkey and a Liquid Glass UI. Zero telemetry by default. **Current status:** the engine + app build and run end-to-end on real hardware; the §25 "true warming" overhaul is done and verified (gamma is the universal true-warm path on base Apple Silicon, confirmed on M5 Air + LG UltraFine). Remaining before a public 1.0: finalize the max-warmth ceiling, add settings persistence, design the incompatibility notice, run the hardware test matrix, re-publish the public repo, and ship the landing site + launch campaign. Signing/notarization is **deferred** (no Apple Developer account yet).

**Last updated:** 2026-06-17

**Legend:** ✅ done · 🟡 doing · ⬜ todo · 🔒 founder-gated · ⛔ blocked

> This is the founder's single source of truth for "what do I actually have to do to launch Abendrot." It spans engineering, testing, signing, the public repo, the website, marketing, SEO/AEO, social, and launch day. Keep it current (see *How to use this file* at the bottom).

---

## Phase 1 — Engine & App (WarmthKit + Abendrot.app)

The long pole. The core warming engine is built, tested (91 tests / 21 suites green), and verified live on the founder's hardware. Open items are mostly polish, persistence, and one pending product decision.

- [x] `WarmthKit` SPM package — 6-module split (WarmthCore / DisplayServices / HardwareDDC / OverlayRenderer / NightShiftBridge / WarmthKit + CInterop); frozen public contract (`docs/engine/warmthkit-api-contract.md`)
- [x] Metal overlay backend (universal floor — works on every display type)
- [x] Gamma backend — now the **universal true-warm default** for any display where the transfer table works (built-in + external), incl. buttonless Apple panels (UltraFine / Studio Display / Pro Display XDR)
- [x] `GammaClassifier` chip-aware + fail-safe (denies gamma → overlay on unreadable/unrecognized chips; never a false "Gamma" badge)
- [x] DDC backend — demoted to **opt-in hardware upgrade** + external true-warm path for the gamma-broken M5 Pro/Max/Ultra bracket
- [x] Night Shift follower (read-only `CBBlueLightClient`) + schedule fix (`.followSystemNightShift` warms in the evening window with configured warmth)
- [x] Hotplug / wake re-baseline (M7)
- [x] Mired-linear strength→Kelvin curve (perceptually even)
- [x] Quit control in popover footer (power icon + ⌘Q, routes through `applicationShouldTerminate` → displays neutral-reset on exit)
- [x] Crash/quit neutral-reset; stable-identity display keying
- [x] App builds end-to-end (menu-bar agent, LSUIElement) and verified true-warming live on M5 Air + LG UltraFine
- [x] **Max-warmth ceiling — DECIDED & implemented (Session-6, HYBRID)** ✅ — `defaultWarmestPoint` 500K → **1900K** (everyday slider max = blue fully removed), default strength 0.15 → **0.7** (out-of-box ~2412K), `Kelvin.everydayWarmest=1900` added, `warmestSupported=500` kept as the absolute floor. Also fixed the `globalKelvin` 2700K readout bug + added warmest-point persistence. Verified: 91/21 tests, BUILD SUCCEEDED, code-review pass applied. *Founder to live-verify the feel.* (Research: `docs/research/max-warmth-circadian-research.md`.)
- [x] **Maximum-warmth dial (opt-in expanded range)** ✅ — built `MaximumWarmthControl` (Settings → Advanced): an opt-in "Expanded range" toggle unlocks 1900K → 500K (pure red) for power users with a hedged, cited note; pure-red is off the everyday slider. *Founder to live-verify + tune copy.*
- [ ] **§25.B Settings persistence** 🟡 — `warmestPoint` now persists (Session-6, focused slice). Still resetting every launch: `isEnabled` / `globalWarmth` / `scheduleMode`. Add `@AppStorage` / a settings store so the rest of user state survives relaunch too.
- [ ] **§25.J Incompatibility notice — design with founder** 🟡 🔒 — DRAFT exists (per-row "Tint only — can't truly warm" + ⚠ tooltip; app-level banner when ALL displays are tint-only). Refine tone/copy/prominence **with the founder** (founder wants to own this UX); add the real chip + macOS version string, a tappable "Why?" explainer, and an onboarding callout. Preview via `ABENDROT_FORCE_TINT_ONLY=1` on a compatible Mac.
- [x] §25 dev preview hook — force overlay-only/incompatible state on a compatible Mac (env var + `setPrivateAPIsEnabled(false)` kill switch) so the founder can design the notice
- [ ] Advanced mode + tabbed Liquid Glass Settings (per-display curves, per-app exclusions, layer override, screenshot-exempt, hide-from-menu-bar) ⬜ — verify completeness against §4/§21.3 before 1.0
- [ ] "The Science" panel (cited, hedged — must obey §13) ⬜ — wire the verified evidence base (`docs/marketing/evidence-base.md` ← canonical claims + 24-paper citation library; `docs/research/max-warmth-circadian-research.md`; `docs/marketing/science-snippets.md`)
- [ ] Onboarding ("3 clicks to warmth") final pass ⬜
- [ ] M2 DDC real-hardware verification ⬜ — still unverified on real panels; lower priority now (gamma covers most externals incl. buttonless Apple displays) but needed before DDC is trustworthy as the opt-in upgrade

---

## Phase 2 — Pre-Release Testing Matrix (§25.K — BINDING before 1.0)

The single biggest validation gap. Gamma is verified on exactly one config (base M5 + built-in + LG UltraFine). It is OS-level so it *should* generalize, but specific monitor/GPU/connection combos can silently no-op. **This matrix maps where gamma truly warms vs where it tints, and confirms the incompatibility notice fires correctly per config.** The founder wants to design the incompatible-state UX as part of this.

- [ ] **Monitor coverage** ⬜ — many brands × connection types (HDMI / DisplayPort / Thunderbolt / USB-C) × resolutions × HDR/EDR on/off; record gamma=true-warm vs silent-no-op for each
- [ ] **Mac config coverage** ⬜ — M-series base / Pro / Max / Ultra, Intel, across multiple macOS 26.x point releases (gamma is known broken on M5 Pro/Max/Ultra ≥ 26.3)
- [ ] **Buttonless Apple panels** ⬜ — Studio Display / Pro Display XDR (no DDC; gamma is the only true-warm path) — confirm gamma warms them
- [ ] **Incompatibility-notice validation** ⬜ 🔒 — for each config where gamma can't warm, confirm the §25.J notice fires and reads well; founder designs this UX
- [ ] **Failure-injection / persistence suite** ⬜ — crash-during-DDC-write, SIGKILL, wake-while-service-gone, hotplug-during-reveal-hold, lost-keyUp-across-Space, duplicate identical monitors, competing apps (f.lux / Lunar / BetterDisplay / MonitorControl) — spec at `docs/qa/failure-injection-suite.md`
- [ ] **Reveal-true-color stress** ⬜ — <150ms restore, watchdog recovers lost keyUp, zero stuck-suspended in 100-cycle test
- [ ] **A11y + appearance** ⬜ — Reduce Motion / Reduce Transparency (ember-tinted SOLID fallback, not grey), VoiceOver, light/dark
- [ ] Test plans exist: `docs/qa/hardware-matrix.md`, `docs/qa/acceptance-gates.md`, `docs/qa/unit-test-plan.md` — execute against real hardware

---

## Phase 3 — Code Signing / Notarization (DEFERRED)

> **Do not claim "notarized" or "signed" anywhere (site, README, posts) during this phase.** No $99/yr Apple Developer Program account purchased yet (cost decision, §22). Build + the full hardware matrix run **unsigned / local** — no account needed for development. The load-bearing trust claims pre-signing are **"open source, auditable, no telemetry by default."**

- [x] Two-mode release pipeline scaffolded — mode A (Developer-ID signed + notarized + stapled, gated on later credentials) and mode B (unsigned/local + plain `hdiutil` DMG = current default). Scripts in `scripts/release/` + `scripts/dmg/`
- [ ] **Decide whether to buy the $99/yr Apple Developer account before launch** ⬜ 🔒 — founder cost/timing call. Unsigned Gatekeeper first-launch ("right-click → Open") is a real friction tax at launch; weigh against $99.
- [ ] Developer ID Application cert + Hardened Runtime (no App Sandbox) ⬜ — only once account exists
- [ ] `notarytool submit --wait` + `stapler staple` the `.app` and `.dmg` ⬜
- [ ] Sign nested Sparkle bundles inside-out ⬜
- [ ] Branded DMG (`pretty-dmg` on UI runner) + deterministic `plain-dmg` fallback; gate release on ≥1 notarized+stapled DMG ⬜ (notarize step blocked on account)
- [ ] Sparkle EdDSA appcast signing — key in login keychain only, never in repo ⬜
- [ ] CI notarization job (currently scaffolded but inert without credentials) ⬜

---

## Phase 4 — Public Repo (github.com/matthewrball/abendrot) 🔒

The public repo **exists and is PUBLIC** (last pushed 2026-06-17) with README, LICENSE (MIT), CONTRIBUTING, SECURITY, PRIVACY, App/, WarmthKit/, scripts/, project.yml, CI. **It is BEHIND** the private `build` repo — it lacks the §25 engine overhaul, the icon, and the sunset palette. The private build repo (`/Users/ball/Documents/abendrot`, branch `build`) is **never pushed** and carries full planning history.

- [x] Public repo created, MIT-licensed, with README / CONTRIBUTING / SECURITY / PRIVACY
- [x] CI scaffold present (`.github/workflows/ci.yml`)
- [ ] **Re-publish §25 engine work to public repo** ⬜ 🔒 — carry over the warming overhaul, icon, and sunset palette; re-scrub all planning tells before pushing (two-repo model: public stays clean of planning history)
- [ ] **Final founder decision on whether/when to push** ⬜ 🔒 — pushing the public repo is a founder gate
- [ ] README conversion pass ⬜ — demo GIF of the warm-shift, badges (MIT / latest release / macOS / stars), feature table, comparison vs Night Shift / f.lux, "audit the engine" code snippet, install/usage. Draft at `docs/marketing/README-draft.md`
- [ ] Repo hygiene ⬜ — custom Open Graph social preview (1280×640), up to 20 topics (`macos, swift, blue-light, night-shift, f-lux, circadian-rhythm, color-temperature, menu-bar, ...`), pin, enable Discussions
- [ ] Homebrew cask (own tap first → homebrew-cask central later) ⬜ — depends on a signed/notarized release artifact
- [ ] awesome-* PRs (`jaywcjlove/awesome-mac` etc.) ⬜ — **after** README is polished and there's traction

---

## Phase 5 — Marketing Website (abendrot.app) 🔒

The landing site is **built locally for preview only** at `landing/` (Vite, vanilla HTML/CSS/JS, static `dist/` output; OG/icon assets present). It explicitly **must not deploy** — live deploy to the production domain is a founder gate. Domain `abendrot.app` is purchased.

- [x] Landing site built locally (`landing/` — hero, demo, badges, science, install structure; `dist/` builds; `vercel.json` present but not wired live)
- [x] Domain `abendrot.app` purchased (`.app` TLD = HSTS-preloaded, always HTTPS)
- [ ] **Deploy to abendrot.app (Vercel)** ⬜ 🔒 — founder-gated production deploy
- [ ] Final content pass on the live site ⬜ — real screenshots (gated on brand lock + the app's final UI), correct version, no "notarized" claim while unsigned
- [ ] Live demo asset (autoplay-muted cool↔warm loop / interactive slider) ⬜ — crafted render, not a Loom
- [ ] Proof-by-demonstration badge row (`Native Swift` · `Menu-bar only` · `< 5 MB` · `No Electron` · `Open source — read every line`) with a real baked-in number ⬜
- [ ] Verify OG/Twitter cards + the matthewball.me/abendrot → abendrot.app 301 redirect pre-launch ⬜
- [ ] Core Web Vitals / perf pass (PH/HN spikes punish slow pages) ⬜
- [ ] AlternativeTo listing as an f.lux / Night Shift alternative ⬜ (evergreen traffic)

---

## Phase 6 — Marketing Content & Messaging

The evidence base is **done and adversarially verified** — this is the safety net for every health claim. All content is BINDING on §13 guardrails (general-wellness, cite-don't-assert, never medical).

- [x] Verified circadian research + §13/FTC-safe claims library — `docs/research/max-warmth-circadian-research.md` (12 angles, 66 verified claims, HIGH confidence; includes "DO NOT CLAIM" list)
- [x] **Marketing evidence base (canonical source of truth)** — `docs/marketing/evidence-base.md` (12 approved headline claims with §13-safe wording + exact spectral levels, red-light story, spectrum table for graphics, 24-paper citation library, banned-claims list, 4 binding guardrails)
- [x] **Campaign material (site/social/SEO/AEO)** — `docs/marketing/messaging-and-campaigns.md` (positioning, taglines, web copy + FAQ, founder-gated social posts, SEO keywords, 12 AEO Q&A pairs — all grounded in the evidence base; compliance-swept clean)
- [x] Science snippets (cited, hedged) — `docs/marketing/science-snippets.md` *(predates the verified library — reconcile its citations against `evidence-base.md` before publishing)*
- [x] README draft — `docs/marketing/README-draft.md`
- [x] Privacy policy — `PRIVACY.md`
- [ ] **Lock the headline messaging** ⬜ — lead with the verifiable input fact: *"reaches zero blue-light emission at its warmest everyday setting"* + pair with "and dim your screen." Keep red as a **circadian-sparing footnote, never a hero** (the sub-1900K region is a model extrapolation — see research "weakest links").
- [ ] **Imagery guardrail (not just wording)** ⬜ — avoid any visual that implies red-light *therapy* or guaranteed sleep improvement; never juxtapose the product sentence with sleep-latency data. (Single biggest §13/FTC net-impression risk.)
- [ ] Channel-tailored leads ⬜ — Show HN / PH lead with reliability + Reveal True Color (tech crowd is cynical about "circadian health"); keep health as the brand story
- [ ] "Audit the engine" transparency snippet (real `WarmthKit` warm-write) for the NightOwl-burned audience ⬜
- [ ] Comparison / alternative copy (vs f.lux, Night Shift, Lunar/MonitorControl, NightOwl) — honest, feature-table-driven ⬜

---

## Phase 7 — SEO & AEO (Answer-Engine Optimization) 🟡 (mostly ⬜)

Goal: Abendrot is *the* answer when a human searches **or** an AI assistant is asked "best f.lux alternative for Mac," "warm my external monitor," "screen warmth for circadian health." Per §14.1 this is a parked-but-important workstream to **integrate with the site before 1.0**. All content obeys §13 guardrails.

- [ ] **Technical foundation on the site** ⬜ — `robots.txt` + XML sitemap; an **`llms.txt`** + per-page machine-readable summaries so answer engines can cite cleanly; canonical URLs; fast Core Web Vitals
- [ ] **Structured data (JSON-LD)** ⬜ — `SoftwareApplication`, `FAQPage`, `Article`/`BlogPosting`, `BreadcrumbList`
- [ ] **FAQ corpus (schema-marked, answer-engine-quotable)** ⬜ — does it work on external monitors? on M-series Tahoe? does it need permissions? is it private? how is it different from Night Shift / f.lux? — clean factual copy LLMs can quote verbatim
- [ ] **Circadian-health editorial** ⬜ — cited, hedged writeups each targeting a real query cluster (evening light, melanopic exposure, the science) — §13 BINDING
- [ ] **Comparison / alternative pages** ⬜ — Abendrot vs f.lux / Night Shift / Lunar / MonitorControl / NightOwl (captures the large "f.lux alternative" evergreen traffic; ties to AlternativeTo)
- [ ] **AI-citation + organic-ranking tracking** ⬜ — privacy-respecting way to measure AI-citation share + rankings over time
- [ ] Decide scope ⬜ 🔒 — §14.1 envisions a large multi-agent content team; founder un-tables and scopes when picked up

---

## Phase 8 — Social Campaign 🔒

All external posts are **founder-gated**. Sequencing (not one blast): soft pre-launch / build-in-public → coordinated Product Hunt + Show HN day → Reddit + socials → sustained. Drafts are written and staged.

- [x] Launch drafts written — `docs/marketing/launch/` (`product-hunt.md`, `show-hn.md`, `reddit.md`, `social-build-in-public.md`, `timeline.md`)
- [ ] **Reserve handles** (X / Mastodon / Bluesky) ⬜ 🔒
- [ ] **Build-in-public posts (2–4 weeks pre-launch)** ⬜ 🔒 — warm-shift clips, menu-bar UI, dev progress, circadian rationale; engage authentically with indie-Mac/design/FOSS communities weeks before any ask
- [ ] **v0.9 designer beta ~2 weeks pre-PH** ⬜ 🔒 — harvest real Liquid-Glass-UI screenshots for "social proof of beauty" in the PH gallery
- [ ] **Product Hunt** (Tue/Wed/Thu 12:01am PT) ⬜ 🔒 — gallery + 15–30s warm-shift demo GIF; first maker comment within 5 min; staggered timezone waves; ask for honest feedback, never upvotes
- [ ] **Show HN** (Tue–Thu 9am–12pm ET) ⬜ 🔒 — `Show HN: Abendrot – free, open-source screen-warmth/circadian app for macOS`; direct repo/DMG, author top-comment, be present for skeptical health-claim + technical questions
- [ ] **Reddit** ⬜ 🔒 — r/macapps (primary), r/macOS, r/QuantifiedSelf, r/eyestrain, r/sleep (no medical claims), r/opensource; verify each sub's rules; never identical cross-posts same hour
- [ ] **Newsletters / curators** ⬜ 🔒 — MacStories/AppStories (embargoed access), iOS Dev Weekly ("how I built the warmth engine"), Console.dev; 9to5Mac/MacRumors post-traction

---

## Phase 9 — Launch Day Checklist 🔒

All external actions founder-gated. One orchestrated day: PH → Show HN → Reddit → socials.

- [ ] Final release artifact built + (if account purchased) notarized + stapled; download link live ⬜ 🔒
- [ ] GitHub Release published with `.dmg` + `.zip` (download_count = the metric) ⬜ 🔒
- [ ] Landing site live + verified (OG cards, redirect, mobile CTA) ⬜ 🔒
- [ ] Public repo current (§25 work re-published, README polished, topics, social preview) ⬜ 🔒
- [ ] Product Hunt posted 12:01am PT + first maker comment within 5 min ⬜ 🔒
- [ ] Show HN posted + author top-comment ⬜ 🔒
- [ ] Reddit posts (staggered) ⬜ 🔒
- [ ] Social posts across X / Mastodon / Bluesky ⬜ 🔒
- [ ] Be present: reply to every PH/HN/Reddit comment within ~15 min ⬜ 🔒
- [ ] Monitor for first-launch / Gatekeeper friction reports (unsigned build) and respond ⬜

---

## Phase 10 — Post-Launch

- [ ] Sustain replies + capture social proof (stars, PH rank, HN points, download trend) ⬜
- [ ] awesome-* PRs once traction is real ⬜ 🔒
- [ ] "How I built the warmth engine" technical post ⬜
- [ ] Ship visible updates (Sparkle vN-1→vN dry-run verified) ⬜
- [ ] SEO the converting terms; sequence more channels ⬜
- [ ] Opt-in analytics (Aptabase, OFF by default) review — activation / schedule-vs-manual / method-distribution aggregates ⬜
- [ ] Signal active maintenance cadence; consider co-maintainers (solo-maintainer fragility) ⬜
- [ ] Roadmap follow-ups: per-user `warmestPoint` setting, ColorSync ICC injection (gamma-broken bracket), per-channel-multiply shader + HDR/EDR clamp, melanopic-aware dimming guidance, scenes/presets, localization ⬜

---

## How to use this file

This is a **living document** — update it as items complete, not just at milestones.

- When you finish a task, flip its `- [ ]` to `- [x]`, change the status emoji (⬜→✅, or 🟡 while in progress), and bump the **Last updated** line at the top.
- Keep 🔒 on anything that needs founder sign-off (pushing the public repo, deploying the landing, any external post). Never silently un-gate.
- When a decision is made (especially the **max-warmth ceiling** in Phase 1), record the chosen value here and in `docs/abendrot-plan.md` §25 so the two never drift.
- If something is genuinely unknown, leave it ⬜ with a one-line note rather than guessing.
- Source of truth for *why*: `docs/abendrot-plan.md` (master plan), `RESUME-PROMPT.md` (session handoff), `docs/research/max-warmth-circadian-research.md` (evidence base). This file is the *what's-left-to-do* view layered on top.
