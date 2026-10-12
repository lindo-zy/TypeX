import os
import pathlib
import subprocess
import tempfile

root = pathlib.Path(__file__).resolve().parent.parent

# Compile the REAL management-page sources (base + standalone page) against
# narrow UIKit/Preferences doubles and drive the full click surface, so the
# device crash class (derived sections + editor-save hooks) reproduces on
# macOS instead of on the phone.

defines = {
    "kLinkActionskey": "linkactions",
    "kLinkActionSelectorPrefix": "__typex_link_action_",
    "kLinkActionGroupsKey": "linkactiongroups",
    "kCustomActionGroupKey": "group",
    "kCustomActionTypeKey": "type",
    "kCustomActionInAppKey": "inapp",
    "kCustomActionUsePullOverKey": "pullover",
    "kCustomActionFloatingKey": "floating",
    "kCustomActionCutReplaceKey": "cutreplace",
    "kCustomActionTextRecordsKey": "textrecords",
    "kCustomActionShortcutTypeKey": "shortcuttype",
    "kCustomActionShortcutTitleKey": "shortcuttitle",
    "kCustomActionSystemIdentifierKey": "systemaction",
    "kCustomActionTypeURLScheme": "urlscheme",
    "kCustomActionTypeText": "text",
    "kCustomActionTypeURL": "url",
    "kCustomActionTypeOpenApp": "openapp",
    "kCustomActionTypeShortcut": "shortcut",
    "kCustomActionTypeJavaScript": "javascript",
    "kCustomActionTypeSystem": "system",
}
common = (root / "common.h").read_text()
for name, value in defines.items():
    assert f'#define {name} @"{value}"' in common, f"{name} drifted from common.h"

# Every plain k*/DX* macro from common.h (the bundle-path/localization macros
# and roothide path shims are provided by the harness instead).
macro_lines = []
for line in common.splitlines():
    if not (line.startswith("#define k") or line.startswith("#define DX")): continue
    if "jbroot" in line or "ROOT_PATH_NS" in line or line.startswith("#define DX_ROOT"): continue
    macro_lines.append(line)

scoped_start = common.index("static inline NSString *DXScopedPreferenceKey")
scoped_end = common.index("static inline NSInteger DXMultiRowButtonsPerRowFromPreferences", scoped_start)
gesture_start = common.index("typedef NS_ENUM(NSInteger, DXShortcutGestureType)")
gesture_end = common.index("// Shared by Settings and toolbar hosts", gesture_start)

common_block = "\n".join(macro_lines) + "\n" + common[scoped_start:scoped_end] + common[gesture_start:gesture_end]
assert "DXCustomActionsKeyForGesture" in common_block and "DXPlaceCaretAtEnd" not in common_block

