#import "../DXGlobalPanelPolicy.h"
#import "../DXGlobalPanelGeometry.h"
#import "../DXKeyboardPanelPreferences.h"

static NSUInteger checks;
static void check(BOOL condition) { NSCAssert(condition, @"Global panel check %lu", (unsigned long)checks + 1); checks++; }

int main(void) {
    @autoreleasepool {
        check(DXDockPanelOriginAllowed(150, 82, 300, 96, 34));
        check(DXDockPanelOriginAllowed(150, 66, 300, 96, 34));
        check(DXDockPanelOriginAllowed(150, 48, 300, 96, 34)); // Between icons, at icon height.
        check(DXDockPanelOriginAllowed(150, 0, 300, 96, 34));
        check(!DXDockPanelOriginAllowed(150, -1, 300, 96, 34));
        check(!DXDockPanelOriginAllowed(-1, 82, 300, 96, 34));
        check(!DXDockPanelOriginAllowed(301, 82, 300, 96, 34));
        check(DXDockPanelOriginAllowed(150, 110, 300, 96, 34)); // Below Dock, on window.
        check(DXDockPanelOriginAllowed(150, 130, 300, 96, 34));
        check(!DXDockPanelOriginAllowed(150, 131, 300, 96, 34));
        check(!DXDockPanelOriginAllowed(150, 97, 300, 96, 0));
        check(!DXDockPanelOriginAllowed(150, 82, 300, 96, -1));
        check(!DXDockPanelOriginAllowed(150, 82, 300, 96, NAN));
        check(!DXDockPanelOriginAllowed(0, 0, 0, 0, 0));
        check(!DXDockPanelOriginAllowed(NAN, 80, 300, 96, 34));
        check(DXDockPanelSwipeCompletes(0, -48));
        check(DXDockPanelSwipeCompletes(32, -48));
        check(!DXDockPanelSwipeCompletes(33, -48));
        check(!DXDockPanelSwipeCompletes(0, -47));
        check(!DXDockPanelSwipeCompletes(0, 80));
        check(!DXDockPanelSwipeCompletes(NAN, -100));
        check(DXGlobalPanelActionNeedsInput(@{@"type": @"text"}));
        check(DXGlobalPanelActionNeedsInput(@{@"type": @"javascript"}));
        check(DXGlobalPanelActionNeedsInput(@{@"type": @"url", @"link": @"https://example.com?q=@@@"}));
        check(DXGlobalPanelActionNeedsInput(@{@"link": @"example://@@@"}));
        check(!DXGlobalPanelActionNeedsInput(@{@"type": @"openapp", @"link": @"com.apple.mobilenotes"}));
        check(!DXGlobalPanelActionNeedsInput(@{@"type": @"system", @"systemaction": @"screenshot"}));
        check(!DXGlobalPanelActionNeedsInput(@{@"type": @"shortcut"}));
        check(!DXGlobalPanelActionNeedsInput(@{@"type": NSNull.null, @"link": @42}));
        check([DXGlobalPanelNormalizedPayload(@"  www.example.com\n") isEqual:@"https://www.example.com"]);
        check([DXGlobalPanelNormalizedPayload(@"com.apple.mobilenotes") isEqual:@"com.apple.mobilenotes"]);
        check([DXGlobalPanelNormalizedPayload(NSNull.null) isEqual:@""]);
        check([DXGlobalPanelString(@42) isEqual:@""]);
        // Fits content, bottom-anchored: available = 844-47-34-20 = 743.
        CGRect portrait = DXGlobalPanelFrame(CGRectMake(0, 0, 390, 844), 47, 34, 200, NO);
        check(CGRectEqualToRect(portrait, CGRectMake(10, 600, 370, 200)));
        // Status-bar origin anchors the same content below the top inset.
        CGRect anchored = DXGlobalPanelFrame(CGRectMake(0, 0, 390, 844), 47, 34, 200, YES);
        check(CGRectEqualToRect(anchored, CGRectMake(10, 57, 370, 200)));
        // Content beyond the on-screen space clamps and scrolls inside.
        CGRect clamped = DXGlobalPanelFrame(CGRectMake(0, 0, 390, 844), 47, 34, 900, NO);
        check(CGRectEqualToRect(clamped, CGRectMake(10, 57, 370, 743)));
        // Sparse content stretches to the 100pt floor.
        CGRect floor_ = DXGlobalPanelFrame(CGRectMake(0, 0, 390, 844), 47, 34, 54, YES);
        check(CGRectEqualToRect(floor_, CGRectMake(10, 57, 370, 100)));
        CGRect landscape = DXGlobalPanelFrame(CGRectMake(0, 0, 844, 390), 0, 21, 200, NO);
        check(CGRectEqualToRect(landscape, CGRectMake(172, 159, 500, 200)));
        check(CGRectIsNull(DXGlobalPanelFrame(CGRectZero, 0, 0, 200, NO)));
        check(CGRectIsNull(DXGlobalPanelFrame(CGRectMake(0, 0, 100, 100), 0, 0, 200, NO)));
        check(CGRectIsNull(DXGlobalPanelFrame(CGRectMake(0, 0, 390, 844), NAN, 34, 200, NO)));
        check(CGRectIsNull(DXGlobalPanelFrame(CGRectMake(0, 0, 390, 844), 47, 34, NAN, NO)));
        check(CGRectIsNull(DXGlobalPanelFrame(CGRectMake(0, 0, 390, 844), 47, 34, -1, NO)));
        // Less than the 100pt floor of on-screen space stays invalid.
        check(CGRectIsNull(DXGlobalPanelFrame(CGRectMake(0, 0, 390, 110), 0, 0, 54, NO)));
        check(DXKeyboardPanelBool(@{}, kDXPanelGlobalEnabled, YES));
        check(!DXKeyboardPanelBool(@{kDXPanelGlobalEnabled: @NO}, kDXPanelGlobalEnabled, YES));
        check(!DXKeyboardPanelBool(@{kDXPanelDockSwipeEnabled: @"yes"}, kDXPanelDockSwipeEnabled, YES));
        NSMutableDictionary *preferences = [@{kDXPanelColumns: @5, kDXPanelScale: @85,
            kDXPanelSystemTogglesVisible: @NO, kDXPanelSystemSlidersVisible: @YES, kDXPanelDark: @NO,
            kDXPanelLeftItems: @[@{@"selector": @"left-action"}], kDXPanelRightItems: @[@{@"selector": @"right-action"}],
            kDXPanelCommonItems: @[@{@"selector": @"common-action"}]} mutableCopy];
        // Each legacy value is retained until the corresponding profile overrides it.
        for (NSString *side in @[@"left", @"right", @"common"]) {
            NSDictionary *profile = DXKeyboardPanelProfilePreferences(preferences, side);
            check(DXKeyboardPanelNumber(profile, kDXPanelColumns, 4, 3, 5) == 5);
            check(!DXKeyboardPanelBool(profile, kDXPanelSystemTogglesVisible, YES));
            check([DXKeyboardPanelItems(profile, side).firstObject[@"selector"] isEqual:[side stringByAppendingString:@"-action"]]);
        }
        check([DXKeyboardPanelProfileKey(kDXPanelColumns, @"common") isEqual:@"keyboardpanelcommoncolumns"]);
        check(!DXKeyboardPanelProfileKey(kDXPanelColumns, @"unknown"));
        check(!DXKeyboardPanelProfileKey(@"enabled", @"left"));
        NSDictionary *original = [preferences copy];
        NSDictionary *overrides = @{kDXPanelColumns: @3, kDXPanelScale: @120,
            kDXPanelSystemTogglesVisible: @YES, kDXPanelSystemSlidersVisible: @NO, kDXPanelDark: @YES};
        for (NSString *key in overrides) preferences[DXKeyboardPanelProfileKey(key, @"left")] = overrides[key];
        for (NSString *side in @[@"left", @"right", @"common"]) {
            NSDictionary *profile = DXKeyboardPanelProfilePreferences(preferences, side);
            for (NSString *key in overrides) check([profile[key] isEqual:[side isEqual:@"left"] ? overrides[key] : original[key]]);
        }
        preferences[DXKeyboardPanelProfileKey(kDXPanelColumns, @"common")] = @4;
        preferences[DXKeyboardPanelProfileKey(kDXPanelSystemTogglesVisible, @"right")] = @"invalid";
        check(DXKeyboardPanelNumber(DXKeyboardPanelProfilePreferences(preferences, @"common"), kDXPanelColumns, 4, 3, 5) == 4);
        check(DXKeyboardPanelNumber(DXKeyboardPanelProfilePreferences(preferences, @"right"), kDXPanelColumns, 4, 3, 5) == 5);
        check(!DXKeyboardPanelBool(DXKeyboardPanelProfilePreferences(preferences, @"right"), kDXPanelSystemTogglesVisible, YES));
        check([original[kDXPanelScale] isEqual:@85]);
        check(!preferences[DXKeyboardPanelProfileKey(kDXPanelScale, @"common")]);
        printf("PASS: %lu global panel policy/geometry checks\n", (unsigned long)checks);
    }
    return 0;
}
