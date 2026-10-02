#import "DXGlobalPanel.h"
#import "DXGlobalPanelPolicy.h"
#import "DXDockPanelTouchPolicy.h"
#import "DXKeyboardPanelPreferences.h"
#import "common.h"
#import <objc/runtime.h>

static char DXDockPanelHandlerKey;
static void DXTryInstallGlobalPanelHooks(void);

@interface DXDockPanelGestureHandler : NSObject <UIGestureRecognizerDelegate>
@property(nonatomic, weak) UIView *dock;
@property(nonatomic, weak) UIWindow *sourceWindow;
@property(nonatomic, weak) UIWindow *installedWindow;
@property(nonatomic, strong) UIPanGestureRecognizer *pan;
@property(nonatomic, assign) BOOL opened;
@property(nonatomic, assign) BOOL loggedRejectedTouch;
- (BOOL)enabled;
- (void)upwardPan:(UIPanGestureRecognizer *)gesture;
@end

@implementation DXDockPanelGestureHandler
- (void)dealloc {
    UIWindow *window = _installedWindow;
    UIPanGestureRecognizer *pan = _pan;
    if (!window || !pan) return;
    if (NSThread.isMainThread) [window removeGestureRecognizer:pan];
    else dispatch_async(dispatch_get_main_queue(), ^{ [window removeGestureRecognizer:pan]; });
}
- (BOOL)enabled {
    DXPrefsManager *manager = DXPrefsManager.sharedInstance;
    if (!NSThread.isMainThread || !manager.preferencesAvailable || !self.dock.window || self.dock.window.hidden ||
        [[DXGlobalPanel sharedInstance] isVisible] || ![DXGlobalPanel deviceUnlocked]) return NO;
    for (UIView *view = self.dock; view; view = view.superview)
        if (view.hidden || view.alpha < 0.01) return NO;
    CGRect frame = [self.dock convertRect:self.dock.bounds toView:self.dock.window];
    if (CGRectIsEmpty(CGRectIntersection(frame, self.dock.window.bounds))) return NO;
    return DXKeyboardPanelBool(manager.prefs, kEnabledkey, YES) &&
        DXKeyboardPanelBool(manager.prefs, kDXPanelGlobalEnabled, YES) &&
        DXKeyboardPanelBool(manager.prefs, kDXPanelDockSwipeEnabled, YES);
}
- (BOOL)gestureRecognizer:(UIGestureRecognizer *)gesture shouldReceiveTouch:(UITouch *)touch {
    (void)gesture;
    self.sourceWindow = nil;
    self.opened = NO;
    UIWindow *window = self.dock.window;
    if (window != self.installedWindow || touch.window != window) return NO;
    CGPoint point = [touch locationInView:window];
    CGRect frame = [self.dock convertRect:self.dock.bounds toView:window];
    CGFloat below = MAX(0, CGRectGetMaxY(window.bounds) - CGRectGetMaxY(frame));
    if (!DXDockPanelOriginAllowed(point.x - frame.origin.x, point.y - frame.origin.y, frame.size.width, frame.size.height, below)) return NO;
    if (!DXDockPanelTouchIsBackground(self.dock, touch.view, point)) {
        if (!self.loggedRejectedTouch) {
            self.loggedRejectedTouch = YES;
            NSLog(@"[TypeX][GlobalPanel] dock swipe rejected: icon/control hit=%@", NSStringFromClass(touch.view.class));
        }
        return NO;
    }
    if (![self enabled]) {
        DXPrefsManager *manager = DXPrefsManager.sharedInstance;
        NSLog(@"[TypeX][GlobalPanel] dock swipe gated prefs=%d enabled=%d global=%d dock=%d unlocked=%d panelVisible=%d",
            manager.preferencesAvailable, DXKeyboardPanelBool(manager.prefs, kEnabledkey, YES),
            DXKeyboardPanelBool(manager.prefs, kDXPanelGlobalEnabled, YES), DXKeyboardPanelBool(manager.prefs, kDXPanelDockSwipeEnabled, YES),
            [DXGlobalPanel deviceUnlocked], [[DXGlobalPanel sharedInstance] isVisible]);
        return NO;
    }
    self.sourceWindow = self.dock.window;
    NSLog(@"[TypeX][GlobalPanel] dock swipe tracking zone=%@ hit=%@",
        point.y > CGRectGetMaxY(frame) ? @"below" : @"inside", NSStringFromClass(touch.view.class));
    return YES;
}
- (BOOL)gestureRecognizerShouldBegin:(UIGestureRecognizer *)recognizer {
    if (![self enabled] || self.sourceWindow != self.dock.window || ![recognizer isKindOfClass:UIPanGestureRecognizer.class]) return NO;
    UIPanGestureRecognizer *pan = (UIPanGestureRecognizer *)recognizer;
    CGPoint delta = [pan translationInView:self.sourceWindow];
    if (CGPointEqualToPoint(delta, CGPointZero)) delta = [pan velocityInView:self.sourceWindow];
    BOOL begins = isfinite(delta.x) && isfinite(delta.y) && delta.y < 0 && -delta.y >= fabs(delta.x) * 1.5;
    if (!begins) self.sourceWindow = nil;
    return begins;
}
- (BOOL)gestureRecognizer:(UIGestureRecognizer *)gesture shouldRecognizeSimultaneouslyWithGestureRecognizer:(UIGestureRecognizer *)other {
    // SpringBoard's background pan must not prevent our bounded upward pan.
    return gesture == self.pan && self.sourceWindow && [other isKindOfClass:UIPanGestureRecognizer.class];
}
- (void)upwardPan:(UIPanGestureRecognizer *)gesture {
    if (gesture.state == UIGestureRecognizerStateCancelled || gesture.state == UIGestureRecognizerStateFailed) {
        if (self.sourceWindow && !self.opened) NSLog(@"[TypeX][GlobalPanel] dock swipe cancelled state=%ld", (long)gesture.state);
        self.sourceWindow = nil; self.opened = NO; return;
    }
    if ((gesture.state == UIGestureRecognizerStateChanged || gesture.state == UIGestureRecognizerStateEnded) &&
        !self.opened && [self enabled] && self.sourceWindow == self.dock.window) {
        CGPoint delta = [gesture translationInView:self.sourceWindow];
        if (DXDockPanelSwipeCompletes(delta.x, delta.y)) {
            self.opened = YES;
            NSLog(@"[TypeX][GlobalPanel] dock swipe accepted");
            [[DXGlobalPanel sharedInstance] presentSide:@"common" fromWindow:self.sourceWindow origin:@"dock"];
        }
    }
    if (gesture.state == UIGestureRecognizerStateEnded) { self.sourceWindow = nil; self.opened = NO; }
}
@end

