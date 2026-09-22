#import "DXPOpenAppPickerController.h"
#import "DXPAppInfo.h"
#import "../common.h"

static NSBundle *tweakBundle;
static NSString *const DXOpenAppCellIdentifier = @"DXOpenAppCell";

typedef NS_ENUM(NSInteger, DXOpenAppSection) {
    DXOpenAppSectionCurrent = 0,
    DXOpenAppSectionUser    = 1,
    DXOpenAppSectionSystem  = 2,
    DXOpenAppSectionCount   = 3,
};

// Rewritten after PullOver-X QSFavoritesPickerController: enumeration runs
// off the main thread behind a loading spinner, web clips / hidden /
// launch-prohibited entries are dropped, the rest splits into User and System
// sections, and search moves into a navigation-item search controller. The
// configured app keeps a pinned top section so the checkmark anchor never
// disappears. The selection contract is unchanged: one DXPAppInfo reported
// to the editor, which owns persistence.
@interface DXPOpenAppPickerController () <UITableViewDelegate, UITableViewDataSource, UISearchResultsUpdating>
@property (nonatomic, strong) UITableView *tableView;
@property (nonatomic, strong) UISearchController *searchController;
@property (nonatomic, strong) NSArray<DXPAppInfo *> *userApps;
@property (nonatomic, strong) NSArray<DXPAppInfo *> *systemApps;
@property (nonatomic, strong) DXPAppInfo *currentApp;
@property (nonatomic, strong) NSArray<DXPAppInfo *> *searchResults;
@property (nonatomic, assign) BOOL isSearching;
@property (nonatomic, assign) BOOL isLoading;
@property (nonatomic, assign) NSUInteger loadGeneration;
@end

@implementation DXPOpenAppPickerController

#pragma mark - Lifecycle

- (void)viewDidLoad {
    tweakBundle = [NSBundle bundleWithPath:bundlePath];
    [tweakBundle load];
    [super viewDidLoad];

    self.title = LOCALIZED(@"SELECT_APP");
    self.userApps = @[];
    self.systemApps = @[];
    self.searchResults = @[];

    self.tableView = [[UITableView alloc] initWithFrame:self.view.bounds style:UITableViewStyleInsetGrouped];
    self.tableView.delegate = self;
    self.tableView.dataSource = self;
    self.tableView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    self.tableView.keyboardDismissMode = UIScrollViewKeyboardDismissModeInteractive;
    [self.tableView registerClass:[UITableViewCell class] forCellReuseIdentifier:DXOpenAppCellIdentifier];
    self.view = self.tableView;

    [self setupSearchController];
    [self startLoadingInstalledApps];
}

#pragma mark - Data loading

