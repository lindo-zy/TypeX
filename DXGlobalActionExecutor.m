#import "DXGlobalActionExecutor.h"
#import "DXGlobalPanelPolicy.h"
#import "DXGlobalPanel.h"
#import "DXShortcutsGenerator.h"
#import "common.h"
#import <notify.h>

void DXExecuteGlobalCustomAction(NSDictionary *entry, DXSystemOpenReply reply) {
    if (!NSThread.isMainThread || ![NSProcessInfo.processInfo.processName isEqual:@"SpringBoard"] ||
        ![DXGlobalPanel deviceUnlocked] || !DXGlobalCustomActionSupported(entry)) {
        if (reply) reply(DXSystemOpenUnavailable);
        return;
    }
    NSString *type = DXGlobalPanelString(entry[@"type"]);
    NSString *payload = DXGlobalPanelNormalizedPayload(entry[@"link"]);
    if ([type isEqual:kCustomActionTypeSystem]) { DXRunSystemAction(entry[kCustomActionSystemIdentifierKey], reply); return; }
    if ([type isEqual:kCustomActionTypeShortcut]) { DXOpenSystemShortcut(payload, entry[kCustomActionShortcutTypeKey], reply); return; }
    if ([type isEqual:kCustomActionTypeOpenApp] || (!type.length && DXIsValidBundleIdentifier(payload))) {
        if (!DXIsValidBundleIdentifier(payload)) { if (reply) reply(DXSystemOpenInvalid); return; }
        if ([entry[kCustomActionUsePullOverKey] isKindOfClass:NSNumber.class] && [entry[kCustomActionUsePullOverKey] boolValue] && [DXShortcutsGenerator isPullOverXInstalled]) {
            int token = NOTIFY_TOKEN_INVALID;
            uint64_t state = DXPullOverOpenStateForBundleIdentifier(payload);
            BOOL published = state && notify_register_check(kPullOverOpenRequestIdentifier.UTF8String, &token) == NOTIFY_STATUS_OK &&
                notify_set_state(token, state) == NOTIFY_STATUS_OK && notify_post(kPullOverOpenRequestIdentifier.UTF8String) == NOTIFY_STATUS_OK;
            if (token != NOTIFY_TOKEN_INVALID) notify_cancel(token);
            if (published) { if (reply) reply(DXSystemOpenSucceeded); return; }
        }
        DXOpenSystemApplication(payload, reply); return;
    }
    NSURL *url = DXIsOpenableSchemeURLString(payload) ? [NSURL URLWithString:payload] : nil;
    if ([type isEqual:kCustomActionTypeURL] && (!url.host.length || ![@[@"http", @"https"] containsObject:url.scheme.lowercaseString])) url = nil;
    if (!url) { if (reply) reply(DXSystemOpenInvalid); return; }
    if (DXIsSensitiveOpenScheme(url.scheme)) { DXOpenSensitiveSystemURL(url, reply); return; }
    UIApplication *application = UIApplication.sharedApplication;
    if (![application respondsToSelector:@selector(openURL:options:completionHandler:)]) {
        if (reply) reply(DXSystemOpenUnavailable); return;
    }
    @try {
        // One dispatch even when another tweak swallows the completion.
        [application openURL:url options:@{} completionHandler:^(BOOL success) {
            if (reply) reply(success ? DXSystemOpenSucceeded : DXSystemOpenFailed);
        }];
    } @catch (__unused NSException *exception) { if (reply) reply(DXSystemOpenFailed); }
}
