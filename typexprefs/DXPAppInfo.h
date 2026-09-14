#import <UIKit/UIKit.h>

// One home-screen quick action (a row of the menu shown when long-pressing an
// app icon). `type` is UIApplicationShortcutItemType — the stable identifier
// the system dispatches back to the app; per the quick-action analysis the
// real payload is bundleID + type (there is no URL scheme behind these menu
// entries), so it is captured here even though this build only displays the
// list. userInfo/targetContentIdentifier are runtime objects that expire, so
// they are intentionally not stored.
@interface DXPAppShortcutItem : NSObject
@property (nonatomic, copy) NSString *type;
@property (nonatomic, copy) NSString *title;    // localized
@property (nonatomic, copy) NSString *subtitle; // localized or nil
@end

// Installed-app lookups for the custom-action editor's pickers: the app list,
// home-screen icons and each app's static home-screen quick actions. Only
// static items (the app's Info.plist UIApplicationShortcutItems) can be
// enumerated from Settings; dynamic items are registered by the app at
// runtime and are only visible inside the app or SpringBoard.
@interface DXPAppInfo : NSObject
@property (nonatomic, copy) NSString *bundleID;
@property (nonatomic, copy) NSString *name;

// All installed apps, deduplicated by bundle identifier and sorted by
// localized name.
+ (NSArray<DXPAppInfo *> *)installedApps;

// Apps that declare at least one static quick action. Each entry is
// @{@"name": NSString, @"bundleID": NSString, @"items": NSArray<DXPAppShortcutItem *>}
// sorted by localized name. Never throws: apps whose metadata cannot be read
// are skipped so one broken bundle cannot take Settings down.
+ (NSArray<NSDictionary *> *)appShortcutGroups;

// Number of installed apps seen by the most recent appShortcutGroups scan;
// lets the picker distinguish "no app declares shortcuts" from "the scan
// itself came up empty".
+ (NSInteger)lastShortcutScanApplicationCount;

// 44x44 rounded home-screen icon for a bundle identifier; falls back to a
// generic symbol when the private icon service returns nothing.
+ (UIImage *)iconForBundleID:(NSString *)bundleID;
@end
