#import <Foundation/Foundation.h>
#import "../DXSystemActionCatalog.h"
#import "../DXSystemActionInvocation.h"
#import "../DXKeyboardPanelPreferences.h"
#import "../DXKeyboardPanelHostPolicy.h"

@interface DXInvocationSpy : NSObject
@property(nonatomic) NSUInteger calls;
- (double)mixed:(BOOL)enabled count:(NSInteger)count level:(float)level;
- (id)object:(id)object error:(NSError **)error;
- (NSRange)range;
- (void)pointer:(void *)pointer;
- (void)raise;
@end
@implementation DXInvocationSpy
- (double)mixed:(BOOL)enabled count:(NSInteger)count level:(float)level { self.calls++; return (enabled ? 100 : 0) + count + level; }
- (id)object:(id)object error:(NSError **)error { self.calls++; NSCAssert(!error, @"out pointer must be nil"); return object; }
- (NSRange)range { self.calls++; return NSMakeRange(0, 1); }
- (void)pointer:(void *)pointer { self.calls++; }
- (void)raise { self.calls++; [NSException raise:@"TestFailure" format:@"test"]; }
@end
static NSUInteger checks;
static void check(BOOL value) { NSCAssert(value, @"check %lu failed", (unsigned long)checks + 1); checks++; }
int main(void) {
    @autoreleasepool {
        NSArray *catalog = DXSystemActionCatalog();
        check(catalog.count == 24);
        NSMutableSet *ids = [NSMutableSet set];
        NSUInteger destructive = 0;
        for (NSDictionary *action in catalog) {
            check(![ids containsObject:action[@"id"]] && DXSystemActionDefinition(action[@"id"]) == action);
            [ids addObject:action[@"id"]];
            destructive += [action[@"destructive"] boolValue];
        }
        check(destructive == 6);
        check(!DXSystemActionDefinition(@"reboot;anything") && !DXSystemActionDefinition(@42));
        NSString *prefix = @"__custom_";
        NSDictionary *saved = @{@"selector": @"__custom_1", @"type": @"system", @"systemaction": @"wifi"};
        check(DXSystemActionIsConfigured(@[saved], @"wifi", prefix));
        check(!DXSystemActionIsConfigured(@[saved], @"reboot", prefix));
        check(!DXSystemActionIsConfigured(@[@{@"type": @"system", @"systemaction": @"reboot"}], @"reboot", prefix));
        check(!DXSystemActionIsConfigured(@[@{@"selector": @"__custom_1", @"type": @"url", @"systemaction": @"wifi"}], @"wifi", prefix));
        check(!DXSystemActionIsConfigured(@[@42, NSNull.null], @"wifi", prefix));
        check(!DXSystemActionIsConfigured(@{}, @"wifi", prefix));
        DXInvocationSpy *spy = [DXInvocationSpy new];
        id result;
        check(DXSystemInvoke(spy, @"mixed:count:level:", @[@YES, @-7, @0.5f], &result) && [result doubleValue] == 93.5);
        check(DXSystemInvoke(spy, @"object:error:", @[@"text", NSNull.null], &result) && [result isEqual:@"text"]);
        NSUInteger before = spy.calls;
        check(!DXSystemInvoke(spy, @"mixed:count:level:", @[@YES, @1], &result));
        check(!DXSystemInvoke(spy, @"mixed:count:level:", @[@"yes", @1, @0], &result));
        check(!DXSystemInvoke(spy, @"pointer:", @[@0], &result));
        check(!DXSystemInvoke(spy, @"range", @[], &result));
        check(!DXSystemInvoke(spy, @"absent", @[], &result));
        check(!DXSystemInvoke(nil, @"mixed:count:level:", @[@YES, @1, @0], &result));
        check(spy.calls == before);
        check(!DXSystemInvoke(spy, @"raise", @[], &result));
        NSArray *items = @[@{@"selector": @"builtin:"}, @{@"selector": @"__custom_1", @"name": @"override"},
                          @{@"selector": @"__custom_missing"}, @42, @{@"selector": @1}];
        check([DXKeyboardPanelFilterCustomItems(items, @[saved], prefix) isEqual:@[items[1]]]);
        check(!DXKeyboardPanelFilterCustomItems(items, @{}, prefix).count);
        check(!DXKeyboardPanelFilterCustomItems(items, @[saved], @"").count);
        check(DXKeyboardPanelHostRank(@"UIRemoteKeyboardWindow", NO) > DXKeyboardPanelHostRank(@"UITextEffectsWindow", NO));
        check(DXKeyboardPanelHostRank(@"UIWindow", NO) == 0);
        check(DXKeyboardPanelHostRank(@"UIWindow", YES) > DXKeyboardPanelHostRank(@"UITextEffectsWindow", NO));
        NSLog(@"PASS: %lu system/panel checks (ABI rejection without invocation, saved-action authorization, custom-only panel, host rank)", (unsigned long)checks);
    }
    return 0;
}
