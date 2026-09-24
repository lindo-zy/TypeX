// TypeXSB — SpringBoard-only companion consumer of the TypeX open-request
// channel (see common.h). Toolbar/url actions triggered in a sandboxed host
// app or keyboard extension cannot open URL schemes through FrontBoard XPC
// (entitlement-rejected), and UIApplication openURL events from a third-party
// source app are exactly what WeChat refuses. Both request kinds therefore
// travel here as one dictionary under one key of the isolated cfprefsd domain
// (the transport the AI chat channel already writes from the same toolbar
// process and that works on device; the 3.5.5 bare-file staging under
// /Library/TypeX had no working precedent for the keyboard-extension writer)
// plus one Darwin notification, and the open executes inside SpringBoard with
// SBSLaunchApplicationWithIdentifierAndLaunchOptions carrying the URL as a
// __LaunchURL launch option -- a system-style launch instead of an openURL
// event, which is what bypasses the interception.
//
// Channel contract (fixed 2026-09-24):
//   * single key, newest-wins: each request replaces the previous value;
//   * the consumer never clears the key, so requests cannot be deleted on
//     consumption -- TTL + requestID dedup make replays inert instead;
//   * one notification name, owned exclusively by this consumer;
//   * an open is never retried, and this dylib never re-posts the request;
//   * every consume/drop outcome is reported under the open-status key in the
//     same domain (quick-action status-v3 precedent for SB writing it); no
//     notification is ever posted back -- the publisher polls after a delay.

#import "common.h"
#import <SpringBoardServices/SpringBoardServices.h>
#import <objc/message.h>

// A request older than this is treated as leftover state (respring, missed
// notification) and dropped, never opened.
static const NSTimeInterval TypeXSBRequestTTL = 10.0;
// Coalesce accidental bursts per the channel protocol ("one open at a time"):
// after the first open the host loses foreground, so a genuine second toolbar
// tap within this window is impossible -- only a replayed notification or a
// runaway chain can land here, and back-to-back launch transactions are what
// used to wedge SpringBoard's main runloop (3.0.71 lesson).
static const NSTimeInterval TypeXSBExecuteThrottle = 1.2;
static const NSUInteger TypeXSBMaxURLLength = 2048;
static const NSUInteger TypeXSBMaxBundleIDLength = 256;

static NSString *gLastConsumedRequestID = nil;
static CFAbsoluteTime gLastExecuteTime = 0;

// Apple schemes that LaunchServices may refuse to resolve and that only
// SpringBoard itself may open. Same table the publisher side used to carry.
static NSString *TypeXSBSensitiveHandlerForScheme(NSString *scheme) {
    static NSDictionary *handlers;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        handlers = @{@"prefs": @"com.apple.Preferences",
                     @"app-prefs": @"com.apple.Preferences"};
    });
    if (scheme.length == 0) return nil;
    return handlers[scheme.lowercaseString];
}

static BOOL TypeXSBIsSensitiveScheme(NSString *scheme) {
    if (scheme.length == 0) return NO;
    static NSSet *sensitive;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        sensitive = [NSSet setWithArray:@[@"prefs", @"app-prefs", @"itms-services"]];
    });
    return [sensitive containsObject:scheme.lowercaseString];
}

// Resolve the bundle identifier owning a URL scheme. Inside SpringBoard the
// LaunchServices query is fully privileged; elements have been observed as
// both NSString and LSApplicationProxy depending on the release, so both
// shapes are accepted. A collision simply takes the first entry.
static NSString *TypeXSBHandlerForScheme(NSString *scheme) {
    NSString *known = TypeXSBSensitiveHandlerForScheme(scheme);
    if (known.length > 0) return known;

    Class workspaceClass = NSClassFromString(@"LSApplicationWorkspace");
    if (!workspaceClass) return nil;
    id workspace = [workspaceClass performSelector:@selector(defaultWorkspace)];
    SEL schemeSelector = @selector(applicationsAvailableForHandlingURLScheme:);
    if (!workspace || ![workspace respondsToSelector:schemeSelector]) return nil;

    @try {
        NSArray *handlers = ((NSArray *(*)(id, SEL, id))objc_msgSend)(workspace, schemeSelector, scheme);
        if (![handlers isKindOfClass:[NSArray class]]) return nil;
        for (id entry in handlers) {
            if ([entry isKindOfClass:[NSString class]]) {
                NSString *identifier = (NSString *)entry;
                if (identifier.length > 0) return identifier;
                continue;
            }
            if ([entry respondsToSelector:@selector(bundleIdentifier)]) {
                NSString *identifier = [entry performSelector:@selector(bundleIdentifier)];
                if ([identifier isKindOfClass:[NSString class]] && identifier.length > 0) return identifier;
            }
        }
    } @catch (__unused NSException *exception) {
        return nil;
    }
    return nil;
}