stub_extensions = '''
#import <objc/runtime.h>
@class UISearchController;
@protocol UISearchResultsUpdating
@optional
- (void)updateSearchResultsForSearchController:(UISearchController *)searchController;
@end
@class UITableView, UITableViewCell;
@protocol UITableViewDataSource
- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView;
- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section;
- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath;
@end
@protocol UITableViewDelegate
@end
typedef NS_ENUM(NSInteger, UIViewContentMode) { UIViewContentModeScaleAspectFit, UIViewContentModeScaleAspectFill };
@interface NSLayoutConstraint : NSObject
+ (void)activateConstraints:(NSArray *)constraints;
@end
@implementation NSLayoutConstraint
+ (void)activateConstraints:(NSArray *)constraints { (void)constraints; }
@end
@interface HarnessLayoutAnchor : NSObject
- (id)constraintEqualToAnchor:(id)anchor;
- (id)constraintLessThanOrEqualToAnchor:(id)anchor;
- (id)constraintLessThanOrEqualToAnchor:(id)anchor constant:(CGFloat)constant;
@end
@implementation HarnessLayoutAnchor
- (id)constraintEqualToAnchor:(id)anchor { (void)anchor; return [NSLayoutConstraint new]; }
- (id)constraintLessThanOrEqualToAnchor:(id)anchor { (void)anchor; return [NSLayoutConstraint new]; }
- (id)constraintLessThanOrEqualToAnchor:(id)anchor constant:(CGFloat)constant { (void)anchor; (void)constant; return [NSLayoutConstraint new]; }
@end
@interface HarnessLayoutDimension : HarnessLayoutAnchor
- (id)constraintEqualToConstant:(CGFloat)constant;
@end
@implementation HarnessLayoutDimension
- (id)constraintEqualToConstant:(CGFloat)constant { (void)constant; return [NSLayoutConstraint new]; }
@end
@interface HarnessLayoutGuide : NSObject
- (id)leadingAnchor;
- (id)trailingAnchor;
- (id)centerYAnchor;
@end
@implementation HarnessLayoutGuide
- (id)leadingAnchor { return [HarnessLayoutAnchor new]; }
- (id)trailingAnchor { return [HarnessLayoutAnchor new]; }
- (id)centerYAnchor { return [HarnessLayoutDimension new]; }
@end
@class UIColor;
// CoreGraphics externs the harness sources reference; defined locally because
// the test links Foundation only.
CGFloat CGRectGetHeight(CGRect rect) { return rect.size.height; }
CGFloat CGRectGetWidth(CGRect rect) { return rect.size.width; }
const CGRect CGRectZero = {{0.0, 0.0}, {0.0, 0.0}};
@interface UIView : NSObject
@property(nonatomic) CGRect bounds, frame;
@property(nonatomic) UIViewContentMode contentMode;
@property(nonatomic, strong) UIColor *backgroundColor;
@property(nonatomic, strong) HarnessLayoutGuide *layoutMarginsGuide;
@property(nonatomic) BOOL translatesAutoresizingMaskIntoConstraints;
- (instancetype)initWithFrame:(CGRect)frame;
- (void)addSubview:(UIView *)view;
@end
@implementation UIView
- (instancetype)initWithFrame:(CGRect)frame { (void)frame; return [super init]; }
- (void)addSubview:(UIView *)view { (void)view; }
@end
@interface UIView (HarnessHierarchy)
@property(nonatomic, readonly) UIView *superview;
@end
@implementation UIView (HarnessHierarchy)
- (UIView *)superview { return nil; }
@end
@interface UIView (HarnessAnchors)
@property(nonatomic, readonly) HarnessLayoutAnchor *leadingAnchor, *trailingAnchor;
@property(nonatomic, readonly) HarnessLayoutDimension *centerYAnchor, *widthAnchor, *heightAnchor;
@end
@implementation UIView (HarnessAnchors)
- (id)leadingAnchor { return [HarnessLayoutAnchor new]; }
- (id)trailingAnchor { return [HarnessLayoutAnchor new]; }
- (id)centerYAnchor { return [HarnessLayoutDimension new]; }
- (id)widthAnchor { return [HarnessLayoutDimension new]; }
- (id)heightAnchor { return [HarnessLayoutDimension new]; }
@end
@interface NSIndexPath (Harness)
@property(nonatomic, readonly) NSInteger row, section;
+ (instancetype)indexPathForRow:(NSInteger)row inSection:(NSInteger)section;
@end
@implementation NSIndexPath (Harness)
+ (instancetype)indexPathForRow:(NSInteger)row inSection:(NSInteger)section {
    NSUInteger indexes[] = {(NSUInteger)section, (NSUInteger)row};
    return [self indexPathWithIndexes:indexes length:2];
}
- (NSInteger)row { return [self indexAtPosition:1]; }
- (NSInteger)section { return [self indexAtPosition:0]; }
@end
'''

