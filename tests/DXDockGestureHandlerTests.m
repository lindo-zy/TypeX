#import "DXPanelTestFixtures.h"
#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <dispatch/dispatch.h>
#import "../DXDockPanelTouchPolicy.h"
#import "../DXDockGesturePolicy.h"
#import "../DXPrefsManager.h"

// The helper declarations normally provided by common.h and the executor.
#define kEnabledkey @"enabledBOOL"
#define kLinkActionskey @"linkactions"
#define kLinkActionSelectorPrefix @"__typex_link_action_"
static BOOL DXIsLinkActionSelector(NSString *selector) {
    return [selector isKindOfClass:NSString.class] && [selector hasPrefix:kLinkActionSelectorPrefix];
}
typedef uint64_t DXSystemOpenResult;
typedef void (^DXSystemOpenReply)(DXSystemOpenResult);
static BOOL unlocked = YES, panelVisible;
static NSUInteger panelCount, actionCount, checks;
static NSString *lastPanel;
static void check(BOOL condition, NSString *name) { checks++; NSCAssert(condition, @"%@", name); }
void DXExecuteGlobalCustomAction(NSDictionary *entry, DXSystemOpenReply reply) {
    check(DXGlobalCustomActionSupported(entry), @"executor receives supported live action");
    actionCount++;
    (void)reply;
}
@interface DXGlobalPanel : NSObject
+ (instancetype)sharedInstance;
+ (BOOL)deviceUnlocked;
- (BOOL)isVisible;
- (void)presentPanelSelector:(NSString *)selector fromWindow:(UIWindow *)window origin:(NSString *)origin;
@end
@implementation DXGlobalPanel
+ (instancetype)sharedInstance { static DXGlobalPanel *panel; if (!panel) panel = [self new]; return panel; }
+ (BOOL)deviceUnlocked { return unlocked; }
- (BOOL)isVisible { return panelVisible; }
- (void)presentPanelSelector:(NSString *)selector fromWindow:(UIWindow *)window origin:(NSString *)origin {
    check(window != nil && [origin isEqual:@"dockgesture"], @"new origin honors chosen panel");
    lastPanel = selector; panelCount++; panelVisible = YES;
}
@end
@interface DXPrefsManager ()
@property(nonatomic, assign, readwrite) BOOL preferencesAvailable;
@end
@implementation DXPrefsManager
+ (instancetype)sharedInstance { static DXPrefsManager *manager; if (!manager) manager = [self new]; return manager; }
@end

@implementation UIView
- (instancetype)init { if ((self = [super init])) { _alpha = 1; _subviews = [NSMutableArray array]; } return self; }
- (void)addSubview:(UIView *)view { [self.subviews addObject:view]; view.superview = self; view.window = self.window; }
- (CGRect)convertRect:(CGRect)rect toView:(UIView *)view {
    (void)view; return CGRectOffset(rect, self.originInWindow.x - self.bounds.origin.x, self.originInWindow.y - self.bounds.origin.y);
}
- (BOOL)isDescendantOfView:(UIView *)view {
    for (UIView *ancestor = self; ancestor; ancestor = ancestor.superview) if (ancestor == view) return YES;
    return NO;
}
@end
@implementation UIView (DockGestureTests)
- (NSMutableArray *)gestureRecognizers {
    NSMutableArray *gestures = objc_getAssociatedObject(self, @selector(gestureRecognizers));
    if (!gestures) { gestures = [NSMutableArray array]; objc_setAssociatedObject(self, @selector(gestureRecognizers), gestures, OBJC_ASSOCIATION_RETAIN_NONATOMIC); }
    return gestures;
}
- (void)setGestureRecognizers:(NSMutableArray *)gestures { objc_setAssociatedObject(self, @selector(gestureRecognizers), gestures, OBJC_ASSOCIATION_RETAIN_NONATOMIC); }
- (void)addGestureRecognizer:(UIGestureRecognizer *)gesture { [self.gestureRecognizers addObject:gesture]; gesture.view = self; }
- (void)removeGestureRecognizer:(UIGestureRecognizer *)gesture { [self.gestureRecognizers removeObject:gesture]; gesture.view = nil; }
@end
@implementation UIWindow @end
@implementation UIWindow (DockGestureTests)
- (UIWindowScene *)windowScene { return objc_getAssociatedObject(self, @selector(windowScene)); }
- (void)setWindowScene:(UIWindowScene *)scene { objc_setAssociatedObject(self, @selector(windowScene), scene, OBJC_ASSOCIATION_RETAIN_NONATOMIC); }
@end
@implementation UIWindowScene @end
@implementation UIControl @end
@implementation SBIconImageView @end
@implementation SBIconView
- (UIView *)iconImageView { return self.image; }
@end
@implementation UIGestureRecognizer
- (instancetype)initWithTarget:(id)target action:(SEL)action {
    (void)target; (void)action; if ((self = [super init])) _enabled = YES; return self;
}
@end
@implementation UIPanGestureRecognizer
- (CGPoint)translationInView:(UIView *)view { (void)view; return self.delta; }
- (CGPoint)velocityInView:(UIView *)view { (void)view; return self.velocity; }
@end
@implementation UIScreenEdgePanGestureRecognizer @end
@implementation UITouch
- (CGPoint)locationInView:(UIView *)view { (void)view; return self.point; }
@end

