#import "DXPCustomActionsController.h"
#import "DXPLinkActionEditorController.h"
#import "DXPAppInfo.h"
#import "DXPBatchOpenAppEntries.h"
#import "DXPActionGroups.h"
#import "DXPOpenAppPickerController.h"
#import "../DXHelper.h"
#import "../common.h"

static NSBundle *tweakBundle;

// Standalone 自定义动作 management page, laid out after the KayokoX reference:
// one section per 自定义分组 (header shows name + count and an ellipsis button
// for rename/delete), the trailing 未分组 section for entries without a group,
// a 选择动作 group of fixed type entries that start the add flow plus the
// batch row, and a navigation-bar search that filters actions into one flat
// result section. Groups are display-only metadata — the flat array order
// remains the order every consumer sees; an in-section drag reorders the
// global array through the section index map.

// Subtitle cell rendering icons at their natural size — SF Symbols and the
// 24pt rounded app-icon slot alike — so 已选择 rows match the 选择动作 type
// rows below instead of showing enlarged 40pt glyphs. Re-pinning origin.y in
// layoutSubviews keeps the small icon vertically centered in the taller row.
@interface DXPManagedActionCell : UITableViewCell
@end
@implementation DXPManagedActionCell
// Registered via registerClass, which would otherwise build a Default-style
// cell; force Subtitle so the detail line (link / type) exists.
- (instancetype)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)reuseIdentifier {
    return [super initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:reuseIdentifier];
}
- (void)layoutSubviews {
    [super layoutSubviews];
    self.imageView.contentMode = UIViewContentModeScaleAspectFit;
    CGRect frame = self.imageView.frame;
    frame.origin.y = roundf((CGRectGetHeight(self.contentView.bounds) - frame.size.height) / 2.0);
    self.imageView.frame = frame;
}
@end

@interface DXPCustomActionsController () <UISearchResultsUpdating>
// Ordered real groups (registry + discovered); groupIndexes has one index
// bucket per group section plus the trailing 未分组 bucket.
@property (nonatomic, copy) NSArray<NSString *> *groupNames;
@property (nonatomic, strong) NSArray<NSArray<NSNumber *> *> *groupIndexes;
@property (nonatomic, strong) NSArray<NSNumber *> *searchIndexes;
@property (nonatomic, strong) UISearchController *searchController;
@property (nonatomic, assign) BOOL isSearching;
@end

@implementation DXPCustomActionsController

#pragma mark - Lifecycle

- (void)viewDidLoad {
    tweakBundle = [NSBundle bundleWithPath:bundlePath];
    [tweakBundle load];

    self.customActionsOnly = YES;
    // No selection on this page; also suppresses the base's 默认 reset button.
    self.selectionManagedExternally = YES;

    [super viewDidLoad];
    self.title = LOCALIZED(@"CUSTOM_ACTIONS");

    // The base built its plain table in viewDidLoad; swap in our own so rows
    // can use subtitle style and taller layout.
    self.tableView = [[UITableView alloc] initWithFrame:self.view.bounds style:UITableViewStyleInsetGrouped];
    self.tableView.delegate = self;
    self.tableView.dataSource = self;
    self.tableView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    [self.tableView registerClass:[DXPManagedActionCell class] forCellReuseIdentifier:@"DXPManagedActionCell"];
    [self.tableView registerClass:[UITableViewCell class] forCellReuseIdentifier:@"DXPManagedTypeCell"];
    [self.tableView registerClass:[UITableViewCell class] forCellReuseIdentifier:@"DXPManagedEmptyCell"];
    self.view = self.tableView;

    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithTitle:LOCALIZED(@"EDIT")
                                                                              style:UIBarButtonItemStylePlain
                                                                             target:self
                                                                             action:@selector(toggleEditing:)];

    self.searchController = [[UISearchController alloc] initWithSearchResultsController:nil];
    self.searchController.searchResultsUpdater = self;
    self.searchController.obscuresBackgroundDuringPresentation = NO;
    self.navigationItem.searchController = self.searchController;
    self.navigationItem.hidesSearchBarWhenScrolling = NO;
    self.definesPresentationContext = YES;
}