table_replacement = '''typedef NS_ENUM(NSInteger, UIScrollViewKeyboardDismissMode) { UIScrollViewKeyboardDismissModeInteractive };
typedef NS_ENUM(NSInteger, UITableViewStyle) { UITableViewStylePlain, UITableViewStyleInsetGrouped };
typedef NS_ENUM(NSInteger, UITableViewRowAnimation) { UITableViewRowAnimationAutomatic, UITableViewRowAnimationNone };
typedef NS_ENUM(NSInteger, UITableViewCellEditingStyle) { UITableViewCellEditingStyleNone, UITableViewCellEditingStyleDelete };
static const CGFloat UITableViewAutomaticDimension = -1.0;
typedef NS_ENUM(NSInteger, UIViewAutoresizing) { UIViewAutoresizingNone = 0, UIViewAutoresizingFlexibleWidth = 1 << 1, UIViewAutoresizingFlexibleHeight = 1 << 4 };
typedef NS_ENUM(NSInteger, UIControlState) { UIControlStateNormal };
typedef NS_ENUM(NSInteger, UIControlEvents) { UIControlEventTouchUpInside = 1 << 6 };
typedef NS_ENUM(NSInteger, UIButtonType) { UIButtonTypeCustom, UIButtonTypeSystem };
typedef NS_ENUM(NSInteger, UIContextualActionStyle) { UIContextualActionStyleDefault, UIContextualActionStyleDestructive };
typedef NS_ENUM(NSInteger, UIBarButtonItemStyle) { UIBarButtonItemStylePlain, UIBarButtonItemStyleDone };
static const NSInteger UIFontWeightSemibold = 4;
static const NSInteger UITableViewCellSelectionStyleNone = 0;
static BOOL RenderOnDataSourceAssignment;
@interface UITableView : UIView
@property(nonatomic, weak) id delegate, dataSource;
@property(nonatomic) UITableViewStyle style;
@property(nonatomic) UIViewAutoresizing autoresizingMask;
@property(nonatomic) UIScrollViewKeyboardDismissMode keyboardDismissMode;
@property(nonatomic, strong) UIView *backgroundView;
@property(nonatomic, getter=isEditing) BOOL editing;
@property(nonatomic) BOOL allowsSelectionDuringEditing;
@property(nonatomic) NSUInteger deselections;
@property(nonatomic) NSMutableArray *reloads, *inserts, *deletes, *moves;
@property(nonatomic) NSInteger reloadAllCount;
@property(nonatomic) NSMutableArray *registeredCellIDs;
@property(nonatomic) NSMutableDictionary *registeredCellClasses;
@property(nonatomic) NSUInteger dequeueCount;
@property(nonatomic) BOOL renderRowsOnReload;
@property(nonatomic, strong) UITableViewCell *reusableCell;
- (instancetype)initWithFrame:(CGRect)frame style:(UITableViewStyle)style;
- (void)registerClass:(Class)cellClass forCellReuseIdentifier:(NSString *)identifier;
- (UITableViewCell *)dequeueReusableCellWithIdentifier:(NSString *)identifier forIndexPath:(NSIndexPath *)indexPath;
- (UITableViewCell *)dequeueReusableCellWithIdentifier:(NSString *)identifier;
- (void)deselectRowAtIndexPath:(NSIndexPath *)indexPath animated:(BOOL)animated;
- (void)setEditing:(BOOL)editing animated:(BOOL)animated;
- (NSArray *)indexPathsForVisibleRows;
- (void)reloadRowsAtIndexPaths:(NSArray *)indexPaths withRowAnimation:(UITableViewRowAnimation)animation;
- (void)insertRowsAtIndexPaths:(NSArray *)indexPaths withRowAnimation:(UITableViewRowAnimation)animation;
- (void)deleteRowsAtIndexPaths:(NSArray *)indexPaths withRowAnimation:(UITableViewRowAnimation)animation;
- (void)reloadData;
- (NSIndexPath *)indexPathForCell:(UITableViewCell *)cell;
@end
@implementation UITableView
- (instancetype)initWithFrame:(CGRect)frame style:(UITableViewStyle)style {
    (void)frame; (void)style;
    if ((self = [super init])) { _reloads = [NSMutableArray array]; _inserts = [NSMutableArray array]; _deletes = [NSMutableArray array]; _moves = [NSMutableArray array]; }
    return self;
}
- (void)registerClass:(Class)cellClass forCellReuseIdentifier:(NSString *)identifier {
    if (!self.registeredCellIDs) self.registeredCellIDs = [NSMutableArray array];
    if (!self.registeredCellClasses) self.registeredCellClasses = [NSMutableDictionary dictionary];
    [self.registeredCellIDs addObject:identifier];
    self.registeredCellClasses[identifier] = cellClass;
}
- (UITableViewCell *)dequeueReusableCellWithIdentifier:(NSString *)identifier forIndexPath:(NSIndexPath *)indexPath {
    // Mirror UIKit: dequeue-by-indexPath throws when the identifier was never
    // registered on THIS table instance (the 4.6.6 device crash class).
    NSCAssert([self.registeredCellIDs containsObject:identifier], @"dequeue unregistered cell %@", identifier);
    self.dequeueCount++;
    Class cellClass = self.registeredCellClasses[identifier];
    return [[cellClass alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:identifier];
}
- (UITableViewCell *)dequeueReusableCellWithIdentifier:(NSString *)identifier { (void)identifier; return self.reusableCell; }
- (void)deselectRowAtIndexPath:(NSIndexPath *)indexPath animated:(BOOL)animated { (void)indexPath; (void)animated; self.deselections++; }
- (void)setEditing:(BOOL)editing animated:(BOOL)animated { (void)animated; _editing = editing; }
- (NSArray *)indexPathsForVisibleRows { return @[]; }
- (void)reloadRowsAtIndexPaths:(NSArray *)indexPaths withRowAnimation:(UITableViewRowAnimation)animation { (void)animation; [self.reloads addObjectsFromArray:indexPaths]; }
- (void)insertRowsAtIndexPaths:(NSArray *)indexPaths withRowAnimation:(UITableViewRowAnimation)animation { (void)animation; [self.inserts addObjectsFromArray:indexPaths]; }
- (void)deleteRowsAtIndexPaths:(NSArray *)indexPaths withRowAnimation:(UITableViewRowAnimation)animation { (void)animation; [self.deletes addObjectsFromArray:indexPaths]; }
- (void)setDataSource:(id)dataSource {
    _dataSource = dataSource;
    if (RenderOnDataSourceAssignment) {
        self.renderRowsOnReload = YES;
        [self reloadData];
    }
}
- (void)reloadData {
    self.reloadAllCount++;
    if (!self.renderRowsOnReload) return;
    for (NSInteger section = 0; section < [self.dataSource numberOfSectionsInTableView:self]; section++) {
        NSInteger rows = [self.dataSource tableView:self numberOfRowsInSection:section];
        for (NSInteger row = 0; row < rows; row++) {
            UITableViewCell *cell = [self.dataSource tableView:self cellForRowAtIndexPath:[NSIndexPath indexPathForRow:row inSection:section]];
            NSCAssert(cell != nil, @"data source must return a cell");
        }
    }
}
- (NSIndexPath *)indexPathForCell:(UITableViewCell *)cell { (void)cell; return nil; }
@end
'''

