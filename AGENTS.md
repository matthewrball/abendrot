# Controlling Abendrot from an AI assistant or the terminal

Abendrot is a macOS menu-bar app that warms the screen. It ships a small command-line
tool, **`abendrot`**, that an AI assistant (Claude Code, Codex, Cursor) or a shell script
can use to read the app's live state and change its settings. This file is the canonical
reference for that control surface. Everything here is grounded in the real binary
(`abendrot --version` → `1.0.2`); no flag is described that the CLI does not implement.

This is a **capability** document: it describes what the `abendrot` CLI can do. It makes no
health or circadian claim — it only documents how to drive the app's visual state.

## TL;DR for an agent

```sh
abendrot set warmth 0.8      # set global warmth (0.0 = none … 1.0 = warmest)
abendrot status --json       # read live state back as JSON, then verify your change
```

`set warmth 0.8` validates the value, writes it to the app's preference domain (so it
survives a restart), and — if the app is running — applies it live and waits for the app to
confirm. `status --json` prints the live snapshot, including `globalWarmthStrength`, so you
can confirm the value landed. Full value ranges, the JSON field reference, and the exit-code
table are below.

If `abendrot` is not on your `PATH`, the binary ships inside the installed app bundle at
`/Applications/Abendrot.app/Contents/Helpers/abendrot` — invoke it by that full path (the
Homebrew cask symlinks it onto `PATH` for you). If neither is available, use the raw
`defaults` fallback in the appendix at the end of this file.

### Building / locating the CLI from source

If you are working in the source tree (not an installed app), build the CLI and run it from the
package's build directory rather than the app bundle:

```sh
swift build -c release --package-path cli
# binary lands at:
cli/.build/release/abendrot          # SwiftPM's stable per-config path (resolves to the arch dir)
./cli/.build/release/abendrot --version   # → 1.0.2
```

The CLI is a standalone SwiftPM executable; it controls the same running app via the shared
preference domain and `state.json`, so a source-built `abendrot` drives an installed/running app
exactly like the shipped one.

## How it works (one paragraph)

The CLI is a thin same-user client. A `set`/`on`/`off`/`exclude` command does two things:
(1) it writes the new value to the app's CFPreferences domain `app.abendrot.Abendrot`, which
persists across launches, and (2) it sends a length-prefixed control message on a same-user Unix-domain socket (`control.sock` beside `state.json`) that wakes the
running app so the change applies live. The app then writes a snapshot file
(`~/Library/Application Support/Abendrot/state.json`) stamped with the request id, and the
CLI polls that file to confirm the change was applied. `status` reads that same snapshot.
There is **no** daemon, XPC service, network listener, or privileged helper.

---

## Commands

Every data-emitting command accepts `--json` for machine-readable output. `abendrot --help`
and `abendrot help <subcommand>` print the same surface this section documents.

### `abendrot status [--json]`

Read live app state: enabled, schedule mode, warmth (strength + approximate Kelvin),
reveal mode, the per-app exclusion set, and the per-display method actually in use. When the
app is **not** running, `status` falls back to the last-saved (persisted) values and says so.

```sh
abendrot status
# Abendrot 1.0.2 (build 4) — running
# Enabled: yes
# Mode: always-on (warming now)
# Warmth: 0.80 (~700K, max 500K)
# Reveal: hold
# Displays:
# • Built-in Retina Display: gamma
# • LG ULTRAFINE: gamma

abendrot status --json   # see the JSON field reference below
```

### `abendrot get <key> [--json]`

Print one configured (persisted) setting. Works whether or not the app is running, because
it reads the preference domain directly.

`<key>` is one of: `warmth` | `mode` | `max-warmth` | `cozy` | `reveal-mode` | `location` | `enabled` |
`late-night` | `bedtime` | `late-night-warmth` | `late-night-kelvin` | `late-night-cozy` | `late-night-ease`

