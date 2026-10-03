#import "../DXStatusBarGesturePolicy.h"
#import "../DXGlobalPanelPolicy.h"

static NSUInteger checks;
static void check(BOOL condition) { checks++; NSCAssert(condition, @"Status-bar check %lu", (unsigned long)checks); }
int main(void) {
    @autoreleasepool {
        check(!DXStatusBarSlot(nil, @"tap"));
        check(!DXStatusBarSlot(@"left", @"up"));
        check(!DXStatusBarFlag(@"YES"));
        check(!DXStatusBarSelector(@{kDXStatusBarBindings: @[]}, @"left.tap"));
        check(!DXStatusBarSelector(@{kDXStatusBarBindings: @{@"left.tap": @{@"enabled": @YES}}}, @"left.tap"));
        check([DXStatusBarRegion(0, 0, 390, 54) isEqual:@"left"]);
        check([DXStatusBarRegion(129, 53, 390, 54) isEqual:@"left"]);
        check([DXStatusBarRegion(130, 0, 390, 54) isEqual:@"middle"]);
        check([DXStatusBarRegion(260, 0, 390, 54) isEqual:@"right"]);
        check(!DXStatusBarRegion(390, 0, 390, 54));
        check(!DXStatusBarRegion(2, 54, 390, 54));
        check(!DXStatusBarRegion(-1, 1, 390, 54));
        check(!DXStatusBarRegion(1, 1, NAN, 54));
        check(!DXStatusBarRegion(1, INFINITY, 390, 54));
        check(!DXStatusBarRegion(1, 1, 390, 0));
        check([DXStatusBarPanelSide(@"__typex_statusbar_panel_common") isEqual:@"common"]);
        check(!DXStatusBarPanelSide(@"__typex_statusbar_panel_middle"));
        NSMutableDictionary *bindings = [NSMutableDictionary dictionary];
        NSMutableSet *slots = [NSMutableSet set];
        for (NSString *region in DXStatusBarRegions()) for (NSString *gesture in DXStatusBarGestures()) {
            NSString *slot = DXStatusBarSlot(region, gesture);
            [slots addObject:slot]; bindings[slot] = @{@"enabled": @YES, @"selector": slot};
        }
        check(slots.count == 15);
        NSMutableDictionary *preferences = [@{kDXStatusBarBindings: bindings, @"unrelated": @42} mutableCopy];
        for (NSString *slot in slots) check([DXStatusBarSelector(preferences, slot) isEqual:slot]);
        DXStatusBarRemoveActionReferences(preferences, @"left.doubletap");
        check(!DXStatusBarSelector(preferences, @"left.doubletap"));
        check(!DXStatusBarFlag(DXStatusBarBinding(preferences, @"left.doubletap")[@"enabled"]));
        for (NSString *slot in slots) if (![slot isEqual:@"left.doubletap"]) check([DXStatusBarSelector(preferences, slot) isEqual:slot]);
        check([preferences[@"unrelated"] isEqual:@42]);
        check(DXGlobalCustomActionSupported(@{@"type": @"system", @"systemaction": @"play-pause"}));
        check(!DXGlobalCustomActionSupported(@{@"type": @"system", @"systemaction": @"unknown"}));
        check(DXGlobalCustomActionSupported(@{@"type": @"openapp", @"link": @"com.apple.mobilesafari"}));
        check(DXGlobalCustomActionSupported(@{@"type": @"shortcut", @"link": @"com.apple.camera", @"shortcuttype": @"selfie"}));
        check(!DXGlobalCustomActionSupported(@{@"type": @"shortcut", @"link": @"com.apple.camera"}));
        check(!DXGlobalCustomActionSupported(@{@"type": @"text", @"textrecords": @[@"text"]}));
        check(!DXGlobalCustomActionSupported(@{@"type": @"javascript", @"link": @"app://"}));
        check(!DXGlobalCustomActionSupported(@{@"type": @"urlscheme", @"link": @"app://search?q=@@@"}));
        check(!DXGlobalCustomActionSupported(@[]));
        check(DXStatusBarHostAllowed(@"SpringBoard", nil));
        check(DXStatusBarHostAllowed(@"Safari", @"app"));
        check(DXStatusBarHostAllowed(@"Safari", @"APP"));
        check(!DXStatusBarHostAllowed(@"extension", @"appex"));
        check(!DXStatusBarHostAllowed(@"daemon", nil));
        for (NSString *slot in slots) {
            NSDictionary *request = @{@"slot": slot, @"selector": @"__typex_statusbar_panel_common", @"landscape": @NO};
            NSMutableDictionary *live = [@{kDXStatusBarEnabled: @YES,
                kDXStatusBarBindings: @{slot: @{@"enabled": @YES, @"selector": request[@"selector"]}}} mutableCopy];
            check(DXStatusBarRequestValid(request));
            check([DXStatusBarRequestSelector(live, request, @"master") isEqual:request[@"selector"]]);
            live[@"master"] = @NO; check(!DXStatusBarRequestSelector(live, request, @"master"));
            live[@"master"] = @YES; live[kDXStatusBarEnabled] = @NO; check(!DXStatusBarRequestSelector(live, request, @"master"));
            live[kDXStatusBarEnabled] = @YES;
            NSMutableDictionary *changed = [request mutableCopy]; changed[@"selector"] = @"different";
            check(!DXStatusBarRequestSelector(live, changed, @"master"));
            changed[@"selector"] = request[@"selector"]; changed[@"landscape"] = @YES;
            check(!DXStatusBarRequestSelector(live, changed, @"master"));
            live[kDXStatusBarLandscape] = @YES; check(DXStatusBarRequestSelector(live, changed, @"master") != nil);
        }
        for (id malformed in @[@[], @{}, @{@"slot": @"left.tap.extra", @"selector": @"action", @"landscape": @NO},
            @{@"slot": @"left.tap", @"selector": @"", @"landscape": @NO},
            @{@"slot": @"left.tap", @"selector": @"action", @"landscape": @"NO"},
            @{@"slot": @"left.tap", @"selector": @"action", @"landscape": @2},
            @{@"slot": @"left.tap", @"selector": @"action", @"landscape": @NO, @"definition": @{}}])
            check(!DXStatusBarRequestValid(malformed));
        printf("PASS: %lu status-bar configuration, region and action checks\n", (unsigned long)checks);
    }
    return 0;
}
