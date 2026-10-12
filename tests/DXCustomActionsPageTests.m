#import "CustomActionsPageHarness.h"

// Drives the REAL DXPCustomActionViewController/DXPCustomActionsController
// sources through the full click surface with device-like state (ungrouped
// openapp actions), so derived-section crashes reproduce here instead of on
// the phone. Rendering and row taps are exercised directly on the delegate;
// UIKit drawing is not emulated.

static NSUInteger checks;
static void check(BOOL condition, NSString *message) { checks++; NSCAssert(condition, @"%@", message); }

@interface DXPCustomActionsController (Test)
- (void)toggleEditing:(UIBarButtonItem *)sender;
- (void)startBatchAddApplicationsFlow;
- (void)assignActionSelector:(NSString *)selector toGroup:(NSString *)group;
- (void)updateSearchResultsForSearchController:(UISearchController *)controller;
@end

static NSString *selectorNamed(NSString *name) {
    return [kLinkActionSelectorPrefix stringByAppendingString:name];
}

static NSMutableArray *actions(NSArray *names) {
    NSMutableArray *result = [NSMutableArray array];
    NSUInteger index = 0;
    for (NSString *name in names) {
        NSString *selector = [kLinkActionSelectorPrefix stringByAppendingString:name];
        [result addObject:[@{@"selector": selector, @"type": kCustomActionTypeOpenApp,
                             @"link": name, @"name": name, @"icon": name,
                             kCustomActionFloatingKey: @YES} mutableCopy]];
        index++;
        (void)index;
    }
    return result;
}

// Renders every section/row through the delegate — the exact surface a tap
// walks — and returns the row count of the action area.
static void renderEverything(DXPCustomActionsController *page, UITableView *table, NSString *stage) {
    NSInteger sections = [page numberOfSectionsInTableView:table];
    NSInteger actionRows = 0;
    for (NSInteger section = 0; section < sections; section++) {
        (void)[page tableView:table titleForHeaderInSection:section];
        (void)[page tableView:table titleForFooterInSection:section];
        (void)[page tableView:table viewForHeaderInSection:section];
        (void)[page tableView:table heightForHeaderInSection:section];
        NSInteger rows = [page tableView:table numberOfRowsInSection:section];
        if (section == 0) actionRows = rows;
        for (NSInteger row = 0; row < rows; row++) {
            NSIndexPath *path = [NSIndexPath indexPathForRow:row inSection:section];
            (void)[page tableView:table heightForRowAtIndexPath:path];
            (void)[page tableView:table cellForRowAtIndexPath:path];
        }
    }
    check(actionRows >= 0, stage);
}

