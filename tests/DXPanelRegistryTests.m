#import "PanelRegistryProduction.h"
#import "../DXGlobalPanelPolicy.h"
static NSUInteger checks;
static void check(BOOL condition, NSString *message) { checks++; NSCAssert(condition, @"%@", message); }
int main(void) {
    @autoreleasepool {
        NSString *link = @"__typex_link_action_url", *text = @"__typex_link_action_text", *script = @"__typex_link_action_script";
        NSDictionary *definition = @{@"selector": link, @"type": @"urlscheme", @"link": @"example://search?q=@@@", @"cutreplace": @YES};
        NSDictionary *old = @{kDXPanelLeftItems: @[@{@"id": @"item", @"selector": link}], kDXPanelRightItems: @[],
            kDXPanelColumns: @5, @"keyboardpanelleftcolumns": @3, kDXPanelScale: @90,
            @"dockgesturebindings": @{@"right": @"__typex_dock_panel_left", @"up": @""},
            @"statusbargesturebindings": @{@"left.tap": @{@"enabled": @YES, @"selector": @"__typex_statusbar_panel_right"}},
            @"linkactions": @[definition, @{@"selector": text, @"type": @"text"}, @{@"selector": script, @"type": @"javascript"}], @"unrelated": @42};
        NSDictionary *migrated = DXPanelMigratePreferences(old);
        check(DXPanelDefinitions(migrated, DXPanelKeyboardKind).count == 3 && DXPanelDefinitions(migrated, DXPanelGestureKind).count == 3, @"legacy content copied to both entry contexts");
        check([DXPanelMigratePreferences(migrated) isEqual:migrated], @"migration idempotent");
        check([DXPanelMigratePreferences(old) isEqual:migrated], @"independent processes derive identical IDs");
        check(!old[kDXPanels] && [migrated[@"unrelated"] isEqual:@42], @"migration does not mutate input or unrelated preferences");
        check(!DXPanelMigratePreferences(@{})[kDXPanels], @"empty authority is not turned into a configured snapshot");
        check(!DXPanelMigratePreferences(nil), @"missing preferences stay missing");
        NSString *keyboard = DXPanelSelector(@"legacy-keyboard-left"), *gesture = DXPanelSelector(@"legacy-gesture-left");
        check(DXPanelAllowed(migrated, keyboard, DXPanelKeyboardKind) && !DXPanelAllowed(migrated, keyboard, DXPanelGestureKind), @"keyboard panel type boundary");
        check(DXPanelAllowed(migrated, gesture, DXPanelGestureKind) && !DXPanelAllowed(migrated, gesture, DXPanelKeyboardKind), @"gesture panel type boundary");
        check([migrated[@"dockgesturebindings"][@"right"] isEqual:gesture] && [migrated[@"dockgesturebindings"][@"up"] isEqual:@""], @"explicit Dock binding and clear survive migration");
        check([migrated[@"statusbargesturebindings"][@"left.tap"][@"selector"] isEqual:DXPanelSelector(@"legacy-gesture-right")], @"status-bar target preserved");
        check(!DXToolbarAction(migrated, @"top", @"left") && !DXToolbarAction(migrated, @"bottom", @"right"), @"toolbar has no default action after migration");
        check([DXPanelPreferences(migrated, keyboard)[kDXPanelColumns] isEqual:@3], @"profile overrides migrate");
        check([DXPanelPreferences(migrated, DXPanelSelector(@"legacy-keyboard-right"))[kDXPanelColumns] isEqual:@5], @"shared fallback migrates independently");
        check(DXPanelItems(migrated, keyboard).count == 1 && DXPanelItems(migrated, gesture).count == 1, @"input-dependent URL is retained in both lists");
        check(DXPanelCustomActionSelectable(definition, DXPanelGestureKind) && DXGlobalPanelActionNeedsInput(definition) && !DXGlobalCustomActionSupported(definition), @"replacement is selectable but cannot execute globally");
        for (NSString *kind in @[DXPanelKeyboardKind, DXPanelGestureKind]) {
            check(DXPanelItemAllowed(migrated, link, kind), @"link selection independent of input requirement");
            check(!DXPanelItemAllowed(migrated, @"__typex_link_action_deleted", kind), @"dangling action rejected");
            check(!DXPanelItemAllowed(migrated, @"__typex_panel_deleted", kind), @"dangling panel rejected");
        }
        check(DXPanelItemAllowed(migrated, @"copyAction:", DXPanelKeyboardKind) && !DXPanelItemAllowed(migrated, @"copyAction:", DXPanelGestureKind), @"base keyboard operation cannot enter gesture context");
        check(DXPanelItemAllowed(migrated, text, DXPanelKeyboardKind) && !DXPanelItemAllowed(migrated, text, DXPanelGestureKind), @"text context boundary");
        check(DXPanelItemAllowed(migrated, script, DXPanelKeyboardKind) && !DXPanelItemAllowed(migrated, script, DXPanelGestureKind), @"script context boundary");
        NSMutableDictionary *preferences = [migrated mutableCopy];
        NSMutableArray *panels = [preferences[kDXPanels] mutableCopy];
        for (NSUInteger i = 0; i < 40; i++) [panels addObject:@{@"id": [NSString stringWithFormat:@"extra-%lu", (unsigned long)i], @"kind": DXPanelKeyboardKind, @"name": @"same name", @"items": @[]}];
        preferences[kDXPanels] = panels;
        check(DXPanelDefinitions(preferences, DXPanelKeyboardKind).count == 43, @"arbitrary number and duplicate display names supported");
        NSString *nested = DXPanelSelector(@"extra-0");
        DXPanelUpdate(preferences, keyboard, @{@"name": @"renamed", @"items": @[@{@"selector": nested}, @{@"selector": gesture}, @{@"selector": @"copyAction:"}, @{@"selector": text}, NSNull.null]});
        check(DXPanelItems(preferences, keyboard).count == 3, @"keyboard panel keeps same-type panel, basic action and text, rejects gesture panel");
        DXPanelUpdate(preferences, gesture, @{@"items": @[@{@"selector": keyboard}, @{@"selector": gesture}, @{@"selector": @"copyAction:"}, @{@"selector": link}, @{@"selector": text}, @{@"selector": script}]});
        check(DXPanelItems(preferences, gesture).count == 2, @"gesture panel cannot run keyboard panel, built-in, text or script");
        check([DXPanelDefinition(preferences, keyboard)[@"id"] isEqual:@"legacy-keyboard-left"], @"rename preserves selector identity");
        check([DXPanelDefinition(preferences, gesture)[@"name"] isEqual:DXPanelDefinition(migrated, gesture)[@"name"]], @"rename does not affect another panel");
        DXPanelUpdate(preferences, keyboard, @{@"icon": @"star", @"items": @[@{@"id": @"named-item", @"selector": @"copyAction:", @"name": @"My copy", @"icon": @"heart"}]});
        DXPanelUpdate(preferences, gesture, @{@"icon": @"com.apple.mobilenotes"});
        NSDictionary *beforeDisplay = [preferences copy];
        check([DXPanelDisplayDefinition(preferences, keyboard)[@"icon"] isEqual:@"keyboard"] && [DXPanelDisplayDefinition(preferences, gesture)[@"icon"] isEqual:@"hand.draw"], @"legacy panel icon overrides display as their type defaults");
        check([DXPanelItems(preferences, keyboard) isEqual:@[@{@"id": @"named-item", @"selector": @"copyAction:", @"name": @"My copy"}]], @"legacy item icon override ignored while name, identity and action survive");
        check([preferences isEqual:beforeDisplay] && [DXPanelDefinition(preferences, keyboard)[@"icon"] isEqual:@"star"], @"display resolution leaves stored definitions intact for update and deletion");
        check(!DXPanelDisplayDefinition(preferences, @"__typex_panel_deleted"), @"deleted panel has no default display definition");
        DXPanelUpdate(preferences, keyboard, @{@"preferences": @{kDXPanelColumns: @4, @"linkactions": @[], kDXPanels: @[]}});
        check([DXPanelPreferences(preferences, keyboard)[kDXPanelColumns] isEqual:@4] && [DXPanelPreferences(preferences, keyboard)[@"linkactions"] isEqual:old[@"linkactions"]], @"panel options cannot override action authority");
        preferences[kDXToolbarBindings] = @{@"top.left": keyboard, @"top.right": gesture, @"bottom.left": link};
        check([DXToolbarAction(preferences, @"top", @"left") isEqual:keyboard], @"explicit keyboard panel toolbar route");
        check(!DXToolbarAction(preferences, @"top", @"right"), @"forged gesture panel toolbar route rejected");
        check([DXToolbarAction(preferences, @"bottom", @"left") isEqual:link], @"custom action toolbar route");
        check(!DXToolbarAction(preferences, @"invalid", @"left") && !DXToolbarBindingSlot(@"top", @"up"), @"invalid toolbar slot fails closed");
        NSString *store = DXCustomActionsKeyForGesture(DXShortcutGestureTap, @"top");
        preferences[store] = @[@{@"identifier": @"button", @"selectors": @[keyboard, link]}];
        [[PanelCleanup new] removeReferencesToSelector:keyboard fromPreferences:preferences];
        check([preferences[store][0][@"selectors"] isEqual:@[link]], @"delete clears button/sub-action reference without restoring defaults");
        check(!DXToolbarAction(preferences, @"top", @"left") && [DXToolbarAction(preferences, @"bottom", @"left") isEqual:link], @"delete clears only matching toolbar reference");
        [[PanelCleanup new] removeReferencesToSelector:gesture fromPreferences:preferences];
        check(![preferences[@"dockgesturebindings"][@"right"] length] && ![preferences[kDXDockRightSwipeEnabled] boolValue], @"delete clears Dock target and switch");
        [[PanelCleanup new] removeReferencesToSelector:link fromPreferences:preferences];
        check(DXPanelItems(preferences, gesture).count == 0 && !DXToolbarAction(preferences, @"bottom", @"left"), @"custom deletion clears every panel and toolbar reference");
        panels = [preferences[kDXPanels] mutableCopy];
        [panels removeObject:DXPanelDefinition(preferences, keyboard)]; preferences[kDXPanels] = panels;
        DXPanelUpdate(preferences, keyboard, @{@"name": @"stale editor"});
        check(!DXPanelDefinition(preferences, keyboard), @"stale editor cannot resurrect deleted panel");
        check(!DXPanelDefinition(@{kDXPanels: @[@42, @{@"id": @"broken", @"kind": @42}]}, @"__typex_panel_broken"), @"malformed registry entries rejected");
        check(DXPanelMigratePreferences(@{kDXPanels: @[], kDXPanelLeftItems: old[kDXPanelLeftItems]})[kDXPanels] != nil && [DXPanelDefinitions(DXPanelMigratePreferences(@{kDXPanels: @[], kDXPanelLeftItems: old[kDXPanelLeftItems]}), nil) count] == 0, @"empty registry never reimports deleted legacy panels");
        printf("PASS: %lu panel migration, context, replacement, binding and deletion checks\n", (unsigned long)checks);
    }
    return 0;
}
