#import "DXPCustomActionViewController.h"
#import "DXPSubActionPickerController.h"
#import "DXPLinkActionEditorController.h"
#import "../DXHelper.h"
#import "../common.h"

static NSBundle *tweakBundle;

@interface DXPCustomActionViewController ()
// Live multi-select state; only maintained while allowsMultipleSelection is on.
@property (nonatomic, strong) NSMutableSet<NSString *> *pickedSelectors;
@end

@implementation DXPCustomActionViewController

#pragma mark - Storage

- (void)reloadPreferences {
    self.prefs = [[[DXPrefsManager sharedInstance] readPrefs] mutableCopy] ?: [NSMutableDictionary dictionary];
    self.linkActions = [NSMutableArray array];
    for (NSDictionary *entry in self.prefs[kLinkActionskey]) {
        if (![entry isKindOfClass:[NSDictionary class]]) continue;
        NSString *selector = entry[@"selector"];
        if (!DXIsLinkActionSelector(selector)) continue;
        [self.linkActions addObject:[entry mutableCopy]];
    }

    if (self.selectionManagedExternally) return;
    self.selectedSelector = nil;
    NSArray *entries = self.prefs[self.keyID];
    if (![entries isKindOfClass:[NSArray class]]) return;
    for (NSDictionary *entry in entries) {
        if (![entry isKindOfClass:[NSDictionary class]] || ![entry[@"identifier"] isEqual:self.identifier]) continue;
        NSString *selector = entry[@"selector2"] ?: entry[@"selector"];
        if ([selector isKindOfClass:[NSString class]] && selector.length > 0) self.selectedSelector = selector;
        break;
    }
}

- (void)writePreferences {
    [[DXPrefsManager sharedInstance] writePrefs:self.prefs];
}

- (void)persistLinkActions {
    self.prefs[kLinkActionskey] = self.linkActions;
    [self writePreferences];
}

- (void)persistSelectedSelector:(NSString *)selector {
    NSMutableArray *entries = [self.prefs[self.keyID] isKindOfClass:[NSArray class]]
        ? [self.prefs[self.keyID] mutableCopy] : [NSMutableArray array];
    NSUInteger found = NSNotFound;
    for (NSUInteger index = 0; index < entries.count; index++) {
        NSDictionary *candidate = entries[index];
        if ([candidate isKindOfClass:[NSDictionary class]] && [candidate[@"identifier"] isEqual:self.identifier]) {
            found = index;
            break;
        }
    }

    if (selector.length == 0) {
        if (found != NSNotFound) [entries removeObjectAtIndex:found];
    } else {
        NSMutableDictionary *entry = found != NSNotFound ? [entries[found] mutableCopy] : [NSMutableDictionary dictionary];
        entry[@"identifier"] = self.identifier;
        entry[@"selector"] = selector;
        [entry removeObjectForKey:@"selector2"];
        if (found != NSNotFound) entries[found] = entry;
        else [entries addObject:entry];
    }

    self.selectedSelector = selector.length ? selector : nil;
    self.prefs[self.keyID] = entries;
    [self writePreferences];
}

// A deleted definition must not remain selected by another button or gesture.
- (void)removeReferencesToSelector:(NSString *)selector fromPreferences:(NSMutableDictionary *)preferences {
    NSMutableSet<NSString *> *keys = [NSMutableSet set];
    for (NSString *configuration in @[@"bottom", @"top"]) {
        for (NSInteger gesture = DXShortcutGestureLongPress; gesture <= DXShortcutGestureTap; gesture++) {
            [keys addObject:DXCustomActionsKeyForGesture((int)gesture, configuration)];
        }
        [keys addObject:DXScopedPreferenceKey(kSubActionskey, configuration)];
    }

    for (NSString *key in keys) {
        NSArray *stored = preferences[key];
        if (![stored isKindOfClass:[NSArray class]]) continue;
        NSMutableArray *updated = [NSMutableArray array];
        for (NSDictionary *value in stored) {
            if (![value isKindOfClass:[NSDictionary class]]) {
                [updated addObject:value];
                continue;
            }
            BOOL selected = [value[@"selector"] isEqual:selector] || [value[@"selector2"] isEqual:selector];
            if (!selected) [updated addObject:value];
        }
        preferences[key] = updated;
    }
}

