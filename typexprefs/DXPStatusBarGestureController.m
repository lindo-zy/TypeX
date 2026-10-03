#import "DXPStatusBarGestureController.h"
#import "DXPLinkActionEditorController.h"
#import "../DXStatusBarGesturePolicy.h"
#import "../DXGlobalPanelPolicy.h"
#import "../DXHelper.h"
#import "../common.h"
#import <Preferences/PSSpecifier.h>

static NSString *DXStatusLocalized(NSString *key) {
    return [[NSBundle bundleWithPath:bundlePath] localizedStringForKey:key value:key table:nil];
}
static NSString *DXStatusTitle(NSString *kind) {
    return DXStatusLocalized([@"STATUS_BAR_" stringByAppendingString:kind.uppercaseString]);
}
static NSDictionary *DXStatusDefinition(NSDictionary *preferences, NSString *selector) {
    id definitions = preferences[kLinkActionskey];
    if (![definitions isKindOfClass:NSArray.class]) return nil;
    for (id entry in definitions)
        if ([entry isKindOfClass:NSDictionary.class] && [entry[@"selector"] isEqual:selector]) return entry;
    return nil;
}
static BOOL DXStatusSlotValid(NSString *slot) {
    if (![slot isKindOfClass:NSString.class]) return NO;
    NSArray *parts = [slot componentsSeparatedByString:@"."];
    return parts.count == 2 && [DXStatusBarSlot(parts[0], parts[1]) isEqual:slot];
}
static BOOL DXStatusSaveBinding(NSString *slot, NSString *field, id value) {
    if (!DXStatusSlotValid(slot) || !field.length) {
        NSLog(@"[TypeX][StatusBarSettings] save rejected: invalid slot or field");
        return NO;
    }
    DXPrefsManager *manager = DXPrefsManager.sharedInstance;
    NSMutableDictionary *preferences = [[manager readPrefs] mutableCopy];
    if (!preferences) return NO;
    id stored = preferences[kDXStatusBarBindings];
    NSMutableDictionary *bindings = [stored isKindOfClass:NSDictionary.class] ? [stored mutableCopy] : [NSMutableDictionary dictionary];
    NSMutableDictionary *entry = [DXStatusBarBinding(preferences, slot) mutableCopy];
    if (value) entry[field] = value; else [entry removeObjectForKey:field];
    bindings[slot] = entry;
    preferences[kDXStatusBarBindings] = bindings;
    [manager writePrefs:preferences];
    id saved = DXStatusBarBinding([manager readPrefs], slot)[field];
    BOOL success = value ? [saved isEqual:value] : saved == nil;
    NSLog(@"[TypeX][StatusBarSettings] save slot=%@ field=%@ success=%d", slot, field, success);
    return success;
}

@interface DXPStatusBarActionPicker : PSListController
@property(nonatomic) BOOL selectAfterSave;
@end
@interface DXPStatusBarGestureEntryController : PSListController
@end

