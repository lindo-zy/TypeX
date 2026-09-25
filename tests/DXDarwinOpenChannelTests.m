// macOS integration harness: imports the actual transport, including its wire
// helpers, to exercise independent processes and malformed packets with notifyd.
#import "../DXDarwinOpenChannel.m"
#import <unistd.h>

static NSString *TestPayload(void) {
    return [@"prefs:root=TypeX&path=中文/%25?x=1&y=" stringByPaddingToLength:2048 withString:@"a" startingAtIndex:0];
}

static NSDictionary *TestQuickAction(void) {
    return @{@"bundleID": @"com.example.shortcuts", @"shortcutType": @"item.中文/\"quoted\""};
}

int main(int argc, const char *argv[]) {
    @autoreleasepool {
        if (argc < 2) return 64;
        NSString *mode = @(argv[1]);
        if ([mode isEqualToString:@"server"] || [mode isEqualToString:@"server-blocked"] ||
            [mode isEqualToString:@"server-silent-reply"]) {
            __block NSUInteger executions = 0;
            if (!DXStartDarwinOpenServer(^(NSDictionary *request, DXSystemOpenReply reply) {
                executions++;
                printf("EXEC %lu\n", (unsigned long)executions); fflush(stdout);
                BOOL equal = [request[@"payload"] isEqualToString:TestPayload()];
                if ([request[@"kind"] isEqualToString:@"quick-action"]) {
                    NSData *data = [request[@"payload"] dataUsingEncoding:NSUTF8StringEncoding];
                    equal = [[NSJSONSerialization JSONObjectWithData:data options:0 error:nil] isEqual:TestQuickAction()];
                }
                if ([mode isEqualToString:@"server-silent-reply"]) {
                    DXOpenPending *staged = [DXOpenPending new];
                    staged.tokens = [NSMutableArray array];
                    DXOpenWriteWord(DXOpenSlot([request[@"id"] unsignedLongLongValue], @"reply"),
                                    equal ? DXSystemOpenSucceeded : DXSystemOpenFailed, staged);
                    for (NSNumber *token in staged.tokens) notify_cancel(token.intValue);
                    return; // Simulate a result whose notification was not delivered.
                }
                reply(equal ? DXSystemOpenSucceeded : DXSystemOpenFailed);
                reply(DXSystemOpenFailed); // A second executor reply is ignored.
            })) return 1;
            if ([mode isEqualToString:@"server-blocked"]) {
                dispatch_async(dispatch_get_main_queue(), ^{ sleep(9); });
            }
            puts("READY"); fflush(stdout);
            dispatch_main();
        }
        if ([mode isEqualToString:@"send"] || [mode isEqualToString:@"send-quick"] || [mode isEqualToString:@"absent"] ||
            [mode isEqualToString:@"oversize"] || [mode isEqualToString:@"expired"]) {
            BOOL absent = [mode isEqualToString:@"absent"];
            BOOL oversize = [mode isEqualToString:@"oversize"];
            NSString *payload = oversize ? [@"x" stringByPaddingToLength:10000 withString:@"x" startingAtIndex:0] : TestPayload();
            BOOL quick = [mode isEqualToString:@"send-quick"];
            if (quick) payload = [[NSString alloc] initWithData:[NSJSONSerialization dataWithJSONObject:TestQuickAction() options:0 error:nil]
                                                     encoding:NSUTF8StringEncoding];
            DXSendDarwinOpenRequest(quick ? @"quick-action" : @"sensitive-url", payload, ^(DXSystemOpenResult result) {
                DXSystemOpenResult expected = absent ? DXSystemOpenTimedOut : (oversize ? DXSystemOpenInvalid :
                    ([mode isEqualToString:@"expired"] ? DXSystemOpenExpired : DXSystemOpenSucceeded));
                // Repost the consumed doorbell; the server must not execute twice.
                if (result == DXSystemOpenSucceeded) {
                    notify_post(DXOpenDoorbell);
                    notify_post(DXOpenDoorbell);
                }
                dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.1 * NSEC_PER_SEC)), DXOpenQueue(), ^{
                    BOOL clean = DXOpenPendingRequests().count == 0;
                    printf("RESULT %llu CLEAN %d\n", (unsigned long long)result, clean); fflush(stdout);
                    exit(result == expected && clean ? 0 : 1);
                });
            });
            dispatch_main();
        }
        if ([mode isEqualToString:@"wire"]) {
            __block int failures = 0;
            dispatch_sync(DXOpenQueue(), ^{
                uint64_t requestID = 0x1234fedc5678abcdULL;
                DXOpenPending *pending = [DXOpenPending new];
                pending.tokens = [NSMutableArray array];
                NSDictionary *request = @{@"id": @(requestID), @"created": @([NSDate date].timeIntervalSince1970),
                                          @"kind": @"sensitive-url", @"payload": TestPayload()};
                NSData *body = [NSPropertyListSerialization dataWithPropertyList:request format:NSPropertyListBinaryFormat_v1_0 options:0 error:nil];
                unsigned char digest[CC_SHA256_DIGEST_LENGTH];
                CC_SHA256(body.bytes, (CC_LONG)body.length, digest);
                NSMutableData *packet = [NSMutableData dataWithBytes:digest length:sizeof(digest)];
                [packet appendData:body];
                const uint8_t *bytes = packet.bytes;
                for (NSUInteger offset = 0; offset < packet.length; offset += 8) {
                    uint64_t word = 0;
                    memcpy(&word, bytes + offset, MIN((NSUInteger)8, packet.length - offset));
                    if (!DXOpenWriteWord(DXOpenSlot(requestID, [NSString stringWithFormat:@"%lu", (unsigned long)(offset / 8)]), word, pending)) failures++;
                }
                DXOpenWriteWord(DXOpenSlot(requestID, @"size"), DXOpenWireMagic | packet.length, pending);
                if (![DXOpenReadRequest(requestID) isEqual:request]) failures++;
                // Wrong ID namespace, corrupted data and oversized metadata fail closed.
                if (DXOpenReadRequest(requestID + 1)) failures++;
                DXOpenWriteWord(DXOpenSlot(requestID, @"4"), 0, pending);
                if (DXOpenReadRequest(requestID)) failures++;
                DXOpenWriteWord(DXOpenSlot(requestID, @"size"), DXOpenWireMagic | (DXOpenMaxPacketBytes + 1), pending);
                if (DXOpenReadRequest(requestID)) failures++;
                for (NSNumber *token in pending.tokens) notify_cancel(token.intValue);
                // Cancelled word slots are no longer usable as a request.
                if (DXOpenReadRequest(requestID)) failures++;
            });
            printf("WIRE failures=%d\n", failures);
            return failures ? 1 : 0;
        }
        return 64;
    }
}
