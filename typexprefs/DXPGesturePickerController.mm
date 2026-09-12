#import "DXPGesturePickerController.h"
#import "DXPCustomActionViewController.h"
#import "../DXHelper.h"
#import "../common.h"

static NSBundle *tweakBundle;


@implementation DXPGesturePickerController

#pragma mark - Per-shortcut custom name/icon storage

- (NSString *)scopedShortcutsKey {
    return [self.configuration isEqualToString:@"top"] ? kTopShortcutskey : kShortcutskey;
}

// Finds the stored shortcut dictionary (enabled or disabled section) whose
// selector matches this page's identifier, so custom overrides live on the same
// entry the toolbar already reads.
- (NSMutableDictionary *)storedShortcutEntry {
    NSDictionary *prefs = [[DXPrefsManager sharedInstance] readPrefs];
    NSArray *sections = prefs[[self scopedShortcutsKey]];
    if (![sections isKindOfClass:[NSArray class]]) return nil;
    for (NSArray *section in sections) {
        if (![section isKindOfClass:[NSArray class]]) continue;
        for (NSDictionary *item in section) {
            if ([item isKindOfClass:[NSDictionary class]] &&
                [item[@"selector"] isKindOfClass:[NSString class]] &&
                [item[@"selector"] isEqualToString:self.identifier]) {
                return [item mutableCopy];
            }
        }
    }
    return nil;
}

- (void)updateStoredShortcutEntryWithMutator:(void (^)(NSMutableDictionary *entry))mutator {
    NSMutableDictionary *prefs = [[[DXPrefsManager sharedInstance] readPrefs] mutableCopy] ?: [NSMutableDictionary dictionary];
    NSString *shortcutsKey = [self scopedShortcutsKey];
    NSArray *sections = prefs[shortcutsKey];
    if (![sections isKindOfClass:[NSArray class]]) return;

    NSMutableArray *mutableSections = [sections mutableCopy];
    BOOL found = NO;
    for (NSUInteger sectionIndex = 0; sectionIndex < mutableSections.count; sectionIndex++) {
        if (![mutableSections[sectionIndex] isKindOfClass:[NSArray class]]) continue;
        NSMutableArray *rows = [mutableSections[sectionIndex] mutableCopy];
        for (NSUInteger rowIndex = 0; rowIndex < rows.count; rowIndex++) {
            if (![rows[rowIndex] isKindOfClass:[NSDictionary class]]) continue;
            NSMutableDictionary *entry = [rows[rowIndex] mutableCopy];
            if (![entry[@"selector"] isKindOfClass:[NSString class]] ||
                ![entry[@"selector"] isEqualToString:self.identifier]) {
                continue;
            }
            mutator(entry);
            // Blank values clear the override so the built-in label/icon applies.
            for (NSString *customKey in @[@"name", @"icon"]) {
                NSString *value = entry[customKey];
                if (![value isKindOfClass:[NSString class]] || value.length == 0) {
                    [entry removeObjectForKey:customKey];
                }
            }
            rows[rowIndex] = entry;
            found = YES;
        }
        mutableSections[sectionIndex] = rows;
    }
    if (!found) return;

    prefs[shortcutsKey] = mutableSections;
    // writePrefs replaces the authoritative domain, mirrors the shared snapshot
    // and posts kPrefsChangedIdentifier so open toolbars reload immediately.
    [[DXPrefsManager sharedInstance] writePrefs:prefs];
}

#pragma mark - Specifier value handlers

- (id)readNameValue:(PSSpecifier *)specifier {
    return [self storedShortcutEntry][@"name"] ?: @"";
}

- (void)setNameValue:(id)value specifier:(PSSpecifier *)specifier {
    NSString *name = [value isKindOfClass:[NSString class]]
        ? [(NSString *)value stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]]
        : @"";
    [self updateStoredShortcutEntryWithMutator:^(NSMutableDictionary *entry) {
        entry[@"name"] = name;
    }];
}

- (id)readIconValue:(PSSpecifier *)specifier {
    return [self storedShortcutEntry][@"icon"] ?: @"";
}

