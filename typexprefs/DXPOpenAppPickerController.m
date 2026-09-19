#import "DXPOpenAppPickerController.h"
#import "DXPAppInfo.h"
#import "../common.h"

static NSBundle *tweakBundle;
static NSString *const DXOpenAppCellIdentifier = @"DXOpenAppCell";

@interface DXPOpenAppPickerController ()
@property (nonatomic, strong) UITableView *tableView;
@property (nonatomic, strong) NSArray<DXPAppInfo *> *apps;
@property (nonatomic, copy) NSString *searchText;
@end

@implementation DXPOpenAppPickerController

- (void)viewDidLoad {
    tweakBundle = [NSBundle bundleWithPath:bundlePath];
    [tweakBundle load];
    [super viewDidLoad];

    self.title = LOCALIZED(@"SELECT_APP");
    self.apps = [DXPAppInfo installedApps];

    self.tableView = [[UITableView alloc] initWithFrame:self.view.bounds style:UITableViewStyleInsetGrouped];
    self.tableView.delegate = self;
    self.tableView.dataSource = self;
    self.tableView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;

    UISearchBar *searchBar = [[UISearchBar alloc] initWithFrame:CGRectMake(0.0, 0.0, 0.0, 44.0)];
    searchBar.delegate = self;
    searchBar.placeholder = LOCALIZED(@"SEARCH_PLACEHOLDER");
    searchBar.autocorrectionType = UITextAutocorrectionTypeNo;
    searchBar.autoresizingMask = UIViewAutoresizingFlexibleWidth;
    self.tableView.tableHeaderView = searchBar;
    self.view = self.tableView;
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    self.apps = [DXPAppInfo installedApps];
    [self.tableView reloadData];
}

- (NSArray<DXPAppInfo *> *)visibleApps {
    if (self.searchText.length == 0) return self.apps ?: @[];
    NSString *query = self.searchText;
    return [self.apps filteredArrayUsingPredicate:[NSPredicate predicateWithBlock:^BOOL(DXPAppInfo *app, NSDictionary *bindings) {
        (void)bindings;
        return [app.name localizedCaseInsensitiveContainsString:query] ||
               [app.bundleID localizedCaseInsensitiveContainsString:query];
    }]];
}

- (void)searchBar:(UISearchBar *)searchBar textDidChange:(NSString *)searchText {
    self.searchText = searchText;
    [self.tableView reloadData];
}

- (void)searchBarSearchButtonClicked:(UISearchBar *)searchBar {
    [searchBar resignFirstResponder];
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    (void)tableView;
    (void)section;
    return self.visibleApps.count;
}

- (CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath {
    (void)tableView;
    (void)indexPath;
    return 52.0;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:DXOpenAppCellIdentifier];
    if (!cell) {
        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:DXOpenAppCellIdentifier];
        cell.imageView.layer.cornerRadius = 8.0;
        cell.imageView.layer.masksToBounds = YES;
        cell.imageView.contentMode = UIViewContentModeScaleAspectFill;
        cell.detailTextLabel.textColor = UIColor.secondaryLabelColor;
        cell.detailTextLabel.font = [UIFont systemFontOfSize:11.0];
    }

    DXPAppInfo *app = self.visibleApps[indexPath.row];
    cell.imageView.image = [DXPAppInfo iconForBundleID:app.bundleID];
    cell.textLabel.text = app.name;
    cell.detailTextLabel.text = app.bundleID;
    cell.accessoryType = [app.bundleID isEqualToString:self.selectedBundleIdentifier]
        ? UITableViewCellAccessoryCheckmark : UITableViewCellAccessoryNone;
    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    DXPAppInfo *app = self.visibleApps[indexPath.row];
    self.selectedBundleIdentifier = app.bundleID;
    if (self.completion) self.completion(app);
    [self.navigationController popViewControllerAnimated:YES];
}

@end
