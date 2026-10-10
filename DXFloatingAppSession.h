#import "DXDarwinOpenChannel.h"

typedef NS_ENUM(NSUInteger, DXFloatingAppState) {
    DXFloatingAppIdle, DXFloatingAppPreparing, DXFloatingAppLive
};

// Confined to the main queue by the host. Kept independent of UIKit so the
// cancellation/deadline races can be exercised without a jailbroken device.
@interface DXFloatingAppSession : NSObject
@property(nonatomic, readonly) NSUInteger generation;
@property(nonatomic, readonly) DXFloatingAppState state;
@property(nonatomic, copy, readonly) NSString *bundleIdentifier;
@property(nonatomic, copy, readonly) NSDate *deadline;
- (NSUInteger)beginBundleIdentifier:(NSString *)bundleIdentifier deadline:(NSDate *)deadline reply:(DXSystemOpenReply)reply;
- (BOOL)isCurrent:(NSUInteger)generation;
- (BOOL)hasExpired;
- (void)publishLive:(NSUInteger)generation;
- (void)finish:(DXSystemOpenResult)result;
@end

static inline BOOL DXActionUsesFloatingApp(NSDictionary *entry) {
    id choice = entry[@"floating"];
    // Both supported action types now use TypeX hosting by default, including
    // old entries whose 'pullover' flag was merely an installation-dependent
    // integration setting. An explicit new choice still permits normal open.
    return ![choice isKindOfClass:NSNumber.class] || [choice boolValue];
}
