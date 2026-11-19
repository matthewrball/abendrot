#import <AppKit/AppKit.h>
#import <QuartzCore/QuartzCore.h>
#import <dlfcn.h>
#import <math.h>
#import <pthread.h>
#import "CInterop.h"

// WebKit's CAColorMatrix ABI: four rows of five floats, including a zero bias column.
typedef struct { float values[20]; } WKWindowColorMatrix;
@interface NSValue (WKWindowColorMatrix)
+ (instancetype)valueWithCAColorMatrix:(WKWindowColorMatrix)matrix;
@end
@interface NSObject (WKWindowPrivateFilter)
+ (id)filterWithType:(NSString *)type;
@end

bool WKWindowFilterAvailable(void) {
    return NSClassFromString(@"CABackdropLayer") != Nil &&
        [NSClassFromString(@"CAFilter") respondsToSelector:@selector(filterWithType:)] &&
        [NSValue respondsToSelector:@selector(valueWithCAColorMatrix:)];
}

bool WKSetWindowFilterGain(CALayer *layer, float red, float green, float blue) {
    if (!layer || !isfinite(red) || !isfinite(green) || !isfinite(blue) ||
        red < 0 || red > 1 || green < 0 || green > 1 || blue < 0 || blue > 1) return false;
    @try {
        // Publish a fresh filter so WindowServer receives changed channel gains.
        id filter = [NSClassFromString(@"CAFilter") filterWithType:@"colorMatrix"];
        if (!filter) return false;
        WKWindowColorMatrix matrix = { .values = {red,0,0,0,0, 0,green,0,0,0, 0,0,blue,0,0, 0,0,0,1,0} };
        [CATransaction begin];
        [CATransaction setDisableActions:YES];
        @try {
            [filter setValue:[NSValue valueWithCAColorMatrix:matrix] forKey:@"inputColorMatrix"];
            layer.filters = @[filter];
        } @finally {
            [CATransaction commit];
        }
        return true;
    } @catch (NSException *exception) {
        return false;
    }
}

CALayer *WKCreateWindowFilterLayer(void) {
    @try {
        if (!WKWindowFilterAvailable()) return nil;
        CALayer *layer = [NSClassFromString(@"CABackdropLayer") layer];
        if (!layer) return nil;
        [layer setValue:@YES forKey:@"windowServerAware"];
        [layer setValue:@1.0 forKey:@"scale"];
        [layer setValue:@0.0 forKey:@"bleedAmount"];
        [layer setValue:@NO forKey:@"allowsInPlaceFiltering"];
        [layer setValue:NSUUID.UUID.UUIDString forKey:@"groupName"];
        layer.actions = @{@"filters": NSNull.null, @"bounds": NSNull.null, @"position": NSNull.null,
                          @"frame": NSNull.null, @"hidden": NSNull.null};
        return WKSetWindowFilterGain(layer, 1, 1, 1) ? layer : nil;
    } @catch (NSException *exception) {
        return nil;
    }
}

bool WKConfigureWindowFilterWindow(NSWindow *window) {
    @try {
        [window setValue:@NO forKey:@"shouldAutoFlattenLayerTree"];
        [window setValue:@NO forKey:@"canHostLayersInWindowServer"];
        [window setValue:@YES forKey:@"canHostLayersInWindowServer"];
        return true;
    } @catch (NSException *exception) {
        return false;
    }
}

// The interactive screenshot tool (`screencapture -i`, used by Cmd-Shift-4 and the Screenshot
// toolbar) picks a window with CGSFindWindowByGeometry and skips a window whose
// "IgnoreForScreencaptureWindowSelection" property is true. AccessibilityUIServer marks its
// overlays this way. It only affects the window picker; area and full-screen captures still
// include the window.
static NSString *const WKCaptureSelectionKey = @"IgnoreForScreencaptureWindowSelection";
typedef int32_t (*WKMainConnectionID)(void);
typedef int32_t (*WKSetWindowProperty)(int32_t cid, uint32_t wid, CFStringRef key, CFTypeRef value);
typedef int32_t (*WKCopyWindowProperty)(int32_t cid, uint32_t wid, CFStringRef key, CFTypeRef *value);
static pthread_once_t windowPropertyOnce = PTHREAD_ONCE_INIT;
static WKMainConnectionID mainConnectionID;
static WKSetWindowProperty setWindowProperty;
static WKCopyWindowProperty copyWindowProperty;

static void loadWindowProperty(void) {
    void *skyLight = dlopen("/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight", RTLD_LAZY | RTLD_LOCAL);
    if (!skyLight) return;
    mainConnectionID = (WKMainConnectionID)dlsym(skyLight, "SLSMainConnectionID");
    setWindowProperty = (WKSetWindowProperty)dlsym(skyLight, "SLSSetWindowProperty");
    copyWindowProperty = (WKCopyWindowProperty)dlsym(skyLight, "SLSCopyWindowProperty");
}

bool WKExcludeWindowFromCaptureSelection(NSWindow *window) {
    pthread_once(&windowPropertyOnce, loadWindowProperty);
    if (!mainConnectionID || !setWindowProperty || !window || window.windowNumber <= 0) return false;
    return setWindowProperty(mainConnectionID(), (uint32_t)window.windowNumber,
                             (__bridge CFStringRef)WKCaptureSelectionKey, kCFBooleanTrue) == 0;
}

bool WKWindowExcludedFromCaptureSelection(NSWindow *window) {
    pthread_once(&windowPropertyOnce, loadWindowProperty);
    if (!mainConnectionID || !copyWindowProperty || !window || window.windowNumber <= 0) return false;
    CFTypeRef value = NULL;
    if (copyWindowProperty(mainConnectionID(), (uint32_t)window.windowNumber,
                           (__bridge CFStringRef)WKCaptureSelectionKey, &value) != 0 || !value) return false;
    bool excluded = CFEqual(value, kCFBooleanTrue);
    CFRelease(value);
    return excluded;
}

CGFloat WKStandardWindowCornerRadius(void) {
    @try {
        NSWindow *window = [[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, 200, 120)
                                                       styleMask:NSWindowStyleMaskTitled
                                                         backing:NSBackingStoreBuffered
                                                           defer:YES];
        NSNumber *radius = [window valueForKey:@"cornerRadius"];
        if (![radius isKindOfClass:[NSNumber class]]) return 0;
        CGFloat value = radius.doubleValue;
        return isfinite(value) && value > 0 && value < 80 ? value : 0;
    } @catch (NSException *exception) {
        return 0;
    }
}
