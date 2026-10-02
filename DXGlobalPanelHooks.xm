#import "DXGlobalPanel.h"
#import "DXGlobalPanelPolicy.h"
#import "DXKeyboardPanelPreferences.h"
#import "common.h"
#import <objc/runtime.h>

static char DXDockPanelHandlerKey;
static void DXTryInstallGlobalPanelHooks(void);

@interface DXDockPanelGestureHandler : NSObject <UIGestureRecognizerDelegate>
@property(nonatomic, weak) UIView *dock;
@property(nonatomic, weak) UIWindow *sourceWindow;
- (BOOL)enabled;
- (void)upwardPan:(UIPanGestureRecognizer *)gesture;
@end

@implementation DXDockPanelGestureHandler
- (BOOL)enabled {
    DXPrefsManager *manager = DXPrefsManager.sharedInstance;
    if (!manager.preferencesAvailable || !self.dock.window || self.dock.window.hidden ||
        [[DXGlobalPanel sharedInstance] isVisible] || ![DXGlobalPanel deviceUnlocked]) return NO;
    for (UIView *view = self.dock; view; view = view.superview)
        if (view.hidden || view.alpha < 0.01) return NO;
    return DXKeyboardPanelBool(manager.prefs, kEnabledkey, YES) &&
        DXKeyboardPanelBool(manager.prefs, kDXPanelGlobalEnabled, YES) &&
        DXKeyboardPanelBool(manager.prefs, kDXPanelDockSwipeEnabled, YES);
}
- (BOOL)gestureRecognizer:(UIGestureRecognizer *)gesture shouldReceiveTouch:(UITouch *)touch {
    (void)gesture;
    self.sourceWindow = nil;
    if (![self enabled]) return NO;
    // Icon taps, long presses and rearrangement keep their original handlers.
    for (UIView *view = touch.view; view && view != self.dock; view = view.superview)
        if ([view isKindOfClass:UIControl.class] || [NSStringFromClass(view.class) containsString:@"IconView"]) return NO;
    CGPoint point = [touch locationInView:self.dock];
    CGRect bounds = self.dock.bounds;
    if (!DXDockPanelOriginAllowed(point.x - bounds.origin.x, point.y - bounds.origin.y, bounds.size.width, bounds.size.height)) return NO;
    self.sourceWindow = self.dock.window;
    return YES;
}
- (BOOL)gestureRecognizerShouldBegin:(UIGestureRecognizer *)recognizer {
    if (![self enabled] || self.sourceWindow != self.dock.window || ![recognizer isKindOfClass:UIPanGestureRecognizer.class]) return NO;
    UIPanGestureRecognizer *pan = (UIPanGestureRecognizer *)recognizer;
    CGPoint delta = [pan translationInView:self.dock], velocity = [pan velocityInView:self.dock];
    return delta.y < 0 && -delta.y >= fabs(delta.x) * 1.5 && velocity.y < -80;
}
- (void)upwardPan:(UIPanGestureRecognizer *)gesture {
    if (gesture.state != UIGestureRecognizerStateEnded || ![self enabled] || self.sourceWindow != self.dock.window) return;
    CGPoint delta = [gesture translationInView:self.dock];
    if (!DXDockPanelSwipeCompletes(delta.x, delta.y)) return;
    NSLog(@"[TypeX][GlobalPanel] dock swipe accepted");
    [[DXGlobalPanel sharedInstance] presentSide:@"common" fromWindow:self.sourceWindow origin:@"dock"];
    self.sourceWindow = nil;
}
@end

static void DXInstallDockPanelGesture(UIView *dock) {
    if (!NSThread.isMainThread || !dock.window || objc_getAssociatedObject(dock, &DXDockPanelHandlerKey)) return;
    DXDockPanelGestureHandler *handler = [DXDockPanelGestureHandler new];
    handler.dock = dock;
    UIPanGestureRecognizer *pan = [[UIPanGestureRecognizer alloc] initWithTarget:handler action:@selector(upwardPan:)];
    pan.minimumNumberOfTouches = 1;
    pan.maximumNumberOfTouches = 1;
    pan.cancelsTouchesInView = YES;
    pan.delaysTouchesBegan = NO;
    pan.delegate = handler;
    objc_setAssociatedObject(dock, &DXDockPanelHandlerKey, handler, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    [dock addGestureRecognizer:pan];
    NSLog(@"[TypeX][GlobalPanel] dock gesture installed class=%@", NSStringFromClass(dock.class));
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
