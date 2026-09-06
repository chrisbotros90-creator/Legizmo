// Legizmo – CompatFixes/CrashDetection.x
// Bridges watchOS 9+ Crash Detection (car crash / hard fall) alerts to older iOS.
// On iOS 14/15 the CrashDetectionManager class is absent or restricted;
// this stub re-routes the emergency payload through CLLocationManager and
// the legacy CTCarrier SOS path so the iPhone can still place the call.

#import <Foundation/Foundation.h>
#import <CoreLocation/CoreLocation.h>

// ── Private interface stubs ───────────────────────────────────────────────────

@interface CDCrashDetectionManager : NSObject
+ (instancetype)sharedManager;
- (void)handleCrashPayload:(NSDictionary *)payload fromWatch:(id)watch;
- (BOOL)isCrashDetectionSupported;
@end

@interface CLLocationManager (LGZPrivate)
- (void)_requestEmergencyLocationWithPayload:(NSDictionary *)payload;
@end

@interface CTCarrier (LGZPrivate)
+ (void)_initiateEmergencySOSWithLocation:(CLLocation *)location;
@end

// ── Helpers ───────────────────────────────────────────────────────────────────

static void LGZDispatchCrashSOS(NSDictionary *payload) {
    // Extract lat/lon from payload if the Watch included them
    double lat = [payload[@"latitude"]  doubleValue];
    double lon = [payload[@"longitude"] doubleValue];

    CLLocationManager *lm = [CLLocationManager new];
    if ([lm respondsToSelector:@selector(_requestEmergencyLocationWithPayload:)]) {
        [lm _requestEmergencyLocationWithPayload:payload];
        NSLog(@"[Legizmo/CrashDetection] Emergency location requested via CLLocationManager");
    } else if (lat != 0 || lon != 0) {
        CLLocation *loc = [[CLLocation alloc] initWithLatitude:lat longitude:lon];
        if ([CTCarrier respondsToSelector:@selector(_initiateEmergencySOSWithLocation:)]) {
            [CTCarrier _initiateEmergencySOSWithLocation:loc];
            NSLog(@"[Legizmo/CrashDetection] Emergency SOS dispatched via CTCarrier at (%.4f, %.4f)", lat, lon);
        }
    } else {
        NSLog(@"[Legizmo/CrashDetection] Crash payload received but no location data; cannot dispatch SOS");
    }
}

// ── Hooks ─────────────────────────────────────────────────────────────────────

%hook CDCrashDetectionManager

- (BOOL)isCrashDetectionSupported {
    // Older iOS returns NO; we return YES so watchOS sends us payloads
    BOOL orig = %orig;
    if (!orig) NSLog(@"[Legizmo/CrashDetection] Forcing isCrashDetectionSupported YES");
    return YES;
}

- (void)handleCrashPayload:(NSDictionary *)payload fromWatch:(id)watch {
    NSLog(@"[Legizmo/CrashDetection] Received crash payload: %@", payload);
    // Try the native handler first; fall back to our SOS bridge if it no-ops
    %orig(payload, watch);
    LGZDispatchCrashSOS(payload);
}

%end


// ── Constructor ───────────────────────────────────────────────────────────────

%ctor {
    NSLog(@"[Legizmo/CrashDetection] Crash Detection compat fix loaded");
    %init;
}
