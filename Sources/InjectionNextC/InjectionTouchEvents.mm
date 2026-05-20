//
//  InjectionTouchEvents.mm
//  InjectionNext
//
//  Captures real UIKit touches as JSON and replays them using the same
//  UITouch/UITouchesEvent strategy Remote used for interactive mirroring.
//

#import "include/InjectionTouchEvents.h"
#import <objc/message.h>
#import <objc/runtime.h>
#import <TargetConditionals.h>

#if TARGET_OS_IOS || TARGET_OS_TV || TARGET_OS_VISION
#import <UIKit/UIKit.h>

@interface UITouch (InjectionReplay)
- (void)setTimestamp:(NSTimeInterval)timestamp;
- (void)setInitialTouchTimestamp:(NSTimeInterval)timestamp;
- (void)setPhase:(NSInteger)phase;
- (void)setWindow:(UIWindow *)window;
- (void)setView:(UIView *)view;
- (void)setTapCount:(NSUInteger)tapCount;
- (void)_setLocationInWindow:(CGPoint)location resetPrevious:(BOOL)reset;
- (void)_setPathIndex:(NSInteger)index;
- (void)_setPathIdentity:(unsigned char)identity;
- (void)_setType:(NSInteger)type;
- (void)_setSenderID:(NSUInteger)senderID;
- (void)_setZGradient:(float)gradient;
- (void)_setEdgeType:(NSInteger)type;
- (void)_setEdgeAim:(NSUInteger)aim;
@end

static InjectionTouchEventCallback injectionTouchEventCallback;
static BOOL injectionCaptureInstalled;
static BOOL injectionIsReplaying;
static NSMutableDictionary<NSNumber *, UITouch *> *injectionTouches;
static NSMutableDictionary<NSNumber *, UIView *> *injectionTargets;
static UIEvent *injectionReplayEvent;

static NSString *InjectionPhaseName(UITouchPhase phase) {
    switch (phase) {
        case UITouchPhaseBegan: return @"began";
        case UITouchPhaseMoved: return @"moved";
        case UITouchPhaseStationary: return @"stationary";
        case UITouchPhaseEnded: return @"ended";
        case UITouchPhaseCancelled: return @"cancelled";
    }
    return @"cancelled";
}

static UITouchPhase InjectionPhaseFromName(NSString *name) {
    if ([name isEqualToString:@"began"]) return UITouchPhaseBegan;
    if ([name isEqualToString:@"moved"]) return UITouchPhaseMoved;
    if ([name isEqualToString:@"stationary"]) return UITouchPhaseStationary;
    if ([name isEqualToString:@"ended"]) return UITouchPhaseEnded;
    if ([name isEqualToString:@"cancelled"]) return UITouchPhaseCancelled;
    return UITouchPhaseCancelled;
}

static UIWindow *InjectionKeyWindow(void) {
    if (@available(iOS 13.0, tvOS 13.0, *)) {
        for (UIWindowScene *scene in UIApplication.sharedApplication.connectedScenes) {
            if (![scene isKindOfClass:UIWindowScene.class] ||
                scene.activationState != UISceneActivationStateForegroundActive)
                continue;
            for (UIWindow *window in scene.windows)
                if (window.isKeyWindow)
                    return window;
            for (UIWindow *window in scene.windows)
                if (!window.isHidden && window.alpha > 0.0)
                    return window;
        }
    }
    for (UIWindow *window in UIApplication.sharedApplication.windows)
        if (window.isKeyWindow)
            return window;
    return UIApplication.sharedApplication.windows.firstObject;
}

static NSNumber *InjectionTouchID(UITouch *touch) {
    return @((NSUInteger)touch.hash);
}

