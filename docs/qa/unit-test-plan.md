# Abendrot — WarmthCore Unit Test Plan (Lane G)

> **Status:** v0 test DESIGN, 2026-06-16. `WarmthCore` (the pure domain module) does not
> exist yet; these are the **proposed Swift Testing cases as code blocks** plus a coverage
> checklist. They become live tests once Lane A ships `WarmthCore`. Lane G owns this gate.
>
> Grounded in contract `docs/engine/warmthkit-api-contract.md` §1 (module map — `WarmthCore`
> is "pure domain … value types, Kelvin↔gain math, schedule logic, state-machine reducer,
> capability/identity *types*, watchdog policy"), §2, §3, §8; plan §8, §19.

---

## 0. Why `WarmthCore` is the most-tested module

The contract (§1) makes `WarmthCore` **pure** — it knows nothing of AppKit/IOKit and has no
side effects. That is the whole point for QA: every behavior here is **deterministic,
headless, fast, and hosted-CI-runnable** (no displays, no permissions, no private symbols).
Per plan §8 the Kelvin↔gain math is "the most-tested unit." These tests are the cheapest
defense and run on **every push** in the hosted lane (§21.2).

Framework: **Swift Testing** (`import Testing`, `@Test`, `#expect`/`Issue.record`) on
Xcode 26 / Swift 6 strict concurrency — matching the contract's compile gate. (`XCTest` per
plan §8 is acceptable; Swift Testing is the modern default on this SDK. Lane A picks; Lane G
matches whatever Lane A's existing `WarmthCore` tests use — match-existing-patterns rule.)

---

## 1. Coverage checklist (each item → a `@Test` below)

### 1.1 Kelvin ↔ gain math (contract §2, plan §8 "most-tested")
- [ ] `Kelvin.init` clamps to `[1000, 6500]` (contract §2 `min(6500, max(1000, …))`).
- [ ] `Kelvin.neutral == 6500`, `Kelvin.warmestSupported == 1900`.
- [ ] `Kelvin` `Comparable` orders by value; `Hashable`/`Codable` round-trip.
- [ ] `WarmthLevel.init` clamps `strength` to `[0, 1]`.
- [ ] `WarmthLevel.off.strength == 0`.
- [ ] `WarmthLevel.kelvin(warmestPoint:)` endpoints: `strength 0 → neutral (6500)`,
      `strength 1 → warmestPoint`.
- [ ] `kelvin(warmestPoint:)` is **monotonic** — more strength is never *less* warm
      (never a higher Kelvin).
- [ ] Kelvin→RGB-gain mapping is monotonic per channel (warmer ⇒ blue gain ↓, never ↑) and
      neutral (6500K) maps to unity gain on all channels (the internal blackbody approx —
      tested behaviorally, not by its constants, contract §2 note).
- [ ] Gain values stay in the valid output range (no channel < 0 or > 1.0 for the overlay
      multiply; DDC gain stays within VCP code bounds).

### 1.2 Schedule resolver (contract §2 `ScheduleMode`/`CustomSchedule`, §7)
- [ ] `.off` → never active.
- [ ] `.alwaysOn` → always active.
- [ ] `.custom` simple window (e.g. 20:00→23:00) → active inside, inactive outside.
- [ ] `.custom` **midnight-wrap** window (e.g. 22:00→06:00) → active at 23:00 **and** 02:00,
      inactive at noon. (This is the classic off-by-one bug — explicit case.)
- [ ] `.custom` boundary semantics are defined and tested (is `end` inclusive/exclusive?
      pick one, assert it, document it).
- [ ] `.custom` zero-width / degenerate window (start == end) has defined behavior.
- [ ] `.solar` → active between computed sunset and sunrise for a known lat/long + date;
      a fixed fixture (e.g. a solstice at a known location) pins the math.
- [ ] `.solar` polar edge cases (high latitude, sun never sets / never rises) don't crash and
      have defined behavior.
- [ ] `.followSystemNightShift` resolution **degrades to `.solar`** when the follower reports
      unavailable (contract §7) — tested at the resolver level with an injected "unavailable".
- [ ] Schedule resolution is a **pure function of (mode, now, location)** — same inputs ⇒ same
      output, no wall-clock dependency (uses injected `now`).

### 1.3 `DisplayIdentity` equality/hashing (contract §3)
- [ ] Equality uses `cgUUID` (+ `edid`); two identities with same `cgUUID` are equal.
- [ ] Transient fields (`currentDisplayID`, `frame`, `backingScale`) are **excluded** from
      equality and hashing — mutating them does not change identity (S6 precondition).
- [ ] Identical-twin monitors (same EDID, different `cgUUID`) are **not** equal.
- [ ] `Hashable` contract holds: equal values ⇒ equal hashes; used correctly as a `Dictionary`
      key across a transient-field mutation.
- [ ] `EDIDFingerprint` `serial` is present in the type but **redaction** is the caller's job;
      `Codable` round-trips (and a redaction helper, if in core, strips serial — see §1.5).

### 1.4 Watchdog policy (contract §8, plan §19)
- [ ] keyDown then timeout elapses with no keyUp ⇒ `shouldResume() == true`.
- [ ] keyDown then keyUp before timeout ⇒ never resumes (no double-fire).
- [ ] Exactly-at-timeout boundary behavior is defined (`>=` vs `>`), asserted.
- [ ] Default timeout is `.seconds(8)` (contract §8); configurable.
- [ ] Watchdog does **not** auto-resume in `.toggle` mode (no keyUp to lose) — S5 adversarial.
- [ ] Re-arm: a second keyDown after a resume starts a fresh timeout window.
- [ ] Pure: driven by an injected clock, never real `sleep` (deterministic).

### 1.5 State-machine reducer / misc core (contract §1, §6 state types)
- [ ] The pure reducer maps (state, event) → state deterministically (enable/disable,
      setWarmth, beginReveal/endReveal flags, schedule-active flip) without side effects.
- [ ] `WarmthState`/`DisplayState` `Equatable` is correct (used to dedupe `stateUpdates()`
      emissions — contract §6 "emits on every meaningful state change", so equal states
      should not spuriously emit).
- [ ] `DisplayMethod.badge` strings exactly match the contract (`"Hardware"`, `"Gamma"`,
      `"Overlay"`, `"Off"`) — these are user-visible and a differentiator (inv. 8).
- [ ] Redaction helper (if in core): never emits `serial` / precise identifiers (contract §3,
      plan §11) — assert a log/analytics projection of an identity contains no serial.

---

## 2. Proposed Swift Testing cases

### 2.1 Kelvin ↔ gain math

```swift
import Testing
@testable import WarmthCore

@Suite("Kelvin & WarmthLevel math")
struct KelvinMathTests {

    @Test("Kelvin clamps to the supported range")
    func kelvinClamps() {
        #expect(Kelvin(50_000).value == 6500)     // clamp high
        #expect(Kelvin(10).value == 1000)         // clamp low
        #expect(Kelvin.neutral.value == 6500)
        #expect(Kelvin.warmestSupported.value == 1900)
    }

    @Test("Kelvin is ordered by value")
    func kelvinComparable() {
        #expect(Kelvin(2700) < Kelvin(6500))
        #expect(!(Kelvin(6500) < Kelvin(2700)))
    }

    @Test("WarmthLevel strength clamps to 0...1")
    func warmthClamps() {
        #expect(WarmthLevel(strength: -3).strength == 0)
        #expect(WarmthLevel(strength: 9).strength == 1)
        #expect(WarmthLevel.off.strength == 0)
    }

    @Test("strength endpoints map to neutral and the warmest point")
    func strengthEndpoints() {
        let warmest = Kelvin(2700)
        #expect(WarmthLevel(strength: 0).kelvin(warmestPoint: warmest) == .neutral)
        #expect(WarmthLevel(strength: 1).kelvin(warmestPoint: warmest) == warmest)
    }

    @Test("warmth is monotonic: more strength is never less warm", arguments: [
        (0.0, 0.25), (0.25, 0.5), (0.5, 0.75), (0.75, 1.0)
    ])
    func warmthMonotonic(lower: Double, higher: Double) {
        let warmest = Kelvin(2700)
        let k1 = WarmthLevel(strength: lower).kelvin(warmestPoint: warmest).value
        let k2 = WarmthLevel(strength: higher).kelvin(warmestPoint: warmest).value
        #expect(k2 <= k1)     // higher strength ⇒ lower-or-equal Kelvin (warmer)
    }

    @Test("neutral maps to unity per-channel gain; warming only reduces blue")
    func gainNeutralAndMonotonic() {
        let neutral = WarmthCore.rgbGain(for: .neutral)          // proposed pure fn
        #expect(approxEqual(neutral.r, 1.0) && approxEqual(neutral.g, 1.0) && approxEqual(neutral.b, 1.0))
        let warm = WarmthCore.rgbGain(for: Kelvin(2700))
        #expect(warm.b < neutral.b)        // blue is attenuated when warm
        #expect(warm.r >= neutral.r * 0.999)   // red not attenuated below neutral
        #expect((0...1).contains(warm.b) && (0...1).contains(warm.g))   // in range
    }
}
```

### 2.2 Schedule resolver (midnight wrap + solar)

```swift
import Testing
import Foundation
@testable import WarmthCore

@Suite("Schedule resolution")
struct ScheduleResolverTests {

    // Helper: build a local Date at H:M for a fixed reference day, in a fixed timezone.
    func at(_ h: Int, _ m: Int = 0) -> Date { TestCalendar.fixedDay(hour: h, minute: m) }

    @Test("alwaysOn and off are unconditional")
    func unconditionalModes() {
        #expect(ScheduleResolver.isActive(.alwaysOn, at: at(3)) == true)
        #expect(ScheduleResolver.isActive(.off, at: at(21)) == false)
    }

    @Test("custom window without wrap")
    func customNoWrap() {
        let s = CustomSchedule(start: dc(20, 0), end: dc(23, 0), warmest: .init(strength: 1))
        #expect(ScheduleResolver.isActive(.custom(s), at: at(21, 30)) == true)
        #expect(ScheduleResolver.isActive(.custom(s), at: at(12, 0)) == false)
    }

    @Test("custom window that wraps past midnight is active on BOTH sides of midnight")
    func customMidnightWrap() {
        let s = CustomSchedule(start: dc(22, 0), end: dc(6, 0), warmest: .init(strength: 1))
        #expect(ScheduleResolver.isActive(.custom(s), at: at(23, 0)) == true)   // before midnight
        #expect(ScheduleResolver.isActive(.custom(s), at: at(2, 0))  == true)   // after midnight
        #expect(ScheduleResolver.isActive(.custom(s), at: at(12, 0)) == false)  // midday
        #expect(ScheduleResolver.isActive(.custom(s), at: at(6, 0))  == false)  // exactly end (exclusive — documented)
    }

    @Test("solar window is active between sunset and sunrise for a fixed fixture")
    func solarKnownFixture() {
        // Fixed location + date with KNOWN sunrise/sunset (e.g. London, summer solstice).
        let mode = ScheduleMode.solar(latitude: 51.5074, longitude: -0.1278)
        let date = TestCalendar.date(year: 2026, month: 6, day: 21, hour: 23, minute: 0) // after sunset
        #expect(ScheduleResolver.isActive(mode, at: date, calendar: TestCalendar.london) == true)
        let noon = TestCalendar.date(year: 2026, month: 6, day: 21, hour: 13, minute: 0)
        #expect(ScheduleResolver.isActive(mode, at: noon, calendar: TestCalendar.london) == false)
    }

    @Test("solar handles a polar 'sun never sets' day without crashing")
    func solarPolarEdge() {
        let mode = ScheduleMode.solar(latitude: 78.0, longitude: 15.0)   // Svalbard, midsummer
        let date = TestCalendar.date(year: 2026, month: 6, day: 21, hour: 2, minute: 0)
        // Defined behavior (e.g. inactive because the sun is up); the point is: no crash, deterministic.
        _ = ScheduleResolver.isActive(mode, at: date, calendar: TestCalendar.utc)
    }

    @Test("followSystemNightShift degrades to solar when the follower is unavailable")
    func followDegradesToSolar() {
        let resolved = ScheduleResolver.resolveFollowMode(
            nightShift: .unavailable,                    // private symbol missing (§7)
            fallback: .solar(latitude: 51.5, longitude: -0.1))
        if case .solar = resolved {} else { Issue.record("did not degrade to .solar") }
    }

    @Test("resolution is pure: identical inputs give identical output")
    func resolutionIsPure() {
        let s = CustomSchedule(start: dc(22, 0), end: dc(6, 0), warmest: .init(strength: 1))
        let t = at(23, 30)
        #expect(ScheduleResolver.isActive(.custom(s), at: t) ==
                ScheduleResolver.isActive(.custom(s), at: t))
    }
}
```

### 2.3 DisplayIdentity equality (ignoring transient fields)

```swift
import Testing
import CoreGraphics
@testable import WarmthCore

@Suite("DisplayIdentity equality & hashing")
struct DisplayIdentityTests {

    @Test("equality keys on cgUUID, ignores transient currentDisplayID/frame/scale")
    func ignoresTransientFields() {
        let uuid = UUID()
        var a = DisplayIdentity.fixture(cgUUID: uuid, displayID: 1, frame: .zero, scale: 2)
        let b = DisplayIdentity.fixture(cgUUID: uuid, displayID: 1, frame: .zero, scale: 2)
        #expect(a == b)
        a.currentDisplayID = 777                       // hotplug reassigned the displayID
        a.frame = CGRect(x: 9, y: 9, width: 9, height: 9)
        a.backingScale = 3
        #expect(a == b)                                // identity unchanged (contract §3)
        #expect(a.hashValue == b.hashValue)
    }

    @Test("identical-twin monitors with different cgUUID are NOT equal")
    func twinsAreDistinct() {
        let edid = EDIDFingerprint(vendorID: 0x1E6D, productID: 0x5B11, serial: nil, displayName: "LG UltraFine")
        let a = DisplayIdentity.fixture(cgUUID: UUID(), edid: edid)
        let b = DisplayIdentity.fixture(cgUUID: UUID(), edid: edid)
        #expect(a != b)
    }

    @Test("usable as a Dictionary key across transient mutation")
    func dictionaryKeyStability() {
        var a = DisplayIdentity.fixture(cgUUID: UUID(), displayID: 1)
        var map: [DisplayIdentity: Int] = [a: 42]
        a.currentDisplayID = 999                       // transient change
        #expect(map[a] == 42)                          // still finds the same entry
    }

    @Test("redaction projection contains no serial")
    func redactionStripsSerial() {
        let edid = EDIDFingerprint(vendorID: 1, productID: 2, serial: 0xDEADBEEF, displayName: "X")
        let id = DisplayIdentity.fixture(cgUUID: UUID(), edid: edid)
        let logSafe = id.redactedForLogging()          // proposed helper (contract §3 redaction)
        #expect(!logSafe.contains("DEADBEEF") && !logSafe.lowercased().contains("3735928559"))
    }
}
```

### 2.4 Watchdog policy

```swift
import Testing
@testable import WarmthCore

@Suite("Reveal watchdog policy")
struct WatchdogTests {

    @Test("auto-resumes after timeout when keyUp is lost")
    func resumesOnLostKeyUp() {
        var clock = FakeClock(.zero)
        var wd = RevealWatchdog(timeout: .seconds(8), mode: .hold, clock: clock)
        wd.keyDown()
        clock.advance(by: .seconds(8) + .milliseconds(1))
        #expect(wd.shouldResume() == true)
    }

    @Test("keyUp before timeout cancels auto-resume (no double fire)")
    func keyUpCancels() {
        var clock = FakeClock(.zero)
        var wd = RevealWatchdog(timeout: .seconds(8), mode: .hold, clock: clock)
        wd.keyDown(); clock.advance(by: .seconds(2)); wd.keyUp()
        clock.advance(by: .seconds(20))
        #expect(wd.shouldResume() == false)
    }

    @Test("default timeout is 8 seconds")
    func defaultTimeout() {
        let wd = RevealWatchdog(mode: .hold, clock: FakeClock(.zero))
        #expect(wd.timeout == .seconds(8))
    }

    @Test("toggle mode never auto-resumes (no keyUp to lose)")
    func toggleNeverResumes() {
        var clock = FakeClock(.zero)
        var wd = RevealWatchdog(timeout: .seconds(8), mode: .toggle, clock: clock)
        wd.keyDown()
        clock.advance(by: .seconds(60))
        #expect(wd.shouldResume() == false)
    }

    @Test("re-arms cleanly for a second reveal cycle")
    func reArm() {
        var clock = FakeClock(.zero)
        var wd = RevealWatchdog(timeout: .seconds(8), mode: .hold, clock: clock)
        wd.keyDown(); clock.advance(by: .seconds(9)); #expect(wd.shouldResume())
        wd.acknowledgeResume()
        wd.keyDown(); clock.advance(by: .seconds(2)); wd.keyUp()
        clock.advance(by: .seconds(9))
        #expect(wd.shouldResume() == false)            // second cycle released normally
    }
}
```

### 2.5 State reducer & badge strings

```swift
import Testing
@testable import WarmthCore

@Suite("State reducer & badges")
struct StateReducerTests {

    @Test("badge strings exactly match the contract")
    func badgeStrings() {
        #expect(DisplayMethod.hardware.badge == "Hardware")
        #expect(DisplayMethod.gamma.badge == "Gamma")
        #expect(DisplayMethod.overlay.badge == "Overlay")
        #expect(DisplayMethod.off.badge == "Off")
    }

    @Test("beginReveal/endReveal flip isRevealing without losing target warmth")
    func revealReducer() {
        var s = WarmthState.fixture(globalWarmth: .init(strength: 0.7))
        s = StateReducer.reduce(s, .beginReveal)
        #expect(s.isRevealing == true)
        #expect(s.globalWarmth.strength == 0.7)        // target warmth retained while revealed
        s = StateReducer.reduce(s, .endReveal)
        #expect(s.isRevealing == false)
    }

    @Test("equal states are Equatable-equal (so stateUpdates can dedupe)")
    func equatableForDedupe() {
        let a = WarmthState.fixture(globalWarmth: .init(strength: 0.5))
        let b = WarmthState.fixture(globalWarmth: .init(strength: 0.5))
        #expect(a == b)
    }
}
```

---

## 3. Test fixtures & helpers needed (request to Lane A)

These belong in a `WarmthCoreTestSupport` target so both unit and `UNIT+FAKE` suites share
them. None change the public surface; they are additive test scaffolding.

- `DisplayIdentity.fixture(cgUUID:edid:displayID:frame:scale:transport:)` — convenience init.
- `WarmthState.fixture(...)` / `DisplayState.fixture(...)`.
- `FakeClock` conforming to whatever clock abstraction `RevealWatchdog`/`ScheduleResolver`
  inject (a `Clock`-like protocol so `.advance(by:)` is deterministic).
- `TestCalendar` — fixed-timezone calendars (UTC, London) + a `fixedDay` helper, so schedule
  tests never depend on the machine's wall clock or locale.
- A way to drive `ScheduleResolver.resolveFollowMode(nightShift:fallback:)` with an injected
  "Night Shift unavailable" value (no real private symbol).

> **Hardcoded-date anti-flake rule:** every schedule/solar test uses an **injected `now` and
> a fixed calendar/timezone**, never `Date()`. A test that reads the real clock is a flaky
> test by construction (it would pass at 23:00 and fail at noon) — that is exactly the
> failure mode this plan exists to prevent.

---

## 4. Run command (hosted lane)

```bash
# Hosted CI (no displays, no permissions) — runs on EVERY push (§21.2 hosted lane).
swift test --package-path WarmthKit --filter WarmthCoreTests
# or, in Xcode 26:
xcodebuild test -scheme WarmthCore -destination 'platform=macOS' -only-testing:WarmthCoreTests
```

Expected gate: **all `WarmthCore` suites green** before any `UNIT+FAKE` engine suite or any
`HW` matrix job is even scheduled — the cheap, pure tests fail fast first.
