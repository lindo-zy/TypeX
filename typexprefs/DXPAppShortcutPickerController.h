#import <Preferences/PSListController.h>

// "选择快捷方式" page: shows every app's home-screen quick actions (the
// long-press menu), grouped one section per app. Rows show the localized
// title plus the item's UIApplicationShortcutItemType — per the quick-action
// analysis, bundleID + type is the real payload behind these entries (there
// is no URL scheme). Selectable mode reports the picked item through
// completion; without a completion (legacy preview) rows stay inert.
@interface DXPAppShortcutPickerController : PSViewController <UITableViewDelegate, UITableViewDataSource, UISearchResultsUpdating>
// Currently configured quick action, shown with a checkmark.
@property (nonatomic, copy) NSString *currentBundleID;
@property (nonatomic, copy) NSString *currentType;
// Fires once on pick with the item's localized title, its app's bundle
// identifier and the shortcut item type. Nil keeps the page display-only.
@property (nonatomic, copy) void (^completion)(NSString *title, NSString *bundleID, NSString *type);
@end