```sh
abendrot get warmth          # 0.80
abendrot get mode            # always-on
abendrot get location        # auto    (or "37.77 -122.42" when set manually)
abendrot get enabled --json  # {"enabled":true}
abendrot get late-night      # on | off
abendrot get bedtime         # 23:00   (24-hour, on this Mac's clock)
abendrot get late-night-ease # 60      (minutes)
```

### `abendrot on [--json]` / `abendrot off [--json]`

Enable or disable warming (`isEnabled`). This is the master toggle, independent of the
schedule mode.

```sh
abendrot on
abendrot off
```

### `abendrot cozy on|off [--json]`

Turn Cozy mode (expanded warmth ceiling down to `~500K` at full strength) on or off in the
running app. `off` restores the active mode's saved warmth at the everyday `1900K` ceiling.

```sh
abendrot cozy on
abendrot cozy off
```

### `abendrot set warmth [<strength>] [--kelvin <kelvin>] [--json]`

Set global warmth either as a strength `0.0`–`1.0`, **or** by targeting an effective Kelvin
with `--kelvin` (the CLI maps the Kelvin to a strength against the configured warmest-point
curve, exactly as the app would). Provide a strength **or** `--kelvin`, not both.

```sh
abendrot set warmth 0.8          # strength 0.0–1.0
abendrot set warmth --kelvin 3000  # target ~3000K effective
```

- `<strength>`: Double, `0.0`–`1.0`. Out-of-range input is rejected (exit 2), not clamped.
- `--kelvin <kelvin>`: Int, `500`–`6500`. Out-of-range rejected (exit 2).
- Giving **both** a strength and `--kelvin` is rejected (exit 2) — pick one.
- A bare leading-negative strength like `set warmth -1` is read as an unknown option and rejected
  (exit 2). To pass a negative value positionally, use the `--` terminator: `set warmth -- -1`
  (which then fails the `0.0`–`1.0` range check, also exit 2). Valid strengths are never negative,
  so this only matters when you are deliberately probing the bound.

### `abendrot set mode <mode> [--json]`

Set the schedule mode. `<mode>` is one of `sunset` | `always-on` | `off`.

- `sunset` — warm on the user's local sunset schedule.
- `always-on` — warm continuously.
- `off` — never warm on a schedule.

```sh
abendrot set mode sunset
```

### `abendrot set max-warmth <kelvin> [--json]`

Set the warmest-point ceiling in Kelvin (the warmest the screen can get). `<kelvin>` is an
Int `500`–`6500`. A lower number is warmer.

```sh
abendrot set max-warmth 1900
```

### `abendrot set reveal-mode <mode> [--json]`

Set how the momentary true-color "reveal" behaves. `<mode>` is `hold` | `toggle`.

```sh
abendrot set reveal-mode toggle
```

### `abendrot set location [<latitude>] [<longitude>] [--auto] [--json]`

Set a manual coordinate for the sunset schedule, or `--auto` to clear it and derive sunset
from the system time zone.

- `<latitude>`: Double, `-90.0`–`90.0`.
- `<longitude>`: Double, `-180.0`–`180.0`.
- `--auto`: clear the manual coordinate (omit lat/lon).

```sh
abendrot set location 37.77 -122.42
abendrot set location --auto
```

### `abendrot exclude add|remove <bundle-id> [--json]` / `abendrot exclude list [--json]`

Manage the per-app warmth-exclusion list. While an excluded app is in front, warmth pauses on the display that app is using. Other displays stay warm. The CLI computes the add/remove against the current set and writes the full sorted replacement.

```sh
abendrot exclude add com.apple.dt.Xcode
abendrot exclude remove com.apple.dt.Xcode
abendrot exclude list            # one bundle id per line, or "(none)"
abendrot exclude list --json     # {"excludedApps":["com.apple.dt.Xcode"]}
```

### `abendrot pause hour|sunrise|resume [--json]` / `abendrot pause fullscreen on|off [--json]`

