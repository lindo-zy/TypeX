#import "PanelApplicationsProduction.h"
static NSUInteger checks;
static void check(BOOL condition, NSString *message) { checks++; NSCAssert(condition, @"%@", message); }
static PSSpecifier *row(NSString *identifier, NSString *name) {
    PSSpecifier *item = [PSSpecifier preferenceSpecifierNamed:name target:nil set:NULL get:NULL detail:nil cell:PSSwitchCell edit:nil];
    [item setProperty:identifier forKey:@"applicationIdentifier"]; return item;
}
static NSArray *selectedIDs(DXPPanelApplicationsController *controller) {
    NSMutableArray *result = [NSMutableArray array];
    for (PSSpecifier *item in controller.specifiers)
        if ([[item propertyForKey:@"panelApplicationSelected"] boolValue]) [result addObject:[item propertyForKey:@"applicationIdentifier"]];
    return result;
}
static NSArray *applicationIDs(NSDictionary *preferences, NSString *panel) {
    return [DXPanelApplications(preferences, panel) valueForKey:@"bundleIdentifier"];
}
int main(void) {
    @autoreleasepool {
        NSString *panel = DXPanelSelector(@"keyboard"), *other = DXPanelSelector(@"gesture");
        NSString *notes = @"com.apple.mobilenotes", *settings = @"com.apple.Preferences", *mail = @"com.apple.mobilemail", *off = @"com.example.off";
        NSDictionary *copy = @{@"id": @"copy", @"selector": @"copyAction:", @"extra": @42};
        NSMutableDictionary *preferences = [@{kDXPanels: @[
            @{@"id": @"keyboard", @"kind": DXPanelKeyboardKind, @"items": @[copy], @"preferences": @{kDXPanelColumns: @4}},
            @{@"id": @"gesture", @"kind": DXPanelGestureKind, @"items": @[]}], @"unrelated": @99} mutableCopy];
        DXPanelSetApplicationEnabled(preferences, panel, notes, @"Notes", YES);
        DXPanelSetApplicationEnabled(preferences, panel, settings, @"Settings", YES);
        DXPanelSetApplicationEnabled(preferences, other, notes, @"Other Notes", YES);
        DXPrefsManager *manager = DXPrefsManager.sharedInstance; manager.preferences = preferences;
        DXPPanelApplicationsController *controller = [DXPPanelApplicationsController new];
        controller.specifier = [PSSpecifier groupSpecifierWithName:@"All Applications"];
        [controller.specifier setProperty:panel forKey:@"panelSelector"];
        controller.table = [UITableView new]; controller.includeIdentifiersInSearch = YES;
        PSSpecifier *notesRow = row(notes, @"Notes"), *settingsRow = row(settings, @"Settings"), *mailRow = row(mail, @"Mail"), *offRow = row(off, @"Off");
        controller.availableSpecifiers = @[[PSSpecifier groupSpecifierWithName:@"User"], offRow,
            [PSSpecifier groupSpecifierWithName:@"System"], settingsRow, mailRow, notesRow];
        [controller viewDidLoad]; [controller viewWillAppear:YES];
        NSArray *display = controller.specifiers;
        check(controller.table.editing && [display[0] name] && [[display[0] name] isEqual:@"PANEL_APPLICATIONS_SELECTED"], @"selected apps first with reorder mode active");
        check([selectedIDs(controller) isEqual:@[notes, settings]], @"selected apps follow panel order rather than alphabetical system list");
        check([display isEqual:@[display[0], notesRow, settingsRow, controller.availableSpecifiers[0], offRow, controller.availableSpecifiers[2], mailRow]], @"selected rows appear once, unselected user and system apps follow");
        NSIndexPath *first = [NSIndexPath indexPathForRow:0 inSection:0], *second = [NSIndexPath indexPathForRow:1 inSection:0];
        NSIndexPath *user = [NSIndexPath indexPathForRow:0 inSection:1];
        check([controller tableView:controller.table canMoveRowAtIndexPath:first] && ![controller tableView:controller.table canMoveRowAtIndexPath:user], @"only enabled section can move");
        check([[controller tableView:controller.table targetIndexPathForMoveFromRowAtIndexPath:first toProposedIndexPath:user] isEqual:first], @"drag cannot enter unselected application sections");
        UITableViewCell *cell = [controller tableView:controller.table cellForRowAtIndexPath:first];
        check(cell.showsReorderControl && cell.accessoryView && cell.editingAccessoryView == cell.accessoryView, @"production cell preserves switch beside reorder handle");
        NSUInteger writes = manager.writes;
        [controller tableView:controller.table moveRowAtIndexPath:first toIndexPath:second];
        check(manager.writes == writes + 1 && [selectedIDs(controller) isEqual:@[settings, notes]], @"downward drag persists and reloads top rows");
        check([applicationIDs(manager.preferences, panel) isEqual:@[settings, notes]], @"panel icon order matches selected app order");
        check([DXPanelDefinition(manager.preferences, panel)[@"items"][0] isEqual:copy] && [DXPanelDefinition(manager.preferences, panel)[@"preferences"] isEqual:@{kDXPanelColumns: @4}] && [manager.preferences[@"unrelated"] isEqual:@99], @"non-app positions, panel options and unrelated settings preserved");
        check([applicationIDs(manager.preferences, other) isEqual:@[notes]], @"other panel order unaffected");
        [controller tableView:controller.table moveRowAtIndexPath:second toIndexPath:first];
        check([selectedIDs(controller) isEqual:@[notes, settings]], @"upward drag restores original app order");
        NSString *selector = DXPanelApplicationSelector(panel, notes);
        check(DXActionUsesFloatingApp(DXPanelActionDefinition(manager.preferences, selector), YES), @"reordering retains floating default");
        [controller setApplicationEnabled:@YES specifier:mailRow];
        check([selectedIDs(controller) isEqual:@[notes, settings, mail]], @"newly enabled app immediately joins top section");
        check(controller.specifiers.count == 6, @"empty system section removed after all its apps are selected");
        [controller setApplicationEnabled:@NO specifier:settingsRow];
        check([selectedIDs(controller) isEqual:@[notes, mail]] && ![[settingsRow propertyForKey:@"panelApplicationSelected"] boolValue], @"disabled app returns to unselected list immediately");
        controller.searchKey = @"mobilemail"; [controller reloadSpecifiers];
        check([selectedIDs(controller) isEqual:@[mail]] && controller.specifiers.count == 2, @"identifier search filters top and lower groups without duplicate or empty groups");
        check(![controller tableView:controller.table canMoveRowAtIndexPath:first], @"search hides reorder handles");
        writes = manager.writes; [controller tableView:controller.table moveRowAtIndexPath:first toIndexPath:second];
        check(manager.writes == writes, @"filtered reorder cannot corrupt full order");
        controller.searchKey = @"Settings"; [controller reloadSpecifiers];
        check(!selectedIDs(controller).count && controller.specifiers.count == 2 && [[controller.specifiers[1] propertyForKey:@"applicationIdentifier"] isEqual:settings], @"search finds disabled apps in lower section");
        controller.searchKey = @""; [controller reloadSpecifiers];
        controller.availableSpecifiers = @[[PSSpecifier groupSpecifierWithName:@"System"], settingsRow, mailRow];
        [controller reloadSpecifiers];
        check([selectedIDs(controller) isEqual:@[notes, mail]], @"uninstalled selected app remains visible and removable");
        PSSpecifier *missing = controller.specifiers[1];
        [controller setApplicationEnabled:@NO specifier:missing];
        check([selectedIDs(controller) isEqual:@[mail]], @"uninstalled app can be disabled");
        [controller setApplicationEnabled:@NO specifier:mailRow];
        check(!selectedIDs(controller).count && [[controller.specifiers[0] name] isEqual:@"System"], @"empty selected section disappears");

        // Exhaust source/destination pairs against the real move helper.
        for (NSUInteger from = 0; from < 6; from++) for (NSUInteger to = 0; to < 6; to++) {
            NSMutableDictionary *snapshot = [preferences mutableCopy];
            DXPanelUpdate(snapshot, panel, @{@"items": @[copy]});
            NSMutableArray *expected = [NSMutableArray array];
            for (NSUInteger index = 0; index < 6; index++) {
                NSString *identifier = [NSString stringWithFormat:@"com.example.app%lu", (unsigned long)index];
                [expected addObject:identifier]; DXPanelSetApplicationEnabled(snapshot, panel, identifier, identifier, YES);
            }
            NSArray *rawBefore = DXPanelDefinition(snapshot, panel)[@"items"];
            NSString *moving = expected[from], *anchor = expected[to];
            BOOL changed = DXPanelMoveApplication(snapshot, panel, moving, anchor, from < to);
            [expected removeObjectAtIndex:from]; [expected insertObject:moving atIndex:to];
            check(changed == (from != to) && [applicationIDs(snapshot, panel) isEqual:expected], @"all up/down/no-op drag positions match visible order");
            NSArray *rawAfter = DXPanelDefinition(snapshot, panel)[@"items"];
            check([rawAfter[0] isEqual:copy] && [[NSSet setWithArray:rawAfter] isEqual:[NSSet setWithArray:rawBefore]], @"reorder preserves every raw application record and non-app position");
        }
        NSMutableDictionary *mixed = [preferences mutableCopy];
        NSString *manual = @"__typex_link_action_oldnotes";
        mixed[@"linkactions"] = @[@{@"selector": manual, @"type": @"openapp", @"link": notes, @"floating": @NO}];
        NSDictionary *duplicate = @{@"selector": manual, @"id": @"duplicate", @"name": @"Old Notes"};
        NSMutableArray *raw = [DXPanelDefinition(mixed, panel)[@"items"] mutableCopy]; [raw addObject:duplicate]; [raw addObject:@42];
        DXPanelUpdate(mixed, panel, @{@"items": raw});
        check([applicationIDs(mixed, panel) isEqual:@[notes, settings]], @"duplicate manual app references produce one selected row");
        check(DXPanelMoveApplication(mixed, panel, notes, settings, YES), @"duplicate app group can move");
        check([DXPanelDefinition(mixed, panel)[@"items"][0] isEqual:copy] && [DXPanelDefinition(mixed, panel)[@"items"] containsObject:duplicate] && [DXPanelDefinition(mixed, panel)[@"items"] containsObject:@42], @"duplicate refs and malformed unrelated raw records preserved");
        check(!DXActionUsesFloatingApp(DXPanelActionDefinition(mixed, manual), YES), @"explicit old floating choice survives ordering");
        NSDictionary *beforeStale = [mixed copy];
        check(!DXPanelMoveApplication(mixed, panel, notes, off, NO) && [mixed isEqual:beforeStale], @"removed drag anchor fails without adding apps");
        check(!DXPanelMoveApplication(mixed, @"__typex_panel_deleted", notes, settings, NO) && [mixed isEqual:beforeStale], @"stale editor cannot recreate deleted panel");
        NSData *serialized = [NSPropertyListSerialization dataWithPropertyList:mixed format:NSPropertyListBinaryFormat_v1_0 options:0 error:nil];
        NSDictionary *reloaded = [NSPropertyListSerialization propertyListWithData:serialized options:NSPropertyListImmutable format:NULL error:nil];
        check([applicationIDs(reloaded, panel) isEqual:@[settings, notes]], @"app order survives serialization and reopening");
        printf("PASS: %lu enabled-app placement, production row/search/reorder and preservation checks (Preferences/UI doubles)\n", (unsigned long)checks);
    }
    return 0;
}
