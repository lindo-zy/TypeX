#import <UIKit/UIKit.h>

// The authoritative SBApplication collection that supplied the item.
typedef NS_ENUM(NSInteger, DXPAppShortcutSource) {
    DXPAppShortcutSourceStatic = 0,
    DXPAppShortcutSourceDynamic,
};

// One home-screen quick action (a row of the menu shown when long-pressing an
// app icon). `type` is the stable identifier the system dispatches back to the
// app. The persistent selection is bundleID + type; SpringBoard re-resolves
// the current object at execution time so userInfo remains current.
@interface DXPAppShortcutItem : NSObject
@property (nonatomic, copy) NSString *type;
@property (nonatomic, copy) NSString *title;    // localized
@property (nonatomic, copy) NSString *subtitle; // localized or nil
@property (nonatomic, assign) DXPAppShortcutSource source;
@end

// Installed-app lookups for the custom-action editor's pickers: the app list
// and each app's static/dynamic home-screen quick actions. Settings enumerates
// apps through LaunchServices; SpringBoard resolves the actual shortcut items
// and replaces one complete shared snapshot.
@interface DXPAppInfo : NSObject
@property (nonatomic, copy) NSString *bundleID;
@property (nonatomic, copy) NSString *name;

// All installed apps, deduplicated by bundle identifier and sorted by
// localized name. Used by the open-app picker; the shortcut catalogue does
// not enumerate here.
+ (NSArray<DXPAppInfo *> *)installedApps;

// Apps that declare at least one quick action. Each entry is
// @{@"name": NSString, @"bundleID": NSString, @"items": NSArray<DXPAppShortcutItem *>}
// sorted by localized name, read from the format-3 SpringBoard snapshot.
// Never throws and never returns nil.
+ (NSArray<NSDictionary *> *)appShortcutGroups;

// 44x44 rounded home-screen icon for a bundle identifier; falls back to a
// generic symbol when the private icon service returns nothing.
+ (UIImage *)iconForBundleID:(NSString *)bundleID;
@end
