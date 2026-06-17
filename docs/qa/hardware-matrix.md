# Abendrot — Hardware Matrix & Self-Hosted Runner Runbook (Lane G)

> **Status:** v0 test DESIGN, 2026-06-16. Steps are written to be run against the real
> engine once Lane A ships it; until then they are the **runbook + automation skeletons**.
> Lane G owns this gate. **Never self-approve** — Lane A does not certify its own hardware.
>
> Grounded in contract `docs/engine/warmthkit-api-contract.md` and plan §8 (device
> matrix), §21.2 (CI split + self-hosted matrix), §19 (acceptance criteria). Hosted CI can
> never give us real displays or every macOS 26.x point release — that is *why* this lane
> exists (§21.2).

---

## 0. TL;DR

| | What |
|---|---|
| **Why a physical matrix** | Gamma breaks only on M5 Tahoe; DDC/overlay/HDR behavior is real-hardware-only; hosted runners have no displays and one OS build (§21.2). |
| **The split** | Hosted CI = lint/unit/`WarmthCore`/archive/sign-dry-run. Self-hosted = everything `HW`-tagged in `failure-injection-suite.md` + this matrix. |
| **Release gate** | A release tag is blocked until the **full matrix passes** on the current macOS 26.x build, including the 100-cycle reveal stuck-test and the <150 ms reveal-restore timing. |
| **Self-hosted runners** | Each matrix Mac runs a GitHub Actions self-hosted runner, labeled by SoC + attached panels; jobs target labels. |
| **Manual gate** | Fresh-user Gatekeeper first-launch + visual badge/tint checks that cannot be automated headlessly (§21.2 "manual fresh-user Gatekeeper gate"). |

---

## 1. The device matrix

Two SoC generations × a set of display archetypes. The SoC axis exists because **gamma is
silently broken on M5 Tahoe** and works on M3/M4 (plan §17, contract §4
`gammaBrokenOnThisOS`); the display axis exists because DDC capability and overlay coverage
differ wildly by panel.

| Machine (SoC / OS) | Role | Key thing it validates |
|---|---|---|
| **M5, macOS 26 Tahoe** | gamma-broken reference | Gamma classified `.unsupported(gammaBrokenOnThisOS)` and **default-OFF**; overlay is the actual default; no silent no-op (inv. 1, §4). |
| **M3 or M4, macOS 26** | gamma-works reference | Gamma path actually warms; gamma↔overlay parity; ColorSync re-baseline (S7). |
| **Apple display (Studio Display / Pro Display XDR / built-in)** | buttonless, no DDC color | Falls straight to overlay (`buttonlessAppleDisplay`, §4); badge says `Overlay`; never claims `Hardware`. |
| **Generic DDC monitor (e.g. Dell/LG with OSD)** | real hardware warmth | DDC capability probe (VCP 0x16 read), write-then-read verify, **opt-in** flow, restore tooling (S1/S2/S9). |
| **HDMI-on-Apple-Silicon / dock edge case** | the flaky transport | Transport classified correctly (§3 `DisplayTransport.hdmi`); DDC over HDMI/dock may be absent → overlay; wake-while-service-gone (S3). |

> **Procurement note (not a blocker):** the matrix degrades gracefully. If the Studio
> Display isn't on hand, the **buttonless-Apple** archetype is covered by the built-in
> panel of any matrix Mac; if a second identical monitor for the duplicate-twin test (S6)
> isn't available, S6's `UNIT`/`UNIT+FAKE` tiers still gate and only the `HW` confirm is
> deferred. Record any deferral explicitly in the gate report (`acceptance-gates.md`) — a
> deferred `HW` row is a known gap, not a silent pass.

### 1.1 What each cell runs (matrix × scenario)

