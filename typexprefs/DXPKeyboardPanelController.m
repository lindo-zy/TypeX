#import "DXPKeyboardPanelController.h"
#import "DXPSubActionPickerController.h"
#import "DXPKeyboardPanelPreviewHeader.h"
#import "DXPPanelSliderCell.h"
#import "DXPIconInputView.h"
#import "DXPSFSymbolPickerController.h"
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
- (void)viewDidLoad {
    self.allowsDeletingCustomActions = YES;
    [super viewDidLoad];
}
- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView { (void)tableView; return 1; }
- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section {
    (void)tableView; (void)section;
    return DXPanelLocalized(@"KEYBOARD_PANEL_PICKER_DELETE_FOOTER");
}
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
// 面板条目外观编辑页：两行表单（名称、图标），图标行走 DXPIconInputView
// （预览缩略图 + 输入框 + 图标库入口），保存回传完整条目。
@interface DXPPanelItemAppearanceController : PSViewController <UITableViewDataSource, UITableViewDelegate>
@property(nonatomic, copy) NSDictionary *entry;
@property(nonatomic, strong) UITextField *nameField;
@property(nonatomic, strong) DXPIconInputView *iconInputView;
@property(nonatomic, copy) void (^completion)(NSDictionary *updatedEntry);
@end

@implementation DXPPanelItemAppearanceController
- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = DXPanelLocalized(@"KEYBOARD_PANEL_ITEM_APPEARANCE");
    self.nameField = [[UITextField alloc] initWithFrame:CGRectMake(0, 0, 180, 36)];
    self.nameField.textAlignment = NSTextAlignmentRight;
    self.nameField.clearButtonMode = UITextFieldViewModeWhileEditing;
    self.nameField.autocorrectionType = UITextAutocorrectionTypeNo;
    self.nameField.placeholder = DXPanelLocalized(@"KEYBOARD_PANEL_NAME");
    self.nameField.text = [self.entry[@"name"] isKindOfClass:NSString.class] ? self.entry[@"name"] : @"";

    self.iconInputView = [[DXPIconInputView alloc] initWithFrame:CGRectMake(0, 0, 267, 36)];
    self.iconInputView.textField.placeholder = DXPanelLocalized(@"KEYBOARD_PANEL_ICON");
    self.iconInputView.textField.text = [self.entry[@"icon"] isKindOfClass:NSString.class] ? self.entry[@"icon"] : @"";
    __weak typeof(self) weakSelf = self;
    self.iconInputView.browseTapped = ^{
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf) return;
        [strongSelf.view endEditing:YES];
        DXPSFSymbolPickerController *picker = [[DXPSFSymbolPickerController alloc] init];
        picker.selectedSymbolName = [strongSelf.iconInputView.textField.text
            stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
        __weak typeof(strongSelf) weakOwner = strongSelf;
        picker.completion = ^(NSString *symbolName) {
            typeof(weakOwner) owner = weakOwner;
            if (!owner || !symbolName.length) return;
            owner.iconInputView.textField.text = symbolName;
            [owner.iconInputView refreshPreview];
        };
        [picker setRootController:[strongSelf rootController]];
        [picker setParentController:[strongSelf parentController]];
        [strongSelf pushController:picker];
    };

    UITableView *table = [[UITableView alloc] initWithFrame:self.view.bounds style:UITableViewStyleInsetGrouped];
    table.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    table.dataSource = self;
    table.delegate = self;
    self.view = table;
    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithTitle:DXPanelLocalized(@"KEYBOARD_PANEL_SAVE")
        style:UIBarButtonItemStyleDone target:self action:@selector(saveTapped)];
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    (void)tableView; (void)section;
    return 2;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"PanelAppearanceCell"];
    if (!cell) cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:@"PanelAppearanceCell"];
    cell.selectionStyle = UITableViewCellSelectionStyleNone;
    cell.textLabel.text = DXPanelLocalized(indexPath.row == 0 ? @"KEYBOARD_PANEL_NAME" : @"KEYBOARD_PANEL_ICON");
    cell.textLabel.font = [UIFont systemFontOfSize:16];
    cell.imageView.image = nil;
    cell.accessoryView = indexPath.row == 0 ? self.nameField : self.iconInputView;
    return cell;
}

- (void)saveTapped {
    [self.view endEditing:YES];
    NSMutableDictionary *updated = [self.entry mutableCopy] ?: [NSMutableDictionary dictionary];
    updated[@"name"] = [self.nameField.text stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet] ?: @"";
    updated[@"icon"] = [self.iconInputView.textField.text stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet] ?: @"";
    if (self.completion) self.completion(updated);
    [self.navigationController popViewControllerAnimated:YES];
}
@end

