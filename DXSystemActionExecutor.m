#import "DXSystemActionExecutor.h"
#import "DXSystemActionCatalog.h"
#import "DXSystemActionInvocation.h"
#import "common.h"
#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <dlfcn.h>
#import <mach-o/dyld.h>
#include <signal.h>
#include <unistd.h>

static __weak UIAlertController *DXSystemActionConfirmation;

void DXCancelSystemActionConfirmation(void) {
    if (!NSThread.isMainThread) return;
    [DXSystemActionConfirmation dismissViewControllerAnimated:NO completion:nil];
    DXSystemActionConfirmation = nil;
}

BOOL DXConfirmSystemExitAction(NSString *action, NSProgress *operation) {
    if (!DXSystemExitActionAvailable(action) || ![DXSystemActionDefinition(action)[@"destructive"] boolValue]) return NO;
    UIWindow *window = DXKeyWindow();
    UIViewController *presenter = window.rootViewController;
    while (presenter.presentedViewController && !presenter.presentedViewController.isBeingDismissed)
        presenter = presenter.presentedViewController;
    if (!presenter || !window || window.hidden || presenter.view.window != window) return NO;
    NSBundle *bundle = [NSBundle bundleWithPath:bundlePath];
    NSString *title = [bundle localizedStringForKey:DXSystemActionDefinition(action)[@"title"] value:action table:nil];
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:title
        message:[bundle localizedStringForKey:@"SYSTEM_ACTION_CONFIRM" value:@"Continue?" table:nil]
        preferredStyle:UIAlertControllerStyleAlert];
    NSTimeInterval deadline = NSDate.date.timeIntervalSince1970 + 60;
    __weak UIWindow *originalWindow = window;
    __weak UIViewController *originalPresenter = presenter;
    __weak UIAlertController *originalAlert = alert;
    [alert addAction:[UIAlertAction actionWithTitle:[bundle localizedStringForKey:@"CANCEL" value:@"Cancel" table:nil]
        style:UIAlertActionStyleCancel handler:^(__unused UIAlertAction *choice) {
            if (DXSystemActionConfirmation == originalAlert) DXSystemActionConfirmation = nil;
            [operation cancel];
        }]];
    [alert addAction:[UIAlertAction actionWithTitle:[bundle localizedStringForKey:@"ANSWER_YES" value:@"Continue" table:nil]
        style:UIAlertActionStyleDestructive handler:^(__unused UIAlertAction *choice) {
            BOOL current = DXSystemActionConfirmation == originalAlert;
            if (current) DXSystemActionConfirmation = nil;
            UIWindow *source = originalWindow;
            if (!current || operation.cancelled || !source || source.hidden || DXKeyWindow() != source ||
                originalPresenter.view.window != source || NSDate.date.timeIntervalSince1970 > deadline) return;
            DXSystemOpenResult result = DXPerformSystemAction(action);
            NSLog(@"[TypeX][SystemAction] confirmed id=%@ result=%llu", action, (unsigned long long)result);
            if (result != DXSystemOpenSucceeded) {
                UIAlertController *error = [UIAlertController alertControllerWithTitle:title
                    message:[bundle localizedStringForKey:@"SYSTEM_ACTION_UNAVAILABLE" value:@"Unavailable" table:nil]
                    preferredStyle:UIAlertControllerStyleAlert];
                [error addAction:[UIAlertAction actionWithTitle:[bundle localizedStringForKey:@"ANSWER_OK" value:@"OK" table:nil]
                    style:UIAlertActionStyleDefault handler:nil]];
                UIAlertController *prompt = originalAlert;
                [prompt dismissViewControllerAnimated:YES completion:^{
                    UIWindow *currentWindow = originalWindow;
                    UIViewController *currentPresenter = originalPresenter;
                    if (operation.cancelled || !currentWindow || currentWindow.hidden || DXKeyWindow() != currentWindow ||
                        currentPresenter.view.window != currentWindow || currentPresenter.presentedViewController ||
                        NSDate.date.timeIntervalSince1970 > deadline) return;
                    [currentPresenter presentViewController:error animated:YES completion:nil];
                }];
            }
        }]];
    DXSystemActionConfirmation = alert;
    [presenter presentViewController:alert animated:YES completion:nil];
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 60 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
        if (DXSystemActionConfirmation != originalAlert || !originalAlert) return;
        [operation cancel];
        DXCancelSystemActionConfirmation();
    });
    return YES;
}

static void DXLoadSystemActionFrameworks(void) {
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        for (NSString *name in @[@"BluetoothManager", @"DoNotDisturb", @"DoNotDisturbKit", @"AVFCapture"]) {
            NSString *path = [NSString stringWithFormat:@"/System/Library/PrivateFrameworks/%@.framework/%@", name, name];
            dlopen(path.fileSystemRepresentation, RTLD_LAZY | RTLD_GLOBAL);
        }
        dlopen("/System/Library/Frameworks/CoreTelephony.framework/CoreTelephony", RTLD_LAZY | RTLD_GLOBAL);
    });
}

