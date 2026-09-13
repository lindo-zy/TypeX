#import <Preferences/PSListController.h>
#import <Preferences/PSSpecifier.h>

// "添加子动作" page for one shortcut button: an ordered list of extra actions
// that run on tap. Supports adding, deleting (minus) and drag reordering.
@interface DXPSubActionsController : PSViewController <UITableViewDelegate, UITableViewDataSource>
@property (strong, nonatomic) UITableView *tableView;
// Owning button's identifier; kNewButtonPendingIdentifier while the button
// itself is still unsaved (re-keyed on Save by DXPGesturePickerController).
@property (nonatomic, readwrite) NSString *identifier;
@property (nonatomic, strong) NSArray *fullOrder;
@property (nonatomic, copy) NSString *configuration;
@end
