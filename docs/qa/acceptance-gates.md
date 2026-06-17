# Abendrot — v1.0 Release Acceptance Gates (Lane G)

> **Status:** v0 test DESIGN, 2026-06-16. This is the **release-gate checklist** that maps
> every plan §19 acceptance criterion to *exactly how it is verified* and *in which lane*.
> It is the single document a release stops on. The engine is still being built, so no box
> is checked yet — this defines what "checkable" means.
>
> **Lane G is the independent release gate and enforces "never self-approve."** The lane
> that built a thing cannot tick its own acceptance box. Lane A (engine), Lane B (UI),
> Lane E (release) *produce*; Lane G *verifies and signs*. A criterion is "met" only with
> **fresh evidence** (a log, a photo, a timing number) attached — never an assertion.
>
> Grounded in plan `docs/abendrot-plan.md` §19, §8, §21.2; contract
> `docs/engine/warmthkit-api-contract.md` §11 verification gate, §0 invariants.

---

## 0. How a release passes this gate

1. Every row in §2 (product acceptance) and §3 (release/distribution) is **Green** with
   evidence linked.
2. Every `UNIT`/`UNIT+FAKE` scenario in `failure-injection-suite.md` is green in the hosted
   lane; every `HW` scenario is green on the self-hosted matrix (`hardware-matrix.md`).
3. The contract's own verification gate (§11) is satisfied: `swift build` clean on
   Xcode 26 / Swift 6 strict concurrency; `WarmthCore` units green; private-API smoke test
   loads-or-cleanly-degrades; a `code-reviewer` pass on the public surface.
4. A **Lane G reviewer who did not implement the feature** signs each gate. In CI this is
   the `environment: release-gate` manual approval (`hardware-matrix.md` §4.2).

**Gate states:** `Not started` · `In progress` · `Green (evidenced)` · `Blocked` ·
`Deferred (known gap, recorded)`. A `Deferred` row is allowed only with an explicit written
reason and founder/Lane-G sign-off — it is never a silent skip.

### Staged-beta gating (plan §21.6)

The full 1.0 gate is preceded by lighter per-beta gates so the hard parts are validated on
real hardware before the branded launch:

| Build | Minimum gate before it ships | Maps to |
|---|---|---|
| `0.1` | A1, A6 (overlay+hotkey+schedule), R1 partial (notarized DMG path proven) | overlay/hotkey/schedule/DMG/notarization |
| `0.2` | + A2 (badges), DDC opt-in + S1/S2/S11 restore tooling green on `generic-ddc` | DDC opt-in + restore tooling proven (§21‑E3) |
| `0.3` | + R2 (Sparkle vN-1→vN dry-run) | Sparkle |
| `1.0` | **entire §2 + §3 matrix green** | branded launch after hardware matrix passes |

---

## 1. Lane legend

| Lane | Owns | In this gate |
|---|---|---|
| **A** | `WarmthKit` engine | produces; cannot self-approve |
| **B** | App UI/UX | produces UI-facing criteria (badges render, hide-from-bar, a11y) |
| **E** | Release/CI | produces signing/notarization/DMG/Sparkle/Homebrew |
| **G** | **QA + this gate** | **verifies + signs every row**; runs failure-injection + matrix |

---

## 2. Product acceptance (plan §19) → verification → lane

### A1 — Warmth on built-in + ≥2 external types incl. one buttonless Apple (overlay) + one DDC (hardware), on M5 Tahoe; overlay is the guaranteed default

- **Verified by:** self-hosted matrix cells (`hardware-matrix.md` §1, §2.1/§2.3/§2.4): apply
  warmth, dump `state.displays`, assert each display warms via its expected layer; M5 Tahoe
  proves gamma is OFF and overlay carries it. **Lab/manual capture or capability
  classification — NOT a default in-app screen-capture probe** (§19, §21‑E1).
- **Evidence:** matrix logs (`gamma-m5.log`, `ddc-generic.log`) + reference photos of each
  panel warmed.
- **Lane:** built by **A**; verified/signed by **G** (on the physical matrix).
- **Status:** `Not started`

### A2 — Each display shows the correct method badge; engine never silently no-ops (self-test demotes broken layers)

- **Verified by:** `failure-injection-suite.md` S8 (HDR badge honesty), `hardware-matrix.md`
  §2.1 (gamma self-demote on M5) / §2.3 (overlay badge) / §2.4 (hardware badge);
  `unit-test-plan.md` §2.5 badge-string test. Assert `appliedMethod`/`badge` equals the
  layer actually doing the work; assert a silently-broken layer is demoted, not sat on
  (inv. 1, inv. 8).
