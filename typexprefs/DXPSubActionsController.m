#import "DXPSubActionsController.h"
#import "DXPSubActionPickerController.h"
#import "../DXHelper.h"
#import "../common.h"

static NSBundle *tweakBundle;

// Leading inset of every row's content: room for the editing minus control.
// Applied through layout margins (with the system editing indent disabled) so
// the "添加" row and the sub-action rows line up in edit mode.
static CGFloat const DXSubActionContentLeading = 40.0;

// Because the table registers cell classes, dequeue never returns nil; the
// fixed row content is therefore built in the cell subclasses instead of
// cellForRowAtIndexPath.

@interface DXPSubActionCell : UITableViewCell
@end

@implementation DXPSubActionCell

- (instancetype)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)reuseIdentifier {
    if ((self = [super initWithStyle:style reuseIdentifier:reuseIdentifier])) {
        self.contentView.layoutMargins = UIEdgeInsetsMake(0, DXSubActionContentLeading, 0, 0);
    }
    return self;
}

@end

@interface DXPSubActionAddCell : UITableViewCell
@end

@implementation DXPSubActionAddCell

- (instancetype)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)reuseIdentifier {
    if ((self = [super initWithStyle:style reuseIdentifier:reuseIdentifier])) {
        UIImageView *plusView = [[UIImageView alloc] initWithImage:[UIImage systemImageNamed:@"plus.circle.fill"]];
        plusView.tintColor = [UIColor systemGreenColor];
        plusView.contentMode = UIViewContentModeScaleAspectFit;
        plusView.translatesAutoresizingMaskIntoConstraints = NO;
        [self.contentView addSubview:plusView];

        UILabel *addLabel = [[UILabel alloc] init];
        addLabel.text = LOCALIZED(@"ADD");
        addLabel.textColor = [UIColor systemBlueColor];
        addLabel.font = [UIFont systemFontOfSize:17];
        addLabel.translatesAutoresizingMaskIntoConstraints = NO;
        [self.contentView addSubview:addLabel];

        [NSLayoutConstraint activateConstraints:@[
            [plusView.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor constant:DXSubActionContentLeading],
            [plusView.centerYAnchor constraintEqualToAnchor:self.contentView.centerYAnchor],
            [plusView.widthAnchor constraintEqualToConstant:29],
            [plusView.heightAnchor constraintEqualToConstant:29],

            [addLabel.leadingAnchor constraintEqualToAnchor:plusView.trailingAnchor constant:10],
            [addLabel.centerYAnchor constraintEqualToAnchor:self.contentView.centerYAnchor],
            [addLabel.topAnchor constraintEqualToAnchor:self.contentView.topAnchor],
            [addLabel.bottomAnchor constraintEqualToAnchor:self.contentView.bottomAnchor],
        ]];
    }
    return self;
}

@end

@interface DXPSubActionsController ()
// In-memory copy of this button's sub-action entries; persisted on every
// add/delete/move/selection.
@property (nonatomic, strong) NSMutableArray<NSMutableDictionary *> *entries;
@end

@implementation DXPSubActionsController

#pragma mark - Storage

// Sub-actions of all buttons live in one store for the toolbar configuration;
// each entry is {identifier, selector} and array order is execution order.
- (NSString *)subActionsKey {
    return DXScopedPreferenceKey(kSubActionskey, self.configuration ?: @"bottom");
}

- (NSMutableArray<NSMutableDictionary *> *)entriesForIdentifier {
    NSMutableArray<NSMutableDictionary *> *entries = [NSMutableArray array];
    NSDictionary *prefs = [[DXPrefsManager sharedInstance] readPrefs];
    for (NSDictionary *entry in prefs[self.subActionsKey]) {
        if ([entry isKindOfClass:[NSDictionary class]] && [entry[@"identifier"] isEqual:self.identifier]) {
            [entries addObject:[entry mutableCopy]];
        }
    }
    return entries;
}

- (void)writeEntries:(NSArray<NSDictionary *> *)entries {
    NSMutableDictionary *prefs = [[[DXPrefsManager sharedInstance] readPrefs] mutableCopy] ?: [NSMutableDictionary dictionary];
    NSString *key = self.subActionsKey;

    NSMutableArray *updated = [NSMutableArray array];
    for (NSDictionary *entry in prefs[key]) {
        // Drop this button's entries, keep every other button's untouched.
        if (![entry isKindOfClass:[NSDictionary class]] || ![entry[@"identifier"] isEqual:self.identifier]) {
            [updated addObject:entry];
        }
    }
    [updated addObjectsFromArray:entries];
    prefs[key] = updated;
    [[DXPrefsManager sharedInstance] writePrefs:prefs];

    CFStringRef notificationName = (__bridge CFStringRef)kPrefsChangedIdentifier;
    if (notificationName) {
        CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(), notificationName, NULL, NULL, YES);
    }
}

#pragma mark - Picker navigation

