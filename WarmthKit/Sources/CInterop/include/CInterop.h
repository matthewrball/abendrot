/*
 * CInterop — private-symbol type SHAPES only.
 *
 * This header declares the opaque types and function-pointer signatures we use to talk to
 * Apple private frameworks (IOAVService for DDC, CoreDisplay for display-info dictionaries,
 * and CoreBrightness / CBBlueLightClient for Night Shift state).
 *
 * IMPORTANT: nothing here links against a private framework. These are DECLARATIONS /
 * typedefs ONLY. Every real symbol is resolved at RUNTIME via dlopen()/dlsym() with null
 * checks and OS-build version gating (see DisplayServices / HardwareDDC / NightShiftBridge).
 * If dlsym() returns null on a given OS build, the corresponding capability resolves to
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
 * the Objective-C runtime (objc_getClass) rather than a C symbol. We only model the
 * read-only status block shape here; the class itself is resolved at runtime in
 * NightShiftBridge. WarmthKit NEVER writes Night Shift.
 *
 * `Status` is the layout CBBlueLightClient fills in for getBlueLightStatus:. The field
 * order/size is an internal detail of CoreBrightness and may differ across OS builds, so it
 * is treated as opaque bytes and only probed behind version gating.
 */
typedef struct {
    int   active;          /* non-zero when Night Shift is currently active */
    int   enabled;         /* schedule enabled */
    int   sunSchedulePermitted;
    int   mode;            /* 0 = off, 1 = sunset-to-sunrise, 2 = custom */
    /* Remaining fields (schedule times, strength) intentionally omitted — opaque. */
} WK_CBBlueLightStatus;

#endif /* WARMTHKIT_CINTEROP_H */
