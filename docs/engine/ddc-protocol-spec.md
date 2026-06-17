# DDC/CI over IOAVService — Apple-Silicon protocol spec (M2)

> **Status:** canonical, 2026-06-17. Reconciled from two independent shipping implementations
> read in full at source — **m1ddc** (waydabber, C) and **MonitorControl `Arm64DDC.swift`**
> (Swift) — cross-checked byte-for-byte against the **VESA MCCS** VCP table, with every golden
> vector hand-recomputed from the stated XOR algorithm. A third (memory-only) source's set-VCP
> checksums were demonstrably wrong (arithmetic errors) and were discarded.
>
> This is the wire contract `HardwareDDC` implements. The **protocol math is certain**; the
> **hardware's tolerance, timing, gain support, and per-display targeting are NOT** and must be
> validated on physical Apple-Silicon + external DDC/CI monitors (a founder hardware pass) before
> the feature is claimed to work. DDC ships **opt-in per display** until that pass (§21‑E3).
>
> Sources: `github.com/waydabber/m1ddc` (`sources/i2c.m`, `sources/ioregistry.m`),
> `github.com/MonitorControl/MonitorControl` (`Arm64DDC.swift`), VESA MCCS 2.2a.

---

## 1. Transaction primitives (`IOAVServiceWriteI2C` / `IOAVServiceReadI2C`)

| Constant | Value | Notes |
|---|---|---|
| `chipAddress` | **`0x37`** | 7-bit DDC/CI address, passed **verbatim** as the 2nd arg. The 8-bit form `0x6E` (=`0x37<<1`) appears **only inside checksum seeds**, never as the IOKit arg. |
| write `offset` | **`0x51`** | DDC/CI data address. (`0x50` only for VCP `0xF4` INPUT_ALT — an LG quirk, irrelevant to RGB gain.) |
| read `offset` | **`0`** | MonitorControl reads at offset `0` (m1ddc uses `0x51`). Both ship working; we follow MonitorControl. *Hardware-verify-only.* |

All 16-bit VCP values are **big-endian** (high byte first).

## 2. Set VCP Feature — 6-byte write

```
buf[0] = 0x84            // 0x80 | length(4)
buf[1] = 0x03            // Set VCP Feature opcode
buf[2] = vcpCode         // 0x16 red / 0x18 green / 0x1A blue / 0x14 preset / 0x10 brightness
buf[3] = (value >> 8) & 0xFF
buf[4] =  value       & 0xFF
buf[5] = checksum = 0x3F ^ buf[0]^buf[1]^buf[2]^buf[3]^buf[4]
//        SEED 0x3F = (0x37<<1) ^ 0x51 = 0x6E ^ 0x51
```
`IOAVServiceWriteI2C(service, 0x37, 0x51, buf, 6)`. Send the packet **twice per attempt**
(reliability double-send). `IOReturn==0` does **not** prove the monitor applied it — verify by
read-back.

## 3. Get VCP Feature — 4-byte request, then read

```
req[0] = 0x82            // 0x80 | length(2)
req[1] = 0x01            // Get VCP Feature request opcode
req[2] = vcpCode
req[3] = checksum = 0x6E ^ req[0]^req[1]^req[2]     // SEED 0x6E ONLY — do NOT XOR 0x51 here
```
Write `req` (`WriteI2C(service, 0x37, 0x51, req, 4)`), sleep the read-settle (~50ms), then
`ReadI2C(service, 0x37, 0, reply, 12)` into a **zero-filled ≥12-byte** buffer.

**Reply parse** (11-byte window; index only after `IOReturn==0`):

```
reply[2] == 0x02         // reply opcode            REQUIRED
reply[3] == 0x00         // result code (0x01 = unsupported VCP)   REQUIRED
reply[4] == vcpCode      // echoed feature code      REQUIRED
max      = (reply[6] << 8) | reply[7]               // big-endian, PER-MONITOR
current  = (reply[8] << 8) | reply[9]               // big-endian
checksum  valid = (0x50 ^ reply[0]^…^reply[len-2]) == reply[len-1]   // SEED 0x50
```
Reject (and retry) on any gate failure. **Reads fail ~30% of the time on Apple Silicon — never
trust an unvalidated reply.**

## 4. RGB gain (relative warming)

VCP **Red `0x16`**, **Green `0x18`**, **Blue `0x1A`** (continuous R/W, VESA MCCS). Range `0..max`
where `max` is **read per-monitor** from `reply[6..7]` (commonly 100, sometimes 255 — never
hardcode).

Recipe: (a) snapshot `nativeGain[c]=current` and `channelMax[c]=max` per channel (and native
preset VCP `0x14`) at first contact; (b) `newGain[c] = clamp(round(nativeGain[c] * mult[c]), 0,
channelMax[c])` where `mult` is the Kelvin→RGB gain (red≈1, blue<green<1 for warmer) — **unsigned
math** (a negative/overflowing value wraps huge); (c) set-VCP each channel, verify by read-back;
(d) **reset = write the snapshotted native gains + restore native `0x14` preset**. Some panels
ignore gain unless `0x14` is first set to a User/Custom preset; if verify persistently fails, try
`0x14=User` once, else mark the display gain-unsupported and degrade to overlay. Warming is
**relative and panel-dependent** — never claim absolute color accuracy.

