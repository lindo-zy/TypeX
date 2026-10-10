#import "DXPFloatingAppController.h"
#import "DXPPanelSliderCell.h"
#import "../DXHelper.h"
#import "../common.h"
#import <Preferences/PSSpecifier.h>

static NSString *DXFloatingLocalized(NSString *key) {
    return [[NSBundle bundleWithPath:bundlePath] localizedStringForKey:key value:key table:nil];
}

// 悬浮打开应用小窗的全局设置。比例键由 DXFloatingCardMaxScaleFromPreferences
// 消费（键盘工具栏触发的 SpringBoard 托管卡片读取同一份快照）。
@implementation DXPFloatingAppController
- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = DXFloatingLocalized(@"FLOATING_APP_SETTINGS");
}
- (NSArray *)specifiers {
    if (_specifiers) return _specifiers;
    PSSpecifier *group = [PSSpecifier groupSpecifierWithName:DXFloatingLocalized(@"FLOATING_APP_SIZE_GROUP")];
    [group setProperty:DXFloatingLocalized(@"FLOATING_APP_SCALE_FOOTER") forKey:@"footerText"];
    PSSpecifier *scale = [PSSpecifier preferenceSpecifierNamed:DXFloatingLocalized(@"FLOATING_APP_MAX_SCALE") target:self
        set:@selector(setPreferenceValue:specifier:) get:@selector(readPreferenceValue:) detail:nil cell:PSStaticTextCell edit:nil];
    [scale setProperty:kFloatingCardMaxScaleKey forKey:@"key"];
    [scale setProperty:@72 forKey:@"default"];
    [scale setProperty:DXPPanelSliderCell.class forKey:@"cellClass"];
    [scale setProperty:@30 forKey:@"min"];
    [scale setProperty:@100 forKey:@"max"];
    [scale setProperty:@YES forKey:@"showValue"];
    _specifiers = [@[group, scale] mutableCopy];
    return _specifiers;
}
- (id)readPreferenceValue:(PSSpecifier *)specifier {
    NSDictionary *preferences = [DXPrefsManager.sharedInstance readPrefs];
    id value = preferences[[specifier propertyForKey:@"key"]];
    return [value respondsToSelector:@selector(floatValue)] ? value : [specifier propertyForKey:@"default"];
}
// 与 DXPKeyboardPanelController 相同：滑杆单元需要 80pt 行高。
- (CGFloat)tableView:(UITableView *)table heightForRowAtIndexPath:(NSIndexPath *)path {
    if ([[self specifierAtIndexPath:path] propertyForKey:@"cellClass"] == DXPPanelSliderCell.class) return 80;
    return [super tableView:table heightForRowAtIndexPath:path];
}
- (void)setPreferenceValue:(id)value specifier:(PSSpecifier *)specifier {
    if (![value isKindOfClass:NSNumber.class]) return;
    // 与滑杆 5% 步进一致；越界值夹回，避免写进快照后触发读取侧缺省回退。
    NSInteger percent = MIN(100, MAX(30, lround([value doubleValue] / 5) * 5));
    [DXPrefsManager.sharedInstance setValue:@(percent) forKey:[specifier propertyForKey:@"key"]];
}
@end
