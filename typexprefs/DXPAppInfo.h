#import <UIKit/UIKit.h>

// Where a listed quick action was found. The Home Screen icon menu merges
// all four planes: static items, dynamic items, (iOS 16+) App Shortcuts and
// the live list captured inside SpringBoard (the real menu as long-pressed,
// including system-merged suggestions).
typedef NS_ENUM(NSInteger, DXPAppShortcutSource) {
    DXPAppShortcutSourceStatic = 0,
    DXPAppShortcutSourceDynamic,
    DXPAppShortcutSourceAppIntent,
    DXPAppShortcutSourceSpringBoard,
};

// One home-screen quick action (a row of the menu shown when long-pressing an
// app icon). `type` is the stable identifier the system dispatches back to the
// app — UIApplicationShortcutItemType for static/dynamic items, the App
// Intents action identifier (e.g. "OpenCollectionIntent") for App Shortcuts;
// per the quick-action analysis the real payload is bundleID + type (there is
// no URL scheme behind these menu entries), so it is captured here even though
// this build only displays the list. userInfo/targetContentIdentifier are
// runtime objects that expire, so they are intentionally not stored.
@interface DXPAppShortcutItem : NSObject
@property (nonatomic, copy) NSString *type;
@property (nonatomic, copy) NSString *title;    // localized
@property (nonatomic, copy) NSString *subtitle; // localized or nil
@property (nonatomic, assign) DXPAppShortcutSource source;
@end

// Installed-app lookups for the custom-action editor's pickers: the app list
// and each app's home-screen quick actions. The quick-action catalogue is
// authored entirely inside SpringBoard — the catalogue refresh reads every
// installed app's system-resolved static and dynamic items (the Home Screen
// menu's own data source, via SBApplicationController) and real long-press
// captures overlay them, writing the shared plist the picker reads. Nothing
// is scanned from the Settings process. Siri donations beyond what
// SpringBoard merges into the icon menu are a separate system plane and are
// not collected.
@interface DXPAppInfo : NSObject
@property (nonatomic, copy) NSString *bundleID;
@property (nonatomic, copy) NSString *name;

// All installed apps, deduplicated by bundle identifier and sorted by
// localized name. Used by the open-app picker; the shortcut catalogue does
// not enumerate here.
+ (NSArray<DXPAppInfo *> *)installedApps;

// Apps that declare at least one quick action. Each entry is
// @{@"name": NSString, @"bundleID": NSString, @"items": NSArray<DXPAppShortcutItem *>}
// sorted by localized name, read from the shared SpringBoard-authored
// catalogue (TypeXSBShortcutsPath). Never throws and never nil; entries
// older than DXSBShortcutCaptureMaxAge are dropped.
+ (NSArray<NSDictionary *> *)appShortcutGroups;

// 44x44 rounded home-screen icon for a bundle identifier; falls back to a
// generic symbol when the private icon service returns nothing.
+ (UIImage *)iconForBundleID:(NSString *)bundleID;
@end
