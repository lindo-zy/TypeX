#import "DXPKeyboardPanelController.h"
#import "DXPSubActionPickerController.h"
#import "DXPKeyboardPanelPreviewHeader.h"
#import "DXPPanelSliderCell.h"
#import "DXPLinkActionEditorController.h"
#import "../DXKeyboardPanelPreferences.h"
#import "../DXHelper.h"
#import "../common.h"
#import <Preferences/PSSpecifier.h>

static NSString *DXPanelLocalized(NSString *key) {
    return [[NSBundle bundleWithPath:bundlePath] localizedStringForKey:key value:key table:nil];
}

// Hide the basic-action section while retaining picker selection and in-place
// creation. customActionsOnly belongs to management mode and would edit rows.
@interface DXPKeyboardPanelActionPicker : DXPSubActionPickerController
@end
@implementation DXPKeyboardPanelActionPicker
- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView { (void)tableView; return 1; }
@end

@interface DXPKeyboardPanelController ()
@property(nonatomic, strong) DXPKeyboardPanelPreviewHeader *previewHeader;
@property(nonatomic, strong) UISearchController *keyboardTestSearch;
@end
@implementation DXPKeyboardPanelController
- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"滑动面板";
    NSString *side = DXKeyboardPanelBool([DXPrefsManager.sharedInstance readPrefs], kDXPanelUnified, NO) ? @"common" : @"left";
    self.previewHeader = [[DXPKeyboardPanelPreviewHeader alloc] initWithSide:side allowsSelection:YES];
    self.previewHeader.frame = CGRectMake(0, 0, self.table.bounds.size.width, self.previewHeader.bounds.size.height);
    self.table.tableHeaderView = self.previewHeader;
    self.keyboardTestSearch = [[UISearchController alloc] initWithSearchResultsController:nil];
    self.keyboardTestSearch.obscuresBackgroundDuringPresentation = NO;
    self.keyboardTestSearch.hidesNavigationBarDuringPresentation = NO;
    self.keyboardTestSearch.searchBar.placeholder = @"输入文字，测试键盘与滑动面板";
    self.navigationItem.searchController = self.keyboardTestSearch;
    self.navigationItem.hidesSearchBarWhenScrolling = YES;
    self.definesPresentationContext = YES;
}
- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [self.previewHeader refresh];
}
- (void)viewWillDisappear:(BOOL)animated {
    self.keyboardTestSearch.active = NO;
    [self.view endEditing:YES];
    [super viewWillDisappear:animated];
}
- (CGFloat)tableView:(UITableView *)table heightForRowAtIndexPath:(NSIndexPath *)path {
    PSSpecifier *specifier = [self specifierAtIndexPath:path];
    if ([specifier propertyForKey:@"cellClass"] == DXPPanelSliderCell.class) return 80;
    return [super tableView:table heightForRowAtIndexPath:path];
}
- (PSSpecifier *)setting:(NSString *)label key:(NSString *)key defaultValue:(id)value cell:(PSCellType)cell {
    PSSpecifier *specifier = [PSSpecifier preferenceSpecifierNamed:DXPanelLocalized(label) target:self
        set:@selector(setPreferenceValue:specifier:) get:@selector(readPreferenceValue:)
        detail:nil cell:cell edit:nil];
    [specifier setProperty:key forKey:@"key"];
    [specifier setProperty:value forKey:@"default"];
    return specifier;
}
- (NSArray *)specifiers {
    if (_specifiers) return _specifiers;
    NSMutableArray *items = [NSMutableArray array];
    PSSpecifier *group = [PSSpecifier groupSpecifierWithName:DXPanelLocalized(@"KEYBOARD_PANEL_ENTRANCE")];
    [group setProperty:DXPanelLocalized(@"KEYBOARD_PANEL_GESTURE_FOOTER") forKey:@"footerText"];
    [items addObject:group];
    [items addObject:[self setting:@"KEYBOARD_PANEL_TOP" key:kDXPanelTopEnabled defaultValue:@YES cell:PSSwitchCell]];
    [items addObject:[self setting:@"KEYBOARD_PANEL_BOTTOM" key:kDXPanelBottomEnabled defaultValue:@YES cell:PSSwitchCell]];
    [items addObject:[self setting:@"KEYBOARD_PANEL_UNIFIED" key:kDXPanelUnified defaultValue:@NO cell:PSSwitchCell]];
    group = [PSSpecifier groupSpecifierWithName:DXPanelLocalized(@"KEYBOARD_PANEL_CONTENT")];
    [group setProperty:DXPanelLocalized(@"KEYBOARD_PANEL_CONTENT_FOOTER") forKey:@"footerText"];
    [items addObject:group];
    for (NSArray *profile in @[@[@"left", @"KEYBOARD_PANEL_LEFT"], @[@"right", @"KEYBOARD_PANEL_RIGHT"], @[@"common", @"KEYBOARD_PANEL_COMMON"]]) {
        PSSpecifier *link = [PSSpecifier preferenceSpecifierNamed:DXPanelLocalized(profile[1]) target:self set:nil get:nil
            detail:DXPKeyboardPanelItemsController.class cell:PSLinkCell edit:nil];
        [link setProperty:profile[0] forKey:@"panelSide"];
        [items addObject:link];
    }
    [items addObject:[PSSpecifier groupSpecifierWithName:DXPanelLocalized(@"KEYBOARD_PANEL_APPEARANCE")]];
    [items addObject:[self setting:@"KEYBOARD_PANEL_DARK" key:kDXPanelDark defaultValue:@YES cell:PSSwitchCell]];
    for (NSArray *row in @[@[@"KEYBOARD_PANEL_COLUMNS", kDXPanelColumns, @4, @3, @5],
                          @[@"KEYBOARD_PANEL_SCALE", kDXPanelScale, @100, @70, @120]]) {
        PSSpecifier *slider = [self setting:row[0] key:row[1] defaultValue:row[2] cell:PSStaticTextCell];
        [slider setProperty:DXPPanelSliderCell.class forKey:@"cellClass"];
        [slider setProperty:row[3] forKey:@"min"];
        [slider setProperty:row[4] forKey:@"max"];
        [slider setProperty:@YES forKey:@"showValue"];
        [items addObject:slider];
    }
    _specifiers = items;
    return _specifiers;
}
- (id)readPreferenceValue:(PSSpecifier *)specifier {
    return [[DXPrefsManager sharedInstance] readPrefs][[specifier propertyForKey:@"key"]] ?: [specifier propertyForKey:@"default"];
}
- (void)setPreferenceValue:(id)value specifier:(PSSpecifier *)specifier {
    NSString *key = [specifier propertyForKey:@"key"];
    if ([key isEqualToString:kDXPanelColumns]) value = @(MIN(5, MAX(3, lround([value doubleValue]))));
    if ([key isEqualToString:kDXPanelScale]) value = @(MIN(120, MAX(70, lround([value doubleValue] / 5) * 5)));
    if (key.length && value) [[DXPrefsManager sharedInstance] setValue:value forKey:key];
    [self.previewHeader refresh];
}
@end

