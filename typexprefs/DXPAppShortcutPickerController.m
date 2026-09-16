#import "DXPAppShortcutPickerController.h"
#import "DXPAppInfo.h"
#import "../common.h"

static NSBundle *tweakBundle;

// Subtitle style: localized quick action title on top, its
// UIApplicationShortcutItemType (the identifier the system dispatches)
// underneath.
@interface DXPAppShortcutCell : UITableViewCell
@end

@implementation DXPAppShortcutCell
- (instancetype)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)reuseIdentifier {
    return [super initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:reuseIdentifier];
}
@end

@interface DXPAppShortcutPickerController ()
@property (nonatomic, strong) UITableView *tableView;
@property (nonatomic, strong) UISearchController *searchController;
@property (nonatomic, copy) NSString *searchText;
@property (nonatomic, strong) NSArray<NSDictionary *> *groups;
@property (nonatomic, strong) NSArray<NSString *> *refreshBundleIdentifiers;
@property (nonatomic, assign) BOOL didRequestShortcutRefresh;
- (void)loadGroups;
- (void)requestSpringBoardShortcutRefreshIfNeeded;
@end

static void DXPShortcutSnapshotChanged(CFNotificationCenterRef center,
                                       void *observer,
                                       CFStringRef name,
                                       const void *object,
                                       CFDictionaryRef userInfo) {
    DXPAppShortcutPickerController *controller = (__bridge DXPAppShortcutPickerController *)observer;
    dispatch_async(dispatch_get_main_queue(), ^{
        [controller loadGroups];
    });
}

@implementation DXPAppShortcutPickerController

#pragma mark - Data

- (void)loadGroups {
    __weak typeof(self) weakSelf = self;
    // The catalogue is one small shared plist authored by SpringBoard: a
    // plain read that renders immediately and refreshes on the Darwin
    // change notification after each catalogue rebuild.
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        NSArray<NSDictionary *> *groups = [DXPAppInfo appShortcutGroups] ?: @[];
        NSArray<DXPAppInfo *> *installedApps = [DXPAppInfo installedApps] ?: @[];
        NSMutableArray<NSString *> *bundleIdentifiers = [NSMutableArray arrayWithCapacity:installedApps.count];
        for (DXPAppInfo *app in installedApps) {
            if (app.bundleID.length > 0) [bundleIdentifiers addObject:app.bundleID];
        }
        dispatch_async(dispatch_get_main_queue(), ^{
            __strong typeof(weakSelf) strongSelf = weakSelf;
            if (!strongSelf) return;
            strongSelf.groups = groups;
            strongSelf.refreshBundleIdentifiers = bundleIdentifiers;
            [strongSelf.tableView reloadData];
            [strongSelf updateFooter];
            [strongSelf requestSpringBoardShortcutRefreshIfNeeded];
        });
    });
}

// SpringBoard composes the real menu and is the only process with reliable
// access to it: request one full catalogue refresh after the first paint.
// Settings supplies the same two-pass LaunchServices enumeration used by the
// reference implementation. SpringBoard has an application-registry fallback
// if that list is empty.
- (void)requestSpringBoardShortcutRefreshIfNeeded {
    if (self.didRequestShortcutRefresh) return;
    NSString *requestID = [NSUUID UUID].UUIDString;
    NSDictionary *request = @{
        @"format": @3,
        @"requestID": requestID,
        @"bundles": self.refreshBundleIdentifiers ?: @[],
    };
    if (!DXSetQuickActionSharedValue(request, TypeXQuickActionRequestKey)) return;
    self.didRequestShortcutRefresh = YES;
    DXSetQuickActionSharedValue(@{
        @"phase": @"request-written",
        @"requestID": requestID,
        @"requestedApps": @(self.refreshBundleIdentifiers.count),
        @"updated": @([NSDate timeIntervalSinceReferenceDate]),
    }, TypeXQuickActionStatusKey);
    CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(),
                                         (__bridge CFStringRef)kShortcutRefreshRequestIdentifier,
                                         NULL, NULL, YES);
}

