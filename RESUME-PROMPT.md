I'm resuming the **Abendrot** project — a free, open-source, native macOS menu-bar app that warms screen color temperature across every display (built-in + external) for circadian health. This directory (`Documents/abendrot`) is the canonical home.

Before doing anything, read these in full:
1. `HANDOFF.md` — full context, locked decisions, gotchas, and the "Session continuity" notes.
2. `docs/abendrot-plan.md` — the master plan. Pay special attention to §15 (execution lanes), §16 (confirmed decisions), §6 + §21.1 (engine architecture + audit safety refinements), §5 + §21.3/21.4 (brand + Liquid Glass), and §9 + §21.2 (release/DMG).
3. Skim `brand/brand-direction.md` and `docs/research/` (research sweeps, plan-audit-ccg, reference-macos-app-skills, name-clearance).

Status: the plan is **APPROVED for execution**. Everything is locked — name **Abendrot**, domain **abendrot.app**, **MIT**, **native Swift/SwiftUI on macOS 26 Tahoe**, circadian-health-first positioning, Aptabase opt-in analytics, **staged-beta release strategy** (0.1 overlay → 0.2 DDC opt-in → 0.3 Sparkle → 1.0 branded launch), and the **provisional** brand direction **Ember amber + Sunset arc** (still to be refined en masse).

Now kick off execution via OMC **/team** across the lanes in plan §15, dispatching heavy backend to **Opus 4.8 `/goal`** sessions (max effort) and keeping the hardest engine logic + design taste in the lead session. Use **ultracode / workflows** for the parallel work. Confirm the lane plan with me first, then go. Suggested first moves (parallel):

- **Lane C — Brand refinement (do early; it gates UI + landing):** run the iterate-en-masse exercise (§5.5 / §21.4) — 3-3-1 icon variations on the Sunset-arc direction, the 18px "vibrant" menu-bar template (glows amber when active, survives wallpaper tinting), finalized Ember-amber tokens + dark/light, then the Liquid Glass component mockups (popover, advanced "liquid expansion", Settings). Keep me in the loop for selection. The starting artifact is `brand/explorations/index.html` (re-serve: `python3 -m http.server 8733 --directory brand/explorations`).
- **Lane A — Warmth engine:** write the `WarmthKit` spec from §6 + §21.1 (module split: WarmthCore / DisplayServices / HardwareDDC / OverlayRenderer / NightShiftBridge; overlay is the default layer, DDC opt-in with restore tooling, DisplayIdentity model, private-API kill switch, NO default screen-capture gamma probe), then dispatch to an Opus 4.8 `/goal`. Build to the staged-beta plan: **0.1 = overlay + hold-to-reveal hotkey + schedule + branded DMG + notarization** first.
- **Lane E — Release skeleton:** an M0 signed + hardened + notarized smoke build and the two-mode DMG (pretty + hdiutil fallback) early, per §21.2.

Decisions still mine — **ask me before doing these:** creating the public `matthewrball/abendrot` GitHub repo and whether to push the internal planning/research docs publicly or keep a private build repo first. Don't create any public repo, push, or post externally without my go-ahead.
