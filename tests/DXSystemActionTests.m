#import <Foundation/Foundation.h>
#import "../DXSystemActionCatalog.h"
#import "../DXSystemActionCompatibility.h"
#import "../DXKeyboardPanelPreferences.h"
#import "../DXKeyboardPanelHostPolicy.h"
#import <notify.h>

static NSUInteger pixPinPosts;
static NSString *pixPinPostedName;
static uint32_t pixPinPostStatus;
static uint32_t DXPixPinTestPost(const char *name) {
    pixPinPosts++;
    pixPinPostedName = [NSString stringWithUTF8String:name];
    return pixPinPostStatus;
}
#define notify_post DXPixPinTestPost
#import "../DXPixPinIntegration.h"
#undef notify_post

@interface DXInvocationSpy : NSObject
@property(nonatomic) NSUInteger calls;
- (double)mixed:(BOOL)enabled count:(NSInteger)count level:(float)level;
- (id)object:(id)object error:(NSError **)error;
- (NSRange)range;
- (void)pointer:(void *)pointer;
- (void)raise;
- (BOOL)failureWithError:(NSError **)error;
- (BOOL)primary;
- (void)secondary;
@end
@implementation DXInvocationSpy
- (double)mixed:(BOOL)enabled count:(NSInteger)count level:(float)level { self.calls++; return (enabled ? 100 : 0) + count + level; }
- (id)object:(id)object error:(NSError **)error { self.calls++; NSCAssert(!error, @"out pointer must be nil"); return object; }
- (NSRange)range { self.calls++; return NSMakeRange(0, 1); }
- (void)pointer:(void *)pointer { self.calls++; }
- (void)raise { self.calls++; [NSException raise:@"TestFailure" format:@"test"]; }
- (BOOL)failureWithError:(NSError **)error { self.calls++; if (error) *error = [NSError errorWithDomain:@"TestDenied" code:17 userInfo:nil]; return NO; }
- (BOOL)primary { self.calls++; return NO; }
- (void)secondary { self.calls++; }

