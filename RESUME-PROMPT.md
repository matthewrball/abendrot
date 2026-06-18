RESUMING **ABENDROT** — a free, open-source, MIT, native macOS menu-bar app that warms color
temperature across **every** display (built-in + external) for circadian health, with a hold-to-
"Reveal True Color" hotkey and a Liquid Glass UI; zero-telemetry-by-default. Canonical **PRIVATE
build repo:** `/Users/ball/Documents/abendrot` (branch `build`, **never pushed**). Public repo
`github.com/matthewrball/abendrot` is behind + founder-gated. This file is the **Session-5 → Session-6
handoff**; it supersedes the old contents.

**Read first, in full:** `docs/abendrot-plan.md` — especially **§25** (the warming overhaul; read its
*Session-5 RESULTS*, *RESULTS part 2*, and *founder directives* subsections top-to-bottom), §24 (M2
DDC log). Then `docs/engine/warmthkit-api-contract.md` (frozen engine contract),
`docs/engine/overlay-multiply-decision.md`, `docs/engine/ddc-protocol-spec.md`.

---

## Environment / build — FDA is now CLEARED
- The repo had been TCC/`com.apple.macl`-locked by a prior sandboxed agent. **Full Disk Access is
  now granted** → the repo is writable and the app builds end-to-end. (If writes ever hit "Operation
  not permitted" again: re-enable FDA for Terminal/Claude Code, or move the repo out of `~/Documents`.)
- **Build the app (no `xcodegen` needed — the `.xcodeproj` is current):**
  ```
  xcodebuild -project Abendrot.xcodeproj -scheme Abendrot -configuration Release \
    -derivedDataPath build/Release CODE_SIGNING_ALLOWED=NO build
  ```
  → app at `build/Release/Build/Products/Release/Abendrot.app`. It's a menu-bar agent (LSUIElement,
  no Dock icon); click the menu-bar glyph for the popover. **It now has a Quit button** (power icon
  in the popover footer + ⌘Q). To relaunch a fresh build: quit via that button, then `open …app`.
- **Engine tests:** `swift test --package-path WarmthKit` → **91 tests / 21 suites pass**.
- **Everything below is committed to `build`** (latest `51ffa84`); this session can be cleared safely.

---

## ⭐ Session 5 result — §25 warming overhaul is DONE + verified on real hardware
The founder's headline complaint ("warmth just tints, doesn't truly warm like BetterDisplay") is
**FIXED**, confirmed on the founder's real hardware (**Apple M5 MacBook Air + LG UltraFine**).

**Diagnosis (all adversarially verified — see plan §25):**
- **Gamma WORKS** (`CGSetDisplayTransferByTable`) on the founder's base M5 — both the built-in AND the
  LG UltraFine (external). The plan's "gamma is broken on Apple-Silicon Tahoe" was over-broad: the
  real 2026 regression hits **M5 Pro/Max/Ultra on macOS 26.3/26.4 only**; base M-series works.
- **CoreDisplay white-point** (Apple's Night Shift mechanism, `CoreDisplay_SetWhitePointWithDuration`)
  was researched + RULED OUT — it didn't warm in isolation and couples to Night Shift (violates our
  read-only-Night-Shift contract). Shelved as a *future* option for the M5 Pro/Max segment only.
- The earlier "no warming / broken" runs = schedule-gating + zero default warmth + no persistence +
  a stale build.

**Engine + app changes (committed: `1295d82` → `05b2c0e` → `0ebb09d` → `51ffa84`):**
- **Gamma is the UNIVERSAL true-warm default** for ANY display where the transfer table works (built-in
  + external) — `LayerResolver`/`WarmthEngine.recommend()`. It's OS-level + display-agnostic, and the
  **only** true-warm path for buttonless Apple displays (UltraFine / Studio Display / Pro Display XDR)
  that expose no DDC. DDC is demoted to an **opt-in hardware upgrade**; overlay is the floor.
- **`GammaClassifier` is chip-aware:** `.supported` on base M-series / Intel / pre-26; `.unsupported`
  ONLY on Pro/Max/Ultra (≥macOS 26). **Fail-safe** brand detection (`GammaClassifier.isBaseAppleSiliconBrand`,
  unit-tested): unreadable/unrecognized → deny gamma → overlay, never a false "Gamma" badge.
- **Schedule fix:** `.followSystemNightShift` follows Night Shift when ON, else the evening window with
  the user's configured warmth (kills "enabled but never warms").
- **Mired-linear** strength→Kelvin curve (perceptually even).
- **Quit button** (the LSUIElement agent had none) — routes through `applicationShouldTerminate` so
  displays neutral-reset on exit.
- **Incompatibility notice (DRAFT, §25.J):** per-display "Tint only — can't truly warm" + ⚠ tooltip
  when a display has no true-warm path; app-level banner when ALL displays are tint-only. **Preview
  it** (force the tint-only state on a compatible Mac):
  `ABENDROT_FORCE_TINT_ONLY=1 build/Release/Build/Products/Release/Abendrot.app/Contents/MacOS/Abendrot`
- **Verified:** 91 tests; an adversarial code-review pass applied (fixed the HIGH chip-detection
  fail-safe + others); app BUILD SUCCEEDED; founder confirmed true warming live on both displays.

**Founder-runnable probes** (standalone Swift, public CoreGraphics only, no app build):
`scripts/probe/gamma-probe.swift` (built-in), `…/gamma-probe-external.swift` (all displays),
`…/whitepoint-probe.swift` (CoreDisplay white-point — ruled out).

---