static id DXSystemShared(NSString *className, NSString *selector) {
    id result = nil;
    return DXSystemInvoke(NSClassFromString(className), selector, @[], &result) ? result : nil;
}

static DXSystemOpenResult DXSystemCall(id target, NSString *selector, NSArray *arguments) {
    id result = nil;
    if (!DXSystemInvoke(target, selector, arguments, &result)) {
        NSLog(@"[TypeX][SystemAction] unavailable class=%@ selector=%@", target ? NSStringFromClass([target class]) : @"nil", selector);
        return DXSystemOpenUnavailable;
    }
    return [result isKindOfClass:NSNumber.class] && ![result boolValue] ? DXSystemOpenFailed : DXSystemOpenSucceeded;
}

static DXSystemOpenResult DXSystemToggle(id target, NSString *getter, NSString *setter) {
    id state = nil;
    if (!DXSystemInvoke(target, getter, @[], &state) || ![state isKindOfClass:NSNumber.class]) return DXSystemOpenUnavailable;
    return DXSystemCall(target, setter, @[@(![state boolValue])]);
}

static BOOL DXSafeModeHandlerLoaded(void) {
    for (uint32_t i = 0; i < _dyld_image_count(); i++) {
        const char *name = _dyld_get_image_name(i);
        NSString *image = name ? [NSString stringWithUTF8String:name].lowercaseString : nil;
        if ([image containsString:@"safemode"] || [image containsString:@"mobilesafety"]) return YES;
    }
    return NO;
}

BOOL DXSystemExitActionAvailable(NSString *action) {
    if (![NSProcessInfo.processInfo.processName isEqualToString:@"SpringBoard"] || !NSThread.isMainThread) return NO;
    if ([action isEqual:@"respring-sb"]) return YES;
    if ([action isEqual:@"safe-mode"]) return DXSafeModeHandlerLoaded();
    // Use the exact userspace flag; never fall back to a full reboot or to a shell.
    // This syscall needs privileges that a particular jailbreak may not grant SB.
    if ([action isEqual:@"userspace-reboot"]) return dlsym(RTLD_DEFAULT, "reboot3") != NULL;
    id service = DXSystemShared(@"FBSSystemService", @"sharedService");
    if ([action isEqual:@"shutdown"]) return [service respondsToSelector:NSSelectorFromString(@"shutdown")];
    if ([action isEqual:@"reboot"]) return [service respondsToSelector:NSSelectorFromString(@"reboot")];
    if ([action isEqual:@"respring"]) return [service respondsToSelector:NSSelectorFromString(@"sendActions:withResult:")] &&
        [NSClassFromString(@"SBSRelaunchAction") respondsToSelector:NSSelectorFromString(@"actionWithReason:options:targetURL:")];
    return NO;
}