@interface DXPKeyboardPanelItemsController () <UITableViewDragDelegate, UITableViewDropDelegate>
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
    UIBarButtonItem *addButton = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemAdd target:self action:@selector(addActions)];
    self.navigationItem.rightBarButtonItem = addButton;
    self.entries = [self configuredEntries];
    // 排序不设编辑模式：长按直接拖动（drag & drop），左滑删除照旧。
    self.table.dragInteractionEnabled = YES;
    self.table.dragDelegate = self;
    self.table.dropDelegate = self;
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
    cell.detailTextLabel.text = DXPanelLocalized(@"KEYBOARD_PANEL_EDIT_HINT");
    return cell;
}
- (void)tableView:(UITableView *)tableView commitEditingStyle:(UITableViewCellEditingStyle)editingStyle forRowAtIndexPath:(NSIndexPath *)indexPath {
    if (editingStyle != UITableViewCellEditingStyleDelete || indexPath.section != 0 || indexPath.row < 0 || indexPath.row >= (NSInteger)self.entries.count) return;
    [self removeEntry:self.entries[indexPath.row] fromTable:tableView];
}
- (BOOL)removeEntry:(NSDictionary *)entry fromTable:(UITableView *)tableView {
    // Resolve the captured item again, so a stale swipe cannot delete a different
    // item after reload/reorder. Delete only this panel's reference, not its definition.
    NSUInteger row = [self.entries indexOfObjectIdenticalTo:entry];
    if (row == NSNotFound) return NO;
    [self.entries removeObjectAtIndex:row];
    [self save];
    [tableView deleteRowsAtIndexPaths:@[[NSIndexPath indexPathForRow:row inSection:0]] withRowAnimation:UITableViewRowAnimationAutomatic];
    return YES;
}
- (BOOL)tableView:(UITableView *)tableView canEditRowAtIndexPath:(NSIndexPath *)indexPath {
    (void)tableView;
    return indexPath.section == 0 && indexPath.row >= 0 && indexPath.row < (NSInteger)self.entries.count;
}
- (UITableViewCellEditingStyle)tableView:(UITableView *)tableView editingStyleForRowAtIndexPath:(NSIndexPath *)indexPath {
    (void)tableView; (void)indexPath;
    return UITableViewCellEditingStyleDelete;
}
- (NSString *)tableView:(UITableView *)tableView titleForDeleteConfirmationButtonForRowAtIndexPath:(NSIndexPath *)indexPath {
    (void)tableView; (void)indexPath;
    return DXPanelLocalized(@"DELETE");
}
- (UISwipeActionsConfiguration *)tableView:(UITableView *)tableView trailingSwipeActionsConfigurationForRowAtIndexPath:(NSIndexPath *)indexPath {
    if (indexPath.section != 0 || indexPath.row < 0 || indexPath.row >= (NSInteger)self.entries.count) return nil;
    NSDictionary *entry = self.entries[indexPath.row];
    __weak typeof(self) weakSelf = self;
    __weak UITableView *weakTable = tableView;
    UIContextualAction *remove = [UIContextualAction contextualActionWithStyle:UIContextualActionStyleDestructive
        title:DXPanelLocalized(@"DELETE") handler:^(__unused UIContextualAction *action, __unused UIView *view, void (^completion)(BOOL)) {
            __strong typeof(weakSelf) self = weakSelf;
            UITableView *table = weakTable;
            completion(self && table && [self removeEntry:entry fromTable:table]);
        }];
    UISwipeActionsConfiguration *configuration = [UISwipeActionsConfiguration configurationWithActions:@[remove]];
    configuration.performsFirstActionWithFullSwipe = NO;
    return configuration;
}
// 长按拖动排序：本地拖动会话由表格跟踪落点间隙，落点即最终数组位置，
// 数据源更新与 moveRow 动画在同一 beginUpdates 里提交。
- (NSArray<UIDragItem *> *)tableView:(UITableView *)tableView itemsForBeginningDragSession:(id<UIDragSession>)session atIndexPath:(NSIndexPath *)indexPath {
    (void)tableView; (void)session;
    if (indexPath.section != 0 || indexPath.row < 0 || indexPath.row >= (NSInteger)self.entries.count) return @[];
    NSDictionary *entry = self.entries[indexPath.row];
    UIDragItem *item = [[UIDragItem alloc] initWithItemProvider:[[NSItemProvider alloc] initWithObject:entry[@"id"] ?: @""]];
    item.localObject = entry;
    return @[item];
}

