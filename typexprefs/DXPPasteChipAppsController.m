#import "DXPPasteChipAppsController.h"
#import "DXPAppInfo.h"
#import "../common.h"

static NSBundle *tweakBundle;

static NSString *const DXAppCellIdentifier = @"DXPPasteChipAppCell";

@implementation DXPPasteChipAppsController {
    NSArray<DXPAppInfo *> *_apps;
    // bundleID -> @YES; absence means off.
    NSMutableDictionary<NSString *, NSNumber *> *_enabled;
    BOOL _showEnabledOnly;
    NSString *_searchText;
}

#pragma mark - Lifecycle

- (void)viewDidLoad {
    tweakBundle = [NSBundle bundleWithPath:bundlePath];
    [tweakBundle load];

    [super viewDidLoad];
    self.title = LOCALIZED(@"PASTE_CHIP_APPS");

    _apps = [DXPAppInfo installedApps];
    _enabled = [self loadEnabledMap];
    _showEnabledOnly = NO;

    self.tableView = [[UITableView alloc] initWithFrame:self.view.bounds style:UITableViewStyleInsetGrouped];
    self.tableView.delegate = self;
    self.tableView.dataSource = self;
    self.tableView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;

    // 表头搜索栏（列表顶部即达）：按应用名称或 Bundle ID 过滤，与"只看已开启"
    // 叠加生效。几百个应用里找回某个开关不用再滚动翻找。
    UISearchBar *searchBar = [[UISearchBar alloc] initWithFrame:CGRectMake(0.0, 0.0, 0.0, 44.0)];
    searchBar.delegate = self;
    searchBar.placeholder = LOCALIZED(@"PASTE_CHIP_APPS_SEARCH");
    searchBar.autocorrectionType = UITextAutocorrectionTypeNo;
    searchBar.autoresizingMask = UIViewAutoresizingFlexibleWidth;
    self.tableView.tableHeaderView = searchBar;

    [self.view addSubview:self.tableView];

    [self updateFilterButton];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    // Apps may have been installed or removed since the last visit.
    _apps = [DXPAppInfo installedApps];
    [self.tableView reloadData];
}

// The nav button toggles between the full list and only the enabled apps --
// with hundreds of installed apps the switches would otherwise be hard to
// find again.
- (void)updateFilterButton {
    NSString *title = _showEnabledOnly
        ? LOCALIZED(@"PASTE_CHIP_APPS_SHOW_ALL")
        : LOCALIZED(@"PASTE_CHIP_APPS_SHOW_ENABLED");
    UIBarButtonItem *button = [[UIBarButtonItem alloc] initWithTitle:title
                                                              style:UIBarButtonItemStylePlain
                                                             target:self
                                                             action:@selector(toggleFilter)];
    self.navigationItem.rightBarButtonItem = button;
}

- (void)toggleFilter {
    _showEnabledOnly = !_showEnabledOnly;
    [self updateFilterButton];
    [self.tableView reloadData];
}

#pragma mark - Search

- (void)searchBar:(UISearchBar *)searchBar textDidChange:(NSString *)searchText {
    _searchText = searchText;
    [self.tableView reloadData];
}

- (void)searchBarSearchButtonClicked:(UISearchBar *)searchBar {
    [searchBar resignFirstResponder];
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
    [[DXPrefsManager sharedInstance] setValue:[_enabled copy] forKey:kPasteImageChipAppsKey];
}

#pragma mark - Table

- (NSArray<DXPAppInfo *> *)visibleApps {
    NSArray<DXPAppInfo *> *apps = _apps;
    if (_showEnabledOnly) {
        apps = [apps filteredArrayUsingPredicate:[NSPredicate predicateWithBlock:^BOOL(DXPAppInfo *app, NSDictionary *bindings) {
            (void)bindings;
            return _enabled[app.bundleID] != nil;
        }]];
    }
    if (_searchText.length > 0) {
        NSString *query = _searchText;
        apps = [apps filteredArrayUsingPredicate:[NSPredicate predicateWithBlock:^BOOL(DXPAppInfo *app, NSDictionary *bindings) {
            (void)bindings;
            return [app.name localizedCaseInsensitiveContainsString:query] ||
                   [app.bundleID localizedCaseInsensitiveContainsString:query];
        }]];
    }
    return apps;
}

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    return 1;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    (void)tableView;
    (void)section;
    return [self visibleApps].count;
}

- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section {
    (void)tableView;
    (void)section;
    return [NSString stringWithFormat:LOCALIZED(@"PASTE_CHIP_APPS_FOOTER"), (long)_enabled.count];
}

- (CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath {
    (void)tableView;
    (void)indexPath;
    return 52.0;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:DXAppCellIdentifier];
    if (!cell) {
        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:DXAppCellIdentifier];
        cell.imageView.layer.cornerRadius = 8.0;
        cell.imageView.layer.masksToBounds = YES;
        cell.imageView.contentMode = UIViewContentModeScaleAspectFill;
        cell.detailTextLabel.textColor = [UIColor secondaryLabelColor];
        cell.detailTextLabel.font = [UIFont systemFontOfSize:11.0];
    }

    DXPAppInfo *app = [self visibleApps][indexPath.row];
    cell.imageView.image = [DXPAppInfo iconForBundleID:app.bundleID];
    cell.textLabel.text = app.name;
    cell.detailTextLabel.text = app.bundleID;

    // Fresh switch per bind, carrying its row: a recycled one would fire for
    // the recycled row mapping.
    UISwitch *toggle = [[UISwitch alloc] init];
    toggle.on = _enabled[app.bundleID] != nil;
    toggle.onTintColor = [UIColor systemGreenColor];
    toggle.tag = indexPath.row;
    [toggle addTarget:self action:@selector(appSwitchChanged:) forControlEvents:UIControlEventValueChanged];
    cell.accessoryView = toggle;
    cell.selectionStyle = UITableViewCellSelectionStyleNone;
    return cell;
}

- (void)appSwitchChanged:(UISwitch *)sender {
    NSArray<DXPAppInfo *> *visible = [self visibleApps];
    if (sender.tag >= visible.count) return;
    DXPAppInfo *app = visible[sender.tag];

    if (sender.on) _enabled[app.bundleID] = @YES;
    else [_enabled removeObjectForKey:app.bundleID];
    [self persistEnabledMap];
}

@end
