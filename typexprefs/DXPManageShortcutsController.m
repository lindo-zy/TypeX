#import "DXPManageShortcutsController.h"
#import "DXPGesturePickerController.h"
#import "../DXShortcutsGenerator.h"
#import "../DXHelper.h"

static NSBundle *tweakBundle;

#define kTestFieldHeaderHeight 78.0

static BOOL DXIsHiddenShortcutSelector(NSString *selector) {
    return ![DXShortcutsGenerator isVisibleShortcutSelector:selector];
}

static void DXAppendUniqueShortcuts(NSArray *shortcuts,
                                    NSMutableArray *destination,
                                    NSMutableSet *seenSelectors,
                                    NSUInteger limit) {
    for (id object in shortcuts) {
        if (destination.count >= limit) break;
        if (![object isKindOfClass:[NSDictionary class]]) continue;

        NSDictionary *shortcut = (NSDictionary *)object;
        NSString *selector = shortcut[@"selector"];
        // Draft buttons (saved without a tap action) carry a synthetic
        // selector and must survive normalization untouched.
        if (!DXIsDraftActionSelector(selector)) {
            if (![selector isKindOfClass:[NSString class]] ||
                DXIsHiddenShortcutSelector(selector) ||
                [seenSelectors containsObject:selector]) {
                continue;
            }
            [seenSelectors addObject:selector];
        }

        [destination addObject:shortcut];
    }
}


@implementation DXPManageShortcutsController

- (NSString *)scopedKey:(NSString *)bottomKey topKey:(NSString *)topKey {
    return self.topConfiguration ? topKey : bottomKey;
}

#pragma mark - Table view: configured buttons only

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    return 1;
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    return nil;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return [self.currentOrder[0] count];
}

- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section {
    return [NSString stringWithFormat:LOCALIZED(@"FOOTER_TOOLBAR_BUTTONS"), (int)maxshortcutpersection];
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"TypeXItemCell" forIndexPath:indexPath];

    if (cell == nil)
        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:@"TypeXItemCell"];

    if (self.currentOrder[0] == nil || indexPath.row >= [self.currentOrder[0] count])
        return cell;

    UIImage *image;
    NSString *label;

    dispatch_semaphore_t smp = dispatch_semaphore_create(0);
    __block BOOL isCustomImagePath = NO;
    __block BOOL isThirteen = NO;

    label = [DXHelper localizedStringForActionNamed:[DXHelper actionNameFromArray:self.currentOrder[0] atIndex:indexPath.row] shortName:NO bundle:tweakBundle];
    image = [DXHelper imageFromArray:self.currentOrder[0] atIndex:indexPath.row withSystemColor:YES completion:^(BOOL thirteen, BOOL customPath){
        isThirteen = thirteen;
        isCustomImagePath = customPath;
        dispatch_semaphore_signal(smp);
    }];
    dispatch_semaphore_wait(smp, DISPATCH_TIME_FOREVER);
    if (!isThirteen && isCustomImagePath){
        [cell.imageView setTintColor:[UIColor blackColor]];
    }

    NSDictionary *shortcutItem = self.currentOrder[indexPath.section][indexPath.row];

    // Per-shortcut overrides set in the button's own settings page: a custom
    // name replaces the localized label and a valid SF Symbol replaces the icon.
    NSString *customName = [DXHelper customNameForShortcutItem:shortcutItem];
    if (customName) label = customName;
    else if ([shortcutItem[@"label"] isKindOfClass:[NSString class]] && [(NSString *)shortcutItem[@"label"] length])
        label = shortcutItem[@"label"];
    NSString *customIcon = [DXHelper customIconForShortcutItem:shortcutItem];
    if (customIcon) image = [DXHelper imageForName:customIcon withSystemColor:YES completion:nil];

    cell.textLabel.text = label;
    cell.imageView.image = image;
    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath{
    DXPGesturePickerController *gesturePickerController = [[DXPGesturePickerController alloc] init];

    gesturePickerController.fullOrder = self.fullOrder;
    gesturePickerController.identifier = self.currentOrder[indexPath.section][indexPath.row][@"selector"];
    gesturePickerController.configuration = self.topConfiguration ? @"top" : @"bottom";
    NSDictionary *shortcutItem = self.currentOrder[indexPath.section][indexPath.row];
    // Draft buttons have a synthetic selector, so prefer the stored label.
    gesturePickerController.title = [DXHelper customNameForShortcutItem:shortcutItem]
        ?: [shortcutItem[@"label"] isKindOfClass:[NSString class]] && [(NSString *)shortcutItem[@"label"] length] ? shortcutItem[@"label"]
        : [DXHelper localizedStringForActionNamed:shortcutItem[@"selector"] shortName:NO bundle:tweakBundle];

    [gesturePickerController setRootController: [self rootController]];
    [gesturePickerController setParentController: [self parentController]];
    [self pushController:gesturePickerController];

    [tableView deselectRowAtIndexPath:indexPath animated:YES];
}