// One-way outcome report for the publisher's delayed read-back (see
// common.h): newest-wins status key, never posted as a notification. Reached
// from the callback thread or the main queue; cfprefsd serializes writers.
static void TypeXSBReportStatus(NSString *requestID, BOOL ok, NSString *code) {
    if (![requestID isKindOfClass:[NSString class]] || requestID.length == 0) return;
    DXSetQuickActionSharedValue(@{kTypeXOpenRequestIDKey: requestID,
                                  @"ok": @(ok),
                                  @"code": code ?: @"unknown"},
                                TypeXOpenStatusKey);
}

// One launch attempt, zero retries. Primary form is the four-argument
// SBSLaunch with the URL carried in the launchOptions dictionary under
// __LaunchURL; if SpringBoard rejects it, the dedicated URL-carrying variant
// of the same family is tried once as a fallback (a failed launch, not a
// repeated one). Returns the SBS result code of the last attempt.
static int TypeXSBSLaunchApplication(NSString *bundleIdentifier, NSURL *launchURL) {
    int result;
    if (launchURL) {
        NSDictionary *launchOptions = @{ @"__LaunchURL": launchURL };
        result = SBSLaunchApplicationWithIdentifierAndLaunchOptions(bundleIdentifier, @{}, launchOptions, NO);
        NSLog(@"[TypeXSB] launch url bundleID=%@ scheme=%@ result=%d (__LaunchURL)",
              bundleIdentifier, launchURL.scheme, result);
        if (result == 0) return result;
        result = SBSLaunchApplicationWithIdentifierAndURLAndLaunchOptions(bundleIdentifier, launchURL, @{}, @{}, NO);
        NSLog(@"[TypeXSB] launch url bundleID=%@ scheme=%@ result=%d (url variant)",
              bundleIdentifier, launchURL.scheme, result);
        return result;
    }

    result = SBSLaunchApplicationWithIdentifierAndLaunchOptions(bundleIdentifier, @{}, @{}, NO);
    NSLog(@"[TypeXSB] launch app bundleID=%@ result=%d", bundleIdentifier, result);
    return result;
}

// Runs on the main queue. One request -> at most one launch call chain.
static void TypeXSBPerformOpenRequest(NSDictionary *request) {
    NSString *kind = request[kTypeXOpenRequestKindKey];
    NSString *requestID = request[kTypeXOpenRequestIDKey];

    if ([kind isEqualToString:kTypeXOpenKindURL]) {
        NSURL *url = [NSURL URLWithString:request[kTypeXOpenRequestURLKey]];
        if (![url.scheme isKindOfClass:[NSString class]] || url.scheme.length == 0) {
            NSLog(@"[TypeXSB] url request without usable scheme, dropped");
            TypeXSBReportStatus(requestID, NO, @"url-noscheme");
            return;
        }

        // Sensitive Apple schemes keep the privileged SpringBoard route that
        // has always handled them; the launch-option path is the fallback.
        if (TypeXSBIsSensitiveScheme(url.scheme)) {
            if (SBSOpenSensitiveURLAndUnlock((__bridge CFURLRef)url, 0)) {
                NSLog(@"[TypeXSB] sensitive open scheme=%@ result=1", url.scheme);
                TypeXSBReportStatus(requestID, YES, @"sensitive");
                return;
            }
            NSLog(@"[TypeXSB] sensitive open scheme=%@ failed, falling back to launch", url.scheme);
        }

        NSString *handler = TypeXSBHandlerForScheme(url.scheme);
        if (handler.length == 0) {
            NSLog(@"[TypeXSB] no handler for scheme %@, dropped", url.scheme);
            TypeXSBReportStatus(requestID, NO, @"nohandler");
            return;
        }
        int result = TypeXSBSLaunchApplication(handler, url);
        TypeXSBReportStatus(requestID, result == 0,
                            [NSString stringWithFormat:@"launch:%d", result]);
        return;
    }

    if ([kind isEqualToString:kTypeXOpenKindOpenApp]) {
        NSString *bundleIdentifier = request[kTypeXOpenRequestBundleIDKey];
        if (!DXIsValidBundleIdentifier(bundleIdentifier)) {
            NSLog(@"[TypeXSB] openapp request with invalid bundle ID, dropped");
            TypeXSBReportStatus(requestID, NO, @"badbundle");
            return;
        }
        int result = TypeXSBSLaunchApplication(bundleIdentifier, nil);
        TypeXSBReportStatus(requestID, result == 0,
                            [NSString stringWithFormat:@"app:%d", result]);
        return;
    }

    NSLog(@"[TypeXSB] unknown kind %@, dropped", kind);
    TypeXSBReportStatus(requestID, NO, @"unknown-kind");
}

