#import <Preferences/PSViewController.h>

@class DXPAppInfo;

// Single-selection installed-app picker used by the Open App custom action.
// The editor owns persistence; this controller only returns the chosen app.
@interface DXPOpenAppPickerController : PSViewController <UITableViewDelegate, UITableViewDataSource, UISearchBarDelegate>
@property (nonatomic, copy) NSString *selectedBundleIdentifier;
@property (nonatomic, copy) void (^completion)(DXPAppInfo *app);
@end
