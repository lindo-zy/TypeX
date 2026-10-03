#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <dispatch/dispatch.h>
#import "../DXStatusBarGesturePolicy.h"
#import "../DXKeyboardPanelPreferences.h"
#import "../DXGlobalPanelPolicy.h"
#import "../DXPrefsManager.h"
#import "../DXSystemOpenBroker.h"
#define kEnabledkey @"enabledBOOL"
#define kEnabledHaptickey @"enabledHapticBOOL"
#define kLinkActionskey @"linkactions"
static NSUInteger checks, sends;
static NSString *sentSlot, *sentSelector;
static BOOL sentLandscape;
static void check(BOOL condition, NSString *name) { checks++; NSCAssert(condition, @"%@", name); }
void DXRequestStatusBarGesture(NSString *slot, NSString *selector, BOOL landscape, DXSystemOpenReply reply) {
    check(NSThread.isMainThread && DXStatusBarSlotValid(slot), @"relay from main thread with valid slot");
    sends++; sentSlot = slot; sentSelector = selector; sentLandscape = landscape; reply(DXSystemOpenSucceeded);
}
@interface DXGlobalPanel : NSObject
+ (instancetype)sharedInstance;
+ (BOOL)deviceUnlocked;
- (BOOL)isVisible;
@end
@implementation DXGlobalPanel
+ (instancetype)sharedInstance { static DXGlobalPanel *panel; if (!panel) panel = [self new]; return panel; }
+ (BOOL)deviceUnlocked { return NO; } // These SpringBoard gates must not block a UIKit host app.
- (BOOL)isVisible { return YES; }
@end
@interface DXPrefsManager ()
@property(nonatomic, readwrite) BOOL preferencesAvailable;
@end
@implementation DXPrefsManager
+ (instancetype)sharedInstance { static DXPrefsManager *manager; if (!manager) manager = [self new]; return manager; }
- (void)reload {}
@end
#include "StatusDoubles.inc"
@implementation UIApplication
+ (instancetype)sharedApplication { static UIApplication *app; if (!app) app = [self new]; return app; }
@end
@implementation UIWindowScene (StatusBarTests)
- (UIInterfaceOrientation)interfaceOrientation { return [objc_getAssociatedObject(self, @selector(interfaceOrientation)) integerValue]; }
- (void)setInterfaceOrientation:(UIInterfaceOrientation)value { objc_setAssociatedObject(self, @selector(interfaceOrientation), @(value), OBJC_ASSOCIATION_RETAIN_NONATOMIC); }
@end
@implementation UITouch (StatusBarTests)
- (NSUInteger)tapCount { return [objc_getAssociatedObject(self, @selector(tapCount)) unsignedIntegerValue]; }
- (void)setTapCount:(NSUInteger)value { objc_setAssociatedObject(self, @selector(tapCount), @(value), OBJC_ASSOCIATION_RETAIN_NONATOMIC); }
@end
@implementation UIGestureRecognizer (StatusBarTests)
- (void)requireGestureRecognizerToFail:(UIGestureRecognizer *)gesture { (void)gesture; }
@end
@implementation UITapGestureRecognizer @end
@implementation UILongPressGestureRecognizer @end
@implementation UIImpactFeedbackGenerator
- (instancetype)initWithStyle:(UIImpactFeedbackStyle)style { (void)style; return [super init]; }
- (void)impactOccurred {}
@end
@implementation UIStatusBar @end
@implementation _UIStatusBar @end
#include "StatusHandler.inc"
static UITouch *touchFor(UIView *anchor, CGFloat x) {
    UITouch *touch = [UITouch new]; touch.view = anchor; touch.window = anchor.window;
    touch.point = CGPointMake(x, 12); touch.tapCount = 1; return touch;
}
static UIGestureRecognizer *gestureFor(DXStatusGestureHandler *handler, NSString *kind) {
    for (UIGestureRecognizer *gesture in handler.recognizers) if ([objc_getAssociatedObject(gesture, &DXStatusKindKey) isEqual:kind]) return gesture;
    return nil;
}
int main(void) {
    @autoreleasepool {
        UIWindow *window = [UIWindow new]; window.window = window; window.bounds = CGRectMake(0, 0, 390, 844);
        UIStatusBar *anchor = [UIStatusBar new]; anchor.bounds = CGRectMake(0, 0, 390, 54); [window addSubview:anchor];
        _UIStatusBar *nested = [_UIStatusBar new]; [anchor addSubview:nested];
        NSMutableDictionary *bindings = [NSMutableDictionary dictionary];
        for (NSString *region in DXStatusBarRegions()) for (NSString *kind in DXStatusBarGestures())
            bindings[DXStatusBarSlot(region, kind)] = @{@"enabled": @YES, @"selector": @"__typex_statusbar_panel_common"};
        NSDictionary *baseline = @{kDXStatusBarEnabled: @YES, kDXStatusBarBindings: bindings};
        DXPrefsManager *manager = DXPrefsManager.sharedInstance; manager.prefs = baseline; manager.preferencesAvailable = YES;
        DXStatusHandlers = [NSHashTable weakObjectsHashTable]; DXInstallStatusGestures(anchor); DXInstallStatusGestures(nested); DXInstallStatusGestures(anchor);
        DXStatusGestureHandler *handler = objc_getAssociatedObject(anchor, &DXStatusHandlerKey);
        check(handler != nil && window.gestureRecognizers.count == 4 && DXStatusHandlers.count == 1, @"nested views install once per anchor");
        check([handler available], @"app availability does not use SpringBoard lock/panel methods");
        for (NSString *region in DXStatusBarRegions()) for (NSString *kind in DXStatusBarGestures()) {
            CGFloat x = [region isEqual:@"left"] ? 10 : ([region isEqual:@"middle"] ? 150 : 300);
            UIGestureRecognizer *gesture = gestureFor(handler, [kind hasSuffix:@"swipe"] ? @"horizontal" : kind);
            check(gesture.enabled, @"configured recognizer enabled");
            gesture.state = UIGestureRecognizerStatePossible;
            check([handler gestureRecognizer:gesture shouldReceiveTouch:touchFor(anchor, x)], @"configured touch accepted");
            if ([gesture isKindOfClass:UIPanGestureRecognizer.class]) ((UIPanGestureRecognizer *)gesture).delta = CGPointMake([kind isEqual:@"leftswipe"] ? -40 : 40, 0);
            check([handler gestureRecognizerShouldBegin:gesture], @"eligible gesture begins");
            NSUInteger before = sends;
            gesture.state = [kind isEqual:@"longpress"] ? UIGestureRecognizerStateBegan : UIGestureRecognizerStateEnded;
            [handler recognized:gesture]; [handler recognized:gesture];
            check(sends == before + 1 && [sentSlot isEqual:DXStatusBarSlot(region, kind)] && [sentSelector isEqual:@"__typex_statusbar_panel_common"] && !sentLandscape, @"one relay for each of fifteen slots");
        }
        UIGestureRecognizer *tap = gestureFor(handler, @"tap"); NSUInteger before = sends;
        check([handler gestureRecognizer:tap shouldReceiveTouch:touchFor(anchor, 10)], @"start pending touch");
        manager.prefs = @{}; tap.state = UIGestureRecognizerStateEnded; [handler recognized:tap];
        check(sends == before, @"changed configuration cancels pending action"); manager.prefs = baseline;
        check([handler gestureRecognizer:tap shouldReceiveTouch:touchFor(anchor, 10)], @"start before refresh"); [handler refresh]; [handler recognized:tap];
        check(sends == before, @"refresh clears old touch session");
        check([handler gestureRecognizer:tap shouldReceiveTouch:touchFor(anchor, 10)], @"start before anchor moves"); anchor.originInWindow = CGPointMake(1, 0); [handler recognized:tap];
        check(sends == before, @"moved anchor cancels"); anchor.originInWindow = CGPointZero;
        UIApplication.sharedApplication.applicationState = UIApplicationStateInactive;
        check(![handler available], @"inactive app blocked"); UIApplication.sharedApplication.applicationState = UIApplicationStateActive;
        window.windowScene = [UIWindowScene new]; window.windowScene.activationState = UISceneActivationStateBackground;
        check(![handler available], @"background scene blocked"); window.windowScene.activationState = UISceneActivationStateForegroundActive;
        window.windowScene.interfaceOrientation = UIInterfaceOrientationLandscapeLeft;
        check(![handler available], @"landscape requires opt in");
        NSMutableDictionary *landscape = [baseline mutableCopy]; landscape[kDXStatusBarLandscape] = @YES; manager.prefs = landscape;
        check([handler gestureRecognizer:tap shouldReceiveTouch:touchFor(anchor, 10)], @"landscape touch with opt in"); [handler recognized:tap];
        check(sends == before + 1 && sentLandscape, @"relay includes landscape state"); manager.prefs = baseline; window.windowScene = nil;
        UIControl *nativeControl = [UIControl new]; [anchor addSubview:nativeControl];
        UITouch *control = touchFor(anchor, 10); control.view = nativeControl;
        check(![handler gestureRecognizer:tap shouldReceiveTouch:control], @"native controls excluded");
        anchor.hidden = YES; check(![handler available], @"hidden status bar blocked"); anchor.hidden = NO;
        manager.preferencesAvailable = NO; check(![handler available], @"missing snapshot blocked"); manager.preferencesAvailable = YES;
        anchor.window = nil; DXInstallStatusGestures(anchor);
        check(window.gestureRecognizers.count == 0 && !objc_getAssociatedObject(anchor, &DXStatusHandlerKey), @"detach removes all recognizers");
        printf("PASS: %lu production status-bar handler checks with UIKit doubles\n", (unsigned long)checks);
    }
    return 0;
}
