#import <Foundation/Foundation.h>
#import "../DXFloatingAppSession.h"
#include <signal.h>
#include <errno.h>

static pid_t currentPID;
static NSString *frontmost;
static NSUInteger signals;
static int signalResult;
static BOOL released;
static BOOL reopened;
static BOOL replacedPID;
static pid_t signalledPID;
static int signalledSignal;
static pid_t DXFloatPID(__unused NSString *identifier) { return currentPID; }
static NSString *DXFloatFrontmostIdentifier(void) { return frontmost; }
static BOOL DXIsValidBundleIdentifier(NSString *identifier) { return identifier.length > 0; }
static int fakeKill(pid_t pid, int signal) {
    NSCAssert(released, @"lease must be released before terminating");
    signals++; signalledPID = pid; signalledSignal = signal;
    errno = EPERM;
    return signalResult;
}
#define kill fakeKill
@interface DXFloatingAppCoordinator : NSObject
@property(nonatomic, strong) DXFloatingAppSession *session;
- (void)close;
- (void)cleanup:(DXSystemOpenResult)result reason:(NSString *)reason;
@end
@implementation DXFloatingAppCoordinator
- (void)cleanup:(DXSystemOpenResult)result reason:(__unused NSString *)reason {
    [self.session finish:result]; released = YES;
    if (replacedPID) currentPID++;
    if (reopened) [self.session beginBundleIdentifier:@"com.apple.Preferences"
        deadline:[NSDate dateWithTimeIntervalSinceNow:8] reply:nil];
}
#include "FloatingClose.inc"
@end
#undef kill
#define REQUIRE(c) do { if (!(c)) { NSLog(@"FAIL line %d: %s", __LINE__, #c); return 1; } checks++; } while (0)
int main(void) {
    @autoreleasepool {
        NSUInteger checks = 0;
        DXFloatingAppCoordinator *host = [DXFloatingAppCoordinator new];
        host.session = [DXFloatingAppSession new];
        for (NSUInteger scenario = 0; scenario < 7; scenario++) {
            currentPID = scenario == 1 ? 0 : 314;
            frontmost = scenario == 3 ? @"com.apple.Preferences" : @"com.example.base";
            reopened = scenario == 4;
            replacedPID = scenario == 2;
            signalResult = scenario == 5 ? -1 : 0;
            released = NO; signals = 0;
            [host.session beginBundleIdentifier:scenario == 6 ? @"com.apple.springboard" : @"com.apple.Preferences"
                deadline:[NSDate dateWithTimeIntervalSinceNow:8] reply:nil];
            [host close];
            REQUIRE(released);
            REQUIRE(signals == ((scenario == 0 || scenario == 5) ? 1U : 0U));
            REQUIRE(reopened || host.session.state == DXFloatingAppIdle);
            if (signals) REQUIRE(signalledPID == 314 && signalledSignal == SIGKILL);
        }
        [host.session finish:DXSystemOpenFailed];
        signals = 0;
        [host close]; [host close];
        REQUIRE(signals == 0);
        printf("PASS: %lu actual close method assertions (release ordering, absent/replaced PID, takeover, reopen, denial, duplicate close)\n", (unsigned long)checks);
    }
    return 0;
}
