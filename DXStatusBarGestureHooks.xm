#import "DXStatusBarGestures.h"
#import "DXStatusBarGesturePolicy.h"
#import "DXGlobalActionExecutor.h"
#import "DXGlobalPanel.h"
#import "DXGlobalPanelPolicy.h"
#import "DXKeyboardPanelPreferences.h"
#import "common.h"
#import <objc/runtime.h>
#import <notify.h>

static char DXStatusHandlerKey, DXStatusKindKey, DXStatusSessionKey;
static NSHashTable *DXStatusHandlers;
static void DXTryStatusHooks(void);
static void DXInstallStatusGestures(UIView *view);

static BOOL DXIsStatusView(UIView *view) {
    for (NSString *name in @[@"UIStatusBar", @"UIStatusBar_Modern", @"_UIStatusBar"]) {
        Class cls = NSClassFromString(name);
        if (cls && [view isKindOfClass:cls]) return YES;
    }
    return NO;
}

@interface DXStatusGestureSession : NSObject
@property(nonatomic, weak) UIWindow *window;
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
@property(nonatomic, strong) NSArray<UIGestureRecognizer *> *recognizers;
- (void)refresh;
- (BOOL)available;
- (BOOL)hasAction:(NSString *)kind region:(NSString *)region preferences:(NSDictionary *)preferences;
- (void)recognized:(UIGestureRecognizer *)gesture;
@end

