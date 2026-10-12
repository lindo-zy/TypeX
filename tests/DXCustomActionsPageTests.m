#import "CustomActionsPageHarness.h"

// Production controllers and display/storage helpers, UIKit drawing omitted.
static NSUInteger checks;
static void check(BOOL condition, NSString *message) { checks++; NSCAssert(condition, @"%@", message); }
static NSString *selector(NSUInteger index) { return [kLinkActionSelectorPrefix stringByAppendingFormat:@"%lu", (unsigned long)index]; }

static NSMutableDictionary *fixture(void) {
    NSMutableArray *entries = [NSMutableArray array], *groups = [NSMutableArray array];
    for (NSUInteger group = 0; group < 10; group++) [groups addObject:[NSString stringWithFormat:@"分组%lu", (unsigned long)group]];
    for (NSUInteger index = 0; index < 200; index++)
        [entries addObject:[@{@"selector": selector(index), @"name": [NSString stringWithFormat:@"动作%03lu", (unsigned long)index],
            @"type": index % 2 ? @"text" : @"openapp", @"link": [NSString stringWithFormat:@"com.example.app%lu", (unsigned long)index],
            @"icon": @"link", @"group": groups[index / 20], @"textrecords": @[@"hello"]} mutableCopy]];
    return [@{kLinkActionskey: entries, kLinkActionGroupsKey: groups,
        kCustomActionskey: @[@{@"identifier": @"copyAction:", @"selector2": selector(0)}],
        kSubActionskey: @[@{@"identifier": @"copyAction:", @"selectors": @[selector(0), selector(1)]}]} mutableCopy];
}

static void renderPage(DXPCustomActionsController *page) {
    for (NSInteger section = 0; section < [page numberOfSectionsInTableView:page.tableView]; section++) {
        [page tableView:page.tableView viewForHeaderInSection:section];
        [page tableView:page.tableView titleForHeaderInSection:section];
        for (NSInteger row = 0; row < [page tableView:page.tableView numberOfRowsInSection:section]; row++) {
            NSIndexPath *path = [NSIndexPath indexPathForRow:row inSection:section];
            NSUInteger before = page.tableView.dequeueCount;
            UITableViewCell *cell = [page tableView:page.tableView cellForRowAtIndexPath:path];
            check(cell != nil && page.tableView.dequeueCount == before + 1, @"each displayed row returns exactly one registered cell");
        }
    }
}

static NSDictionary *definition(NSDictionary *prefs, NSUInteger index) {
    for (NSDictionary *entry in prefs[kLinkActionskey])
        if ([entry[@"selector"] isEqual:selector(index)]) return entry;
    return nil;
}

static DXPActionOrganizationController *groupManager(UINavigationController *nav) {
    DXPActionOrganizationController *manager = [DXPActionOrganizationController new];
    manager.managesGroups = YES;
    manager.navigationController = nav;
    [manager viewDidLoad];
    return manager;
}

