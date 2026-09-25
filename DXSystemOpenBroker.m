#import "DXSystemOpenBroker.h"
#import "DXSensitiveURLExecutor.h"
#import "DXQuickActionProvider.h"
#import "common.h"
#import <objc/message.h>
#import <dlfcn.h>

BOOL DXIsSensitiveOpenScheme(NSString *scheme) {
    NSString *lower = scheme.lowercaseString;
    return [lower isEqualToString:@"prefs"] || [lower isEqualToString:@"app-prefs"] ||
           [lower isEqualToString:@"itms-services"];
}

static BOOL DXIsSystemOpenServerProcess(void) {
    return [NSProcessInfo.processInfo.processName isEqualToString:@"SpringBoard"];
}

// Accessed on the main queue; NSProgress cancellation can be read by the RPC
// worker. A newer system action invalidates an older pending foreground step.
static NSProgress *DXCurrentSystemOpenRequest;

static NSProgress *DXBeginSystemOpenOperation(void) {
    [DXCurrentSystemOpenRequest cancel];
    DXCurrentSystemOpenRequest = [NSProgress discreteProgressWithTotalUnitCount:1];
    return DXCurrentSystemOpenRequest;
}

static DXSystemOpenResult DXActivateSystemApplication(NSString *bundleIdentifier) {
    // Activate inside SpringBoard through the same native selector used by
    // local PullOver-X. No URL event is sent through WeChat and no invented
    // __LaunchURL option is involved. Check the runtime BOOL return ABI;
    // historical headers disagree about this method's return type.
    UIApplication *application = UIApplication.sharedApplication;
    SEL launch = NSSelectorFromString(@"launchApplicationWithIdentifier:suspended:");
    NSMethodSignature *signature = [application methodSignatureForSelector:launch];
    const char *returnType = signature.methodReturnType;
    if (!application || ![application respondsToSelector:launch] || signature.numberOfArguments != 4 || !returnType ||
        (strcmp(returnType, @encode(BOOL)) != 0 && strcmp(returnType, "c") != 0)) {
        return DXSystemOpenUnavailable;
    }
    NSLog(@"[TypeXSB] native application dispatch bundleID=%@", bundleIdentifier);
    BOOL opened = ((BOOL (*)(id, SEL, id, BOOL))objc_msgSend)(application, launch, bundleIdentifier, NO);
    NSLog(@"[TypeXSB] native application bundleID=%@ result=%d", bundleIdentifier, opened);
    return opened ? DXSystemOpenSucceeded : DXSystemOpenFailed;
}

