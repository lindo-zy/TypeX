#import "DXPCustomActionViewController.h"
#import "DXPLinkActionEditorController.h"
#import "../DXHelper.h"
#import "../common.h"

static NSBundle *tweakBundle;

@interface DXPCustomActionViewController ()
@property (nonatomic, strong) NSMutableArray<NSMutableDictionary *> *linkActions;
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
        [strongSelf.tableView reloadRowsAtIndexPaths:@[[NSIndexPath indexPathForRow:row inSection:1]]
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
    if (indexPath.section == 1) [self pushEditorForCustomRow:indexPath.row];
}

#pragma mark - Table view

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    return 2;
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    return section == 0 ? LOCALIZED(@"ACTION") : LOCALIZED(@"CUSTOM_ACTIONS");
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return section == 0 ? self.fullOrder.count : self.linkActions.count + 1;
}

- (CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath {
    return 44;
}

- (UITableViewCell *)builtInCellForIndexPath:(NSIndexPath *)indexPath {
    UITableViewCell *cell = [self.tableView dequeueReusableCellWithIdentifier:@"TypeXLPItemCell" forIndexPath:indexPath];
    NSString *selector = [DXHelper actionNameFromArray:self.fullOrder atIndex:indexPath.row];
    cell.accessoryType = [self.selectedSelector isEqualToString:selector]
        ? UITableViewCellAccessoryCheckmark : UITableViewCellAccessoryNone;
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
    UIImage *image = [UIImage systemImageNamed:(icon.length ? icon : @"link")];
    cell.imageView.image = image ?: [UIImage systemImageNamed:@"link"];
    cell.accessoryType = [self.selectedSelector isEqualToString:selector]
        ? UITableViewCellAccessoryCheckmark : UITableViewCellAccessoryNone;
    cell.accessoryView = nil;
    cell.editingAccessoryView = nil;
    return cell;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    if (indexPath.section == 0) return [self builtInCellForIndexPath:indexPath];
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
    if (indexPath.section == 1 && indexPath.row >= (NSInteger)self.linkActions.count) {
        NSString *selector = [kLinkActionSelectorPrefix stringByAppendingString:NSUUID.UUID.UUIDString];
        NSMutableDictionary *entry = [@{
            @"selector": selector,
            @"name": LOCALIZED(@"DEFAULT_BUTTON_NAME"),
            @"icon": @"link",
            @"link": @"",
        } mutableCopy];
        [self.linkActions addObject:entry];
        [self persistLinkActions];
        NSIndexPath *newPath = [NSIndexPath indexPathForRow:self.linkActions.count - 1 inSection:1];
        [tableView insertRowsAtIndexPaths:@[newPath] withRowAnimation:UITableViewRowAnimationAutomatic];
        [self pushEditorForCustomRow:newPath.row];
        return;
    }

    NSString *selector = indexPath.section == 0
        ? [DXHelper actionNameFromArray:self.fullOrder atIndex:indexPath.row]
        : self.linkActions[indexPath.row][@"selector"];
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

#pragma mark - Edit and delete

- (BOOL)tableView:(UITableView *)tableView canEditRowAtIndexPath:(NSIndexPath *)indexPath {
    return indexPath.section == 1 && indexPath.row < (NSInteger)self.linkActions.count;
}

- (UITableViewCellEditingStyle)tableView:(UITableView *)tableView editingStyleForRowAtIndexPath:(NSIndexPath *)indexPath {
    return indexPath.section == 1 && indexPath.row < (NSInteger)self.linkActions.count
        ? UITableViewCellEditingStyleDelete : UITableViewCellEditingStyleNone;
}

- (void)tableView:(UITableView *)tableView commitEditingStyle:(UITableViewCellEditingStyle)editingStyle forRowAtIndexPath:(NSIndexPath *)indexPath {
    if (editingStyle != UITableViewCellEditingStyleDelete || indexPath.section != 1 ||
        indexPath.row >= (NSInteger)self.linkActions.count) return;
    NSString *selector = self.linkActions[indexPath.row][@"selector"];
    [self.linkActions removeObjectAtIndex:indexPath.row];
    self.prefs[kLinkActionskey] = self.linkActions;
    [self removeReferencesToSelector:selector fromPreferences:self.prefs];
    if ([self.selectedSelector isEqualToString:selector]) self.selectedSelector = nil;
    [self writePreferences];
    [tableView deleteRowsAtIndexPaths:@[indexPath] withRowAnimation:UITableViewRowAnimationAutomatic];
}

- (UISwipeActionsConfiguration *)tableView:(UITableView *)tableView leadingSwipeActionsConfigurationForRowAtIndexPath:(NSIndexPath *)indexPath {
    if (indexPath.section != 1 || indexPath.row >= (NSInteger)self.linkActions.count) return nil;
    __weak typeof(self) weakSelf = self;
    UIContextualAction *edit = [UIContextualAction contextualActionWithStyle:UIContextualActionStyleNormal
                                                                        title:LOCALIZED(@"EDIT")
                                                                      handler:^(__unused UIContextualAction *action,
                                                                                __unused UIView *sourceView,
                                                                                void (^completionHandler)(BOOL)) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        [strongSelf pushEditorForCustomRow:indexPath.row];
        completionHandler(strongSelf != nil);
    }];
    edit.backgroundColor = [UIColor systemBlueColor];
    return [UISwipeActionsConfiguration configurationWithActions:@[edit]];
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
}

@end