| Scenario (from failure-injection-suite) | M5 Tahoe | M3/M4 | Apple display | Generic DDC | HDMI/dock |
|---|:--:|:--:|:--:|:--:|:--:|
| S1 crash-during-DDC-write | — | — | — | ✅ | ✅ (if DDC present) |
| S2 SIGKILL relaunch-recovery | ✅ | ✅ | ✅ (overlay) | ✅ (DDC) | ✅ |
| S3 wake / service gone | — | — | — | ✅ | ✅ (primary) |
| S4 hotplug during reveal | ✅ | ✅ | ✅ | ✅ | ✅ |
| S5 100-cycle reveal stuck-test | ✅ | ✅ | ✅ | ✅ | ✅ |
| S6 duplicate twins | — | — | — | ✅ (×2 panels) | — |
| S7 ColorSync change | — | ✅ (gamma) | — | ✅ | — |
| S8 Night Shift/TrueTone/HDR | ✅ (HDR) | ✅ | ✅ (TrueTone) | — | — |
| S9 competing apps | ✅ | ✅ | — | ✅ (primary) | — |
| Gamma classification (§4) | ✅ **must be OFF** | ✅ **must work** | n/a | n/a | n/a |

`✅` = run here; `—` = not meaningful on this archetype.

---

## 2. Per-cell validation procedures

Each procedure lists **automatable** steps (run by the self-hosted runner via
`xcodebuild test` with `HW`-tagged suites or a small driver CLI) and **manual** steps (a
human with a camera/eyes — the things no headless check can prove).

### 2.1 M5 Tahoe — gamma-broken reference (the headline machine)

**Automatable:**
1. Build + launch the engine harness; call `start()`; dump `state.displays`.
2. Assert the built-in display's `capabilities.gamma == .unsupported(gammaBrokenOnThisOS)`
   (contract §4) and `appliedMethod != .gamma`.
3. Force gamma via `setPreferredMethod(.gamma, for:)`, then assert the engine either
   refuses or self-demotes to overlay (it must **never** sit on a silently-broken layer —
   inv. 1). Read back `appliedMethod` → expect `.overlay`.

```bash
# self-hosted runner step (label: m5-tahoe)
xcodebuild test \
  -scheme WarmthKit-HW \
  -destination 'platform=macOS' \
  -only-testing:WarmthKitHWTests/GammaClassificationTests \
  RUNNER_DISPLAY_ARCHETYPE=builtin-m5 | tee gamma-m5.log
# Gate: GammaClassificationTests asserts gamma == .unsupported(gammaBrokenOnThisOS)
```

**Manual (camera/eyes — gamma silent-no-op can ONLY be seen):**
- Set max warmth. Photograph the screen. Confirm it is **visibly warm via overlay**, not
  unchanged. If a gamma-app-style "writes succeed, no visual change" occurs, the demotion
  logic failed — this is the exact bug Abendrot exists to route around (plan §2.1, §17).

### 2.2 M3/M4 — gamma-works reference

**Automatable:** assert `capabilities.gamma == .supported(())`; apply warmth via gamma;
run S7 (ColorSync change re-baseline). **Manual:** photograph gamma-warmed vs
overlay-warmed at the same target and confirm visual parity (no double-tint, no banding).

### 2.3 Apple display (buttonless) — overlay-only

**Automatable:** assert `capabilities.hardware == .unsupported(buttonlessAppleDisplay)`
(contract §4) and `appliedMethod == .overlay`; assert the badge string is `"Overlay"`
(contract §2 `DisplayMethod.badge`). **Manual:** confirm warmth is visible and the UI row
reads `Overlay`, never `Hardware` (inv. 8 honest badge; §0‑E2 "never market it as hardware").

### 2.4 Generic DDC monitor — real hardware warmth

**Automatable:**
1. Probe: assert `capabilities.hardware == .supported(DDCColorCaps(supportsRGBGain: true))`.
2. **Opt-in flow:** confirm DDC is OFF until `setHardwareDDCEnabled(true, for:)` (inv. 2,
   §21‑E3 — DDC is opt-in, not default).