static void InjectionSendTouchJSON(UIEvent *event) {
    if (!injectionTouchEventCallback || injectionIsReplaying)
        return;

    NSSet<UITouch *> *touches = event.allTouches;
    if (!touches.count)
        return;

    UIWindow *window = touches.anyObject.window ?: InjectionKeyWindow();
    CGRect screenBounds = window.bounds;
    CGFloat screenScale = 1.0;
#if !TARGET_OS_VISION
    UIScreen *screen = window.screen ?: UIScreen.mainScreen;
    screenBounds = screen.bounds;
    screenScale = screen.scale;
#endif
    NSMutableArray *encodedTouches = [NSMutableArray arrayWithCapacity:touches.count];
    UITouchPhase phase = touches.anyObject.phase;

    for (UITouch *touch in touches) {
        CGPoint location = [touch locationInView:touch.window ?: window];
        phase = touch.phase;
        [encodedTouches addObject:@{
            @"id": InjectionTouchID(touch),
            @"x": @(location.x),
            @"y": @(location.y),
            @"phase": InjectionPhaseName(touch.phase),
            @"tapCount": @(touch.tapCount)
        }];
    }

    NSDictionary *payload = @{
        @"time": @(event.timestamp),
        @"phase": InjectionPhaseName(phase),
        @"touches": encodedTouches,
        @"screen": @{
            @"width": @(screenBounds.size.width),
            @"height": @(screenBounds.size.height),
            @"scale": @(screenScale)
        }
    };
    NSData *data = [NSJSONSerialization dataWithJSONObject:payload options:0 error:nil];
    if (!data)
        return;
    NSString *json = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
    if (json)
        injectionTouchEventCallback(json.UTF8String);
}

@implementation UIApplication (InjectionTouchEvents)
- (void)injection_sendEvent:(UIEvent *)event {
    [self injection_sendEvent:event];
    InjectionSendTouchJSON(event);
}
@end

static void InjectionConfigureTouch(UITouch *touch, UIView *target,
                                    CGPoint location, UITouchPhase phase,
                                    NSTimeInterval timestamp, NSUInteger tapCount,
                                    NSUInteger identity) {
    [touch setTimestamp:timestamp];
    if (phase == UITouchPhaseBegan)
        [touch setInitialTouchTimestamp:timestamp];
    [touch setPhase:phase];
    [touch setWindow:target.window];
    [touch setView:target];
    [touch setTapCount:MAX(tapCount, 1)];
    [touch _setPathIndex:1];
    [touch _setPathIdentity:(unsigned char)(identity & 0xff)];
    [touch _setType:0];
    [touch _setSenderID:778835616971358211];
    [touch _setZGradient:0.0];
    [touch _setEdgeType:0];
    [touch _setEdgeAim:0];
    [touch _setLocationInWindow:location resetPrevious:phase == UITouchPhaseBegan];
}

static void InjectionShowTapIndicator(UIWindow *window, CGPoint location) {
    static const CGFloat size = 44.0;
    UIView *indicator = [[UIView alloc] initWithFrame:CGRectMake(
        location.x - size / 2.0, location.y - size / 2.0, size, size)];
    indicator.userInteractionEnabled = NO;
    indicator.layer.cornerRadius = size / 2.0;
    indicator.layer.borderWidth = 2.0;
    indicator.layer.borderColor = UIColor.systemBlueColor.CGColor;
    indicator.backgroundColor =
        [UIColor.systemBlueColor colorWithAlphaComponent:0.18];
    indicator.alpha = 0.9;

    [window addSubview:indicator];
    [UIView animateWithDuration:0.25 delay:0.15
                        options:UIViewAnimationOptionCurveEaseOut
                     animations:^{
        indicator.alpha = 0.0;
        indicator.transform = CGAffineTransformMakeScale(1.4, 1.4);
    } completion:^(__unused BOOL finished) {
        [indicator removeFromSuperview];
    }];
}