static void DXInstallDockPanelGesture(UIView *dock) {
    if (!NSThread.isMainThread) return;
    DXDockPanelGestureHandler *handler = objc_getAssociatedObject(dock, &DXDockPanelHandlerKey);
    if (handler && handler.installedWindow == dock.window && handler.pan.view == dock.window) return;
    [handler.installedWindow removeGestureRecognizer:handler.pan];
    handler.pan = nil;
    handler.installedWindow = nil;
    handler.sourceWindow = nil;
    handler.opened = NO;
    if (!dock.window) {
        objc_setAssociatedObject(dock, &DXDockPanelHandlerKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        return;
    }
    handler = [DXDockPanelGestureHandler new];
    handler.dock = dock;
    handler.installedWindow = dock.window;
    UIPanGestureRecognizer *pan = [[UIPanGestureRecognizer alloc] initWithTarget:handler action:@selector(upwardPan:)];
    pan.minimumNumberOfTouches = 1;
    pan.maximumNumberOfTouches = 1;
    pan.cancelsTouchesInView = YES;
    pan.delaysTouchesBegan = NO;
    pan.delegate = handler;
    handler.pan = pan;
    objc_setAssociatedObject(dock, &DXDockPanelHandlerKey, handler, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    [dock.window addGestureRecognizer:pan];
    NSLog(@"[TypeX][GlobalPanel] dock gesture installed class=%@ window=%@", NSStringFromClass(dock.class), NSStringFromClass(dock.window.class));
}

%group TypeXGlobalDock
%hook SBDockView
- (void)didMoveToWindow {
    %orig;
    DXInstallDockPanelGesture((UIView *)self);
}
%end
%end

%group TypeXGlobalTransition
%hook SBMainSwitcherControllerCoordinator
- (void)layoutStateTransitionCoordinator:(id)coordinator transitionDidBeginWithTransitionContext:(id)context {
    [[DXGlobalPanel sharedInstance] dismiss];
    %orig;
}
%end
%end

%group TypeXGlobalLaunch
%hook SpringBoard
- (void)applicationDidFinishLaunching:(id)application {
    %orig;
    // SpringBoardHome classes can be loaded after tweak constructors run.
    DXTryInstallGlobalPanelHooks();
}
%end
%end

static void DXTryInstallGlobalPanelHooks(void) {
    if (!NSThread.isMainThread) return;
    static BOOL dockInstalled = NO, transitionInstalled = NO;
    Class dock = NSClassFromString(@"SBDockView");
    if (!dockInstalled && !dock) NSLog(@"[TypeX][GlobalPanel] dock hook pending: SBDockView unavailable");
    if (!dockInstalled && [dock instancesRespondToSelector:@selector(didMoveToWindow)]) {
        %init(TypeXGlobalDock, SBDockView = dock);
        dockInstalled = YES;
        // Also cover a Dock that had already joined its window before hooks.
        #pragma clang diagnostic push
        #pragma clang diagnostic ignored "-Wdeprecated-declarations"
        NSMutableArray<UIView *> *pending = [NSMutableArray arrayWithArray:UIApplication.sharedApplication.windows ?: @[]];
        #pragma clang diagnostic pop
        while (pending.count) {
            UIView *view = pending.lastObject;
            [pending removeLastObject];
            if ([view isKindOfClass:dock]) DXInstallDockPanelGesture(view);
            else [pending addObjectsFromArray:view.subviews];
        }
    }
    Class transition = NSClassFromString(@"SBMainSwitcherControllerCoordinator");
    SEL selector = NSSelectorFromString(@"layoutStateTransitionCoordinator:transitionDidBeginWithTransitionContext:");
    Method method = class_getInstanceMethod(transition, selector);
    if (!transitionInstalled && method) {
        NSMethodSignature *signature = [NSMethodSignature signatureWithObjCTypes:method_getTypeEncoding(method)];
        if (signature.numberOfArguments == 4 && !strcmp(signature.methodReturnType, @encode(void)) &&
            !strcmp([signature getArgumentTypeAtIndex:2], "@") && !strcmp([signature getArgumentTypeAtIndex:3], "@")) {
            %init(TypeXGlobalTransition, SBMainSwitcherControllerCoordinator = transition);
            transitionInstalled = YES;
        }
    }
}

%ctor {
    @autoreleasepool {
        if (![NSProcessInfo.processInfo.processName isEqual:@"SpringBoard"]) return;
        DXTryInstallGlobalPanelHooks();
        dispatch_async(dispatch_get_main_queue(), ^{ DXTryInstallGlobalPanelHooks(); });
        Class springBoard = NSClassFromString(@"SpringBoard");
        Method method = class_getInstanceMethod(springBoard, NSSelectorFromString(@"applicationDidFinishLaunching:"));
        if (method) {
            NSMethodSignature *signature = [NSMethodSignature signatureWithObjCTypes:method_getTypeEncoding(method)];
            if (signature.numberOfArguments == 3 && !strcmp(signature.methodReturnType, @encode(void)) &&
                !strcmp([signature getArgumentTypeAtIndex:2], "@")) {
                %init(TypeXGlobalLaunch, SpringBoard = springBoard);
            }
        }
    }
}