- (void)reloadDataKeepingSelection {
    [self refreshSections];
    [self.tableView reloadData];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [self reloadPreferences];
    [self refreshSections];
    [self.tableView reloadData];
}

- (void)toggleEditing:(UIBarButtonItem *)sender {
    BOOL editing = !self.tableView.editing;
    [self.tableView setEditing:editing animated:YES];
    sender.title = LOCALIZED(editing ? @"DONE" : @"EDIT");
    // Chevrons hide while editing; refresh the visible action rows.
    [self.tableView reloadRowsAtIndexPaths:[self.tableView indexPathsForVisibleRows]
                          withRowAnimation:UITableViewRowAnimationAutomatic];
}

#pragma mark - Section model

// One rebuild per data change: group sections mirror the flat array through
// global index buckets, so every row gesture below works on the underlying
// linkactions positions without duplicating storage.
- (void)refreshSections {
    self.groupNames = DXActionGroupNames(self.prefs, self.linkActions);
    NSMutableArray<NSMutableArray<NSNumber *> *> *buckets = [NSMutableArray array];
    for (NSUInteger index = 0; index <= self.groupNames.count; index++) [buckets addObject:[NSMutableArray array]];
    [self.linkActions enumerateObjectsUsingBlock:^(NSDictionary *entry, NSUInteger index, BOOL *stop) {
        NSString *name = DXActionGroupNormalizedName(entry[kCustomActionGroupKey]);
        NSInteger slot = name.length ? (NSInteger)[self.groupNames indexOfObject:name] : NSNotFound;
        [buckets[(slot >= 0 ? slot : (NSInteger)self.groupNames.count)] addObject:@(index)];
    }];
    self.groupIndexes = buckets;
}

// Global (flat-array) index for an action row; NSNotFound for placeholder rows.
- (NSInteger)globalIndexAtIndexPath:(NSIndexPath *)indexPath {
    if (self.isSearching)
        return indexPath.row < (NSInteger)self.searchIndexes.count ? self.searchIndexes[indexPath.row].integerValue : NSNotFound;
    if (indexPath.section < 0 || indexPath.section >= (NSInteger)self.groupIndexes.count) return NSNotFound;
    NSArray<NSNumber *> *indexes = self.groupIndexes[indexPath.section];
    return indexPath.row < (NSInteger)indexes.count ? indexes[indexPath.row].integerValue : NSNotFound;
}

- (NSInteger)addSection {
    return self.isSearching ? -1 : (NSInteger)self.groupNames.count + 1;
}

- (NSInteger)ungroupedSection {
    return (NSInteger)self.groupNames.count;
}

#pragma mark - Table view

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    return self.isSearching ? 1 : self.groupNames.count + 2;
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    if (self.isSearching) return nil;
    if (section == self.addSection) return LOCALIZED(@"CHOOSE_ACTION");
    if (section == self.ungroupedSection) return LOCALIZED(@"UNGROUPED");
    return self.groupNames[section];
}

- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section {
    if (section == 0) {
        return [NSString stringWithFormat:@"• %@\n• %@",
                LOCALIZED(@"MANAGE_HINT_TAP_EDIT"), LOCALIZED(@"MANAGE_HINT_EDIT_DELETE")];
    }
    if (section == self.addSection) return LOCALIZED(@"ADD_TYPE_HINT");
    return nil;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    if (self.isSearching) return MAX(1, (NSInteger)self.searchIndexes.count);
    if (section == self.addSection) return self.addTypeList.count + 1;
    NSInteger count = (NSInteger)self.groupIndexes[section].count;
    // The empty-list placeholder row lives in the trailing 未分组 section.
    if (self.linkActions.count == 0 && section == self.ungroupedSection) count = MAX(count, 1);
    return count;
}

