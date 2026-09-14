#import <Preferences/PSListController.h>

// "选择应用" page: lists every installed app so the user can pick one for a
// custom action. Reports the app's name and bundle identifier through
// completion; the caller fills the editor's 名称/动作链接 fields.
@interface DXPAppPickerController : PSViewController <UITableViewDelegate, UITableViewDataSource, UISearchResultsUpdating>
// Trimmed 动作链接 value; apps whose bundle identifier matches it are shown
// under 已选择.
@property (nonatomic, copy) NSString *currentLink;
@property (nonatomic, copy) void (^completion)(NSString *name, NSString *bundleID);
@end