// Runs only in SpringBoard, on the main queue. The requester never supplies
// an Objective-C selector or an arbitrary launch-options dictionary.
static void DXPerformSystemOpen(NSDictionary *request, DXSystemOpenReply reply) {
    if (!DXIsSystemOpenServerProcess() || !NSThread.isMainThread) {
        reply(DXSystemOpenUnavailable);
        return;
    }
    NSString *kind = request[@"kind"];
    NSString *payload = request[@"payload"];
    if (![kind isKindOfClass:NSString.class] || ![payload isKindOfClass:NSString.class] || !payload.length) {
        reply(DXSystemOpenInvalid);
        return;
    }
    if ([kind isEqualToString:@"quick-action"]) {
        NSData *data = [payload dataUsingEncoding:NSUTF8StringEncoding];
        if (!data.length || data.length > 4096) { reply(DXSystemOpenInvalid); return; }
        id fields = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
        if (![fields isKindOfClass:NSDictionary.class]) { reply(DXSystemOpenInvalid); return; }
        NSString *bundleIdentifier = fields[@"bundleID"];
        NSString *shortcutType = fields[@"shortcutType"];
        if (!DXIsValidBundleIdentifier(bundleIdentifier) || bundleIdentifier.length > 256 ||
            !DXIsValidAppShortcutType(shortcutType)) { reply(DXSystemOpenInvalid); return; }
        NSTimeInterval age = [NSDate date].timeIntervalSince1970 - [request[@"created"] doubleValue];
        if (!(age >= 0 && age <= DXSystemOpenRequestTTL)) { reply(DXSystemOpenExpired); return; }
        DXBeginSystemOpenOperation();
        reply([DXQuickActionProvider activateShortcutWithBundleIdentifier:bundleIdentifier type:shortcutType]);
        return;
    }
    if ([kind isEqualToString:@"sensitive-url"]) {
        NSURL *url = [NSURL URLWithString:payload];
        if (!url || payload.length > 2048 || !DXIsSensitiveOpenScheme(url.scheme)) { reply(DXSystemOpenInvalid); return; }
        typedef bool (*DXSensitiveOpen)(CFURLRef, char);
        DXSensitiveOpen openSensitive = (DXSensitiveOpen)dlsym(RTLD_DEFAULT, "SBSOpenSensitiveURLAndUnlock");
        if (!openSensitive) { reply(DXSystemOpenUnavailable); return; }
        // Preserve the original deadline across the worker queue. A queued RPC
        // cannot become a surprise open after the caller's request expired.
        NSNumber *created = request[@"created"];
        NSDate *deadline = [NSDate dateWithTimeIntervalSince1970:created.doubleValue + DXSystemOpenRequestTTL];
        DXExecuteSensitiveURL(url, deadline, DXBeginSystemOpenOperation(), ^BOOL(NSURL *sensitiveURL) {
            return openSensitive((__bridge CFURLRef)sensitiveURL, 0);
        }, ^DXSystemOpenResult(NSString *bundleIdentifier) {
            return DXActivateSystemApplication(bundleIdentifier);
        }, reply);
        return;
    }
    if (![kind isEqualToString:@"application"] || payload.length > 256 || !DXIsValidBundleIdentifier(payload)) {
        reply(DXSystemOpenInvalid);
        return;
    }

    DXBeginSystemOpenOperation();
    reply(DXActivateSystemApplication(payload));
}

static void DXSubmitSystemOpen(NSString *kind, NSString *payload, DXSystemOpenReply reply) {
    if (DXIsSystemOpenServerProcess()) {
        NSDictionary *request = @{@"kind": kind, @"payload": payload ?: @"",
                                   @"created": @([NSDate date].timeIntervalSince1970)};
        dispatch_async(dispatch_get_main_queue(), ^{
            __block BOOL completed = NO;
            DXSystemOpenReply finish = ^(DXSystemOpenResult result) {
                dispatch_async(dispatch_get_main_queue(), ^{
                    if (completed) return;
                    completed = YES;
                    if (reply) reply(result);
                });
            };
            @try { DXPerformSystemOpen(request, finish); }
            @catch (NSException *exception) {
                NSLog(@"[TypeXSB] direct exception=%@", exception.name);
                finish(DXSystemOpenFailed);
            }
        });
        return;
    }
    DXSendDarwinOpenRequest(kind, payload, reply);
}

void DXOpenSystemApplication(NSString *bundleIdentifier, DXSystemOpenReply reply) {
    DXSubmitSystemOpen(@"application", bundleIdentifier, reply);
}

void DXOpenSensitiveSystemURL(NSURL *url, DXSystemOpenReply reply) {
    DXSubmitSystemOpen(@"sensitive-url", url.absoluteString, reply);
}

BOOL DXStartSystemOpenBroker(void) {
    if (!DXIsSystemOpenServerProcess()) return NO;
    return DXStartDarwinOpenServer(^(NSDictionary *request, DXSystemOpenReply reply) {
        DXPerformSystemOpen(request, reply);
    });
}

void DXOpenSystemShortcut(NSString *bundleIdentifier, NSString *shortcutType, DXSystemOpenReply reply) {
    if (!DXIsValidBundleIdentifier(bundleIdentifier) || bundleIdentifier.length > 256 ||
        !DXIsValidAppShortcutType(shortcutType)) {
        if (reply) dispatch_async(dispatch_get_main_queue(), ^{ reply(DXSystemOpenInvalid); });
        return;
    }
    NSData *data = [NSJSONSerialization dataWithJSONObject:@{@"bundleID": bundleIdentifier, @"shortcutType": shortcutType}
                                                 options:0 error:nil];
    if (!data.length || data.length > 4096) {
        if (reply) dispatch_async(dispatch_get_main_queue(), ^{ reply(DXSystemOpenInvalid); });
        return;
    }
    DXSubmitSystemOpen(@"quick-action", [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding], reply);
}
