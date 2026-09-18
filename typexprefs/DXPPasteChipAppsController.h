#import <Preferences/PSViewController.h>

// 生效应用 allowlist for the clipboard paste chip: every installed app with a
// switch, all off by default. Persisted as bundleID -> @YES under
// kPasteImageChipAppsKey in the shared preferences.
@interface DXPPasteChipAppsController : PSViewController <UITableViewDelegate, UITableViewDataSource>
@property (strong, nonatomic) UITableView *tableView;
@end