static void InjectionReplayEvent(NSDictionary *event) {
    NSArray *touches = event[@"touches"];
    if (![touches isKindOfClass:NSArray.class] || touches.count == 0)
        return;

    UIWindow *window = InjectionKeyWindow();
    if (!window)
        return;

    if (!injectionTouches)
        injectionTouches = [NSMutableDictionary new];
    if (!injectionTargets)
        injectionTargets = [NSMutableDictionary new];
    if (!injectionReplayEvent) {
        id event = [NSClassFromString(@"UITouchesEvent") alloc];
        SEL initSelector = NSSelectorFromString(@"_init");
        injectionReplayEvent =
            ((id (*)(id, SEL))objc_msgSend)(event, initSelector);
    }

    ((void (*)(id, SEL))objc_msgSend)(injectionReplayEvent,
                                      NSSelectorFromString(@"_clearTouches"));
    NSMutableSet<UITouch *> *currentTouches = [NSMutableSet set];
    NSTimeInterval timestamp = [event[@"time"] doubleValue] ?: NSDate.timeIntervalSinceReferenceDate;

    for (NSDictionary *touchInfo in touches) {
        if (![touchInfo isKindOfClass:NSDictionary.class])
            continue;

        NSNumber *touchID = touchInfo[@"id"] ?: @1;
        CGPoint location = CGPointMake([touchInfo[@"x"] doubleValue],
                                       [touchInfo[@"y"] doubleValue]);
        UITouchPhase phase = InjectionPhaseFromName(touchInfo[@"phase"] ?: event[@"phase"]);
        UIView *target = injectionTargets[touchID];

        if (phase == UITouchPhaseBegan || !target) {
            target = [window hitTest:location withEvent:nil] ?: window;
            injectionTargets[touchID] = target;
        }

        UITouch *touch = injectionTouches[touchID];
        if (!touch) {
            touch = [UITouch new];
            injectionTouches[touchID] = touch;
        }

        InjectionConfigureTouch(touch, target, location, phase, timestamp,
                                [touchInfo[@"tapCount"] unsignedIntegerValue],
                                touchID.unsignedIntegerValue);
        if (phase == UITouchPhaseBegan)
            InjectionShowTapIndicator(window, location);
        ((void (*)(id, SEL, id, BOOL))objc_msgSend)(
            injectionReplayEvent,
            NSSelectorFromString(@"_addTouch:forDelayedDelivery:"),
            touch, NO);
        [currentTouches addObject:touch];

        if (phase == UITouchPhaseEnded || phase == UITouchPhaseCancelled) {
            [injectionTouches removeObjectForKey:touchID];
            [injectionTargets removeObjectForKey:touchID];
        }
    }

    [UIApplication.sharedApplication sendEvent:injectionReplayEvent];
}

void InjectionInstallTouchEventCapture(InjectionTouchEventCallback callback) {
    injectionTouchEventCallback = [callback copy];
    if (injectionCaptureInstalled)
        return;
    injectionCaptureInstalled = YES;
    Method original = class_getInstanceMethod(UIApplication.class, @selector(sendEvent:));
    Method replacement = class_getInstanceMethod(UIApplication.class, @selector(injection_sendEvent:));
    if (original && replacement)
        method_exchangeImplementations(original, replacement);
}

void InjectionReplayTouchEventsJSON(const char *json) {
    if (!json)
        return;
    NSData *data = [[NSData alloc] initWithBytes:json length:strlen(json)];
    id payload = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
    NSArray *events = [payload isKindOfClass:NSArray.class] ? payload : [payload objectForKey:@"events"];
    if (![events isKindOfClass:NSArray.class])
        return;

    NSTimeInterval firstTime = 0;
    BOOL foundFirstTime = NO;
    for (NSDictionary *event in events) {
        if ([event isKindOfClass:NSDictionary.class]) {
            firstTime = [event[@"time"] doubleValue];
            foundFirstTime = YES;
            break;
        }
    }

    injectionIsReplaying = YES;
    NSTimeInterval replayStart = NSDate.timeIntervalSinceReferenceDate;
    NSTimeInterval lastDelay = 0;
    for (NSDictionary *event in events) {
        if (![event isKindOfClass:NSDictionary.class])
            continue;
        NSTimeInterval eventTime = [event[@"time"] doubleValue];
        NSTimeInterval delay = foundFirstTime ? MAX(0, eventTime - firstTime) : lastDelay;
        lastDelay = delay;
        NSMutableDictionary *copy = [event mutableCopy];
        copy[@"time"] = @(replayStart + delay);
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(delay * NSEC_PER_SEC)),
                       dispatch_get_main_queue(), ^{
            InjectionReplayEvent(copy);
        });
    }
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)((lastDelay + 0.05) * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
        injectionIsReplaying = NO;
    });
    if (!events.count)
        injectionIsReplaying = NO;
}

#else

void InjectionInstallTouchEventCapture(InjectionTouchEventCallback callback) {}
void InjectionReplayTouchEventsJSON(const char *json) {}

#endif