Temporary warmth holds. These do not change the master toggle, the schedule, or the warmth
curve. `hour` and `sunrise` require warmth to be on, and persist an absolute end time; an
expired hold is discarded on launch so displays cannot stay neutral. `resume` clears that
hold. Turning warmth off also clears it. `fullscreen on` pauses a display when the topmost
window there belongs to an app that also covers that display, or when that display is showing
a native full-screen Space, including on a notched built-in. A zoomed window counts only when it fills the whole display.
Exclusions and fullscreen pause the whole display the window is on, not one window.

```sh
abendrot pause hour
abendrot pause sunrise
abendrot pause resume
abendrot pause fullscreen on
```

### `abendrot late-night [status] [--json]` / `on` / `off` / `bedtime <time>` / `warmth [<strength>] [--kelvin <kelvin>]` / `cozy on|off` / `ease <minutes>`

Sunset mode's opt-in second stage ("Deepen late at night" in Settings → General). The evening
still arrives with the real sunset; the screen then eases warmer before a bedtime and holds
until sunrise. Off by default. It only acts in **Sunset mode**: in `always-on` or `off` the
commands still save the value, exit 0, and print `late-night takes effect in Sunset mode` to
stderr. Each setting command accepts `--json` and sends only its own field.

- `late-night` or `late-night status` prints the configured stage. With `--json` it prints the
  `lateNight` object from `status --json` plus `scheduleMode` and `activeInCurrentMode`.
  While the app runs in Sunset mode with the stage on, a `Now:` line says what the stage is doing:
  `easing`, `holding the late-night colour`, `releasing back to day` or `not active`. `status`
  appends `(easing now)`, `(holding now)` or `(releasing now)` to its `Late night:` line.
- `on` / `off` turn the stage on or off. `off` keeps the other settings.
- `bedtime <time>` takes a 24-hour `HH:MM` (`23:30`, `00:30`) or a 12-hour time with am/pm
  (`11pm`, `11:30pm`, `1am`), on this Mac's clock. Allowed: `20:00`–`04:00` in 30-minute steps.
  Anything else exits 2; it is never rounded.
- `warmth <strength>` takes `0.0`–`1.0` on the everyday curve (`1.0` = 1900K, whatever the
  max-warmth ceiling is). `--kelvin <K>` (`500`–`6500`) maps a Kelvin onto that curve; a Kelvin
  below 1900 lands on 1900 and says so. Setting a warmth does **not** turn `cozy` off, as in
  Settings: while `late-night cozy` is on, bedtime still goes to Cozy and a note says so.
- `cozy on|off` goes to Cozy (~500K) at bedtime instead of the late-night warmth.
- `ease <minutes>` sets how long the ease that ends at bedtime takes: `15`, `30`, `45`, `60`,
  `90` or `120`. Default `60`. Any other number exits 2.

A late-night level no warmer than the evening changes nothing. If the sun sets less than the
ease length before bedtime, the ease starts at sunset instead and ends that much later.

```sh
abendrot late-night on
abendrot late-night bedtime 23:30
abendrot late-night ease 90
abendrot late-night warmth 1.0
abendrot late-night
# Late night: on
# Bedtime: 23:30
# Ease: 1 hr 30 min before bedtime
# Warmth: 1.00 (~1900K)
# Cozy: off
abendrot late-night --json
# {"activeInCurrentMode":true,"bedtime":"23:30","bedtimeMinutes":1410,"cozy":false,"easeMinutes":90,"enabled":true,"kelvin":1900,"phase":"inactive","scheduleMode":"sunset","warmthStrength":1}
```

### `abendrot debug fullscreen [--delay <seconds>]`

Print what Abendrot sees when it decides whether each screen is full screen: the verdict per
display, whether Finder's desktop and the Dock's full-screen backdrop are present, the top app
window, and the desktop-level, app-level and menu-level window list with each window's corner
radius as WindowServer reports it. Window owners, layers, sizes and radii only, never titles.
`--delay` (0-60) waits first so you can switch to the full-screen app or open a menu.