static void TypeXSBOpenRequestCallback(CFNotificationCenterRef center,
                                       void *observer,
                                       CFStringRef name,
                                       const void *object,
                                       CFDictionaryRef userInfo) {
    // Same read pattern the AI channel consumer uses: Synchronize first so a
    // just-written request is visible, then copy the single newest-wins key.
    id rawRequest = DXQuickActionSharedValue(TypeXOpenRequestKey);
    if (![rawRequest isKindOfClass:[NSDictionary class]]) {
        NSLog(@"[TypeXSB] request slot unreadable, dropped");
        return;
    }
    NSDictionary *request = rawRequest;

    NSNumber *format = [request[kTypeXOpenRequestFormatKey] isKindOfClass:[NSNumber class]]
        ? request[kTypeXOpenRequestFormatKey] : nil;
    NSString *requestID = [request[kTypeXOpenRequestIDKey] isKindOfClass:[NSString class]]
        ? request[kTypeXOpenRequestIDKey] : nil;
    NSNumber *created = [request[kTypeXOpenRequestCreatedKey] isKindOfClass:[NSNumber class]]
        ? request[kTypeXOpenRequestCreatedKey] : nil;
    NSString *kind = [request[kTypeXOpenRequestKindKey] isKindOfClass:[NSString class]]
        ? request[kTypeXOpenRequestKindKey] : nil;
    NSString *payload = request[kTypeXOpenRequestURLKey];
    if (![payload isKindOfClass:[NSString class]]) payload = request[kTypeXOpenRequestBundleIDKey];
    if (![payload isKindOfClass:[NSString class]]) payload = nil;

    if (format.integerValue != 1 || requestID.length == 0 || kind.length == 0 || payload.length == 0) {
        NSLog(@"[TypeXSB] malformed request (format=%@ id=%@ kind=%@), dropped",
              format, requestID.length > 0 ? @"set" : @"missing", kind);
        TypeXSBReportStatus(requestID, NO, @"malformed");
        return;
    }
    if (payload.length > ([kind isEqualToString:kTypeXOpenKindURL] ? TypeXSBMaxURLLength
                                                                   : TypeXSBMaxBundleIDLength)) {
        NSLog(@"[TypeXSB] request payload over limit, dropped");
        TypeXSBReportStatus(requestID, NO, @"payload-limit");
        return;
    }

    NSTimeInterval age = created ? [NSDate date].timeIntervalSince1970 - created.doubleValue : NAN;
    if (!(age >= 0 && age <= TypeXSBRequestTTL)) {
        NSLog(@"[TypeXSB] stale request (age=%.1fs), dropped", age);
        TypeXSBReportStatus(requestID, NO, @"stale");
        return;
    }
    if ([requestID isEqualToString:gLastConsumedRequestID]) {
        // Replay of the notification for a slot already consumed. The slot is
        // never cleared, so dedup lives on the request identity. Its outcome
        // was already reported under this requestID.
        return;
    }

    CFAbsoluteTime now = CFAbsoluteTimeGetCurrent();
    if (gLastExecuteTime > 0 && now - gLastExecuteTime < TypeXSBExecuteThrottle) {
        NSLog(@"[TypeXSB] throttled burst, dropped id=%@", requestID);
        TypeXSBReportStatus(requestID, NO, @"throttled");
        return;
    }

    gLastConsumedRequestID = requestID;
    gLastExecuteTime = now;
    NSLog(@"[TypeXSB] consumed kind=%@ age=%.1fs", kind, age);
    dispatch_async(dispatch_get_main_queue(), ^{
        TypeXSBPerformOpenRequest(request);
    });
}

%ctor {
    @autoreleasepool {
        CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(),
                                        NULL, &TypeXSBOpenRequestCallback,
                                        (CFStringRef)kTypeXOpenRequestIdentifier, NULL,
                                        CFNotificationSuspensionBehaviorDeliverImmediately);
        NSLog(@"[TypeXSB] open-request channel ready");
    }
}