navigation_replacement = '''@class UITableView;
@interface UINavigationItem : NSObject
@property(nonatomic, strong) id searchController;
@property(nonatomic) BOOL hidesSearchBarWhenScrolling;
@property(nonatomic, strong) id rightBarButtonItem;
@end
@implementation UINavigationItem @end
@interface UIBarButtonItem : NSObject
@property(nonatomic, copy) NSString *title;
- (instancetype)initWithTitle:(NSString *)title style:(NSInteger)style target:(id)target action:(SEL)action;
@end
@implementation UIBarButtonItem
- (instancetype)initWithTitle:(NSString *)title style:(NSInteger)style target:(id)target action:(SEL)action {
    (void)title; (void)style; (void)target; (void)action; return [self init];
}
@end
@interface PSViewController : NSObject {
@protected UIView *_harnessView;
}
@property(nonatomic, copy) NSString *title;
@property(nonatomic, strong) UINavigationController *navigationController;
@property(nonatomic, weak) id rootController;
@property(nonatomic, weak) id parentController;
@property(nonatomic, strong) id presentedViewController;
@property(nonatomic, strong) UIView *view;
@property(nonatomic, strong) UINavigationItem *navigationItem;
@property(nonatomic) BOOL definesPresentationContext;
- (void)viewDidLoad;
- (void)viewWillAppear:(BOOL)animated;
- (void)viewDidAppear:(BOOL)animated;
- (void)pushController:(PSViewController *)controller;
- (void)presentViewController:(id)controller animated:(BOOL)animated completion:(void (^)(void))completion;
@end
@implementation PSViewController
- (UIView *)view { if (!_harnessView) _harnessView = [[UIView alloc] init]; return _harnessView; }
- (void)setView:(UIView *)view { _harnessView = view; }
- (UINavigationItem *)navigationItem { if (!_navigationItem) _navigationItem = [UINavigationItem new]; return _navigationItem; }
- (void)viewDidLoad {}
- (void)viewWillAppear:(BOOL)animated { (void)animated; }
- (void)viewDidAppear:(BOOL)animated { (void)animated; }
- (void)pushController:(PSViewController *)controller {
    controller.navigationController = self.navigationController;
    self.navigationController.viewControllers = [self.navigationController.viewControllers arrayByAddingObject:controller];
}
- (void)presentViewController:(id)controller animated:(BOOL)animated completion:(void (^)(void))completion {
    (void)animated; self.presentedViewController = controller; if (completion) completion();
}
@end
'''