#pragma mark - Action editor

- (void)startAddFlowForType:(NSString *)type {
    NSMutableDictionary *entry = [@{
        @"selector": [kLinkActionSelectorPrefix stringByAppendingString:NSUUID.UUID.UUIDString],
        @"name": LOCALIZED(@"DEFAULT_BUTTON_NAME"),
        @"icon": @"link",
        @"link": @"",
        kCustomActionTypeKey: type,
    } mutableCopy];
    if ([type isEqualToString:kCustomActionTypeURL]) entry[kCustomActionInAppKey] = @YES;

    DXPLinkActionEditorController *editor = [[DXPLinkActionEditorController alloc] init];
    editor.entry = entry;
    __weak typeof(self) weakSelf = self;
    editor.completion = ^(NSDictionary *savedEntry) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf) return;
        // The management page shows one placeholder row while the list is
        // empty, so the first added action replaces that row 1:1 — inserting
        // there contradicts the data source and crashes the update.
        BOOL listWasEmpty = strongSelf.linkActions.count == 0;
        [strongSelf.linkActions addObject:[savedEntry mutableCopy]];
        [strongSelf persistLinkActions];
        if (listWasEmpty) {
            [strongSelf.tableView reloadData];
            return;
        }
        NSIndexPath *newPath = [NSIndexPath indexPathForRow:strongSelf.linkActions.count - 1
                                                  inSection:strongSelf.customActionsSection];
        [strongSelf.tableView insertRowsAtIndexPaths:@[newPath] withRowAnimation:UITableViewRowAnimationAutomatic];
    };
    [editor setRootController:[self rootController]];
    [editor setParentController:[self parentController]];
    [self pushController:editor];
}

// 添加 flow: the type is chosen first (URL Scheme preselected as the first
// entry of the chooser), then startAddFlowForType: runs the pending-entry
// editor. Nothing touches the store here — the action joins the list (and the
// prefs) only when the editor's 保存 reports the finished entry, so backing out
// of the editor never leaves a half-configured row behind.
- (void)presentAddActionTypeChooser {
    __weak typeof(self) weakSelf = self;
    [DXPLinkActionEditorController presentTypeChooserFromController:self
                                                        currentType:kCustomActionTypeURLScheme
                                                         completion:^(NSString *type) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf || type.length == 0) return;
        [strongSelf startAddFlowForType:type];
    }];
}

// In customActionsOnly mode the custom-actions group is the single section 0;
// otherwise it sits behind the built-in actions as section 1.
- (NSInteger)customActionsSection {
    return self.customActionsOnly ? 0 : 1;
}

- (void)pushEditorForCustomRow:(NSInteger)row {
    if (row < 0 || row >= (NSInteger)self.linkActions.count) return;
    DXPLinkActionEditorController *editor = [[DXPLinkActionEditorController alloc] init];
    editor.entry = [self.linkActions[row] mutableCopy];

    __weak typeof(self) weakSelf = self;
    editor.completion = ^(NSDictionary *entry) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf || row >= (NSInteger)strongSelf.linkActions.count) return;
        strongSelf.linkActions[row] = [entry mutableCopy];
        [strongSelf persistLinkActions];
        [strongSelf.tableView reloadRowsAtIndexPaths:@[[NSIndexPath indexPathForRow:row inSection:strongSelf.customActionsSection]]
                                    withRowAnimation:UITableViewRowAnimationNone];
    };
    [editor setRootController:[self rootController]];
    [editor setParentController:[self parentController]];
    [self pushController:editor];
}

