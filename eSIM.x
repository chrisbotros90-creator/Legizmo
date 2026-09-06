// Legizmo – CompatFixes/eSIM.x
// Patches the Apple Watch cellular / eSIM pairing flow on iOS 14-16.
// watchOS 9/10 moved to a new Euicc provisioning API that requires iOS 16+
// on the iPhone side. On iOS 14/15 the EUICCManager class either lacks the
// required selectors or enforces a firmware gate. We bridge the call
// through the legacy MCCTelephonySupport provisioning path.

#import <Foundation/Foundation.h>

// ── Private interface stubs ───────────────────────────────────────────────────

@interface EUICCManager : NSObject
+ (instancetype)sharedManager;
- (void)provisionEmbeddedSIMForWatch:(id)watch
                     activationCode:(NSString *)code
                          completion:(void(^)(BOOL success, NSError *error))completion;
- (BOOL)isCellularWatchPairingSupported;
- (NSString *)activationURLForWatch:(id)watch;
@end

@interface MCCTelephonySupport : NSObject
+ (instancetype)sharedInstance;
- (void)activateEmbeddedSIMWithURL:(NSString *)url
                         forWatch:(id)watch
                       completion:(void(^)(BOOL, NSError *))completion;
@end

// ── Helpers ───────────────────────────────────────────────────────────────────

static void LGZProvisionViaTelephonySupport(NSString *activationURL,
                                            id watch,
                                            void(^completion)(BOOL, NSError *)) {
    MCCTelephonySupport *support = [NSClassFromString(@"MCCTelephonySupport") performSelector:@selector(sharedInstance)];
    if (!support || ![support respondsToSelector:@selector(activateEmbeddedSIMWithURL:forWatch:completion:)]) {
        NSLog(@"[Legizmo/eSIM] MCCTelephonySupport unavailable; eSIM pairing cannot proceed");
        if (completion) {
            completion(NO, [NSError errorWithDomain:@"com.lunotech11.legizmo"
                                              code:1001
                                          userInfo:@{NSLocalizedDescriptionKey: @"Cellular pairing not supported on this iOS version"}]);
        }
        return;
    }
    NSLog(@"[Legizmo/eSIM] Falling back to MCCTelephonySupport activation with URL: %@", activationURL);
    [support activateEmbeddedSIMWithURL:activationURL forWatch:watch completion:completion];
}

// ── Hooks ─────────────────────────────────────────────────────────────────────

%hook EUICCManager

- (BOOL)isCellularWatchPairingSupported {
    BOOL orig = %orig;
    if (!orig) NSLog(@"[Legizmo/eSIM] Forcing isCellularWatchPairingSupported YES");
    return YES;
}

- (void)provisionEmbeddedSIMForWatch:(id)watch
                     activationCode:(NSString *)code
                          completion:(void(^)(BOOL success, NSError *error))completion {
    // Let the native path run first
    %orig(watch, code, completion);

    // If native path is a no-op stub (iOS 14/15), the completion will never fire.
    // We re-attempt via legacy path after a 3-second grace period.
    NSString *activationURL = [self activationURLForWatch:watch];
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(3.0 * NSEC_PER_SEC)),
                   dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
        LGZProvisionViaTelephonySupport(activationURL, watch, completion);
    });
}

%end


// ── Constructor ───────────────────────────────────────────────────────────────

%ctor {
    NSLog(@"[Legizmo/eSIM] eSIM compat fix loaded");
    %init;
}