3. Write warmth; verify-read VCP 0x16/0x18/0x1A back; assert applied ≈ target.
4. Run S1 (crash mid-write → relaunch restore) and S9 (contention) here.

```bash
# label: generic-ddc
xcodebuild test -scheme WarmthKit-HW -destination 'platform=macOS' \
  -only-testing:WarmthKitHWTests/DDCWriteVerifyTests \
  -only-testing:WarmthKitHWTests/DDCRecoveryTests \
  RUNNER_DISPLAY_ARCHETYPE=generic-ddc | tee ddc-generic.log
```

**Manual:** physically power-cycle the monitor mid-write (or pull the cable) to prove the
launch-time recovery restores native gain even when the engine never got an exit handler
(S1/S2 `HW` variant). Photograph before/after.

### 2.5 HDMI-on-AS / dock — the flaky transport

**Automatable:** assert `identity.transport == .hdmi` (or `.usbC`/`.thunderbolt` for the
dock); if DDC is absent over this path, assert clean fallback to overlay (no crash, typed
`.unsupported`). Run S3 (wake while service gone) as the primary here. **Manual:**
sleep/wake with the dock; unplug+replug during wake; confirm re-baseline and no stuck tint.

---

## 3. The two acceptance benchmarks that need a stopwatch + a loop

These come straight from §19 and §8 and are the hardest to fake — they need real timing
and real repetition on real hardware.

### 3.1 100-cycle Reveal stuck-test (§8 watchdog, §19 "zero stuck-suspended")

Drive `beginReveal()`/`endReveal()` 100 times, including adversarial cases that drop the
keyUp (Space switch), and assert warmth is **never** left suspended at the end of any cycle.

```swift
@Test("100 reveal cycles, including lost-keyUp, leave zero displays stuck-suspended")
func reveal_100Cycles_neverStuck() async throws {
    let engine = WarmthEngine.testHW()        // real backends on this matrix machine
    await engine.start()
    await engine.setWarmth(.init(strength: 0.8))

    for i in 0..<100 {
        await engine.beginReveal()
        #expect(await engine.state.isRevealing)
        if i % 7 == 0 {
            // Adversarial: simulate a swallowed keyUp (Space switch) → rely on the watchdog.
            await engine.simulateLostKeyUp()
            await engine.advanceWatchdogClock(by: .seconds(9))   // > 8s default
        } else {
            await engine.endReveal()
        }
        // INVARIANT after every cycle: warmth is restored, nothing stuck off.
        #expect(await engine.state.isRevealing == false)
        for d in await engine.state.displays {
            #expect(d.warmth.strength > 0, "display \(d.name) stuck-suspended at cycle \(i)")
        }
    }
}
```

> **Manual companion:** a human holds ⌥⌘T, switches Spaces / opens Mission Control / hits
> the login window, and confirms warmth always comes back — the watchdog path is hard to
> fully simulate because the OS event-swallowing is the thing under test.

### 3.2 Reveal-restore timing < 150 ms (§19, §4.2)

`endReveal()` must ease warmth back across all displays in ~100–150 ms. Measure the time
from `endReveal()` to the overlay reaching its target (drawn frame), not just the call
return.

```swift
@Test("endReveal eases warmth back in under 150ms across all displays")
func reveal_restoreUnder150ms() async throws {
    let engine = WarmthEngine.testHW()
    await engine.start()
    await engine.setWarmth(.init(strength: 0.8))
    await engine.beginReveal()

    let start = ContinuousClock.now
    await engine.endReveal()
    await engine.waitUntilWarmthSettled()        // resolves when every layer hit its target frame
    let elapsed = ContinuousClock.now - start
    #expect(elapsed < .milliseconds(150), "reveal restore took \(elapsed)")
}
```