- (void)tableView:(UITableView *)tableView moveRowAtIndexPath:(NSIndexPath *)sourceIndexPath toIndexPath:(NSIndexPath *)destinationIndexPath {
    if (self.tableView == nil)
        return;

    NSString *objectToMove = [self.currentOrder[0] objectAtIndex:sourceIndexPath.row];
    [self.currentOrder[0] removeObjectAtIndex:sourceIndexPath.row];
    [self.currentOrder[0] insertObject:objectToMove atIndex:destinationIndexPath.row];
    [self.tableView reloadData];
    [self writeToFile];
}

- (BOOL)tableView:(UITableView *)tableView canMoveRowAtIndexPath:(NSIndexPath *)indexPath {
    return indexPath.section == 0;
}

- (BOOL)tableView:(UITableView *)tableView canEditRowAtIndexPath:(NSIndexPath *)indexPath{
    return indexPath.section == 0;
}

- (void)tableView:(UITableView *)tableView commitEditingStyle:(UITableViewCellEditingStyle)editingStyle forRowAtIndexPath:(NSIndexPath *)indexPath {
    if (editingStyle != UITableViewCellEditingStyleDelete || indexPath.section != 0) return;

    // Deleting forgets the button entirely: the entry leaves the toolbar and
    // its per-button gesture configuration is cleared with it.
    NSString *identifier = self.currentOrder[0][indexPath.row][@"selector"];
    [tableView beginUpdates];
    [self.currentOrder[0] removeObjectAtIndex:indexPath.row];
    [tableView deleteRowsAtIndexPaths:@[indexPath] withRowAnimation:UITableViewRowAnimationFade];
    [tableView endUpdates];
    [self removeCustomActionsForIdentifier:identifier];
    [self writeToFile];
}

- (UITableViewCellEditingStyle)tableView:(UITableView *)tableView editingStyleForRowAtIndexPath:(NSIndexPath *)indexPath {
    return indexPath.section == 0 ? UITableViewCellEditingStyleDelete : UITableViewCellEditingStyleNone;
}

- (BOOL)tableView:(UITableView *)tableView shouldIndentWhileEditingRowAtIndexPath:(NSIndexPath *)indexPath {
    return NO;
}

-(NSIndexPath *)tableView:(UITableView *)tableView targetIndexPathForMoveFromRowAtIndexPath:(NSIndexPath *)sourceIndexPath toProposedIndexPath:(NSIndexPath *)proposedDestinationIndexPath
{
    if( sourceIndexPath.section != proposedDestinationIndexPath.section )
    {
        return sourceIndexPath;
    }
    else
    {
        return proposedDestinationIndexPath;
    }
}

#pragma mark - Test input field

// A text field pinned above the list: tapping it pops the keyboard with the
// TypeX toolbar attached (the tweak loads into UIKit, Settings included), so
// freshly saved buttons can be tried without leaving the page.
- (void)buildTestFieldHeader {
    CGFloat width = CGRectGetWidth(self.tableView.bounds);
    UIView *header = [[UIView alloc] initWithFrame:CGRectMake(0, 0, width, kTestFieldHeaderHeight)];
    header.autoresizingMask = UIViewAutoresizingFlexibleWidth;

    UILabel *title = [[UILabel alloc] initWithFrame:CGRectMake(16, 12, MAX(0, width - 32), 18)];
    title.text = LOCALIZED(@"TEST_INPUT_FIELD");
    title.font = [UIFont systemFontOfSize:13 weight:UIFontWeightSemibold];
    title.textColor = [UIColor secondaryLabelColor];
    title.autoresizingMask = UIViewAutoresizingFlexibleWidth;
    [header addSubview:title];

    self.testInputField = [[UITextField alloc] initWithFrame:CGRectMake(16, 36, MAX(0, width - 32), 36)];
    self.testInputField.placeholder = LOCALIZED(@"TEST_INPUT_FIELD_PLACEHOLDER");
    self.testInputField.font = [UIFont systemFontOfSize:15];
    self.testInputField.borderStyle = UITextBorderStyleRoundedRect;
    self.testInputField.delegate = self;
    self.testInputField.returnKeyType = UIReturnKeyDone;
    self.testInputField.clearButtonMode = UITextFieldViewModeWhileEditing;
    self.testInputField.autoresizingMask = UIViewAutoresizingFlexibleWidth;
    [header addSubview:self.testInputField];

    self.tableView.tableHeaderView = header;
}

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    // Rotation support: keep the header as wide as the table.
    CGFloat width = CGRectGetWidth(self.tableView.bounds);
    UIView *header = self.tableView.tableHeaderView;
    if (header && fabs(CGRectGetWidth(header.frame) - width) > 0.5) {
        header.frame = CGRectMake(0, 0, width, kTestFieldHeaderHeight);
        self.tableView.tableHeaderView = header;
    }
}

