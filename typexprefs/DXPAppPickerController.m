#import "DXPAppPickerController.h"
#import "DXPAppInfo.h"
#import "../common.h"

static NSBundle *tweakBundle;

// Subtitle style: app name on top, bundle identifier underneath.
@interface DXPAppPickerCell : UITableViewCell
@end

@implementation DXPAppPickerCell
- (instancetype)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)reuseIdentifier {
    return [super initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:reuseIdentifier];
}
@end

@interface DXPAppPickerController ()
@property (nonatomic, strong) UITableView *tableView;
@property (nonatomic, strong) UISearchController *searchController;
@property (nonatomic, copy) NSString *searchText;
@property (nonatomic, strong) NSArray<DXPAppInfo *> *apps;
@end

@implementation DXPAppPickerController

#pragma mark - Data

- (void)loadApps {
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        NSArray<DXPAppInfo *> *apps = [DXPAppInfo installedApps];
        dispatch_async(dispatch_get_main_queue(), ^{
            self.apps = apps;
            [self.tableView reloadData];
        });
    });
}

- (NSArray<DXPAppInfo *> *)filteredApps {
    NSString *query = [self.searchText stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if (query.length == 0) return self.apps;
    NSMutableArray<DXPAppInfo *> *result = [NSMutableArray array];
    for (DXPAppInfo *app in self.apps) {
        if ([app.name localizedCaseInsensitiveContainsString:query] ||
            [app.bundleID localizedCaseInsensitiveContainsString:query]) {
            [result addObject:app];
        }
    }
    return result;
}

- (NSArray<DXPAppInfo *> *)selectedApps {
    NSString *link = self.currentLink;
    NSMutableArray<DXPAppInfo *> *result = [NSMutableArray array];
    for (DXPAppInfo *app in [self filteredApps]) {
        if (link.length && [app.bundleID isEqualToString:link]) [result addObject:app];
    }
    return result;
}

- (NSArray<DXPAppInfo *> *)unselectedApps {
    NSString *link = self.currentLink;
    NSMutableArray<DXPAppInfo *> *result = [NSMutableArray array];
    for (DXPAppInfo *app in [self filteredApps]) {
        if (link.length && [app.bundleID isEqualToString:link]) continue;
        [result addObject:app];
    }
    return result;
}

- (BOOL)hasSelectedSection {
    return [self selectedApps].count > 0;
}

- (NSArray<DXPAppInfo *> *)appsForSection:(NSInteger)section {
    if (section == 0 && [self hasSelectedSection]) return [self selectedApps];
    return [self unselectedApps];
}

#pragma mark - Table view

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    return [self hasSelectedSection] ? 2 : 1;
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    return (section == 0 && [self hasSelectedSection]) ? LOCALIZED(@"SELECTED") : LOCALIZED(@"UNSELECTED");
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return [self appsForSection:section].count;
}

- (CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath {
    return 60;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    DXPAppPickerCell *cell = [tableView dequeueReusableCellWithIdentifier:@"DXPAppPickerCell" forIndexPath:indexPath];
    DXPAppInfo *app = [self appsForSection:indexPath.section][indexPath.row];
    cell.textLabel.text = app.name;
    cell.detailTextLabel.text = app.bundleID;
    cell.detailTextLabel.textColor = [UIColor secondaryLabelColor];
    cell.detailTextLabel.lineBreakMode = NSLineBreakByTruncatingMiddle;
    cell.imageView.image = [DXPAppInfo iconForBundleID:app.bundleID];
    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    DXPAppInfo *app = [self appsForSection:indexPath.section][indexPath.row];
    if (!app) return;
    if (self.completion) self.completion(app.name, app.bundleID);
    [self.navigationController popViewControllerAnimated:YES];
}

#pragma mark - Search

- (void)updateSearchResultsForSearchController:(UISearchController *)searchController {
    self.searchText = searchController.searchBar.text;
    [self.tableView reloadData];
}

#pragma mark - Lifecycle

- (void)viewDidLoad {
    tweakBundle = [NSBundle bundleWithPath:bundlePath];
    [tweakBundle load];
    [super viewDidLoad];

    self.title = LOCALIZED(@"SELECT_APP");

    self.tableView = [[UITableView alloc] initWithFrame:self.view.bounds style:UITableViewStyleInsetGrouped];
    self.tableView.delegate = self;
    self.tableView.dataSource = self;
    self.tableView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    [self.tableView registerClass:[DXPAppPickerCell class] forCellReuseIdentifier:@"DXPAppPickerCell"];
    self.view = self.tableView;

    self.searchController = [[UISearchController alloc] initWithSearchResultsController:nil];
    self.searchController.searchResultsUpdater = self;
    self.searchController.obscuresBackgroundDuringPresentation = NO;
    self.searchController.definesPresentationContext = YES;
    self.searchController.searchBar.placeholder = LOCALIZED(@"SEARCH_PLACEHOLDER");
    self.navigationItem.searchController = self.searchController;
    self.navigationItem.hidesSearchBarWhenScrolling = NO;

    [self loadApps];
}

@end
