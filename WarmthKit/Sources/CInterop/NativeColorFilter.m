#import <Foundation/Foundation.h>
#import <CoreGraphics/CoreGraphics.h>
#import <ColorSync/ColorSync.h>
#import "CInterop.h"
#include <dlfcn.h>
#include <math.h>
#include <pthread.h>
#include <string.h>

// Private ABI: the system-filter getter returns nine row-major doubles by value;
// the WindowServer setter takes a dictionary containing nine float32 values.
// Independently implemented from the observed signatures, not upstream code.
typedef struct { double values[9]; } WKNativeSystemMatrix;
typedef int32_t (*WKSetNativeAdjustments)(CFDictionaryRef);
typedef bool (*WKSystemFilterEnabled)(long);
typedef CFTypeRef (*WKCopySystemFilter)(long, long, long);
typedef WKNativeSystemMatrix (*WKGetSystemFilterMatrix)(CFTypeRef);

_Static_assert(sizeof(float) == 4, "Native matrix payload requires float32");
_Static_assert(sizeof(WKNativeSystemMatrix) == 72, "System matrix ABI requires nine doubles");

static pthread_once_t nativeLoadOnce = PTHREAD_ONCE_INIT;
static WKSetNativeAdjustments setNativeAdjustments;
static WKSystemFilterEnabled systemFilterEnabled;
static WKCopySystemFilter copySystemFilter;
static WKGetSystemFilterMatrix getSystemFilterMatrix;
static CFStringRef nativeMatrixKey;
static CFStringRef nativeTargetKey;
static bool nativeAvailable;

// Defensive input ceiling, not a claimed platform limit. Negative coefficients
// are valid for system color-correction filters and must not be clamped to zero.
static const double nativeCoefficientLimit = 16.0;

static void loadNativeColorFilter(void) {
    // Handles remain open for the lifetime of the cached function/key pointers.
    void *skyLight = dlopen("/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight", RTLD_LAZY | RTLD_LOCAL);
    void *mediaAccessibility = dlopen("/System/Library/Frameworks/MediaAccessibility.framework/MediaAccessibility", RTLD_LAZY | RTLD_LOCAL);
    if (!skyLight || !mediaAccessibility) return;

    setNativeAdjustments = (WKSetNativeAdjustments)dlsym(skyLight, "SLSSetAccessibilityAdjustments");
    CFStringRef *matrix = (CFStringRef *)dlsym(skyLight, "kSLSAccessibilityAdjustmentMatrix");
    CFStringRef *target = (CFStringRef *)dlsym(skyLight, "kSLSAccessibilityTargetDisplay");
    systemFilterEnabled = (WKSystemFilterEnabled)dlsym(mediaAccessibility, "MADisplayFilterPrefGetCategoryEnabled");
    copySystemFilter = (WKCopySystemFilter)dlsym(mediaAccessibility, "MADisplayFilterCopySystemFilter");
    getSystemFilterMatrix = (WKGetSystemFilterMatrix)dlsym(mediaAccessibility, "MADisplayFilterGetMatrix");
    if (!setNativeAdjustments || !systemFilterEnabled || !copySystemFilter || !getSystemFilterMatrix ||
        !matrix || !target || !*matrix || !*target ||
        CFGetTypeID(*matrix) != CFStringGetTypeID() || CFGetTypeID(*target) != CFStringGetTypeID() ||
        CFEqual(*matrix, *target)) return;
    nativeMatrixKey = *matrix;
    nativeTargetKey = *target;
    nativeAvailable = true;
}

bool WKNativeColorFilterAvailable(void) {
    pthread_once(&nativeLoadOnce, loadNativeColorFilter);
    return nativeAvailable;
}

static bool validNativeMatrix(const float matrix[9]) {
    if (!matrix) return false;
    for (size_t i = 0; i < 9; i++) {
        if (!isfinite(matrix[i]) || fabs((double)matrix[i]) > nativeCoefficientLimit) return false;
    }
    return true;
}