int main(void) {
    @autoreleasepool {
        DXPrefsManager *storage = DXPrefsManager.sharedInstance;
        storage.preferences = fixture();
        UINavigationController *nav = [UINavigationController new];
        nav.viewControllers = @[];
        RenderOnDataSourceAssignment = YES;
        DXPCustomActionsController *page = [DXPCustomActionsController new];
        page.navigationController = nav;
        [page viewDidLoad];
        [page viewWillAppear:YES];
        RenderOnDataSourceAssignment = NO;
        check(page.view == page.tableView && page.groupNames.count == 10 && page.linkActions.count == 200, @"initial setup prepares a single table and all ten groups");
        check([page numberOfSectionsInTableView:page.tableView] == 11, @"ten groups plus ungrouped");
        renderPage(page);
        UITableView *foreign = [UITableView new];
        check([page tableView:foreign cellForRowAtIndexPath:[NSIndexPath indexPathForRow:0 inSection:0]] != nil, @"foreign table registration still works");

        NSArray *originalOrder = [storage.preferences[kLinkActionskey] valueForKey:@"selector"];
        [page setAllCollapsed:YES];
        check([page tableView:page.tableView numberOfRowsInSection:0] == 0, @"collapse hides rows");
        page.actionSearchController.searchBar.text = @"分组3";
        [page updateSearchResultsForSearchController:page.actionSearchController];
        check(page.searchIndexes.count == 20, @"search includes group names despite collapse");
        [page toggleEditing:nil];
        [page selectAllVisible];
        check(page.batchSelectors.count == 20, @"select all covers only search matches");
        NSDictionary *beforeMissingGroup = [storage.preferences copy];
        [page applySelectors:[page.batchSelectors copy] toGroup:@"Already deleted"];
        check([storage.preferences isEqual:beforeMissingGroup] && page.batchSelectors.count == 20,
              @"a missing destination preserves data and current checks");
        [page moveSelected];
        DXPActionOrganizationController *chooser = nav.viewControllers.lastObject;
        [chooser viewDidLoad];
        NSUInteger target = [chooser.visibleGroups indexOfObject:@"分组8"] + 1;
        [chooser tableView:chooser.tableView didSelectRowAtIndexPath:[NSIndexPath indexPathForRow:target inSection:0]];
        check(DXActionsInGroup(storage.preferences[kLinkActionskey], @"分组8").count == 40, @"group chooser moves every selected action");
        check([originalOrder isEqual:[storage.preferences[kLinkActionskey] valueForKey:@"selector"]], @"batch grouping preserves definition order");
        check([storage.preferences[kCustomActionskey][0][@"selector2"] isEqual:selector(0)], @"grouping preserves gesture reference");
        page.actionSearchController.searchBar.text = @"";
        [page updateSearchResultsForSearchController:page.actionSearchController];
        check([page tableView:page.tableView numberOfRowsInSection:0] == 0, @"clearing search restores stored collapse state");
        [page setAllCollapsed:NO];
        page.actionTypeFilter = @"openapp";
        [page actionFilterDidChange];
        [page selectAllVisible];
        check(page.batchSelectors.count == 100, @"type filter selection contains only openapp actions");
        page.actionTypeFilter = @"text";
        [page actionFilterDidChange];
        check(page.batchSelectors.count == 0 && page.searchIndexes.count == 100, @"changing filter clears checks");
        [page selectAllVisible];
        NSDictionary *beforeCancel = [storage.preferences copy];
        [page deleteSelected];
        UIAlertController *confirm = page.presentedViewController;
        check(confirm.actions.count == 2 && [storage.preferences isEqual:beforeCancel], @"bulk deletion waits for confirmation");
        if (confirm.actions.lastObject.handler) confirm.actions.lastObject.handler(confirm.actions.lastObject);
        check([storage.preferences isEqual:beforeCancel], @"cancelled deletion writes nothing");
        [page ungroupSelected];
        check(DXActionsInGroup(storage.preferences[kLinkActionskey], @"").count == 100, @"ungroup keeps all selected actions");
        [page toggleEditing:nil];
        page.actionTypeFilter = @"";
        [page actionFilterDidChange];

        [page startSorting];
        NSIndexPath *sortFrom = [NSIndexPath indexPathForRow:0 inSection:0];
        NSIndexPath *sortTo = [NSIndexPath indexPathForRow:1 inSection:0];
        NSString *moving = page.linkActions[[page.groupIndexes[0][0] unsignedIntegerValue]][@"selector"];
        check([page tableView:page.tableView canMoveRowAtIndexPath:sortFrom] &&
              [page tableView:page.tableView canEditRowAtIndexPath:sortFrom], @"sort mode exposes UIKit reorder controls");
        [page tableView:page.tableView moveRowAtIndexPath:sortFrom toIndexPath:sortTo];
        check([page.linkActions[[page.groupIndexes[0][1] unsignedIntegerValue]][@"selector"] isEqual:moving], @"sort uses stable selectors within its group");
        NSIndexPath *crossGroup = [NSIndexPath indexPathForRow:0 inSection:1];
        check([[page tableView:page.tableView targetIndexPathForMoveFromRowAtIndexPath:sortFrom toProposedIndexPath:crossGroup] isEqual:sortFrom],
              @"sort cannot accidentally change group membership");
        [page toggleEditing:nil];

        DXPActionOrganizationController *groups = groupManager(nav);
        [groups requestNameForGroup:@"分组0"];
        UIAlertController *rename = groups.presentedViewController;
        rename.textFields.firstObject.text = @"工作";
        rename.actions.firstObject.handler(rename.actions.firstObject);
        check([DXActionStoredGroups(storage.preferences) containsObject:@"工作"] && ![DXActionStoredGroups(storage.preferences) containsObject:@"分组0"], @"rename updates group registry");
        check([definition(storage.preferences, 0)[@"group"] isEqual:@"工作"], @"rename follows membership");
        [groups confirmDeleteGroup:@"工作"];
        UIAlertController *remove = groups.presentedViewController;
        remove.actions.firstObject.handler(remove.actions.firstObject);
        check([storage.preferences[kLinkActionskey] count] == 200 && !definition(storage.preferences, 0)[@"group"], @"deleting a group preserves its actions");
        [groups createGroup];
        UIAlertController *create = groups.presentedViewController;
        create.textFields.firstObject.text = @"空分组";
        create.actions.firstObject.handler(create.actions.firstObject);
        check([DXActionStoredGroups(storage.preferences) containsObject:@"空分组"], @"group manager creates empty groups");
        NSArray *beforeSort = [storage.preferences[kLinkActionskey] valueForKey:@"selector"];
        [groups tableView:groups.tableView moveRowAtIndexPath:[NSIndexPath indexPathForRow:0 inSection:0] toIndexPath:[NSIndexPath indexPathForRow:3 inSection:0]];
        check([beforeSort isEqual:[storage.preferences[kLinkActionskey] valueForKey:@"selector"]], @"group reordering preserves definition order");

        [page viewWillAppear:YES];
        page.tableView.renderRowsOnReload = YES;
        NSDictionary *populated = [storage.preferences copy];
        storage.preferences = @{};
        [page viewWillAppear:YES];
        check(page.linkActions.count == 0 && [page tableView:page.tableView numberOfRowsInSection:0] == 1, @"existing page can reload an empty store safely");
        storage.preferences = populated;
        [page viewWillAppear:YES];
        page.tableView.renderRowsOnReload = NO;

        // Save locates an action by selector after a concurrent array reorder.
        nav.viewControllers = @[];
        [page pushEditorForCustomRow:0];
        DXPLinkActionEditorController *editor = nav.viewControllers.lastObject;
        NSMutableDictionary *draft = [editor.entry mutableCopy];
        NSString *editingSelector = draft[@"selector"];
        draft[@"name"] = @"Saved after reorder";
        NSMutableDictionary *live = [storage.preferences mutableCopy];
        NSMutableArray *definitions = DXActionMutableDefinitions(live);
        id first = definitions.firstObject;
        [definitions removeObjectAtIndex:0];
        [definitions addObject:first];
        live[kLinkActionskey] = definitions;
        storage.preferences = live;
        editor.completion(draft);
        check([[storage.preferences[kLinkActionskey] lastObject][@"selector"] isEqual:editingSelector] &&
              [[storage.preferences[kLinkActionskey] lastObject][@"name"] isEqual:@"Saved after reorder"], @"editor save updates the same selector at its new index");
        check(![storage.preferences[kLinkActionskey][0][@"name"] isEqual:@"Saved after reorder"], @"editor save never overwrites the replacement row");

        nav.viewControllers = @[];
        page.defaultActionGroup = @"分组1";
        NSUInteger count = [storage.preferences[kLinkActionskey] count];
        [page startAddFlowForType:@"openapp"];
        DXPLinkActionEditorController *added = nav.viewControllers.lastObject;
        check([added.entry[@"group"] isEqual:@"分组1"] && [storage.preferences[kLinkActionskey] count] == count, @"group add starts a draft without persisting");
        NSMutableDictionary *newEntry = [added.entry mutableCopy];
        newEntry[@"link"] = @"com.example.new";
        added.completion(newEntry);
        check([storage.preferences[kLinkActionskey] count] == count + 1, @"add save persists one definition");
        added.completion(newEntry);
        check([storage.preferences[kLinkActionskey] count] == count + 1, @"duplicate add completion never duplicates the action");

        DXPCustomActionViewController *picker = [DXPCustomActionViewController new];
        picker.selectionManagedExternally = YES;
        picker.allowsMultipleSelection = YES;
        picker.allowsCreatingCustomActions = YES;
        picker.navigationController = nav;
        [picker viewDidLoad];
        check(picker.customDisplayRows.count > picker.linkActions.count, @"picker includes group headers");
        NSUInteger header = [picker.customDisplayRows indexOfObjectPassingTest:^BOOL(NSDictionary *row, NSUInteger index, BOOL *stop) { return [row[@"kind"] isEqual:@"group"]; }];
        NSUInteger chosenBefore = picker.pickedSelectors.count;
        [picker tableView:picker.tableView didSelectRowAtIndexPath:[NSIndexPath indexPathForRow:header inSection:0]];
        check(picker.pickedSelectors.count == chosenBefore, @"group header never becomes an action selection");
        picker.actionSearchController.searchBar.text = @"分组1";
        [picker updateSearchResultsForSearchController:picker.actionSearchController];
        for (NSUInteger row = 0; row < picker.customDisplayRows.count; row++) {
            NSIndexPath *path = [NSIndexPath indexPathForRow:row inSection:0];
            check([picker tableView:picker.tableView cellForRowAtIndexPath:path] != nil, @"picker search renders each row");
        }
        [picker tableView:picker.tableView didSelectRowAtIndexPath:[NSIndexPath indexPathForRow:0 inSection:0]];
        check(picker.pickedSelectors.count == 1, @"picker search keeps multi-select checkmarks");
        NSArray *pending = [picker orderedPickedSelectors];
        check(pending.count == 1 && DXIsLinkActionSelector(pending[0]), @"batch picker reports action selectors, never group headers");
        picker.actionTypeFilter = @"text";
        [picker actionFilterDidChange];
        check(picker.pickedSelectors.count == 0, @"picker filter changes clear checks");
        for (NSDictionary *row in picker.customDisplayRows) if ([row[@"kind"] isEqual:@"action"])
            check([DXActionDisplayType(picker.linkActions[[row[@"index"] unsignedIntegerValue]]) isEqual:@"text"], @"picker uses the same type filter");

        picker.actionSearchController.searchBar.text = @"";
        [picker updateSearchResultsForSearchController:picker.actionSearchController];
        check(picker.customDisplayRows.count >= 100, @"type filtering spans all groups when search is cleared");
        __block NSString *picked = nil;
        picker.allowsMultipleSelection = NO;
        picker.completion = ^(NSString *value) { picked = value; };
        [picker tableView:picker.tableView didSelectRowAtIndexPath:[NSIndexPath indexPathForRow:0 inSection:0]];
        check(picked.length && [picked isEqual:picker.linkActions[[picker.customDisplayRows[0][@"index"] unsignedIntegerValue]][@"selector"]],
              @"single selection resolves the filtered action and returns it");

        // Search deletes by captured selector, even after preference reorder.
        [page reloadPreferences];
        page.actionQuery = @"com.example.app0";
        [page actionFilterDidChange];
        [page toggleEditing:nil];
        [page selectAllVisible];
        NSSet *deleting = [page.batchSelectors copy];
        [page deleteSelected];
        UIAlertController *delete = page.presentedViewController;
        delete.actions.firstObject.handler(delete.actions.firstObject);
        for (NSDictionary *entry in storage.preferences[kLinkActionskey])
            check(![deleting containsObject:entry[@"selector"]], @"confirmed delete removes only captured selectors");
        check([storage.preferences[kCustomActionskey] count] == 0, @"deletion cleans gesture references");
        check(![storage.preferences[kSubActionskey][0][@"selectors"] containsObject:selector(0)], @"deletion cleans sub-action references");

        DXPAppInfo *app = [DXPAppInfo new]; app.bundleID = @"com.example.batch"; app.name = @"Batch";
        [page addOpenAppActionsForApps:@[app] group:@"分组2"];
        NSDictionary *batch = [storage.preferences[kLinkActionskey] lastObject];
        check([batch[@"group"] isEqual:@"分组2"], @"batch application add applies chosen group");
        NSUInteger afterBatch = [storage.preferences[kLinkActionskey] count];
        [page addOpenAppActionsForApps:@[app] group:@"分组2"];
        check([storage.preferences[kLinkActionskey] count] == afterBatch, @"batch application add skips existing apps");
        printf("PASS: %lu custom-action organization/controller checks\n", (unsigned long)checks);
    }
    return 0;
}
