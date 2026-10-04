#import "../DXDockGesturePolicy.h"
#import "DXPanelTestFixtures.h"

static NSUInteger checks;
static void check(BOOL condition, NSString *name) { checks++; NSCAssert(condition, @"%@", name); }
int main(void) {
    @autoreleasepool {
        check([DXDockGestureEnabledKey(@"up") isEqual:kDXPanelDockSwipeEnabled], @"legacy up switch");
        check(!DXDockGestureEnabledKey(@"down"), @"unsupported direction");
        check(DXDockGestureEnabled(@{}, @"up"), @"legacy up default");
        check(!DXDockGestureEnabled(@{}, @"left") && !DXDockGestureEnabled(@{}, @"right"), @"new directions default off");
        check(!DXDockGestureEnabled(nil, @"up"), @"missing snapshot fails closed");
        check(!DXDockGestureSelector(@{kDXPanelDockSwipeEnabled: @NO}, @"up"), @"legacy disabled stays off");
        check(!DXDockGestureSelector(@{kDXPanelDockSwipeEnabled: @"YES"}, @"up"), @"invalid switch fails closed");
        check(!DXDockGestureSelector(@{}, @"up"), @"unassigned direction has no panel default");
        check(!DXDockGestureConfiguredSelector(@{kDXDockGestureBindings: @[]}, @"up"), @"malformed bindings do not restore common");
        check(!DXDockGestureConfiguredSelector(@{kDXDockGestureBindings: @{@"up": @42}}, @"up"), @"malformed selector");
        check(!DXDockGestureConfiguredSelector(@{kDXDockGestureBindings: @{@"up": @""}}, @"up"), @"explicit clear stays empty");
        check(!DXDockGestureConfiguredSelector(@{}, @"down"), @"down cannot use fallback");
        NSDictionary *action = @{@"selector": @"__typex_link_action_app", @"type": @"openapp", @"link": @"com.apple.mobilenotes"};
        NSMutableDictionary *preferences = [@{kDXPanels: DXTestGesturePanels(), kDXDockLeftSwipeEnabled: @YES, kDXDockRightSwipeEnabled: @YES,
            kDXDockGestureBindings: @{@"left": action[@"selector"], @"right": @"__typex_panel_test-right"},
            @"linkactions": @[NSNull.null, action], @"unrelated": @42} mutableCopy];
        check([DXDockGestureSelector(preferences, @"left") isEqual:action[@"selector"]], @"left binding");
        check(DXPanelAllowed(preferences, DXDockGestureSelector(preferences, @"right"), DXPanelGestureKind), @"right binding");
        check(!DXDockGestureSelector(preferences, @"up"), @"left/right save never assigns up implicitly");
        check([DXDockGestureDefinition(preferences, action[@"selector"], @"linkactions") isEqual:action], @"resolve live definition");
        check(!DXDockGestureDefinition(@{@"linkactions": @{}}, action[@"selector"], @"linkactions"), @"invalid action storage");
        check(!DXDockGestureDefinition(preferences, @"deleted", @"linkactions"), @"deleted definition cannot execute");
        check(DXGlobalCustomActionSupported(DXDockGestureDefinition(preferences, action[@"selector"], @"linkactions")), @"SpringBoard app supported");
        preferences[kDXPanelGlobalEnabled] = @NO;
        check([DXDockGestureSelector(preferences, @"left") isEqual:action[@"selector"]], @"custom binding independent of panel switch");
        NSDictionary *before = [preferences copy];
        DXDockGestureRemoveActionReferences(preferences, action[@"selector"]);
        check(!DXDockGestureEnabled(preferences, @"left") && !DXDockGestureConfiguredSelector(preferences, @"left"), @"delete clears and disables left");
        check([DXDockGestureSelector(preferences, @"right") isEqual:DXDockGestureSelector(before, @"right")], @"deleting left preserves right");
        check([preferences[@"unrelated"] isEqual:@42], @"unrelated preferences preserved");
        preferences[kDXDockGestureBindings] = @{@"up": action[@"selector"], @"left": action[@"selector"], @"right": @"other"};
        preferences[kDXPanelDockSwipeEnabled] = @YES;
        DXDockGestureRemoveActionReferences(preferences, action[@"selector"]);
        check(!DXDockGestureEnabled(preferences, @"up") && !DXDockGestureConfiguredSelector(preferences, @"up"), @"deleted up does not restore legacy panel");
        check([preferences[kDXDockGestureBindings][@"right"] isEqual:@"other"], @"unrelated binding preserved");
        for (NSString *direction in DXDockGestureDirections()) {
            double dx = [direction isEqual:@"left"] ? -48 : ([direction isEqual:@"right"] ? 48 : 0);
            double dy = [direction isEqual:@"up"] ? -48 : 0;
            check([DXDockGestureDirection(dx, dy) isEqual:direction], @"direction classified");
            check(DXDockGestureCompletes(direction, dx, dy), @"48pt threshold accepted");
            check(!DXDockGestureCompletes(direction, dx * 47.0 / 48.0, dy * 47.0 / 48.0), @"47pt rejected");
            check(!DXDockGestureCompletes(direction, -dx, -dy), @"reverse direction rejected");
            check(!DXDockGestureCompletes(direction, NAN, dy), @"NaN rejected");
            check(!DXDockGestureCompletes(direction, dx, INFINITY), @"infinity rejected");
        }
        check(DXDockGestureCompletes(@"left", -48, 32), @"horizontal dominance boundary");
        check(!DXDockGestureCompletes(@"left", -48, 33), @"diagonal horizontal rejection");
        check(DXDockGestureCompletes(@"up", 32, -48), @"vertical dominance boundary");
        check(!DXDockGestureCompletes(@"up", 33, -48), @"diagonal up rejection");
        check(!DXDockGestureDirection(0, 0) && !DXDockGestureDirection(0, 48), @"stationary/down rejected");
        check(!DXDockGestureDirection(48, 48), @"diagonal cannot select direction");
        check(!DXDockGestureCompletes(nil, -48, 0), @"no session direction");
        printf("PASS: %lu Dock configuration, compatibility, deletion and direction checks\n", (unsigned long)checks);
    }
    return 0;
}