```sh
abendrot debug fullscreen --delay 5
```

### `abendrot reveal [--hold <hold>] [--json]`

Momentary true-color peek — temporarily drop warmth to reveal real colors. This is
**live-only**: it requires a running app and does not write any persisted setting. If the app
is not running, it exits `3`.

- `--hold <hold>`: finite Double `0`–`300`, hold the reveal for N seconds
  (default `3`). Non-finite or out-of-range input is rejected (exit `2`).

```sh
abendrot reveal              # ~3s peek
abendrot reveal --hold 10    # 10s peek
```

### `abendrot --version` / `abendrot --help`

`--version` prints the CLI semver (`1.0.2`). `--help` (and `abendrot help <subcommand>`)
prints usage.

---

## Settable preferences — value ranges and types

| Setting | Command | Type | Range / values | Notes |
|---|---|---|---|---|
| Warmth strength | `set warmth <strength>` | Double | `0.0`–`1.0` | 0 = none, 1 = warmest. Rejected if out of range. |
| Warmth by Kelvin | `set warmth --kelvin <K>` | Int | `500`–`6500` | Mapped to a strength against the warmest-point curve. |
| Schedule mode | `set mode <mode>` | enum | `sunset` \| `always-on` \| `off` | |
| Max warmth (ceiling) | `set max-warmth <K>` | Int | `500`–`6500` | Lower = warmer. |
| Reveal mode | `set reveal-mode <mode>` | enum | `hold` \| `toggle` | |
| Location latitude | `set location <lat> <lon>` | Double | `-90.0`–`90.0` | Pair with longitude. |
| Location longitude | `set location <lat> <lon>` | Double | `-180.0`–`180.0` | Pair with latitude. |
| Location auto | `set location --auto` | flag | — | Clears the manual coordinate. |
| Enabled | `on` / `off` | Bool | — | Master toggle. |
| Cozy mode | `cozy on/off` | Bool | `on` or `off` | Expands warmth to `~500K`; `off` restores everyday `1900K` ceiling. |
| Pause for one hour | `pause hour` | Date + String | one hour from now | Exit 2 if warmth is off. Does not change the toggle or the schedule. |
| Pause until sunrise | `pause sunrise` | Date + String | next local sunrise | Exit 2 if warmth is off, or if sunrise is unavailable for this location today. |
| End a timed pause | `pause resume` | flag | — | Clears `pauseUntil` and `pauseKind`. Does not require warmth to be on. |
| Full-screen pause | `pause fullscreen on/off` | Bool | `on` or `off` | Exit 2 for any other word. A standing preference, not a timed pause. |
| Late-night stage | `late-night on` / `late-night off` | Bool | — | Off by default. Acts in Sunset mode only; saved in any mode. |
| Bedtime | `late-night bedtime <time>` | Int (minutes after midnight) | `20:00`–`04:00`, 30-minute steps | `HH:MM` or `11:30pm`. Off-step or out of range exits 2. |
| Late-night warmth | `late-night warmth <strength>` | Double | `0.0`–`1.0` | Everyday curve: `1.0` = 1900K. Leaves `late-night cozy` as it is. |
| Late-night warmth by Kelvin | `late-night warmth --kelvin <K>` | Int | `500`–`6500` | Mapped onto the everyday curve; 1900 and below store exactly `1.0`, 6500 stores `0.0`. |
| Cozy at bedtime | `late-night cozy on/off` | Bool | `on` or `off` | Go to `~500K` at bedtime instead of the late-night warmth. |
| Ease before bedtime | `late-night ease <minutes>` | Int | `15` \| `30` \| `45` \| `60` \| `90` \| `120` | Default `60`. The ease ends at bedtime. |
| Excluded apps | `exclude add\|remove <bundle-id>` | String | a macOS bundle id | e.g. `com.apple.dt.Xcode`. |
| Reveal (transient) | `reveal [--hold <s>]` | Double | `0`–`300` seconds, default `3` | Live-only; not persisted. |