- (void)infoTapped:(UIButton *)sender {
    UIView *view = sender;
    while (view && ![view isKindOfClass:[UITableViewCell class]]) view = view.superview;
    NSIndexPath *indexPath = [self.tableView indexPathForCell:(UITableViewCell *)view];
    if (self.customActionsOnly && indexPath.section == self.customActionsSection) [self pushEditorForCustomRow:indexPath.row];
}

#pragma mark - Table view

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    return self.customActionsOnly ? 1 : 2;
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    if (section != self.customActionsSection) return LOCALIZED(@"ACTION");
    // Picker modes hide the whole group when there is nothing to select.
    if (!self.customActionsOnly && self.linkActions.count == 0) return nil;
    return LOCALIZED(@"CUSTOM_ACTIONS");
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    if (section != self.customActionsSection) return self.fullOrder.count;
    // The trailing "添加" row belongs to the management page only; pickers
    // list custom actions for selection without offering mutations.
    return self.linkActions.count + (self.customActionsOnly ? 1 : 0);
}

- (CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath {
    return 44;
}

- (UITableViewCell *)builtInCellForIndexPath:(NSIndexPath *)indexPath {
    UITableViewCell *cell = [self.tableView dequeueReusableCellWithIdentifier:@"TypeXLPItemCell" forIndexPath:indexPath];
    NSString *selector = [DXHelper actionNameFromArray:self.fullOrder atIndex:indexPath.row];
    BOOL checked = self.allowsMultipleSelection
        ? [self.pickedSelectors containsObject:selector]
        : [self.selectedSelector isEqualToString:selector];
    cell.accessoryType = checked ? UITableViewCellAccessoryCheckmark : UITableViewCellAccessoryNone;
    cell.accessoryView = nil;
    cell.editingAccessoryView = nil;
    cell.textLabel.text = [DXHelper localizedStringForActionNamed:selector shortName:NO bundle:tweakBundle];
    cell.imageView.image = [DXHelper imageFromArray:self.fullOrder atIndex:indexPath.row withSystemColor:YES completion:nil];
    return cell;
}

- (UITableViewCell *)customCellForIndexPath:(NSIndexPath *)indexPath {
    UITableViewCell *cell = [self.tableView dequeueReusableCellWithIdentifier:@"TypeXCustomLinkActionCell" forIndexPath:indexPath];
    NSDictionary *entry = self.linkActions[indexPath.row];
    NSString *selector = entry[@"selector"];
    NSString *name = [entry[@"name"] isKindOfClass:[NSString class]] ? entry[@"name"] : @"";
    NSString *icon = [entry[@"icon"] isKindOfClass:[NSString class]] ? entry[@"icon"] : @"";
    cell.textLabel.text = name.length ? name : LOCALIZED(@"DEFAULT_BUTTON_NAME");
    cell.imageView.image = [DXHelper imageForIconConfig:icon defaultSymbolName:@"link"]
        ?: [UIImage systemImageNamed:@"link"];
    BOOL checked = self.allowsMultipleSelection
        ? [self.pickedSelectors containsObject:selector]
        : [self.selectedSelector isEqualToString:selector];
    cell.accessoryType = checked ? UITableViewCellAccessoryCheckmark : UITableViewCellAccessoryNone;
    cell.accessoryView = nil;
    cell.editingAccessoryView = nil;
    return cell;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    if (indexPath.section != self.customActionsSection) return [self builtInCellForIndexPath:indexPath];
    if (indexPath.row >= (NSInteger)self.linkActions.count) {
        UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"DXPActionAddCell" forIndexPath:indexPath];
        cell.textLabel.text = LOCALIZED(@"ADD");
        cell.textLabel.textColor = [UIColor systemBlueColor];
        cell.imageView.image = [UIImage systemImageNamed:@"plus.circle.fill"];
        cell.imageView.tintColor = [UIColor systemGreenColor];
        cell.accessoryType = UITableViewCellAccessoryNone;
        return cell;
    }
    return [self customCellForIndexPath:indexPath];
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    // Only the management page carries the "添加" row, so this branch is
    // unreachable in picker modes (they are select-only for custom actions).
    if (indexPath.section == self.customActionsSection && indexPath.row >= (NSInteger)self.linkActions.count) {
        [self presentAddActionTypeChooser];
        return;
    }

    // Management page: tapping a custom action edits it instead of selecting.
    if (self.customActionsOnly) {
        [self pushEditorForCustomRow:indexPath.row];
        return;
    }

    if (self.allowsMultipleSelection) {
        NSString *selector = indexPath.section == self.customActionsSection
            ? self.linkActions[indexPath.row][@"selector"]
            : [DXHelper actionNameFromArray:self.fullOrder atIndex:indexPath.row];
        if ([self.pickedSelectors containsObject:selector]) {
            [self.pickedSelectors removeObject:selector];
        } else {
            [self.pickedSelectors addObject:selector];
        }
        [tableView reloadRowsAtIndexPaths:@[indexPath] withRowAnimation:UITableViewRowAnimationNone];
        return;
    }

    NSString *selector = indexPath.section == self.customActionsSection
        ? self.linkActions[indexPath.row][@"selector"]
        : [DXHelper actionNameFromArray:self.fullOrder atIndex:indexPath.row];
    NSString *oldSelector = self.selectedSelector;

    if (self.selectionManagedExternally) {
        self.selectedSelector = selector;
        NSMutableArray *paths = [NSMutableArray arrayWithObject:indexPath];
        NSIndexPath *oldPath = [self indexPathForSelector:oldSelector];
        if (oldPath && ![oldPath isEqual:indexPath]) [paths addObject:oldPath];
        [tableView reloadRowsAtIndexPaths:paths withRowAnimation:UITableViewRowAnimationAutomatic];
        if (self.completion) self.completion(selector);
        [self.navigationController popViewControllerAnimated:YES];
        return;
    }

    [self persistSelectedSelector:[oldSelector isEqualToString:selector] ? nil : selector];

    NSMutableArray *paths = [NSMutableArray arrayWithObject:indexPath];
    NSIndexPath *oldPath = [self indexPathForSelector:oldSelector];
    if (oldPath && ![oldPath isEqual:indexPath]) [paths addObject:oldPath];
    [tableView reloadRowsAtIndexPaths:paths withRowAnimation:UITableViewRowAnimationAutomatic];
}