@implementation DXPStatusBarGestureController
- (void)viewDidLoad { [super viewDidLoad]; self.title = DXStatusLocalized(@"STATUS_BAR_SETTINGS"); }
- (PSSpecifier *)toggle:(NSString *)title key:(NSString *)key {
    PSSpecifier *item = [PSSpecifier preferenceSpecifierNamed:DXStatusLocalized(title) target:self
        set:@selector(setPreferenceValue:specifier:) get:@selector(readPreferenceValue:) detail:nil cell:PSSwitchCell edit:nil];
    [item setProperty:key forKey:@"key"];
    [item setProperty:@NO forKey:@"default"];
    return item;
}
- (NSArray *)specifiers {
    if (_specifiers) return _specifiers;
    NSMutableArray *items = [NSMutableArray array];
    PSSpecifier *group = [PSSpecifier groupSpecifierWithName:DXStatusLocalized(@"STATUS_BAR_SETTINGS")];
    [group setProperty:DXStatusLocalized(@"STATUS_BAR_FOOTER") forKey:@"footerText"];
    [items addObject:group];
    [items addObject:[self toggle:@"ENABLED" key:kDXStatusBarEnabled]];
    [items addObject:[self toggle:@"STATUS_BAR_LANDSCAPE" key:kDXStatusBarLandscape]];
    for (NSString *region in DXStatusBarRegions()) {
        [items addObject:[PSSpecifier groupSpecifierWithName:DXStatusTitle(region)]];
        for (NSString *gesture in DXStatusBarGestures()) {
            PSSpecifier *item = [PSSpecifier preferenceSpecifierNamed:DXStatusTitle(gesture) target:self set:nil get:nil
                detail:DXPStatusBarGestureEntryController.class cell:PSLinkCell edit:nil];
            [item setProperty:DXStatusBarSlot(region, gesture) forKey:@"statusBarSlot"];
            [item setProperty:[NSString stringWithFormat:@"%@ · %@", DXStatusTitle(region), DXStatusTitle(gesture)] forKey:@"entryTitle"];
            [items addObject:item];
        }
    }
    _specifiers = items; return items;
}
- (id)readPreferenceValue:(PSSpecifier *)specifier {
    return @(DXStatusBarFlag([[DXPrefsManager sharedInstance] readPrefs][[specifier propertyForKey:@"key"]]));
}
- (void)setPreferenceValue:(id)value specifier:(PSSpecifier *)specifier {
    NSString *key = [specifier propertyForKey:@"key"];
    if (key.length) [[DXPrefsManager sharedInstance] setValue:@(DXStatusBarFlag(value)) forKey:key];
}
@end

@implementation DXPStatusBarGestureEntryController
- (void)viewDidLoad { [super viewDidLoad]; self.title = [self.specifier propertyForKey:@"entryTitle"]; }
- (void)viewWillAppear:(BOOL)animated { [super viewWillAppear:animated]; [self reloadSpecifiers]; }
- (NSArray *)specifiers {
    if (_specifiers) return _specifiers;
    NSString *slot = [self.specifier propertyForKey:@"statusBarSlot"];
    NSMutableArray *items = [NSMutableArray array];
    PSSpecifier *group = [PSSpecifier groupSpecifierWithName:nil];
    [group setProperty:DXStatusLocalized(@"STATUS_BAR_ENTRY_FOOTER") forKey:@"footerText"];
    [items addObject:group];
    PSSpecifier *enabled = [PSSpecifier preferenceSpecifierNamed:DXStatusLocalized(@"ENABLED") target:self
        set:@selector(setPreferenceValue:specifier:) get:@selector(readPreferenceValue:) detail:nil cell:PSSwitchCell edit:nil];
    [enabled setProperty:slot forKey:@"statusBarSlot"];
    [items addObject:enabled];
    PSSpecifier *action = [PSSpecifier preferenceSpecifierNamed:DXStatusLocalized(@"CHOOSE_ACTION") target:self set:nil get:@selector(readActionName:)
        detail:DXPStatusBarActionPicker.class cell:PSLinkCell edit:nil];
    [action setProperty:slot forKey:@"statusBarSlot"];
    [items addObject:action];
    PSSpecifier *clear = [PSSpecifier preferenceSpecifierNamed:DXStatusLocalized(@"STATUS_BAR_CLEAR") target:self set:nil get:nil detail:nil cell:PSButtonCell edit:nil];
    clear->action = @selector(clearAction:);
    [items addObject:clear];
    _specifiers = items; return items;
}
- (id)readPreferenceValue:(PSSpecifier *)specifier {
    return @(DXStatusBarFlag(DXStatusBarBinding([[DXPrefsManager sharedInstance] readPrefs], [specifier propertyForKey:@"statusBarSlot"])[@"enabled"]));
}
- (id)readActionName:(PSSpecifier *)specifier {
    NSDictionary *preferences = [[DXPrefsManager sharedInstance] readPrefs];
    NSString *selector = DXGlobalPanelString(DXStatusBarBinding(preferences, [specifier propertyForKey:@"statusBarSlot"])[@"selector"]);
    NSString *side = DXStatusBarPanelSide(selector);
    NSDictionary *entry = DXStatusDefinition(preferences, selector);
    NSString *name = side ? DXStatusLocalized([@"STATUS_BAR_PANEL_" stringByAppendingString:side.uppercaseString]) : DXGlobalPanelString(entry[@"name"]);
    return name.length && (side || DXGlobalCustomActionSupported(entry)) ? name : DXStatusLocalized(@"STATUS_BAR_UNASSIGNED");
}
- (void)setPreferenceValue:(id)value specifier:(PSSpecifier *)specifier {
    DXStatusSaveBinding([specifier propertyForKey:@"statusBarSlot"], @"enabled", @(DXStatusBarFlag(value)));
}
- (void)clearAction:(PSSpecifier *)specifier {
    (void)specifier;
    DXStatusSaveBinding([self.specifier propertyForKey:@"statusBarSlot"], @"selector", nil);
    [self reloadSpecifiers];
}
- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    PSSpecifier *item = [self respondsToSelector:@selector(specifierAtIndexPath:)] ? [self specifierAtIndexPath:indexPath] : nil;
    if (item && item->action == @selector(clearAction:)) {
        [tableView deselectRowAtIndexPath:indexPath animated:YES];
        [self clearAction:item];
        return;
    }
    [super tableView:tableView didSelectRowAtIndexPath:indexPath];
}
@end