- **Evidence:** unit log (badge strings) + matrix log showing M5 gamma → overlay demotion +
  UI screenshot (Lane B) of the rendered badge.
- **Lane:** **A** (engine demotion) + **B** (badge render); verified by **G**.
- **Status:** `Not started`

### A3 — Reveal True Color: hold restores true color across all displays in <150 ms; resumes on release; watchdog recovers a lost keyUp within N s; zero stuck-suspended in a 100-cycle test

- **Verified by:**
  - `<150 ms`: `hardware-matrix.md` §3.2 timing test (stopwatch on real overlay frames).
  - watchdog/lost-keyUp: `failure-injection-suite.md` S5 (`UNIT` pure-policy +
    `UNIT+FAKE`); `unit-test-plan.md` §2.4.
  - 100-cycle zero-stuck: `hardware-matrix.md` §3.1 loop test + manual Space-switch run.
- **Evidence:** timing number (< 150 ms), 100-cycle log (0 stuck), pure watchdog unit log,
  240 fps capture of the veil-lift (manual).
- **Lane:** **A** (engine + watchdog) + **B** (motion feel); verified by **G**.
- **Status:** `Not started`

### A4 — Schedule follow tracks the system Night Shift `active` flip without altering the user's Night Shift setting; degrades to solar if the private API fails

- **Verified by:** `failure-injection-suite.md` S8 (read-only follow, `writeCount == 0`) +
  S10 / `unit-test-plan.md` §2.2 `followDegradesToSolar`; manual spot-check on a matrix Mac:
  toggle Night Shift, confirm `isScheduleActiveNow` tracks it and the user's Night Shift
  config is unchanged afterward (contract §7).
- **Evidence:** unit log (degrade-to-solar + zero-write) + manual before/after screenshot of
  System Settings Night Shift state (unchanged).
- **Lane:** **A**; verified by **G**.
- **Status:** `Not started`

### A5 — Hide-from-menu-bar works and the app remains reachable + clearly re-enterable

- **Verified by:** **manual QA** (this is UI behavior, not engine): turn off "Show in menu
  bar", confirm the app keeps running, reachable via the global hotkey and via relaunch
  (which re-opens Settings), with a clear re-entry instruction shown (plan §4.3).
- **Evidence:** manual QA checklist run + screen recording of the hide → re-enter flow.
- **Lane:** **B**; verified by **G** (manual). (Out of engine scope — listed so the gate is
  complete, per §19.)
- **Status:** `Not started`

### A6 — Idle CPU/GPU ≈ 0% (overlay draws on change only); bundle < ~5 MB; RAM ~tens of MB

- **Verified by:** `hardware-matrix.md` §3.3 (`powermetrics` GPU residency + `ps` CPU over a
  steady 60 s window; record bundle size + RSS). Assert no continuous redraw (shape, not just
  a small percentage).
- **Evidence:** `idle-cpu.log`, `idle-gpu.log`, `du -sh Abendrot.app`, RSS sample.
- **Lane:** **A** (draw-on-change) + **E** (bundle size); verified by **G**.
- **Status:** `Not started`

### A7 — A11y: Reduce Motion / Reduce Transparency + VoiceOver respected; light/dark correct

- **Verified by:** **manual QA** with the accessibility settings toggled: confirm Reduce
  Motion disables the spring/ease, Reduce Transparency falls back to the **ember-tinted
  SOLID** (not grey — §21.3), VoiceOver reads the controls + badges, light/dark both render.
- **Evidence:** manual a11y checklist + screenshots in each mode.
- **Lane:** **B**; verified by **G** (manual).
- **Status:** `Not started`

---

## 3. Release / distribution acceptance (plan §19, §9, §21.2) → verification → lane

### R1 — Signed, notarized, stapled; clean Gatekeeper first-launch on a fresh Mac

- **Verified by:** `hardware-matrix.md` §3.4 — `spctl -a -vvv` (accepted, Notarized
  Developer ID), `codesign --verify --deep --strict`, `xcrun stapler validate`, plus a
  **manual fresh-user double-click** (§21.2 manual gate). In **Mode B** (no Apple account,
  per `docs/release/RELEASE.md`) the gate is the unsigned right-click→Open path and the
  notarized assertion is the **Mode A** release requirement — record which mode.