## 5. IOAVService resolution (CGDirectDisplayID → service)

1. `CoreDisplay_DisplayCreateInfoDictionary(displayID)` (dlsym, CoreDisplay) → read
   `IODisplayLocation` (CFString, a `kIOServicePlane` path) + `kCGDisplayUUID`. Null → not
   DDC-addressable.
2. `IORegistryGetRootEntry` → `IORegistryEntryCreateIterator(root, kIOServicePlane,
   kIORegistryIterateRecursively, &iter)` (all **public** IOKit).
3. Walk with `IOIteratorNext`; `IORegistryEntryGetPath(entry, kIOServicePlane, pathBuf)`
   (`io_string_t`, **512 bytes**). When `path == IODisplayLocation`, from that cursor keep
   advancing until `IORegistryEntryGetName(entry, nameBuf)` (`io_name_t`, **128 bytes**) ==
   `"DCPAVServiceProxy"`.
4. On that proxy read property `"Location"`; **require `== "External"`** (built-in panels are
   `Internal`/other → **never DDC them**; use DisplayServices for built-in).
5. `IOAVServiceCreateWithService(kCFAllocatorDefault, proxy)` (dlsym) → null-guard; CF Create
   rule (`takeRetainedValue` + release on teardown).

**Multi-identical-display fallback** (MonitorControl score-based): collect framebuffer nodes
(`AppleCLCD2` / `IOMobileFramebufferShim`) and `DCPAVServiceProxy` nodes in iterator order; the
framebuffer immediately preceding a proxy supplies its identity; score `(displayID, service)` by
CoreDisplay location-path match (+10 dominant) plus EDID-UUID slice / ProductName / serial
matches; assign greedily, each used once; still gate on `Location=="External"`. There is **no
public service→displayID API** — multi-identical targeting is hardware-verify-only and must be
user-reassignable.

## 6. Timing & retry (MonitorControl shipping defaults)

- Serialize **all** transactions for one service through a single actor/queue — concurrent I²C on
  one bus physically corrupts. Distinct services are independent buses.
- `writeSleep ≈ 10ms` before each write · `readSleep ≈ 50ms` settle after request-write ·
  `retrySleep ≈ 20ms` (optionally exponential to ~80ms). **2 write cycles** per attempt; **up to
  5 attempts** (4 retries + 1) for read/verify. DDC/CI mandates ≥40ms between command/response.
- A 3-channel set+verify ≈ 6 transactions ≈ 300–600ms. DDC is slow **by design**.

## 7. Golden vectors (hand-recomputed, source-agreed → unit tests)

| Op | VCP | Value | Bytes (hex) |
|---|---|---|---|
| set | 0x10 brightness | 50 | `84 03 10 00 32 9A` |
| set | 0x16 red | 90 | `84 03 16 00 5A F4` |
| set | 0x16 red | 75 | `84 03 16 00 4B E5` |
| set | 0x16 red | 100 | `84 03 16 00 64 CA` |
| set | 0x18 green | 80 | `84 03 18 00 50 F0` |
| set | 0x18 green | 50 | `84 03 18 00 32 92` |
| set | 0x1A blue | 75 | `84 03 1A 00 4B E9` |
| set | 0x1A blue | 100 | `84 03 1A 00 64 C6` |
| set | 0x12 contrast | 80 | `84 03 12 00 50 FA` |
| get-req | 0x10 | — | `82 01 10 FD` |
| get-req | 0x16 | — | `82 01 16 FB` |
| get-req | 0x18 | — | `82 01 18 F5` |
| get-req | 0x1A | — | `82 01 1A F7` |
| reply | 0x10 (cur=50,max=100) | — | `6E 88 02 00 10 00 00 64 00 32 F2` |

## 8. Never-do list (safety)

- Never pass `0x6E` as the chipAddress (it's 7-bit `0x37`); `0x6E` lives only in checksum seeds.
- Never XOR `0x51` into the **get-request** checksum (seed `0x6E` only); never omit it from the
  **set** checksum (seed `0x3F`).
- Never DDC a `Location != "External"` (built-in) service.
- Never trust an unvalidated reply (gate `reply[2]==0x02`, `reply[3]==0x00`, `reply[4]==code`, +
  `0x50` checksum).
- Never key persistent state by `CGDirectDisplayID` (unstable across reconnect on arm64) — key by
  `DisplayIdentity` (cgUUID + EDID).
- Never run concurrent transactions on one service; never loop verify forever (DDC is lossy by
  design); never assume gain max is 100; never use signed math for value/clamp.
- Crash/exit handlers can't reliably do async DDC → rely on **launch-time stale-state recovery**,
  not exit handlers. Guard against snapshotting a competing app's warmed gains (f.lux / Lunar /
  BetterDisplay / Night Shift) as "native".

## 9. What remains hardware-verify-only

Read offset (`0` vs `0x51`); exact timing thresholds for stubborn panels; whether a given monitor
honors per-channel gain at all / requires `0x14=User` first; multi-identical-display targeting;
HDMI-port / built-in degradation (no usable IOAVService). The protocol math is certain; the rest
needs a real Apple-Silicon + external-DDC monitor pass.