> **Manual companion:** high-speed phone capture (240 fps) of the veil lift; confirm the
> ease-out feels physical (Emil-Kowalski-style, plan §4.2 / §21.3 spring) and there is no
> visible snap or stutter. This crosses into Lane B's motion polish but Lane G owns the
> *timing-budget* assertion.

### 3.3 Idle CPU/GPU ≈ 0% (§19, draw-on-change)

After warmth is applied and steady (no schedule transition, no reveal), the overlay must
draw on change only → ~0% idle GPU and negligible CPU.

```bash
# label: any matrix machine. Sample over a steady 60s window with NO interaction.
RUN_SECONDS=60
APP_PID=$(pgrep -x Abendrot)
# CPU: sample once/sec, assert median ~0%.
for i in $(seq $RUN_SECONDS); do ps -o %cpu= -p "$APP_PID"; sleep 1; done | tee idle-cpu.log
# GPU: powermetrics samples GPU active residency (needs sudo on the runner).
sudo powermetrics --samplers gpu_power -n 6 -i 10000 | tee idle-gpu.log
# Gate: median idle CPU < ~1%; GPU active residency near 0 over the window (no continuous redraw).
```

> The exact CPU/GPU numeric thresholds are tuned per matrix machine on first run and
> recorded in the gate report; the **shape** of the assertion (flat, near-zero, no
> continuous redraw) is the gate. A continuously-redrawing overlay is a regression even if
> the percentage looks small.

### 3.4 Gatekeeper first-launch (§19, §21.2 manual gate)

On a **fresh user account** (or a clean VM image of the matrix OS), the signed/notarized
build must pass Gatekeeper first-launch with no scary dialog beyond the standard one.

```bash
# label: clean-gatekeeper (a freshly-imaged or fresh-account machine)
spctl -a -vvv /Applications/Abendrot.app        # expect: accepted, source=Notarized Developer ID
codesign --verify --deep --strict --verbose=2 /Applications/Abendrot.app
xcrun stapler validate /Applications/Abendrot.app
```

> **Manual:** double-click the app as a never-before-seen user; confirm it launches and the
> overlay applies. In **Mode B** (unsigned local build, per `docs/release/RELEASE.md`),
> the expected path is right-click→Open / `xattr -dr com.apple.quarantine`; the *notarized*
> assertion above is the **Mode A** release gate. Record which mode the run was in.

---

## 4. Self-hosted runner plan (§21.2)

### 4.1 Topology

- Each physical matrix Mac runs **one GitHub Actions self-hosted runner**, registered to
  the repo, labeled by SoC + attached displays:
  - `self-hosted, macos-26, m5-tahoe, builtin, hdr`
  - `self-hosted, macos-26, m3, builtin, generic-ddc, gamma-works`
  - `self-hosted, macos-26, apple-display, buttonless`
  - `self-hosted, macos-26, generic-ddc, twin-pair` (the two-identical-monitor rig for S6)
  - `self-hosted, macos-26, hdmi, dock`
- A job that needs a specific archetype targets it with `runs-on: [self-hosted, m5-tahoe]`.
- Runners are **interactive-session** (logged-in UI agent), because overlay windows,
  Gatekeeper, and DDC all require a real user session — headless runners cannot host them
  (§21.2; also matches the DMG UI-runner constraint in `docs/release/RELEASE.md`).

### 4.2 CI split (mirrors §21.2)

