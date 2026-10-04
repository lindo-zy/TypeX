#import "DXPanelTestFixtures.h"
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
static BOOL testUnlocked, testPanelVisible = YES;
static NSDictionary *reloadPreferences;
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
+ (BOOL)deviceUnlocked { return testUnlocked; } // These SpringBoard gates must not block a UIKit host app.
- (BOOL)isVisible { return testPanelVisible; }
@end
@interface DXPrefsManager ()
@property(nonatomic, readwrite) BOOL preferencesAvailable;
@end
@implementation DXPrefsManager
+ (instancetype)sharedInstance { static DXPrefsManager *manager; if (!manager) manager = [self new]; return manager; }
- (void)reload { if (reloadPreferences) { self.prefs = reloadPreferences; self.preferencesAvailable = YES; } }
@end
#include "StatusDoubles.inc"
@implementation UIApplication
+ (instancetype)sharedApplication { static UIApplication *app; if (!app) app = [self new]; return app; }
@end
@implementation UIView (StatusBarLifecycleTests)
- (void)didMoveToWindow {}
@end
@implementation UIWindow (StatusBarTests)
- (id)screen { return objc_getAssociatedObject(self, @selector(screen)); }
- (void)setScreen:(id)value { objc_setAssociatedObject(self, @selector(screen), value, OBJC_ASSOCIATION_RETAIN_NONATOMIC); }
- (BOOL)isKeyWindow { return [objc_getAssociatedObject(self, @selector(isKeyWindow)) boolValue]; }
- (void)setKeyWindow:(BOOL)value { objc_setAssociatedObject(self, @selector(isKeyWindow), @(value), OBJC_ASSOCIATION_RETAIN_NONATOMIC); }
- (CGFloat)windowLevel { return [objc_getAssociatedObject(self, @selector(windowLevel)) doubleValue]; }
- (void)setWindowLevel:(CGFloat)value { objc_setAssociatedObject(self, @selector(windowLevel), @(value), OBJC_ASSOCIATION_RETAIN_NONATOMIC); }
@end
@implementation UIWindowScene (StatusBarTests)
- (UIInterfaceOrientation)interfaceOrientation { return [objc_getAssociatedObject(self, @selector(interfaceOrientation)) integerValue]; }
- (void)setInterfaceOrientation:(UIInterfaceOrientation)value { objc_setAssociatedObject(self, @selector(interfaceOrientation), @(value), OBJC_ASSOCIATION_RETAIN_NONATOMIC); }
- (NSArray *)windows { return objc_getAssociatedObject(self, @selector(windows)); }
- (void)setWindows:(NSArray *)value { objc_setAssociatedObject(self, @selector(windows), value, OBJC_ASSOCIATION_COPY_NONATOMIC); }
@end
@implementation UITouch (StatusBarTests)
- (NSUInteger)tapCount { return [objc_getAssociatedObject(self, @selector(tapCount)) unsignedIntegerValue]; }
- (void)setTapCount:(NSUInteger)value { objc_setAssociatedObject(self, @selector(tapCount), @(value), OBJC_ASSOCIATION_RETAIN_NONATOMIC); }
@end
@implementation UIGestureRecognizer (StatusBarTests)
- (BOOL)delaysTouchesEnded { return [objc_getAssociatedObject(self, @selector(delaysTouchesEnded)) boolValue]; }
- (void)setDelaysTouchesEnded:(BOOL)value { objc_setAssociatedObject(self, @selector(delaysTouchesEnded), @(value), OBJC_ASSOCIATION_RETAIN_NONATOMIC); }
- (void)requireGestureRecognizerToFail:(UIGestureRecognizer *)gesture { (void)gesture; }
@end
@implementation UITapGestureRecognizer
- (instancetype)init { if ((self = [super init])) { self.enabled = YES; _numberOfTapsRequired = 1; _numberOfTouchesRequired = 1; } return self; }
- (instancetype)initWithTarget:(id)target action:(SEL)action {
    if ((self = [super initWithTarget:target action:action])) { _numberOfTapsRequired = 1; _numberOfTouchesRequired = 1; } return self;
}
@end
@implementation UILongPressGestureRecognizer @end
@implementation _UIStatusBarActionGestureRecognizer @end
@implementation STUIStatusBarActionGestureRecognizer @end
@implementation UIImpactFeedbackGenerator
- (instancetype)initWithStyle:(UIImpactFeedbackStyle)style { (void)style; return [super init]; }
- (void)impactOccurred {}
@end
@implementation UIStatusBar_Base @end
@implementation UIStatusBar @end
@implementation UIStatusBar_Modern @end
@implementation _UIStatusBar @end
@implementation SBSystemApertureContainerView @end
@implementation SBHomeScreenWindow @end
#include "StatusHandler.inc"
static NSMutableDictionary<NSString *, NSNumber *> *hookInstallCounts;
static void DXTestInstallHook(NSString *group, Class cls) {
    check([cls isSubclassOfClass:UIView.class], @"hook registration only receives a view class");
    hookInstallCounts[NSStringFromClass(cls)] = @([hookInstallCounts[NSStringFromClass(cls)] unsignedIntegerValue] + 1);
    (void)group;
}
#include "StatusHookInstaller.inc"
@interface DXStatusGestureHandler (ArbitrationRegression)
- (BOOL)gestureRecognizer:(UIGestureRecognizer *)gesture shouldBeRequiredToFailByGestureRecognizer:(UIGestureRecognizer *)other;
@end
static BOOL nativeTapWaits(DXStatusGestureHandler *handler, UIGestureRecognizer *gesture, UIGestureRecognizer *native) {
    return [handler respondsToSelector:@selector(gestureRecognizer:shouldBeRequiredToFailByGestureRecognizer:)] &&
        [handler gestureRecognizer:gesture shouldBeRequiredToFailByGestureRecognizer:native];
}
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
            bindings[DXStatusBarSlot(region, kind)] = @{@"enabled": @YES, @"selector": @"__typex_panel_test-common"};
        NSDictionary *baseline = @{kDXPanels: DXTestGesturePanels(), kDXStatusBarEnabled: @YES, kDXStatusBarBindings: bindings};
        DXPrefsManager *manager = DXPrefsManager.sharedInstance; manager.prefs = baseline; manager.preferencesAvailable = YES;
        DXStatusHandlers = nil; DXInstallStatusGestures(anchor); DXInstallStatusGestures(nested); DXInstallStatusGestures(anchor);
        check(DXStatusHandlers.count == 1, @"early lifecycle installation initializes the weak handler registry");
        DXStatusGestureHandler *handler = objc_getAssociatedObject(anchor, &DXStatusHandlerKey);
        check(handler != nil && window.gestureRecognizers.count == 4 && DXStatusHandlers.count == 1, @"nested views install once per anchor");
        check([handler available], @"app availability does not use SpringBoard lock/panel methods");
        UITapGestureRecognizer *nativeTap = [UITapGestureRecognizer new]; [nested addGestureRecognizer:nativeTap];
        UIGestureRecognizer *legacyAction = [[_UIStatusBarActionGestureRecognizer alloc] initWithTarget:nil action:NULL]; [nested addGestureRecognizer:legacyAction];
        UIGestureRecognizer *systemAction = [[STUIStatusBarActionGestureRecognizer alloc] initWithTarget:nil action:NULL]; [nested addGestureRecognizer:systemAction];
        UITapGestureRecognizer *lateWindowTap = [UITapGestureRecognizer new]; [window addGestureRecognizer:lateWindowTap];
        for (NSString *region in DXStatusBarRegions()) for (NSString *kind in DXStatusBarGestures()) {
            CGFloat x = [region isEqual:@"left"] ? 10 : ([region isEqual:@"middle"] ? 150 : 300);
            UIGestureRecognizer *gesture = gestureFor(handler, [kind hasSuffix:@"swipe"] ? @"horizontal" : kind);
            check(gesture.enabled, @"configured recognizer enabled");
            gesture.state = UIGestureRecognizerStatePossible;
            check([handler gestureRecognizer:gesture shouldReceiveTouch:touchFor(anchor, x)], @"configured touch accepted");
            if ([gesture isKindOfClass:UIPanGestureRecognizer.class]) ((UIPanGestureRecognizer *)gesture).delta = CGPointMake([kind isEqual:@"leftswipe"] ? -40 : 40, 0);
            check([handler gestureRecognizerShouldBegin:gesture], @"eligible gesture begins");
            check(nativeTapWaits(handler, gesture, legacyAction), @"UIKit status action waits for each configured gesture");
            check(nativeTapWaits(handler, gesture, systemAction), @"SystemStatusUI action waits for each configured gesture");
            if ([kind isEqual:@"tap"] || [kind isEqual:@"doubletap"]) {
                check(gesture.delaysTouchesBegan && gesture.delaysTouchesEnded, @"configured taps defer native view touch callbacks");
                check(nativeTapWaits(handler, gesture, nativeTap), @"descendant native single tap waits for configured tap in each region");
                check(nativeTapWaits(handler, gesture, lateWindowTap), @"late window native single tap also waits");
                check(!nativeTapWaits(handler, gesture, gestureFor(handler, @"longpress")), @"priority does not subordinate other TypeX gestures");
                check(!nativeTapWaits(handler, gesture, gestureFor(handler, @"horizontal")), @"priority does not subordinate swipes");
                nativeTap.numberOfTapsRequired = 2;
                check(!nativeTapWaits(handler, gesture, nativeTap), @"native double tap keeps its own behavior"); nativeTap.numberOfTapsRequired = 1;
                nativeTap.numberOfTouchesRequired = 2;
                check(!nativeTapWaits(handler, gesture, nativeTap), @"native multi-finger tap keeps its own behavior"); nativeTap.numberOfTouchesRequired = 1;
            }
            NSUInteger before = sends;
            gesture.state = [kind isEqual:@"longpress"] ? UIGestureRecognizerStateBegan : UIGestureRecognizerStateEnded;
            [handler recognized:gesture]; [handler recognized:gesture];
            check(sends == before + 1 && [sentSlot isEqual:DXStatusBarSlot(region, kind)] && [sentSelector isEqual:@"__typex_panel_test-common"] && !sentLandscape, @"one relay for each of fifteen slots");
        }
        UIGestureRecognizer *tap = gestureFor(handler, @"tap"); NSUInteger before = sends;
        check(!nativeTapWaits(handler, tap, nativeTap), @"dispatched session cannot take native-tap priority");
        check([handler gestureRecognizer:tap shouldReceiveTouch:touchFor(anchor, 10)], @"start pending touch");
        check([handler gestureRecognizer:tap shouldRequireFailureOfGestureRecognizer:gestureFor(handler, @"doubletap")], @"single tap waits for a configured double tap in the touched region");
        manager.prefs = @{}; tap.state = UIGestureRecognizerStateEnded; [handler recognized:tap];
        check(!nativeTapWaits(handler, tap, nativeTap), @"changed binding restores native priority");
        check(sends == before, @"changed configuration cancels pending action"); manager.prefs = baseline;
        check([handler gestureRecognizer:tap shouldReceiveTouch:touchFor(anchor, 10)], @"start before refresh"); [handler refresh]; [handler recognized:tap];
        check(sends == before, @"refresh clears old touch session");
        check(!nativeTapWaits(handler, tap, nativeTap), @"refresh clears pending priority too");
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
        NSMutableDictionary *singleOnly = [baseline mutableCopy];
        singleOnly[kDXStatusBarBindings] = @{@"left.tap": bindings[@"left.tap"], @"middle.tap": bindings[@"middle.tap"]};
        manager.prefs = singleOnly; [handler refresh];
        for (NSString *region in @[@"left", @"middle"]) {
            CGFloat x = [region isEqual:@"left"] ? 10 : 150;
            check([handler gestureRecognizer:tap shouldReceiveTouch:touchFor(anchor, x)], @"single-only configured region receives tap");
            check(![handler gestureRecognizer:tap shouldRequireFailureOfGestureRecognizer:gestureFor(handler, @"doubletap")], @"disabled double tap does not delay single tap");
            check(nativeTapWaits(handler, tap, nativeTap), @"single-only configured region takes priority");
            NSUInteger sentBefore = sends; tap.state = UIGestureRecognizerStateEnded; [handler recognized:tap];
            check(sends == sentBefore + 1 && [sentSlot isEqual:DXStatusBarSlot(region, @"tap")], @"single-only tap dispatches its own slot");
        }
        check(![handler gestureRecognizer:tap shouldReceiveTouch:touchFor(anchor, 300)], @"unconfigured right region leaves native tap alone");
        check(!nativeTapWaits(handler, tap, nativeTap), @"unconfigured region has no failure priority");
        check(!nativeTapWaits(handler, tap, legacyAction), @"unconfigured region keeps UIKit status action");
        check(!nativeTapWaits(handler, tap, systemAction), @"unconfigured region keeps SystemStatusUI action");
        manager.prefs = baseline; [handler refresh];
        check([handler gestureRecognizer:tap shouldReceiveTouch:touchFor(anchor, 10)], @"new configured touch for system pan test");
        UIPanGestureRecognizer *verticalSystem = [[UIPanGestureRecognizer alloc] initWithTarget:nil action:NULL]; [window addGestureRecognizer:verticalSystem];
        check(!nativeTapWaits(handler, tap, verticalSystem), @"vertical system gestures never wait for TypeX tap");
        [window removeGestureRecognizer:verticalSystem];
        UIControl *nativeControl = [UIControl new]; [anchor addSubview:nativeControl];
        UITouch *control = touchFor(anchor, 10); control.view = nativeControl;
        check(![handler gestureRecognizer:tap shouldReceiveTouch:control], @"native controls excluded");
        check(!nativeTapWaits(handler, tap, nativeTap), @"rejected native control clears the previous priority session");
        check(!nativeTapWaits(handler, tap, legacyAction), @"rejected native controls keep status action");
        anchor.hidden = YES; check(![handler available], @"hidden status bar blocked"); anchor.hidden = NO;
        manager.preferencesAvailable = NO; check(![handler available], @"missing snapshot blocked"); manager.preferencesAvailable = YES;
        [nested removeGestureRecognizer:legacyAction]; [nested removeGestureRecognizer:systemAction];
        anchor.window = nil; DXInstallStatusGestures(anchor);
        check(window.gestureRecognizers.count == 1 && window.gestureRecognizers[0] == lateWindowTap && !objc_getAssociatedObject(anchor, &DXStatusHandlerKey), @"detach removes only TypeX recognizers");

        NSString *originalProcess = [NSProcessInfo.processInfo.processName copy]; NSProcessInfo.processInfo.processName = @"SpringBoard";
        testUnlocked = YES; testPanelVisible = NO; manager.prefs = baseline;
        UIWindow *islandWindow = [UIWindow new]; islandWindow.window = islandWindow; islandWindow.bounds = CGRectMake(0, 0, 390, 844);
        SBSystemApertureContainerView *island = [SBSystemApertureContainerView new]; island.bounds = CGRectMake(0, 0, 140, 44);
        island.originInWindow = CGPointMake(125, 10); [islandWindow addSubview:island];
        SBSystemApertureContainerView *islandChild = [SBSystemApertureContainerView new]; [island addSubview:islandChild];
        UIControl *islandControl = [UIControl new]; [island addSubview:islandControl];
        UITapGestureRecognizer *islandNativeTap = [UITapGestureRecognizer new]; [islandControl addGestureRecognizer:islandNativeTap];
        DXInstallStatusGestures(island); DXInstallStatusGestures(islandChild);
        DXStatusGestureHandler *islandHandler = objc_getAssociatedObject(islandWindow, &DXStatusApertureHandlerKey);
        check(islandHandler.aperture && islandHandler.recognizers.count == 1 && islandWindow.gestureRecognizers.count == 1, @"nested Dynamic Island views install only one tap recognizer");
        UIGestureRecognizer *islandTap = gestureFor(islandHandler, @"tap");
        UIStatusBar *islandStatusBar = [UIStatusBar new]; islandStatusBar.bounds = CGRectMake(0, 0, 390, 54); [islandWindow addSubview:islandStatusBar];
        DXInstallStatusGestures(islandStatusBar);
        DXStatusGestureHandler *ordinaryHandler = objc_getAssociatedObject(islandStatusBar, &DXStatusHandlerKey);
        UITouch *sharedIslandTouch = touchFor(island, 70); sharedIslandTouch.view = islandControl;
        check(![ordinaryHandler gestureRecognizer:gestureFor(ordinaryHandler, @"tap") shouldReceiveTouch:sharedIslandTouch], @"ordinary status-bar handler rejects an island touch in the same window");
        for (NSNumber *x in @[@5, @70, @135]) {
            UITouch *touch = touchFor(island, x.doubleValue); touch.view = islandControl;
            check([islandHandler gestureRecognizer:islandTap shouldReceiveTouch:touch], @"configured island tap accepts hosted controls");
            check(nativeTapWaits(islandHandler, islandTap, islandNativeTap), @"island native single tap waits for configured action");
            NSUInteger sentBefore = sends; islandTap.state = UIGestureRecognizerStateEnded; [islandHandler recognized:islandTap]; [islandHandler recognized:islandTap];
            check(sends == sentBefore + 1 && [sentSlot isEqual:@"middle.tap"], @"all island content maps to one middle single-tap dispatch");
        }
        manager.prefs = @{kDXPanels: DXTestGesturePanels(), kDXStatusBarEnabled: @YES, kDXStatusBarBindings: @{@"left.tap": bindings[@"left.tap"]}};
        [islandHandler refresh];
        check(!islandTap.enabled && ![islandHandler gestureRecognizer:islandTap shouldReceiveTouch:touchFor(island, 70)], @"unconfigured middle tap keeps native island behavior");
        check(!nativeTapWaits(islandHandler, islandTap, islandNativeTap), @"unconfigured island never takes native priority");
        manager.prefs = baseline; [islandHandler refresh];
        testUnlocked = NO; check(![islandHandler available], @"island action blocked while locked"); testUnlocked = YES;
        testPanelVisible = YES; check(![islandHandler available], @"island action blocked while global panel visible"); testPanelVisible = NO;
        UITouch *outside = touchFor(island, 70); outside.view = islandWindow;
        check(![islandHandler gestureRecognizer:islandTap shouldReceiveTouch:outside], @"island handler never accepts unrelated window content");
        // A second container instance in the same window (presentation swap)
        // resolves at touch time and must not stack another gesture set.
        SBSystemApertureContainerView *islandSwap = [SBSystemApertureContainerView new]; islandSwap.bounds = island.bounds;
        islandSwap.originInWindow = island.originInWindow; [islandWindow addSubview:islandSwap];
        UIControl *swapControl = [UIControl new]; [islandSwap addSubview:swapControl];
        DXInstallStatusGestures(islandSwap);
        check(!objc_getAssociatedObject(islandSwap, &DXStatusHandlerKey) && islandWindow.gestureRecognizers.count == 5, @"second island instance reuses the window gesture set");
        UITapGestureRecognizer *swapNativeTap = [UITapGestureRecognizer new]; [swapControl addGestureRecognizer:swapNativeTap];
        UITouch *swapTouch = touchFor(islandSwap, 70); swapTouch.view = swapControl;
        check([islandHandler gestureRecognizer:islandTap shouldReceiveTouch:swapTouch], @"the window gesture accepts a swapped container's touch");
        check(nativeTapWaits(islandHandler, islandTap, swapNativeTap), @"swapped container's native tap uses the current receiver");
        islandSwap.hidden = YES;
        check(![islandHandler gestureRecognizer:islandTap shouldReceiveTouch:swapTouch], @"hidden swapped receiver rejected"); islandSwap.hidden = NO;
        check([islandHandler gestureRecognizer:islandTap shouldReceiveTouch:swapTouch], @"visible swapped receiver accepted");
        NSUInteger invalidBefore = sends; islandSwap.window = nil; islandTap.state = UIGestureRecognizerStateEnded; [islandHandler recognized:islandTap];
        check(sends == invalidBefore, @"detached touch receiver cancels pending island session"); islandSwap.window = islandWindow;
        check([islandHandler gestureRecognizer:islandTap shouldReceiveTouch:touchFor(island, 70)], @"start island touch before layout change");
        NSUInteger sentBefore = sends; island.originInWindow = CGPointMake(126, 10); [islandHandler recognized:islandTap];
        check(sends == sentBefore + 1 && [sentSlot isEqual:@"middle.tap"], @"island sessions ride window identity, not anchor frames");
        island.window = nil; DXInstallStatusGestures(island);
        check(islandWindow.gestureRecognizers.count == 5, @"island detach preserves window-owned tap for replacement container");
        check([islandHandler available], @"released island anchor does not gate the window gesture");
        check([islandHandler gestureRecognizer:islandTap shouldReceiveTouch:swapTouch], @"window gesture still serves the swapped container");
        islandStatusBar.window = nil; DXInstallStatusGestures(islandStatusBar);
        check(islandWindow.gestureRecognizers.count == 1, @"ordinary detach preserves independent island recognizer");

        // No strong local reference to the handler or install-time container:
        // the original test hid this lifetime bug by retaining islandHandler.
        __weak DXStatusGestureHandler *weakIslandHandler;
        __weak UIView *weakOriginalIsland;
        __weak DXStatusGestureHandler *releasedWithWindow;
        @autoreleasepool {
            UIWindow *lifetimeWindow = [UIWindow new]; lifetimeWindow.window = lifetimeWindow; lifetimeWindow.bounds = window.bounds;
            SBSystemApertureContainerView *replacement = [SBSystemApertureContainerView new]; replacement.bounds = CGRectMake(0, 0, 140, 44);
            @autoreleasepool {
                SBSystemApertureContainerView *original = [SBSystemApertureContainerView new]; original.bounds = replacement.bounds;
                [lifetimeWindow addSubview:original]; DXInstallStatusGestures(original);
                for (DXStatusGestureHandler *entry in DXStatusHandlers.allObjects)
                    if (entry.aperture && entry.window == lifetimeWindow) weakIslandHandler = entry;
                weakOriginalIsland = original;
                [lifetimeWindow addSubview:replacement]; DXInstallStatusGestures(replacement);
                [lifetimeWindow.subviews removeObject:original]; original.superview = nil; original.window = nil;
                DXInstallStatusGestures(original);
            }
            check(!weakOriginalIsland && weakIslandHandler && lifetimeWindow.gestureRecognizers.count == 1, @"original container release preserves shared window handler");
            UIGestureRecognizer *replacementTap = lifetimeWindow.gestureRecognizers.firstObject;
            check([weakIslandHandler gestureRecognizer:replacementTap shouldReceiveTouch:touchFor(replacement, 70)], @"replacement responds without another install or scan");
            NSUInteger lifetimeBefore = sends; replacementTap.state = UIGestureRecognizerStateEnded; [weakIslandHandler recognized:replacementTap];
            check(sends == lifetimeBefore + 1, @"replacement dispatches after install-time container is gone");
            releasedWithWindow = weakIslandHandler;
        }
        check(!releasedWithWindow, @"window release releases its handler without a retain cycle");
        NSProcessInfo.processInfo.processName = originalProcess;
        check(!DXIsApertureView(island), @"island hooks do not activate in host apps");

        // Runtime hierarchy from iOS 17: neither SystemStatusUI class inherits
        // UIStatusBar, UIStatusBar_Modern, or _UIStatusBar. Load them only after
        // the initial hook attempt, then exercise scanning and retries.
        hookInstallCounts = [NSMutableDictionary dictionary];
        check(!NSClassFromString(@"STUIStatusBar_Wrapper") && !NSClassFromString(@"STUIStatusBar"), @"SystemStatusUI initially unavailable");
        UIApplication.sharedApplication.windows = @[];
        DXTryStatusHooks();
        check([hookInstallCounts[@"UIStatusBar"] unsignedIntegerValue] == 1 &&
              [hookInstallCounts[@"UIStatusBar_Modern"] unsignedIntegerValue] == 1 &&
              [hookInstallCounts[@"_UIStatusBar"] unsignedIntegerValue] == 1, @"UIKit hooks remain available before SystemStatusUI loads");

        // A UIKit status bar can exist before preferences and only belong to
        // a connected scene, outside UIApplication's legacy windows array.
        UIWindow *sceneWindow = [UIWindow new]; sceneWindow.window = sceneWindow; sceneWindow.bounds = window.bounds;
        UIStatusBar *sceneBar = [UIStatusBar new]; sceneBar.bounds = anchor.bounds; [sceneWindow addSubview:sceneBar];
        manager.preferencesAvailable = NO; manager.prefs = @{}; DXInstallStatusGestures(sceneBar);
        DXStatusGestureHandler *sceneHandler = objc_getAssociatedObject(sceneBar, &DXStatusHandlerKey);
        UIGestureRecognizer *sceneTap = gestureFor(sceneHandler, @"tap"); check(!sceneTap.enabled, @"cold unavailable configuration leaves recognizer disabled");
        UIWindowScene *connectedScene = [UIWindowScene new]; connectedScene.windows = @[sceneWindow];
        sceneWindow.windowScene = connectedScene; UIApplication.sharedApplication.connectedScenes = [NSSet setWithObject:connectedScene];
        UIWindow *unscannedWindow = [UIWindow new]; unscannedWindow.window = unscannedWindow; unscannedWindow.bounds = window.bounds;
        UIStatusBar *unscannedBar = [UIStatusBar new]; unscannedBar.bounds = anchor.bounds; [unscannedWindow addSubview:unscannedBar];
        connectedScene.windows = @[sceneWindow, unscannedWindow];
        reloadPreferences = baseline; DXTryStatusHooks(); reloadPreferences = nil;
        check(unscannedWindow.gestureRecognizers.count == 4 && objc_getAssociatedObject(unscannedBar, &DXStatusHandlerKey), @"connected scene scan discovers an existing unhooked status bar");
        check(sceneTap.enabled && [sceneHandler gestureRecognizer:sceneTap shouldReceiveTouch:touchFor(sceneBar, 10)], @"late preferences recover already installed scene-only recognizer");
        NSUInteger sceneBefore = sends; sceneTap.state = UIGestureRecognizerStateEnded; [sceneHandler recognized:sceneTap];
        check(sends == sceneBefore + 1, @"scene-only UIKit status bar dispatches after cold configuration recovery");
        UIApplication.sharedApplication.connectedScenes = nil; sceneBar.window = nil; DXInstallStatusGestures(sceneBar);
        unscannedBar.window = nil; DXInstallStatusGestures(unscannedBar);

        // Child-first didMoveToWindow order must not leave two competing sets.
        UIWindow *orderedWindow = [UIWindow new]; orderedWindow.window = orderedWindow; orderedWindow.bounds = window.bounds;
        _UIStatusBar *earlyCore = [_UIStatusBar new]; earlyCore.bounds = anchor.bounds; [orderedWindow addSubview:earlyCore]; DXInstallStatusGestures(earlyCore);
        DXStatusGestureHandler *earlyHandler = objc_getAssociatedObject(earlyCore, &DXStatusHandlerKey);
        UIGestureRecognizer *earlyTap = gestureFor(earlyHandler, @"tap");
        check([earlyHandler gestureRecognizer:earlyTap shouldReceiveTouch:touchFor(earlyCore, 10)], @"core begins session before wrapper arrival");
        UIStatusBar *lateWrapper = [UIStatusBar new]; lateWrapper.bounds = anchor.bounds; [orderedWindow addSubview:lateWrapper];
        DXInstallStatusGestures(lateWrapper);
        check(orderedWindow.gestureRecognizers.count == 8, @"separate status views initially own separate sets");
        [orderedWindow.subviews removeObject:earlyCore]; [lateWrapper addSubview:earlyCore]; DXInstallStatusGestures(earlyCore);
        check(orderedWindow.gestureRecognizers.count == 4 && !objc_getAssociatedObject(earlyCore, &DXStatusHandlerKey), @"wrapper arrival retires earlier core set");
        NSUInteger orderBefore = sends; earlyTap.state = UIGestureRecognizerStateEnded; [earlyHandler recognized:earlyTap];
        check(sends == orderBefore && !earlyTap.enabled && !earlyTap.delegate, @"retired core cannot execute pending session");
        DXStatusGestureHandler *lateHandler = objc_getAssociatedObject(lateWrapper, &DXStatusHandlerKey);
        UIGestureRecognizer *lateTap = gestureFor(lateHandler, @"tap");
        check([lateHandler gestureRecognizer:lateTap shouldReceiveTouch:touchFor(earlyCore, 10)], @"wrapper receives nested core touch after consolidation");
        lateTap.state = UIGestureRecognizerStateEnded; [lateHandler recognized:lateTap];
        check(sends == orderBefore + 1, @"consolidated wrapper dispatches once");
        lateWrapper.window = nil; DXInstallStatusGestures(lateWrapper);

        UIWindow *oldCoreWindow = [UIWindow new]; oldCoreWindow.window = oldCoreWindow; oldCoreWindow.bounds = window.bounds;
        _UIStatusBar *movingCore = [_UIStatusBar new]; movingCore.bounds = anchor.bounds; [oldCoreWindow addSubview:movingCore]; DXInstallStatusGestures(movingCore);
        UIStatusBar *newWrapper = [UIStatusBar new]; newWrapper.bounds = anchor.bounds; [orderedWindow addSubview:newWrapper]; DXInstallStatusGestures(newWrapper);
        [oldCoreWindow.subviews removeObject:movingCore]; [newWrapper addSubview:movingCore]; DXInstallStatusGestures(movingCore);
        check(oldCoreWindow.gestureRecognizers.count == 0 && orderedWindow.gestureRecognizers.count == 4 && !objc_getAssociatedObject(movingCore, &DXStatusHandlerKey), @"cross-window reparent also removes the old core's recognizers");
        newWrapper.window = nil; DXInstallStatusGestures(newWrapper);
        Class systemWrapperClass = objc_allocateClassPair(UIStatusBar_Base.class, "STUIStatusBar_Wrapper", 0);
        Class systemCoreClass = objc_allocateClassPair(UIView.class, "STUIStatusBar", 0);
        objc_registerClassPair(systemWrapperClass); objc_registerClassPair(systemCoreClass);
        check(![systemWrapperClass isSubclassOfClass:UIStatusBar.class] && ![systemCoreClass isSubclassOfClass:_UIStatusBar.class], @"SystemStatusUI test hierarchy is independent of legacy implementations");
        for (NSString *process in @[@"SpringBoard", @"Preferences", @"MobileSafari"]) {
            NSProcessInfo.processInfo.processName = process;
            UIApplication.sharedApplication.applicationState = UIApplicationStateActive;
            UIWindow *hostWindow = [UIWindow new]; hostWindow.window = hostWindow; hostWindow.bounds = CGRectMake(0, 0, 390, 844);
            UIView *systemWrapper = [systemWrapperClass new]; systemWrapper.bounds = CGRectMake(0, 0, 390, 54); [hostWindow addSubview:systemWrapper];
            UIView *systemCore = [systemCoreClass new]; systemCore.bounds = systemWrapper.bounds; [systemWrapper addSubview:systemCore];
            check(DXIsStatusView(systemWrapper) && DXIsStatusView(systemCore), @"SystemStatusUI wrapper and core accepted");
            UIApplication.sharedApplication.windows = @[hostWindow]; DXTryStatusHooks(); DXTryStatusHooks();
            DXStatusGestureHandler *systemHandler = objc_getAssociatedObject(systemWrapper, &DXStatusHandlerKey);
            check(systemHandler && hostWindow.gestureRecognizers.count == 4 &&
                  !objc_getAssociatedObject(systemCore, &DXStatusHandlerKey), @"scan installs one set for nested SystemStatusUI views across hosts");
            check([hookInstallCounts[@"STUIStatusBar_Wrapper"] unsignedIntegerValue] == 1 &&
                  [hookInstallCounts[@"STUIStatusBar"] unsignedIntegerValue] == 1, @"late SystemStatusUI hooks register exactly once");
            for (NSString *region in DXStatusBarRegions()) for (NSString *kind in DXStatusBarGestures()) {
                CGFloat x = [region isEqual:@"left"] ? 10 : ([region isEqual:@"middle"] ? 150 : 300);
                UIGestureRecognizer *gesture = gestureFor(systemHandler, [kind hasSuffix:@"swipe"] ? @"horizontal" : kind);
                check([systemHandler gestureRecognizer:gesture shouldReceiveTouch:touchFor(systemCore, x)], @"SystemStatusUI touch accepted in each host");
                if ([gesture isKindOfClass:UIPanGestureRecognizer.class]) ((UIPanGestureRecognizer *)gesture).delta = CGPointMake([kind isEqual:@"leftswipe"] ? -40 : 40, 0);
                check([systemHandler gestureRecognizerShouldBegin:gesture], @"SystemStatusUI gesture can begin");
                NSUInteger sentBefore = sends;
                gesture.state = [kind isEqual:@"longpress"] ? UIGestureRecognizerStateBegan : UIGestureRecognizerStateEnded;
                [systemHandler recognized:gesture]; [systemHandler recognized:gesture];
                check(sends == sentBefore + 1 && [sentSlot isEqual:DXStatusBarSlot(region, kind)], @"SystemStatusUI dispatches each slot exactly once");
            }
            UIView *unrelated = [UIView new]; unrelated.bounds = systemWrapper.bounds; [hostWindow addSubview:unrelated];
            DXInstallStatusGestures(unrelated);
            check(!objc_getAssociatedObject(unrelated, &DXStatusHandlerKey) && hostWindow.gestureRecognizers.count == 4, @"unrelated views do not install status gestures");
            UIGestureRecognizer *systemTap = gestureFor(systemHandler, @"tap");
            check([systemHandler gestureRecognizer:systemTap shouldReceiveTouch:touchFor(systemCore, 10)], @"start SystemStatusUI session before window switch");
            NSUInteger sentBefore = sends;
            UIWindow *replacementWindow = [UIWindow new]; replacementWindow.window = replacementWindow; replacementWindow.bounds = hostWindow.bounds;
            systemWrapper.window = replacementWindow; systemCore.window = replacementWindow;
            DXInstallStatusGestures(systemWrapper); [systemHandler recognized:systemTap];
            check(sends == sentBefore && hostWindow.gestureRecognizers.count == 0 && replacementWindow.gestureRecognizers.count == 4, @"window switch removes old gestures and cancels old session");
            DXStatusGestureHandler *replacementHandler = objc_getAssociatedObject(systemWrapper, &DXStatusHandlerKey);
            systemTap = gestureFor(replacementHandler, @"tap");
            check([replacementHandler gestureRecognizer:systemTap shouldReceiveTouch:touchFor(systemCore, 10)], @"replacement SystemStatusUI window receives touches");
            systemTap.state = UIGestureRecognizerStateEnded; [replacementHandler recognized:systemTap];
            check(sends == sentBefore + 1 && [sentSlot isEqual:@"left.tap"], @"replacement SystemStatusUI window dispatches");
            systemWrapper.window = nil; DXInstallStatusGestures(systemWrapper);
            check(replacementWindow.gestureRecognizers.count == 0, @"SystemStatusUI detach cleans recognizers");
        }
        // Home-screen touches can land in a different window from the visible
        // status-bar renderer. Previous tests always equated those windows.
        NSProcessInfo.processInfo.processName = @"SpringBoard"; manager.prefs = baseline;
        UIWindow *displayWindow = [UIWindow new]; displayWindow.window = displayWindow; displayWindow.bounds = window.bounds;
        UIStatusBar *desktopBar = [UIStatusBar new]; desktopBar.bounds = CGRectMake(0, 0, 390, 54); [displayWindow addSubview:desktopBar]; DXInstallStatusGestures(desktopBar);
        SBHomeScreenWindow *homeWindow = [SBHomeScreenWindow new]; homeWindow.window = homeWindow; homeWindow.bounds = window.bounds; homeWindow.keyWindow = YES;
        NSObject *mainScreen = [NSObject new]; homeWindow.screen = mainScreen; displayWindow.screen = mainScreen;
        UIView *homeContent = [UIView new]; [homeWindow addSubview:homeContent];
        DXScanStatusViews(homeWindow);
        DXStatusGestureHandler *homeHandler;
        for (DXStatusGestureHandler *entry in DXStatusHandlers.allObjects) if (entry.window == homeWindow) homeHandler = entry;
        check(homeHandler && homeWindow.gestureRecognizers.count == 4, @"desktop touch window owns a status-bar gesture set");
        homeWindow.keyWindow = NO;
        check(![homeHandler available], @"unobserved non-key desktop window waits for appearance");
        DXStatusBarHomeScreenDidAppear(homeWindow);
        check([homeHandler available], @"observed desktop appearance activates a non-key touch window");
        homeWindow.keyWindow = YES;
        for (NSString *region in DXStatusBarRegions()) for (NSString *kind in DXStatusBarGestures()) {
            CGFloat x = [region isEqual:@"left"] ? 10 : ([region isEqual:@"middle"] ? 150 : 300);
            UITouch *homeTouch = touchFor(desktopBar, x); homeTouch.view = homeContent; homeTouch.window = homeWindow;
            UIGestureRecognizer *gesture = gestureFor(homeHandler, [kind hasSuffix:@"swipe"] ? @"horizontal" : kind);
            check([homeHandler gestureRecognizer:gesture shouldReceiveTouch:homeTouch], @"desktop pass-through touch accepted in displayed status-bar bounds");
            if ([gesture isKindOfClass:UIPanGestureRecognizer.class]) ((UIPanGestureRecognizer *)gesture).delta = CGPointMake([kind isEqual:@"leftswipe"] ? -40 : 40, 0);
            check([homeHandler gestureRecognizerShouldBegin:gesture], @"desktop configured gesture begins");
            NSUInteger desktopBefore = sends;
            gesture.state = [kind isEqual:@"longpress"] ? UIGestureRecognizerStateBegan : UIGestureRecognizerStateEnded;
            [homeHandler recognized:gesture]; [homeHandler recognized:gesture];
            check(sends == desktopBefore + 1 && [sentSlot isEqual:DXStatusBarSlot(region, kind)], @"desktop pass-through dispatches each slot exactly once");
        }
        DXStatusBarHomeScreenDidAppear(homeWindow); DXStatusBarHomeScreenDidAppear(homeWindow);
        check(homeWindow.gestureRecognizers.count == 4, @"desktop appearance and repeated scans do not stack recognizers");
        UIGestureRecognizer *homeTap = gestureFor(homeHandler, @"tap");
        UITouch *homeTouch = touchFor(desktopBar, 10); homeTouch.window = homeWindow; homeTouch.view = homeContent;
        UITapGestureRecognizer *desktopNativeTap = [UITapGestureRecognizer new]; desktopNativeTap.numberOfTapsRequired = 1; desktopNativeTap.numberOfTouchesRequired = 1;
        [homeContent addGestureRecognizer:desktopNativeTap];
        check([homeHandler gestureRecognizer:homeTap shouldReceiveTouch:homeTouch] &&
              [homeHandler gestureRecognizer:homeTap shouldBeRequiredToFailByGestureRecognizer:desktopNativeTap], @"desktop native content tap waits on configured status-bar touch");
        UIPanGestureRecognizer *desktopNativePan = [UIPanGestureRecognizer new]; [homeContent addGestureRecognizer:desktopNativePan];
        check(![homeHandler gestureRecognizer:homeTap shouldBeRequiredToFailByGestureRecognizer:desktopNativePan], @"desktop vertical/system pan gets no tap failure priority");
        homeTouch.point = CGPointMake(10, 54);
        check(![homeHandler gestureRecognizer:homeTap shouldReceiveTouch:homeTouch], @"desktop content below actual status bar excluded"); homeTouch.point = CGPointMake(10, 12);
        UIControl *desktopControl = [UIControl new]; [homeWindow addSubview:desktopControl]; homeTouch.view = desktopControl;
        check(![homeHandler gestureRecognizer:homeTap shouldReceiveTouch:homeTouch], @"desktop native control excluded");
        SBIconView *desktopIcon = [SBIconView new]; [homeWindow addSubview:desktopIcon]; homeTouch.view = desktopIcon;
        check(![homeHandler gestureRecognizer:homeTap shouldReceiveTouch:homeTouch], @"desktop icons excluded even when overlapping status bar"); homeTouch.view = homeContent;
        homeWindow.keyWindow = NO; check([homeHandler gestureRecognizer:homeTap shouldReceiveTouch:homeTouch], @"visible desktop does not require key-window role"); homeWindow.keyWindow = YES;
        testUnlocked = NO; check(![homeHandler available], @"locked desktop excluded"); testUnlocked = YES;
        testPanelVisible = YES; check(![homeHandler available], @"desktop excluded while panel visible"); testPanelVisible = NO;
        homeWindow.windowScene = [UIWindowScene new]; homeWindow.windowScene.activationState = UISceneActivationStateBackground;
        check(![homeHandler available], @"inactive desktop scene excluded"); homeWindow.windowScene = nil;
        displayWindow.screen = [NSObject new]; check(![homeHandler available], @"status bar from another screen excluded"); displayWindow.screen = mainScreen;
        desktopBar.hidden = YES; check(![homeHandler available], @"hidden displayed status bar excluded"); desktopBar.hidden = NO;
        check([homeHandler gestureRecognizer:homeTap shouldReceiveTouch:homeTouch], @"start before desktop disappears");
        NSUInteger homeBefore = sends; homeTap.state = UIGestureRecognizerStateEnded; DXStatusBarHomeScreenWillDisappear(homeWindow); [homeHandler recognized:homeTap];
        check(sends == homeBefore && ![homeHandler available], @"desktop disappearance cancels old session even if window remains key");
        DXStatusBarHomeScreenDidAppear(homeWindow);
        check([homeHandler gestureRecognizer:homeTap shouldReceiveTouch:homeTouch], @"start before desktop hit view detaches");
        homeContent.window = nil; [homeHandler recognized:homeTap];
        check(sends == homeBefore, @"detached desktop touch view cancels old session"); homeContent.window = homeWindow;
        check([homeHandler gestureRecognizer:homeTap shouldReceiveTouch:homeTouch], @"start before display bar replacement");
        UIStatusBar *newDesktopBar = [UIStatusBar new]; newDesktopBar.bounds = desktopBar.bounds; [displayWindow addSubview:newDesktopBar];
        desktopBar.hidden = YES; DXInstallStatusGestures(newDesktopBar); [homeHandler recognized:homeTap];
        check(sends == homeBefore, @"display bar replacement cancels old receiver session");
        check([homeHandler gestureRecognizer:homeTap shouldReceiveTouch:homeTouch], @"new desktop touch resolves replacement display bar"); [homeHandler recognized:homeTap];
        check(sends == homeBefore + 1, @"replacement display bar continues dispatching through desktop receiver");
        NSMutableDictionary *desktopSingleOnly = [baseline mutableCopy]; desktopSingleOnly[kDXStatusBarBindings] = @{@"left.tap": bindings[@"left.tap"]}; manager.prefs = desktopSingleOnly; [homeHandler refresh];
        homeTouch.point = CGPointMake(300, 12);
        check(![homeHandler gestureRecognizer:homeTap shouldReceiveTouch:homeTouch], @"unconfigured desktop region keeps native touches"); manager.prefs = baseline; [homeHandler refresh]; homeTouch.point = CGPointMake(10, 12);
        UIStatusBar *inlineBar = [UIStatusBar new]; inlineBar.bounds = desktopBar.bounds; [homeWindow addSubview:inlineBar]; DXInstallStatusGestures(inlineBar);
        check(![homeHandler gestureRecognizer:homeTap shouldReceiveTouch:homeTouch], @"desktop fallback does not compete with same-window status handler");
        DXStatusGestureHandler *inlineHandler = objc_getAssociatedObject(inlineBar, &DXStatusHandlerKey);
        UIGestureRecognizer *inlineTap = gestureFor(inlineHandler, @"tap");
        check([inlineHandler gestureRecognizer:inlineTap shouldReceiveTouch:touchFor(inlineBar, 10)], @"normal same-window desktop status bar remains usable");
        homeBefore = sends; inlineTap.state = UIGestureRecognizerStateEnded; [inlineHandler recognized:inlineTap];
        check(sends == homeBefore + 1, @"same-window desktop path dispatches once"); inlineBar.window = nil; DXInstallStatusGestures(inlineBar);
        check(homeWindow.gestureRecognizers.count == 4 && [homeHandler gestureRecognizer:homeTap shouldReceiveTouch:homeTouch], @"fallback recovers after inline status bar detaches");
        NSProcessInfo.processInfo.processName = @"MobileSafari";
        check(!DXIsHomeScreenWindow(homeWindow), @"desktop fallback never activates in an app process");
        SBHomeScreenWindow *appHomeLookalike = [SBHomeScreenWindow new]; appHomeLookalike.window = appHomeLookalike; DXInstallStatusGestures(appHomeLookalike);
        check(appHomeLookalike.gestureRecognizers.count == 0, @"app lookalike cannot install desktop recognizers");
        NSProcessInfo.processInfo.processName = originalProcess; UIApplication.sharedApplication.windows = @[];
        printf("PASS: %lu production status-bar handler checks with UIKit doubles\n", (unsigned long)checks);
    }
    return 0;
}