- (CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath {
    if (indexPath.section == self.addSection) return 44.0;
    return [self globalIndexAtIndexPath:indexPath] != NSNotFound ? 60.0 : 44.0;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    if (indexPath.section == self.addSection) return [self typeCellForIndexPath:indexPath];
    NSInteger global = [self globalIndexAtIndexPath:indexPath];
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"DXPManagedEmptyCell" forIndexPath:indexPath];
    if (global == NSNotFound) {
        cell.textLabel.text = LOCALIZED(self.isSearching ? @"SEARCH_NO_MATCH" : @"NO_CUSTOM_ACTIONS");
        cell.textLabel.textColor = [UIColor secondaryLabelColor];
        cell.detailTextLabel.text = nil;
        cell.imageView.image = nil;
        cell.accessoryType = UITableViewCellAccessoryNone;
        cell.selectionStyle = UITableViewCellSelectionStyleNone;
        return cell;
    }
    return [self actionCellForRowAtIndexPath:indexPath global:global];
}

- (UITableViewCell *)actionCellForRowAtIndexPath:(NSIndexPath *)indexPath global:(NSInteger)global {
    UITableViewCell *cell = [self.tableView dequeueReusableCellWithIdentifier:@"DXPManagedActionCell" forIndexPath:indexPath];
    NSDictionary *entry = self.linkActions[global];
    NSString *type = [entry[kCustomActionTypeKey] isKindOfClass:[NSString class]] ? entry[kCustomActionTypeKey] : @"";
    NSString *name = [entry[@"name"] isKindOfClass:[NSString class]] ? entry[@"name"] : @"";
    NSString *link = [entry[@"link"] isKindOfClass:[NSString class]] ? entry[@"link"] : @"";
    NSString *icon = [entry[@"icon"] isKindOfClass:[NSString class]] ? entry[@"icon"] : @"";

    cell.textLabel.text = name.length ? name : LOCALIZED(@"DEFAULT_BUTTON_NAME");
    NSString *shortcutTitle = [entry[kCustomActionShortcutTitleKey] isKindOfClass:NSString.class]
        ? entry[kCustomActionShortcutTitleKey] : @"";
    cell.detailTextLabel.text = [type isEqualToString:kCustomActionTypeShortcut] && shortcutTitle.length
        ? [NSString stringWithFormat:@"%@ · %@", link, shortcutTitle]
        : (link.length ? link : [DXPLinkActionEditorController displayNameForType:type]);
    if ([type isEqualToString:kCustomActionTypeText]) {
        id records = entry[kCustomActionTextRecordsKey];
        NSUInteger count = [records isKindOfClass:NSArray.class] ? [records count] : 0;
        cell.detailTextLabel.text = [NSString stringWithFormat:LOCALIZED(@"TEXT_RECORD_COUNT"), (unsigned long)count];
    }
    cell.detailTextLabel.textColor = [UIColor secondaryLabelColor];
    cell.imageView.image = [DXHelper imageForIconConfig:icon defaultSymbolName:[DXPLinkActionEditorController defaultIconForType:type]]
        ?: [UIImage systemImageNamed:[DXPLinkActionEditorController defaultIconForType:type]];
    // Same explicit tint as the 选择动作 rows; app icons are AlwaysOriginal and
    // unaffected, so both sections draw symbols in the same blue.
    cell.imageView.tintColor = [UIColor systemBlueColor];
    cell.accessoryType = self.tableView.editing ? UITableViewCellAccessoryNone : UITableViewCellAccessoryDisclosureIndicator;
    cell.editingAccessoryType = UITableViewCellAccessoryNone;
    return cell;
}

- (UITableViewCell *)typeCellForIndexPath:(NSIndexPath *)indexPath {
    UITableViewCell *cell = [self.tableView dequeueReusableCellWithIdentifier:@"DXPManagedTypeCell" forIndexPath:indexPath];
    NSInteger batchRow = (NSInteger)self.addTypeList.count;
    if (indexPath.row == batchRow) {
        // Kept outside addTypeList so the shared type chooser and this section
        // never need to agree on a pseudo-type (the 3.10.3 sync trap).
        cell.textLabel.text = LOCALIZED(@"BATCH_ADD_APPLICATIONS");
        cell.imageView.image = [UIImage systemImageNamed:@"square.grid.2x2"];
    } else {
        NSString *type = [self typeAtIndex:indexPath.row];
        cell.textLabel.text = [DXPLinkActionEditorController displayNameForType:type];
        cell.imageView.image = [UIImage systemImageNamed:[DXPLinkActionEditorController defaultIconForType:type]];
    }
    cell.textLabel.textColor = [UIColor labelColor];
    cell.detailTextLabel.text = nil;
    cell.imageView.tintColor = [UIColor systemBlueColor];
    cell.accessoryType = UITableViewCellAccessoryNone;
    cell.editingAccessoryType = UITableViewCellAccessoryNone;
    return cell;
}

