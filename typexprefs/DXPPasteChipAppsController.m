#import "DXPPasteChipAppsController.h"
#import "DXPAppInfo.h"
#import "../common.h"

static NSBundle *tweakBundle;
static NSString *const DXPPasteChipAppCellIdentifier = @"DXPPasteChipAppCell";

// Switch carrying the row's bundle identifier: the change handler resolves
// the app by identity, never by recycled index math across sections.
@interface DXPAppToggle : UISwitch
@property (nonatomic, copy) NSString *bundleID;
@end
@implementation DXPAppToggle
@end

// Same shape as DXPOpenAppPickerController, adapted to a multi-select
// allowlist: one background enumeration behind a loading spinner, web clips /
// hidden / launch-prohibited entries dropped, User and System sections, and
// the search bar promoted to the navigation item. The nav-bar "enabled only"
// toggle and the switch-per-row persistence contract are unchanged. Because
// the filtered enumeration can no longer see an app whose allowlist entry is
// still on (uninstalled, or hidden since), such entries keep placeholder rows
// in a pinned section — otherwise they would silently stay active and
// unreachable.
@interface DXPPasteChipAppsController () <UITableViewDelegate, UITableViewDataSource, UISearchResultsUpdating>
@property (nonatomic, strong) UITableView *tableView;
@property (nonatomic, strong) UISearchController *searchController;
@property (nonatomic, strong) NSArray<DXPAppInfo *> *userApps;
@property (nonatomic, strong) NSArray<DXPAppInfo *> *systemApps;
@property (nonatomic, strong) NSArray<DXPAppInfo *> *orphanApps;
@property (nonatomic, strong) NSArray<DXPAppInfo *> *searchResults;
// bundleID -> @YES; absence means off.
@property (nonatomic, strong) NSMutableDictionary<NSString *, NSNumber *> *enabled;
@property (nonatomic, assign) BOOL showEnabledOnly;
@property (nonatomic, assign) BOOL isSearching;
@property (nonatomic, assign) BOOL isLoading;
@property (nonatomic, assign) NSUInteger loadGeneration;
@end

@implementation DXPPasteChipAppsController

#pragma mark - Lifecycle

- (void)viewDidLoad {
    tweakBundle = [NSBundle bundleWithPath:bundlePath];
    [tweakBundle load];
    [super viewDidLoad];

    self.title = LOCALIZED(@"PASTE_CHIP_APPS");
    self.enabled = [self loadEnabledMap];
    self.showEnabledOnly = NO;
    self.userApps = @[];
    self.systemApps = @[];
    self.orphanApps = @[];
    self.searchResults = @[];

    self.tableView = [[UITableView alloc] initWithFrame:self.view.bounds style:UITableViewStyleInsetGrouped];
    self.tableView.delegate = self;
    self.tableView.dataSource = self;
    self.tableView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    self.tableView.keyboardDismissMode = UIScrollViewKeyboardDismissModeInteractive;
    [self.tableView registerClass:[UITableViewCell class] forCellReuseIdentifier:DXPPasteChipAppCellIdentifier];
    self.view = self.tableView;

    [self setupSearchController];
    [self updateFilterButton];
    [self startLoadingInstalledApps];
}

#pragma mark - Data loading

// One background enumeration per push; the generation counter discards a
// stale completion if the controller leaves before its first load finishes.
- (void)startLoadingInstalledApps {
    NSUInteger generation = ++self.loadGeneration;
    self.isLoading = YES;
    [self showLoadingIndicator];

    __weak typeof(self) weakSelf = self;
    [DXPAppInfo installedAppsWithCompletion:^(NSArray<DXPAppInfo *> *apps) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf || generation != strongSelf.loadGeneration) return;

        [strongSelf applyLoadedApps:apps];
        NSLog(@"[TypeX] pastechip: app list loaded (%lu user, %lu system, %lu enabled-not-listed)",
              (unsigned long)strongSelf.userApps.count,
              (unsigned long)strongSelf.systemApps.count,
              (unsigned long)strongSelf.orphanApps.count);
        strongSelf.isLoading = NO;
        strongSelf.tableView.backgroundView = nil;
        [strongSelf.tableView reloadData];
    }];
}

- (void)showLoadingIndicator {
    UIView *loadingView = [[UIView alloc] initWithFrame:CGRectZero];
    UIActivityIndicatorView *indicator = [[UIActivityIndicatorView alloc]
        initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleMedium];
    indicator.translatesAutoresizingMaskIntoConstraints = NO;
    indicator.color = [UIColor secondaryLabelColor];
    [indicator startAnimating];
    [loadingView addSubview:indicator];
    [NSLayoutConstraint activateConstraints:@[
        [indicator.centerXAnchor constraintEqualToAnchor:loadingView.centerXAnchor],
        [indicator.centerYAnchor constraintEqualToAnchor:loadingView.centerYAnchor],
    ]];
    self.tableView.backgroundView = loadingView;
}