static char DXDockPanelHandlerKey, DXDockRecognizerKey;
static NSHashTable *DXDockGestureHandlers;
// Extracted verbatim from DXGlobalPanelHooks.xm by the test runner.
#include "DockHandler.inc"

static UITouch *touchFor(UIView *dock) {
    UITouch *touch = [UITouch new]; touch.view = dock; touch.window = dock.window;
    touch.point = CGPointMake(150, 548); return touch;
}
static void start(DXDockPanelGestureHandler *handler, CGPoint delta) {
    handler.pan.numberOfTouches = 0; handler.pan.state = UIGestureRecognizerStatePossible;
    check([handler gestureRecognizer:handler.pan shouldReceiveTouch:touchFor(handler.dock)], @"receive eligible single touch");
    handler.pan.numberOfTouches = 1; handler.pan.delta = delta;
    check([handler gestureRecognizerShouldBegin:handler.pan], @"begin configured direction");
}
static void send(DXDockPanelGestureHandler *handler, UIGestureRecognizerState state, CGPoint delta) {
    handler.pan.state = state; handler.pan.delta = delta; [handler dockPan:handler.pan];
    if (state == UIGestureRecognizerStateEnded || state == UIGestureRecognizerStateCancelled) handler.pan.numberOfTouches = 0;
}
int main(void) {
    @autoreleasepool {
        UIWindow *window = [UIWindow new]; window.window = window; window.bounds = CGRectMake(0, 0, 300, 650);
        UIView *dock = [UIView new]; dock.bounds = CGRectMake(0, 0, 300, 96); dock.originInWindow = CGPointMake(0, 500); [window addSubview:dock];
        DXPrefsManager *manager = DXPrefsManager.sharedInstance; manager.preferencesAvailable = YES; manager.prefs = @{kDXPanels: DXTestGesturePanels(), kDXDockGestureBindings: @{@"up": @"__typex_panel_test-common"}};
        DXInstallDockPanelGesture(dock);
        DXDockPanelGestureHandler *handler = objc_getAssociatedObject(dock, &DXDockPanelHandlerKey);
        DXInstallDockPanelGesture(dock);
        check(window.gestureRecognizers.count == 1 && handler.pan.maximumNumberOfTouches == 1, @"idempotent single-finger installation");
        start(handler, CGPointMake(0, -10)); send(handler, UIGestureRecognizerStateChanged, CGPointMake(0, -60));
        check(panelCount == 1 && [lastPanel isEqual:@"__typex_panel_test-common"], @"legacy up opens common before release");
        send(handler, UIGestureRecognizerStateEnded, CGPointMake(0, -80)); check(panelCount == 1, @"up does not repeat on release");
        panelVisible = NO;
        manager.prefs = @{kDXPanels: DXTestGesturePanels(), kDXPanelDockSwipeEnabled: @NO, kDXDockRightSwipeEnabled: @YES,
            kDXDockGestureBindings: @{@"right": @"__typex_panel_test-right"}};
        start(handler, CGPointMake(10, 0)); send(handler, UIGestureRecognizerStateChanged, CGPointMake(60, 0));
        check(panelCount == 1, @"right panel waits for release");
        send(handler, UIGestureRecognizerStateEnded, CGPointMake(60, 0));
        check(panelCount == 2 && [lastPanel isEqual:@"__typex_panel_test-right"], @"right swipe opens right profile");
        panelVisible = NO;
        NSDictionary *action = @{@"selector": @"__typex_link_action_app", @"type": @"openapp", @"link": @"com.apple.mobilenotes"};
        manager.prefs = @{kDXDockGestureBindings: @{@"up": action[@"selector"]}, kLinkActionskey: @[action]};
        start(handler, CGPointMake(0, -10)); send(handler, UIGestureRecognizerStateChanged, CGPointMake(0, -60));
        check(actionCount == 0, @"custom up waits for release");
        send(handler, UIGestureRecognizerStateCancelled, CGPointMake(0, -60)); check(actionCount == 0, @"cancel custom up");
        NSDictionary *baseline = @{kDXPanelDockSwipeEnabled: @NO, kDXPanelGlobalEnabled: @NO, kDXDockLeftSwipeEnabled: @YES,
            kDXDockGestureBindings: @{@"left": action[@"selector"]}, kLinkActionskey: @[action]};
        manager.prefs = baseline;
        start(handler, CGPointMake(-10, 0));
        UIPanGestureRecognizer *native = [UIPanGestureRecognizer new];
        check([handler gestureRecognizer:handler.pan shouldBeRequiredToFailByGestureRecognizer:native], @"configured horizontal receives precedence");
        check(![handler gestureRecognizer:handler.pan shouldRecognizeSimultaneouslyWithGestureRecognizer:native], @"horizontal does not request paging simultaneously");
        check(![handler gestureRecognizer:handler.pan shouldBeRequiredToFailByGestureRecognizer:[UIScreenEdgePanGestureRecognizer new]], @"system edge pan excluded");
        send(handler, UIGestureRecognizerStateChanged, CGPointMake(-60, 0)); check(actionCount == 0, @"left waits for release");
        send(handler, UIGestureRecognizerStateCancelled, CGPointMake(-60, 0)); check(actionCount == 0, @"cancel does not execute");
        start(handler, CGPointMake(-10, 0)); send(handler, UIGestureRecognizerStateEnded, CGPointMake(-60, 0));
        check(actionCount == 1, @"custom action runs with panels disabled");
        send(handler, UIGestureRecognizerStateEnded, CGPointMake(-60, 0)); check(actionCount == 1, @"duplicate end cannot repeat");
        for (NSValue *delta in @[[NSValue valueWithPoint:NSMakePoint(-47, 0)], [NSValue valueWithPoint:NSMakePoint(60, 0)], [NSValue valueWithPoint:NSMakePoint(-60, 50)]]) {
            start(handler, CGPointMake(-10, 0)); NSPoint point = delta.pointValue;
            send(handler, UIGestureRecognizerStateEnded, CGPointMake(point.x, point.y)); check(actionCount == 1, @"short/reversed/diagonal cannot execute");
        }
        start(handler, CGPointMake(-10, 0));
        check(![handler gestureRecognizer:handler.pan shouldReceiveTouch:touchFor(dock)], @"second finger invalidates session");
        send(handler, UIGestureRecognizerStateEnded, CGPointMake(-60, 0)); check(actionCount == 1, @"multitouch pending action cancelled");
        start(handler, CGPointMake(-10, 0)); manager.prefs = @{};
        send(handler, UIGestureRecognizerStateEnded, CGPointMake(-60, 0)); check(actionCount == 1, @"changed preferences cancel"); manager.prefs = baseline;
        start(handler, CGPointMake(-10, 0)); dock.originInWindow = CGPointMake(1, 500);
        send(handler, UIGestureRecognizerStateEnded, CGPointMake(-60, 0)); check(actionCount == 1, @"moved Dock cancels"); dock.originInWindow = CGPointMake(0, 500);
        start(handler, CGPointMake(-10, 0)); dock.hidden = YES;
        send(handler, UIGestureRecognizerStateEnded, CGPointMake(-60, 0)); check(actionCount == 1, @"hidden Dock cancels"); dock.hidden = NO;
        start(handler, CGPointMake(-10, 0));
        [NSNotificationCenter.defaultCenter postNotificationName:UIDeviceOrientationDidChangeNotification object:nil];
        send(handler, UIGestureRecognizerStateEnded, CGPointMake(-60, 0)); check(actionCount == 1, @"rotation notification cancels");
        unlocked = NO; check(![handler available], @"locked gate"); unlocked = YES;
        manager.preferencesAvailable = NO; check(![handler available], @"unavailable snapshot gate"); manager.preferencesAvailable = YES;
        window.windowScene = [UIWindowScene new]; window.windowScene.activationState = UISceneActivationStateBackground;
        check(![handler available], @"inactive scene gate"); window.windowScene = nil;
        handler.pan.numberOfTouches = 0;
        check([handler gestureRecognizer:handler.pan shouldReceiveTouch:touchFor(dock)], @"configured left touch tracked");
        handler.pan.delta = CGPointMake(10, 0);
        check(![handler gestureRecognizerShouldBegin:handler.pan], @"unassigned right relinquishes recognition");
        start(handler, CGPointMake(-10, 0)); dock.window = nil; DXInstallDockPanelGesture(dock);
        check(window.gestureRecognizers.count == 0 && !handler.sourceWindow, @"detach removes recognizer and session");
        check(!objc_getAssociatedObject(dock, &DXDockPanelHandlerKey), @"detach removes owner association");
        printf("PASS: %lu production Dock handler checks with UIKit doubles\n", (unsigned long)checks);
    }
    return 0;
}