// 管理页「选择动作」分区的类型清单：与添加弹窗（presentTypeChooserFrom-
// Controller）保持同一集合与顺序——网页链接已退役，系统动作在此直选。
- (NSArray<NSString *> *)addTypeList {
    static NSArray<NSString *> *types;
    if (!types) types = @[
        kCustomActionTypeURLScheme,
        kCustomActionTypeText,
        kCustomActionTypeOpenApp,
        kCustomActionTypeShortcut,
        kCustomActionTypeSystem,
        kCustomActionTypeJavaScript,
    ];
    return types;
}

- (NSString *)typeAtIndex:(NSInteger)row {
    return self.addTypeList[row];
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    if (indexPath.section == self.addSection) {
        if (indexPath.row == (NSInteger)self.addTypeList.count) [self startBatchAddApplicationsFlow];
        else [self startAddFlowForType:[self typeAtIndex:indexPath.row]];
        return;
    }
    NSInteger global = [self globalIndexAtIndexPath:indexPath];
    if (global == NSNotFound) return;
    if (tableView.editing) {
        // Per the reference layout: tapping a row in edit mode deletes it.
        [self tableView:tableView commitEditingStyle:UITableViewCellEditingStyleDelete forRowAtIndexPath:indexPath];
        return;
    }
    [self pushEditorForCustomRow:global];
}

#pragma mark - Grouping

// Registry = the full visible group list: persisting it also absorbs groups
// discovered on entries but missing from storage, so what you see is what is
// stored from here on.
- (void)assignActionSelector:(NSString *)selector toGroup:(NSString *)group {
    NSString *name = DXActionGroupNormalizedName(group);
    NSMutableArray<NSString *> *registry = [self.groupNames mutableCopy];
    if (name.length && ![registry containsObject:name]) [registry addObject:name];
    if (!DXActionAssignGroup(self.linkActions, selector, name) && [registry isEqualToArray:self.groupNames]) return;
    self.prefs[kLinkActionGroupsKey] = registry;
    [self persistLinkActions];
    [self refreshSections];
    [self.tableView reloadData];
}

- (void)presentAssignGroupMenuForSelector:(NSString *)selector currentGroup:(NSString *)currentGroup {
    UIAlertController *menu = [UIAlertController alertControllerWithTitle:LOCALIZED(@"MOVE_TO_GROUP")
                                                                  message:nil preferredStyle:UIAlertControllerStyleAlert];
    for (NSString *name in self.groupNames) {
        if ([name isEqualToString:currentGroup]) continue;
        [menu addAction:[UIAlertAction actionWithTitle:name style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *action) {
            [self assignActionSelector:selector toGroup:name];
        }]];
    }
    [menu addAction:[UIAlertAction actionWithTitle:LOCALIZED(@"NEW_GROUP") style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *action) {
        [self presentCreateGroupAlertForSelector:selector];
    }]];
    [menu addAction:[UIAlertAction actionWithTitle:LOCALIZED(@"ANSWER_CANCEL") style:UIAlertActionStyleCancel handler:nil]];
    [self presentViewController:menu animated:YES completion:nil];
}