- (BOOL)textFieldShouldReturn:(UITextField *)textField {
    [textField resignFirstResponder];
    return YES;
}

#pragma mark - Add button

- (void)addButtonTapped{
    if ([self.currentOrder[0] count] >= maxshortcutpersection) {
        UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"TypeX"
                                                                       message:[NSString stringWithFormat:LOCALIZED(@"MAX_BUTTONS_REACHED"), (int)maxshortcutpersection]
                                                                preferredStyle:UIAlertControllerStyleAlert];
        [alert addAction:[UIAlertAction actionWithTitle:LOCALIZED(@"ANSWER_OK") style:UIAlertActionStyleCancel handler:nil]];
        [self presentViewController:alert animated:YES completion:nil];
        return;
    }

    DXPGesturePickerController *gesturePickerController = [[DXPGesturePickerController alloc] init];
    gesturePickerController.fullOrder = self.fullOrder;
    gesturePickerController.configuration = self.topConfiguration ? @"top" : @"bottom";
    // A new button has no action yet: its tap action (chosen in the pushed
    // page) defines it, so the identifier is left nil until the user picks.
    gesturePickerController.pendingNewEntry = YES;
    gesturePickerController.title = LOCALIZED(@"NEW_BUTTON");

    [gesturePickerController setRootController: [self rootController]];
    [gesturePickerController setParentController: [self parentController]];
    [self pushController:gesturePickerController];
}

#pragma mark - Storage

- (void)writeToFile{
    [[DXPrefsManager sharedInstance] setValue:self.currentOrder forKey:self.shortcutsPreferenceKey ?: kShortcutskey];
}

// Removes the per-gesture custom actions recorded for a deleted button so a
// later re-add starts clean instead of silently inheriting old gestures.
- (void)removeCustomActionsForIdentifier:(NSString *)identifier {
    if (![identifier isKindOfClass:[NSString class]] || identifier.length == 0) return;
    NSString *configuration = self.topConfiguration ? @"top" : @"bottom";

    NSMutableDictionary *prefs = [[[DXPrefsManager sharedInstance] readPrefs] mutableCopy] ?: [NSMutableDictionary dictionary];
    BOOL changed = NO;
    for (NSInteger gesture = DXShortcutGestureLongPress; gesture <= DXShortcutGestureTap; gesture++) {
        NSString *key = DXCustomActionsKeyForGesture((int)gesture, configuration);
        NSArray *entries = prefs[key];
        if (![entries isKindOfClass:[NSArray class]]) continue;
        NSArray *filtered = [entries filteredArrayUsingPredicate:[NSPredicate predicateWithFormat:@"identifier != %@", identifier]];
        if (![filtered isEqualToArray:entries]) {
            prefs[key] = filtered;
            changed = YES;
        }
    }
    if (changed) [[DXPrefsManager sharedInstance] writePrefs:prefs];
}

