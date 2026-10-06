#import <UIKit/UIKit.h>
#import <dispatch/dispatch.h>
#import <objc/message.h>
#import "../DXPrefsManager.h"

@interface UIApplication : NSObject
@property(nonatomic, strong) id frontmost;
@property(nonatomic) BOOL queryAvailable;
@property(nonatomic) BOOL wrongABI;
@property(nonatomic) BOOL throws;
+ (instancetype)sharedApplication;
- (id)_accessibilityFrontMostApplication;
@end
@implementation UIApplication
+ (instancetype)sharedApplication { static UIApplication *app; if (!app) app = [self new]; return app; }
- (BOOL)respondsToSelector:(SEL)selector {
    return selector == @selector(_accessibilityFrontMostApplication) ? self.queryAvailable : [super respondsToSelector:selector];
}
- (NSMethodSignature *)methodSignatureForSelector:(SEL)selector {
    if (selector == @selector(_accessibilityFrontMostApplication) && self.wrongABI)
        return [NSMethodSignature signatureWithObjCTypes:"v@:"];
    return [super methodSignatureForSelector:selector];
}
- (id)_accessibilityFrontMostApplication {
    if (self.throws) [NSException raise:@"TestQueryException" format:@"query unavailable"];
    return self.frontmost;
}
@end
@implementation UIView @end
@implementation UIWindow @end
@implementation UIWindowScene @end
@implementation UIWindow (DockGestureTests)
- (UIWindowScene *)windowScene { return objc_getAssociatedObject(self, @selector(windowScene)); }
- (void)setWindowScene:(UIWindowScene *)scene { objc_setAssociatedObject(self, @selector(windowScene), scene, OBJC_ASSOCIATION_RETAIN_NONATOMIC); }
@end
@interface DXGlobalPanelWindow : UIWindow @end
@implementation DXGlobalPanelWindow @end
@implementation DXPrefsManager
+ (instancetype)sharedInstance { static DXPrefsManager *manager; if (!manager) manager = [self new]; return manager; }
@end
static BOOL unlocked = YES;
static NSUInteger checks;
static void check(BOOL condition, NSString *name) { checks++; NSCAssert(condition, @"%@", name); }

@interface DXGlobalPanel : NSObject
@property(nonatomic, strong) DXGlobalPanelWindow *window;
@property(nonatomic, copy) NSDictionary *snapshot;
@property(nonatomic) NSUInteger closes;
@property(nonatomic) NSUInteger layouts;
@property(nonatomic, copy) NSString *reason;
+ (BOOL)deviceUnlocked;
- (BOOL)isVisible;
- (void)layout;
- (void)dismissForReason:(NSString *)reason;
- (void)interrupted:(NSNotification *)notification;
- (void)systemStateChanged:(NSString *)name;
@end
#include "GlobalForeground.inc"
@implementation DXGlobalPanel
+ (BOOL)deviceUnlocked { return unlocked; }
- (BOOL)isVisible { return self.window && !self.window.hidden; }
- (void)layout { self.layouts++; }
- (void)dismissForReason:(NSString *)reason { self.closes++; self.reason = reason; self.window = nil; }
// Extracted verbatim from the production panel, including both signal handlers.
#include "GlobalInterruptions.inc"
@end

static void openPanel(DXGlobalPanel *panel, UIWindowScene *scene) {
    panel.window = [DXGlobalPanelWindow new]; panel.window.windowScene = scene;
    panel.snapshot = @{ @"configuration": @1 }; DXPrefsManager.sharedInstance.prefs = panel.snapshot;
}
static void send(DXGlobalPanel *panel, NSString *name, id object) {
    [panel interrupted:[NSNotification notificationWithName:name object:object]];
}
static void drainMainQueue(void) {
    __block BOOL finished = NO;
    dispatch_async(dispatch_get_main_queue(), ^{ finished = YES; });
    NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:1];
    while (!finished && deadline.timeIntervalSinceNow > 0)
        [NSRunLoop.mainRunLoop runMode:NSDefaultRunLoopMode beforeDate:[NSDate dateWithTimeIntervalSinceNow:0.01]];
    check(finished, @"main queue drained");
}
int main(void) {
    @autoreleasepool {
        UIApplication *app = UIApplication.sharedApplication; app.queryAvailable = YES;
        DXGlobalPanel *panel = [DXGlobalPanel new]; UIWindowScene *scene = [UIWindowScene new];
        for (NSUInteger visit = 0; visit < 3; visit++) {
            openPanel(panel, scene); app.frontmost = nil;
            [panel systemStateChanged:@"com.apple.springboard.frontmostapplicationchanged"];
            [panel systemStateChanged:@"com.apple.springboard.lockstate"];
            check(panel.isVisible && panel.closes == visit, @"return Home/unlock signals preserve every first presentation");
            app.frontmost = [NSObject new];
            [panel systemStateChanged:@"com.apple.springboard.frontmostapplicationchanged"];
            check(!panel.isVisible && panel.closes == visit + 1, @"opening an app still dismisses");
        }
        openPanel(panel, scene); unlocked = NO;
        [panel systemStateChanged:@"com.apple.springboard.lockstate"];
        check(!panel.isVisible, @"actual lock dismisses"); unlocked = YES;
        openPanel(panel, scene); app.queryAvailable = NO;
        [panel systemStateChanged:@"com.apple.springboard.frontmostapplicationchanged"];
        check(!panel.isVisible, @"missing private query keeps conservative dismissal"); app.queryAvailable = YES;
        openPanel(panel, scene); app.wrongABI = YES;
        [panel systemStateChanged:@"com.apple.springboard.frontmostapplicationchanged"];
        check(!panel.isVisible, @"changed private query ABI is never invoked"); app.wrongABI = NO;
        openPanel(panel, scene); app.throws = YES;
        [panel systemStateChanged:@"com.apple.springboard.frontmostapplicationchanged"];
        check(!panel.isVisible, @"private query exception safely closes"); app.throws = NO;
        openPanel(panel, scene);
        send(panel, UIDeviceOrientationDidChangeNotification, nil);
        send(panel, @"typeXLayoutChanged", nil);
        check(panel.isVisible && panel.layouts == 2, @"orientation and unchanged tint update relayout in place");
        send(panel, UISceneWillDeactivateNotification, [UIWindowScene new]);
        check(panel.isVisible, @"unrelated scene cannot close this panel");
        send(panel, UISceneWillDeactivateNotification, scene);
        check(!panel.isVisible, @"own scene deactivation closes");
        openPanel(panel, nil); DXPrefsManager.sharedInstance.prefs = @{};
        send(panel, @"typeXLayoutChanged", nil);
        check(!panel.isVisible, @"changed preference snapshot closes");
        openPanel(panel, nil); send(panel, UIApplicationWillResignActiveNotification, nil);
        check(!panel.isVisible, @"application deactivation still closes");
        openPanel(panel, scene);
        dispatch_sync(dispatch_get_global_queue(QOS_CLASS_DEFAULT, 0), ^{ send(panel, UIApplicationWillResignActiveNotification, nil); });
        openPanel(panel, scene); drainMainQueue();
        check(panel.isVisible, @"queued interruption from an older window cannot close a new presentation");
        printf("PASS: %lu production global panel lifecycle checks with UIKit doubles\n", (unsigned long)checks);
    }
    return 0;
}