- (void)presentCreateGroupAlertForSelector:(NSString *)selector {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:LOCALIZED(@"NEW_GROUP")
                                                                   message:nil preferredStyle:UIAlertControllerStyleAlert];
    [alert addTextFieldWithConfigurationHandler:^(UITextField *textField) {
        textField.placeholder = LOCALIZED(@"GROUP_NAME");
    }];
    [alert addAction:[UIAlertAction actionWithTitle:LOCALIZED(@"ANSWER_OK") style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *action) {
        [self assignActionSelector:selector toGroup:alert.textFields.firstObject.text];
    }]];
    [alert addAction:[UIAlertAction actionWithTitle:LOCALIZED(@"ANSWER_CANCEL") style:UIAlertActionStyleCancel handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)groupHeaderTapped:(UIButton *)sender {
    NSInteger section = sender.tag;
    if (section < 0 || section >= (NSInteger)self.groupNames.count) return; // the trailing 未分组 header has no button
    NSString *name = self.groupNames[section];
    UIAlertController *menu = [UIAlertController alertControllerWithTitle:name
                                                                  message:nil preferredStyle:UIAlertControllerStyleAlert];
    [menu addAction:[UIAlertAction actionWithTitle:LOCALIZED(@"RENAME_GROUP") style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *action) {
        [self presentRenameGroupAlertForSection:section];
    }]];
    [menu addAction:[UIAlertAction actionWithTitle:LOCALIZED(@"DELETE_GROUP") style:UIAlertActionStyleDestructive handler:^(__unused UIAlertAction *action) {
        [self presentDeleteGroupAlertForSection:section];
    }]];
    [menu addAction:[UIAlertAction actionWithTitle:LOCALIZED(@"ANSWER_CANCEL") style:UIAlertActionStyleCancel handler:nil]];
    [self presentViewController:menu animated:YES completion:nil];
}

