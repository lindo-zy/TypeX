#import "DXPCustomActionsController.h"
#import "DXPLinkActionEditorController.h"
#import "../DXHelper.h"
#import "../common.h"

static NSBundle *tweakBundle;

// Standalone 自定义动作 management page, laid out after the KayokoX reference:
// a 已选择 group listing every action as a large icon + name + detail row with
// a disclosure chevron, a 选择动作 group of fixed type entries that start the
// add flow, an 编辑/完成 nav button toggling delete mode, and usage-hint
// footers under both groups.

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

@implementation DXPCustomActionsController

static NSInteger const DXSectionSelected = 0;
static NSInteger const DXSectionAddType = 1;

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
}

- (void)reloadDataKeepingSelection {
    [self.tableView reloadData];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [self reloadPreferences];
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

#pragma mark - Table view

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    return 2;
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    return section == DXSectionSelected ? LOCALIZED(@"SELECTED") : LOCALIZED(@"CHOOSE_ACTION");
}

- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section {
    if (section == DXSectionSelected) {
        return [NSString stringWithFormat:@"• %@\n• %@",
                LOCALIZED(@"MANAGE_HINT_TAP_EDIT"), LOCALIZED(@"MANAGE_HINT_EDIT_DELETE")];
    }
    return LOCALIZED(@"ADD_TYPE_HINT");
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    if (section == DXSectionSelected) return MAX(1, (NSInteger)self.linkActions.count);
    return 4;
}

- (CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath {
    return (indexPath.section == DXSectionSelected && self.linkActions.count > 0) ? 60.0 : 44.0;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    if (indexPath.section == DXSectionAddType) return [self typeCellForIndexPath:indexPath];
    if (self.linkActions.count == 0) {
        UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"DXPManagedEmptyCell" forIndexPath:indexPath];
        cell.textLabel.text = LOCALIZED(@"NO_CUSTOM_ACTIONS");
        cell.textLabel.textColor = [UIColor secondaryLabelColor];
        cell.detailTextLabel.text = nil;
        cell.imageView.image = nil;
        cell.accessoryType = UITableViewCellAccessoryNone;
        cell.selectionStyle = UITableViewCellSelectionStyleNone;
        return cell;
    }
    return [self actionCellForIndexPath:indexPath];
}

- (UITableViewCell *)actionCellForIndexPath:(NSIndexPath *)indexPath {
    UITableViewCell *cell = [self.tableView dequeueReusableCellWithIdentifier:@"DXPManagedActionCell" forIndexPath:indexPath];
    NSDictionary *entry = self.linkActions[indexPath.row];
    NSString *type = [entry[kCustomActionTypeKey] isKindOfClass:[NSString class]] ? entry[kCustomActionTypeKey] : @"";
    NSString *name = [entry[@"name"] isKindOfClass:[NSString class]] ? entry[@"name"] : @"";
    NSString *link = [entry[@"link"] isKindOfClass:[NSString class]] ? entry[@"link"] : @"";
    NSString *icon = [entry[@"icon"] isKindOfClass:[NSString class]] ? entry[@"icon"] : @"";

    cell.textLabel.text = name.length ? name : LOCALIZED(@"DEFAULT_BUTTON_NAME");
    cell.detailTextLabel.text = link.length ? link : [DXPLinkActionEditorController displayNameForType:type];
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
    NSString *type = [self typeAtIndex:indexPath.row];
    cell.textLabel.text = [DXPLinkActionEditorController displayNameForType:type];
    cell.textLabel.textColor = [UIColor labelColor];
    cell.detailTextLabel.text = nil;
    cell.imageView.image = [UIImage systemImageNamed:[DXPLinkActionEditorController defaultIconForType:type]];
    cell.imageView.tintColor = [UIColor systemBlueColor];
    cell.accessoryType = UITableViewCellAccessoryNone;
    cell.editingAccessoryType = UITableViewCellAccessoryNone;
    return cell;
}

- (NSString *)typeAtIndex:(NSInteger)row {
    static NSArray<NSString *> *types;
    if (!types) types = @[
        kCustomActionTypeURLScheme,
        kCustomActionTypeText,
        kCustomActionTypeURL,
        kCustomActionTypeOpenApp,
    ];
    return types[row];
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    if (indexPath.section == DXSectionAddType) {
        [self startAddFlowForType:[self typeAtIndex:indexPath.row]];
        return;
    }
    if (self.linkActions.count == 0) return;
    if (tableView.editing) {
        // Per the reference layout: tapping a row in edit mode deletes it.
        [self tableView:tableView commitEditingStyle:UITableViewCellEditingStyleDelete forRowAtIndexPath:indexPath];
        return;
    }
    [self pushEditorForCustomRow:indexPath.row];
}

#pragma mark - Edit and delete

- (BOOL)tableView:(UITableView *)tableView canEditRowAtIndexPath:(NSIndexPath *)indexPath {
    return indexPath.section == DXSectionSelected && indexPath.row < (NSInteger)self.linkActions.count;
}

- (UITableViewCellEditingStyle)tableView:(UITableView *)tableView editingStyleForRowAtIndexPath:(NSIndexPath *)indexPath {
    return [self tableView:tableView canEditRowAtIndexPath:indexPath]
        ? UITableViewCellEditingStyleDelete : UITableViewCellEditingStyleNone;
}

- (void)tableView:(UITableView *)tableView commitEditingStyle:(UITableViewCellEditingStyle)editingStyle forRowAtIndexPath:(NSIndexPath *)indexPath {
    if (editingStyle != UITableViewCellEditingStyleDelete || indexPath.section != DXSectionSelected ||
        indexPath.row >= (NSInteger)self.linkActions.count) return;
    NSString *selector = self.linkActions[indexPath.row][@"selector"];
    [self.linkActions removeObjectAtIndex:indexPath.row];
    self.prefs[kLinkActionskey] = self.linkActions;
    [self removeReferencesToSelector:selector fromPreferences:self.prefs];
    [self writePreferences];
    if (self.linkActions.count == 0 && !self.tableView.editing) {
        [self.tableView reloadData];
    } else {
        [tableView deleteRowsAtIndexPaths:@[indexPath] withRowAnimation:UITableViewRowAnimationAutomatic];
    }
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

@end
