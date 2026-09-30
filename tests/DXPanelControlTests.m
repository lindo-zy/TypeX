#import "../DXPanelControlState.h"
#import "../DXPanelControlSession.h"
#import "../DXPanelControlLayout.h"
#import "../DXKeyboardPanelLayout.h"
#import <notify.h>

static NSUInteger checks;
static void check(BOOL value) { NSCAssert(value, @"check %lu failed", (unsigned long)checks + 1); checks++; }
static void drain(double seconds) { [NSRunLoop.mainRunLoop runUntilDate:[NSDate dateWithTimeIntervalSinceNow:seconds]]; }
// Compile the actual Foundation-only client entrypoint from the production
// broker. The executor is a stand-in; notify registrations/cleanup are real.
static NSUInteger mockExecutions, mockCallbacks;
static BOOL mockBadWord;
static void DXSubmitSystemOpen(NSString *kind, NSString *payload, DXSystemOpenReply reply) {
    check([kind isEqual:@"panel-control"]);
    NSDictionary *request = [NSJSONSerialization JSONObjectWithData:[payload dataUsingEncoding:NSUTF8StringEncoding] options:0 error:nil];
    check(DXPanelControlRequestValid(request));
    dispatch_async(dispatch_get_main_queue(), ^{
        int token = NOTIFY_TOKEN_INVALID;
        check(notify_register_check(DXPanelControlStateSlot(request[@"token"]).UTF8String, &token) == NOTIFY_STATUS_OK);
        uint64_t word = 0;
        check(notify_get_state(token, &word) == NOTIFY_STATUS_OK);
        if (word != DXPanelControlPendingWord) reply(DXSystemOpenExpired);
        else {
            mockExecutions++;
            check(notify_set_state(token, mockBadWord ? 0 : DXPanelControlEncodeState(@{@"wifi": @YES, @"brightness": @0.6, @"volume": @0.3})) == NOTIFY_STATUS_OK);
            reply(DXSystemOpenSucceeded);
        }
        check(notify_get_state(token, &word) == NOTIFY_STATUS_OK && word == 0);
        notify_cancel(token);
    });
}
#import "panel-request-under-test.h"
int main(void) {
    @autoreleasepool {
        NSDictionary *base = @{@"token": NSUUID.UUID.UUIDString, @"source": @"top", @"action": @"state"};
        check(DXPanelControlRequestValid(base));
        for (NSString *action in DXPanelToggleIdentifiers()) {
            NSMutableDictionary *request = [base mutableCopy]; request[@"action"] = action;
            check(DXPanelControlRequestValid(request)); request[@"value"] = @1;
            check(!DXPanelControlRequestValid(request));
        }
        for (id action in @[@"reboot", @"respring", @"setVolume:", @42, NSNull.null]) {
            NSMutableDictionary *request = [base mutableCopy]; request[@"action"] = action;
            check(!DXPanelControlRequestValid(request));
        }
        for (id token in @[@"not-a-uuid", @"../state", @42, NSNull.null]) {
            NSMutableDictionary *request = [base mutableCopy]; request[@"token"] = token;
            check(!DXPanelControlRequestValid(request));
        }
        for (id value in @[@-0.1, @1.1, @(NAN), @(INFINITY), @"0.5", NSNull.null]) {
            NSMutableDictionary *request = [base mutableCopy]; request[@"action"] = @"volume"; request[@"value"] = value;
            check(!DXPanelControlRequestValid(request));
        }
        NSMutableDictionary *request = [base mutableCopy]; request[@"action"] = @"brightness"; request[@"value"] = @0;
        check(DXPanelControlRequestValid(request)); request[@"value"] = @1;
        check(DXPanelControlRequestValid(request)); request[@"source"] = @"other";
        check(!DXPanelControlRequestValid(request)); check(!DXPanelControlRequestValid(@[]));
        check(!DXPanelControlDecodeState(0)); check(!DXPanelControlDecodeState(DXPanelControlPendingWord));
        for (NSUInteger known = 0; known < 32; known++) for (NSUInteger on = 0; on < 32; on++) {
            NSMutableDictionary *state = [NSMutableDictionary dictionary];
            for (NSUInteger index = 0; index < 5; index++) if (known & (1 << index)) state[DXPanelToggleIdentifiers()[index]] = @((on & (1 << index)) != 0);
            state[@"brightness"] = @0.62; state[@"volume"] = @0.38;
            NSDictionary *decoded = DXPanelControlDecodeState(DXPanelControlEncodeState(state));
            for (NSString *key in DXPanelToggleIdentifiers()) check((!state[key] && !decoded[key]) || [state[key] isEqual:decoded[key]]);
            check(fabs([decoded[@"brightness"] doubleValue] - 0.62) <= 1.0 / 65535 && fabs([decoded[@"volume"] doubleValue] - 0.38) <= 1.0 / 65535);
        }
        check(!DXPanelControlDecodeState(DXPanelControlEncodeState(@{@"volume": @(NAN)}))[@"volume"]);
        for (NSNumber *width in @[@280, @343, @398, @1024]) {
            CGFloat controlsHeight = DXPanelSystemControlsHeight(width.doubleValue);
            check(controlsHeight >= 100 && controlsHeight < 200);
            // The control block precedes the grid in one scrollable surface,
            // including viewports shorter than the controls themselves.
            for (NSNumber *height in @[@80, @170, @326]) {
                CGRect item = DXKeyboardPanelItemFrame(0, width.doubleValue, 4, 1); item.origin.y += controlsHeight;
                CGFloat content = MAX(height.doubleValue, controlsHeight + DXKeyboardPanelContentHeight(12, width.doubleValue, 4, 1));
                check(CGRectGetMinY(item) == controlsHeight && content > CGRectGetMaxY(item) && content > height.doubleValue);
            }
        }
        NSMutableArray *calls = [NSMutableArray array], *replies = [NSMutableArray array], *operations = [NSMutableArray array];
        __block NSDictionary *visible;
        __block NSUInteger updates = 0;
        DXPanelControlSession *session = [[DXPanelControlSession alloc] initWithRequester:^NSProgress *(NSString *action, NSNumber *value, DXPanelSystemControlReply reply) {
            [calls addObject:@{@"action": action, @"value": value ?: NSNull.null}]; [replies addObject:[reply copy]];
            NSProgress *operation = [NSProgress discreteProgressWithTotalUnitCount:1]; [operations addObject:operation]; return operation;
        } validity:^BOOL { return YES; } update:^(__unused DXSystemOpenResult result, NSDictionary *state, __unused BOOL busy, __unused NSString *action) {
            if (state) { visible = state; updates++; }
        }];
        [session enqueueAction:@"state" value:nil];
        [session enqueueAction:@"volume" value:@0.1]; [session enqueueAction:@"volume" value:@0.4]; [session enqueueAction:@"volume" value:@0.9];
        check(calls.count == 1 && session.busy);
        ((DXPanelSystemControlReply)replies[0])(DXSystemOpenSucceeded, @{@"volume": @0.3}); drain(0.15);
        check(calls.count == 2 && [calls[1][@"value"] isEqual:@0.9] && [visible[@"volume"] isEqual:@0.9]);
        [session enqueueAction:@"volume" value:@0.2]; [session enqueueAction:@"brightness" value:@0.8];
        ((DXPanelSystemControlReply)replies[1])(DXSystemOpenSucceeded, @{@"volume": @0.9, @"brightness": @0.6}); drain(0.15);
        check(calls.count == 3 && [calls[2][@"value"] isEqual:@0.2] && [visible[@"volume"] isEqual:@0.2] && [visible[@"brightness"] isEqual:@0.8]);
        NSUInteger before = updates;
        ((DXPanelSystemControlReply)replies[1])(DXSystemOpenSucceeded, @{@"volume": @0.1}); drain(0.02);
        check(updates == before && calls.count == 3);
        ((DXPanelSystemControlReply)replies[2])(DXSystemOpenTimedOut, nil); drain(1.1);
        check(!session.busy && calls.count == 3 && !visible.count);
        [session enqueueAction:@"wifi" value:nil]; drain(0.01);
        check(calls.count == 4);
        [session invalidate]; check([operations.lastObject isCancelled]);
        before = updates;
        ((DXPanelSystemControlReply)replies.lastObject)(DXSystemOpenSucceeded, @{@"wifi": @YES}); drain(0.15);
        [session enqueueAction:@"wifi" value:nil]; check(updates == before && calls.count == 4);
        __block BOOL valid = YES;
        DXPanelControlSession *invalidated = [[DXPanelControlSession alloc] initWithRequester:^NSProgress *(__unused NSString *action, __unused NSNumber *value, __unused DXPanelSystemControlReply reply) { check(NO); return nil; }
            validity:^BOOL { return valid; } update:nil];
        valid = NO; [invalidated enqueueAction:@"state" value:nil]; check(!invalidated.busy);
        NSProgress *operation = DXRequestPanelSystemControl(@"state", nil, @"top", ^(DXSystemOpenResult result, NSDictionary *state) {
            mockCallbacks++; check(result == DXSystemOpenSucceeded && [state[@"wifi"] boolValue]);
        });
        drain(0.05); check(mockExecutions == 1 && mockCallbacks == 1); [operation cancel];
        operation = DXRequestPanelSystemControl(@"wifi", nil, @"top", ^(__unused DXSystemOpenResult result, __unused NSDictionary *state) { mockCallbacks++; });
        [operation cancel]; drain(0.05); check(mockExecutions == 1 && mockCallbacks == 1);
        mockBadWord = YES;
        DXRequestPanelSystemControl(@"state", nil, @"bottom", ^(DXSystemOpenResult result, NSDictionary *state) {
            mockCallbacks++; check(result == DXSystemOpenUnavailable && !state);
        });
        drain(0.05); check(mockExecutions == 2 && mockCallbacks == 2);
        DXRequestPanelSystemControl(@"reboot", nil, @"top", ^(DXSystemOpenResult result, __unused NSDictionary *state) {
            mockCallbacks++; check(result == DXSystemOpenInvalid);
        });
        drain(0.05); check(mockExecutions == 2 && mockCallbacks == 3);
        NSLog(@"PASS: %lu panel-control checks (fixed whitelist, state round trip, layout, coalescing, timeout, duplicate/late replies and cancellation)", (unsigned long)checks);
    }
    return 0;
}
