#import "DXSensitiveURLExecutor.h"

static dispatch_queue_t DXSensitiveURLQueue(void) {
    static dispatch_queue_t queue;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        queue = dispatch_queue_create("com.lindo.typex.open.sensitive-rpc", DISPATCH_QUEUE_SERIAL);
    });
    return queue;
}

static BOOL DXSensitiveRequestExpired(NSProgress *request, NSDate *deadline) {
    return !request || request.cancelled || !deadline || !(deadline.timeIntervalSinceNow > 0);
}

void DXExecuteSensitiveURL(NSURL *url, NSDate *deadline, NSProgress *request,
                          DXSensitiveURLDelivery deliver,
                          DXSensitiveURLActivation activate, DXSystemOpenReply reply) {
    NSString *scheme = url.scheme.lowercaseString;
    NSString *foregroundBundle = ([scheme isEqualToString:@"prefs"] || [scheme isEqualToString:@"app-prefs"])
        ? @"com.apple.Preferences" : nil;
    dispatch_async(DXSensitiveURLQueue(), ^{
        @autoreleasepool {
            __block DXSystemOpenResult result = DXSystemOpenUnavailable;
            if (DXSensitiveRequestExpired(request, deadline)) {
                result = DXSystemOpenExpired;
            } else if (deliver) {
                // SBSOpenSensitiveURLAndUnlock is a synchronous client entry
                // point into SpringBoard. Waiting for it on SpringBoard's UI
                // thread can hold up the activation it is asking to perform.
                NSLog(@"[TypeXSB] sensitive RPC begin scheme=%@", scheme);
                @try { result = deliver(url) ? DXSystemOpenSucceeded : DXSystemOpenFailed; }
                @catch (NSException *exception) {
                    NSLog(@"[TypeXSB] sensitive RPC exception=%@", exception.name);
                    result = DXSystemOpenFailed;
                }
                NSLog(@"[TypeXSB] sensitive RPC end scheme=%@ result=%llu", scheme, (unsigned long long)result);
            }
            dispatch_async(dispatch_get_main_queue(), ^{
                // The RPC cannot be cancelled once entered. An old result must
                // not foreground Settings after a newer action or a timeout.
                if (DXSensitiveRequestExpired(request, deadline)) {
                    result = DXSystemOpenExpired;
                } else if (result == DXSystemOpenSucceeded && foregroundBundle) {
                    @try { result = activate ? activate(foregroundBundle) : DXSystemOpenUnavailable; }
                    @catch (NSException *exception) {
                        NSLog(@"[TypeXSB] sensitive foreground exception=%@", exception.name);
                        result = DXSystemOpenFailed;
                    }
                    NSLog(@"[TypeXSB] sensitive foreground bundleID=%@ result=%llu",
                          foregroundBundle, (unsigned long long)result);
                }
                if (reply) reply(result);
            });
        }
    });
}
