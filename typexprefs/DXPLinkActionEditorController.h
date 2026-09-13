#import <Preferences/PSListController.h>

// Edits one user-defined URL action. The caller owns persistence and receives
// a normalized entry when Save is tapped.
@interface DXPLinkActionEditorController : PSViewController <UITableViewDelegate, UITableViewDataSource, UITextFieldDelegate>
@property (nonatomic, strong) NSMutableDictionary *entry;
@property (nonatomic, copy) void (^completion)(NSDictionary *entry);
@end