Validation is enforced by the CLI **and** re-checked by the app, so a bad value is rejected
loudly (exit 2) rather than silently clamped.

---

## `status --json` field reference

`abendrot status --json` emits one JSON object. When the app is **running**, it contains the
full live snapshot plus the CLI-only fields. When the app is **not** running, `running` is
`false` and a reduced set of last-saved fields is surfaced (the persisted values:
`isEnabled`, `scheduleMode`, `globalWarmthStrength` if set, `warmestPointKelvin`,
`revealMode` if set, `excludedApps`, `pauseUntil` and `pauseKind` while a timed pause is
still active, `pausesForFullScreen` if set, and `lateNight` without its `phase`). Always check
`running` first.

Example (app running):

```json
{
  "running": true,
  "cliVersion": "1.0.2",
  "schemaVersion": 1,
  "snapshotSchemaVersion": 1,
  "appVersion": "1.0.2",
  "appBuild": "3",
  "pid": 96889,
  "appLaunchID": "70CAA930-6F6B-40F2-91BF-A5E2812818B0",
  "updatedAt": "2026-06-21T01:32:11Z",
  "lastAppliedRequestID": "3CA23F17-9D1E-4662-9BEB-8AD9204FCFBE",
  "isEnabled": true,
  "scheduleMode": "always-on",
  "isScheduleActiveNow": true,
  "isRevealing": false,
  "globalWarmthStrength": 1,
  "globalKelvin": 500,
  "warmestPointKelvin": 500,
  "revealMode": "hold",
  "excludedApps": [],
  "pauseUntil": "2026-11-09T06:12:00Z",
  "pauseKind": "untilSunrise",
  "pausesForFullScreen": true,
  "lateNight": {
    "enabled": true,
    "bedtime": "23:00",
    "bedtimeMinutes": 1380,
    "warmthStrength": 1,
    "kelvin": 1900,
    "cozy": false,
    "easeMinutes": 60,
    "phase": "inactive"
  },
  "displays": [
    {
      "id": "37D8832A-2D66-02CA-B9F7-8F30A301B230",
      "name": "Built-in Retina Display",
      "appliedMethod": "gamma",
      "warmthStrength": 0,
      "warmthOverridden": false,
      "isHardwareDDCEnabled": false
    }
  ]
}
```

| Field | Type | Meaning |
|---|---|---|
| `running` | Bool | True iff the app's snapshot exists and its `pid` is alive. **Check this first.** |
| `cliVersion` | String | The `abendrot` CLI's own semver. |
| `schemaVersion` | Int | Wire-schema version of the snapshot (currently `1`). |
| `snapshotSchemaVersion` | Int | Same schema version, surfaced even when no live snapshot exists. |
| `appVersion` | String | App marketing version (`CFBundleShortVersionString`). |
| `appBuild` | String | App build number (`CFBundleVersion`). |
| `pid` | Int | The running app's process id. |
| `appLaunchID` | String (UUID) | Regenerated each app launch. |
| `updatedAt` | String (ISO-8601) | When the snapshot was last written. |
| `lastAppliedRequestID` | String (UUID) or null | The request id of the last CLI command the app applied. The CLI uses this to confirm its own change. |
| `isEnabled` | Bool | Master warming toggle. |
| `scheduleMode` | String | `sunset` \| `always-on` \| `off`. |
| `isScheduleActiveNow` | Bool | True when the schedule says "warm now". |
| `isRevealing` | Bool | True during a momentary true-color reveal. |
| `globalWarmthStrength` | Double | Current global warmth strength, `0.0`–`1.0`. |
| `globalKelvin` | Int | Approximate effective Kelvin at the current strength. |
| `warmestPointKelvin` | Int | The warmest-point ceiling. |
| `cozy` | Bool | True when Cozy mode (`~500K` ceiling) is enabled. |
| `revealMode` | String | `hold` \| `toggle`. |
| `excludedApps` | [String] | Sorted bundle ids excluded from warming. |
| `pauseUntil` | String (ISO-8601) or absent | Timed-pause end. Present only while that end is still in the future. Turning warmth off clears it. |
| `pauseKind` | String or absent | `oneHour` \| `untilSunrise`. Present only with `pauseUntil`. |
| `pausesForFullScreen` | Bool or absent | Standing preference: pause a display while a window covers it or while it shows a native full-screen Space. Independent of the timed pause. |
| `lateNight` | object or absent | Sunset mode's late-night stage (see below). Absent from an app older than the stage. |
| `displays` | [object] | Per-display status (see below). |

