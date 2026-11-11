#import <AppKit/AppKit.h>
#import <QuartzCore/QuartzCore.h>
#import <math.h>
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