- (void)presentRenameGroupAlertForSection:(NSInteger)section {
    NSString *oldName = self.groupNames[section];
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:LOCALIZED(@"RENAME_GROUP")
                                                                   message:nil preferredStyle:UIAlertControllerStyleAlert];
    [alert addTextFieldWithConfigurationHandler:^(UITextField *textField) {
        textField.text = oldName;
        textField.placeholder = LOCALIZED(@"GROUP_NAME");
    }];
    [alert addAction:[UIAlertAction actionWithTitle:LOCALIZED(@"ANSWER_OK") style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *action) {
        NSString *name = DXActionGroupNormalizedName(alert.textFields.firstObject.text);
        if (!name.length || [name isEqualToString:oldName]) return;
        NSMutableArray<NSString *> *registry = [self.groupNames mutableCopy];
        if ([registry containsObject:name]) {
            UIAlertController *taken = [UIAlertController alertControllerWithTitle:nil
                                                                           message:LOCALIZED(@"GROUP_EXISTS")
                                                                  preferredStyle:UIAlertControllerStyleAlert];
            [taken addAction:[UIAlertAction actionWithTitle:LOCALIZED(@"ANSWER_OK") style:UIAlertActionStyleDefault handler:nil]];
            [self presentViewController:taken animated:YES completion:nil];
            return;
        }
        registry[section] = name;
        DXActionRenameGroup(self.linkActions, oldName, name);
        self.prefs[kLinkActionGroupsKey] = registry;
        [self persistLinkActions];
        [self refreshSections];
        [self.tableView reloadData];
    }]];
    [alert addAction:[UIAlertAction actionWithTitle:LOCALIZED(@"ANSWER_CANCEL") style:UIAlertActionStyleCancel handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)presentDeleteGroupAlertForSection:(NSInteger)section {
    NSString *name = self.groupNames[section];
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:LOCALIZED(@"DELETE_GROUP")
                                                                   message:[NSString stringWithFormat:LOCALIZED(@"DELETE_GROUP_CONFIRM"), name]
                                                                  preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:LOCALIZED(@"DELETE") style:UIAlertActionStyleDestructive handler:^(__unused UIAlertAction *action) {
        NSMutableArray<NSString *> *registry = [self.groupNames mutableCopy];
        [registry removeObject:name];
        DXActionUngroupMembers(self.linkActions, name);
        self.prefs[kLinkActionGroupsKey] = registry;
        [self persistLinkActions];
        [self refreshSections];
        [self.tableView reloadData];
    }]];
    [alert addAction:[UIAlertAction actionWithTitle:LOCALIZED(@"ANSWER_CANCEL") style:UIAlertActionStyleCancel handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}

#pragma mark - Group header views

- (UIView *)tableView:(UITableView *)tableView viewForHeaderInSection:(NSInteger)section {
    if (self.isSearching || section == self.addSection) return nil; // title-based header fallback
    NSString *name = section == self.ungroupedSection ? LOCALIZED(@"UNGROUPED") : self.groupNames[section];
    NSString *detail = [NSString stringWithFormat:LOCALIZED(@"GROUP_ACTIONS_COUNT"),
                        (unsigned long)self.groupIndexes[section].count];

    UIView *header = [[UIView alloc] initWithFrame:CGRectZero];
    UILabel *label = [[UILabel alloc] init];
    label.text = [NSString stringWithFormat:@"%@ · %@", name, detail];
    label.font = [UIFont systemFontOfSize:13.0 weight:UIFontWeightSemibold];
    label.textColor = [UIColor secondaryLabelColor];
    label.translatesAutoresizingMaskIntoConstraints = NO;
    [header addSubview:label];
    [NSLayoutConstraint activateConstraints:@[
        [label.leadingAnchor constraintEqualToAnchor:header.layoutMarginsGuide.leadingAnchor],
        [label.trailingAnchor constraintLessThanOrEqualToAnchor:header.layoutMarginsGuide.trailingAnchor],
        [label.centerYAnchor constraintEqualToAnchor:header.centerYAnchor],
    ]];
    if (section != self.ungroupedSection) {
        UIButton *menuButton = [UIButton buttonWithType:UIButtonTypeSystem];
        [menuButton setImage:[UIImage systemImageNamed:@"ellipsis.circle"] forState:UIControlStateNormal];
        menuButton.tintColor = [UIColor secondaryLabelColor];
        menuButton.tag = section;
        [menuButton addTarget:self action:@selector(groupHeaderTapped:) forControlEvents:UIControlEventTouchUpInside];
        menuButton.translatesAutoresizingMaskIntoConstraints = NO;
        [header addSubview:menuButton];
        [NSLayoutConstraint activateConstraints:@[
            [menuButton.trailingAnchor constraintEqualToAnchor:header.layoutMarginsGuide.trailingAnchor],
            [menuButton.centerYAnchor constraintEqualToAnchor:header.centerYAnchor],
            [menuButton.widthAnchor constraintEqualToConstant:28.0],
            [menuButton.heightAnchor constraintEqualToConstant:28.0],
            [label.trailingAnchor constraintLessThanOrEqualToAnchor:menuButton.leadingAnchor constant:-8.0],
        ]];
    }
    return header;
}

- (CGFloat)tableView:(UITableView *)tableView heightForHeaderInSection:(NSInteger)section {
    return (self.isSearching || section == self.addSection) ? UITableViewAutomaticDimension : 34.0;
}

#pragma mark - Edit and delete

- (BOOL)tableView:(UITableView *)tableView canEditRowAtIndexPath:(NSIndexPath *)indexPath {
    // Searching rebuilds the visible order from a filter, so structural edits
    // are disabled there (the same guard the panel lists use).
    return !self.isSearching && [self globalIndexAtIndexPath:indexPath] != NSNotFound;
}

- (UITableViewCellEditingStyle)tableView:(UITableView *)tableView editingStyleForRowAtIndexPath:(NSIndexPath *)indexPath {
    return [self tableView:tableView canEditRowAtIndexPath:indexPath]
        ? UITableViewCellEditingStyleDelete : UITableViewCellEditingStyleNone;
}

- (void)tableView:(UITableView *)tableView commitEditingStyle:(UITableViewCellEditingStyle)editingStyle forRowAtIndexPath:(NSIndexPath *)indexPath {
    if (editingStyle != UITableViewCellEditingStyleDelete) return;
    NSInteger global = [self globalIndexAtIndexPath:indexPath];
    if (global == NSNotFound) return;
    NSString *selector = self.linkActions[global][@"selector"];
    [self.linkActions removeObjectAtIndex:(NSUInteger)global];
    self.prefs[kLinkActionskey] = self.linkActions;
    [self removeReferencesToSelector:selector fromPreferences:self.prefs];
    [self writePreferences];
    [self refreshSections];
    [self.tableView reloadData];
}

// Edit-mode drag reorder within one group section. The array order is the
// display order everywhere the actions are offered, so a section drag is a
// plain global-array move — other groups and their relative positions stay
// untouched.
- (BOOL)tableView:(UITableView *)tableView canMoveRowAtIndexPath:(NSIndexPath *)indexPath {
    return [self tableView:tableView canEditRowAtIndexPath:indexPath];
}

- (NSIndexPath *)tableView:(UITableView *)tableView targetIndexPathForMoveFromRowAtIndexPath:(NSIndexPath *)source toProposedIndexPath:(NSIndexPath *)destination {
    // Keep moves inside the action list and inside one group: never onto a
    // placeholder row, another group, or the add-action section.
    if (![self tableView:tableView canEditRowAtIndexPath:source] ||
        ![self tableView:tableView canEditRowAtIndexPath:destination] ||
        source.section != destination.section) return source;
    return destination;
}

- (void)tableView:(UITableView *)tableView moveRowAtIndexPath:(NSIndexPath *)sourceIndexPath toIndexPath:(NSIndexPath *)destinationIndexPath {
    if (self.isSearching || sourceIndexPath.section != destinationIndexPath.section) return;
    NSInteger from = [self globalIndexAtIndexPath:sourceIndexPath];
    NSInteger to = [self globalIndexAtIndexPath:destinationIndexPath];
    if (from == NSNotFound || to == NSNotFound || from == to) return;
    NSMutableDictionary *entry = self.linkActions[from];
    [self.linkActions removeObjectAtIndex:(NSUInteger)from];
    [self.linkActions insertObject:entry atIndex:(NSUInteger)to];
    self.prefs[kLinkActionskey] = self.linkActions;
    [self writePreferences];
    // The table applied the move visually; only the index map shifts.
    [self refreshSections];
}

// Swipe delete stays reachable outside edit mode as well.
- (UISwipeActionsConfiguration *)tableView:(UITableView *)tableView trailingSwipeActionsConfigurationForRowAtIndexPath:(NSIndexPath *)indexPath {
    if (![self tableView:tableView canEditRowAtIndexPath:indexPath]) return nil;
    __weak typeof(self) weakSelf = self;
    UIContextualAction *delete = [UIContextualAction contextualActionWithStyle:UIContextualActionStyleDestructive
                                                                         title:LOCALIZED(@"DELETE")
                                                                       handler:^(__unused UIContextualAction *action,
                                                                                 __unused UIView *sourceView,
                                                                                 void (^completionHandler)(BOOL)) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (strongSelf) [strongSelf tableView:strongSelf.tableView
                            commitEditingStyle:UITableViewCellEditingStyleDelete
                             forRowAtIndexPath:indexPath];
        completionHandler(strongSelf != nil);
    }];
    return [UISwipeActionsConfiguration configurationWithActions:@[delete]];
}

