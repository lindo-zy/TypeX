#import <Preferences/PSViewController.h>

// 生效应用 allowlist for the clipboard paste chip: every installed app with a
// switch, all off by default. Persisted as bundleID -> @YES under
// kPasteImageChipAppsKey in the shared preferences. A header search bar filters
// by display name or bundle ID on top of the enabled-only toggle.
@interface DXPPasteChipAppsController : PSViewController <UITableViewDelegate, UITableViewDataSource, UISearchBarDelegate>
@property (strong, nonatomic) UITableView *tableView;
@end
