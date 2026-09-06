// Legizmo – CompatFixes/DoubleTap.x
// Bridges watchOS 10+ Double Tap gesture actions to older iOS.
// The iPhone-side handler (WKDoubleTapActionManager) was introduced in iOS 17;
// on iOS 14-16 we intercept the action payload from companionappd and
// dispatch the equivalent UIEvent / app action locally.

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

// ── Private interface stubs ───────────────────────────────────────────────────

@interface WKDoubleTapActionManager : NSObject
+ (instancetype)sharedManager;
- (void)handleDoubleTapAction:(NSString *)actionIdentifier context:(NSDictionary *)context;
- (NSArray<NSString *> *)registeredActionIdentifiers;
@end

// companionappd routes Double Tap payloads through CAWatchActionDispatcher
@interface CAWatchActionDispatcher : NSObject
+ (instancetype)sharedDispatcher;
- (void)dispatchActionPayload:(NSDictionary *)payload fromWatch:(id)watch;
@end

// ── Known action identifiers (watchOS 10) ────────────────────────────────────
// These are the default Double Tap bindings. The Watch sends these as strings.
static NSString * const kLGZDoubleTapCallAnswer     = @"com.apple.doubleTap.phone.answerCall";
static NSString * const kLGZDoubleTapCallDecline    = @"com.apple.doubleTap.phone.declineCall";
static NSString * const kLGZDoubleTapTimerSnooze    = @"com.apple.doubleTap.clock.snooze";
static NSString * const kLGZDoubleTapTimerStop      = @"com.apple.doubleTap.clock.stopTimer";
static NSString * const kLGZDoubleTapScrollNext     = @"com.apple.doubleTap.scroll.next";

// ── Action dispatcher ─────────────────────────────────────────────────────────

static void LGZHandleDoubleTapAction(NSString *actionId, NSDictionary *context) {
    NSLog(@"[Legizmo/DoubleTap] Action received: %@, context: %@", actionId, context);

    // Attempt native handler first (may be absent on iOS 14-16)
    WKDoubleTapActionManager *mgr = [NSClassFromString(@"WKDoubleTapActionManager") performSelector:@selector(sharedManager)];
    if (mgr && [[mgr registeredActionIdentifiers] containsObject:actionId]) {
        [mgr handleDoubleTapAction:actionId context:context];
        return;
    }

    // Fallback: dispatch via UIApplication for phone/timer actions
    UIApplication *app = [UIApplication sharedApplication];
    if ([actionId isEqualToString:kLGZDoubleTapCallAnswer]) {
        // Post a notification; CallKit / TelephonyUI listens for this
        [[NSNotificationCenter defaultCenter] postNotificationName:@"LGZAnswerIncomingCall" object:nil];
        NSLog(@"[Legizmo/DoubleTap] Posted LGZAnswerIncomingCall notification");

    } else if ([actionId isEqualToString:kLGZDoubleTapTimerSnooze]) {
        [[NSNotificationCenter defaultCenter] postNotificationName:@"LGZSnoozeActiveAlarm" object:nil];
        NSLog(@"[Legizmo/DoubleTap] Posted LGZSnoozeActiveAlarm notification");

    } else if ([actionId isEqualToString:kLGZDoubleTapTimerStop]) {
        [[NSNotificationCenter defaultCenter] postNotificationName:@"LGZStopActiveTimer" object:nil];
        NSLog(@"[Legizmo/DoubleTap] Posted LGZStopActiveTimer notification");

    } else {
        NSLog(@"[Legizmo/DoubleTap] Unknown action identifier: %@; no-op", actionId);
    }

    (void)app; // suppress unused warning
}

// ── Hooks ─────────────────────────────────────────────────────────────────────

%hook CAWatchActionDispatcher

- (void)dispatchActionPayload:(NSDictionary *)payload fromWatch:(id)watch {
    NSString *actionId = payload[@"actionIdentifier"];
    if (actionId.length) {
        LGZHandleDoubleTapAction(actionId, payload[@"context"]);
        return; // Don't call %orig; we handle it
    }
    %orig(payload, watch);
}

%end


// ── Constructor ───────────────────────────────────────────────────────────────

%ctor {
    NSLog(@"[Legizmo/DoubleTap] Double Tap compat fix loaded");
    %init;
}