```yaml
# .github/workflows/qa-matrix.yml  (SKELETON — Lane G + Lane E reconcile final form)
name: QA Matrix
on: [workflow_dispatch, release]

jobs:
  hosted-unit:                       # hosted, fast, every push — the HOSTED lane
    runs-on: macos-26                # GitHub-hosted
    steps:
      - uses: actions/checkout@v4
      - run: swift test --package-path WarmthKit \
               --filter 'WarmthCoreTests|EngineFakeTests'   # UNIT + UNIT+FAKE only
      # These are everything NON-HW from failure-injection-suite.md.

  hw-matrix:                         # self-hosted, gated to release / manual — the HARDWARE lane
    needs: hosted-unit
    strategy:
      fail-fast: false               # one bad panel must not hide the others
      matrix:
        include:
          - { runner: m5-tahoe,     suite: GammaClassificationTests,RevealStuckTests,SigkillRecoveryTests }
          - { runner: m3,           suite: GammaWorksTests,ColorSyncReBaselineTests,RevealStuckTests }
          - { runner: apple-display,suite: OverlayBadgeHonestyTests,RevealStuckTests }
          - { runner: generic-ddc,  suite: DDCWriteVerifyTests,DDCRecoveryTests,ContentionTests }
          - { runner: hdmi-dock,    suite: TransportClassifyTests,WakeServiceGoneTests }
    runs-on: [self-hosted, '${{ matrix.runner }}']
    steps:
      - uses: actions/checkout@v4
      - run: xcodebuild test -scheme WarmthKit-HW -destination 'platform=macOS' \
               $(echo '${{ matrix.suite }}' | tr ',' '\n' | sed 's/^/-only-testing:WarmthKitHWTests\//')
      - run: ./scripts/qa/idle-perf-sample.sh        # §3.3 idle CPU/GPU
      - uses: actions/upload-artifact@v4
        with: { name: 'hw-${{ matrix.runner }}-logs', path: '*.log' }

  manual-gate:                       # NOT auto — a human signs the fresh-user Gatekeeper check
    needs: hw-matrix
    runs-on: [self-hosted, clean-gatekeeper]
    environment: release-gate        # requires manual approval (the never-self-approve seam)
    steps:
      - run: ./scripts/qa/gatekeeper-check.sh        # §3.4
```

> **The "never self-approve" enforcement lives in the `environment: release-gate` manual
> approval.** Lane A (engine) cannot approve its own matrix run; a Lane G reviewer (or the
> founder) is the required approver on that GitHub environment. This is the gate, in code.

### 4.3 Recurring-regression job (§9 / §21.2 "per 26.x point release")

Because gamma broke on a *point release*, a scheduled job re-runs the M5 gamma
classification + a smoke of the matrix whenever the runner's OS updates, catching a
recurrence early rather than at the next release.

```yaml
  os-drift-watch:
    runs-on: [self-hosted, m5-tahoe]
    on:
      schedule: [{ cron: '0 8 * * 1' }]              # weekly; also trigger on OS update
    steps:
      - run: sw_vers -productVersion | tee os-build.txt
      - run: xcodebuild test -scheme WarmthKit-HW \
               -only-testing:WarmthKitHWTests/GammaClassificationTests
      # If gamma classification flips on a new 26.x, this fails LOUD before a release does.
```

---

## 5. Matrix → §19 acceptance traceability

| §19 acceptance criterion | Where verified in this matrix |
|---|---|
| Warmth on built-in + ≥2 external types incl. buttonless Apple (overlay) + DDC (hardware), on M5 Tahoe | §1 matrix cells; §2.1/§2.3/§2.4 |
| Correct method badge; never silently no-ops | §2.1 (gamma demote), §2.3 (overlay badge), §2.4 (hardware badge); inv. 1/8 |
| Reveal <150 ms restore; watchdog recovers lost keyUp; 0 stuck in 100-cycle | §3.1, §3.2 |
| Schedule follows Night Shift flip without altering it; degrades to solar | S8 + S10 (`failure-injection-suite.md`); spot-checked on any matrix Mac |
| Idle CPU/GPU ≈ 0% | §3.3 |
| Signed/notarized/stapled; clean Gatekeeper first-launch | §3.4 |
| Bundle < ~5 MB; RAM ~tens of MB | measured in §3.3 perf step (record bundle size + RSS) |

Every row here must be **green and evidenced** (fresh log/photo) before the gate in
`acceptance-gates.md` flips a release to releasable. Lane G holds the pen.
