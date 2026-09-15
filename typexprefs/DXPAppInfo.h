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

// Installed-app lookups for the custom-action editor's pickers: the app list,
// home-screen icons and each app's home-screen quick actions. Static items
// (the app's Info.plist UIApplicationShortcutItems), dynamic items (the
// UIApplicationShortcutItems key UIKit persists in the app's own
// data-container preferences when the app calls setShortcutItems:) and App
// Shortcuts (the autoShortcuts of the Metadata.appintents/
// extract.actionsdata metadata appintentsmetadataprocessor compiles into the
// bundle, localized through the bundle's .loctable / strings tables) are
// enumerated from Settings; the fourth source is the live list captured in
// SpringBoard when the user long-presses an icon (see TypeX.xm). Siri
// donations beyond what SpringBoard merges into the icon menu are a separate
// system plane and are not collected.
@interface DXPAppInfo : NSObject
@property (nonatomic, copy) NSString *bundleID;
@property (nonatomic, copy) NSString *name;

// All installed apps, deduplicated by bundle identifier and sorted by
// localized name.
+ (NSArray<DXPAppInfo *> *)installedApps;

// Live icon-menu captures written by the SpringBoard side of the tweak
// (TypeXSBShortcutsPath), keyed by bundle ID. A capture reflects the real
// merged menu, so it is the freshest source; entries older than
// DXSBShortcutCaptureMaxAge are dropped. Never throws and never nil.
+ (NSDictionary<NSString *, NSArray<DXPAppShortcutItem *> *> *)springBoardCapturedShortcutsByBundleID;

// Apps that declare at least one quick action, static or dynamic. Each entry
// is @{@"name": NSString, @"bundleID": NSString, @"items": NSArray<DXPAppShortcutItem *>}
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
