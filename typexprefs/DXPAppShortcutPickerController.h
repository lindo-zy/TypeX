#import <Preferences/PSListController.h>

// "选择快捷方式" page: shows every app's static home-screen quick actions
// (the long-press menu), grouped one section per app. Rows show the localized
// title plus the item's UIApplicationShortcutItemType — per the quick-action
// analysis, bundleID + type is the real payload behind these entries (there
// is no URL scheme). Display only for now: rows are not selectable and
// nothing is written back.
@interface DXPAppShortcutPickerController : PSViewController <UITableViewDelegate, UITableViewDataSource, UISearchResultsUpdating>
@end
