#import "DXStatusBarGestures.h"
#import "DXStatusBarGesturePolicy.h"
#import "DXSystemOpenBroker.h"
#import "DXGlobalPanel.h"
#import "DXGlobalPanelPolicy.h"
#import "DXKeyboardPanelPreferences.h"
#import "DXPanelRegistry.h"
#import "common.h"
#import <objc/runtime.h>
#import <notify.h>

static char DXStatusHandlerKey, DXStatusApertureHandlerKey, DXStatusHomeHandlerKey, DXStatusKindKey, DXStatusSessionKey;
static NSHashTable *DXStatusHandlers;
static void DXTryStatusHooks(void);
static void DXInstallStatusGestures(UIView *view);

static BOOL DXIsStatusView(UIView *view) {
    // iOS 17's system status bar uses SystemStatusUI classes that are siblings
    // of the UIKit implementations, rather than subclasses of them.
    for (NSString *name in @[@"UIStatusBar", @"UIStatusBar_Modern", @"_UIStatusBar",
                            @"STUIStatusBar_Wrapper", @"STUIStatusBar"]) {
        Class cls = NSClassFromString(name);
        if (cls && [cls isSubclassOfClass:UIView.class] && [view isKindOfClass:cls]) return YES;
    }
    return NO;
}
static BOOL DXIsApertureView(UIView *view) {
    if (![NSProcessInfo.processInfo.processName isEqual:@"SpringBoard"]) return NO;
    Class cls = NSClassFromString(@"SBSystemApertureContainerView");
    return cls && [cls isSubclassOfClass:UIView.class] && [view isKindOfClass:cls];
}
static BOOL DXIsHomeScreenWindow(UIView *view) {
    if (![NSProcessInfo.processInfo.processName isEqual:@"SpringBoard"]) return NO;
    Class cls = NSClassFromString(@"SBHomeScreenWindow");
    return cls && [cls isSubclassOfClass:UIWindow.class] && [view isKindOfClass:cls];
}
static BOOL DXIsStatusActionRecognizer(UIGestureRecognizer *gesture) {
    for (NSString *name in @[@"_UIStatusBarActionGestureRecognizer", @"STUIStatusBarActionGestureRecognizer"]) {
        Class cls = NSClassFromString(name);
        if (cls && [cls isSubclassOfClass:UIGestureRecognizer.class] && [gesture isKindOfClass:cls]) return YES;
    }
    return NO;
}
static BOOL DXStatusReceiverVisible(UIView *view, UIWindow *window) {
    if (!view || view.window != window) return NO;
    for (UIView *ancestor = view; ancestor; ancestor = ancestor.superview)
        if (ancestor.hidden || ancestor.alpha < 0.01) return NO;
    CGRect frame = [view convertRect:view.bounds toView:window];
    return !CGRectIsEmpty(frame) && !CGRectIsEmpty(CGRectIntersection(frame, window.bounds));
}

@interface DXStatusGestureSession : NSObject
@property(nonatomic, weak) UIWindow *window;
@property(nonatomic, weak) UIView *receiver;
@property(nonatomic, weak) UIView *touchView;
@property(nonatomic, copy) NSDictionary *preferences;
@property(nonatomic, copy) NSString *region;
@property(nonatomic, copy) NSString *horizontalDirection;
@property(nonatomic) CGRect frame;
@property(nonatomic) BOOL dispatched;
@end
@implementation DXStatusGestureSession @end

@interface DXStatusGestureHandler : NSObject <UIGestureRecognizerDelegate>
@property(nonatomic, weak) UIView *anchor;
@property(nonatomic, weak) UIWindow *window;
@property(nonatomic) BOOL aperture;
@property(nonatomic) BOOL homeScreen;
@property(nonatomic) BOOL homeAppearanceKnown;
@property(nonatomic) BOOL homeVisible;
@property(nonatomic, strong) NSArray<UIGestureRecognizer *> *recognizers;
@property(nonatomic, copy) NSString *lastRejection;
@property(nonatomic, copy) NSString *lastConfiguration;
- (void)refresh;
- (void)invalidate;
- (BOOL)available;
- (BOOL)reject:(NSString *)reason;
- (BOOL)hasAction:(NSString *)kind region:(NSString *)region preferences:(NSDictionary *)preferences;
- (BOOL)sessionIsCurrent:(DXStatusGestureSession *)session;
- (void)recognized:(UIGestureRecognizer *)gesture;
@end