The `lateNight` object (also what `abendrot late-night --json` prints):

| Field | Type | Meaning |
|---|---|---|
| `enabled` | Bool | The stage is turned on. It still only acts in Sunset mode. |
| `bedtime` | String | Bedtime on this Mac's clock, 24-hour `HH:MM`. |
| `bedtimeMinutes` | Int | The same bedtime as minutes after midnight, `0`–`1439`. |
| `warmthStrength` | Double | Saved late-night warmth, `0.0`–`1.0` on the everyday curve. Kept while `cozy` overrides it. |
| `kelvin` | Int | The colour reached at bedtime: `500` when `cozy`, else `warmthStrength` on the everyday curve. |
| `cozy` | Bool | Go to Cozy at bedtime. |
| `easeMinutes` | Int or absent | Length of the ease that ends at bedtime. Treat absent as `60`. |
| `phase` | String or absent | Running app only. `inactive`: the stage is not changing the screen now (day, the evening before the ease, another mode, a late-night level no warmer than the evening), or the screen is held neutral by a timed, until-sunrise or full-screen pause or a reveal. `easing`: getting warmer before bed. `held`: the ease is done and nothing is moving. `releasing`: cooling back to day, after sunrise or over the last hour before midday when the sun does not rise. A sunrise that stops the ease short goes straight from `easing` to `releasing`; the stage is never held part-way. Treat an unknown value as "something else": `releasing` was added without a `schemaVersion` bump, and more may follow. |

Each `displays[]` object:

| Field | Type | Meaning |
|---|---|---|
| `id` | String (UUID) | Stable display identifier. |
| `name` | String | Display name. |
| `appliedMethod` | String | The layer producing warmth now: `hardware` \| `gamma` \| `colorFilter` \| `windowFilter` \| `overlay` \| `off`. `windowFilter` means an excluded app is in front and only its windows are neutral. |
| `preferredMethod` | String or absent | A user-pinned method, when set (otherwise omitted = automatic). |
| `warmthStrength` | Double | Per-display warmth strength. |
| `warmthOverridden` | Bool | True when this display has a custom (non-global) warmth. |
| `isHardwareDDCEnabled` | Bool | True when hardware DDC warmth is in use for this display. |
| `lastError` | String or absent | Last per-display error, when one occurred. |

JSON keys are emitted in sorted order. Treat any field above as possibly absent and default
gracefully; new fields may appear under the same `schemaVersion` minor evolution.

---

## Exit codes