// One background enumeration per push; the generation counter discards a
// stale completion if the controller outlives its first load. Re-enumerating
// here (as the old viewWillAppear did) duplicated the full pass a second
// time on every entry into the page.
- (void)startLoadingInstalledApps {
    NSUInteger generation = ++self.loadGeneration;
    self.isLoading = YES;
    [self showLoadingIndicator];

    __weak typeof(self) weakSelf = self;
    [DXPAppInfo installedAppsWithCompletion:^(NSArray<DXPAppInfo *> *apps) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf || generation != strongSelf.loadGeneration) return;

        [strongSelf applyLoadedApps:apps];
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

// The configured app gets a dedicated pinned section even when the filters
// dropped it or it was uninstalled since — a placeholder carrying the raw
// bundle ID keeps the current value visible and re-selectable.
- (void)applyLoadedApps:(NSArray<DXPAppInfo *> *)apps {
    NSMutableArray<DXPAppInfo *> *user = [NSMutableArray array];
    NSMutableArray<DXPAppInfo *> *system = [NSMutableArray array];
    DXPAppInfo *current = nil;
    for (DXPAppInfo *app in apps) {
        if ([app.bundleID isEqualToString:self.selectedBundleIdentifier]) {
            current = app;
            continue;
        }
        [(app.isUserApp ? user : system) addObject:app];
    }
    if (!current && self.selectedBundleIdentifier.length > 0) {
        current = [[DXPAppInfo alloc] init];
        current.bundleID = self.selectedBundleIdentifier;
        current.name = self.selectedBundleIdentifier;
    }

    self.currentApp = current;
    self.userApps = user;
    self.systemApps = system;
}

#pragma mark - Search

- (void)setupSearchController {
    self.searchController = [[UISearchController alloc] initWithSearchResultsController:nil];
    self.searchController.searchResultsUpdater = self;
    self.searchController.obscuresBackgroundDuringPresentation = NO;
    self.searchController.searchBar.placeholder = LOCALIZED(@"SEARCH_PLACEHOLDER");

    self.navigationItem.searchController = self.searchController;
    self.navigationItem.hidesSearchBarWhenScrolling = NO;
    self.definesPresentationContext = YES;
}

// The pinned Current section already shows the selection, so search matches
// against the User/System pools only — the PullOver-X list excludes its
// selected section the same way.
- (void)updateSearchResultsForSearchController:(UISearchController *)controller {
    NSString *query = [controller.searchBar.text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
    self.isSearching = query.length > 0;

    if (self.isSearching) {
        NSMutableArray<DXPAppInfo *> *results = [NSMutableArray array];
        for (DXPAppInfo *app in [self.userApps arrayByAddingObjectsFromArray:self.systemApps]) {
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

#pragma mark - Table view data source

- (DXPAppInfo *)appAtIndexPath:(NSIndexPath *)indexPath {
    if (indexPath.section == DXOpenAppSectionCurrent) return self.currentApp;
    if (indexPath.section == DXOpenAppSectionUser) {
        NSArray<DXPAppInfo *> *pool = self.isSearching ? self.searchResults : self.userApps;
        return (indexPath.row < (NSInteger)pool.count) ? pool[indexPath.row] : nil;
    }
    if (indexPath.section == DXOpenAppSectionSystem) {
        return (indexPath.row < (NSInteger)self.systemApps.count) ? self.systemApps[indexPath.row] : nil;
    }
    return nil;
}

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    if (self.isLoading) return 0;
    return self.isSearching ? 2 : DXOpenAppSectionCount;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    switch (section) {
        case DXOpenAppSectionCurrent:
            return self.currentApp ? 1 : 0;
        case DXOpenAppSectionUser:
            return self.isSearching ? self.searchResults.count : self.userApps.count;
        case DXOpenAppSectionSystem:
            return self.isSearching ? 0 : self.systemApps.count;
        default:
            return 0;
    }
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    if (self.isLoading) return nil;
    switch (section) {
        case DXOpenAppSectionCurrent:
            return self.currentApp ? LOCALIZED(@"SELECTED_APP_SECTION") : nil;
        case DXOpenAppSectionUser:
            return self.isSearching ? nil : LOCALIZED(@"USER_APPS_SECTION");
        case DXOpenAppSectionSystem:
            return self.isSearching ? nil : LOCALIZED(@"SYSTEM_APPS_SECTION");
        default:
            return nil;
    }
}

- (CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath {
    (void)tableView;
    (void)indexPath;
    return 52.0;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    // The registered cell class means dequeue never returns nil; the fixed
    // row content is therefore applied on every pass, not at creation.
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:DXOpenAppCellIdentifier forIndexPath:indexPath];

    DXPAppInfo *app = [self appAtIndexPath:indexPath];
    cell.imageView.layer.cornerRadius = 8.0;
    cell.imageView.layer.masksToBounds = YES;
    cell.imageView.contentMode = UIViewContentModeScaleAspectFill;
    cell.detailTextLabel.textColor = UIColor.secondaryLabelColor;
    cell.detailTextLabel.font = [UIFont systemFontOfSize:11.0];

    cell.textLabel.text = app.name;
    cell.detailTextLabel.text = app.bundleID;
    cell.imageView.image = app ? [DXPAppInfo iconForBundleID:app.bundleID] : nil;
    cell.accessoryType = [app.bundleID isEqualToString:self.selectedBundleIdentifier]
        ? UITableViewCellAccessoryCheckmark : UITableViewCellAccessoryNone;
    return cell;
}

#pragma mark - Selection

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    DXPAppInfo *app = [self appAtIndexPath:indexPath];
    if (!app) return;

    self.selectedBundleIdentifier = app.bundleID;
    if (self.completion) self.completion(app);
    [self.navigationController popViewControllerAnimated:YES];
}

@end