- (void)applyLoadedApps:(NSArray<DXPAppInfo *> *)apps {
    NSMutableArray<DXPAppInfo *> *user = [NSMutableArray array];
    NSMutableArray<DXPAppInfo *> *system = [NSMutableArray array];
    NSMutableSet<NSString *> *listed = [NSMutableSet set];
    for (DXPAppInfo *app in apps) {
        [listed addObject:app.bundleID];
        [(app.isUserApp ? user : system) addObject:app];
    }

    NSMutableArray<DXPAppInfo *> *orphans = [NSMutableArray array];
    for (NSString *bundleID in self.enabled) {
        if ([listed containsObject:bundleID]) continue;
        DXPAppInfo *app = [[DXPAppInfo alloc] init];
        app.bundleID = bundleID;
        app.name = bundleID;
        [orphans addObject:app];
    }
    [orphans sortUsingComparator:^NSComparisonResult(DXPAppInfo *left, DXPAppInfo *right) {
        return [left.name localizedStandardCompare:right.name];
    }];

    self.userApps = user;
    self.systemApps = system;
    self.orphanApps = orphans;
}

#pragma mark - Search

- (void)setupSearchController {
    self.searchController = [[UISearchController alloc] initWithSearchResultsController:nil];
    self.searchController.searchResultsUpdater = self;
    self.searchController.obscuresBackgroundDuringPresentation = NO;
    self.searchController.searchBar.placeholder = LOCALIZED(@"PASTE_CHIP_APPS_SEARCH");
    self.searchController.searchBar.autocorrectionType = UITextAutocorrectionTypeNo;

    self.navigationItem.searchController = self.searchController;
    self.navigationItem.hidesSearchBarWhenScrolling = NO;
    self.definesPresentationContext = YES;
}

// Search spans all three pools — an orphaned entry is exactly the kind of app
// one searches for in order to switch it back off.
- (void)updateSearchResultsForSearchController:(UISearchController *)controller {
    NSString *query = [controller.searchBar.text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
    self.isSearching = query.length > 0;

    if (self.isSearching) {
        NSMutableArray<DXPAppInfo *> *results = [NSMutableArray array];
        NSArray<DXPAppInfo *> *pool = [self.orphanApps arrayByAddingObjectsFromArray:self.userApps];
        pool = [pool arrayByAddingObjectsFromArray:self.systemApps];
        for (DXPAppInfo *app in pool) {
            if (self.showEnabledOnly && self.enabled[app.bundleID] == nil) continue;
            if ([app.name localizedCaseInsensitiveContainsString:query] ||
                [app.bundleID localizedCaseInsensitiveContainsString:query]) {
                [results addObject:app];
            }
        }
        self.searchResults = results;
    } else {
        self.searchResults = @[];
    }

    [self.tableView reloadData];
}

#pragma mark - Filter button

// The nav button toggles between the full list and only the enabled apps --
// with hundreds of installed apps the switches would otherwise be hard to
// find again.
- (void)updateFilterButton {
    NSString *title = self.showEnabledOnly
        ? LOCALIZED(@"PASTE_CHIP_APPS_SHOW_ALL")
        : LOCALIZED(@"PASTE_CHIP_APPS_SHOW_ENABLED");
    UIBarButtonItem *button = [[UIBarButtonItem alloc] initWithTitle:title
                                                              style:UIBarButtonItemStylePlain
                                                             target:self
                                                             action:@selector(toggleFilter)];
    self.navigationItem.rightBarButtonItem = button;
}

- (void)toggleFilter {
    self.showEnabledOnly = !self.showEnabledOnly;
    [self updateFilterButton];
    // Route through the search updater so an active search re-filters too;
    // with no query it degenerates to a plain reload.
    [self updateSearchResultsForSearchController:self.searchController];
}

#pragma mark - Storage

- (NSMutableDictionary<NSString *, NSNumber *> *)loadEnabledMap {
    id value = [[DXPrefsManager sharedInstance] getValueForKey:kPasteImageChipAppsKey];
    if (![value isKindOfClass:[NSDictionary class]]) return [NSMutableDictionary dictionary];
    NSMutableDictionary *map = [NSMutableDictionary dictionary];
    for (NSString *bundleID in value) {
        if (![bundleID isKindOfClass:[NSString class]]) continue;
        NSNumber *flag = value[bundleID];
        if ([flag isKindOfClass:[NSNumber class]] && flag.boolValue) map[bundleID] = @YES;
    }
    return map;
}

- (void)persistEnabledMap {
    // writePrefs replaces the whole domain in Settings; pass a plain
    // dictionary holding only this feature's allowlist.
    [[DXPrefsManager sharedInstance] setValue:[self.enabled copy] forKey:kPasteImageChipAppsKey];
}

#pragma mark - Table view data source

// Non-search sections: pinned orphans (when present), then User, then System.
- (BOOL)hasOrphanSection {
    return self.orphanApps.count > 0;
}

- (NSArray<DXPAppInfo *> *)userPoolForDisplay {
    if (!self.showEnabledOnly) return self.userApps;
    return [self.userApps filteredArrayUsingPredicate:[NSPredicate predicateWithBlock:^BOOL(DXPAppInfo *app, NSDictionary *bindings) {
        (void)bindings;
        return self.enabled[app.bundleID] != nil;
    }]];
}

- (NSArray<DXPAppInfo *> *)systemPoolForDisplay {
    if (!self.showEnabledOnly) return self.systemApps;
    return [self.systemApps filteredArrayUsingPredicate:[NSPredicate predicateWithBlock:^BOOL(DXPAppInfo *app, NSDictionary *bindings) {
        (void)bindings;
        return self.enabled[app.bundleID] != nil;
    }]];
}

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    (void)tableView;
    if (self.isLoading) return 0;
    if (self.isSearching) return 1;
    return 2 + (self.hasOrphanSection ? 1 : 0);
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    if (self.isSearching) {
        return self.searchResults.count;
    }
    NSInteger offset = 0;
    if (self.hasOrphanSection) {
        if (section == 0) return self.orphanApps.count;
        offset = 1;
    }
    return (section - offset == 0) ? self.userPoolForDisplay.count : self.systemPoolForDisplay.count;
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    (void)tableView;
    if (self.isSearching) return nil;
    if (self.hasOrphanSection && section == 0) return LOCALIZED(@"ENABLED_NOT_LISTED_SECTION");
    NSInteger offset = self.hasOrphanSection ? 1 : 0;
    return (section - offset == 0) ? LOCALIZED(@"USER_APPS_SECTION") : LOCALIZED(@"SYSTEM_APPS_SECTION");
}

