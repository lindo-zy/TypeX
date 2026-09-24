#import "DXSystemOpenBroker.h"
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
    if ([kind isEqualToString:@"sensitive-url"]) {
        NSURL *url = [NSURL URLWithString:payload];
        if (!url || payload.length > 2048 || !DXIsSensitiveOpenScheme(url.scheme)) { reply(DXSystemOpenInvalid); return; }
        typedef bool (*DXSensitiveOpen)(CFURLRef, char);
        DXSensitiveOpen openSensitive = (DXSensitiveOpen)dlsym(RTLD_DEFAULT, "SBSOpenSensitiveURLAndUnlock");
        if (!openSensitive) { reply(DXSystemOpenUnavailable); return; }
        BOOL opened = openSensitive((__bridge CFURLRef)url, NO);
        NSLog(@"[TypeXSB] sensitive scheme=%@ result=%d", url.scheme.lowercaseString, opened);
        reply(opened ? DXSystemOpenSucceeded : DXSystemOpenFailed);
        return;
    }
    if (![kind isEqualToString:@"application"] || payload.length > 256 || !DXIsValidBundleIdentifier(payload)) {
        reply(DXSystemOpenInvalid);
        return;
    }

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
        reply(DXSystemOpenUnavailable);
        return;
    }
    NSLog(@"[TypeXSB] native application dispatch bundleID=%@", payload);
    BOOL opened = ((BOOL (*)(id, SEL, id, BOOL))objc_msgSend)(application, launch, payload, NO);
    NSLog(@"[TypeXSB] native application bundleID=%@ result=%d", payload, opened);
    reply(opened ? DXSystemOpenSucceeded : DXSystemOpenFailed);
}

static void DXSubmitSystemOpen(NSString *kind, NSString *payload, DXSystemOpenReply reply) {
    if (DXIsSystemOpenServerProcess()) {
        dispatch_async(dispatch_get_main_queue(), ^{
            __block BOOL completed = NO;
            DXSystemOpenReply finish = ^(DXSystemOpenResult result) {
                dispatch_async(dispatch_get_main_queue(), ^{
                    if (completed) return;
                    completed = YES;
                    if (reply) reply(result);
                });
            };
            @try { DXPerformSystemOpen(@{@"kind": kind, @"payload": payload ?: @""}, finish); }
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