- (NSIndexPath *)indexPathForSelector:(NSString *)selector {
    if (selector.length == 0) return nil;
    for (NSUInteger row = 0; row < self.fullOrder.count; row++) {
        if ([[DXHelper actionNameFromArray:self.fullOrder atIndex:row] isEqualToString:selector]) {
            return [NSIndexPath indexPathForRow:row inSection:0];
        }
    }
    for (NSUInteger row = 0; row < self.linkActions.count; row++) {
        if ([self.linkActions[row][@"selector"] isEqual:selector]) return [NSIndexPath indexPathForRow:row inSection:1];
    }
    return nil;
}

#pragma mark - Multi-select (batch pick)

// Report picks in list order (built-ins first, then custom actions) so a
// batch append lands in the order the user saw on screen.
- (NSArray<NSString *> *)orderedPickedSelectors {
    NSMutableArray<NSString *> *ordered = [NSMutableArray array];
    for (NSUInteger row = 0; row < self.fullOrder.count; row++) {
        NSString *selector = [DXHelper actionNameFromArray:self.fullOrder atIndex:row];
        if ([self.pickedSelectors containsObject:selector]) [ordered addObject:selector];
    }
    for (NSDictionary *entry in self.linkActions) {
        NSString *selector = entry[@"selector"];
        if ([selector isKindOfClass:[NSString class]] && [self.pickedSelectors containsObject:selector]) [ordered addObject:selector];
    }
    return ordered;
}

- (void)confirmMultiSelection {
    if (self.multiSelectionCompletion) self.multiSelectionCompletion([self orderedPickedSelectors]);
    [self.navigationController popViewControllerAnimated:YES];
}

