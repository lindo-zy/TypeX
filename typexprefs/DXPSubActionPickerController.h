#import <Preferences/PSListController.h>
#import <Preferences/PSSpecifier.h>

// Picker shown for one sub-action row: lists every available action and
// reports the chosen selector back through `completion`.
@interface DXPSubActionPickerController : PSViewController <UITableViewDelegate, UITableViewDataSource>
@property (strong, nonatomic) UITableView *tableView;
@property (nonatomic, strong) NSArray *fullOrder;
// Currently assigned selector (empty string when none was chosen yet).
@property (nonatomic, copy) NSString *selectedSelector;
// Called with the picked selector when the user taps an action.
@property (nonatomic, copy) void (^completion)(NSString *selector);
@end