- (void)updateOrder:(BOOL)reset{
    NSMutableDictionary *prefs = [[[DXPrefsManager sharedInstance] readPrefs] mutableCopy] ?: [NSMutableDictionary dictionary];
    NSString *shortcutsKey = self.shortcutsPreferenceKey ?: kShortcutskey;

    DXShortcutsGenerator *shortcutsGenerator = [DXShortcutsGenerator sharedInstance];
    NSMutableArray *defaultOrderLabel = [[shortcutsGenerator labelName] mutableCopy];
    NSMutableArray *defaultOrderSelector = [[shortcutsGenerator selectorNames] mutableCopy];
    NSMutableArray *defaultOrder12 = [[shortcutsGenerator imageNameArrayForiOS:0] mutableCopy];
    NSMutableArray *defaultOrder13 = [[shortcutsGenerator imageNameArrayForiOS:1] mutableCopy];

    NSMutableArray *fullOrderDict = [[NSMutableArray alloc] init];

    for (int i = 0; i < [defaultOrderLabel count]; i++){
        if (DXIsHiddenShortcutSelector(defaultOrderSelector[i])) {
            continue;
        }
        [fullOrderDict addObject: @{
            @"label" : defaultOrderLabel[i],
            @"images12" : defaultOrder12[i],
            @"images13" : defaultOrder13[i],
            @"selector" : defaultOrderSelector[i],
        }];
    }

    self.fullOrder = fullOrderDict;

    id storedOrder = prefs[shortcutsKey];
    BOOL hasStoredOrder = !reset && [storedOrder isKindOfClass:[NSArray class]] && [storedOrder count] >= 2;
    NSArray *storedEnabled = hasStoredOrder && [storedOrder[0] isKindOfClass:[NSArray class]] ? storedOrder[0] : @[];
    NSArray *storedDisabled = hasStoredOrder && [storedOrder[1] isKindOfClass:[NSArray class]] ? storedOrder[1] : @[];

    NSMutableArray *enabled = [NSMutableArray array];
    NSMutableArray *disabled = [NSMutableArray array];
    NSMutableSet *seenSelectors = [NSMutableSet set];

    if (hasStoredOrder) {
        DXAppendUniqueShortcuts(storedEnabled, enabled, seenSelectors, maxshortcutpersection);
    }
    // Defaults seed only a configuration that was never stored. An explicitly
    // emptied toolbar (user deleted every button) stays empty.
    if (!hasStoredOrder) {
        DXAppendUniqueShortcuts(fullOrderDict, enabled, seenSelectors, maxdefaultshortcuts);
    }

    if (hasStoredOrder) {
        DXAppendUniqueShortcuts(storedDisabled, disabled, seenSelectors, NSUIntegerMax);
    }
    // Compare shortcut identity by selector.  Stored entries from older versions
    // may contain obsolete metadata (for example selectorlp), so dictionary
    // equality would incorrectly append a second copy of the same action.
    DXAppendUniqueShortcuts(fullOrderDict, disabled, seenSelectors, NSUIntegerMax);

    self.currentOrder = [NSMutableArray arrayWithObjects:enabled, disabled, nil];

    // The page only manages the enabled section; the disabled section is kept
    // in the stored schema so the toolbar keeps reading the two-section format.
    NSArray *normalizedOrder = @[[enabled copy], [disabled copy]];
    if (reset || ![storedOrder isEqual:normalizedOrder]) {
        prefs[shortcutsKey] = normalizedOrder;
        [[DXPrefsManager sharedInstance] writePrefs:prefs];
    }
}

- (void)viewWillDisappear:(BOOL)animated {
    [super viewWillDisappear:animated];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [self updateOrder:NO];
    [self.tableView reloadData];
}

- (void)viewDidLoad {
    self.topConfiguration = [[self.specifier propertyForKey:@"configuration"] isEqualToString:@"top"];
    self.shortcutsPreferenceKey = self.topConfiguration ? kTopShortcutskey : kShortcutskey;
    tweakBundle = [NSBundle bundleWithPath:bundlePath];
    [tweakBundle load];
    [super viewDidLoad];
    self.tableView = [[UITableView alloc] initWithFrame:CGRectMake(0, 0, self.view.frame.size.width, self.view.frame.size.height) style:UITableViewStyleGrouped];
    self.tableView.delegate = self;
    self.tableView.dataSource = self;
    [self.tableView setAutoresizingMask:UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight];
    [self.tableView registerClass:[UITableViewCell class] forCellReuseIdentifier:@"TypeXItemCell"];
    [self.tableView setEditing:YES];
    self.tableView.allowsSelectionDuringEditing=YES;

    ((UIViewController *)self).title = self.topConfiguration ? @"顶部设置" : @"底部设置";
    self.view = self.tableView;

    [self buildTestFieldHeader];

    self.addBtn = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemAdd target:self action:@selector(addButtonTapped)];
    self.navigationItem.rightBarButtonItem = self.addBtn;
}

@end