@implementation DXPStatusBarActionPicker
- (NSString *)slot { return [self.specifier propertyForKey:@"statusBarSlot"]; }
- (void)viewDidLoad { [super viewDidLoad]; self.title = DXStatusLocalized(@"CHOOSE_ACTION"); }
- (void)viewWillAppear:(BOOL)animated { [super viewWillAppear:animated]; [self reloadSpecifiers]; }
- (void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];
    if (self.selectAfterSave) { self.selectAfterSave = NO; [self.navigationController popViewControllerAnimated:YES]; }
}
- (NSArray *)specifiers {
    if (_specifiers) return _specifiers;
    NSMutableArray *items = [NSMutableArray array];
    [items addObject:[PSSpecifier groupSpecifierWithName:DXStatusLocalized(@"STATUS_BAR_PANELS")]];
    for (NSString *side in @[@"left", @"right", @"common"]) {
        PSSpecifier *item = [PSSpecifier preferenceSpecifierNamed:DXStatusLocalized([@"STATUS_BAR_PANEL_" stringByAppendingString:side.uppercaseString])
            target:self set:nil get:nil detail:nil cell:PSButtonCell edit:nil];
        [item setProperty:[@"__typex_statusbar_panel_" stringByAppendingString:side] forKey:@"actionSelector"];
        item->action = @selector(selectAction:); [items addObject:item];
    }
    PSSpecifier *group = [PSSpecifier groupSpecifierWithName:DXStatusLocalized(@"CUSTOM_ACTIONS")];
    [group setProperty:DXStatusLocalized(@"STATUS_BAR_PICKER_FOOTER") forKey:@"footerText"];
    [items addObject:group];
    id definitions = [[DXPrefsManager sharedInstance] readPrefs][kLinkActionskey];
    for (id entry in [definitions isKindOfClass:NSArray.class] ? definitions : @[]) {
        if (!DXGlobalCustomActionSupported(entry) || !DXIsLinkActionSelector(entry[@"selector"])) continue;
        NSString *name = DXGlobalPanelString(entry[@"name"]);
        PSSpecifier *item = [PSSpecifier preferenceSpecifierNamed:name.length ? name : DXStatusLocalized(@"DEFAULT_BUTTON_NAME")
            target:self set:nil get:nil detail:nil cell:PSButtonCell edit:nil];
        [item setProperty:entry[@"selector"] forKey:@"actionSelector"];
        [item setProperty:[DXHelper imageForIconConfig:entry[@"icon"] defaultSymbolName:@"link"] forKey:@"iconImage"];
        item->action = @selector(selectAction:); [items addObject:item];
    }
    PSSpecifier *add = [PSSpecifier preferenceSpecifierNamed:DXStatusLocalized(@"ADD") target:self set:nil get:nil detail:nil cell:PSButtonCell edit:nil];
    add->action = @selector(addAction:); [items addObject:add];
    _specifiers = items; return items;
}
- (void)selectAction:(PSSpecifier *)specifier {
    NSString *selector = [specifier propertyForKey:@"actionSelector"];
    if (![selector isKindOfClass:NSString.class] || !selector.length) return;
    NSDictionary *entry = DXStatusDefinition([[DXPrefsManager sharedInstance] readPrefs], selector);
    if (!DXStatusBarPanelSide(selector) && (!DXIsLinkActionSelector(selector) || !DXGlobalCustomActionSupported(entry))) { [self reloadSpecifiers]; return; }
    if (DXStatusSaveBinding(self.slot, @"selector", selector)) [self.navigationController popViewControllerAnimated:YES];
}
- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    // The row owns the action payload; pass its specifier explicitly.
    PSSpecifier *item = [self respondsToSelector:@selector(specifierAtIndexPath:)] ? [self specifierAtIndexPath:indexPath] : nil;
    if (item && (item->action == @selector(selectAction:) || item->action == @selector(addAction:))) {
        [tableView deselectRowAtIndexPath:indexPath animated:YES];
        if (item->action == @selector(selectAction:)) [self selectAction:item];
        else [self addAction:item];
        return;
    }
    [super tableView:tableView didSelectRowAtIndexPath:indexPath];
}
- (void)addAction:(PSSpecifier *)specifier {
    (void)specifier;
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:DXStatusLocalized(@"ADD") message:nil preferredStyle:UIAlertControllerStyleAlert];
    __weak typeof(self) weakSelf = self;
    for (NSString *type in @[kCustomActionTypeURLScheme, kCustomActionTypeOpenApp, kCustomActionTypeShortcut, kCustomActionTypeSystem]) {
        [alert addAction:[UIAlertAction actionWithTitle:[DXPLinkActionEditorController displayNameForType:type] style:UIAlertActionStyleDefault
            handler:^(__unused UIAlertAction *action) { [weakSelf addType:type]; }]];
    }
    [alert addAction:[UIAlertAction actionWithTitle:DXStatusLocalized(@"ANSWER_CANCEL") style:UIAlertActionStyleCancel handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}
- (void)addType:(NSString *)type {
    DXPLinkActionEditorController *editor = [DXPLinkActionEditorController new];
    editor.entry = [@{@"selector": [kLinkActionSelectorPrefix stringByAppendingString:NSUUID.UUID.UUIDString],
        @"type": type, @"name": [DXPLinkActionEditorController displayNameForType:type],
        @"icon": [DXPLinkActionEditorController defaultIconForType:type], @"link": @""} mutableCopy];
    __weak typeof(self) weakSelf = self;
    __weak DXPLinkActionEditorController *weakEditor = editor;
    NSString *slot = [self.slot copy];
    __block BOOL completed = NO;
    editor.completion = ^(NSDictionary *entry) {
        DXPStatusBarActionPicker *picker = weakSelf;
        if (completed || !picker || !DXStatusSlotValid(slot) || ![picker.slot isEqual:slot] ||
            ![picker.navigationController.viewControllers containsObject:picker] ||
            picker.navigationController.topViewController != weakEditor) return;
        DXPrefsManager *manager = DXPrefsManager.sharedInstance;
        NSMutableDictionary *preferences = [[manager readPrefs] mutableCopy];
        if (!preferences || ![entry isKindOfClass:NSDictionary.class] || !DXIsLinkActionSelector(entry[@"selector"])) return;
        id stored = preferences[kLinkActionskey];
        NSMutableArray *definitions = [stored isKindOfClass:NSArray.class] ? [stored mutableCopy] : [NSMutableArray array];
        [definitions addObject:entry]; preferences[kLinkActionskey] = definitions;
        completed = YES;
        [manager writePrefs:preferences];
        if (DXGlobalCustomActionSupported(DXStatusDefinition([manager readPrefs], entry[@"selector"]))) {
            picker.selectAfterSave = DXStatusSaveBinding(slot, @"selector", entry[@"selector"]);
        }
    };
    [editor setRootController:self.rootController]; [editor setParentController:self]; [self pushController:editor];
}
@end
