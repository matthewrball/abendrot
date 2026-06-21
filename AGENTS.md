# Controlling Abendrot from an AI assistant or the terminal

Abendrot is a macOS menu-bar app that warms the screen. It ships a small command-line
tool, **`abendrot`**, that an AI assistant (Claude Code, Codex, Cursor) or a shell script
can use to read the app's live state and change its settings. This file is the canonical
reference for that control surface. Everything here is grounded in the real binary
(`abendrot --version` → `0.1.0`); no flag is described that the CLI does not implement.

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
./cli/.build/release/abendrot --version   # → 0.1.0
```

The CLI is a standalone SwiftPM executable; it controls the same running app via the shared
preference domain and `state.json`, so a source-built `abendrot` drives an installed/running app
exactly like the shipped one.

## How it works (one paragraph)

The CLI is a thin same-user client. A `set`/`on`/`off`/`exclude` command does two things:
(1) it writes the new value to the app's CFPreferences domain `app.abendrot.Abendrot`, which
persists across launches, and (2) it posts a local `DistributedNotification` that wakes the
running app so the change applies live. The app then writes a snapshot file
(`~/Library/Application Support/Abendrot/state.json`) stamped with the request id, and the
CLI polls that file to confirm the change was applied. `status` reads that same snapshot.
There is **no** daemon, socket, XPC service, network listener, or privileged helper.

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
# Abendrot 0.1.0 (build 1) — running
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

`<key>` is one of: `warmth` | `mode` | `max-warmth` | `reveal-mode` | `location` | `enabled`

```sh
abendrot get warmth          # 0.80
abendrot get mode            # always-on
abendrot get location        # auto    (or "37.77 -122.42" when set manually)
abendrot get enabled --json  # {"enabled":true}
```

### `abendrot on [--json]` / `abendrot off [--json]`

Enable or disable warming (`isEnabled`). This is the master toggle, independent of the
schedule mode.

```sh
abendrot on
abendrot off
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

Manage the per-app warmth-exclusion list (apps whose windows are not warmed). The CLI
computes the add/remove against the current set and writes the full sorted replacement.

```sh
abendrot exclude add com.apple.dt.Xcode
abendrot exclude remove com.apple.dt.Xcode
abendrot exclude list            # one bundle id per line, or "(none)"
abendrot exclude list --json     # {"excludedApps":["com.apple.dt.Xcode"]}
```

### `abendrot reveal [--hold <hold>] [--json]`

Momentary true-color peek — temporarily drop warmth to reveal real colors. This is
**live-only**: it requires a running app and does not write any persisted setting. If the app
is not running, it exits `3`.

- `--hold <hold>`: Double, hold the reveal for N seconds (default `3`).

```sh
abendrot reveal              # ~3s peek
abendrot reveal --hold 10    # 10s peek
```

### `abendrot --version` / `abendrot --help`

`--version` prints the CLI semver (`0.1.0`). `--help` (and `abendrot help <subcommand>`)
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
| Excluded apps | `exclude add\|remove <bundle-id>` | String | a macOS bundle id | e.g. `com.apple.dt.Xcode`. |
| Reveal (transient) | `reveal [--hold <s>]` | Double | hold seconds, default `3` | Live-only; not persisted. |

Validation is enforced by the CLI **and** re-checked by the app, so a bad value is rejected
loudly (exit 2) rather than silently clamped.

---

## `status --json` field reference

`abendrot status --json` emits one JSON object. When the app is **running**, it contains the
full live snapshot plus the CLI-only fields. When the app is **not** running, `running` is
`false` and a reduced set of last-saved fields is surfaced (the persisted values:
`isEnabled`, `scheduleMode`, `globalWarmthStrength` if set, `warmestPointKelvin`,
`revealMode` if set, `excludedApps`). Always check `running` first.

Example (app running):

```json
{
  "running": true,
  "cliVersion": "0.1.0",
  "schemaVersion": 1,
  "snapshotSchemaVersion": 1,
  "appVersion": "0.1.0",
  "appBuild": "1",
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
| `revealMode` | String | `hold` \| `toggle`. |
| `excludedApps` | [String] | Sorted bundle ids excluded from warming. |
| `displays` | [object] | Per-display status (see below). |

Each `displays[]` object:

| Field | Type | Meaning |
|---|---|---|
| `id` | String (UUID) | Stable display identifier. |
| `name` | String | Display name. |
| `appliedMethod` | String | The layer producing warmth now: `hardware` \| `gamma` \| `overlay` \| `off`. |
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
| `2` | Bad input | Invalid value or unknown key (e.g. `warmth 50`, an unknown `get` key, a malformed mode), **and** any malformed invocation — a missing/extra argument, an unknown option or subcommand, a non-numeric value, or both a strength and `--kelvin`. The CLI prints a clear message to stderr. (There is no separate `64`/`EX_USAGE` exit; usage errors are normalized to `2`.) |
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
- There is **no** network listener, **no** socket, **no** LaunchDaemon, **no** privileged
  helper, and **no** cross-user delivery. The live wakeup is a local same-session
  `DistributedNotification`.
- The app validates every command exactly like UI input; a notification payload is a hint, not
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

If the `abendrot` CLI is unavailable, an agent can still drive the app by writing the same
CFPreferences domain directly with `defaults write app.abendrot.Abendrot …`. **Caveat:** raw
writes do **not** post the live wakeup notification, so they are **not guaranteed live**. They
apply on the app's next launch, or whenever the app next reloads its persisted state via its
nil-payload reload path. Prefer the CLI when it is installed; it both persists and applies
live with confirmation.

Domain: `app.abendrot.Abendrot`

| Key | Encoding | Value | `defaults` example |
|---|---|---|---|
| `isEnabled` | Bool | master toggle | `defaults write app.abendrot.Abendrot isEnabled -bool true` |
| `globalWarmthStrength` | Number (Double) | `0.0`–`1.0` | `defaults write app.abendrot.Abendrot globalWarmthStrength -float 0.8` |
| `warmestPointKelvin` | Number (Int) | `500`–`6500` | `defaults write app.abendrot.Abendrot warmestPointKelvin -int 1900` |
| `revealMode` | String | `hold` \| `toggle` | `defaults write app.abendrot.Abendrot revealMode -string hold` |
| `excludedApps` | Array of String | bundle ids (keep sorted) | `defaults write app.abendrot.Abendrot excludedApps -array com.apple.dt.Xcode` |
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