@implementation DXStatusGestureHandler
- (void)dealloc {
    UIWindow *window = _window;
    NSArray *recognizers = _recognizers;
    if (NSThread.isMainThread) { for (UIGestureRecognizer *gesture in recognizers) { gesture.enabled = NO; [window removeGestureRecognizer:gesture]; } }
    else dispatch_async(dispatch_get_main_queue(), ^{ for (UIGestureRecognizer *gesture in recognizers) { gesture.enabled = NO; [window removeGestureRecognizer:gesture]; } });
}
- (BOOL)available {
    if (!NSThread.isMainThread || !self.anchor || !self.window || self.anchor.window != self.window || self.window.hidden ||
        ![DXGlobalPanel deviceUnlocked] || [DXGlobalPanel.sharedInstance isVisible]) return NO;
    for (UIView *view = self.anchor; view; view = view.superview) if (view.hidden || view.alpha < 0.01) return NO;
    UIWindowScene *scene = self.window.windowScene;
    if (scene && scene.activationState != UISceneActivationStateForegroundActive) return NO;
    DXPrefsManager *manager = DXPrefsManager.sharedInstance;
    if (!manager.preferencesAvailable || !DXKeyboardPanelBool(manager.prefs, kEnabledkey, YES) || !DXStatusBarFlag(manager.prefs[kDXStatusBarEnabled])) return NO;
    UIInterfaceOrientation orientation = self.window.windowScene.interfaceOrientation;
    BOOL landscape = UIInterfaceOrientationIsLandscape(orientation) ||
        (orientation == UIInterfaceOrientationUnknown && self.window.bounds.size.width > self.window.bounds.size.height);
    if (landscape && !DXStatusBarFlag(manager.prefs[kDXStatusBarLandscape])) return NO;
    CGRect frame = [self.anchor convertRect:self.anchor.bounds toView:self.window];
    return !CGRectIsEmpty(frame) && !CGRectIsEmpty(CGRectIntersection(frame, self.window.bounds));
}
- (BOOL)hasAction:(NSString *)kind region:(NSString *)region preferences:(NSDictionary *)preferences {
    NSString *selector = DXStatusBarSelector(preferences, DXStatusBarSlot(region, kind));
    if (!selector) return NO;
    if (DXStatusBarPanelSide(selector)) return DXKeyboardPanelBool(preferences, kDXPanelGlobalEnabled, YES);
    id definitions = preferences[kLinkActionskey];
    if (![definitions isKindOfClass:NSArray.class]) return NO;
    for (id entry in definitions)
        if ([entry isKindOfClass:NSDictionary.class] && [entry[@"selector"] isEqual:selector]) return DXGlobalCustomActionSupported(entry);
    return NO;
}
- (void)refresh {
    if (!NSThread.isMainThread) return;
    NSDictionary *preferences = DXPrefsManager.sharedInstance.prefs;
    for (UIGestureRecognizer *gesture in self.recognizers) {
        gesture.enabled = NO;
        objc_setAssociatedObject(gesture, &DXStatusSessionKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        NSString *kind = objc_getAssociatedObject(gesture, &DXStatusKindKey);
        BOOL active = NO;
        for (NSString *region in DXStatusBarRegions()) {
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
    if (![self available] || touch.window != self.window) return NO;
    // Leave native controls and the system's Live Activity affordances alone.
    for (UIView *view = touch.view; view && view != self.window; view = view.superview) {
        if ([view isKindOfClass:UIControl.class] || [NSStringFromClass(view.class) containsString:@"Aperture"]) return NO;
    }
    CGPoint point = [touch locationInView:self.anchor];
    NSString *region = DXStatusBarRegion(point.x, point.y, self.anchor.bounds.size.width, self.anchor.bounds.size.height);
    if (!region) return NO;
    NSString *kind = objc_getAssociatedObject(gesture, &DXStatusKindKey);
    NSDictionary *preferences = DXPrefsManager.sharedInstance.prefs;
    BOOL enabled = [kind isEqual:@"horizontal"] ? ([self hasAction:@"leftswipe" region:region preferences:preferences] ||
        [self hasAction:@"rightswipe" region:region preferences:preferences]) : [self hasAction:kind region:region preferences:preferences];
    if (!enabled) return NO;
    DXStatusGestureSession *previous = objc_getAssociatedObject(gesture, &DXStatusSessionKey);
    if ([kind isEqual:@"doubletap"] && touch.tapCount > 1 && previous &&
        (![previous.region isEqual:region] || ![previous.preferences isEqual:preferences])) return NO;
    DXStatusGestureSession *session = [DXStatusGestureSession new];
    session.region = region; session.window = self.window; session.preferences = [preferences copy];
    session.frame = [self.anchor convertRect:self.anchor.bounds toView:self.window];
    objc_setAssociatedObject(gesture, &DXStatusSessionKey, session, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    return YES;
}
- (BOOL)gestureRecognizer:(UIGestureRecognizer *)gesture shouldRequireFailureOfGestureRecognizer:(UIGestureRecognizer *)other {
    NSString *kind = objc_getAssociatedObject(gesture, &DXStatusKindKey);
    NSString *otherKind = objc_getAssociatedObject(other, &DXStatusKindKey);
    if (![kind isEqual:@"tap"] || ![otherKind isEqual:@"doubletap"]) return NO;
    DXStatusGestureSession *session = objc_getAssociatedObject(gesture, &DXStatusSessionKey);
    return session && [self hasAction:@"doubletap" region:session.region preferences:session.preferences];
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
    if (!session || session.dispatched || ![self available] || session.window != self.window ||
        ![session.preferences isEqual:DXPrefsManager.sharedInstance.prefs] ||
        !CGRectEqualToRect(session.frame, [self.anchor convertRect:self.anchor.bounds toView:self.window])) return;
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
    NSLog(@"[TypeX][StatusBarGesture] trigger slot=%@", slot);
    if (DXKeyboardPanelBool(session.preferences, kEnabledHaptickey, YES)) {
        UIImpactFeedbackGenerator *feedback = [[UIImpactFeedbackGenerator alloc] initWithStyle:UIImpactFeedbackStyleLight];
        [feedback impactOccurred];
    }
    NSString *side = DXStatusBarPanelSide(selector);
    if (side) { [DXGlobalPanel.sharedInstance presentSide:side fromWindow:self.window origin:@"statusbar"]; return; }
    for (id entry in session.preferences[kLinkActionskey]) {
        if (![entry isKindOfClass:NSDictionary.class] || ![entry[@"selector"] isEqual:selector]) continue;
        DXExecuteGlobalCustomAction(entry, ^(DXSystemOpenResult result) {
            NSLog(@"[TypeX][StatusBarGesture] result slot=%@ status=%llu", slot, (unsigned long long)result);
        });
        return;
    }
}
@end

static void DXInstallStatusGestures(UIView *view) {
    if (!NSThread.isMainThread || !DXIsStatusView(view)) return;
    UIView *anchor = view;
    for (UIView *parent = view.superview; parent; parent = parent.superview) if (DXIsStatusView(parent)) anchor = parent;
    DXStatusGestureHandler *handler = objc_getAssociatedObject(anchor, &DXStatusHandlerKey);
    if (handler && handler.window == anchor.window) return;
    for (UIGestureRecognizer *gesture in handler.recognizers) { gesture.enabled = NO; [handler.window removeGestureRecognizer:gesture]; }
    objc_setAssociatedObject(anchor, &DXStatusHandlerKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    if (!anchor.window) return;
    handler = [DXStatusGestureHandler new]; handler.anchor = anchor; handler.window = anchor.window;
    NSMutableArray *recognizers = [NSMutableArray array];
    for (NSString *kind in @[@"tap", @"doubletap", @"longpress", @"horizontal"]) {
        UIGestureRecognizer *gesture;
        if ([kind isEqual:@"longpress"]) {
            UILongPressGestureRecognizer *press = [[UILongPressGestureRecognizer alloc] initWithTarget:handler action:@selector(recognized:)];
            press.minimumPressDuration = 0.5; press.allowableMovement = 10; gesture = press;
        } else if ([kind isEqual:@"horizontal"]) {
            UIPanGestureRecognizer *pan = [[UIPanGestureRecognizer alloc] initWithTarget:handler action:@selector(recognized:)];
            pan.minimumNumberOfTouches = 1; pan.maximumNumberOfTouches = 1; gesture = pan;
        } else {
            UITapGestureRecognizer *tap = [[UITapGestureRecognizer alloc] initWithTarget:handler action:@selector(recognized:)];
            tap.numberOfTapsRequired = [kind isEqual:@"doubletap"] ? 2 : 1; gesture = tap;
        }
        gesture.delegate = handler; gesture.cancelsTouchesInView = YES; gesture.delaysTouchesBegan = NO;
        objc_setAssociatedObject(gesture, &DXStatusKindKey, kind, OBJC_ASSOCIATION_COPY_NONATOMIC);
        [recognizers addObject:gesture];
    }
    // Only status-bar ancestor taps are subordinated; vertical system recognizers stay untouched.
    for (UIView *ancestor = anchor; ancestor; ancestor = ancestor.superview) {
        for (UIGestureRecognizer *native in [ancestor.gestureRecognizers copy]) {
            if (![native isKindOfClass:UITapGestureRecognizer.class] || objc_getAssociatedObject(native, &DXStatusKindKey)) continue;
            for (UIGestureRecognizer *ours in recognizers) [native requireGestureRecognizerToFail:ours];
        }
    }
    handler.recognizers = recognizers;
    objc_setAssociatedObject(anchor, &DXStatusHandlerKey, handler, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    [DXStatusHandlers addObject:handler];
    for (UIGestureRecognizer *gesture in recognizers) [anchor.window addGestureRecognizer:gesture];
    [handler refresh];
    NSLog(@"[TypeX][StatusBarGesture] installed view=%@ window=%@", NSStringFromClass(anchor.class), NSStringFromClass(anchor.window.class));
}

static void DXScanStatusViews(UIView *view) {
    if (DXIsStatusView(view)) { DXInstallStatusGestures(view); return; }
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

static void DXTryStatusHooks(void) {
    if (!NSThread.isMainThread) return;
    static BOOL wrapperInstalled = NO, coreInstalled = NO, modernInstalled = NO, loggedUnavailable = NO;
    Class wrapper = NSClassFromString(@"UIStatusBar") ?: NSClassFromString(@"UIStatusBar_Modern");
    Class core = NSClassFromString(@"_UIStatusBar");
    Class modern = NSClassFromString(@"UIStatusBar_Modern");
    SEL selector = @selector(didMoveToWindow);
    for (Class cls in @[wrapper ?: NSObject.class, core ?: NSObject.class, modern ?: NSObject.class]) {
        if (![cls isSubclassOfClass:UIView.class]) continue;
        Method method = class_getInstanceMethod(cls, selector);
        if (!method) continue;
        NSMethodSignature *signature = [NSMethodSignature signatureWithObjCTypes:method_getTypeEncoding(method)];
        if (signature.numberOfArguments != 2 || strcmp(signature.methodReturnType, @encode(void))) continue;
        if (cls == wrapper && !wrapperInstalled) { %init(TypeXStatusBarWrapper, UIStatusBar = wrapper); wrapperInstalled = YES; }
        if (cls == core && !coreInstalled) { %init(TypeXStatusBarCore, _UIStatusBar = core); coreInstalled = YES; }
        if (cls == modern && modern != wrapper && !modernInstalled) { %init(TypeXStatusBarModern, UIStatusBar_Modern = modern); modernInstalled = YES; }
    }
    #pragma clang diagnostic push
    #pragma clang diagnostic ignored "-Wdeprecated-declarations"
    for (UIWindow *window in UIApplication.sharedApplication.windows) DXScanStatusViews(window);
    #pragma clang diagnostic pop
    if (!wrapperInstalled && !coreInstalled && !modernInstalled && !loggedUnavailable) {
        loggedUnavailable = YES;
        NSLog(@"[TypeX][StatusBarGesture] unavailable: status-bar classes missing");
    }
}

void DXStartStatusBarGestures(void) {
    if (![NSProcessInfo.processInfo.processName isEqual:@"SpringBoard"]) return;
    dispatch_async(dispatch_get_main_queue(), ^{
        static dispatch_once_t once;
        dispatch_once(&once, ^{
            DXStatusHandlers = [NSHashTable weakObjectsHashTable];
            NSNotificationCenter *center = NSNotificationCenter.defaultCenter;
            [center addObserverForName:UIWindowDidBecomeVisibleNotification object:nil queue:NSOperationQueue.mainQueue usingBlock:^(NSNotification *note) {
                if ([note.object isKindOfClass:UIWindow.class]) DXScanStatusViews(note.object);
                for (DXStatusGestureHandler *handler in DXStatusHandlers.allObjects) [handler refresh];
            }];
            [center addObserverForName:UIApplicationDidFinishLaunchingNotification object:nil queue:NSOperationQueue.mainQueue usingBlock:^(__unused NSNotification *note) { DXTryStatusHooks(); }];
            [center addObserverForName:UIDeviceOrientationDidChangeNotification object:nil queue:NSOperationQueue.mainQueue usingBlock:^(__unused NSNotification *note) {
                for (DXStatusGestureHandler *handler in DXStatusHandlers.allObjects) [handler refresh];
            }];
            for (NSString *name in @[kPrefsChangedIdentifier, @"com.apple.springboard.lockstate", @"com.apple.springboard.frontmostapplicationchanged"]) {
                int token = NOTIFY_TOKEN_INVALID;
                uint32_t result = notify_register_dispatch(name.UTF8String, &token, dispatch_get_main_queue(), ^(__unused int delivered) {
                    [DXPrefsManager.sharedInstance reload];
                    DXTryStatusHooks();
                    for (DXStatusGestureHandler *handler in DXStatusHandlers.allObjects) [handler refresh];
                });
                if (result != NOTIFY_STATUS_OK) NSLog(@"[TypeX][StatusBarGesture] notification registration failed status=%u", result);
            }
            DXTryStatusHooks();
        });
    });
}
