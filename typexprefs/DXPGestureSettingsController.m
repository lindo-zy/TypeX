#import "DXPGestureSettingsController.h"
#import "DXPStatusBarGestureController.h"
#import "DXPManageShortcutsController.h"
#import "../DXKeyboardPanelPreferences.h"
#import "../DXHelper.h"
#import "../common.h"
#import <Preferences/PSSpecifier.h>

static NSString *DXGestureLocalized(NSString *key) {
    return [[NSBundle bundleWithPath:bundlePath] localizedStringForKey:key value:key table:nil];
}

// The moved switches retain their original keys and defaults.
@interface DXPPanelGestureController : PSListController
- (PSSpecifier *)toggle:(NSString *)label key:(NSString *)key;
@end
@interface DXPDockGestureController : DXPPanelGestureController
@end
@interface DXPKeyboardGestureController : DXPPanelGestureController
@end

@implementation DXPGestureSettingsController
- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = DXGestureLocalized(@"GESTURE_SETTINGS");
}
- (NSArray *)specifiers {
    if (_specifiers) return _specifiers;
    NSMutableArray *items = [NSMutableArray array];
    for (NSArray *category in @[
        @[@"DOCK_GESTURE_SETTINGS", DXPDockGestureController.class, @"rectangle.bottomthird.inset.filled"],
        @[@"STATUS_BAR_SETTINGS", DXPStatusBarGestureController.class, @"arrow.up.square"],
        @[@"KEYBOARD_GESTURE_SETTINGS", DXPKeyboardGestureController.class, @"keyboard"]
    ]) {
        [items addObject:[PSSpecifier groupSpecifierWithName:nil]];
        PSSpecifier *link = [PSSpecifier preferenceSpecifierNamed:DXGestureLocalized(category[0]) target:self
            set:nil get:nil detail:category[1] cell:PSLinkCell edit:nil];
        [link setProperty:[DXHelper imageForIconConfig:category[2] defaultSymbolName:@"hand.draw"] forKey:@"iconImage"];
        [items addObject:link];
    }
    _specifiers = items;
    return _specifiers;
}
@end

@implementation DXPPanelGestureController
- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = self.specifier.name;
}
- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [self reloadSpecifiers];
}
- (PSSpecifier *)toggle:(NSString *)label key:(NSString *)key {
    PSSpecifier *item = [PSSpecifier preferenceSpecifierNamed:DXGestureLocalized(label) target:self
        set:@selector(setPreferenceValue:specifier:) get:@selector(readPreferenceValue:) detail:nil cell:PSSwitchCell edit:nil];
    [item setProperty:key forKey:@"key"];
    [item setProperty:@YES forKey:@"default"];
    return item;
}
- (id)readPreferenceValue:(PSSpecifier *)specifier {
    NSDictionary *preferences = [[DXPrefsManager sharedInstance] readPrefs];
    return @(DXKeyboardPanelBool(preferences, [specifier propertyForKey:@"key"], YES));
}
- (void)setPreferenceValue:(id)value specifier:(PSSpecifier *)specifier {
    NSString *key = [specifier propertyForKey:@"key"];
    if (key.length && [value isKindOfClass:NSNumber.class])
        [[DXPrefsManager sharedInstance] setValue:@([value boolValue]) forKey:key];
}
@end

@implementation DXPDockGestureController
- (NSArray *)specifiers {
    if (_specifiers) return _specifiers;
    PSSpecifier *group = [PSSpecifier groupSpecifierWithName:nil];
    [group setProperty:DXGestureLocalized(@"DOCK_GESTURE_FOOTER") forKey:@"footerText"];
    _specifiers = [@[group, [self toggle:@"GLOBAL_PANEL_DOCK_SWIPE" key:kDXPanelDockSwipeEnabled]] mutableCopy];
    return _specifiers;
}
@end

@implementation DXPKeyboardGestureController
- (NSArray *)specifiers {
    if (_specifiers) return _specifiers;
    NSMutableArray *items = [NSMutableArray array];
    PSSpecifier *group = [PSSpecifier groupSpecifierWithName:DXGestureLocalized(@"KEYBOARD_PANEL_ENTRANCE")];
    [group setProperty:DXGestureLocalized(@"KEYBOARD_PANEL_GESTURE_FOOTER") forKey:@"footerText"];
    [items addObject:group];
    [items addObject:[self toggle:@"KEYBOARD_PANEL_TOP" key:kDXPanelTopEnabled]];
    [items addObject:[self toggle:@"KEYBOARD_PANEL_BOTTOM" key:kDXPanelBottomEnabled]];
    group = [PSSpecifier groupSpecifierWithName:DXGestureLocalized(@"TOOLBAR_BUTTON_GESTURES")];
    [group setProperty:DXGestureLocalized(@"TOOLBAR_BUTTON_GESTURES_FOOTER") forKey:@"footerText"];
    [items addObject:group];
    for (NSArray *toolbar in @[@[@"top", @"TOP_BUTTON_GESTURES"], @[@"bottom", @"BOTTOM_BUTTON_GESTURES"]]) {
        PSSpecifier *link = [PSSpecifier preferenceSpecifierNamed:DXGestureLocalized(toolbar[1]) target:self
            set:nil get:nil detail:DXPManageShortcutsController.class cell:PSLinkCell edit:nil];
        [link setProperty:toolbar[0] forKey:@"configuration"];
        [items addObject:link];
    }
    _specifiers = items;
    return _specifiers;
}
@end