// The enabled-count footer rides the last visible section only.
- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section {
    (void)tableView;
    return (section == [self numberOfSectionsInTableView:tableView] - 1)
        ? [NSString stringWithFormat:LOCALIZED(@"PASTE_CHIP_APPS_FOOTER"), (long)self.enabled.count]
        : nil;
}

- (CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath {
    (void)tableView;
    (void)indexPath;
    return 52.0;
}

- (DXPAppInfo *)appAtIndexPath:(NSIndexPath *)indexPath {
    if (self.isSearching) {
        return (indexPath.row < (NSInteger)self.searchResults.count) ? self.searchResults[indexPath.row] : nil;
    }
    NSInteger section = indexPath.section;
    if (self.hasOrphanSection) {
        if (section == 0) {
            return (indexPath.row < (NSInteger)self.orphanApps.count) ? self.orphanApps[indexPath.row] : nil;
        }
        section -= 1;
    }
    NSArray<DXPAppInfo *> *pool = (section == 0) ? self.userPoolForDisplay : self.systemPoolForDisplay;
    return (indexPath.row < (NSInteger)pool.count) ? pool[indexPath.row] : nil;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    // The registered cell class means dequeue never returns nil; the fixed
    // row content is therefore applied on every pass, not at creation.
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:DXPPasteChipAppCellIdentifier forIndexPath:indexPath];

    DXPAppInfo *app = [self appAtIndexPath:indexPath];
    cell.imageView.layer.cornerRadius = 8.0;
    cell.imageView.layer.masksToBounds = YES;
    cell.imageView.contentMode = UIViewContentModeScaleAspectFill;
    cell.detailTextLabel.textColor = [UIColor secondaryLabelColor];
    cell.detailTextLabel.font = [UIFont systemFontOfSize:11.0];

    cell.textLabel.text = app.name;
    cell.detailTextLabel.text = app.bundleID;
    cell.imageView.image = app ? [DXPAppInfo iconForBundleID:app.bundleID] : nil;

    // Fresh switch per bind, carrying the bundle ID: a recycled one would
    // fire for the recycled row mapping.
    DXPAppToggle *toggle = [[DXPAppToggle alloc] init];
    toggle.on = (app && self.enabled[app.bundleID] != nil);
    toggle.onTintColor = [UIColor systemGreenColor];
    toggle.bundleID = app.bundleID;
    [toggle addTarget:self action:@selector(appSwitchChanged:) forControlEvents:UIControlEventValueChanged];
    cell.accessoryView = toggle;
    cell.selectionStyle = UITableViewCellSelectionStyleNone;
    return cell;
}

#pragma mark - Switch

- (void)appSwitchChanged:(DXPAppToggle *)sender {
    if (sender.bundleID.length == 0) return;

    if (sender.on) self.enabled[sender.bundleID] = @YES;
    else [self.enabled removeObjectForKey:sender.bundleID];
    [self persistEnabledMap];

    // Keep the enabled-count footer current without a full reload.
    UITableViewHeaderFooterView *footer = [self.tableView footerViewForSection:[self numberOfSectionsInTableView:self.tableView] - 1];
    footer.textLabel.text = [NSString stringWithFormat:LOCALIZED(@"PASTE_CHIP_APPS_FOOTER"), (long)self.enabled.count];
}

@end