// Long-press a row to move it between groups (edit mode keeps drag = reorder,
// so the menu is suppressed there).
- (UIContextMenuConfiguration *)tableView:(UITableView *)tableView contextMenuConfigurationForRowAtIndexPath:(NSIndexPath *)indexPath point:(CGPoint)point {
    if (tableView.editing || self.isSearching || indexPath.section == self.addSection) return nil;
    NSInteger global = [self globalIndexAtIndexPath:indexPath];
    if (global == NSNotFound) return nil;
    NSString *selector = self.linkActions[global][@"selector"];
    NSString *currentGroup = DXActionGroupNormalizedName(self.linkActions[global][kCustomActionGroupKey]);
    __weak typeof(self) weakSelf = self;
    return [UIContextMenuConfiguration configurationWithIdentifier:nil previewProvider:nil actionProvider:^UIMenu *(NSArray *suggestedActions) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf) return [UIMenu menuWithTitle:@"" children:@[]];
        NSMutableArray<UIAction *> *actions = [NSMutableArray array];
        [actions addObject:[UIAction actionWithTitle:LOCALIZED(@"MOVE_TO_GROUP")
                                               image:[UIImage systemImageNamed:@"folder.badge.plus"]
                                          identifier:nil handler:^(__unused UIAction *action) {
            [strongSelf presentAssignGroupMenuForSelector:selector currentGroup:currentGroup];
        }]];
        if (currentGroup.length) {
            [actions addObject:[UIAction actionWithTitle:LOCALIZED(@"REMOVE_FROM_GROUP")
                                                   image:[UIImage systemImageNamed:@"folder"]
                                              identifier:nil handler:^(__unused UIAction *action) {
                [strongSelf assignActionSelector:selector toGroup:@""];
            }]];
        }
        return [UIMenu menuWithTitle:@"" children:actions];
    }];
}