@interface DXPKeyboardPanelItemsController ()
@property(nonatomic, strong) UITableView *table;
@property(nonatomic, strong) DXPKeyboardPanelPreviewHeader *previewHeader;
@property(nonatomic, copy) NSString *side;
@property(nonatomic, strong) NSMutableArray<NSDictionary *> *entries;
@end

@implementation DXPKeyboardPanelItemsController
- (NSMutableArray *)configuredEntries {
    NSDictionary *preferences = [[DXPrefsManager sharedInstance] readPrefs];
    return [DXKeyboardPanelFilterCustomItems(DXKeyboardPanelItems(preferences, self.side),
        preferences[kLinkActionskey], kLinkActionSelectorPrefix) mutableCopy];
}
- (void)viewDidLoad {
    [super viewDidLoad];
    self.side = [self.specifier propertyForKey:@"panelSide"] ?: @"left";
    self.title = self.specifier.name;
    self.table = [[UITableView alloc] initWithFrame:self.view.bounds style:UITableViewStyleInsetGrouped];
    self.table.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    self.table.delegate = self;
    self.table.dataSource = self;
    [self.view addSubview:self.table];
    self.previewHeader = [[DXPKeyboardPanelPreviewHeader alloc] initWithSide:self.side allowsSelection:NO];
    self.previewHeader.frame = CGRectMake(0, 0, self.table.bounds.size.width, self.previewHeader.bounds.size.height);
    self.table.tableHeaderView = self.previewHeader;
    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemAdd target:self action:@selector(addActions)];
    self.entries = [self configuredEntries];
    [self.table setEditing:YES animated:NO];
    self.table.allowsSelectionDuringEditing = YES;
}
- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    self.entries = [self configuredEntries];
    [self.previewHeader refresh];
    [self.table reloadData];
}
- (void)save {
    [[DXPrefsManager sharedInstance] setValue:[self.entries copy] forKey:DXKeyboardPanelItemsKey(self.side)];
    [self.previewHeader refresh];
}
- (NSDictionary *)definitionForSelector:(NSString *)selector {
    id stored = [[DXPrefsManager sharedInstance] readPrefs][kLinkActionskey];
    if (![stored isKindOfClass:NSArray.class]) return nil;
    for (id entry in stored) if ([entry isKindOfClass:NSDictionary.class] && [entry[@"selector"] isEqual:selector]) return entry;
    return nil;
}
- (NSString *)nameForEntry:(NSDictionary *)entry {
    NSString *name = entry[@"name"];
    if (name.length) return name;
    name = [self definitionForSelector:entry[@"selector"]][@"name"];
    return name.length ? name : [DXHelper localizedStringForActionNamed:entry[@"selector"] shortName:NO bundle:[NSBundle bundleWithPath:bundlePath]];
}
- (UIImage *)imageForEntry:(NSDictionary *)entry {
    NSString *icon = entry[@"icon"];
    if (!icon.length) icon = [self definitionForSelector:entry[@"selector"]][@"icon"];
    if (icon.length) return [DXHelper imageForIconConfig:icon defaultSymbolName:@"link"];
    return [UIImage systemImageNamed:@"square.grid.2x2"];
}
- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    (void)tableView; (void)section;
    return self.entries.count;
}
- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section {
    (void)tableView; (void)section;
    return DXPanelLocalized(@"KEYBOARD_PANEL_ITEMS_FOOTER");
}
- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"PanelItem"];
    if (!cell) cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:@"PanelItem"];
    NSDictionary *entry = self.entries[indexPath.row];
    cell.textLabel.text = [self nameForEntry:entry];
    cell.imageView.image = [self imageForEntry:entry];
    cell.showsReorderControl = YES;
    cell.detailTextLabel.text = DXPanelLocalized(@"KEYBOARD_PANEL_EDIT_HINT");
    return cell;
}
- (void)tableView:(UITableView *)tableView commitEditingStyle:(UITableViewCellEditingStyle)editingStyle forRowAtIndexPath:(NSIndexPath *)indexPath {
    if (editingStyle != UITableViewCellEditingStyleDelete) return;
    [self.entries removeObjectAtIndex:indexPath.row];
    [self save];
    [tableView deleteRowsAtIndexPaths:@[indexPath] withRowAnimation:UITableViewRowAnimationAutomatic];
}
- (BOOL)tableView:(UITableView *)tableView canMoveRowAtIndexPath:(NSIndexPath *)indexPath {
    (void)tableView; (void)indexPath; return YES;
}
- (void)tableView:(UITableView *)tableView moveRowAtIndexPath:(NSIndexPath *)from toIndexPath:(NSIndexPath *)to {
    (void)tableView;
    NSDictionary *entry = self.entries[from.row];
    [self.entries removeObjectAtIndex:from.row];
    [self.entries insertObject:entry atIndex:to.row];
    [self save];
}
- (void)pushPicker:(DXPSubActionPickerController *)picker {
    picker.fullOrder = @[];
    picker.title = DXPanelLocalized(@"CHOOSE_ACTION");
    [picker setRootController:[self rootController]];
    [picker setParentController:[self parentController]];
    [self pushController:picker];
}
- (void)addActions {
    DXPSubActionPickerController *picker = [[DXPKeyboardPanelActionPicker alloc] init];
    picker.allowsMultipleSelection = YES;
    __weak typeof(self) weakSelf = self;
    picker.multiSelectionCompletion = ^(NSArray<NSString *> *selectors) {
        __strong typeof(weakSelf) self = weakSelf;
        if (!self) return;
        for (NSString *selector in selectors) {
            if (DXIsLinkActionSelector(selector) && [self definitionForSelector:selector])
                [self.entries addObject:@{@"id": NSUUID.UUID.UUIDString, @"selector": selector}];
        }
        [self save];
        [self.table reloadData];
    };
    [self pushPicker:picker];
}
- (void)replaceActionAtRow:(NSInteger)row {
    if (row >= (NSInteger)self.entries.count) return;
    NSDictionary *original = self.entries[row];
    DXPSubActionPickerController *picker = [[DXPKeyboardPanelActionPicker alloc] init];
    picker.selectedSelector = original[@"selector"];
    __weak typeof(self) weakSelf = self;
    picker.completion = ^(NSString *selector) {
        __strong typeof(weakSelf) self = weakSelf;
        if (!self || row >= (NSInteger)self.entries.count || ![self.entries[row] isEqual:original] ||
            !DXIsLinkActionSelector(selector) || ![self definitionForSelector:selector]) return;
        NSMutableDictionary *entry = [original mutableCopy];
        entry[@"selector"] = selector;
        self.entries[row] = entry;
        [self save];
        [self.table reloadData];
    };
    [self pushPicker:picker];
}
- (void)editAppearanceAtRow:(NSInteger)row {
    NSDictionary *original = self.entries[row];
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:DXPanelLocalized(@"KEYBOARD_PANEL_ITEM_APPEARANCE") message:nil preferredStyle:UIAlertControllerStyleAlert];
    [alert addTextFieldWithConfigurationHandler:^(UITextField *field) {
        field.placeholder = DXPanelLocalized(@"KEYBOARD_PANEL_NAME");
        field.text = original[@"name"];
    }];
    [alert addTextFieldWithConfigurationHandler:^(UITextField *field) {
        field.placeholder = DXPanelLocalized(@"KEYBOARD_PANEL_ICON");
        field.text = original[@"icon"];
        field.autocapitalizationType = UITextAutocapitalizationTypeNone;
        field.autocorrectionType = UITextAutocorrectionTypeNo;
    }];
    [alert addAction:[UIAlertAction actionWithTitle:DXPanelLocalized(@"CANCEL") style:UIAlertActionStyleCancel handler:nil]];
    __weak typeof(self) weakSelf = self;
    __weak UIAlertController *weakAlert = alert;
    [alert addAction:[UIAlertAction actionWithTitle:DXPanelLocalized(@"KEYBOARD_PANEL_SAVE") style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *action) {
        __strong typeof(weakSelf) self = weakSelf;
        if (!self || row >= (NSInteger)self.entries.count || ![self.entries[row] isEqual:original]) return;
        NSMutableDictionary *entry = [original mutableCopy];
        entry[@"name"] = [weakAlert.textFields[0].text stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet] ?: @"";
        entry[@"icon"] = [weakAlert.textFields[1].text stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet] ?: @"";
        self.entries[row] = entry;
        [self save];
        [self.table reloadData];
    }]];
    [self presentViewController:alert animated:YES completion:nil];
}
- (void)editDefinition:(NSDictionary *)definition {
    DXPLinkActionEditorController *editor = [[DXPLinkActionEditorController alloc] init];
    editor.entry = [definition mutableCopy];
    __weak typeof(self) weakSelf = self;
    editor.completion = ^(NSDictionary *saved) {
        NSMutableDictionary *preferences = [[[DXPrefsManager sharedInstance] readPrefs] mutableCopy];
        id stored = preferences[kLinkActionskey];
        if (![stored isKindOfClass:NSArray.class]) return;
        NSMutableArray *actions = [stored mutableCopy];
        for (NSUInteger index = 0; index < actions.count; index++) {
            if ([actions[index] isKindOfClass:NSDictionary.class] && [actions[index][@"selector"] isEqual:saved[@"selector"]]) {
                actions[index] = saved;
                preferences[kLinkActionskey] = actions;
                [[DXPrefsManager sharedInstance] writePrefs:preferences];
                [weakSelf.previewHeader refresh];
                [weakSelf.table reloadData];
                break;
            }
        }
    };
    [editor setRootController:[self rootController]];
    [editor setParentController:[self parentController]];
    [self pushController:editor];
}
- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    NSInteger row = indexPath.row;
    NSDictionary *entry = self.entries[row];
    UIAlertController *menu = [UIAlertController alertControllerWithTitle:[self nameForEntry:entry] message:nil preferredStyle:UIAlertControllerStyleActionSheet];
    __weak typeof(self) weakSelf = self;
    [menu addAction:[UIAlertAction actionWithTitle:DXPanelLocalized(@"KEYBOARD_PANEL_ITEM_APPEARANCE") style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *action) { [weakSelf editAppearanceAtRow:row]; }]];
    [menu addAction:[UIAlertAction actionWithTitle:DXPanelLocalized(@"KEYBOARD_PANEL_REPLACE_ACTION") style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *action) { [weakSelf replaceActionAtRow:row]; }]];
    NSDictionary *definition = [self definitionForSelector:entry[@"selector"]];
    if (definition) [menu addAction:[UIAlertAction actionWithTitle:DXPanelLocalized(@"KEYBOARD_PANEL_EDIT_ACTION") style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *action) { [weakSelf editDefinition:definition]; }]];
    [menu addAction:[UIAlertAction actionWithTitle:DXPanelLocalized(@"CANCEL") style:UIAlertActionStyleCancel handler:nil]];
    menu.popoverPresentationController.sourceView = [tableView cellForRowAtIndexPath:indexPath];
    menu.popoverPresentationController.sourceRect = menu.popoverPresentationController.sourceView.bounds;
    [self presentViewController:menu animated:YES completion:nil];
}
@end