- (void)pushPickerForRow:(NSInteger)row {
    if (row >= (NSInteger)self.entries.count) return;

    DXPSubActionPickerController *picker = [[DXPSubActionPickerController alloc] init];
    picker.fullOrder = self.fullOrder;
    picker.selectedSelector = self.entries[row][@"selector"];
    picker.title = LOCALIZED(@"CHOOSE_ACTION");

    __weak typeof(self) weakSelf = self;
    [picker setCompletion:^(NSString *selector) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf || row >= (NSInteger)strongSelf.entries.count) return;
        strongSelf.entries[row][@"selector"] = selector ?: @"";
        [strongSelf writeEntries:strongSelf.entries];
        [strongSelf.tableView reloadRowsAtIndexPaths:@[[NSIndexPath indexPathForRow:row inSection:0]]
                                    withRowAnimation:UITableViewRowAnimationNone];
    }];

    [picker setRootController:[self rootController]];
    [picker setParentController:[self parentController]];
    [self pushController:picker];
}

- (void)infoTapped:(UIButton *)sender {
    // Walk up from the button to its cell to recover the row.
    UIView *view = sender;
    while (view && ![view isKindOfClass:[UITableViewCell class]]) view = view.superview;
    NSIndexPath *indexPath = [self.tableView indexPathForCell:(UITableViewCell *)view];
    if (!indexPath) return;
    [self pushPickerForRow:indexPath.row];
}

- (NSDictionary *)linkActionForSelector:(NSString *)selector {
    if (!DXIsLinkActionSelector(selector)) return nil;
    NSDictionary *prefs = [[DXPrefsManager sharedInstance] readPrefs];
    for (NSDictionary *entry in prefs[kLinkActionskey]) {
        if ([entry isKindOfClass:[NSDictionary class]] && [entry[@"selector"] isEqual:selector]) return entry;
    }
    return nil;
}

// Built-in actions use localized selector names; link actions use the name
// configured by the user. Never feed a private link-action selector through
// the localization helper, otherwise it renders as LONG___TYPEX_... .
- (NSString *)displayNameForSelector:(NSString *)selector {
    NSDictionary *linkAction = [self linkActionForSelector:selector];
    if (DXIsLinkActionSelector(selector)) {
        NSString *name = [linkAction[@"name"] isKindOfClass:[NSString class]] ? linkAction[@"name"] : @"";
        return name.length ? name : LOCALIZED(@"DEFAULT_BUTTON_NAME");
    }
    return [DXHelper localizedStringForActionNamed:selector shortName:NO bundle:tweakBundle];
}

- (UIImage *)displayImageForSelector:(NSString *)selector {
    NSDictionary *linkAction = [self linkActionForSelector:selector];
    if (DXIsLinkActionSelector(selector)) {
        NSString *icon = [linkAction[@"icon"] isKindOfClass:[NSString class]] ? linkAction[@"icon"] : @"";
        UIImage *image = [UIImage systemImageNamed:(icon.length ? icon : @"link")];
        return image ?: [UIImage systemImageNamed:@"link"];
    }

    for (NSUInteger index = 0; index < self.fullOrder.count; index++) {
        if ([[DXHelper actionNameFromArray:self.fullOrder atIndex:index] isEqualToString:selector]) {
            return [DXHelper imageFromArray:self.fullOrder atIndex:index withSystemColor:YES completion:nil];
        }
    }
    return nil;
}

#pragma mark - Table view

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    return 1;
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    return LOCALIZED(@"ADD_SUB_ACTION");
}

// Fixed standard row height: the add cell pins its label to the contentView's
// top and bottom, so self-sizing would otherwise squash the row down to the
// text height and clip the plus icon.
- (CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath {
    return 44;
}

// The last row is the fixed "添加" row.
- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return self.entries.count + 1;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    if (indexPath.row >= (NSInteger)self.entries.count) {
        return [tableView dequeueReusableCellWithIdentifier:@"DXPSubActionAddCell" forIndexPath:indexPath];
    }

    DXPSubActionCell *cell = [tableView dequeueReusableCellWithIdentifier:@"DXPSubActionCell" forIndexPath:indexPath];

    // The info button lives in the editing accessory slot because the table is
    // permanently in edit mode (the minus and the drag handle come from there).
    UIButton *infoButton = [UIButton buttonWithType:UIButtonTypeSystem];
    infoButton.tintColor = [UIColor systemOrangeColor];
    [infoButton setImage:[UIImage systemImageNamed:@"info.circle"] forState:UIControlStateNormal];
    infoButton.frame = CGRectMake(0, 0, 30, 30);
    [infoButton addTarget:self action:@selector(infoTapped:) forControlEvents:UIControlEventTouchUpInside];
    cell.editingAccessoryView = infoButton;

    NSString *selector = self.entries[indexPath.row][@"selector"];
    cell.textLabel.text = [selector isKindOfClass:[NSString class]] && selector.length > 0
        ? [self displayNameForSelector:selector]
        : LOCALIZED(@"SUB_ACTION");
    cell.imageView.image = [selector isKindOfClass:[NSString class]] && selector.length > 0
        ? [self displayImageForSelector:selector]
        : nil;
    return cell;
}

