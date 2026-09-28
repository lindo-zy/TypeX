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
        printf("PASS: %lu gesture compatibility, isolation, ordering, deletion and malformed-input checks\n", (unsigned long)checks);
    }
    return 0;
}
