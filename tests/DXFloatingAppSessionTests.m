#import <Foundation/Foundation.h>
#import "../DXFloatingAppSession.h"

#define REQUIRE(condition) do { if (!(condition)) { NSLog(@"FAIL %s:%d: %s", __FILE__, __LINE__, #condition); return 1; } } while (0)

int main(void) {
    @autoreleasepool {
        REQUIRE(DXActionUsesFloatingApp(@{}));
        REQUIRE(DXActionUsesFloatingApp(@{@"pullover": @NO}));
        REQUIRE(DXActionUsesFloatingApp(@{@"pullover": @YES}));
        REQUIRE(!DXActionUsesFloatingApp(@{@"floating": @NO, @"pullover": @YES}));
        REQUIRE(DXActionUsesFloatingApp(@{@"floating": @YES}));
        DXFloatingAppSession *session = [DXFloatingAppSession new];
        __block NSUInteger firstReplies = 0, secondReplies = 0;
        __block DXSystemOpenResult firstResult = 0, secondResult = 0;
        NSUInteger first = [session beginBundleIdentifier:@"com.apple.mobilenotes" deadline:[NSDate dateWithTimeIntervalSinceNow:8]
            reply:^(DXSystemOpenResult result) { firstReplies++; firstResult = result; }];
        REQUIRE([session isCurrent:first]);
        REQUIRE(session.state == DXFloatingAppPreparing);
        NSUInteger second = [session beginBundleIdentifier:@"com.apple.Preferences" deadline:[NSDate dateWithTimeIntervalSinceNow:8]
            reply:^(DXSystemOpenResult result) { secondReplies++; secondResult = result; }];
        REQUIRE(firstReplies == 1 && firstResult == DXSystemOpenBusy);
        REQUIRE(![session isCurrent:first] && [session isCurrent:second]);
        [session publishLive:first];
        REQUIRE(secondReplies == 0 && session.state == DXFloatingAppPreparing);
        [session publishLive:second];
        [session publishLive:second];
        REQUIRE(secondReplies == 1 && secondResult == DXSystemOpenSucceeded);
        REQUIRE(session.state == DXFloatingAppLive);
        [session finish:DXSystemOpenFailed];
        [session finish:DXSystemOpenFailed];
        REQUIRE(secondReplies == 1 && session.state == DXFloatingAppIdle && !session.bundleIdentifier);
        REQUIRE(![session isCurrent:second]);

        __block NSUInteger expiredReplies = 0;
        NSUInteger expired = [session beginBundleIdentifier:@"com.apple.mobilenotes" deadline:[NSDate dateWithTimeIntervalSinceNow:-1]
            reply:^(DXSystemOpenResult result) { expiredReplies++; firstResult = result; }];
        REQUIRE(session.hasExpired);
        [session publishLive:expired];
        REQUIRE(expiredReplies == 0 && session.state == DXFloatingAppPreparing);
        [session finish:DXSystemOpenTimedOut];
        REQUIRE(expiredReplies == 1 && firstResult == DXSystemOpenTimedOut);
        [session publishLive:expired];
        REQUIRE(session.state == DXFloatingAppIdle && expiredReplies == 1);

        NSUInteger cancelled = [session beginBundleIdentifier:@"com.apple.mobilenotes" deadline:[NSDate dateWithTimeIntervalSinceNow:8]
            reply:^(DXSystemOpenResult result) { firstReplies++; firstResult = result; }];
        [session finish:DXSystemOpenFailed];
        [session publishLive:cancelled];
        REQUIRE(firstReplies == 2 && firstResult == DXSystemOpenFailed && session.state == DXFloatingAppIdle);
        puts("PASS: floating defaults, legacy migration, replacement, stale publication, expiry, close and exactly-once replies");
    }
    return 0;
}