DXSystemOpenResult DXPerformSystemAction(NSString *action) {
    if (!DXSystemActionDefinition(action)) return DXSystemOpenInvalid;
    if (![NSProcessInfo.processInfo.processName isEqualToString:@"SpringBoard"] || !NSThread.isMainThread) return DXSystemOpenUnavailable;
    DXLoadSystemActionFrameworks();
    NSLog(@"[TypeX][SystemAction] execute id=%@", action);
    if ([action isEqual:@"previous-track"] || [action isEqual:@"next-track"]) {
        return DXSystemCall(DXSystemShared(@"SBMediaController", @"sharedInstance"), @"changeTrack:eventSource:",
            @[@([action isEqual:@"next-track"] ? 1 : -1), @0]);
    }
    if ([action isEqual:@"play-pause"]) return DXSystemCall(DXSystemShared(@"SBMediaController", @"sharedInstance"), @"togglePlayPauseForEventSource:", @[@0]);
    if ([action isEqual:@"home"]) return DXSystemCall(UIApplication.sharedApplication, @"_simulateHomeButtonPress", @[]);
    if ([action isEqual:@"switcher"]) {
        id coordinator = DXSystemShared(@"SBMainSwitcherControllerCoordinator", @"sharedInstance");
        NSString *selector = @"toggleSwitcherNoninteractivelyWithSource:";
        if (![coordinator respondsToSelector:NSSelectorFromString(selector)]) coordinator = DXSystemShared(@"SBMainSwitcherViewController", @"sharedInstance");
        return DXSystemCall(coordinator, selector, @[@1]);
    }
    if ([action isEqual:@"control-center"]) return DXSystemCall(DXSystemShared(@"SBControlCenterController", @"sharedInstance"), @"presentAnimated:completion:", @[@YES, NSNull.null]);
    if ([action isEqual:@"wifi"]) return DXSystemToggle(DXSystemShared(@"SBWiFiManager", @"sharedInstance"), @"wiFiEnabled", @"setWiFiEnabled:");
    if ([action isEqual:@"bluetooth"]) return DXSystemToggle(DXSystemShared(@"BluetoothManager", @"sharedInstance"), @"powered", @"setPowered:");
    if ([action isEqual:@"airplane"]) return DXSystemToggle(DXSystemShared(@"SBAirplaneModeController", @"sharedInstance"), @"isInAirplaneMode", @"setInAirplaneMode:");
    if ([action isEqual:@"cellular"]) {
        typedef Boolean (*GetData)(void);
        typedef void (*SetData)(Boolean);
        GetData get = (GetData)dlsym(RTLD_DEFAULT, "CTCellularDataPlanGetIsEnabled");
        SetData set = (SetData)dlsym(RTLD_DEFAULT, "CTCellularDataPlanSetIsEnabled");
        if (!get || !set) return DXSystemOpenUnavailable;
        Boolean next = !get();
        set(next);
        // The setter has no acknowledgment; radio changes are asynchronous.
        return DXSystemOpenSucceeded;
    }
    if ([action isEqual:@"orientation-lock"]) {
        id manager = DXSystemShared(@"SBOrientationLockManager", @"sharedInstance");
        id locked = nil;
        if (!DXSystemInvoke(manager, @"isUserLocked", @[], &locked) || ![locked isKindOfClass:NSNumber.class]) return DXSystemOpenUnavailable;
        return DXSystemCall(manager, [locked boolValue] ? @"unlock" : @"lock", @[]);
    }
    if ([action isEqual:@"dark-mode"]) return DXSystemCall(DXSystemShared(@"UIUserInterfaceStyleArbiter", @"sharedInstance"), @"toggleCurrentStyle", @[]);
    if ([action isEqual:@"brightness-up"] || [action isEqual:@"brightness-down"]) {
        UIScreen *screen = UIScreen.mainScreen;
        screen.brightness = MIN(1, MAX(0, screen.brightness + ([action isEqual:@"brightness-up"] ? 0.1 : -0.1)));
        return DXSystemOpenSucceeded;
    }
    if ([action isEqual:@"volume-up"] || [action isEqual:@"volume-down"]) {
        id media = DXSystemShared(@"SBMediaController", @"sharedInstance");
        Ivar ivar = media ? class_getInstanceVariable([media class], "_volumeControl") : NULL;
        const char *type = ivar ? ivar_getTypeEncoding(ivar) : NULL;
        id volume = type && type[0] == '@' ? object_getIvar(media, ivar) : nil;
        return DXSystemCall(volume, [action isEqual:@"volume-up"] ? @"increaseVolume" : @"decreaseVolume", @[]);
    }
    if ([action isEqual:@"flashlight"]) {
        static id flashlight;
        if (!flashlight) flashlight = [NSClassFromString(@"AVFlashlight") new];
        id level = nil;
        if (!DXSystemInvoke(flashlight, @"flashlightLevel", @[], &level) || ![level isKindOfClass:NSNumber.class]) return DXSystemOpenUnavailable;
        return DXSystemCall(flashlight, @"setFlashlightLevel:withError:", @[@([level floatValue] > 0 ? 0.0f : 1.0f), NSNull.null]);
    }
    if ([action isEqual:@"do-not-disturb"]) {
        id service = nil, state = nil, manager = nil, activeIdentifier = nil;
        if (!DXSystemInvoke(NSClassFromString(@"DNDStateService"), @"serviceForClientIdentifier:", @[@"com.lindo.typex.systemactions"], &service) ||
            !DXSystemInvoke(service, @"queryCurrentStateWithError:", @[NSNull.null], &state) || !state ||
            !DXSystemInvoke(NSClassFromString(@"DNDToggleManager"), @"managerForClientIdentifier:", @[@"com.lindo.typex.systemactions"], &manager) || !manager ||
            !DXSystemInvoke(state, @"activeModeIdentifier", @[], &activeIdentifier)) return DXSystemOpenUnavailable;
        BOOL active = [activeIdentifier isEqual:@"com.apple.donotdisturb.mode.default"];
        return DXSystemCall(manager, active ? @"_toggleDNDOffReturningError:" : @"_toggleDNDOnReturningError:", @[NSNull.null]);
    }
    if (!DXSystemExitActionAvailable(action)) return DXSystemOpenUnavailable;
    if ([action isEqual:@"respring-sb"]) { exit(0); }
    if ([action isEqual:@"safe-mode"]) { return kill(getpid(), SIGSEGV) == 0 ? DXSystemOpenSucceeded : DXSystemOpenFailed; }
    if ([action isEqual:@"userspace-reboot"]) {
        typedef int (*UserReboot)(uint64_t, ...);
        UserReboot reboot = (UserReboot)dlsym(RTLD_DEFAULT, "reboot3");
        return reboot && reboot(0x2000000000000000ULL) == 0 ? DXSystemOpenSucceeded : DXSystemOpenFailed;
    }
    id service = DXSystemShared(@"FBSSystemService", @"sharedService");
    if ([action isEqual:@"respring"]) {
        id relaunch = nil;
        if (!DXSystemInvoke(NSClassFromString(@"SBSRelaunchAction"), @"actionWithReason:options:targetURL:",
            @[@"RestartRenderServer", @4, NSNull.null], &relaunch) || !relaunch) return DXSystemOpenUnavailable;
        return DXSystemCall(service, @"sendActions:withResult:", @[[NSSet setWithObject:relaunch], NSNull.null]);
    }
    return DXSystemCall(service, [action isEqual:@"shutdown"] ? @"shutdown" : @"reboot", @[]);
}