- **Evidence:** `spctl`/`codesign`/`stapler` output + manual fresh-account launch recording.
- **Lane:** **E** (signing/notarization pipeline); verified by **G** (fresh-Mac, manual).
- **Status:** `Not started`

### R2 — Sparkle vN-1 → vN auto-update succeeds

- **Verified by:** Lane E builds the appcast; **G** runs the update **dry-run** from the
  previous tag to the new one on a matrix Mac (per plan §8 release gates, §9 Sparkle), and
  confirms the app relaunches on the new version.
- **Evidence:** update-dry-run log + post-update `Abendrot.app` version string.
- **Lane:** **E**; verified by **G**.
- **Status:** `Not started`

### R3 — Contract verification gate (contract §11) satisfied

- **Verified by:** `swift build` clean on Xcode 26 / macOS 26 / Swift 6 strict concurrency;
  `WarmthCore` unit suite green (`unit-test-plan.md`); private-API **smoke test** loads
  IOAVService + CBBlueLightClient or cleanly reports `.unknown(privateSymbolUnavailable)`
  and stays overlay-only (contract §11, §9, §21‑E5 — **from M0**, not just at release);
  `code-reviewer` pass on the public surface for Sendable/actor-isolation.
- **Evidence:** build log, `WarmthCore` test log, smoke-test log, code-reviewer sign-off.
- **Lane:** **A** (engine) + **G** (review pass is a separate lane — never self-approve);
  signed by **G**.
- **Status:** `Not started`

### R4 — DMG robustness (plan §21.2)

- **Verified by:** Lane E produces ≥1 **notarized + stapled** DMG; **G** mounts the final
  DMG on a UI runner and verifies layout, signature, quarantine first-launch, and the
  `/Applications` drag-install (§21.2). (`create-dmg` AppleScript can't run headless — UI
  runner only.)
- **Evidence:** mounted-DMG verification log + screenshot of the drag-install window.
- **Lane:** **E**; verified by **G**.
- **Status:** `Not started`

### R5 — Full failure-injection suite green (the safety floor)

- **Verified by:** every scenario S1–S11 in `failure-injection-suite.md` at its required
  tier — `UNIT`/`UNIT+FAKE` green in hosted CI, `HW` green on the matrix. This is the
  **launch-recovery / `restoreAllDisplays()` / watchdog / kill-switch** safety net the whole
  product reputation rests on (the anti-NightOwl, anti-"f.lux silently broke" promise).
- **Evidence:** hosted-CI suite report + per-matrix-machine `HW` logs; the §2.3/§2.4 recovery
  photos.
- **Lane:** **A** (engine) builds; **G** owns and signs the suite.
- **Status:** `Not started`

---

## 4. Master gate table (one-glance)

| Gate | Criterion (short) | Primary verify doc | Built by | Signed by | Status |
|---|---|---|---|---|---|
| A1 | Warmth on built-in + 2 externals on M5 Tahoe, overlay default | hardware-matrix §2 | A | **G** | ☐ |
| A2 | Correct badge, never silent no-op | hardware-matrix §2.1, unit §2.5 | A/B | **G** | ☐ |
| A3 | Reveal <150 ms, watchdog, 100-cycle zero-stuck | hardware-matrix §3.1–3.2, fis S5 | A/B | **G** | ☐ |
| A4 | Night Shift follow read-only, solar degrade | fis S8/S10, unit §2.2 | A | **G** | ☐ |
| A5 | Hide-from-menu-bar + re-entry | manual QA | B | **G** | ☐ |
| A6 | Idle CPU/GPU ≈ 0%, < ~5 MB, RAM tens MB | hardware-matrix §3.3 | A/E | **G** | ☐ |
| A7 | Reduce Motion/Transparency, VoiceOver, light/dark | manual QA | B | **G** | ☐ |
| R1 | Signed/notarized/stapled, fresh-Mac Gatekeeper | hardware-matrix §3.4 | E | **G** | ☐ |
| R2 | Sparkle vN-1→vN update | update dry-run | E | **G** | ☐ |
| R3 | Contract §11 gate (build/units/smoke/review) | unit-test-plan, contract §11 | A/G | **G** | ☐ |
| R4 | DMG robustness (mount/sig/quarantine/drag) | release §21.2 | E | **G** | ☐ |
| R5 | Full failure-injection suite green | failure-injection-suite | A | **G** | ☐ |

**Release is releasable only when every row is `Green (evidenced)` (or an explicitly
recorded `Deferred`), and a Lane G reviewer who did not build the feature has signed it.**
That signature, not a self-assessment by the implementing lane, is the gate.