| Code | Name | Meaning |
|---|---|---|
| `0` | OK | Command succeeded. For a `set` while the app is **closed**, this still means the value was **persisted** (it applies on next launch); the CLI prints `saved; app not running` on stderr and reports `"appliedLive": false` under `--json`. |
| `2` | Bad input | Invalid value or unknown key (e.g. `warmth 50`, an unknown `get` key, a malformed mode), **and** any malformed invocation — a missing/extra argument, an unknown option or subcommand, a non-numeric value, or both a strength and `--kelvin`. The CLI prints a clear message to stderr. (There is no separate `64`/`EX_USAGE` exit; usage errors are normalized to `2`.) `pause hour` and `pause sunrise` also exit 2 when warmth is off. `pause sunrise` exits 2 when no sunrise exists for the location today. `pause fullscreen` exits 2 unless the argument is `on` or `off`. |
| `3` | App not running | A command that **requires** the running app could not reach it. Today this is `reveal` (live-only): no running app, or the app did not confirm the reveal in time. |
| `4` | Live-apply timeout | A `set` persisted successfully and the app **was** running, but it did not confirm the live apply within the timeout. The value is saved; it just was not confirmed live. |

`--json` apply commands print `{"ok":…,"appliedLive":…,"persisted":…}` so an agent can branch
on the result without parsing prose. For example, a successful live `set` prints
`{"ok":true,"appliedLive":true,"persisted":true}`; a code-4 timeout prints
`{"ok":false,"appliedLive":false,"persisted":true}`.

A recommended agent flow: run the `set` (check exit code / `ok`), then run `status --json`
and confirm the field changed. If the app was closed, your change is persisted and will take
effect on next launch — re-check with `status --json` after the app starts.

---

## Trust boundary (read before driving the app)

The control surface is deliberately scoped to: **same macOS user, local session, visual state
only.**

- Any process running as the same user that can run `abendrot` (or write the preference plist)
  can change warmth, toggle warming, or trigger reveal. This is not a macOS privilege
  escalation, but it is sharper than cosmetic: it can affect color-critical work or briefly
  defeat the user's chosen eye-comfort state.
- There is **no** network listener, **no** LaunchDaemon, **no** privileged
  helper, and **no** cross-user delivery. The live wakeup is a user-only Unix-domain
  socket; a peer is accepted only when its uid equals the app's uid.
- The app validates every command exactly like UI input; a socket payload is a hint, not
  trusted authority.

Operate accordingly: this is a tool for the user's own machine and session.

---

## Files

| Path | Role |
|---|---|
| `~/Library/Application Support/Abendrot/state.json` | The live snapshot the app writes and `status` reads. |
| `~/Library/Preferences/app.abendrot.Abendrot.plist` | The CFPreferences domain (`app.abendrot.Abendrot`) where settings persist. |

---

## Appendix: raw `defaults` keys (fallback when the CLI is not installed)

If the `abendrot` CLI is unavailable, an agent can still write the same CFPreferences domain
directly with `defaults write app.abendrot.Abendrot …`. **Caveat:** those writes are **not live**.
Nothing in the running app reloads them. They apply on the next launch only. Prefer the CLI
when it is installed; it persists and applies live over the same-user socket, then confirms.

Domain: `app.abendrot.Abendrot`