extra_uikit = '''
@implementation UIColor (HarnessColors)
+ (UIColor *)systemBlueColor { return (id)@"blue"; }
+ (UIColor *)systemGreenColor { return (id)@"green"; }
+ (UIColor *)clearColor { return (id)@"clear"; }
@end
@interface UIFont : NSObject
+ (UIFont *)systemFontOfSize:(CGFloat)size weight:(NSInteger)weight;
@end
@implementation UIFont
+ (UIFont *)systemFontOfSize:(CGFloat)size weight:(NSInteger)weight { (void)size; (void)weight; return [UIFont new]; }
@end
@interface UIButton : UIView
@property(nonatomic, strong) UIColor *tintColor;
@property(nonatomic) NSInteger tag;
+ (instancetype)buttonWithType:(NSInteger)type;
- (void)setImage:(UIImage *)image forState:(NSInteger)state;
- (void)addTarget:(id)target action:(SEL)action forControlEvents:(UIControlEvents)events;
@end
@implementation UIButton
+ (instancetype)buttonWithType:(NSInteger)type { (void)type; return [[self alloc] init]; }
- (void)setImage:(UIImage *)image forState:(NSInteger)state { (void)image; (void)state; }
- (void)addTarget:(id)target action:(SEL)action forControlEvents:(UIControlEvents)events { (void)target; (void)action; (void)events; }
@end
@interface UIImage (Harness)
+ (UIImage *)systemImageNamed:(NSString *)name;
@end
@implementation UIImage (Harness)
+ (UIImage *)systemImageNamed:(NSString *)name { (void)name; return nil; }
@end
@interface UISearchBar : NSObject
@property(nonatomic, copy) NSString *text;
@end
@implementation UISearchBar @end
@interface UISearchController : NSObject
@property(nonatomic, weak) id searchResultsUpdater;
@property(nonatomic) BOOL obscuresBackgroundDuringPresentation;
@property(nonatomic, strong) UISearchBar *searchBar;
- (instancetype)initWithSearchResultsController:(id)results;
@end
@implementation UISearchController
- (instancetype)initWithSearchResultsController:(id)results {
    (void)results;
    if ((self = [super init])) _searchBar = [UISearchBar new];
    return self;
}
@end
@interface UIContextualAction : NSObject
@property(nonatomic, copy) void (^handler)(UIContextualAction *, UIView *, void (^)(BOOL));
+ (instancetype)contextualActionWithStyle:(NSInteger)style title:(NSString *)title handler:(void (^)(UIContextualAction *, UIView *, void (^)(BOOL)))handler;
@end
@implementation UIContextualAction
+ (instancetype)contextualActionWithStyle:(NSInteger)style title:(NSString *)title handler:(void (^)(UIContextualAction *, UIView *, void (^)(BOOL)))handler {
    (void)style; (void)title;
    UIContextualAction *action = [self new]; action.handler = handler; return action;
}
@end
@interface UISwipeActionsConfiguration : NSObject
@property(nonatomic) BOOL performsFirstActionWithFullSwipe;
+ (instancetype)configurationWithActions:(NSArray *)actions;
@end
@implementation UISwipeActionsConfiguration
+ (instancetype)configurationWithActions:(NSArray *)actions { (void)actions; return [self new]; }
@end
@interface UIMenu : NSObject
@property(nonatomic, copy) NSArray *children;
+ (instancetype)menuWithTitle:(NSString *)title children:(NSArray *)children;
@end
@implementation UIMenu
+ (instancetype)menuWithTitle:(NSString *)title children:(NSArray *)children { (void)title; UIMenu *menu = [self new]; menu.children = children; return menu; }
@end
@interface UIAction : NSObject
@property(nonatomic, copy) void (^handler)(UIAction *);
+ (instancetype)actionWithTitle:(NSString *)title image:(UIImage *)image identifier:(id)identifier handler:(void (^)(UIAction *))handler;
@end
@implementation UIAction
+ (instancetype)actionWithTitle:(NSString *)title image:(UIImage *)image identifier:(id)identifier handler:(void (^)(UIAction *))handler {
    (void)title; (void)image; (void)identifier;
    UIAction *action = [self new]; action.handler = handler; return action;
}
@end
@interface UIContextMenuConfiguration : NSObject
@property(nonatomic, copy) UIMenu *(^actionProvider)(NSArray *);
+ (instancetype)configurationWithIdentifier:(id)identifier previewProvider:(id)preview actionProvider:(UIMenu *(^)(NSArray *))actionProvider;
@end
@implementation UIContextMenuConfiguration
+ (instancetype)configurationWithIdentifier:(id)identifier previewProvider:(id)preview actionProvider:(UIMenu *(^)(NSArray *))actionProvider {
    (void)identifier; (void)preview;
    UIContextMenuConfiguration *configuration = [self new]; configuration.actionProvider = actionProvider; return configuration;
}
@end
@interface UITextField : NSObject
@property(nonatomic, copy) NSString *text, *placeholder;
@end
@implementation UITextField @end
// Alert text fields are keyed by non-retained object identity (ARC-safe).
static NSMutableDictionary<NSValue *, NSMutableArray *> *AlertTextStorage;
@interface UIAlertController (Harness)
- (void)addTextFieldWithConfigurationHandler:(void (^)(UITextField *))handler;
- (NSArray<UITextField *> *)textFields;
@end
@implementation UIAlertController (Harness)
- (void)addTextFieldWithConfigurationHandler:(void (^)(UITextField *))handler {
    if (!AlertTextStorage) AlertTextStorage = [NSMutableDictionary dictionary];
    NSValue *key = [NSValue valueWithNonretainedObject:self];
    NSMutableArray *fields = AlertTextStorage[key] ?: [NSMutableArray array];
    UITextField *field = [UITextField new];
    handler(field);
    [fields addObject:field];
    AlertTextStorage[key] = fields;
}
- (NSArray *)textFields { return AlertTextStorage[[NSValue valueWithNonretainedObject:self]] ?: @[]; }
@end
@interface DXPAppInfo : NSObject
@property(nonatomic, copy) NSString *bundleID, *name;
+ (NSString *)displayNameForBundleID:(NSString *)bundleID;
+ (UIImage *)iconForBundleID:(NSString *)bundleID;
@end
@implementation DXPAppInfo
+ (NSString *)displayNameForBundleID:(NSString *)bundleID { return bundleID; }
+ (UIImage *)iconForBundleID:(NSString *)bundleID { (void)bundleID; return nil; }
@end
@interface DXPOpenAppPickerController : PSViewController
@property(nonatomic, copy) NSString *selectedBundleIdentifier;
@property(nonatomic, copy) void (^completion)(DXPAppInfo *);
@property(nonatomic) BOOL allowsMultipleSelection;
@property(nonatomic, copy) void (^multiSelectionCompletion)(NSArray *);
@end
@implementation DXPOpenAppPickerController @end
'''

