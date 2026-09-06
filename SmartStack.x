// Legizmo – CompatFixes/SmartStack.x
// Bridges watchOS 10+ Smart Stack widget data to older iOS.
// Smart Stack pushes complication/widget timeline data via a new Bluetooth
// message type (LGZMessageTypeSmartStack = 0x09) that iOS 14-16's
// companionappd does not recognise. We decode and re-route it through
// the legacy CLKComplication update path.

#import <Foundation/Foundation.h>
#import <ClockKit/ClockKit.h>

// ── Message type extension ────────────────────────────────────────────────────
// (matches SyncHooks.x enum; defined locally to avoid re-declaration)
#define kLGZMessageTypeSmartStack 0x09

// ── Private interface stubs ───────────────────────────────────────────────────

@interface CLKComplicationServer : NSObject
+ (instancetype)sharedInstance;
- (void)reloadTimelineForComplication:(CLKComplication *)complication;
- (void)extendTimelineForComplication:(CLKComplication *)complication;
@end

@interface CAWatchSmartStackManager : NSObject
+ (instancetype)sharedManager;
- (void)processSmartStackPayload:(NSDictionary *)payload;
- (BOOL)isSmartStackSupported;
@end

@interface CAWatchMessage : NSObject
@property (nonatomic, assign) NSUInteger messageType;
@property (nonatomic, strong) NSData    *payload;
@property (nonatomic, assign) NSUInteger protocolVersion;
@end

@interface CAWatchCompanionManager : NSObject
+ (instancetype)sharedManager;
- (void)processIncomingMessage:(CAWatchMessage *)message fromWatch:(id)watch;
@end

// ── Smart Stack payload decoder ───────────────────────────────────────────────
// Smart Stack payloads are NSKeyedArchiver'd NSDictionary blobs.

static NSDictionary *LGZDecodeSmartStackPayload(NSData *data) {
    if (!data.length) return nil;
    @try {
        NSError *err = nil;
        id obj = [NSKeyedUnarchiver unarchivedObjectOfClasses:
                    [NSSet setWithObjects:[NSDictionary class], [NSArray class],
                     [NSString class], [NSNumber class], [NSDate class], [NSData class], nil]
                  fromData:data error:&err];
        if (err) NSLog(@"[Legizmo/SmartStack] Decode error: %@", err);
        return [obj isKindOfClass:[NSDictionary class]] ? obj : nil;
    } @catch (NSException *e) {
        NSLog(@"[Legizmo/SmartStack] Exception decoding payload: %@", e);
        return nil;
    }
}

// ── Hooks ─────────────────────────────────────────────────────────────────────

%hook CAWatchSmartStackManager

- (BOOL)isSmartStackSupported {
    BOOL orig = %orig;
    if (!orig) NSLog(@"[Legizmo/SmartStack] Forcing isSmartStackSupported YES");
    return YES;
}

- (void)processSmartStackPayload:(NSDictionary *)payload {
    NSLog(@"[Legizmo/SmartStack] Processing Smart Stack payload with %lu keys", (unsigned long)payload.count);

    // Attempt native handler
    %orig(payload);

    // Also trigger ClockKit complication reload so Siri/watch faces update
    CLKComplicationServer *server = [CLKComplicationServer sharedInstance];
    NSArray<CLKComplication *> *complications = [server valueForKey:@"activeComplications"];
    for (CLKComplication *c in complications) {
        [server reloadTimelineForComplication:c];
    }
    NSLog(@"[Legizmo/SmartStack] Triggered timeline reload for %lu complications", (unsigned long)complications.count);
}

%end


%hook CAWatchCompanionManager

- (void)processIncomingMessage:(CAWatchMessage *)message fromWatch:(id)watch {
    if (message.messageType == kLGZMessageTypeSmartStack) {
        NSDictionary *payload = LGZDecodeSmartStackPayload(message.payload);
        if (payload) {
            CAWatchSmartStackManager *mgr = [NSClassFromString(@"CAWatchSmartStackManager") performSelector:@selector(sharedManager)];
            if (mgr) {
                [mgr processSmartStackPayload:payload];
                return; // handled
            }
        }
        NSLog(@"[Legizmo/SmartStack] Received Smart Stack message but could not decode or dispatch");
        return;
    }
    %orig(message, watch);
}

%end


// ── Constructor ───────────────────────────────────────────────────────────────

%ctor {
    NSLog(@"[Legizmo/SmartStack] Smart Stack compat fix loaded");
    %init;
}
