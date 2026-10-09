#import "GestureProduction.h"

static NSUInteger checks;
static void expect(NSDictionary *prefs, NSString *identifier, int gesture, NSString *scope, NSArray *expected) {
    NSArray *actual = DXGestureActionSelectors(prefs, identifier, gesture, scope);
    if (![actual isEqual:expected]) {
        NSLog(@"FAIL gesture=%d scope=%@ expected=%@ actual=%@", gesture, scope, expected, actual);
        exit(1);
    }
    checks++;
}

int main(void) {
    @autoreleasepool {
        // Exercise the production classification: long distance, confined-button and cancelled drags.
        struct { double x, y, width, button; int has, inside, expected; } swipes[] = {
            {-140, 5, 390, 60, 1, 0, -2}, {140, 5, 390, 60, 1, 0, 2},
            {116, 0, 390, 60, 1, 0, 0}, {117, 0, 390, 60, 1, 0, 2},
            {99, 0, 250, 32, 0, 0, 0}, {100, 0, 250, 32, 0, 0, 2},
            {25, 1, 390, 60, 1, 1, 1}, {-25, 1, 390, 60, 1, 1, -1},
            {150, 0, 390, 200, 1, 1, 1}, {150, 0, 390, 200, 1, 0, 0},
            {70, 0, 390, 60, 1, 0, 0}, {200, 160, 390, 60, 1, 0, 0},
            {3, 0, 390, 60, 1, 1, 0}, {150, 0, 0, 60, 1, 0, 0},
            {NAN, 0, 390, 60, 1, 0, 0}, {INFINITY, 0, 390, 60, 1, 0, 0}
        };
        for (NSUInteger i = 0; i < sizeof(swipes)/sizeof(swipes[0]); i++) {
            int actual = DXToolbarHorizontalResult(swipes[i].x, swipes[i].y, swipes[i].width,
                swipes[i].button, swipes[i].has, swipes[i].inside);
            if (actual != swipes[i].expected) { NSLog(@"FAIL horizontal %lu: %d", (unsigned long)i, actual); return 1; }
            checks++;
        }
        NSMutableDictionary *panelPrefs = [@{kDXPanelLeftItems: @[], kDXPanelRightItems: @[@{@"selector": @"copyAction:", @"name": @"Copy"}],
            kDXPanelCommonItems: @"malformed", kDXPanelScale: @(NAN)} mutableCopy];
        if (DXKeyboardPanelItems(nil, @"left").count || DXKeyboardPanelItems(panelPrefs, @"left").count ||
            DXKeyboardPanelItems(panelPrefs, @"common").count || DXKeyboardPanelItems(panelPrefs, @"right").count != 1 ||
            DXKeyboardPanelItems(@{}, @"left").count != 0 || DXKeyboardPanelNumber(panelPrefs, kDXPanelScale, 100, 70, 120) != 100) return 1;
        [panelPrefs removeObjectForKey:kDXPanelCommonItems];
        if (DXKeyboardPanelItems(panelPrefs, @"common").count != 0 || DXKeyboardPanelItems(panelPrefs, @"left").count != 0) return 1;
        checks += 7;
        NSMutableArray *savedButtons = [NSMutableArray array];
        for (NSInteger i = 0; i < 20; i++) [savedButtons addObject:@{@"selector": [NSString stringWithFormat:@"button%ld", (long)i], @"name": @"kept"}];
        NSArray *order = @[savedButtons, @[@{@"selector": @"disabled-record"}]];
        // Missing and legacy on/off values all use the same two-row capacity.
        for (NSArray *fixture in @[
            @[@{}, @"top", @12],
            @[@{@"topmultirowBOOL": @NO}, @"top", @12],
            @[@{DXScopedPreferenceKey(kButtonsPerRowKey, @"top"): @4, @"topmultirowBOOL": @YES}, @"top", @8],
            @[@{DXScopedPreferenceKey(kButtonsPerRowKey, @"top"): @4, @"topmultirowBOOL": @NO}, @"top", @8],
            @[@{DXScopedPreferenceKey(kButtonsPerRowKey, @"top"): @1}, @"top", @2],
            @[@{DXScopedPreferenceKey(kButtonsPerRowKey, @"top"): @8}, @"top", @16],
            @[@{}, @"bottom", @8],
            @[@{@"topmultirowBOOL": @YES}, @"bottom", @8],
        ]) {
            NSDictionary *settings = fixture[0];
            NSArray *normalized = DXToolbarOrderFittingCapacity(order, settings, fixture[1]);
            NSUInteger active = 0;
            for (NSDictionary *entry in normalized[0]) if (![entry[@"disabled"] boolValue]) active++;
            if (active != [fixture[2] unsignedIntegerValue] || [normalized[0] count] != 20 ||
                ![normalized[1] isEqual:order[1]] || ![normalized[0][19][@"name"] isEqual:@"kept"]) return 1;
            checks++;
        }
        NSString *button = @"copyAction:";
        NSString *custom = @"__typex_link_action_example";
        NSMutableDictionary *prefs = [NSMutableDictionary dictionary];
        expect(prefs, button, DXShortcutGestureTap, @"bottom", @[button]);
        expect(prefs, kNewButtonPendingIdentifier, DXShortcutGestureTap, @"bottom", @[]);
        expect(prefs, @"__typexdraft_saved", DXShortcutGestureTap, @"bottom", @[]);
        expect(nil, button, DXShortcutGestureTap, @"bottom", @[]);
        for (int gesture = 0; gesture < DXShortcutGestureTap; gesture++) {
            expect(prefs, button, gesture, @"bottom", @[]);
        }

        // Prior releases ignored this obsolete long-press single action.
        prefs[kCustomActionskey] = @[@{@"identifier": button, @"selector": @"obsoleteAction:"}];
        expect(prefs, button, DXShortcutGestureLongPress, @"bottom", @[]);
        prefs[kSubActionskey] = @[@{@"identifier": button, @"selector": custom},
                                  @{@"identifier": button, @"selector": @"pasteAction:"}];
        prefs[kTapCustomActionskey] = @[@{@"identifier": button, @"selector": @"selectAllAction:"}];
        expect(prefs, button, DXShortcutGestureLongPress, @"bottom", (@[custom, @"pasteAction:"]));
        expect(prefs, button, DXShortcutGestureTap, @"bottom", @[@"selectAllAction:"]);
        prefs[kShortcutskey] = @[@[], @[@{@"selector": button, kTapSubActionsEntryKey: @YES}]];
        expect(prefs, button, DXShortcutGestureTap, @"bottom", (@[custom, @"pasteAction:"]));
        expect(prefs, button, DXShortcutGestureTap, @"top", @[button]);

        for (NSString *scope in @[@"bottom", @"top"]) {
            for (int gesture = 0; gesture <= DXShortcutGestureTap; gesture++) {
                NSString *key = DXCustomActionsKeyForGesture(gesture, scope);
                NSMutableDictionary *fixture = [prefs mutableCopy];
                fixture[key] = @[@{@"identifier": @"other", @"selectors": @[@"otherAction:"]},
                                 @{@"identifier": button, @"selectors": @[custom, @"pasteAction:", custom]}];
                expect(fixture, button, gesture, scope, (@[custom, @"pasteAction:", custom]));
                [[GestureCleanup new] removeReferencesToSelector:custom fromPreferences:fixture];
                expect(fixture, button, gesture, scope, @[@"pasteAction:"]);
                [[GestureCleanup new] removeReferencesToSelector:@"pasteAction:" fromPreferences:fixture];
                expect(fixture, button, gesture, scope, @[]);
                expect(fixture, @"other", gesture, scope, @[@"otherAction:"]);

                // Corrupt lists fail closed; invalid elements cannot dispatch.
                fixture[key] = @[@{@"identifier": button, @"selectors": @42}];
                expect(fixture, button, gesture, scope, @[]);
                fixture[key] = @[@{@"identifier": button, @"selectors": @[@42, @"", @"copyAction:"]}];
                expect(fixture, button, gesture, scope, @[@"copyAction:"]);
                if (gesture >= DXShortcutGestureSwipeUp && gesture <= DXShortcutGestureSwipeRight) {
                    fixture[key] = @[@{@"identifier": button, @"selector": @"copyAction:", @"selector2": @"pasteAction:"}];
                    expect(fixture, button, gesture, scope, @[@"pasteAction:"]);
                    fixture[key] = @[@{@"identifier": button, @"selector": @"copyAction:", @"selector2": @""}];
                    expect(fixture, button, gesture, scope, @[]);
                }
            }
        }

        // Independent per-gesture lists on the same button in both toolbars.
        for (NSString *scope in @[@"bottom", @"top"]) {
            for (int gesture = 0; gesture <= DXShortcutGestureTap; gesture++) {
                NSString *value = [NSString stringWithFormat:@"%@-%d", scope, gesture];
                prefs[DXCustomActionsKeyForGesture(gesture, scope)] = @[@{@"identifier": button, @"selectors": @[value]}];
            }
        }
        for (NSString *scope in @[@"bottom", @"top"]) {
            for (int gesture = 0; gesture <= DXShortcutGestureTap; gesture++) {
                expect(prefs, button, gesture, scope, @[[NSString stringWithFormat:@"%@-%d", scope, gesture]]);
            }
        }
        NSMutableDictionary *panelCleanup = [@{kDXPanelLeftItems: @[@{@"id": @"a", @"selector": custom}, @{@"id": @"b", @"selector": button}],
            kDXPanelRightItems: @[@{@"selector": custom}], kDXPanelCommonItems: @[]} mutableCopy];
        [[GestureCleanup new] removeReferencesToSelector:custom fromPreferences:panelCleanup];
        if ([panelCleanup[kDXPanelLeftItems] count] != 1 || [panelCleanup[kDXPanelRightItems] count] || [panelCleanup[kDXPanelCommonItems] count]) return 1;
        checks++;
        printf("PASS: %lu gesture compatibility, isolation, ordering, deletion and malformed-input checks\n", (unsigned long)checks);
    }
    return 0;
}
