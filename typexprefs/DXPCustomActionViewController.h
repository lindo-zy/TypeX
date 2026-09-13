#import <Preferences/PSListController.h>
#import <Preferences/PSSpecifier.h>

@interface DXPCustomActionViewController : PSViewController <UITableViewDelegate, UITableViewDataSource>
@property (strong, nonatomic) UITableView *tableView;
@property (nonatomic,readwrite) NSString *identifier;
@property (nonatomic,readwrite) NSString *keyID;
@property (nonatomic, strong) NSArray *fullOrder;
@property (nonatomic, strong) NSIndexPath *selectedIndexPath;
// Sub-action rows reuse this exact picker UI. In external mode selection is
// returned through completion instead of being stored as a gesture override.
@property (nonatomic, copy) NSString *selectedSelector;
@property (nonatomic, copy) void (^completion)(NSString *selector);
@property (nonatomic, assign) BOOL selectionManagedExternally;
@property (nonatomic, strong) NSMutableDictionary *prefs;
@property(nonatomic, retain) UIBarButtonItem *defaultBtn;
@property (nonatomic, copy) NSString *configuration;
@end