original_stub = (root / "tests/PreferencesStatusBarStub.h").read_text()
stub_patches = [
    ('''@interface UIAlertController : NSObject
@property(nonatomic, strong) NSMutableArray *actions;''', '''@interface UIAlertController : NSObject
@property(nonatomic, strong) NSMutableArray<UIAlertAction *> *actions;'''),
    ('''typedef NS_ENUM(NSInteger, UIAlertActionStyle) { UIAlertActionStyleDefault, UIAlertActionStyleCancel };''',
     '''typedef NS_ENUM(NSInteger, UIAlertActionStyle) { UIAlertActionStyleDefault, UIAlertActionStyleCancel, UIAlertActionStyleDestructive };'''),
    ('''@interface UILabel : NSObject
@property(nonatomic, copy) NSString *text;
@property(nonatomic, strong) UIColor *textColor;
@end''', '''@class UIFont;
@interface UILabel : UIView
@property(nonatomic, copy) NSString *text;
@property(nonatomic, strong) UIColor *textColor;
@property(nonatomic, strong) UIFont *font;
@end'''),
    ('''@interface UIImageView : NSObject
@property(nonatomic, strong) UIImage *image;
@end''', '''@interface UIImageView : UIView
@property(nonatomic, strong) UIImage *image;
@property(nonatomic, strong) UIColor *tintColor;
@end'''),
    ('''@interface UITableViewCell : NSObject
@property(nonatomic, strong) UILabel *textLabel;''', '''@interface UITableViewCell : UIView
@property(nonatomic, strong) UIView *contentView;
@property(nonatomic, strong) UILabel *textLabel;'''),
    ('''@property(nonatomic, strong) id accessoryView;
@property(nonatomic) UITableViewCellAccessoryType accessoryType;''', '''@property(nonatomic, strong) id accessoryView, editingAccessoryView;
@property(nonatomic) UITableViewCellAccessoryType accessoryType, editingAccessoryType;
@property(nonatomic) NSInteger selectionStyle;'''),
    ('''- (instancetype)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)identifier;
@end
@implementation UITableViewCell
- (instancetype)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)identifier {
    (void)identifier;
    if ((self = [super init])) { _textLabel = [UILabel new]; _imageView = [UIImageView new]; if (style == UITableViewCellStyleSubtitle) _detailTextLabel = [UILabel new]; }
    return self;
}
@end''', '''- (instancetype)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)identifier;
- (void)layoutSubviews;
@end
@implementation UITableViewCell
- (instancetype)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)identifier {
    (void)identifier;
    if ((self = [super init])) { _textLabel = [UILabel new]; _imageView = [UIImageView new]; _contentView = [UIView new]; if (style == UITableViewCellStyleSubtitle) _detailTextLabel = [UILabel new]; }
    return self;
}
- (void)layoutSubviews {}
@end'''),
    ('''+ (NSString *)localizedStringForActionNamed:(NSString *)selector shortName:(BOOL)shortName bundle:(NSBundle *)bundle { (void)shortName; (void)bundle; return selector; }
+ (id)imageForIconConfig:(id)config defaultSymbolName:(NSString *)symbol { (void)config; return symbol; }
@end''', '''+ (NSString *)localizedStringForActionNamed:(NSString *)selector shortName:(BOOL)shortName bundle:(NSBundle *)bundle { (void)shortName; (void)bundle; return selector; }
+ (id)imageForIconConfig:(id)config defaultSymbolName:(NSString *)symbol { (void)config; return symbol; }
+ (NSString *)actionNameFromArray:(NSArray *)array atIndex:(NSInteger)index { (void)array; (void)index; return @""; }
+ (id)imageFromArray:(NSArray *)array atIndex:(NSInteger)index { (void)array; (void)index; return nil; }
+ (id)imageFromArray:(NSArray *)array atIndex:(NSInteger)index withSystemColor:(BOOL)system completion:(void (^)(UIImage *))completion { (void)array; (void)index; (void)system; if (completion) completion(nil); return nil; }
@end'''),
    ('''- (NSArray *)imageNameArrayForiOS:(NSInteger)version { (void)version; return @[@"doc.on.doc", @"doc.on.clipboard"]; }''',
     '''- (NSArray *)imageNameArrayForiOS:(NSInteger)version { (void)version; return @[@"doc.on.doc", @"doc.on.clipboard"]; }
+ (NSArray *)builtInActionGroupOrder { return @[]; }
+ (NSString *)builtInActionGroupForSelector:(NSString *)selector { (void)selector; return @""; }'''),
    ('''@interface DXPLinkActionEditorController : PSViewController
@property(nonatomic, strong) NSMutableDictionary *entry;
@property(nonatomic, copy) void (^completion)(NSDictionary *);
+ (NSString *)displayNameForType:(NSString *)type;
+ (NSString *)defaultIconForType:(NSString *)type;
@end
@implementation DXPLinkActionEditorController
+ (NSString *)displayNameForType:(NSString *)type { return type; }
+ (NSString *)defaultIconForType:(NSString *)type { (void)type; return @"link"; }
@end''', '''@interface DXPLinkActionEditorController : PSViewController
@property(nonatomic, strong) NSMutableDictionary *entry;
@property(nonatomic, copy) void (^completion)(NSDictionary *);
+ (NSString *)displayNameForType:(NSString *)type;
+ (NSString *)defaultIconForType:(NSString *)type;
+ (void)presentTypeChooserFromController:(PSViewController *)controller currentType:(NSString *)type completion:(void (^)(NSString *))completion;
@end
static void (^TypeChooserCompletion)(NSString *);
@implementation DXPLinkActionEditorController
+ (NSString *)displayNameForType:(NSString *)type { return type; }
+ (NSString *)defaultIconForType:(NSString *)type { (void)type; return @"link"; }
+ (void)presentTypeChooserFromController:(PSViewController *)controller currentType:(NSString *)type completion:(void (^)(NSString *))completion {
    (void)controller; (void)type; TypeChooserCompletion = completion;
}
@end'''),
    ('''@interface UITableView : NSObject
@property(nonatomic) NSUInteger deselections;
@property(nonatomic, strong) UITableViewCell *reusableCell;
- (UITableViewCell *)dequeueReusableCellWithIdentifier:(NSString *)identifier;
- (void)deselectRowAtIndexPath:(NSIndexPath *)indexPath animated:(BOOL)animated;
@end
@implementation UITableView
- (UITableViewCell *)dequeueReusableCellWithIdentifier:(NSString *)identifier { (void)identifier; return self.reusableCell; }
- (void)deselectRowAtIndexPath:(NSIndexPath *)indexPath animated:(BOOL)animated { (void)indexPath; (void)animated; self.deselections++; }
@end''', table_replacement),
    ('''@interface PSViewController : NSObject
@property(nonatomic, copy) NSString *title;
@property(nonatomic, strong) UINavigationController *navigationController;
@property(nonatomic, weak) id rootController;
@property(nonatomic, weak) id parentController;
@property(nonatomic, strong) id presentedViewController;
- (void)viewDidLoad;
- (void)viewWillAppear:(BOOL)animated;
- (void)viewDidAppear:(BOOL)animated;
- (void)pushController:(PSViewController *)controller;
- (void)presentViewController:(id)controller animated:(BOOL)animated completion:(void (^)(void))completion;
@end
@implementation PSViewController
- (void)viewDidLoad {}
- (void)viewWillAppear:(BOOL)animated { (void)animated; }
- (void)viewDidAppear:(BOOL)animated { (void)animated; }
- (void)pushController:(PSViewController *)controller {
    controller.navigationController = self.navigationController;
    self.navigationController.viewControllers = [self.navigationController.viewControllers arrayByAddingObject:controller];
}
- (void)presentViewController:(id)controller animated:(BOOL)animated completion:(void (^)(void))completion {
    (void)animated; self.presentedViewController = controller; if (completion) completion();
}
@end''', navigation_replacement),
]

