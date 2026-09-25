#import "../DXSensitiveURLExecutor.h"
#import <unistd.h>

typedef NS_OPTIONS(NSUInteger, TestFlags) {
    DeliveryFailure = 1 << 0, DeliveryException = 1 << 1,
    ActivationFailure = 1 << 2, ActivationException = 1 << 3,
    CancelBefore = 1 << 4, CancelDuring = 1 << 5,
    ExpireBefore = 1 << 6, ExpireDuring = 1 << 7,
    MissingActivation = 1 << 8, MissingDelivery = 1 << 9,
};

static BOOL RunCase(NSString *urlString, TestFlags flags, DXSystemOpenResult expected,
                    NSUInteger expectedDeliveries, NSUInteger expectedActivations) {
    NSURL *url = [NSURL URLWithString:urlString];
    NSProgress *operation = [NSProgress discreteProgressWithTotalUnitCount:1];
    if (flags & CancelBefore) [operation cancel];
    NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:(flags & ExpireBefore) ? -1 : ((flags & ExpireDuring) ? 0.03 : 2)];
    __block NSUInteger deliveries = 0, activations = 0, replies = 0;
    __block BOOL finished = NO, heartbeat = NO, deliveryFinished = NO, valid = YES;
    __block DXSystemOpenResult outcome = 0;
    DXSensitiveURLDelivery deliver = ^BOOL(NSURL *received) {
        deliveries++;
        valid &= !NSThread.isMainThread && [received.absoluteString isEqualToString:urlString];
        // Model a synchronous SBS RPC waiting for SpringBoard's main queue.
        // This must complete while the RPC is outstanding, not after it returns.
        dispatch_semaphore_t processed = dispatch_semaphore_create(0);
        dispatch_async(dispatch_get_main_queue(), ^{
            heartbeat = YES;
            if (flags & CancelDuring) [operation cancel];
            dispatch_semaphore_signal(processed);
        });
        valid &= dispatch_semaphore_wait(processed, dispatch_time(DISPATCH_TIME_NOW, NSEC_PER_SEC / 2)) == 0;
        if (flags & ExpireDuring) usleep(60000);
        deliveryFinished = YES;
        if (flags & DeliveryException) @throw [NSException exceptionWithName:@"DeliveryTest" reason:nil userInfo:nil];
        return !(flags & DeliveryFailure);
    };
    DXSensitiveURLActivation activate = ^DXSystemOpenResult(NSString *bundleIdentifier) {
        activations++;
        valid &= NSThread.isMainThread && deliveryFinished && heartbeat && [bundleIdentifier isEqualToString:@"com.apple.Preferences"];
        if (flags & ActivationException) @throw [NSException exceptionWithName:@"ActivationTest" reason:nil userInfo:nil];
        return flags & ActivationFailure ? DXSystemOpenFailed : DXSystemOpenSucceeded;
    };
    DXExecuteSensitiveURL(url, deadline, operation,
                          flags & MissingDelivery ? nil : deliver,
                          flags & MissingActivation ? nil : activate,
                          ^(DXSystemOpenResult result) {
        valid &= NSThread.isMainThread;
        replies++;
        outcome = result;
        finished = YES;
    });
    NSDate *stop = [NSDate dateWithTimeIntervalSinceNow:3];
    while (!finished && stop.timeIntervalSinceNow > 0) {
        [[NSRunLoop mainRunLoop] runMode:NSDefaultRunLoopMode beforeDate:[NSDate dateWithTimeIntervalSinceNow:0.01]];
    }
    BOOL passed = finished && valid && replies == 1 && outcome == expected &&
        deliveries == expectedDeliveries && activations == expectedActivations;
    printf("%s scheme=%s flags=%lu deliveries=%lu activations=%lu result=%llu\n",
           passed ? "PASS" : "FAIL", url.scheme.UTF8String, (unsigned long)flags,
           (unsigned long)deliveries, (unsigned long)activations, (unsigned long long)outcome);
    return passed;
}

int main(void) {
    @autoreleasepool {
        NSUInteger failures = 0;
        NSString *prefs = @"prefs:root=XXXX&path=detail%2Fsection&value=%E4%B8%AD%E6%96%87";
        failures += !RunCase(prefs, 0, DXSystemOpenSucceeded, 1, 1);
        failures += !RunCase(@"App-Prefs:root=WIFI", 0, DXSystemOpenSucceeded, 1, 1);
        failures += !RunCase(@"itms-services://?action=download-manifest", 0, DXSystemOpenSucceeded, 1, 0);
        failures += !RunCase(prefs, DeliveryFailure, DXSystemOpenFailed, 1, 0);
        failures += !RunCase(prefs, DeliveryException, DXSystemOpenFailed, 1, 0);
        failures += !RunCase(prefs, ActivationFailure, DXSystemOpenFailed, 1, 1);
        failures += !RunCase(prefs, ActivationException, DXSystemOpenFailed, 1, 1);
        failures += !RunCase(prefs, CancelBefore, DXSystemOpenExpired, 0, 0);
        failures += !RunCase(prefs, CancelDuring, DXSystemOpenExpired, 1, 0);
        failures += !RunCase(prefs, ExpireBefore, DXSystemOpenExpired, 0, 0);
        failures += !RunCase(prefs, ExpireDuring, DXSystemOpenExpired, 1, 0);
        failures += !RunCase(prefs, MissingActivation, DXSystemOpenUnavailable, 1, 0);
        failures += !RunCase(prefs, MissingDelivery, DXSystemOpenUnavailable, 0, 0);
        printf("Sensitive URL executor: %lu failures\n", (unsigned long)failures);
        return failures ? 1 : 0;
    }
}