## ⭐⭐ THE #1 NEXT-SESSION TASK — circadian-health deep research: what is the OPTIMAL max warmth?
The founder pushed the slider's warmest end to **pure red (~500K)** this session, then flagged it
**might be too far**. Decide the ceiling with **research, not a guess.**

**Established engine facts:**
- The **blue channel gain hits 0 by ~1900K** — at/below ~1900K the display emits **zero blue** (blue
  fully off). "Minimize blue light" is already 100% achieved there.
- Below ~1900K, going warmer removes **green** too (green → 0 at ~500K = pure red). It does NOT remove
  more blue (there is none left).
- **Current code state:** Kelvin floor = 500, `defaultWarmestPoint` = 500K, default strength 0.15.
  This puts pure-red at the slider max and **compresses** the everyday range (3000–4000K) into the
  lower ~15% of the slider. **This is the thing under review and is likely to be pulled back.**

**Research question (run a deep, cited, adversarially-verified Workflow — melanopic/circadian lens,
§13 guardrails BINDING: general-wellness, cite-don't-assert, no medical claims):**
1. Melanopsin/ipRGC sensitivity peaks ~480nm (blue) with a tail into green (~500–550nm). **Does
   removing GREEN (beyond blue-already-gone) add any meaningful melanopic/circadian benefit, or is it
   negligible?** I.e., is there a physiological reason to go below ~1900K (pure-red), or is "blue 100%
   gone" the sensible extreme?
2. What CCT / melanopic-EDI does the literature support as the practical "maximally protective"
   evening target before diminishing returns + legibility collapse?

**The decision the research drives:**
- **Option A — cap at "blue 100% gone" (~1900K):** the sensible physiological extreme; no pure-red, no
  max-warmth dial needed; the everyday slider stays uncompressed. **Founder currently leans this way.**
- **Option B — keep pure-red available via a separate "Maximum warmth" dial:** main Warmth slider
  stays comfortable (6500K → ~1800K); an advanced/settings control lets power users push their own
  ceiling toward pure red. (Engine already has `setWarmestPoint()` wired — it's mostly a UI control.)

Run it as a **Workflow** (ultracode is on): fan-out web research on the melanopic action spectrum /
green-light circadian sensitivity / optimal evening CCT, adversarially verify citations, synthesize a
cited recommendation, then implement the chosen ceiling (likely pull the floor/warmestPoint back from
500K) and — only if Option B — build the Maximum-warmth dial. Rebuild; founder verifies.

---

## Other open §25 work (continue the plan)
- **§25.B Persistence (App-side):** settings (isEnabled / globalWarmth / scheduleMode / warmestPoint)
  reset every launch — only launchAtLogin + soft-tone persist. Add `@AppStorage` / a settings store.
- **§25.J Incompatibility notice — refine WITH founder:** the draft works; iterate tone/copy/prominence,
  add the actual chip + macOS version string, a tappable "Why?" explainer, an onboarding callout.
- **§25.K Pre-release testing matrix (BINDING before 1.0):** test gamma across MANY monitors (brands,
  HDMI/DP/TB/USB-C, HDR/EDR) + Mac configs (M base/Pro/Max/Ultra, Intel, multiple macOS 26.x) to map
  where gamma works vs silently no-ops; confirm the §25.J notice fires + reads well per incompatible
  config. Founder wants to design the incompatible-state UX as part of this.
- **Maximum-warmth dial** — gated on the circadian research above.
- **M2 DDC real-hardware pass** — still unverified on real hardware; now lower priority (gamma covers
  most externals incl. buttonless Apple displays), but DDC stays the opt-in upgrade + the external
  true-warm path for the M5 Pro/Max gamma-broken bracket.
- **Re-publish public repo** (carries the §25 engine work + icon + sunset palette) — founder-gated;
  re-scrub planning tells. **Landing deploy** to abendrot.app — founder-gated.

---

## Durable locked decisions / context
- **Signing DEFERRED** (no $99 Apple Developer account) — build/test unsigned/local; don't claim
  "notarized" pre-release. Load-bearing trust = "open source, auditable, no telemetry by default."
- **Two-repo model:** this dir = private build repo (full planning, NEVER pushed); the public repo =
  clean (no planning history) and BEHIND (lacks §25 engine work + icon + sunset palette) → re-publish
  needed (founder-gated).
- **Brand = icon-derived SUNSET palette** (founder: "maybe temporary"). Icon pipeline:
  `scripts/icon/build-icons.py`.
- **Engine:** `WarmthKit` SPM package; layers = overlay (floor) / gamma (now the universal true-warm
  default) / Night Shift follower (read-only) / M7 hotplug-wake / M2 DDC (opt-in). Frozen public contract.

## Founder gates — ASK before: pushing the public repo, deploying the landing, any external posts.

## FIRST ACTIONS (Session 6)
1. Read plan §25 (RESULTS + part 2 + founder directives) + the engine contract; confirm
   `swift test --package-path WarmthKit` → 91/21 green.
2. **Run the circadian-health deep-research Workflow on the optimal maximum warmth** (the #1 task) →
   decide Option A ("blue-gone ~1900K") vs Option B ("pure-red + Maximum-warmth dial").
3. Implement the chosen ceiling (likely pull the Kelvin floor / `defaultWarmestPoint` back from 500K),
   and — only if Option B — build the Maximum-warmth dial. Rebuild; founder verifies.
4. Then continue §25 pending: persistence, incompatibility-notice design refinement, pre-release
   testing matrix.

Keep design taste + the hardest engine logic in the lead session; dispatch heavy/parallel work to
subagents; verify in a separate lane (never self-approve); **commit to `build` only** (public push is
founder-gated).