stub = original_stub
for old, new in stub_patches:
    assert old in stub, f"stub anchor drifted: {old[:60]!r}"
    stub = stub.replace(old, new, 1)
stub = stub.replace("#import <Foundation/Foundation.h>",
                    "#import <Foundation/Foundation.h>\n" + stub_extensions, 1)

extra_defines = f"""
{chr(10).join(macro_lines)}
#define bundlePath @"/tmp/TypeXHarnessMissing.bundle"
#define LOCALIZED(str) (str)
"""


def strip_imports(path):
    return "\n".join(line for line in (root / path).read_text().splitlines()
                     if not line.strip().startswith("#import"))


with tempfile.TemporaryDirectory(prefix="typex-custom-actions-page-") as directory:
    tmp = pathlib.Path(directory)
    harness = "\n".join([
        "#pragma once",
        stub,
        extra_defines,
        common_block,
        extra_uikit,
        strip_imports("DXSystemActionCatalog.h"),
        strip_imports("DXKeyboardPanelPreferences.h"),
        strip_imports("DXGlobalPanelPolicy.h"),
        strip_imports("DXStatusBarGesturePolicy.h"),
        strip_imports("DXDockGesturePolicy.h"),
        strip_imports("DXPanelRegistry.h"),
        strip_imports("typexprefs/DXPBatchOpenAppEntries.h"),
        strip_imports("typexprefs/DXPActionGroups.h"),
        strip_imports("typexprefs/DXPCustomActionViewController.h"),
        strip_imports("typexprefs/DXPCustomActionsController.h"),
        strip_imports("typexprefs/DXPCustomActionViewController.m").replace("tweakBundle", "tweakBundleBase"),
        strip_imports("typexprefs/DXPCustomActionsController.m"),
    ])
    # Foundation loads CoreAutoLayout on macOS; avoid shadowing its real class.
    harness = harness.replace("NSLayoutConstraint", "HarnessLayoutConstraint")
    (tmp / "CustomActionsPageHarness.h").write_text(harness)
    if os.environ.get("TYPEX_DUMP_HARNESS"):
        import shutil
        shutil.copy(tmp / "CustomActionsPageHarness.h", os.environ["TYPEX_DUMP_HARNESS"])

    binary = tmp / "custom-actions-page"
    subprocess.run(["xcrun", "clang", "-fobjc-arc", "-fblocks", "-Wall", "-Wextra", "-Werror", "-Wno-unused-function",
                    "-Wno-unused-parameter", "-Wno-format", "-framework", "Foundation", "-I", str(tmp), "-I", str(root),
                    str(root / "tests/DXCustomActionsPageTests.m"), "-o", str(binary)], check=True)
    subprocess.run([str(binary)], check=True, timeout=30)