#pragma mark - Batch add applications

// 批量添加应用: one multi-select pass over installed apps, then a single
// read-modify-write creating one openapp action per pick (in tap order).
// Apps that already have an openapp action are skipped and reported; an
// empty pick touches nothing.
- (void)startBatchAddApplicationsFlow {
    DXPOpenAppPickerController *picker = [[DXPOpenAppPickerController alloc] init];
    picker.allowsMultipleSelection = YES;
    __weak typeof(self) weakSelf = self;
    picker.multiSelectionCompletion = ^(NSArray<DXPAppInfo *> *apps) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (strongSelf) [strongSelf addOpenAppActionsForApps:apps];
    };
    [picker setRootController:[self rootController]];
    [picker setParentController:[self parentController]];
    [self pushController:picker];
}

- (void)addOpenAppActionsForApps:(NSArray<DXPAppInfo *> *)apps {
    NSMutableArray<NSDictionary *> *picks = [NSMutableArray array];
    for (DXPAppInfo *app in apps)
        [picks addObject:@{@"bundleID": app.bundleID ?: @"", @"name": app.name ?: @""}];

    NSUInteger skipped = 0;
    NSArray<NSMutableDictionary *> *entries = DXBatchOpenAppEntries(self.linkActions, picks, &skipped);
    if (entries.count == 0) {
        if (skipped > 0) [self showBatchAddResult:0 skipped:skipped];
        return;
    }
    [self.linkActions addObjectsFromArray:entries];
    [self persistLinkActions];
    [self refreshSections];
    [self.tableView reloadData];
    if (skipped > 0) [self showBatchAddResult:entries.count skipped:skipped];
}

- (void)showBatchAddResult:(NSUInteger)added skipped:(NSUInteger)skipped {
    NSString *message = added > 0
        ? [NSString stringWithFormat:LOCALIZED(@"BATCH_ADD_RESULT"), (unsigned long)added, (unsigned long)skipped]
        : LOCALIZED(@"BATCH_ADD_ALL_DUPLICATES");
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:nil message:message
                                                                 preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:LOCALIZED(@"ANSWER_OK") style:UIAlertActionStyleDefault handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}

#pragma mark - Search

- (void)updateSearchResultsForSearchController:(UISearchController *)controller {
    NSString *query = controller.searchBar.text;
    self.isSearching = [query stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet].length > 0;
    if (self.isSearching) {
        NSArray *hits = DXActionsMatchingQuery(self.linkActions, query, ^NSString *(NSDictionary *entry) {
            NSString *type = [entry[kCustomActionTypeKey] isKindOfClass:NSString.class] ? entry[kCustomActionTypeKey] : nil;
            return type ? [DXPLinkActionEditorController displayNameForType:type] : nil;
        });
        NSMutableArray<NSNumber *> *indexes = [NSMutableArray array];
        [self.linkActions enumerateObjectsUsingBlock:^(NSDictionary *entry, NSUInteger index, BOOL *stop) {
            if ([hits containsObject:entry]) [indexes addObject:@(index)];
        }];
        self.searchIndexes = indexes;
    } else {
        self.searchIndexes = @[];
    }
    [self.tableView reloadData];
}

@end