- (void)setIconValue:(id)value specifier:(PSSpecifier *)specifier {
    NSString *icon = [value isKindOfClass:[NSString class]]
        ? [(NSString *)value stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]]
        : @"";

    // Only standard SF Symbol names are accepted; anything else keeps the
    // default icon instead of silently rendering a blank shortcut.
    if (icon.length > 0 && ![DXHelper customIconForShortcutItem:@{@"icon": icon}]) {
        UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"TypeX"
                                                                       message:LOCALIZED(@"CUSTOM_ICON_INVALID")
                                                                preferredStyle:UIAlertControllerStyleAlert];
        [alert addAction:[UIAlertAction actionWithTitle:LOCALIZED(@"ANSWER_YES")
                                                  style:UIAlertActionStyleCancel handler:nil]];
        [self presentViewController:alert animated:YES completion:nil];
    }

    [self updateStoredShortcutEntryWithMutator:^(NSMutableDictionary *entry) {
        entry[@"icon"] = icon;
    }];
}

#pragma mark - Specifiers

- (NSArray *)specifiers {
    if (!_specifiers) {
        NSMutableArray *snippetEntrySpecifiers = [[NSMutableArray alloc] init];

        PSSpecifier *displayGroup = [PSSpecifier preferenceSpecifierNamed:LOCALIZED(@"CUSTOM_APPEARANCE") target:nil set:nil get:nil detail:nil cell:PSGroupCell edit:nil];
        [displayGroup setProperty:LOCALIZED(@"FOOTER_CUSTOM_APPEARANCE") forKey:@"footerText"];
        [snippetEntrySpecifiers addObject:displayGroup];

        PSSpecifier *customNameSpec = [PSSpecifier preferenceSpecifierNamed:LOCALIZED(@"CUSTOM_NAME") target:self set:@selector(setNameValue:specifier:) get:@selector(readNameValue:) detail:nil cell:PSEditTextCell edit:nil];
        [customNameSpec setProperty:@YES forKey:@"noAutoCorrect"];
        [customNameSpec setProperty:LOCALIZED(@"CUSTOM_NAME") forKey:@"label"];
        [snippetEntrySpecifiers addObject:customNameSpec];

        PSSpecifier *customIconSpec = [PSSpecifier preferenceSpecifierNamed:LOCALIZED(@"CUSTOM_ICON") target:self set:@selector(setIconValue:specifier:) get:@selector(readIconValue:) detail:nil cell:PSEditTextCell edit:nil];
        [customIconSpec setProperty:@YES forKey:@"noAutoCorrect"];
        [customIconSpec setProperty:LOCALIZED(@"CUSTOM_ICON") forKey:@"label"];
        [snippetEntrySpecifiers addObject:customIconSpec];

        PSSpecifier *gestureTypeGroup = [PSSpecifier preferenceSpecifierNamed:LOCALIZED(@"GESTURES") target:nil set:nil get:nil detail:nil cell:PSGroupCell edit:nil];
        [snippetEntrySpecifiers addObject:gestureTypeGroup];

        PSSpecifier *longPressSpec = [PSSpecifier preferenceSpecifierNamed:LOCALIZED(@"LONG_PRESS") target:nil set:nil get:nil detail:NSClassFromString(@"DXPGesturePickerController") cell:PSLinkListCell edit:nil];
        [longPressSpec setProperty:LOCALIZED(@"LONG_PRESS") forKey:@"label"];
        [snippetEntrySpecifiers addObject:longPressSpec];

        _specifiers = snippetEntrySpecifiers;

    }

    return _specifiers;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath{

    UITableViewCell *cell = [tableView cellForRowAtIndexPath:indexPath];

    // The custom name/icon rows are plain edit-text cells handled by
    // Preferences; only the long-press row pushes the action editor.
    if (![cell.textLabel.text isEqualToString:LOCALIZED(@"LONG_PRESS")]) {
        [tableView deselectRowAtIndexPath:indexPath animated:YES];
        return;
    }

    DXPCustomActionViewController *actionViewController = [[DXPCustomActionViewController alloc] init];

    actionViewController.fullOrder = self.fullOrder;
    actionViewController.identifier = self.identifier;
    actionViewController.configuration = self.configuration;

    switch (indexPath.row) {
        case 0:
            actionViewController.keyID = [self.configuration isEqualToString:@"top"] ? kTopCustomActionskey : kCustomActionskey;
            break;
        default:
            actionViewController.keyID = [self.configuration isEqualToString:@"top"] ? kTopCustomActionskey : kCustomActionskey;
            break;
    }

    actionViewController.title = cell.textLabel.text;

    [actionViewController setRootController: [self rootController]];
    [actionViewController setParentController: [self parentController]];
    [self pushController:actionViewController];

    [tableView deselectRowAtIndexPath:indexPath animated:YES];


}

- (void)viewDidLoad {
    tweakBundle = [NSBundle bundleWithPath:bundlePath];
    [tweakBundle load];
    [super viewDidLoad];
}
@end