#pragma mark - Edit and delete

- (BOOL)tableView:(UITableView *)tableView canEditRowAtIndexPath:(NSIndexPath *)indexPath {
    return self.customActionsOnly && indexPath.section == self.customActionsSection &&
        indexPath.row < (NSInteger)self.linkActions.count;
}

- (UITableViewCellEditingStyle)tableView:(UITableView *)tableView editingStyleForRowAtIndexPath:(NSIndexPath *)indexPath {
    return self.customActionsOnly && indexPath.section == self.customActionsSection &&
        indexPath.row < (NSInteger)self.linkActions.count
        ? UITableViewCellEditingStyleDelete : UITableViewCellEditingStyleNone;
}

- (void)tableView:(UITableView *)tableView commitEditingStyle:(UITableViewCellEditingStyle)editingStyle forRowAtIndexPath:(NSIndexPath *)indexPath {
    if (editingStyle != UITableViewCellEditingStyleDelete || indexPath.section != self.customActionsSection ||
        indexPath.row >= (NSInteger)self.linkActions.count) return;
    NSString *selector = self.linkActions[indexPath.row][@"selector"];
    [self.linkActions removeObjectAtIndex:indexPath.row];
    self.prefs[kLinkActionskey] = self.linkActions;
    [self removeReferencesToSelector:selector fromPreferences:self.prefs];
    if ([self.selectedSelector isEqualToString:selector]) self.selectedSelector = nil;
    [self.pickedSelectors removeObject:selector];
    [self writePreferences];
    [tableView deleteRowsAtIndexPaths:@[indexPath] withRowAnimation:UITableViewRowAnimationAutomatic];
}

// Management page only: the picker keeps delete reachable through edit mode.
// There is no leading-swipe 编辑 any more — tapping a row already opens its
// editor.
- (UISwipeActionsConfiguration *)tableView:(UITableView *)tableView trailingSwipeActionsConfigurationForRowAtIndexPath:(NSIndexPath *)indexPath {
    if (!self.customActionsOnly || indexPath.section != self.customActionsSection ||
        indexPath.row >= (NSInteger)self.linkActions.count) return nil;
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

#pragma mark - Lifecycle

- (void)resetToDefault {
    if (self.selectionManagedExternally) return;
    [self persistSelectedSelector:nil];
    [self.tableView reloadData];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [self reloadPreferences];
    [self.tableView reloadData];
}

- (void)viewDidLoad {
    tweakBundle = [NSBundle bundleWithPath:bundlePath];
    [tweakBundle load];
    [super viewDidLoad];
    [self reloadPreferences];

    self.tableView = [[UITableView alloc] initWithFrame:self.view.bounds style:UITableViewStyleInsetGrouped];
    self.tableView.delegate = self;
    self.tableView.dataSource = self;
    self.tableView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    [self.tableView registerClass:[UITableViewCell class] forCellReuseIdentifier:@"TypeXLPItemCell"];
    [self.tableView registerClass:[UITableViewCell class] forCellReuseIdentifier:@"TypeXCustomLinkActionCell"];
    [self.tableView registerClass:[UITableViewCell class] forCellReuseIdentifier:@"DXPActionAddCell"];
    self.view = self.tableView;

    if (!self.selectionManagedExternally) {
        self.defaultBtn = [[UIBarButtonItem alloc] initWithTitle:LOCALIZED(@"DEFAULT")
                                                           style:UIBarButtonItemStylePlain
                                                          target:self
                                                          action:@selector(resetToDefault)];
        self.navigationItem.rightBarButtonItem = self.defaultBtn;
    }

    if (self.allowsMultipleSelection) {
        self.pickedSelectors = [NSMutableSet set];
        self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithTitle:LOCALIZED(@"DONE")
                                                                                  style:UIBarButtonItemStyleDone
                                                                                 target:self
                                                                                 action:@selector(confirmMultiSelection)];
    }
}

@end
