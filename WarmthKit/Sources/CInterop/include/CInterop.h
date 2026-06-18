/*
 * CInterop — private-symbol type SHAPES only.
 *
 * This header declares the opaque types and function-pointer signatures we use to talk to
 * Apple private frameworks (IOAVService for DDC, CoreDisplay for display-info dictionaries,
 * and CoreBrightness / CBBlueLightClient for Night Shift state).
 *
 * IMPORTANT: nothing here links against a private framework. These are DECLARATIONS /
 * typedefs ONLY. Every real symbol is resolved at RUNTIME via dlopen()/dlsym() (or, for the
 * Objective-C CBBlueLightClient class, the Objective-C runtime) with null checks and OS-build
 * version gating (see DisplayServices / HardwareDDC / NightShiftBridge). If a symbol can't be
 * resolved on a given OS build, the corresponding capability resolves to
 * `.unknown(.privateSymbolUnavailable)` and the engine falls back to overlay-only.
 */

#ifndef WARMTHKIT_CINTEROP_H
#define WARMTHKIT_CINTEROP_H

#include <stdint.h>
#include <stddef.h>
#include <IOKit/IOKitLib.h>
#include <CoreFoundation/CoreFoundation.h>

/* ── IOAVService (private, IOKit) ─────────────────────────────────────────────
 * The DDC/CI write path. `IOAVServiceCreate` / `IOAVServiceCreateWithService` return an
 * opaque ref; `IOAVServiceWriteI2C` / `IOAVServiceReadI2C` carry VCP gain transactions.
 * Declared as an opaque pointer; the concrete struct is private to IOKit.
 */
typedef CFTypeRef WK_IOAVServiceRef;

/* Function-pointer shapes resolved via dlsym at runtime. */
typedef WK_IOAVServiceRef (*WK_IOAVServiceCreate_fn)(CFAllocatorRef allocator);
typedef WK_IOAVServiceRef (*WK_IOAVServiceCreateWithService_fn)(CFAllocatorRef allocator, io_service_t service);
typedef IOReturn (*WK_IOAVServiceWriteI2C_fn)(WK_IOAVServiceRef service,
                                              uint32_t chipAddress,
                                              uint32_t offset,
                                              void *outputBuffer,
                                              uint32_t outputBufferSize);
typedef IOReturn (*WK_IOAVServiceReadI2C_fn)(WK_IOAVServiceRef service,
                                             uint32_t chipAddress,
                                             uint32_t offset,
                                             void *inputBuffer,
                                             uint32_t inputBufferSize);

/* ── CoreDisplay (private) ────────────────────────────────────────────────────
 * CoreDisplay_DisplayCreateInfoDictionary returns a CFDictionary of EDID-ish display info
 * keyed by CGDirectDisplayID. Used (best-effort) to enrich DisplayIdentity.
 */
typedef CFDictionaryRef (*WK_CoreDisplay_DisplayCreateInfoDictionary_fn)(uint32_t displayID);

/* ── CoreBrightness / CBBlueLightClient (private, Objective-C) ─────────────────
 * Night Shift state is read via the CBBlueLightClient Objective-C class, obtained through
 * the Objective-C runtime (NSClassFromString / objc_getClass) rather than a C symbol. We model
 * only the read-only status struct shape here; the class itself is resolved at runtime in
 * NightShiftBridge. WarmthKit NEVER writes Night Shift.
 *
 * `WK_CBBlueLightStatus` mirrors the layout CBBlueLightClient fills in for `getBlueLightStatus:`.
 * Getting the ABI right matters: across the known public reimplementations (Shifty, the
 * nightlight/shift CLIs) the struct is:
 *
 *     typedef struct { int hour; int minute; } Time;          // macOS: 4-byte ints, NOT char
 *     typedef struct { Time fromTime; Time toTime; } Schedule; // 16 bytes
 *     typedef struct {
 *         BOOL                active;               // Night Shift currently warming the screen
 *         BOOL                enabled;              // the schedule master switch
 *         BOOL                sunSchedulePermitted; // location-based schedule allowed
 *         int                 mode;                 // 0 = off, 1 = sunset→sunrise, 2 = custom
 *         Schedule            schedule;             // { fromTime{h,m}, toTime{h,m} }
 *         unsigned long long  disableFlags;
 *         BOOL                available;            // Night Shift supported on this hardware
 *     } Status;
 *
 * CRITICAL ABI NOTES (both confirmed against the public CoreBrightness runtime headers):
 *   1. Objective-C `BOOL` is `signed char` (1 byte) on arm64/Apple Silicon and modern x86_64
 *      macOS — NOT a 4-byte `int`. Modelling the leading flags as `signed char` lets the C
 *      compiler insert the natural 3-byte pad before the 4-byte-aligned `int mode`, matching the
 *      real offsets so `active`/`enabled` read correctly.
 *   2. The `Time` sub-struct uses 4-byte `int` hour/minute on macOS (it is `char` on iOS). The
 *      total struct SIZE matters even though the follower only reads `active`: `getBlueLightStatus:`
 *      writes the WHOLE struct into the out-parameter, so an undersized buffer would be a stack
 *      overflow. We therefore model every field at its true width so the buffer is exactly the
 *      size CoreBrightness expects to fill.
 *
 * A runtime `sizeof` sanity check can guard against ABI drift before we trust any read.
 */
typedef struct {
    int hour;
    int minute;
} WK_CBBlueLightTime;

typedef struct {
    WK_CBBlueLightTime fromTime;
    WK_CBBlueLightTime toTime;
} WK_CBBlueLightSchedule;

typedef struct {
    signed char            active;               /* non-zero when Night Shift is currently active */
    signed char            enabled;              /* schedule master switch */
    signed char            sunSchedulePermitted; /* location schedule allowed */
    int                    mode;                 /* 0 = off, 1 = sunset→sunrise, 2 = custom */
    WK_CBBlueLightSchedule schedule;             /* fromTime / toTime (h,m) */
    unsigned long long     disableFlags;
    signed char            available;            /* Night Shift supported on this hardware */
} WK_CBBlueLightStatus;

/* The size we expect `getBlueLightStatus:` to fill. A runtime `sizeof` comparison against the
 * value the live class reports (where derivable) is a cheap ABI-drift guard: if it disagrees we
 * report `.unknown(.privateSymbolUnavailable)` rather than trusting a misaligned read. */
static const size_t WK_CBBlueLightStatus_expected_size = sizeof(WK_CBBlueLightStatus);

#endif /* WARMTHKIT_CINTEROP_H */