// Searching keeps groups whose app name/bundle identifier matches with all
// their items; a title/type match shows the group with only the matching
// items. Every value is nil-guarded: a malformed group must render as an
// empty section, never raise.
- (NSArray<NSDictionary *> *)filteredGroups {
    NSString *query = [self.searchText stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]] ?: @"";
    NSArray<NSDictionary *> *groups = self.groups ?: @[];
    if (query.length == 0) return groups;
    NSMutableArray<NSDictionary *> *result = [NSMutableArray array];
    for (NSDictionary *group in groups) {
        NSString *name = [group isKindOfClass:[NSDictionary class]] ? (group[@"name"] ?: @"") : @"";
        NSString *bundleID = [group isKindOfClass:[NSDictionary class]] ? (group[@"bundleID"] ?: @"") : @"";
        if ([name localizedCaseInsensitiveContainsString:query] ||
            [bundleID localizedCaseInsensitiveContainsString:query]) {
            [result addObject:group];
            continue;
        }
        NSMutableArray<DXPAppShortcutItem *> *matches = [NSMutableArray array];
        for (DXPAppShortcutItem *item in group[@"items"]) {
            NSString *title = item.title ?: @"";
            NSString *type = item.type ?: @"";
            if ([title localizedCaseInsensitiveContainsString:query] ||
                [type localizedCaseInsensitiveContainsString:query]) {
                [matches addObject:item];
            }
        }
        if (matches.count > 0) {
            [result addObject:@{@"name": name, @"bundleID": bundleID, @"items": [matches copy]}];
        }
    }
    return result;
}

- (NSDictionary *)groupForSection:(NSInteger)section {
    NSArray<NSDictionary *> *groups = [self filteredGroups];
    if (section < 0 || section >= (NSInteger)groups.count) return @{};
    NSDictionary *group = groups[section];
    return [group isKindOfClass:[NSDictionary class]] ? group : @{};
}

- (NSArray<DXPAppShortcutItem *> *)itemsForSection:(NSInteger)section {
    NSArray *items = [self groupForSection:section][@"items"];
    if (![items isKindOfClass:[NSArray class]]) return @[];
    return items;
}

- (DXPAppShortcutItem *)itemForIndexPath:(NSIndexPath *)indexPath {
    NSArray<DXPAppShortcutItem *> *items = [self itemsForSection:indexPath.section];
    if (indexPath.row < 0 || indexPath.row >= (NSInteger)items.count) return nil;
    return items[indexPath.row];
}

// Explains what the page lists (the shared catalogue SpringBoard authored
// from each app's resolved quick actions) and doubles as the empty-state
// view; the empty case points at the background build so a just-installed
// state is not mistaken for a broken one.
- (void)updateFooter {
    NSString *text = [self filteredGroups].count > 0
        ? LOCALIZED(@"STATIC_SHORTCUTS_FOOTER")
        : LOCALIZED(@"NO_APP_SHORTCUTS");

    CGFloat width = self.tableView.bounds.size.width - 40;
    UILabel *label = [[UILabel alloc] initWithFrame:CGRectMake(20, 8, width, 40)];
    label.text = text;
    label.font = [UIFont systemFontOfSize:13];
    label.textColor = [UIColor secondaryLabelColor];
    label.textAlignment = NSTextAlignmentCenter;
    label.numberOfLines = 0;
    CGFloat height = [label sizeThatFits:CGSizeMake(width, CGFLOAT_MAX)].height + 8;
    label.frame = CGRectMake(20, 8, width, height);
    self.tableView.tableFooterView = label;
}

#pragma mark - Table view

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    return [self filteredGroups].count;
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    return [self groupForSection:section][@"name"];
}

- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section {
    return [self groupForSection:section][@"bundleID"];
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return [self itemsForSection:section].count;
}