bool WKCopySystemColorFilterMatrix(float outMatrix[9]) {
    if (!outMatrix || !WKNativeColorFilterAvailable()) return false;
    float result[9] = {1,0,0, 0,1,0, 0,0,1};
    CFTypeRef filter = NULL;
    @try {
        // Category 1 is the macOS color-filter category. Identity is appropriate
        // only when that category is disabled, never when an enabled filter fails.
        bool enabled = systemFilterEnabled(1);
        if (enabled) {
            filter = copySystemFilter(0, 1, 0);
            if (!filter) return false;
            WKNativeSystemMatrix system = getSystemFilterMatrix(filter);
            for (size_t i = 0; i < 9; i++) {
                if (!isfinite(system.values[i]) || fabs(system.values[i]) > nativeCoefficientLimit) return false;
                result[i] = (float)system.values[i];
            }
        }
        // Refuse a category change during the read; the caller can retry.
        if (systemFilterEnabled(1) != enabled) return false;
    } @catch (NSException *exception) {
        return false;
    } @finally {
        if (filter) CFRelease(filter);
    }
    memcpy(outMatrix, result, sizeof(result));
    return true;
}

static bool nativeTargetMatches(uint32_t displayID, CFStringRef expectedUUID) {
    if (!displayID || !expectedUUID || CFGetTypeID(expectedUUID) != CFStringGetTypeID() ||
        !CGDisplayIsOnline(displayID) || !CGDisplayIsActive(displayID) || !CGDisplayIsBuiltin(displayID) ||
        CGDisplayIsInMirrorSet(displayID) || CGDisplayMirrorsDisplay(displayID) != kCGNullDirectDisplay) return false;
    CFUUIDRef expected = CFUUIDCreateFromString(NULL, expectedUUID);
    if (!expected) return false;
    CFUUIDRef actual = CGDisplayCreateUUIDFromDisplayID(displayID);
    bool matches = actual && CFEqual(actual, expected);
    if (actual) CFRelease(actual);
    CFRelease(expected);
    return matches;
}

bool WKApplyNativeColorMatrix(uint32_t displayID, CFStringRef expectedUUID, const float matrix[9]) {
    if (!validNativeMatrix(matrix) || !WKNativeColorFilterAvailable() || !nativeTargetMatches(displayID, expectedUUID)) return false;
    CFDataRef payload = NULL;
    CFNumberRef target = NULL;
    CFDictionaryRef adjustments = NULL;
    @try {
        payload = CFDataCreate(NULL, (const UInt8 *)matrix, 9 * sizeof(float));
        int64_t targetID = displayID;
        target = CFNumberCreate(NULL, kCFNumberSInt64Type, &targetID);
        if (!payload || !target) return false;
        const void *keys[] = {nativeMatrixKey, nativeTargetKey};
        const void *values[] = {payload, target};
        adjustments = CFDictionaryCreate(NULL, keys, values, 2,
                                         &kCFTypeDictionaryKeyCallBacks, &kCFTypeDictionaryValueCallBacks);
        if (!adjustments || !nativeTargetMatches(displayID, expectedUUID)) return false;
        // The explicit nonzero target is mandatory. There is no global reset path.
        return setNativeAdjustments(adjustments) == 0;
    } @catch (NSException *exception) {
        return false;
    } @finally {
        if (adjustments) CFRelease(adjustments);
        if (target) CFRelease(target);
        if (payload) CFRelease(payload);
    }
}

bool WKComposeNativeColorMatrix(const float baseline[9], float red, float green,
                                float blue, float outMatrix[9]) {
    if (!outMatrix || !validNativeMatrix(baseline) ||
        !isfinite(red) || !isfinite(green) || !isfinite(blue) ||
        red < 0 || red > 1 || green < 0 || green > 1 || blue < 0 || blue > 1) return false;
    const float gains[3] = {red, green, blue};
    float result[9];
    // baseline * diagonal(gains): scale columns, not rows. This linear matrix
    // has no additive bias, so black remains black. The temporary permits aliasing.
    for (size_t row = 0; row < 3; row++) {
        for (size_t column = 0; column < 3; column++) {
            result[row * 3 + column] = baseline[row * 3 + column] * gains[column];
        }
    }
    memcpy(outMatrix, result, sizeof(result));
    return true;
}
