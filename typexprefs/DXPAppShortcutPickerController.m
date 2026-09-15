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
@property (nonatomic, strong) NSArray<NSString *> *shortcutRefreshBundleIDs;
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
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        NSArray<NSDictionary *> *groups = [DXPAppInfo appShortcutGroups] ?: @[];
        NSMutableOrderedSet<NSString *> *bundleIDs = [NSMutableOrderedSet orderedSet];
        for (DXPAppInfo *app in [DXPAppInfo installedApps]) {
            if (DXIsValidBundleIdentifier(app.bundleID)) [bundleIDs addObject:app.bundleID];
            if (bundleIDs.count >= 2048) break;
        }
        dispatch_async(dispatch_get_main_queue(), ^{
            __strong typeof(weakSelf) strongSelf = weakSelf;
            if (!strongSelf) return;
            strongSelf.groups = groups;
            strongSelf.shortcutRefreshBundleIDs = bundleIDs.array;
            [strongSelf.tableView reloadData];
            [strongSelf updateFooter];
            [strongSelf requestSpringBoardShortcutRefreshIfNeeded];
        });
    });
}

// The Settings process can parse bundle metadata, but only SpringBoard has
// full access to the final composed menu. Request one catalogue refresh after
// the initial scan; the Darwin response reloads the picker with localized,
// current SBSApplicationShortcutItem titles.
- (void)requestSpringBoardShortcutRefreshIfNeeded {
    if (self.didRequestShortcutRefresh) return;
    self.didRequestShortcutRefresh = YES;

    if (self.shortcutRefreshBundleIDs.count == 0) return;

    NSDictionary *request = @{@"bundles": self.shortcutRefreshBundleIDs};
    if (![request writeToFile:TypeXShortcutRefreshRequestPath atomically:YES]) return;
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

// Explains what the page lists (static items from each app bundle plus the
// dynamic items apps registered on this device) and doubles as the empty-state
// view. When empty, the scanned-app count distinguishes "no app declares
// shortcuts" from "the scan found no apps at all".
- (void)updateFooter {
    NSString *text;
    if ([self filteredGroups].count > 0) {
        text = LOCALIZED(@"STATIC_SHORTCUTS_FOOTER");
    } else {
        NSInteger scanned = [DXPAppInfo lastShortcutScanApplicationCount];
        text = scanned > 0
            ? [NSString stringWithFormat:LOCALIZED(@"NO_APP_SHORTCUTS_SCANNED"), (long)scanned]
            : LOCALIZED(@"NO_APP_SHORTCUTS");
    }

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
        // Source tag tells the four planes apart: a live entry captured from
        // the real SpringBoard menu (freshest, includes system-merged
        // suggestions), a dynamic entry (present only because the app
        // registered it on this device), an App Shortcut (iOS 16+ App
        // Intents), and a static one from the app bundle.
        NSString *source = item.source == DXPAppShortcutSourceSpringBoard
            ? LOCALIZED(@"SHORTCUT_SOURCE_SPRINGBOARD")
            : (item.source == DXPAppShortcutSourceDynamic
                ? LOCALIZED(@"SHORTCUT_SOURCE_DYNAMIC")
                : (item.source == DXPAppShortcutSourceAppIntent
                    ? LOCALIZED(@"SHORTCUT_SOURCE_APPINTENT")
                    : LOCALIZED(@"SHORTCUT_SOURCE_STATIC")));
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