- (CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath {
    return 60;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    DXPAppShortcutCell *cell = [tableView dequeueReusableCellWithIdentifier:@"DXPAppShortcutCell" forIndexPath:indexPath];
    DXPAppShortcutItem *item = [self itemForIndexPath:indexPath];
    if (item) {
        cell.textLabel.text = item.title ?: item.type;
        NSString *source = item.source == DXPAppShortcutSourceDynamic
            ? LOCALIZED(@"SHORTCUT_SOURCE_DYNAMIC")
            : LOCALIZED(@"SHORTCUT_SOURCE_STATIC");
        cell.detailTextLabel.text = item.type.length > 0
            ? [NSString stringWithFormat:@"%@ · %@", item.type, source]
            : source;
    } else {
        cell.textLabel.text = nil;
        cell.detailTextLabel.text = nil;
    }
    cell.detailTextLabel.textColor = [UIColor secondaryLabelColor];
    cell.detailTextLabel.lineBreakMode = NSLineBreakByTruncatingMiddle;
    cell.imageView.image = [DXPAppInfo iconForBundleID:[self groupForSection:indexPath.section][@"bundleID"]];
    // Selectable when a completion is set (checkmark marks the configured
    // item); the legacy preview keeps rows inert and unhighlighted.
    BOOL isSelected = [item.type isKindOfClass:[NSString class]] &&
        [item.type isEqualToString:self.currentType] &&
        [[self groupForSection:indexPath.section][@"bundleID"] isEqualToString:self.currentBundleID];
    cell.accessoryType = (self.completion && isSelected)
        ? UITableViewCellAccessoryCheckmark : UITableViewCellAccessoryNone;
    cell.selectionStyle = self.completion
        ? UITableViewCellSelectionStyleDefault : UITableViewCellSelectionStyleNone;
    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    // Without a completion (legacy preview mode) the page stays display-only.
    if (!self.completion) return;

    DXPAppShortcutItem *item = [self itemForIndexPath:indexPath];
    if (![item isKindOfClass:[DXPAppShortcutItem class]] || item.type.length == 0) return;
    NSString *bundleID = [self groupForSection:indexPath.section][@"bundleID"];
    if (![bundleID isKindOfClass:[NSString class]] || bundleID.length == 0) return;

    self.completion(item.title ?: item.type, bundleID, item.type);
    [self.navigationController popViewControllerAnimated:YES];
}

#pragma mark - Search

- (void)updateSearchResultsForSearchController:(UISearchController *)searchController {
    self.searchText = searchController.searchBar.text;
    [self.tableView reloadData];
    [self updateFooter];
}

#pragma mark - Lifecycle

- (void)viewDidLoad {
    tweakBundle = [NSBundle bundleWithPath:bundlePath];
    [tweakBundle load];
    [super viewDidLoad];

    self.title = LOCALIZED(@"SELECT_SHORTCUT");

    CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(),
                                    (__bridge const void *)self,
                                    DXPShortcutSnapshotChanged,
                                    (__bridge CFStringRef)kShortcutSnapshotChangedIdentifier,
                                    NULL,
                                    CFNotificationSuspensionBehaviorDeliverImmediately);

    self.tableView = [[UITableView alloc] initWithFrame:self.view.bounds style:UITableViewStyleInsetGrouped];
    self.tableView.delegate = self;
    self.tableView.dataSource = self;
    self.tableView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    [self.tableView registerClass:[DXPAppShortcutCell class] forCellReuseIdentifier:@"DXPAppShortcutCell"];
    self.view = self.tableView;

    self.searchController = [[UISearchController alloc] initWithSearchResultsController:nil];
    self.searchController.searchResultsUpdater = self;
    self.searchController.obscuresBackgroundDuringPresentation = NO;
    self.searchController.definesPresentationContext = YES;
    self.searchController.searchBar.placeholder = LOCALIZED(@"SEARCH_PLACEHOLDER");
    self.navigationItem.searchController = self.searchController;
    self.navigationItem.hidesSearchBarWhenScrolling = NO;

    [self loadGroups];
}

- (void)dealloc {
    CFNotificationCenterRemoveObserver(CFNotificationCenterGetDarwinNotifyCenter(),
                                       (__bridge const void *)self,
                                       (__bridge CFStringRef)kShortcutSnapshotChangedIdentifier,
                                       NULL);
}

@end
