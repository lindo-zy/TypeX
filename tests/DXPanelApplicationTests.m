#import "PanelApplicationsProduction.h"

static NSUInteger checks;
static void check(BOOL condition, NSString *message) { checks++; NSCAssert(condition, @"%@", message); }
static PSSpecifier *appRow(NSString *identifier, NSString *name) {
    PSSpecifier *row = [PSSpecifier groupSpecifierWithName:name];
    [row setProperty:identifier forKey:@"applicationIdentifier"];
    return row;
}
static DXPPanelApplicationsController *controller(NSString *selector) {
    DXPPanelApplicationsController *result = [DXPPanelApplicationsController new];
    result.specifier = [PSSpecifier groupSpecifierWithName:@"Applications"];
    [result.specifier setProperty:selector forKey:@"panelSelector"];
    return result;
}

int main(void) {
    @autoreleasepool {
        NSString *keyboard = DXPanelSelector(@"keyboard"), *gesture = DXPanelSelector(@"gesture");
        NSString *notes = @"com.apple.mobilenotes", *settings = @"com.apple.Preferences";
        NSString *manual = @"__typex_link_action_manual", *url = @"__typex_link_action_url";
        NSDictionary *manualDefinition = @{@"selector": manual, @"type": @"openapp", @"link": @" com.apple.mobilenotes ", @"floating": @NO};
        NSDictionary *urlDefinition = @{@"selector": url, @"type": @"urlscheme", @"link": settings};
        NSMutableDictionary *preferences = [@{kDXPanels: @[
            @{@"id": @"keyboard", @"kind": DXPanelKeyboardKind, @"items": @[@{@"selector": @"copyAction:", @"id": @"copy"}], @"preferences": @{kDXPanelColumns: @5}},
            @{@"id": @"gesture", @"kind": DXPanelGestureKind, @"items": @[]}],
            @"linkactions": @[manualDefinition, urlDefinition], @"unrelated": @42} mutableCopy];
        NSDictionary *before = [preferences copy];
        check(!DXPanelApplicationEnabled(preferences, keyboard, notes), @"apps initially absent are off");
        check(DXPanelSetApplicationEnabled(preferences, keyboard, notes, @"Notes", YES), @"enable app in keyboard panel");
        NSArray *items = DXPanelItems(preferences, keyboard);
        check(items.count == 2 && [items[0][@"id"] isEqual:@"copy"], @"new app appended after existing actions");
        NSDictionary *added = items.lastObject;
        NSString *selector = added[@"selector"];
        check([added[@"name"] isEqual:@"Notes"] && [added[@"id"] length] > 0, @"app gets editable name and stable item ID");
        check(DXPanelApplicationEnabled(preferences, keyboard, notes) && !DXPanelApplicationEnabled(preferences, gesture, notes), @"switch state independent per panel");
        check([preferences[@"linkactions"] isEqual:before[@"linkactions"]] && [preferences[@"unrelated"] isEqual:@42], @"no global action definitions or unrelated settings added");
        NSDictionary *definition = DXPanelActionDefinition(preferences, selector);
        check([definition[@"type"] isEqual:@"openapp"] && [definition[@"link"] isEqual:notes] && [definition[@"icon"] isEqual:notes], @"runtime and preview get app payload and app icon");
        check(DXGlobalCustomActionSupported(definition) && DXActionUsesFloatingApp(definition, YES), @"generated app executable globally with floating default");
        NSDictionary *enabledSnapshot = [preferences copy];
        check(!DXPanelSetApplicationEnabled(preferences, keyboard, notes, @"Changed", YES) && [preferences isEqual:enabledSnapshot], @"repeated enable preserves name and identity without duplicate");
        check(DXPanelSetApplicationEnabled(preferences, gesture, notes, @"Gesture Notes", YES) && DXPanelItems(preferences, gesture).count == 1, @"same app supported independently in gesture panel");
        NSString *gestureAppSelector = DXPanelItems(preferences, gesture).firstObject[@"selector"];
        check(![gestureAppSelector isEqual:selector] && [DXPanelActionDefinition(preferences, gestureAppSelector)[@"name"] isEqual:@"Gesture Notes"], @"each panel owns independent application action identity and name");
        check(DXPanelSetApplicationEnabled(preferences, keyboard, notes, nil, NO) && !DXPanelApplicationEnabled(preferences, keyboard, notes), @"disable only current panel app");
        check(DXPanelApplicationEnabled(preferences, gesture, notes) && DXPanelActionDefinition(preferences, gestureAppSelector) && !DXPanelActionDefinition(preferences, selector), @"removed app revoked while other panel keeps executable app");
        check(DXPanelSetApplicationEnabled(preferences, gesture, notes, nil, NO) && !DXPanelActionDefinition(preferences, gestureAppSelector), @"last reference removal revokes generated action");
        check(!DXPanelSetApplicationEnabled(preferences, gesture, notes, nil, NO), @"repeated disable is no-op");

        NSArray *mixed = @[@{@"selector": manual, @"id": @"old-1", @"name": @"Old Notes"},
            @{@"selector": url, @"id": @"url"}, @{@"selector": manual, @"id": @"old-2"}, @42,
            @{@"selector": @"pasteAction:", @"id": @"paste", @"extra": @"retained"}];
        DXPanelUpdate(preferences, keyboard, @{@"items": mixed});
        check(DXPanelApplicationEnabled(preferences, keyboard, notes) && !DXPanelApplicationEnabled(preferences, keyboard, settings), @"manual Open App selected; URL action is not mistaken for an app");
        NSDictionary *manualSnapshot = [preferences copy];
        check(!DXPanelSetApplicationEnabled(preferences, keyboard, notes, @"Notes", YES) && [preferences isEqual:manualSnapshot], @"existing manual actions not duplicated or changed");
        check(!DXActionUsesFloatingApp(DXPanelActionDefinition(preferences, manual), YES), @"manual app retains saved floating preference");
        check(DXPanelSetApplicationEnabled(preferences, keyboard, notes, nil, NO), @"disable removes manual app references");
        check([DXPanelDefinition(preferences, keyboard)[@"items"] isEqual:@[mixed[1], mixed[3], mixed[4]]], @"all matching duplicates removed while raw unrelated entries preserved");
        check([preferences[@"linkactions"] isEqual:before[@"linkactions"]], @"manual definitions remain available elsewhere");

        DXPrefsManager *manager = DXPrefsManager.sharedInstance;
        manager.preferences = preferences;
        DXPPanelApplicationsController *keyboardController = controller(keyboard), *gestureController = controller(gesture);
        PSSpecifier *notesRow = appRow(notes, @"Notes"), *settingsRow = appRow(settings, @"Settings");
        NSUInteger writes = manager.writes;
        [keyboardController setApplicationEnabled:@YES specifier:notesRow];
        check(manager.writes == writes + 1 && [[keyboardController readApplicationEnabled:notesRow] boolValue], @"production controller writes app switch immediately");
        [keyboardController setApplicationEnabled:@YES specifier:notesRow];
        check(manager.writes == writes + 1, @"duplicate UI toggle does not rewrite snapshot");
        check(![[gestureController readApplicationEnabled:notesRow] boolValue], @"another panel controller reads independent state");
        [gestureController setApplicationEnabled:@YES specifier:notesRow];
        NSMutableDictionary *concurrent = [manager.preferences mutableCopy];
        concurrent[@"changedElsewhere"] = @99;
        DXPanelUpdate(concurrent, keyboard, @{@"name": @"Renamed elsewhere"});
        manager.preferences = concurrent;
        [keyboardController setApplicationEnabled:@YES specifier:settingsRow];
        check([manager.preferences[@"changedElsewhere"] isEqual:@99] && [DXPanelDefinition(manager.preferences, keyboard)[@"name"] isEqual:@"Renamed elsewhere"], @"controller merges latest preferences rather than stale app list");
        check([[keyboardController readApplicationEnabled:notesRow] boolValue] && [[keyboardController readApplicationEnabled:settingsRow] boolValue] && [[gestureController readApplicationEnabled:notesRow] boolValue], @"successive toggles retain earlier apps and other panels");
        prefs = manager.preferences;
        check([preferencesLinkActionForSelector(selector) isEqual:DXPanelActionDefinition(prefs, selector)], @"actual keyboard resolver accepts panel apps");
        check([[[RuntimePanel new] definition:selector] isEqual:DXPanelActionDefinition(prefs, selector)], @"actual gesture resolver accepts panel apps");
        check([preferencesLinkActionForSelector(manual) isEqual:manualDefinition], @"ordinary custom action resolver unchanged");
        [keyboardController setApplicationEnabled:@NO specifier:notesRow];
        check(![[keyboardController readApplicationEnabled:notesRow] boolValue] && [[gestureController readApplicationEnabled:notesRow] boolValue], @"production switch off preserves other panel");
        check([[controller(keyboard) readApplicationEnabled:settingsRow] boolValue], @"reopened controller reads stored switches");
        NSData *serialized = [NSPropertyListSerialization dataWithPropertyList:manager.preferences format:NSPropertyListBinaryFormat_v1_0 options:0 error:nil];
        manager.preferences = [NSPropertyListSerialization propertyListWithData:serialized options:NSPropertyListImmutable format:NULL error:nil];
        check([[keyboardController readApplicationEnabled:settingsRow] boolValue] && [[gestureController readApplicationEnabled:notesRow] boolValue], @"switches survive property-list serialization and reload");

        for (id invalid in @[@"", @"com", @"com..app", @"com.app\n", @"com.app/path", @"app://x", @42, NSNull.null]) {
            NSMutableDictionary *snapshot = [manager.preferences mutableCopy];
            check(!DXPanelApplicationIdentifierValid(invalid) && !DXPanelApplicationSelector(keyboard, invalid), @"invalid identifier rejected");
            check(!DXPanelSetApplicationEnabled(snapshot, keyboard, invalid, @"Invalid", YES) && [snapshot isEqual:manager.preferences], @"invalid identifier never updates panels");
        }
        check(!DXPanelActionDefinition(manager.preferences, [DXPanelApplicationSelectorPrefix stringByAppendingString:@"bad://x"]), @"forged app selector cannot execute");
        check(!DXPanelActionDefinition(@{@"linkactions": @[@{@"selector": selector}]}, selector), @"generated selector needs panel ownership even if forged in global actions");
        concurrent = [manager.preferences mutableCopy];
        NSMutableArray *panels = [concurrent[kDXPanels] mutableCopy];
        [panels removeObject:DXPanelDefinition(concurrent, keyboard)]; concurrent[kDXPanels] = panels;
        manager.preferences = concurrent; writes = manager.writes;
        [keyboardController setApplicationEnabled:@YES specifier:settingsRow];
        check(manager.writes == writes && !DXPanelDefinition(manager.preferences, keyboard) && ![[keyboardController readApplicationEnabled:settingsRow] boolValue], @"stale app page cannot resurrect deleted panel");
        [gestureController setApplicationEnabled:@NO specifier:notesRow];
        prefs = manager.preferences;
        check(!preferencesLinkActionForSelector(selector) && ![[RuntimePanel new] definition:selector], @"both actual runtime resolvers revoke last removed app");

        concurrent = [manager.preferences mutableCopy];
        for (NSUInteger i = 0; i < 100; i++) {
            NSString *identifier = [NSString stringWithFormat:@"com.example.app%lu", (unsigned long)i];
            check(DXPanelSetApplicationEnabled(concurrent, gesture, identifier, identifier, YES), @"large app list supports repeated additions");
        }
        check(DXPanelItems(concurrent, gesture).count == 100, @"all selected applications retained for existing three-row pager");
        printf("PASS: %lu panel application toggle, preservation, persistence and production resolver checks\n", (unsigned long)checks);
    }
    return 0;
}