| Key | Encoding | Value | `defaults` example |
|---|---|---|---|
| `isEnabled` | Bool | master toggle | `defaults write app.abendrot.Abendrot isEnabled -bool true` |
| `globalWarmthStrength` | Number (Double) | `0.0`–`1.0` | `defaults write app.abendrot.Abendrot globalWarmthStrength -float 0.8` |
| `warmestPointKelvin` | Number (Int) | `500`–`6500` | `defaults write app.abendrot.Abendrot warmestPointKelvin -int 1900` |
| `revealMode` | String | `hold` \| `toggle` | `defaults write app.abendrot.Abendrot revealMode -string hold` |
| `excludedApps` | Array of String | bundle ids (keep sorted) | `defaults write app.abendrot.Abendrot excludedApps -array com.apple.dt.Xcode` |
| `pauseUntil` | Number (Double) | Unix time of the pause end | `defaults write app.abendrot.Abendrot pauseUntil -float 1762661520` |
| `pauseKind` | String | `oneHour` \| `untilSunrise` | `defaults write app.abendrot.Abendrot pauseKind -string oneHour` |
| `pausesForFullScreen` | Bool | standing full-screen preference | `defaults write app.abendrot.Abendrot pausesForFullScreen -bool true` |
| `keepsOtherWindowsWarm` | Bool | experimental, direct download: keep only an excluded app's windows neutral | `defaults write app.abendrot.Abendrot keepsOtherWindowsWarm -bool true` |
| `lateNightEnabled` | Bool or absent | Sunset mode's opt-in late-night stage: ease warmer before bedtime, hold until sunrise. Absent = off | `defaults write app.abendrot.Abendrot lateNightEnabled -bool true` |
| `bedtimeMinutes` | Number (Int) | bedtime as minutes after midnight on the Mac's clock, 8 PM–4 AM: `1200`–`1439` or `0`–`240`, on a 30-minute step. A time outside the range is moved to the nearer end, and a time off the step (`1395`, 23:15) snaps to the nearest step, the earlier one on a tie. Absent = `1380` (11 PM) | `defaults write app.abendrot.Abendrot bedtimeMinutes -int 1380` |
| `lateNightWarmthStrength` | Number (Double) | `0.0`–`1.0` on the everyday curve (1900 K at `1.0`). Absent or invalid = `1.0`. A level no warmer than the evening changes nothing | `defaults write app.abendrot.Abendrot lateNightWarmthStrength -float 1.0` |
| `lateNightCozy` | Bool or absent | go to the Cozy floor at bedtime instead of `lateNightWarmthStrength` | `defaults write app.abendrot.Abendrot lateNightCozy -bool true` |
| `lateNightEaseMinutes` | Number (Int) or absent | length of the ease that ends at bedtime: `15`, `30`, `45`, `60`, `90` or `120`. Any other number is moved to the nearest of these. Absent = `60` | `defaults write app.abendrot.Abendrot lateNightEaseMinutes -int 60` |
| `displaySettings` | **Data** (JSON of validated per-display settings) | app-managed; use the CLI/UI | not a plain scalar — do not hand-edit |
| `userLatitude` | Number (Double) | `-90.0`–`90.0` | `defaults write app.abendrot.Abendrot userLatitude -float 37.77` |
| `userLongitude` | Number (Double) | `-180.0`–`180.0` | `defaults write app.abendrot.Abendrot userLongitude -float -122.42` |
| `scheduleMode` | **Data** (JSON of the engine enum) | see below | not a plain scalar — see note |

### `scheduleMode` is a Data blob, not a string

`scheduleMode` is stored as **Data**: the JSON encoding of the app's internal schedule enum.
The three modes the CLI exposes encode to exactly:

| CLI mode | JSON bytes stored as Data |
|---|---|
| `sunset` | `{"followSystemNightShift":{}}` |
| `always-on` | `{"alwaysOn":{}}` |
| `off` | `{"off":{}}` |

(`sunset` maps to the engine's `followSystemNightShift` case — that is what the app's own UI
writes for Sunset.) Writing this with `defaults` requires the hex of those JSON bytes, e.g.
`{"alwaysOn":{}}` is `7b22616c776179734f6e223a7b7d7d`:

```sh
# always-on
defaults write app.abendrot.Abendrot scheduleMode -data 7b22616c776179734f6e223a7b7d7d
# off -> {"off":{}}
defaults write app.abendrot.Abendrot scheduleMode -data 7b226f6666223a7b7d7d
# sunset -> {"followSystemNightShift":{}} (hex of the literal JSON string)
```

To clear the manual location (the `--auto` equivalent), delete both coordinate keys:

```sh
defaults delete app.abendrot.Abendrot userLatitude
defaults delete app.abendrot.Abendrot userLongitude
```

There is no `reveal` via `defaults` — reveal is a transient, live-only action with no
persisted key. It requires the running app (use the CLI's `abendrot reveal`).

After any raw `defaults` write, run `abendrot status` (or restart the app) to confirm the new
state.