- (void)tableView:(UITableView *)tableView willDisplayCell:(UITableViewCell *)cell forRowAtIndexPath:(NSIndexPath *)indexPath {
    if (![cell isKindOfClass:[DXPSubActionCell class]]) return;
    // UIKit resets cell margins from the table defaults during layout, so the
    // fixed leading inset is re-applied here on every display pass.
    cell.preservesSuperviewLayoutMargins = NO;
    UIEdgeInsets insets = UIEdgeInsetsMake(0, DXSubActionContentLeading, 0, 0);
    cell.layoutMargins = insets;
    cell.contentView.layoutMargins = insets;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];

    if (indexPath.row >= (NSInteger)self.entries.count) {
        NSMutableDictionary *entry = [NSMutableDictionary dictionary];
        entry[@"identifier"] = self.identifier;
        entry[@"selector"] = @"";
        [self.entries addObject:entry];
        [self.tableView insertRowsAtIndexPaths:@[[NSIndexPath indexPathForRow:self.entries.count - 1 inSection:0]]
                              withRowAnimation:UITableViewRowAnimationAutomatic];
        [self writeEntries:self.entries];
        [self pushPickerForRow:(NSInteger)self.entries.count - 1];
        return;
    }

    [self pushPickerForRow:indexPath.row];
}

#pragma mark - Editing (delete + reorder)

- (UITableViewCellEditingStyle)tableView:(UITableView *)tableView editingStyleForRowAtIndexPath:(NSIndexPath *)indexPath {
    return indexPath.row < (NSInteger)self.entries.count ? UITableViewCellEditingStyleDelete : UITableViewCellEditingStyleNone;
}

- (BOOL)tableView:(UITableView *)tableView shouldIndentWhileEditingRowAtIndexPath:(NSIndexPath *)indexPath {
    // The system indent is replaced by the fixed layout margin above so the
    // add row and the sub-action rows align.
    return NO;
}

- (BOOL)tableView:(UITableView *)tableView canEditRowAtIndexPath:(NSIndexPath *)indexPath {
    return YES;
}

- (BOOL)tableView:(UITableView *)tableView canMoveRowAtIndexPath:(NSIndexPath *)indexPath {
    return indexPath.row < (NSInteger)self.entries.count;
}

- (NSIndexPath *)tableView:(UITableView *)tableView targetIndexPathForMoveFromRowAtIndexPath:(NSIndexPath *)sourceIndexPath toProposedIndexPath:(NSIndexPath *)proposedDestinationIndexPath {
    // Never drop onto the trailing add row.
    if (proposedDestinationIndexPath.row >= (NSInteger)self.entries.count) {
        return [NSIndexPath indexPathForRow:self.entries.count - 1 inSection:0];
    }
    return proposedDestinationIndexPath;
}

- (void)tableView:(UITableView *)tableView commitEditingStyle:(UITableViewCellEditingStyle)editingStyle forRowAtIndexPath:(NSIndexPath *)indexPath {
    if (editingStyle != UITableViewCellEditingStyleDelete) return;
    if (indexPath.row >= (NSInteger)self.entries.count) return;

    [self.entries removeObjectAtIndex:indexPath.row];
    [tableView deleteRowsAtIndexPaths:@[indexPath] withRowAnimation:UITableViewRowAnimationAutomatic];
    [self writeEntries:self.entries];
}

- (void)tableView:(UITableView *)tableView moveRowAtIndexPath:(NSIndexPath *)sourceIndexPath toIndexPath:(NSIndexPath *)destinationIndexPath {
    if (sourceIndexPath.row >= (NSInteger)self.entries.count || destinationIndexPath.row >= (NSInteger)self.entries.count) return;

    NSMutableDictionary *entry = self.entries[sourceIndexPath.row];
    [self.entries removeObjectAtIndex:sourceIndexPath.row];
    [self.entries insertObject:entry atIndex:destinationIndexPath.row];
    [self writeEntries:self.entries];
}

#pragma mark - View lifecycle

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    // The unified action picker can delete a custom action globally. Reload so
    // a sub-action that referenced the deleted definition disappears at once.
    self.entries = [self entriesForIdentifier];
    [self.tableView reloadData];
}

- (void)viewDidLoad {
    tweakBundle = [NSBundle bundleWithPath:bundlePath];
    [tweakBundle load];
    [super viewDidLoad];

    self.entries = [self entriesForIdentifier];

    self.tableView = [[UITableView alloc] initWithFrame:CGRectMake(0, 0, self.view.frame.size.width, self.view.frame.size.height)
                                                  style:UITableViewStyleInsetGrouped];
    self.tableView.delegate = self;
    self.tableView.dataSource = self;
    [self.tableView setAutoresizingMask:UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight];
    [self.tableView registerClass:[DXPSubActionCell class] forCellReuseIdentifier:@"DXPSubActionCell"];
    [self.tableView registerClass:[DXPSubActionAddCell class] forCellReuseIdentifier:@"DXPSubActionAddCell"];
    // Edit mode supplies the delete minus and the drag handle for every row.
    [self.tableView setEditing:YES];
    self.tableView.allowsSelectionDuringEditing = YES;

    self.view = self.tableView;
}

@end
