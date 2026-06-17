# Abendrot — Failure-Injection & Persistence Test Suite (Lane G)

> **Status:** v0 test DESIGN, 2026-06-16. The engine (Lane A / `WarmthKit`) is still
> being built; everything here is **design + runnable skeletons as code blocks**, not
> live tests yet. Lane G is the **independent release gate** — it enforces
> "never self-approve." A scenario is *not* covered until Lane G has run it against the
> real engine and shown fresh output.
>
> Grounded in contract `docs/engine/warmthkit-api-contract.md` (§0 invariants, §6
> `WarmthEngine`, §9 safety guarantees) and plan `docs/abendrot-plan.md` §21.1‑E14, §8,
> §19. Where the contract and older plan prose disagree, **the contract + §21.1 win.**

---

## 0. How to read this suite

Each scenario gives: **Setup**, **Injection method**, **Expected recovery** (tied to a
specific contract guarantee), and a **Concrete assertion** (no vague "test that it
works"). Each is tagged with an execution tier:

| Tag | Where it runs | What it can prove |
|---|---|---|
| `UNIT` | `WarmthCore`, headless, hosted CI (§21.2 hosted lane) | pure state-machine / policy / math behavior — **no real display touched** |
| `UNIT+FAKE` | `WarmthKit` with an injected fake/mock `WarmthBackend` + fake clock | engine orchestration, recovery ordering, persistence round-trips — still headless |
| `HW` | self-hosted physical matrix (§21.2, see `hardware-matrix.md`) | the actual DDC/gamma/overlay side effect and its restore on real panels |

**Design rule for testability (Lane G ↔ Lane A contract ask):** the failure-injection
matrix is only automatable if the engine exposes seams. The contract already gives us
the seams that matter — `WarmthBackend` is a protocol (§5), capability results are typed
values (§4), identity is a value type (§3), and the watchdog *policy* lives in pure
`WarmthCore` (§1 module map). Lane G additionally **requests** (does not assume) these
test hooks from Lane A, none of which change the frozen public surface:

- A `FaultInjectingBackend` test double that can be told to throw at a chosen phase
  (pre-write / mid-write / post-write / on-reset) and to drop/delay I²C transactions.
- A `Clock`/`now` injection point so the watchdog and reveal-ease timing are
  deterministic (no real `sleep`).
- A pluggable **persistence store** (the EDID + native-gain snapshot of §9) so a test can
  pre-seed a "dirty" prior-run snapshot and assert launch-time recovery reads it.
- A way to enumerate a **fake display registry** (inject `DisplayIdentity` fixtures) so
  duplicate-monitor / hotplug bursts are reproducible headless.

If a seam is missing, the scenario degrades from `UNIT+FAKE` to `HW`-only — which is
slower, flakier, and not runnable in hosted CI. **Flag every such gap back to Lane A.**

---

## 1. The fault-injection harness (shared skeleton)

This is the test double every `UNIT+FAKE` scenario builds on. It conforms to the frozen
`WarmthBackend` protocol (contract §5) so the engine can't tell it from a real backend.

```swift
import Testing
import Foundation
@testable import WarmthKit          // or the relevant package module
@testable import WarmthCore

/// Where in the apply()/reset() lifecycle a fault fires.
enum FaultPhase: Sendable {
    case beforeApply        // throws before any side effect — engine must treat as "not applied"
    case midApply           // side effect partially committed (the dangerous DDC case)
    case afterApply         // side effect committed, then throws (verify-read failed)
    case onReset            // reset() itself fails — restore path must be resilient
}

/// A WarmthBackend that records every call and can be told to fail deterministically.
/// Also models a persistent "device state" so we can assert what was left on the panel.
actor FaultInjectingBackend: WarmthBackend {
    let method: DisplayMethod
    private(set) var applied: [DisplayIdentity: Kelvin] = [:]   // "what the panel shows now"
    private(set) var callLog: [String] = []
    var faultAt: FaultPhase?
    var dropTransaction = false      // simulate I²C write that never lands (mid-write power loss)

    init(method: DisplayMethod) { self.method = method }

    func classify(_ id: DisplayIdentity) async -> Capability<Void> { .supported(()) }

    func apply(_ kelvin: Kelvin, to id: DisplayIdentity) async throws {
        callLog.append("apply(\(kelvin.value),\(id.cgUUID))")
        if faultAt == .beforeApply { throw FaultError.injected(.beforeApply) }
        if faultAt == .midApply {
            // The panel is left in a HALF-WRITTEN state — this is the crux of crash-during-DDC.
            applied[id] = Kelvin((kelvin.value + Kelvin.neutral.value) / 2)
            throw FaultError.injected(.midApply)
        }
        if !dropTransaction { applied[id] = kelvin }
        if faultAt == .afterApply { throw FaultError.injected(.afterApply) }   // write OK, verify-read failed
    }

    func reset(_ id: DisplayIdentity) async throws {
        callLog.append("reset(\(id.cgUUID))")
        if faultAt == .onReset { throw FaultError.injected(.onReset) }
        applied[id] = .neutral
    }
}

enum FaultError: Error, Equatable { case injected(FaultPhase) }

extension FaultPhase: Equatable {}
```

> **Persistence double** (used by the SIGKILL / launch-recovery scenarios): a
> `FakeSnapshotStore` that the engine writes the EDID + native-gain snapshot into and
> reads on `start()`. A test pre-seeds it with a "dirty" snapshot (gain ≠ neutral) to
> simulate a prior run that crashed mid-warmth.

```swift
actor FakeSnapshotStore {
    struct Snapshot: Codable, Equatable { var nativeGain: [String: Int]; var leftDirty: Bool }
    var stored: Snapshot?
    func write(_ s: Snapshot) { stored = s }
    func read() -> Snapshot? { stored }
    func preseedDirty(uuid: String, gain: Int) { stored = .init(nativeGain: [uuid: gain], leftDirty: true) }
}
```

---

## 2. Scenarios

### S1 — Crash during a DDC write `UNIT+FAKE` + `HW`

The single most dangerous case: a DDC I²C write is interrupted, leaving the panel's RGB
gain in a non-neutral, non-target state. The panel does **not** restore itself.

- **Setup:** one DDC-capable display, hardware DDC opt-in enabled (contract §6
  `setHardwareDDCEnabled(true)`). Engine has previously persisted the native-state EDID
  snapshot (contract §9 "store last-known native DDC gain").
- **Injection method:**
  - `UNIT+FAKE`: `backend.faultAt = .midApply` so `apply()` commits a half-written gain
    then throws; then construct a **new** engine instance pointed at the same
    `FakeSnapshotStore` to simulate relaunch.
  - `HW`: drive a real DDC write and `kill -9` the process mid-`apply` (or pull a USB-C
    dock to sever the I²C bus mid-transaction). Confirm visually the panel is left tinted.
- **Expected recovery (contract §9 + invariant 7):** crash/exit handlers are **not**
  relied on for async DDC. On the **next `start()`**, launch-time stale-state recovery
  reads the persisted native snapshot and **restores the panel to its native gain before
  applying anything**. The badge/state must reflect a clean baseline, not the dirty
  intermediate.
- **Concrete assertion:**

```swift
@Test("Launch-time recovery restores native DDC gain after a mid-write crash")
func crashDuringDDCWrite_recoversOnRelaunch() async throws {
    let store = FakeSnapshotStore()
    let ddc = FaultInjectingBackend(method: .hardware)
    let display = DisplayIdentity.fixture(transport: .displayPort)

    // Run 1: persist native baseline, then crash mid-write.
    await store.write(.init(nativeGain: [display.cgUUID.uuidString: 6500], leftDirty: false))
    await ddc.setFault(.midApply)
    let engine1 = WarmthEngine.test(backends: [ddc], store: store, displays: [display])
    await engine1.start()
    await engine1.setHardwareDDCEnabled(true, for: display)
    try? await engine1.setWarmth(.init(strength: 0.8), for: display)   // throws mid-write internally
    let dirtyGain = await ddc.applied[display]
    #expect(dirtyGain != .neutral)                       // panel IS left dirty (precondition holds)

    // Run 2: brand-new engine, same store. start() must clean up BEFORE applying.
    let engine2 = WarmthEngine.test(backends: [ddc], store: store, displays: [display])
    await engine2.start()
    let recoveredGain = await ddc.applied[display]
    #expect(recoveredGain == .neutral)                   // restored to native baseline
    let resetIndex = await ddc.callLog.firstIndex(of: "reset(\(display.cgUUID))")
    let firstApplyIndex = await ddc.callLog.lastIndex(where: { $0.hasPrefix("apply") })
    #expect(resetIndex != nil)
    #expect(resetIndex! < (firstApplyIndex ?? .max))     // restore happened BEFORE any new apply
}
```

> `HW` variant assertion: after relaunch, read VCP 0x16/0x18/0x1A back via `ddcutil`/the
> engine's verify-read and assert each channel == the persisted native value (±0 codes),
> AND visually confirm no residual tint.

---

### S2 — SIGKILL (no chance to run any exit handler) `UNIT+FAKE` + `HW`

Like S1 but stronger: the process receives `SIGKILL`, so **no** `shutdown()`, no
`atexit`, no signal handler runs at all. This is the proof that recovery does not depend
on graceful teardown.

- **Setup:** warmth applied across built-in (overlay) + one DDC panel (hardware), schedule
  active. Native snapshot persisted.
- **Injection method:**
  - `UNIT+FAKE`: never call `shutdown()`; drop the engine instance and build a fresh one
    over the same persisted store with a `leftDirty: true` snapshot.
  - `HW`: `kill -KILL <pid>` while warmth is visibly applied. Then relaunch.
- **Expected recovery (contract §9 "Crash/exit handlers are not relied on", invariant 7):**
  on the next `start()`, every display is neutral-reset from the persisted snapshot via
  its layer *before* re-applying current settings. Overlay teardown is implicit (windows
  died with the process); DDC must be actively restored from snapshot.
- **Concrete assertion:**

```swift
@Test("SIGKILL leaves no display stuck-warm: relaunch restores from snapshot, no exit handler needed")
func sigkill_relaunchRestoresEveryLayer() async throws {
    let store = FakeSnapshotStore()
    await store.preseedDirty(uuid: ddcDisplay.cgUUID.uuidString, gain: 6500)  // prior run died dirty
    let ddc = FaultInjectingBackend(method: .hardware)
    await ddc.forceApplied(ddcDisplay, Kelvin(3000))   // simulate the stuck-warm panel

    let engine = WarmthEngine.test(backends: [ddc], store: store, displays: [ddcDisplay])
    await engine.start()                               // NO shutdown() ever called

    #expect(await ddc.applied[ddcDisplay] == .neutral) // recovered without any teardown hook
    let state = await engine.state
    #expect(state.displays.first?.lastError == nil)    // recovery is silent, not an error surfaced to user
}
```

> `HW` variant: a CI step that `kill -KILL`s the app, asserts the panel is visibly tinted
> via a reference photo, then relaunches and asserts the tint is gone within the launch
> window. This is a `requires-self-hosted-hardware` gate; it cannot run hosted.

---

### S3 — Wake while the display service is gone `UNIT+FAKE` + `HW`

System wakes from sleep but the external display's IOKit service / `DCPAVServiceProxy`
isn't back yet (common with docks/Thunderbolt). The engine must not crash, must not write
to a dead service, and must re-apply once the display reappears.

- **Setup:** built-in + one dock-attached DDC external, warmth active. Engine running.
- **Injection method:**
  - `UNIT+FAKE`: fire the reconfiguration callback with the external **absent**, then fire
    it again with the external **present** after a short delay. Backend `classify()`
    returns `.unknown(reason: .privateSymbolUnavailable)` (contract §4) for the window the
    service is missing.
  - `HW`: sleep the Mac, unplug+replug the dock during the wake transition.
- **Expected recovery (contract §9 "Hotplug / wake: debounced reconfiguration callback
  re-baselines identity + capabilities and re-applies"):** while the service is gone the
  display drops out of `state.displays` (or shows `.off` with a typed `.unknown` capability,
  never a crash); when it returns, identity is re-resolved by `cgUUID` (NOT a stale
  `currentDisplayID`, contract §3) and warmth is re-applied.
- **Concrete assertion:**

```swift
@Test("Wake with display service temporarily gone: no write to dead service, re-applies on return")
func wakeWhileServiceGone_reappliesWithoutWritingDeadService() async throws {
    let ddc = FaultInjectingBackend(method: .hardware)
    let engine = WarmthEngine.test(backends: [ddc], store: FakeSnapshotStore(), displays: [external])
    await engine.start()
    await engine.setWarmth(.init(strength: 0.7), for: external)
    let writesBefore = await ddc.callLog.filter { $0.hasPrefix("apply") }.count

    await engine.simulateReconfiguration(present: [])           // external vanished mid-wake
    let writesDuringGone = await ddc.callLog.filter { $0.hasPrefix("apply") }.count
    #expect(writesDuringGone == writesBefore)                   // ZERO writes to a dead service
    #expect(await engine.state.displays.contains { $0.id == external } == false)

    await engine.simulateReconfiguration(present: [external])   // service came back
    let s = await engine.state
    #expect(s.displays.first?.id == external)
    #expect(s.displays.first?.warmth.strength == 0.7)           // re-applied after re-baseline
}
```

---

### S4 — Hotplug during a reveal hold `UNIT+FAKE` + `HW`

A display is plugged/unplugged *while* Reveal True Color is held (warmth suspended). The
new display must come up at **true color** (not warm) to match the global reveal state,
and on `endReveal()` every display — including the newly-arrived one — must ease back to
its correct warmth.

- **Setup:** built-in + one external, schedule warm, reveal **held** (`beginReveal()` has
  run, `isRevealing == true`).
- **Injection method:**
  - `UNIT+FAKE`: `beginReveal()`, then `simulateReconfiguration(present: [+newExternal])`,
    then `endReveal()`.
  - `HW`: hold ⌥⌘T, hot-plug an external monitor, release.
- **Expected recovery (contract §6 reveal is "across ALL displays", invariant 1
  "engine never silently no-ops"):** the new display joins in the **revealed** state
  (warmth off) so it doesn't briefly flash warm against the others; on release it eases to
  its resolved warmth alongside the rest.
- **Concrete assertion:**

```swift
@Test("Display hot-plugged mid-reveal joins at true color, eases in on release")
func hotplugDuringReveal_newDisplayJoinsRevealed() async throws {
    let overlay = FaultInjectingBackend(method: .overlay)
    let engine = WarmthEngine.test(backends: [overlay], store: FakeSnapshotStore(), displays: [builtIn])
    await engine.start()
    await engine.setWarmth(.init(strength: 0.6))
    await engine.beginReveal()
    #expect(await engine.state.isRevealing)

    await engine.simulateReconfiguration(present: [builtIn, lateExternal])
    #expect(await overlay.applied[lateExternal] == .neutral)   // new display NOT warm during reveal

    await engine.endReveal()
    #expect(await engine.state.isRevealing == false)
    #expect(await overlay.applied[lateExternal] != .neutral)   // eases to warmth with the rest
}
```

---

### S5 — Lost keyUp across a Space switch (watchdog) `UNIT` + `UNIT+FAKE` + `HW`

The signature reliability guarantee. A Space/Mission-Control switch eats the hotkey
keyUp, so `endReveal()` is never delivered. Warmth must **not** stay stuck off — the
watchdog auto-resumes after the timeout.

- **Setup:** reveal mode `.hold`, watchdog timeout `.seconds(8)` (contract §8 default).
- **Injection method:**
  - `UNIT`: test the pure watchdog policy in `WarmthCore` directly (preferred — no engine,
    no clock flakiness). Feed it `keyDown` then advance a fake clock past the timeout with
    no `keyUp`.
  - `UNIT+FAKE`: `beginReveal()`, never call `endReveal()`, advance the injected clock past
    8 s, assert the engine auto-ran `endReveal()`.
  - `HW`: hold ⌥⌘T, switch Spaces (swallows keyUp), wait, confirm warmth returns. This is
    **the 100-cycle stuck-test** (contract §8, plan §19 acceptance) — see `hardware-matrix.md`.
- **Expected recovery (contract §8 watchdog "guarantees warmth is never stuck-suspended",
  plan §19 "zero stuck-suspended in a 100-cycle test"):** after `watchdogTimeout`, warmth
  resumes exactly as if `endReveal()` had been called.
- **Concrete assertion (pure-core, deterministic):**

```swift
@Test("Watchdog resumes warmth when keyUp is lost (no real time elapses)")
func watchdog_resumesAfterTimeoutWithoutKeyUp() {
    var clock = FakeClock(now: .zero)
    var watchdog = RevealWatchdog(timeout: .seconds(8), clock: clock)
    watchdog.keyDown()                       // reveal begins
    #expect(watchdog.shouldResume() == false)
    clock.advance(by: .seconds(7))
    #expect(watchdog.shouldResume() == false)   // not yet
    clock.advance(by: .seconds(2))              // total 9s > 8s, no keyUp ever arrived
    #expect(watchdog.shouldResume() == true)    // auto-resume fires
}

@Test("A keyUp before the timeout cancels the watchdog (normal release path)")
func watchdog_keyUpCancelsAutoResume() {
    var clock = FakeClock(now: .zero)
    var watchdog = RevealWatchdog(timeout: .seconds(8), clock: clock)
    watchdog.keyDown()
    clock.advance(by: .seconds(3))
    watchdog.keyUp()                         // user released normally
    clock.advance(by: .seconds(10))
    #expect(watchdog.shouldResume() == false)   // watchdog did NOT double-fire
}
```

> **Adversarial note:** also assert the watchdog does not fire on a *toggle*-mode reveal
> (contract §8 `RevealMode.toggle`), where there is no key-up to lose — a watchdog that
> force-resumes a deliberate toggle would be a regression.

---

### S6 — Duplicate identical monitors `UNIT` + `UNIT+FAKE` + `HW`

Two physically identical monitors (same vendor/product, possibly same or absent serial).
Per-display state must **not** collapse onto one identity — warming display A must not warm
display B, and B's badge/warmth are independent.

- **Setup:** two `DisplayIdentity` fixtures with identical `EDIDFingerprint.vendorID` /
  `productID`, differing only by `cgUUID` (and `ioRegistryPath` / `serial` if present).
- **Injection method:**
  - `UNIT`: construct the two identities and exercise `DisplayIdentity` equality/hashing
    directly (contract §3 "Equality / hashing use cgUUID (+ edid to disambiguate identical
    twin monitors); the transient fields are excluded").
  - `UNIT+FAKE`: set warmth on A only; assert B unchanged.
  - `HW`: two identical panels on the bench; warm one, observe only it changes.
- **Expected recovery (contract §3, invariant 5 "Stable identity, never raw displayID"):**
  the two are distinct keys; transient fields (`currentDisplayID`, `frame`, `backingScale`)
  never participate in equality, so a hotplug that swaps their `displayID`s doesn't swap
  their state.
- **Concrete assertion:**

```swift
@Test("Identical twin monitors are distinct identities; transient fields don't affect equality")
func duplicateMonitors_remainDistinctAcrossDisplayIDSwap() {
    let edid = EDIDFingerprint(vendorID: 0x1E6D, productID: 0x5B11, serial: nil, displayName: "LG UltraFine")
    var a = DisplayIdentity.fixture(cgUUID: UUID(), edid: edid, displayID: 2)
    var b = DisplayIdentity.fixture(cgUUID: UUID(), edid: edid, displayID: 3)
    #expect(a != b)                          // same EDID, different cgUUID → different displays
    #expect(a.hashValue != b.hashValue || a != b)

    // Hotplug swaps the transient currentDisplayID — identity must NOT change.
    let aBefore = a
    a.currentDisplayID = 99; a.frame = .init(x: 1, y: 1, width: 1, height: 1); a.backingScale = 3
    #expect(a == aBefore)                    // transient changes are equality-invisible
    #expect(a != b)                          // still not B
}

@Test("Warming one twin does not warm the other")
func duplicateMonitors_independentWarmth() async throws {
    let overlay = FaultInjectingBackend(method: .overlay)
    let engine = WarmthEngine.test(backends: [overlay], store: FakeSnapshotStore(), displays: [twinA, twinB])
    await engine.start()
    await engine.setWarmth(.init(strength: 0.9), for: twinA)
    #expect(await overlay.applied[twinA] != .neutral)
    #expect(await overlay.applied[twinB] == .neutral)   // B untouched
}
```

---

### S7 — ColorSync / ICC profile changes underneath us `UNIT+FAKE` + `HW`

The user (or another app, or Display calibration) changes a display's ColorSync/ICC
profile while warmth is applied. For the **gamma** layer this can silently clobber the
transfer table; the engine must re-baseline rather than leave a stale or doubled tint.

- **Setup:** a gamma-capable display (M3/M4, gamma works) with warmth applied via the
  gamma layer; OR any display where ColorSync re-baseline matters.
- **Injection method:**
  - `UNIT+FAKE`: fire the ColorSync/display-profile change notification (modeled through
    the same `simulateReconfiguration` debounce path, contract §3 reconfiguration bursts).
  - `HW`: in System Settings → Displays → Color, switch the profile while warm.
- **Expected recovery (contract §3 debounced re-baseline + §5 GammaBackend "reset via
  `CGDisplayRestoreColorSyncSettings`"):** the engine re-reads native state and re-applies
  its own warmth on top of the *new* baseline — no compounding, no residual after
  `restoreAllDisplays()`.
- **Concrete assertion:**

```swift
@Test("ColorSync profile change re-baselines gamma without compounding warmth")
func colorSyncChange_reBaselinesNotCompounds() async throws {
    let gamma = FaultInjectingBackend(method: .gamma)
    let engine = WarmthEngine.test(backends: [gamma], store: FakeSnapshotStore(), displays: [gammaDisplay])
    await engine.start()
    await engine.setWarmth(.init(strength: 0.5), for: gammaDisplay)
    let afterFirst = await gamma.applied[gammaDisplay]

    await engine.simulateColorSyncChange(for: gammaDisplay)   // profile swapped underneath
    let afterReBaseline = await gamma.applied[gammaDisplay]
    #expect(afterReBaseline == afterFirst)                    // same target, NOT doubled

    await engine.restoreAllDisplays()
    #expect(await gamma.applied[gammaDisplay] == .neutral)     // clean restore, no residue
}
```

---

### S8 — Night Shift / True Tone / HDR active `UNIT+FAKE` + `HW`

System Night Shift, True Tone, and/or HDR/EDR content are on at the same time as
Abendrot. The engine **reads** Night Shift (never writes — contract §7), must not fight
True Tone, and must respect the overlay's documented HDR/EDR limits (contract §5 / §0‑E2).

- **Setup:** schedule mode `.followSystemNightShift` (contract §7); a display with True
  Tone; an HDR/EDR video playing.
- **Injection method:**
  - `UNIT+FAKE`: drive a fake `SystemNightShiftStateFollower` that flips its `active`
    boolean; assert the engine follows without ever calling a write API (there is none in
    the contract — assert it stays read-only by checking no Night-Shift mutation seam is
    invoked).
  - `HW`: toggle Night Shift in System Settings; confirm Abendrot's `isScheduleActiveNow`
    tracks it and the user's Night Shift setting is **unchanged** afterward.
- **Expected recovery (contract §7 "never writes Night Shift", §0 invariant 8 honest
  badges, §5 overlay HDR limit):** Abendrot follows the Night Shift `active` flip;
  the user's Night Shift configuration is untouched; on an HDR/EDR surface the overlay
  badge stays `Overlay` and the UI never claims hardware-accurate coverage.
- **Concrete assertion:**

```swift
@Test("Follows Night Shift active flip without writing the user's Night Shift setting")
func nightShiftFollow_isReadOnly() async throws {
    let follower = FakeNightShiftFollower(active: false)
    let engine = WarmthEngine.test(nightShift: follower, displays: [builtIn])
    await engine.start()
    await engine.setScheduleMode(.followSystemNightShift)
    #expect(await engine.state.isScheduleActiveNow == false)

    await follower.setActive(true)                  // system Night Shift turned on
    await engine.tickSchedule()
    #expect(await engine.state.isScheduleActiveNow == true)   // we followed it
    #expect(await follower.writeCount == 0)         // we NEVER wrote Night Shift (read-only contract §7)
}

@Test("HDR/EDR display keeps the Overlay badge — never falsely claims hardware")
func hdrDisplay_badgeStaysHonest() async throws {
    let engine = WarmthEngine.test(backends: [FaultInjectingBackend(method: .overlay)], displays: [hdrDisplay])
    await engine.start()
    let ds = await engine.state.displays.first
    #expect(ds?.appliedMethod == .overlay)
    #expect(ds?.appliedMethod.badge == "Overlay")   // §0‑E2: never marketed as hardware
}
```

> **Degradation path (contract §7):** also assert that when the Night Shift private symbol
> is unavailable (`dlsym` null), the engine reports `.unknown(privateSymbolUnavailable)`
> and degrades to `.solar` — see S10 (kill switch) which shares this machinery.

---

### S9 — Competing apps (f.lux / Lunar / BetterDisplay / MonitorControl) `UNIT+FAKE` + `HW`

Another warmth/DDC tool is running and also writing gamma or DDC gain. Two failure shapes:
(a) **gamma war** — another app keeps resetting the transfer table; (b) **DDC contention**
— another app holds/writes the I²C bus, causing our write-then-read verify to mismatch.

- **Setup:** Abendrot active on a DDC panel; a competing app (e.g. MonitorControl) also
  driving that panel.
- **Injection method:**
  - `UNIT+FAKE`: a `CompetingWriterBackend` that mutates the fake panel's `applied` value
    out from under the engine between our `apply()` and our verify-read; and one that resets
    gamma on a timer.
  - `HW`: run MonitorControl / f.lux / Lunar / BetterDisplay concurrently on the matrix
    machines (see `hardware-matrix.md` — this is `requires-self-hosted-hardware`).
- **Expected recovery (contract §5 DDC "write-then-read verify" + rate-limit/backoff;
  invariant 1 never silently no-op; invariant 8 honest badge):** on a verify mismatch the
  engine does **not** spin in a write war — it backs off, surfaces a non-fatal
  `lastError` (contract §6 `DisplayState.lastError`, "surfaced quietly in advanced mode"),
  and the badge reflects reality (it must not claim `Hardware` if it can't hold the panel).
- **Concrete assertion:**

```swift
@Test("DDC verify-mismatch under contention backs off and surfaces a non-fatal error, no write war")
func ddcContention_backsOffAndReports() async throws {
    let ddc = ContendedDDCBackend(method: .hardware)     // mutates value after our write
    await ddc.enableContention(true)
    let engine = WarmthEngine.test(backends: [ddc], store: FakeSnapshotStore(), displays: [external])
    await engine.start()
    await engine.setHardwareDDCEnabled(true, for: external)
    await engine.setWarmth(.init(strength: 0.7), for: external)

    let writes = await ddc.writeCount
    #expect(writes <= ddc.backoffCeiling)                // bounded retries, NOT an infinite write war
    let ds = await engine.state.displays.first
    #expect(ds?.lastError != nil)                        // non-fatal error surfaced, not a crash
    #expect(ds?.appliedMethod != .hardware)              // badge is honest: we couldn't hold it
}
```

> **Coexistence detection (plan §18 v1.0):** a softer `UNIT` assertion can check that the
> engine *detects* a known competing bundle ID is running and records it — but the
> hard behavioral guarantee (no write war, honest badge) is the one that ships the gate.

---

### S10 — Private-API kill switch / OS denylist `UNIT` + `UNIT+FAKE`

The kill switch (contract §6 `setPrivateAPIsEnabled(false)`, invariant 6, §21‑E5) and the
construction-time OS denylist must drop **all** private-API paths (DDC + Night Shift) and
run overlay-only — with state reflecting it. This is partly headless and is the cheapest,
highest-value gate (it protects against OS-build breakage).

- **Setup:** an engine with DDC + Night Shift backends available.
- **Injection method:**
  - `UNIT+FAKE`: call `setPrivateAPIsEnabled(false)` at runtime; separately, construct with
    `EngineConfiguration(startWithPrivateAPIsEnabled: false)` (denylist path).
  - Also: a fake `dlsym` returning null → backend `classify()` yields
    `.unknown(reason: .privateSymbolUnavailable)` (contract §4).
- **Expected recovery (contract §9 kill switch, §7 degrade-to-solar):** DDC + Night Shift
  go inert; every display falls to `overlay`; `state.privateAPIsEnabled == false`; schedule
  follow degrades to `.solar`.
- **Concrete assertion:**

```swift
@Test("Kill switch drops DDC + Night Shift to overlay-only and reflects it in state")
func killSwitch_fallsBackToOverlayOnly() async throws {
    let ddc = FaultInjectingBackend(method: .hardware)
    let overlay = FaultInjectingBackend(method: .overlay)
    let engine = WarmthEngine.test(backends: [ddc, overlay], displays: [external])
    await engine.start()
    await engine.setHardwareDDCEnabled(true, for: external)
    await engine.setWarmth(.init(strength: 0.8), for: external)
    #expect(await engine.state.displays.first?.appliedMethod == .hardware)

    await engine.setPrivateAPIsEnabled(false)            // KILL SWITCH
    let s = await engine.state
    #expect(s.privateAPIsEnabled == false)
    #expect(s.displays.first?.appliedMethod == .overlay) // dropped to the safe universal layer
    #expect(await ddc.applied[external] == .neutral)     // DDC actively restored on the way down
}

@Test("Construction-time OS denylist starts overlay-only, schedule degrades to solar")
func osDenylist_startsOverlayOnlyAndSolar() async throws {
    let engine = WarmthEngine.test(
        config: EngineConfiguration(startWithPrivateAPIsEnabled: false,
                                    defaultScheduleMode: .followSystemNightShift),
        displays: [builtIn])
    await engine.start()
    #expect(await engine.state.privateAPIsEnabled == false)
    if case .solar = await engine.state.scheduleMode {} else { Issue.record("did not degrade to .solar") }
}
```

---

### S11 — `restoreAllDisplays()` is the unconditional escape hatch `UNIT+FAKE` + `HW`

The emergency menu command (contract §6, invariant 7) must restore **every** known display
across **every** active layer, and must succeed even when one layer's `reset()` throws —
a failure on one display must not abort restoration of the others.

- **Setup:** three displays on three layers (overlay / gamma / hardware), all warm; arm one
  backend's `reset()` to throw.
- **Injection method:** `backend.faultAt = .onReset` on exactly one layer, then call
  `restoreAllDisplays()`.
- **Expected recovery (contract §6 "Always available" + invariant 7):** the other two are
  restored to neutral; the failing one surfaces a `lastError` but does not prevent the rest;
  no exception escapes `restoreAllDisplays()` (it is the safety floor — it must not throw).
- **Concrete assertion:**

```swift
@Test("restoreAllDisplays restores every healthy display even when one layer's reset throws")
func restoreAll_isResilientToOneFailingLayer() async {
    let overlay = FaultInjectingBackend(method: .overlay)
    let gamma   = FaultInjectingBackend(method: .gamma)
    let ddc     = FaultInjectingBackend(method: .hardware)
    await gamma.setFault(.onReset)                       // gamma reset will throw
    let engine = WarmthEngine.test(backends: [overlay, gamma, ddc],
                                   displays: [dOverlay, dGamma, dDDC])
    await engine.start()
    await engine.setWarmth(.init(strength: 0.9))         // warm everything

    await engine.restoreAllDisplays()                    // MUST NOT throw — it's the safety floor
    #expect(await overlay.applied[dOverlay] == .neutral) // healthy layers restored
    #expect(await ddc.applied[dDDC] == .neutral)
    let gammaState = await engine.state.displays.first { $0.id == dGamma }
    #expect(gammaState?.lastError != nil)                // failing layer reports, doesn't abort the rest
}
```

---

## 3. Coverage map (scenario → contract guarantee → tier)

| # | Scenario | Contract guarantee enforced | Tier |
|---|---|---|---|
| S1 | Crash during DDC write | §9 launch-time stale-state recovery; inv. 7 | `UNIT+FAKE` + `HW` |
| S2 | SIGKILL | §9 "exit handlers not relied on"; inv. 7 | `UNIT+FAKE` + `HW` |
| S3 | Wake, display service gone | §9 hotplug/wake re-baseline; §3 identity | `UNIT+FAKE` + `HW` |
| S4 | Hotplug during reveal hold | §6 reveal across ALL displays; inv. 1 | `UNIT+FAKE` + `HW` |
| S5 | Lost keyUp across Space | §8 watchdog; §19 100-cycle stuck-test | `UNIT` + `UNIT+FAKE` + `HW` |
| S6 | Duplicate identical monitors | §3 identity equality; inv. 5 | `UNIT` + `UNIT+FAKE` + `HW` |
| S7 | ColorSync profile change | §3 re-baseline; §5 gamma reset | `UNIT+FAKE` + `HW` |
| S8 | Night Shift / True Tone / HDR | §7 read-only; §5/§0‑E2 overlay limits | `UNIT+FAKE` + `HW` |
| S9 | Competing apps | §5 verify+backoff; inv. 1/8; §6 lastError | `UNIT+FAKE` + `HW` |
| S10 | Kill switch / OS denylist | §9 kill switch; §7 solar degrade; inv. 6 | `UNIT` + `UNIT+FAKE` |
| S11 | restoreAllDisplays resilience | §6 always-available; inv. 7 | `UNIT+FAKE` + `HW` |

**Gate rule:** a release cannot ship until **every `UNIT`/`UNIT+FAKE` row is green in
hosted CI** and **every `HW` row is green on the self-hosted matrix** (see
`acceptance-gates.md`). Lane G runs this; Lane A does not self-certify it.