int main(void) {
    @autoreleasepool {
        DXPrefsManager *manager = DXPrefsManager.sharedInstance;
        UINavigationController *nav = [UINavigationController new];
        nav.viewControllers = [NSMutableArray array];
        UITableView *table = [UITableView new];

        // Device-like starting state: batch-added ungrouped openapp actions.
        manager.preferences = @{kLinkActionskey: actions(@[@"com.a.one", @"com.b.two", @"com.c.three"])};
        DXPCustomActionsController *page = [DXPCustomActionsController new];
        page.navigationController = nav;
        [page viewDidLoad];
        [page viewWillAppear:YES];

        // No groups yet: one ungrouped section plus the add section, and the
        // ungrouped bucket holds every action (the 4.6.4 NSNotFound crash
        // fired exactly here).
        check([page numberOfSectionsInTableView:table] == 2, @"ungrouped-only page has two sections");
        check([page tableView:table numberOfRowsInSection:0] == 3, @"all actions live in the ungrouped section");
        check(page.groupNames.count == 0, @"no groups registered yet");
        renderEverything(page, table, @"ungrouped page renders end to end");

        // iOS 16.x search/presentation can drive the data source with a table
        // other than self.tableView (the 4.6.6 device abort): every render
        // table must register its own cells before dequeueing.
        UITableView *foreign = [UITableView new];
        foreign.reusableCell = [UITableViewCell new];
        UITableViewCell *foreignCell = [page tableView:foreign cellForRowAtIndexPath:[NSIndexPath indexPathForRow:0 inSection:0]];
        check(foreignCell != nil, @"a foreign render table registers and builds its own cells");

        // Tap an action row -> editor pushes; saving exercises the 4.6.4
        // editor-save hook path (was reloadRows with a global row index).
        [page tableView:table didSelectRowAtIndexPath:[NSIndexPath indexPathForRow:1 inSection:0]];
        check(nav.viewControllers.count == 1, @"tapping a row pushes exactly one editor");
        DXPLinkActionEditorController *editor = nav.viewControllers.lastObject;
        NSMutableDictionary *saved = [editor.entry mutableCopy];
        saved[@"name"] = @"Renamed";
        editor.completion(saved);
        check([page.linkActions[1][@"name"] isEqual:@"Renamed"], @"editor save updates the store");
        check(page.tableView.reloadAllCount >= 1, @"editor save reloads through the section model");
        nav.viewControllers = [NSMutableArray array];

        // Add flow: pending entry then editor save (insertRows crash path).
        [page startAddFlowForType:kCustomActionTypeOpenApp];
        DXPLinkActionEditorController *addEditor = nav.viewControllers.lastObject;
        check(((NSString *)addEditor.entry[@"selector"]).length > 0, @"add flow creates a pending entry");
        addEditor.completion([@{@"selector": addEditor.entry[@"selector"], @"type": kCustomActionTypeOpenApp,
                                @"link": @"com.d.four", @"name": @"Four"} mutableCopy]);
        check(page.linkActions.count == 4, @"saved add lands in the store");
        nav.viewControllers = [NSMutableArray array];

        // Batch add through the app picker: 全部未分组 state stays intact.
        [page startBatchAddApplicationsFlow];
        DXPOpenAppPickerController *picker = nav.viewControllers.lastObject;
        check(picker.allowsMultipleSelection, @"batch entry opens the picker in multi-select mode");
        DXPAppInfo *app = [DXPAppInfo new]; app.bundleID = @"com.e.five"; app.name = @"Five";
        picker.multiSelectionCompletion(@[app]);
        check(page.linkActions.count == 5, @"batch pick appends one openapp action");
        nav.viewControllers = [NSMutableArray array];

        renderEverything(page, table, @"five ungrouped actions render end to end");

        // Grouping: assign two actions, then walk every row again — the
        // buckets and the delegate must agree.
        [page assignActionSelector:selectorNamed(@"com.a.one") toGroup:@"工作"];
        [page assignActionSelector:selectorNamed(@"com.b.two") toGroup:@"工作"];
        check(page.groupNames.count == 1, @"assigning creates the group registry entry");
        check([page numberOfSectionsInTableView:table] == 3, @"group + ungrouped + add sections");
        check([page tableView:table numberOfRowsInSection:0] == 2, @"group section holds its members");
        renderEverything(page, table, @"grouped page renders end to end");

        // Long-press menu path: move to group then remove from group.
        [page assignActionSelector:selectorNamed(@"com.a.one") toGroup:@""];
        check([page tableView:table numberOfRowsInSection:0] == 1, @"removing from group falls back to 未分组");

        // Rename via the header alert: invoke the OK action with a text field.
        [page groupHeaderTapped:nil];
        UIAlertController *headerMenu = page.presentedViewController;
        check(headerMenu.actions.count == 3, @"group header offers rename/delete/cancel");
        headerMenu.actions[0].handler(headerMenu.actions[0]);
        UIAlertController *renameAlert = page.presentedViewController == headerMenu ? nil : page.presentedViewController;
        check(renameAlert != nil, @"rename opens a text alert");
        renameAlert.textFields.firstObject.text = @"深度工作";
        renameAlert.actions.firstObject.handler(renameAlert.actions.firstObject);
        check([page.groupNames.firstObject isEqual:@"深度工作"], @"rename rewrites the registry");
        check([page.linkActions[1][kCustomActionGroupKey] isEqual:@"深度工作"], @"rename follows the entries");

        // Delete group: members fall back to 未分组, actions survive.
        [page groupHeaderTapped:nil];
        headerMenu = page.presentedViewController;
        headerMenu.actions[1].handler(headerMenu.actions[1]);
        UIAlertController *deleteAlert = page.presentedViewController == headerMenu ? nil : page.presentedViewController;
        deleteAlert.actions.firstObject.handler(deleteAlert.actions.firstObject);
        check(page.groupNames.count == 0 && page.linkActions.count == 5, @"deleting the group keeps every action");

        // Search: filter, tap a result, then clear.
        UISearchController *search = [[UISearchController alloc] initWithSearchResultsController:nil];
        search.searchBar.text = @"two";
        [page updateSearchResultsForSearchController:search];
        check([page numberOfSectionsInTableView:table] == 1, @"searching collapses to one result section");
        check([page tableView:table numberOfRowsInSection:0] == 1, @"search matches by name");
        [page tableView:table didSelectRowAtIndexPath:[NSIndexPath indexPathForRow:0 inSection:0]];
        check(nav.viewControllers.count == 1, @"tapping a result opens its editor");
        nav.viewControllers = [NSMutableArray array];
        search.searchBar.text = @"";
        [page updateSearchResultsForSearchController:search];
        check([page numberOfSectionsInTableView:table] == 2, @"clearing search restores the grouped sections");

        // Edit-mode tap-to-delete: dead on device until
        // allowsSelectionDuringEditing was set. During a search the tap must
        // fall through to the editor instead of deleting a filtered row.
        // The harness drives the delegate with its own table, so the editing
        // flag goes there (on device the EDIT button flags the page's table).
        [table setEditing:YES animated:NO];
        NSUInteger countBeforeTap = page.linkActions.count;
        [page tableView:table didSelectRowAtIndexPath:[NSIndexPath indexPathForRow:0 inSection:0]];
        check(page.linkActions.count == countBeforeTap - 1, @"tapping a row in edit mode deletes it");
        search.searchBar.text = @"two";
        [page updateSearchResultsForSearchController:search];
        [page tableView:table didSelectRowAtIndexPath:[NSIndexPath indexPathForRow:0 inSection:0]];
        check(page.linkActions.count == countBeforeTap - 1, @"searching blocks the edit-tap delete");
        check(nav.viewControllers.count == 1, @"searching edit-tap opens the editor instead");
        nav.viewControllers = [NSMutableArray array];
        search.searchBar.text = @"";
        [page updateSearchResultsForSearchController:search];

        // Edit-mode delete down to empty: the flat layout crashed right here
        // when the placeholder row appeared (DXPCustomActionsController :227).
        [page toggleEditing:nil];
        while (page.linkActions.count > 0)
            [page tableView:table commitEditingStyle:UITableViewCellEditingStyleDelete
                              forRowAtIndexPath:[NSIndexPath indexPathForRow:0 inSection:0]];
        check(page.linkActions.count == 0 && [page tableView:table numberOfRowsInSection:0] == 1,
              @"deleting the last action swaps in the placeholder without crashing");
        renderEverything(page, table, @"empty page renders end to end");

        printf("PASS: %lu custom-actions page click-surface checks\n", (unsigned long)checks);
    }
    return 0;
}