- (UITableViewDropProposal *)tableView:(UITableView *)tableView dropSessionDidUpdate:(id<UIDropSession>)session withDestinationIndexPath:(NSIndexPath *)destinationIndexPath {
    (void)tableView; (void)destinationIndexPath;
    if (!session.localDragSession) return nil;
    return [[UITableViewDropProposal alloc] initWithDropOperation:UIDropOperationMove
        intent:UITableViewDropIntentInsertAtDestinationIndexPath];
}

- (void)tableView:(UITableView *)tableView performDropWithCoordinator:(id<UITableViewDropCoordinator>)coordinator {
    NSIndexPath *destination = coordinator.destinationIndexPath;
    id<UITableViewDropItem> dropItem = coordinator.items.firstObject;
    if (!destination || !dropItem.sourceIndexPath) return;
    NSDictionary *entry = dropItem.dragItem.localObject;
    if (![entry isKindOfClass:NSDictionary.class]) return;
    NSUInteger sourceRow = [self.entries indexOfObjectIdenticalTo:entry];
    if (sourceRow == NSNotFound) return;
    // 落点按当前序的插入位计（末尾追加=行数）；先移除源行，向下移动回缩一位。
    NSInteger targetRow = MIN(MAX(destination.row, 0), (NSInteger)self.entries.count);
    if (targetRow > (NSInteger)sourceRow) targetRow--;
    if (targetRow == (NSInteger)sourceRow) return;
    [tableView beginUpdates];
    [self.entries removeObjectAtIndex:sourceRow];
    [self.entries insertObject:entry atIndex:targetRow];
    [tableView moveRowAtIndexPath:[NSIndexPath indexPathForRow:sourceRow inSection:0]
        toIndexPath:[NSIndexPath indexPathForRow:targetRow inSection:0]];
    [tableView endUpdates];
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
        // The picker can delete definitions and saved panel references. Start
        // from that latest configuration instead of restoring the parent's copy.
        self.entries = [self configuredEntries];
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
        if (!self || !DXIsLinkActionSelector(selector) || ![self definitionForSelector:selector]) return;
        self.entries = [self configuredEntries];
        NSUInteger currentRow = [self.entries indexOfObject:original];
        if (currentRow == NSNotFound) return;
        NSMutableDictionary *entry = [original mutableCopy];
        entry[@"selector"] = selector;
        self.entries[currentRow] = entry;
        [self save];
        [self.table reloadData];
    };
    [self pushPicker:picker];
}
// 外观编辑改为独立页面：名称 + 图标行（DXPIconInputView 提供实时预览与
// 图标库入口），替代原双文本框弹窗。
- (void)pushAppearanceEditorAtRow:(NSInteger)row {
    if (row < 0 || row >= (NSInteger)self.entries.count) return;
    NSDictionary *original = self.entries[row];
    DXPPanelItemAppearanceController *editor = [[DXPPanelItemAppearanceController alloc] init];
    editor.entry = original;
    __weak typeof(self) weakSelf = self;
    editor.completion = ^(NSDictionary *updated) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf || ![updated isKindOfClass:NSDictionary.class]) return;
        // 返回时按原条目对象定位行；行已删除或重排则放弃写入。
        NSUInteger currentRow = [strongSelf.entries indexOfObjectIdenticalTo:original];
        if (currentRow == NSNotFound) return;
        strongSelf.entries[currentRow] = updated;
        [strongSelf save];
        [strongSelf.table reloadData];
    };
    [editor setRootController:[self rootController]];
    [editor setParentController:[self parentController]];
    [self pushController:editor];
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
    [menu addAction:[UIAlertAction actionWithTitle:DXPanelLocalized(@"KEYBOARD_PANEL_ITEM_APPEARANCE") style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *action) { [weakSelf pushAppearanceEditorAtRow:row]; }]];
    [menu addAction:[UIAlertAction actionWithTitle:DXPanelLocalized(@"KEYBOARD_PANEL_REPLACE_ACTION") style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *action) { [weakSelf replaceActionAtRow:row]; }]];
    NSDictionary *definition = [self definitionForSelector:entry[@"selector"]];
    if (definition) [menu addAction:[UIAlertAction actionWithTitle:DXPanelLocalized(@"KEYBOARD_PANEL_EDIT_ACTION") style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *action) { [weakSelf editDefinition:definition]; }]];
    [menu addAction:[UIAlertAction actionWithTitle:DXPanelLocalized(@"CANCEL") style:UIAlertActionStyleCancel handler:nil]];
    menu.popoverPresentationController.sourceView = [tableView cellForRowAtIndexPath:indexPath];
    menu.popoverPresentationController.sourceRect = menu.popoverPresentationController.sourceView.bounds;
    [self presentViewController:menu animated:YES completion:nil];
}
@end

