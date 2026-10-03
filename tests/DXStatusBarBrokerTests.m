#import <Foundation/Foundation.h>
#import "../DXSystemOpenBroker.h"
#import "../DXStatusBarGesturePolicy.h"
#import "../DXGlobalPanelPolicy.h"
#import "../DXPrefsManager.h"
#define kEnabledkey @"enabledBOOL"
#define kLinkActionskey @"linkactions"
static BOOL server = YES, unlocked = YES, visible, panelCanShow = YES;
static NSUInteger checks, reloads, executions, replies;
static NSTimeInterval requestAge;
static NSDictionary *executed;
static NSString *sentKind, *sentPayload, *shownSide;
static DXSystemOpenResult result;
static void check(BOOL condition) { checks++; NSCAssert(condition, @"Status-bar broker check %lu", (unsigned long)checks); }
static BOOL DXIsSystemOpenServerProcess(void) { return server; }
static BOOL DXIsLinkActionSelector(NSString *value) { return [value hasPrefix:@"__typex_link_action_"]; }
@interface DXPrefsManager ()
@property(nonatomic, readwrite) BOOL preferencesAvailable;
@end
@implementation DXPrefsManager
+ (instancetype)sharedInstance { static DXPrefsManager *manager; if (!manager) manager = [self new]; return manager; }
- (void)reload { reloads++; }
@end
@interface DXGlobalPanel : NSObject
+ (instancetype)sharedInstance;
+ (BOOL)deviceUnlocked;
- (BOOL)isVisible;
- (void)presentSide:(NSString *)side fromWindow:(id)window origin:(NSString *)origin;
@end
@implementation DXGlobalPanel
+ (instancetype)sharedInstance { static DXGlobalPanel *panel; if (!panel) panel = [self new]; return panel; }
+ (BOOL)deviceUnlocked { return unlocked; }
- (BOOL)isVisible { return visible; }
- (void)presentSide:(NSString *)side fromWindow:(id)window origin:(NSString *)origin {
    check(window == nil && [origin isEqual:@"statusbar"]); shownSide = side; visible = panelCanShow;
}
@end
void DXExecuteGlobalCustomAction(NSDictionary *entry, DXSystemOpenReply reply) { executions++; executed = entry; reply(DXSystemOpenSucceeded); }
#include "StatusBroker.inc"
static void DXSubmitSystemOpen(NSString *kind, NSString *payload, DXSystemOpenReply reply) {
    sentKind = kind; sentPayload = payload;
    DXPerformSystemOpen(@{@"kind": kind, @"payload": payload, @"created": @(NSDate.date.timeIntervalSince1970 - requestAge)}, reply);
}
#include "StatusSender.inc"
static DXSystemOpenReply completion(void) { replies = 0; result = 0; return ^(DXSystemOpenResult value) { replies++; result = value; }; }
int main(void) {
    @autoreleasepool {
        DXPrefsManager *manager = DXPrefsManager.sharedInstance; manager.preferencesAvailable = YES;
        NSDictionary *action = @{@"selector": @"__typex_link_action_live", @"name": @"Live name", @"type": @"openapp", @"link": @"com.apple.mobilesafari"};
        NSDictionary *baseline = @{kDXStatusBarEnabled: @YES, kLinkActionskey: @[action],
            kDXStatusBarBindings: @{@"left.tap": @{@"enabled": @YES, @"selector": action[@"selector"]}}};
        manager.prefs = baseline;
        DXRequestStatusBarGesture(@"left.tap", action[@"selector"], NO, completion());
        check(replies == 1 && result == DXSystemOpenSucceeded && executions == 1 && executed == action && reloads == 1);
        check([sentKind isEqual:@"statusbar-gesture"]);
        NSDictionary *fields = [NSJSONSerialization JSONObjectWithData:[sentPayload dataUsingEncoding:NSUTF8StringEncoding] options:0 error:nil];
        check(DXStatusBarRequestValid(fields) && fields.count == 3);
        for (NSString *side in @[@"left", @"right", @"common"]) {
            NSString *selector = [@"__typex_statusbar_panel_" stringByAppendingString:side];
            manager.prefs = @{kDXStatusBarEnabled: @YES, kDXStatusBarBindings: @{@"left.tap": @{@"enabled": @YES, @"selector": selector}}};
            DXRequestStatusBarGesture(@"left.tap", selector, NO, completion());
            check(replies == 1 && result == DXSystemOpenSucceeded && [shownSide isEqual:side]); visible = NO;
        }
        manager.prefs = baseline;
        for (NSNumber *age in @[@2, @(-1)]) {
            requestAge = age.doubleValue; DXRequestStatusBarGesture(@"left.tap", action[@"selector"], NO, completion());
            check(replies == 1 && result == DXSystemOpenExpired && executions == 1);
        }
        requestAge = 0;
        for (NSNumber *gate in @[@0, @1, @2, @3]) {
            manager.prefs = baseline; manager.preferencesAvailable = gate.intValue != 0; unlocked = gate.intValue != 1; visible = gate.intValue == 2;
            if (gate.intValue == 3) manager.prefs = @{kDXStatusBarEnabled: @NO};
            DXRequestStatusBarGesture(@"left.tap", action[@"selector"], NO, completion());
            check(replies == 1 && result == DXSystemOpenUnavailable && executions == 1);
        }
        manager.preferencesAvailable = YES; unlocked = YES; visible = NO; manager.prefs = baseline;
        DXRequestStatusBarGesture(@"left.tap", @"__typex_link_action_changed", NO, completion()); check(replies == 1 && result == DXSystemOpenUnavailable && executions == 1);
        DXRequestStatusBarGesture(@"left.tap", action[@"selector"], YES, completion()); check(replies == 1 && result == DXSystemOpenUnavailable);
        NSMutableDictionary *unsupported = [baseline mutableCopy]; unsupported[kLinkActionskey] = @[@{@"selector": action[@"selector"], @"type": @"text"}]; manager.prefs = unsupported;
        DXRequestStatusBarGesture(@"left.tap", action[@"selector"], NO, completion()); check(replies == 1 && result == DXSystemOpenInvalid && executions == 1);
        manager.prefs = baseline; server = NO; DXRequestStatusBarGesture(@"left.tap", action[@"selector"], NO, completion()); check(result == DXSystemOpenUnavailable); server = YES;
        DXRequestStatusBarGesture(@"invalid.slot", action[@"selector"], NO, completion()); check(replies == 1 && result == DXSystemOpenInvalid);
        DXPerformSystemOpen(@{@"kind": @"statusbar-gesture", @"payload": @"{}", @"created": @(NSDate.date.timeIntervalSince1970)}, completion()); check(replies == 1 && result == DXSystemOpenInvalid);
        check(executions == 1);
        printf("PASS: %lu production status-bar broker and sender checks with platform doubles\n", (unsigned long)checks);
    }
    return 0;
}