@end
// Stand-ins deliberately reject the old TypeX client identifier. These test
// production routing and native error propagation, not private iOS availability.
static NSString *const allowedDNDClient = @"com.apple.donotdisturb.control-center.module";
static id dndState;
static BOOL dndQueryDenied, dndToggleDenied;
static NSUInteger dndOnCalls, dndOffCalls;
@interface DXDNDStateSpy : NSObject
@property(nonatomic, copy) NSString *activeModeIdentifier;
@end
@implementation DXDNDStateSpy
@end
@interface DXDNDLegacyStateSpy : NSObject
@property(nonatomic) BOOL isActive;
@end
@implementation DXDNDLegacyStateSpy
@end
@interface DXDNDServiceSpy : NSObject
+ (id)serviceForClientIdentifier:(NSString *)client;
- (id)queryCurrentStateWithError:(NSError **)error;
@end
@implementation DXDNDServiceSpy
+ (id)serviceForClientIdentifier:(NSString *)client { return [client isEqual:allowedDNDClient] ? [self new] : nil; }
- (id)queryCurrentStateWithError:(NSError **)error {
    NSCAssert(error, @"native errors must be captured");
    if (dndQueryDenied) { *error = [NSError errorWithDomain:@"DNDDenied" code:1 userInfo:nil]; return nil; }
    return dndState;
}
@end
@interface DXDNDManagerSpy : NSObject
+ (id)managerForClientIdentifier:(NSString *)client;
- (BOOL)_toggleDNDOnReturningError:(NSError **)error;
- (BOOL)_toggleDNDOffReturningError:(NSError **)error;
@end
@implementation DXDNDManagerSpy
+ (id)managerForClientIdentifier:(NSString *)client { return [client isEqual:allowedDNDClient] ? [self new] : nil; }
- (BOOL)_toggleDNDOnReturningError:(NSError **)error {
    dndOnCalls++; if (dndToggleDenied) { *error = [NSError errorWithDomain:@"DNDDenied" code:2 userInfo:nil]; return NO; } return YES;
}
- (BOOL)_toggleDNDOffReturningError:(NSError **)error { dndOffCalls++; return YES; }
@end
static NSUInteger checks;
static void check(BOOL value) { NSCAssert(value, @"check %lu failed", (unsigned long)checks + 1); checks++; }
int main(void) {
    @autoreleasepool {
        NSArray *catalog = DXSystemActionCatalog();
        check(catalog.count == 34);
        NSMutableSet *ids = [NSMutableSet set];
        NSUInteger destructive = 0;
        for (NSDictionary *action in catalog) {
            check(![ids containsObject:action[@"id"]] && DXSystemActionDefinition(action[@"id"]) == action);
            [ids addObject:action[@"id"]];
            destructive += [action[@"destructive"] boolValue];
        }
        check(destructive == 6);
        NSDictionary *pixPinModes = @{
            @"pixpin-full": @"full", @"pixpin-area": @"area", @"pixpin-freeze": @"freeze",
            @"pixpin-instant": @"instant", @"pixpin-markup": @"markup", @"pixpin-long": @"long",
            @"pixpin-cancel": @"cancel"
        };
        check([DXPixPinDylibPath isEqual:@"/Library/MobileSubstrate/DynamicLibraries/PixPin.dylib"]);
        check(DXVisibleSystemActionCatalog(NO).count == 27 && DXVisibleSystemActionCatalog(YES).count == 34);
        for (NSDictionary *action in DXVisibleSystemActionCatalog(NO)) check(!action[@"pixpinNotification"]);
        check(DXSystemActionIsPixPinCapture(@"pixpin-full") && DXSystemActionIsPixPinCapture(@"pixpin-long"));
        check(!DXSystemActionIsPixPinCapture(@"pixpin-cancel") && !DXSystemActionIsPixPinCapture(@"wifi") && !DXSystemActionIsPixPinCapture(nil));
        NSString *fixtureDirectory = [NSTemporaryDirectory() stringByAppendingPathComponent:NSUUID.UUID.UUIDString];
        NSString *fixtureDylib = [fixtureDirectory stringByAppendingPathComponent:@"PixPin.dylib"];
        check([NSFileManager.defaultManager createDirectoryAtPath:fixtureDirectory withIntermediateDirectories:YES attributes:nil error:nil]);
        check(!DXPixPinInstalledAtPath(nil) && !DXPixPinInstalledAtPath(fixtureDylib) && !DXPixPinInstalledAtPath(fixtureDirectory));
        for (NSString *identifier in pixPinModes) {
            NSDictionary *definition = DXSystemActionDefinition(identifier);
            NSString *expectedName = [@"com.pixpin.screenshot/capture/" stringByAppendingString:pixPinModes[identifier]];
            check([definition[@"pixpinNotification"] isEqual:expectedName] && [definition[@"group"] isEqual:@"pixpin"] && ![definition[@"destructive"] boolValue]);
            check(DXPostPixPinSystemAction(identifier, fixtureDylib) == DXSystemOpenUnavailable && pixPinPosts == 0);
        }
        check([NSFileManager.defaultManager createFileAtPath:fixtureDylib contents:NSData.data attributes:nil]);
        check(DXPixPinInstalledAtPath(fixtureDylib));
        pixPinPostStatus = NOTIFY_STATUS_OK;
        for (NSString *identifier in pixPinModes) {
            NSUInteger beforePosts = pixPinPosts;
            NSString *expectedName = [@"com.pixpin.screenshot/capture/" stringByAppendingString:pixPinModes[identifier]];
            check(DXPostPixPinSystemAction(identifier, fixtureDylib) == DXSystemOpenSucceeded && pixPinPosts == beforePosts + 1 && [pixPinPostedName isEqual:expectedName]);
            check(DXSystemActionIsConfigured(@[@{@"selector": @"__custom_pixpin", @"type": @"system", @"systemaction": identifier}], identifier, @"__custom_"));
        }
        NSUInteger beforePosts = pixPinPosts;
        check(DXPostPixPinSystemAction(@"wifi", fixtureDylib) == DXSystemOpenInvalid && pixPinPosts == beforePosts);
        check(DXPostPixPinSystemAction(@"pixpin-full;anything", fixtureDylib) == DXSystemOpenInvalid && pixPinPosts == beforePosts);
        pixPinPostStatus = NOTIFY_STATUS_FAILED;
        check(DXPostPixPinSystemAction(@"pixpin-full", fixtureDylib) == DXSystemOpenFailed && pixPinPosts == beforePosts + 1);
        check([NSFileManager.defaultManager removeItemAtPath:fixtureDylib error:nil]);
        beforePosts = pixPinPosts;
        check(DXPostPixPinSystemAction(@"pixpin-cancel", fixtureDylib) == DXSystemOpenUnavailable && pixPinPosts == beforePosts);
        // Removing the optional tweak must not erase saved action definitions.
        check(DXSystemActionDefinition(@"pixpin-cancel") != nil && DXVisibleSystemActionCatalog(DXPixPinInstalledAtPath(fixtureDylib)).count == 27);
        check([NSFileManager.defaultManager removeItemAtPath:fixtureDirectory error:nil]);
        check(!DXSystemActionDefinition(@"reboot;anything") && !DXSystemActionDefinition(@42));
        NSString *prefix = @"__custom_";
        NSDictionary *saved = @{@"selector": @"__custom_1", @"type": @"system", @"systemaction": @"wifi"};
        check(DXSystemActionIsConfigured(@[saved], @"wifi", prefix));
        check(!DXSystemActionIsConfigured(@[saved], @"reboot", prefix));
        check(!DXSystemActionIsConfigured(@[@{@"type": @"system", @"systemaction": @"reboot"}], @"reboot", prefix));
        check(!DXSystemActionIsConfigured(@[@{@"selector": @"__custom_1", @"type": @"url", @"systemaction": @"wifi"}], @"wifi", prefix));
        check(!DXSystemActionIsConfigured(@[@42, NSNull.null], @"wifi", prefix));
        check(!DXSystemActionIsConfigured(@{}, @"wifi", prefix));
        check(DXSystemActionIsRecording(@"screen-recording") && DXSystemActionIsRecording(@"screen-recording-microphone") && !DXSystemActionIsRecording(@"wifi"));
        for (NSString *action in @[@"screenshot", @"screen-recording", @"screen-recording-microphone"]) {
            NSDictionary *definition = @{@"selector": @"__custom_recording", @"type": @"system", @"systemaction": action};
            check(DXSystemActionIsConfigured(@[definition], action, prefix) && ![DXSystemActionDefinition(action)[@"destructive"] boolValue]);
        }
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
        NSError *error = nil;
        check(DXSystemInvokeReportingError(spy, @"failureWithError:", @[NSNull.null], &result, &error) && ![result boolValue] && error.code == 17);
        check(DXSystemCall(spy, @"failureWithError:", @[NSNull.null]) == DXSystemOpenFailed);
        before = spy.calls;
        check(DXSystemCallFirstAvailable(spy, @[@[@"primary", @[]], @[@"secondary", @[]]]) == DXSystemOpenFailed && spy.calls == before + 1);
        check(DXSystemCallFirstAvailable(spy, @[@[@"absent", @[]], @[@"secondary", @[]]]) == DXSystemOpenSucceeded && spy.calls == before + 2);
        check(DXSystemCallFirstAvailable(nil, @[@[@"secondary", @[]]]) == DXSystemOpenUnavailable);
        DXDNDStateSpy *modern = [DXDNDStateSpy new];
        dndState = modern;
        check(DXSystemToggleDND(DXDNDServiceSpy.class, DXDNDManagerSpy.class) == DXSystemOpenSucceeded && dndOnCalls == 1 && dndOffCalls == 0);
        modern.activeModeIdentifier = @"com.apple.donotdisturb.mode.default";
        check(DXSystemToggleDND(DXDNDServiceSpy.class, DXDNDManagerSpy.class) == DXSystemOpenSucceeded && dndOnCalls == 1 && dndOffCalls == 1);
        modern.activeModeIdentifier = @"com.apple.focus.work";
        check(DXSystemToggleDND(DXDNDServiceSpy.class, DXDNDManagerSpy.class) == DXSystemOpenSucceeded && dndOnCalls == 2 && dndOffCalls == 1);
        DXDNDLegacyStateSpy *legacy = [DXDNDLegacyStateSpy new]; legacy.isActive = YES; dndState = legacy;
        check(DXSystemToggleDND(DXDNDServiceSpy.class, DXDNDManagerSpy.class) == DXSystemOpenSucceeded && dndOffCalls == 2);
        dndQueryDenied = YES;
        check(DXSystemToggleDND(DXDNDServiceSpy.class, DXDNDManagerSpy.class) == DXSystemOpenFailed && dndOnCalls == 2 && dndOffCalls == 2);
        dndQueryDenied = NO; dndToggleDenied = YES; legacy.isActive = NO;
        check(DXSystemToggleDND(DXDNDServiceSpy.class, DXDNDManagerSpy.class) == DXSystemOpenFailed && dndOnCalls == 3 && dndOffCalls == 2);
        check(DXSystemToggleDND(Nil, DXDNDManagerSpy.class) == DXSystemOpenUnavailable && dndOnCalls == 3);
        check(DXSystemToggleDND(DXDNDServiceSpy.class, Nil) == DXSystemOpenUnavailable && dndOnCalls == 3);
        check(DXKeyboardPanelHostRank(@"UIRemoteKeyboardWindow", NO) > DXKeyboardPanelHostRank(@"UITextEffectsWindow", NO));
        check(DXKeyboardPanelHostRank(@"UIWindow", NO) == 0);
        check(DXKeyboardPanelHostRank(@"UIWindow", YES) > DXKeyboardPanelHostRank(@"UITextEffectsWindow", NO));
        NSLog(@"PASS: %lu system/panel checks (PixPin installation/filtering/one-shot dispatch, ABI rejection, native errors, DND route, configured custom actions, host rank)", (unsigned long)checks);
    }
    return 0;
}
