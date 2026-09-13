#import <Preferences/PSViewController.h>
#import <Preferences/PSSpecifier.h>
#import "../common.h"

@interface DXPManageShortcutsController : PSViewController <UITableViewDelegate, UITableViewDataSource, UITextFieldDelegate>
@property (strong, nonatomic) UITableView *tableView;
@property (strong, nonatomic) UITextField *testInputField;
@property (nonatomic, strong) NSMutableArray *currentOrder;
@property (nonatomic, strong) NSArray *fullOrder;
@property(nonatomic, retain) UIBarButtonItem *addBtn;
@property(nonatomic, copy) NSString *shortcutsPreferenceKey;
@property(nonatomic, assign, getter=isTopConfiguration) BOOL topConfiguration;
@end
