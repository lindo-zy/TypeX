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
// Multi-select mode (batch sub-action add): rows toggle checkmarks, nothing
// is persisted here, and the whole pick is reported through
// multiSelectionCompletion when the Done button taps out.
@property (nonatomic, assign) BOOL allowsMultipleSelection;
@property (nonatomic, copy) void (^multiSelectionCompletion)(NSArray<NSString *> *selectors);
// Standalone 自定义动作 management mode: the ONLY place custom actions are
// added or edited. The built-in action section is hidden, tapping a custom
// row opens its editor, and custom rows gain swipe delete. Picker modes list
// custom actions for selection only — no add row, no editing.
@property (nonatomic, assign) BOOL customActionsOnly;
@property (nonatomic, strong) NSMutableDictionary *prefs;
@property(nonatomic, retain) UIBarButtonItem *defaultBtn;
@property (nonatomic, copy) NSString *configuration;
@end
