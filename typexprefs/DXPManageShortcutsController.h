#import <Preferences/PSViewController.h>
#import <Preferences/PSSpecifier.h>
#import "../common.h"

@interface DXPManageShortcutsController : PSViewController <UITableViewDelegate, UITableViewDataSource, UISearchBarDelegate>
@property (strong, nonatomic) UITableView *tableView;
@property (nonatomic, strong) NSMutableArray *currentOrder;
@property (nonatomic, strong) NSMutableArray *extrasOptions;
@property (nonatomic, strong) NSArray *fullOrder;
@property(nonatomic, retain) UIBarButtonItem *resetBtn;
@property(nonatomic, copy) NSString *shortcutsPreferenceKey;
@property(nonatomic, assign, getter=isTopConfiguration) BOOL topConfiguration;
@end