static UIView *DXHomeStatusAnchor(UIWindow *homeWindow) {
    UIView *selected;
    // Resolve the displayed bar for every new touch; a desktop window is only
    // the touch receiver, never a substitute for status-bar geometry.
    for (DXStatusGestureHandler *handler in DXStatusHandlers.allObjects) {
        UIView *anchor = handler.anchor;
        UIWindow *displayWindow = anchor.window;
        if (handler.aperture || handler.homeScreen || !displayWindow || displayWindow.screen != homeWindow.screen ||
            !DXStatusReceiverVisible(anchor, displayWindow)) continue;
        // A bar already hosted by this window has its normal gesture set.
        // Installing the fallback as well must not dispatch the same touch.
        if (displayWindow == homeWindow) return nil;
        CGRect frame = [anchor convertRect:anchor.bounds toView:homeWindow];
        if (CGRectIsEmpty(CGRectIntersection(frame, homeWindow.bounds))) continue;
        if (!selected || displayWindow.windowLevel > selected.window.windowLevel) selected = anchor;
    }
    return selected;
}

@implementation DXStatusGestureHandler
- (BOOL)reject:(NSString *)reason {
    if (![self.lastRejection isEqual:reason])
        NSLog(@"[TypeX][StatusBarGesture] rejected host=%@ gate=%@", NSProcessInfo.processInfo.processName, reason);
    self.lastRejection = reason;
    return NO;
}
- (void)dealloc {
    UIWindow *window = _window;
    NSArray *recognizers = _recognizers;
    if (NSThread.isMainThread) { for (UIGestureRecognizer *gesture in recognizers) { gesture.enabled = NO; [window removeGestureRecognizer:gesture]; } }
    else dispatch_async(dispatch_get_main_queue(), ^{ for (UIGestureRecognizer *gesture in recognizers) { gesture.enabled = NO; [window removeGestureRecognizer:gesture]; } });
}
- (void)invalidate {
    if (!NSThread.isMainThread) return;
    for (UIGestureRecognizer *gesture in self.recognizers) {
        gesture.enabled = NO;
        gesture.delegate = nil;
        objc_setAssociatedObject(gesture, &DXStatusSessionKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        [self.window removeGestureRecognizer:gesture];
    }
    self.recognizers = @[];
    self.window = nil;
}
- (BOOL)available {
    if (!NSThread.isMainThread) return NO;
    if (!self.window || self.window.hidden) return [self reject:@"window"];
    if (self.homeScreen) {
        // Appearance is authoritative once observed. SpringBoard's display
        // and touch windows need not share UIKit's key-window role.
        if (!DXIsHomeScreenWindow(self.window) ||
            (self.homeAppearanceKnown ? !self.homeVisible : !self.window.isKeyWindow)) return [self reject:@"home-inactive-window"];
        self.anchor = DXHomeStatusAnchor(self.window);
        if (!self.anchor) return [self reject:@"home-statusbar"];
    }
    // The island anchor is only the install-time container; touch-time
    // resolution owns the receiver, so a swapped or released instance and its
    // geometry must not gate the window-level gesture.
    if (!self.aperture && !self.homeScreen && (!self.anchor || self.anchor.window != self.window)) return [self reject:@"window"];
    BOOL springBoard = [NSProcessInfo.processInfo.processName isEqual:@"SpringBoard"];
    if (springBoard) {
        if (![DXGlobalPanel deviceUnlocked] || [DXGlobalPanel.sharedInstance isVisible]) return [self reject:@"lock/panel"];
    } else if (UIApplication.sharedApplication.applicationState != UIApplicationStateActive) return [self reject:@"inactive-app"];
    if (!self.aperture) for (UIView *view = self.anchor; view; view = view.superview) if (view.hidden || view.alpha < 0.01) return [self reject:@"hidden-anchor"];
    UIWindowScene *scene = self.window.windowScene;
    if (scene && scene.activationState != UISceneActivationStateForegroundActive) return [self reject:@"inactive-scene"];
    DXPrefsManager *manager = DXPrefsManager.sharedInstance;
    if (!manager.preferencesAvailable) [manager reload];
    if (!manager.preferencesAvailable || !DXKeyboardPanelBool(manager.prefs, kEnabledkey, YES) || !DXStatusBarFlag(manager.prefs[kDXStatusBarEnabled])) return [self reject:@"preferences/enabled"];
    UIInterfaceOrientation orientation = self.window.windowScene.interfaceOrientation;
    BOOL landscape = UIInterfaceOrientationIsLandscape(orientation) ||
        (orientation == UIInterfaceOrientationUnknown && self.window.bounds.size.width > self.window.bounds.size.height);
    if (landscape && !DXStatusBarFlag(manager.prefs[kDXStatusBarLandscape])) return [self reject:@"landscape-disabled"];
    if (!self.aperture) {
        CGRect frame = [self.anchor convertRect:self.anchor.bounds toView:self.window];
        if (CGRectIsEmpty(frame) || CGRectIsEmpty(CGRectIntersection(frame, self.window.bounds))) return [self reject:@"geometry"];
    }
    return YES;
}
- (BOOL)hasAction:(NSString *)kind region:(NSString *)region preferences:(NSDictionary *)preferences {
    NSString *selector = DXStatusBarSelector(preferences, DXStatusBarSlot(region, kind));
    if (!selector) return NO;
    if (DXPanelAllowed(preferences, selector, DXPanelGestureKind)) return DXKeyboardPanelBool(preferences, kDXPanelGlobalEnabled, YES);
    id definitions = preferences[kLinkActionskey];
    if (![definitions isKindOfClass:NSArray.class]) return NO;
    for (id entry in definitions)
        if ([entry isKindOfClass:NSDictionary.class] && [entry[@"selector"] isEqual:selector]) return DXGlobalCustomActionSupported(entry);
    return NO;
}
- (void)refresh {
    if (!NSThread.isMainThread) return;
    NSDictionary *preferences = DXPrefsManager.sharedInstance.prefs;
    NSArray *regions = self.aperture ? @[@"middle"] : DXStatusBarRegions();
    NSArray *kinds = self.aperture ? @[@"tap"] : DXStatusBarGestures();
    NSUInteger configured = 0;
    for (NSString *region in regions) for (NSString *kind in kinds)
        if ([self hasAction:kind region:region preferences:preferences]) configured++;
    NSString *summary = [NSString stringWithFormat:@"%d/%d/%lu", DXPrefsManager.sharedInstance.preferencesAvailable,
        DXStatusBarFlag(preferences[kDXStatusBarEnabled]), (unsigned long)configured];
    if (![self.lastConfiguration isEqual:summary]) {
        self.lastConfiguration = summary;
        NSLog(@"[TypeX][StatusBarGesture] config host=%@ available=%d enabled=%d slots=%lu", NSProcessInfo.processInfo.processName,
            DXPrefsManager.sharedInstance.preferencesAvailable, DXStatusBarFlag(preferences[kDXStatusBarEnabled]), (unsigned long)configured);
    }
    for (UIGestureRecognizer *gesture in self.recognizers) {
        gesture.enabled = NO;
        objc_setAssociatedObject(gesture, &DXStatusSessionKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        NSString *kind = objc_getAssociatedObject(gesture, &DXStatusKindKey);
        BOOL active = NO;
        for (NSString *region in regions) {
            active |= [kind isEqual:@"horizontal"] ? ([self hasAction:@"leftswipe" region:region preferences:preferences] ||
                [self hasAction:@"rightswipe" region:region preferences:preferences]) : [self hasAction:kind region:region preferences:preferences];
        }
        // Visibility/lock/panel gates are evaluated for each touch. Keeping
        // these separate lets gestures work again after a panel closes.
        gesture.enabled = active && DXPrefsManager.sharedInstance.preferencesAvailable &&
            DXKeyboardPanelBool(preferences, kEnabledkey, YES) && DXStatusBarFlag(preferences[kDXStatusBarEnabled]);
    }
}
- (BOOL)gestureRecognizer:(UIGestureRecognizer *)gesture shouldReceiveTouch:(UITouch *)touch {
    DXStatusGestureSession *previous = objc_getAssociatedObject(gesture, &DXStatusSessionKey);
    objc_setAssociatedObject(gesture, &DXStatusSessionKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    if (![self available]) return NO;
    if (touch.window != self.window) return [self reject:@"window-mismatch"];
    NSString *kind = objc_getAssociatedObject(gesture, &DXStatusKindKey);
    // SpringBoard swaps island container instances between presentation modes.
    // The receiver is resolved per touch; binding to the install-time anchor
    // let an earlier instance's window gesture silently reject later ones.
    UIView *receiver = self.anchor;
    BOOL apertureTap = NO;
    if (self.aperture && [kind isEqual:@"tap"])
        for (UIView *view = touch.view; view && view != self.window; view = view.superview)
            if (DXIsApertureView(view)) { apertureTap = YES; receiver = view; }
    if (self.aperture && !apertureTap) return [self reject:@"aperture-container"];
    if (!DXStatusReceiverVisible(receiver, self.homeScreen ? receiver.window : self.window)) return [self reject:@"hidden-receiver"];
    // Only an explicitly configured island tap can replace its native action.
    // The ordinary status-bar handler must not dispatch the same island touch.
    for (UIView *view = touch.view; view && view != self.window; view = view.superview) {
        if (!apertureTap && ([view isKindOfClass:UIControl.class] || [NSStringFromClass(view.class) containsString:@"Aperture"])) return [self reject:@"native-control"];
        if (self.homeScreen) {
            Class icon = NSClassFromString(@"SBIconView");
            if (icon && [icon isSubclassOfClass:UIView.class] && [view isKindOfClass:icon]) return [self reject:@"home-icon"];
        }
    }
    NSString *region;
    if (self.aperture) {
        region = @"middle";
    } else {
        CGPoint point = [touch locationInView:self.anchor];
        CGRect bounds = self.anchor.bounds;
        region = DXStatusBarRegion(point.x - bounds.origin.x, point.y - bounds.origin.y, bounds.size.width, bounds.size.height);
    }
    if (!region) return NO;
    NSDictionary *preferences = DXPrefsManager.sharedInstance.prefs;
    BOOL enabled = [kind isEqual:@"horizontal"] ? ([self hasAction:@"leftswipe" region:region preferences:preferences] ||
        [self hasAction:@"rightswipe" region:region preferences:preferences]) : [self hasAction:kind region:region preferences:preferences];
    if (!enabled) return NO;
    self.lastRejection = nil;
    if ([kind isEqual:@"doubletap"] && touch.tapCount > 1 && previous &&
        (![previous.region isEqual:region] || ![previous.preferences isEqual:preferences])) return NO;
    DXStatusGestureSession *session = [DXStatusGestureSession new];
    session.region = region; session.window = self.window; session.receiver = receiver; session.touchView = touch.view; session.preferences = [preferences copy];
    session.frame = self.aperture ? touch.window.bounds : [self.anchor convertRect:self.anchor.bounds toView:self.window];
    objc_setAssociatedObject(gesture, &DXStatusSessionKey, session, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    NSLog(@"[TypeX][StatusBarGesture] touch host=%@ slot=%@ view=%@ receiver=%@ window=%@ display=%@", NSProcessInfo.processInfo.processName,
        DXStatusBarSlot(region, kind) ?: [region stringByAppendingString:@".horizontal"], NSStringFromClass(touch.view.class),
        NSStringFromClass(receiver.class), NSStringFromClass(touch.window.class), NSStringFromClass(receiver.window.class));
    return YES;
}
- (BOOL)sessionIsCurrent:(DXStatusGestureSession *)session {
    return session && !session.dispatched && [self available] && session.window == self.window &&
        DXStatusReceiverVisible(session.receiver, self.homeScreen ? session.receiver.window : self.window) &&
        (!self.homeScreen || (session.receiver == self.anchor && session.touchView.window == self.window)) &&
        [session.preferences isEqual:DXPrefsManager.sharedInstance.prefs] &&
        // A new touch resolves the current island container. An in-flight
        // touch must keep its receiver attached, without pinning its frame.
        (self.aperture || CGRectEqualToRect(session.frame, [self.anchor convertRect:self.anchor.bounds toView:self.window]));
}
- (BOOL)gestureRecognizer:(UIGestureRecognizer *)gesture shouldRequireFailureOfGestureRecognizer:(UIGestureRecognizer *)other {
    NSString *kind = objc_getAssociatedObject(gesture, &DXStatusKindKey);
    NSString *otherKind = objc_getAssociatedObject(other, &DXStatusKindKey);
    if (![kind isEqual:@"tap"] || ![otherKind isEqual:@"doubletap"] || other.delegate != self) return NO;
    DXStatusGestureSession *session = objc_getAssociatedObject(gesture, &DXStatusSessionKey);
    return [self sessionIsCurrent:session] && [self hasAction:@"doubletap" region:session.region preferences:session.preferences];
}
- (BOOL)gestureRecognizer:(UIGestureRecognizer *)gesture shouldBeRequiredToFailByGestureRecognizer:(UIGestureRecognizer *)other {
    NSString *kind = objc_getAssociatedObject(gesture, &DXStatusKindKey);
    if (!gesture.enabled || !kind || objc_getAssociatedObject(other, &DXStatusKindKey) || !other.enabled) return NO;
    BOOL nativeAction = !self.aperture && DXIsStatusActionRecognizer(other);
    if (!nativeAction) {
        if (![@[@"tap", @"doubletap"] containsObject:kind] || ![other isKindOfClass:UITapGestureRecognizer.class]) return NO;
        UITapGestureRecognizer *native = (UITapGestureRecognizer *)other;
        if (native.numberOfTapsRequired != 1 || native.numberOfTouchesRequired != 1) return NO;
    }
    DXStatusGestureSession *session = objc_getAssociatedObject(gesture, &DXStatusSessionKey);
    if (![self sessionIsCurrent:session]) return NO;
    UIView *view = other.view;
    UIView *touchReceiver = self.homeScreen ? session.touchView : session.receiver;
    if (!view || (view != self.window && view.window != self.window) ||
        !(view == self.window || [view isDescendantOfView:touchReceiver] || [touchReceiver isDescendantOfView:view])) return NO;
    BOOL configured = [kind isEqual:@"horizontal"] ?
        ([self hasAction:@"leftswipe" region:session.region preferences:session.preferences] ||
         [self hasAction:@"rightswipe" region:session.region preferences:session.preferences]) :
        [self hasAction:kind region:session.region preferences:session.preferences];
    if (!configured) return NO;
    // UIKit evaluates this per touch, including descendant taps and recognizers
    // installed after ours. Unconfigured/native-control touches never get here.
    NSLog(@"[TypeX][StatusBarGesture] priority host=%@ slot=%@ native=%@", NSProcessInfo.processInfo.processName,
        DXStatusBarSlot(session.region, kind) ?: [session.region stringByAppendingString:@".horizontal"], NSStringFromClass(other.class));
    return YES;
}
- (BOOL)gestureRecognizerShouldBegin:(UIGestureRecognizer *)gesture {
    if (![self available]) return NO;
    if (![gesture isKindOfClass:UIPanGestureRecognizer.class]) return YES;
    DXStatusGestureSession *session = objc_getAssociatedObject(gesture, &DXStatusSessionKey);
    CGPoint delta = [(UIPanGestureRecognizer *)gesture translationInView:self.window];
    if (!isfinite(delta.x) || !isfinite(delta.y) || fabs(delta.x) < fabs(delta.y) * 1.5 || delta.x == 0) return NO;
    NSString *direction = delta.x < 0 ? @"leftswipe" : @"rightswipe";
    if (!session || ![self hasAction:direction region:session.region preferences:session.preferences]) return NO;
    session.horizontalDirection = direction;
    return YES;
}
- (BOOL)gestureRecognizer:(UIGestureRecognizer *)gesture shouldRecognizeSimultaneouslyWithGestureRecognizer:(UIGestureRecognizer *)other {
    if (![objc_getAssociatedObject(gesture, &DXStatusKindKey) isEqual:@"horizontal"] ||
        objc_getAssociatedObject(other, &DXStatusKindKey) || ![other isKindOfClass:UIPanGestureRecognizer.class]) return NO;
    DXStatusGestureSession *session = objc_getAssociatedObject(gesture, &DXStatusSessionKey);
    CGPoint delta = [(UIPanGestureRecognizer *)gesture translationInView:self.window];
    return session && [self available] && isfinite(delta.x) && isfinite(delta.y) && delta.x != 0 &&
        fabs(delta.x) >= fabs(delta.y) * 1.5 && [self hasAction:delta.x < 0 ? @"leftswipe" : @"rightswipe"
            region:session.region preferences:session.preferences];
}
- (void)recognized:(UIGestureRecognizer *)gesture {
    NSString *kind = objc_getAssociatedObject(gesture, &DXStatusKindKey);
    if ([kind isEqual:@"longpress"] ? gesture.state != UIGestureRecognizerStateBegan : gesture.state != UIGestureRecognizerStateEnded) return;
    DXStatusGestureSession *session = objc_getAssociatedObject(gesture, &DXStatusSessionKey);
    if (![self sessionIsCurrent:session]) return;
    if ([kind isEqual:@"horizontal"]) {
        CGPoint delta = [(UIPanGestureRecognizer *)gesture translationInView:self.window];
        if (!isfinite(delta.x) || !isfinite(delta.y) || fabs(delta.x) < 28 || fabs(delta.x) < fabs(delta.y) * 1.5) return;
        kind = delta.x < 0 ? @"leftswipe" : @"rightswipe";
        if (![session.horizontalDirection isEqual:kind]) return;
    }
    if (![self hasAction:kind region:session.region preferences:session.preferences]) return;
    session.dispatched = YES;
    NSString *slot = DXStatusBarSlot(session.region, kind);
    NSString *selector = DXStatusBarSelector(session.preferences, slot);
    NSLog(@"[TypeX][StatusBarGesture] trigger host=%@ slot=%@", NSProcessInfo.processInfo.processName, slot);
    if (DXKeyboardPanelBool(session.preferences, kEnabledHaptickey, YES)) {
        UIImpactFeedbackGenerator *feedback = [[UIImpactFeedbackGenerator alloc] initWithStyle:UIImpactFeedbackStyleLight];
        [feedback impactOccurred];
    }
    UIInterfaceOrientation orientation = self.window.windowScene.interfaceOrientation;
    BOOL landscape = UIInterfaceOrientationIsLandscape(orientation) ||
        (orientation == UIInterfaceOrientationUnknown && self.window.bounds.size.width > self.window.bounds.size.height);
    DXRequestStatusBarGesture(slot, selector, landscape, ^(DXSystemOpenResult result) {
        NSLog(@"[TypeX][StatusBarGesture] result host=%@ slot=%@ status=%llu", NSProcessInfo.processInfo.processName, slot, (unsigned long long)result);
    });
}
@end

static void DXInstallStatusGestures(UIView *view) {
    if (!NSThread.isMainThread || (!DXIsStatusView(view) && !DXIsApertureView(view) && !DXIsHomeScreenWindow(view))) return;
    if (!DXStatusHandlers) DXStatusHandlers = [NSHashTable weakObjectsHashTable];
    BOOL aperture = DXIsApertureView(view);
    BOOL homeScreen = DXIsHomeScreenWindow(view);
    UIView *anchor = view;
    for (UIView *parent = view.superview; parent; parent = parent.superview)
        if (aperture ? DXIsApertureView(parent) : DXIsStatusView(parent)) anchor = parent;
    // Island and desktop receivers are owned by their windows. Displayed
    // status-bar/container instances can be replaced independently of them.
    if ((aperture || homeScreen) && !anchor.window) return;
    id owner = (aperture || homeScreen) ? (id)anchor.window : (id)anchor;
    const void *key = homeScreen ? &DXStatusHomeHandlerKey : (aperture ? &DXStatusApertureHandlerKey : &DXStatusHandlerKey);
    DXStatusGestureHandler *handler = objc_getAssociatedObject(owner, key);
    // A core can enter the window before its wrapper. Retire its earlier set
    // when the enclosing wrapper arrives, regardless of hook/scan order.
    if (!aperture && !homeScreen && anchor.window) for (DXStatusGestureHandler *existing in DXStatusHandlers.allObjects) {
        UIView *oldAnchor = existing.anchor;
        if (!existing.aperture && !existing.homeScreen && oldAnchor != anchor && [oldAnchor isDescendantOfView:anchor]) {
            [existing invalidate];
            objc_setAssociatedObject(oldAnchor, &DXStatusHandlerKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        }
    }
    if (handler && handler.window == anchor.window) return;
    [handler invalidate];
    objc_setAssociatedObject(owner, key, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    if (!anchor.window) return;
    handler = [DXStatusGestureHandler new]; handler.anchor = anchor; handler.window = anchor.window; handler.aperture = aperture;
    handler.homeScreen = homeScreen;
    NSMutableArray *recognizers = [NSMutableArray array];
    for (NSString *kind in aperture ? @[@"tap"] : @[@"tap", @"doubletap", @"longpress", @"horizontal"]) {
        UIGestureRecognizer *gesture;
        if ([kind isEqual:@"longpress"]) {
            UILongPressGestureRecognizer *press = [[UILongPressGestureRecognizer alloc] initWithTarget:handler action:@selector(recognized:)];
            press.minimumPressDuration = 0.5; press.allowableMovement = 10; gesture = press;
        } else if ([kind isEqual:@"horizontal"]) {
            UIPanGestureRecognizer *pan = [[UIPanGestureRecognizer alloc] initWithTarget:handler action:@selector(recognized:)];
            pan.minimumNumberOfTouches = 1; pan.maximumNumberOfTouches = 1; gesture = pan;
        } else {
            UITapGestureRecognizer *tap = [[UITapGestureRecognizer alloc] initWithTarget:handler action:@selector(recognized:)];
            tap.numberOfTapsRequired = [kind isEqual:@"doubletap"] ? 2 : 1;
            tap.numberOfTouchesRequired = 1;
            tap.delaysTouchesEnded = YES; gesture = tap;
        }
        gesture.delegate = handler; gesture.cancelsTouchesInView = YES;
        gesture.delaysTouchesBegan = [kind isEqual:@"tap"] || [kind isEqual:@"doubletap"];
        objc_setAssociatedObject(gesture, &DXStatusKindKey, kind, OBJC_ASSOCIATION_COPY_NONATOMIC);
        [recognizers addObject:gesture];
    }
    handler.recognizers = recognizers;
    objc_setAssociatedObject(owner, key, handler, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    [DXStatusHandlers addObject:handler];
    for (UIGestureRecognizer *gesture in recognizers) [anchor.window addGestureRecognizer:gesture];
    [handler refresh];
    NSLog(@"[TypeX][StatusBarGesture] installed host=%@ view=%@ window=%@", NSProcessInfo.processInfo.processName,
        NSStringFromClass(anchor.class), NSStringFromClass(anchor.window.class));
}

static void DXScanStatusViews(UIView *view) {
    if (DXIsStatusView(view) || DXIsApertureView(view) || DXIsHomeScreenWindow(view)) DXInstallStatusGestures(view);
    for (UIView *child in view.subviews) DXScanStatusViews(child);
}

%group TypeXStatusBarWrapper
%hook UIStatusBar
- (void)didMoveToWindow { %orig; DXInstallStatusGestures((UIView *)self); }
%end
%end
%group TypeXStatusBarCore
%hook _UIStatusBar
- (void)didMoveToWindow { %orig; DXInstallStatusGestures((UIView *)self); }
%end
%end
%group TypeXStatusBarModern
%hook UIStatusBar_Modern
- (void)didMoveToWindow { %orig; DXInstallStatusGestures((UIView *)self); }
%end
%end
%group TypeXSystemStatusBarWrapper
%hook STUIStatusBar_Wrapper
- (void)didMoveToWindow { %orig; DXInstallStatusGestures((UIView *)self); }
%end
%end
%group TypeXSystemStatusBarCore
%hook STUIStatusBar
- (void)didMoveToWindow { %orig; DXInstallStatusGestures((UIView *)self); }
%end
%end
%group TypeXStatusBarAperture
%hook SBSystemApertureContainerView
- (void)didMoveToWindow { %orig; DXInstallStatusGestures((UIView *)self); }
%end
%end

static void DXTryStatusHooks(void) {
    if (!NSThread.isMainThread) return;
    if (!DXPrefsManager.sharedInstance.preferencesAvailable) [DXPrefsManager.sharedInstance reload];
    static BOOL wrapperInstalled = NO, coreInstalled = NO, modernInstalled = NO, apertureInstalled = NO, loggedUnavailable = NO;
    static BOOL systemWrapperInstalled = NO, systemCoreInstalled = NO;
    Class wrapper = NSClassFromString(@"UIStatusBar") ?: NSClassFromString(@"UIStatusBar_Modern");
    Class core = NSClassFromString(@"_UIStatusBar");
    Class modern = NSClassFromString(@"UIStatusBar_Modern");
    Class systemWrapper = NSClassFromString(@"STUIStatusBar_Wrapper");
    Class systemCore = NSClassFromString(@"STUIStatusBar");
    Class aperture = [NSProcessInfo.processInfo.processName isEqual:@"SpringBoard"] ? NSClassFromString(@"SBSystemApertureContainerView") : Nil;
    SEL selector = @selector(didMoveToWindow);
    for (Class cls in @[wrapper ?: NSObject.class, core ?: NSObject.class, modern ?: NSObject.class,
                       systemWrapper ?: NSObject.class, systemCore ?: NSObject.class, aperture ?: NSObject.class]) {
        if (![cls isSubclassOfClass:UIView.class]) continue;
        Method method = class_getInstanceMethod(cls, selector);
        if (!method) continue;
        NSMethodSignature *signature = [NSMethodSignature signatureWithObjCTypes:method_getTypeEncoding(method)];
        if (signature.numberOfArguments != 2 || strcmp(signature.methodReturnType, @encode(void))) continue;
        if (cls == wrapper && !wrapperInstalled) {
            %init(TypeXStatusBarWrapper, UIStatusBar = wrapper); wrapperInstalled = YES;
            NSLog(@"[TypeX][StatusBarGesture] hook host=%@ class=%@", NSProcessInfo.processInfo.processName, NSStringFromClass(cls));
        }
        if (cls == core && !coreInstalled) {
            %init(TypeXStatusBarCore, _UIStatusBar = core); coreInstalled = YES;
            NSLog(@"[TypeX][StatusBarGesture] hook host=%@ class=%@", NSProcessInfo.processInfo.processName, NSStringFromClass(cls));
        }
        if (cls == modern && modern != wrapper && !modernInstalled) {
            %init(TypeXStatusBarModern, UIStatusBar_Modern = modern); modernInstalled = YES;
            NSLog(@"[TypeX][StatusBarGesture] hook host=%@ class=%@", NSProcessInfo.processInfo.processName, NSStringFromClass(cls));
        }
        if (cls == systemWrapper && !systemWrapperInstalled) {
            %init(TypeXSystemStatusBarWrapper, STUIStatusBar_Wrapper = systemWrapper); systemWrapperInstalled = YES;
            NSLog(@"[TypeX][StatusBarGesture] hook host=%@ class=%@", NSProcessInfo.processInfo.processName, NSStringFromClass(cls));
        }
        if (cls == systemCore && !systemCoreInstalled) {
            %init(TypeXSystemStatusBarCore, STUIStatusBar = systemCore); systemCoreInstalled = YES;
            NSLog(@"[TypeX][StatusBarGesture] hook host=%@ class=%@", NSProcessInfo.processInfo.processName, NSStringFromClass(cls));
        }
        if (cls == aperture && !apertureInstalled) { %init(TypeXStatusBarAperture, SBSystemApertureContainerView = aperture); apertureInstalled = YES; }
    }
    #pragma clang diagnostic push
    #pragma clang diagnostic ignored "-Wdeprecated-declarations"
    for (UIWindow *window in UIApplication.sharedApplication.windows) DXScanStatusViews(window);
    #pragma clang diagnostic pop
    for (UIScene *scene in UIApplication.sharedApplication.connectedScenes)
        if ([scene isKindOfClass:UIWindowScene.class])
            for (UIWindow *window in ((UIWindowScene *)scene).windows) DXScanStatusViews(window);
    for (DXStatusGestureHandler *handler in DXStatusHandlers.allObjects) [handler refresh];
    if (!wrapperInstalled && !coreInstalled && !modernInstalled && !systemWrapperInstalled && !systemCoreInstalled && !loggedUnavailable) {
        loggedUnavailable = YES;
        NSLog(@"[TypeX][StatusBarGesture] unavailable: status-bar classes missing");
    }
}

void DXStatusBarHomeScreenDidAppear(UIWindow *window) {
    if (!NSThread.isMainThread || !DXIsHomeScreenWindow(window)) return;
    DXTryStatusHooks();
    DXScanStatusViews(window);
    DXStatusGestureHandler *handler = objc_getAssociatedObject(window, &DXStatusHomeHandlerKey);
    if (!handler) return;
    if (!handler.homeAppearanceKnown || !handler.homeVisible)
        NSLog(@"[TypeX][StatusBarGesture] desktop visible=1 window=%@", NSStringFromClass(window.class));
    handler.homeAppearanceKnown = YES;
    handler.homeVisible = YES;
    [handler refresh];
}

void DXStatusBarHomeScreenWillDisappear(UIWindow *window) {
    if (!NSThread.isMainThread || !DXIsHomeScreenWindow(window)) return;
    DXStatusGestureHandler *handler = objc_getAssociatedObject(window, &DXStatusHomeHandlerKey);
    if (!handler) return;
    if (!handler.homeAppearanceKnown || handler.homeVisible)
        NSLog(@"[TypeX][StatusBarGesture] desktop visible=0 window=%@", NSStringFromClass(window.class));
    handler.homeAppearanceKnown = YES;
    handler.homeVisible = NO;
    [handler refresh];
}

void DXStartStatusBarGestures(void) {
    if (!DXStatusBarHostAllowed(NSProcessInfo.processInfo.processName, NSBundle.mainBundle.bundleURL.pathExtension)) return;
    dispatch_async(dispatch_get_main_queue(), ^{
        static dispatch_once_t once;
        dispatch_once(&once, ^{
            if (!DXStatusHandlers) DXStatusHandlers = [NSHashTable weakObjectsHashTable];
            NSNotificationCenter *center = NSNotificationCenter.defaultCenter;
            for (NSString *name in @[UIWindowDidBecomeVisibleNotification, UIWindowDidBecomeKeyNotification]) {
                [center addObserverForName:name object:nil queue:NSOperationQueue.mainQueue usingBlock:^(NSNotification *note) {
                    // System bars may load late; the desktop can also regain
                    // key status without its window becoming visible again.
                    DXTryStatusHooks();
                    if ([note.object isKindOfClass:UIWindow.class]) DXScanStatusViews(note.object);
                }];
            }
            for (NSString *name in @[UIApplicationDidFinishLaunchingNotification, UISceneWillConnectNotification, UISceneDidActivateNotification]) {
                [center addObserverForName:name object:nil queue:NSOperationQueue.mainQueue usingBlock:^(__unused NSNotification *note) { DXTryStatusHooks(); }];
            }
            [center addObserverForName:UIApplicationDidBecomeActiveNotification object:nil queue:NSOperationQueue.mainQueue usingBlock:^(__unused NSNotification *note) {
                [DXPrefsManager.sharedInstance reload];
                DXTryStatusHooks();
            }];
            for (NSString *name in @[UIApplicationWillResignActiveNotification, UISceneWillDeactivateNotification]) {
                [center addObserverForName:name object:nil queue:NSOperationQueue.mainQueue usingBlock:^(__unused NSNotification *note) {
                    for (DXStatusGestureHandler *handler in DXStatusHandlers.allObjects) [handler refresh];
                }];
            }
            [center addObserverForName:UIDeviceOrientationDidChangeNotification object:nil queue:NSOperationQueue.mainQueue usingBlock:^(__unused NSNotification *note) {
                for (DXStatusGestureHandler *handler in DXStatusHandlers.allObjects) [handler refresh];
            }];
            for (NSString *name in @[kPrefsChangedIdentifier, @"com.apple.springboard.lockstate", @"com.apple.springboard.frontmostapplicationchanged"]) {
                int token = NOTIFY_TOKEN_INVALID;
                uint32_t result = notify_register_dispatch(name.UTF8String, &token, dispatch_get_main_queue(), ^(__unused int delivered) {
                    [DXPrefsManager.sharedInstance reload];
                    DXTryStatusHooks();
                });
                if (result != NOTIFY_STATUS_OK) NSLog(@"[TypeX][StatusBarGesture] notification registration failed status=%u", result);
            }
            DXTryStatusHooks();
        });
    });
}
