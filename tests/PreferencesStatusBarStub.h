#import <Foundation/Foundation.h>

typedef NS_ENUM(NSInteger, UITableViewCellStyle) { UITableViewCellStyleDefault, UITableViewCellStyleSubtitle };
typedef NS_ENUM(NSInteger, UITableViewCellAccessoryType) { UITableViewCellAccessoryNone, UITableViewCellAccessoryDisclosureIndicator, UITableViewCellAccessoryCheckmark };
typedef uint64_t UIAccessibilityTraits;
static const UIAccessibilityTraits UIAccessibilityTraitSelected = 1ULL << 2;
@interface UIImage : NSObject @end
@implementation UIImage @end
@interface UIColor : NSObject
+ (instancetype)labelColor;
+ (instancetype)secondaryLabelColor;
@end
@implementation UIColor
+ (instancetype)labelColor { return (id)@"label"; }
+ (instancetype)secondaryLabelColor { return (id)@"secondary"; }
@end
@interface UILabel : NSObject
@property(nonatomic, copy) NSString *text;
@property(nonatomic, strong) UIColor *textColor;
@end
@implementation UILabel @end
@interface UIImageView : NSObject
@property(nonatomic, strong) UIImage *image;
@end
@implementation UIImageView @end
@interface UITableViewCell : NSObject
@property(nonatomic, strong) UILabel *textLabel;
@property(nonatomic, strong) UILabel *detailTextLabel;
@property(nonatomic, strong) UIImageView *imageView;
@property(nonatomic, strong) id accessoryView;
@property(nonatomic) UITableViewCellAccessoryType accessoryType;
@property(nonatomic) UIAccessibilityTraits accessibilityTraits;
- (instancetype)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)identifier;
@end
@implementation UITableViewCell
- (instancetype)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)identifier {
    (void)identifier;
    if ((self = [super init])) { _textLabel = [UILabel new]; _imageView = [UIImageView new]; if (style == UITableViewCellStyleSubtitle) _detailTextLabel = [UILabel new]; }
    return self;
}
@end

// Narrow Preferences/navigation doubles. These do not emulate UIKit or prove
// the private framework's implementation on iOS; row actions and buttonAction
// deliberately remain separate, as declared by the shipped Theos headers.
typedef NS_ENUM(NSInteger, PSCellType) { PSGroupCell, PSLinkCell, PSSwitchCell, PSButtonCell };
@interface PSSpecifier : NSObject { @public SEL action; }
@property(nonatomic, strong) id target;
@property(nonatomic, copy) NSString *name;
@property(nonatomic) PSCellType cellType;
@property(nonatomic) SEL buttonAction;
@property(nonatomic, strong) NSMutableDictionary *properties;
+ (instancetype)preferenceSpecifierNamed:(NSString *)name target:(id)target set:(SEL)set get:(SEL)get detail:(Class)detail cell:(PSCellType)cell edit:(Class)edit;
+ (instancetype)groupSpecifierWithName:(NSString *)name;
- (void)setProperty:(id)value forKey:(NSString *)key;
- (id)propertyForKey:(NSString *)key;
@end
@implementation PSSpecifier
+ (instancetype)preferenceSpecifierNamed:(NSString *)name target:(id)target set:(SEL)set get:(SEL)get detail:(Class)detail cell:(PSCellType)cell edit:(Class)edit {
    (void)set; (void)get; (void)detail; (void)edit;
    PSSpecifier *item = [self new]; item.name = name; item.target = target; item.cellType = cell; return item;
}
+ (instancetype)groupSpecifierWithName:(NSString *)name { return [self preferenceSpecifierNamed:name target:nil set:NULL get:NULL detail:nil cell:PSGroupCell edit:nil]; }
- (instancetype)init { if ((self = [super init])) _properties = [NSMutableDictionary dictionary]; return self; }
- (void)setProperty:(id)value forKey:(NSString *)key { if (value) self.properties[key] = value; }
- (id)propertyForKey:(NSString *)key { return self.properties[key]; }
@end

@class PSViewController;
@interface UINavigationController : NSObject
@property(nonatomic, copy) NSArray *viewControllers;
@property(nonatomic, readonly) id topViewController;
@property(nonatomic) NSUInteger pops;
- (id)popViewControllerAnimated:(BOOL)animated;
@end
@implementation UINavigationController
- (id)topViewController { return self.viewControllers.lastObject; }
- (id)popViewControllerAnimated:(BOOL)animated {
    (void)animated; self.pops++;
    id last = self.topViewController;
    if (self.viewControllers.count) self.viewControllers = [self.viewControllers subarrayWithRange:NSMakeRange(0, self.viewControllers.count - 1)];
    return last;
}
@end
@interface PSViewController : NSObject
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
@end
@interface UITableView : NSObject
@property(nonatomic) NSUInteger deselections;
@property(nonatomic, strong) UITableViewCell *reusableCell;
- (UITableViewCell *)dequeueReusableCellWithIdentifier:(NSString *)identifier;
- (void)deselectRowAtIndexPath:(NSIndexPath *)indexPath animated:(BOOL)animated;
@end
@implementation UITableView
- (UITableViewCell *)dequeueReusableCellWithIdentifier:(NSString *)identifier { (void)identifier; return self.reusableCell; }
- (void)deselectRowAtIndexPath:(NSIndexPath *)indexPath animated:(BOOL)animated { (void)indexPath; (void)animated; self.deselections++; }
@end
@interface PSListController : PSViewController { @protected NSArray *_specifiers; }
@property(nonatomic, strong) PSSpecifier *specifier;
- (NSArray *)specifiers;
- (void)reloadSpecifiers;
- (PSSpecifier *)specifierAtIndexPath:(NSIndexPath *)indexPath;
- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath;
- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath;
@end
@implementation PSListController
- (NSArray *)specifiers { return _specifiers; }
- (void)reloadSpecifiers { _specifiers = nil; (void)[self specifiers]; }
- (PSSpecifier *)specifierAtIndexPath:(NSIndexPath *)indexPath {
    NSInteger section = -1, row = -1;
    for (PSSpecifier *item in self.specifiers) {
        if (item.cellType == PSGroupCell) { section++; row = -1; }
        else if (section == (NSInteger)[indexPath indexAtPosition:0] && ++row == (NSInteger)[indexPath indexAtPosition:1]) return item;
    }
    return nil;
}
- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath { (void)tableView; (void)indexPath; }
- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    (void)tableView; (void)indexPath; return [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:@"private"];
}
@end
@interface DXPStatusBarGestureController : PSListController @end
@interface DXPDockGestureController : PSListController @end

typedef NS_ENUM(NSInteger, UIAlertActionStyle) { UIAlertActionStyleDefault, UIAlertActionStyleCancel };
typedef NS_ENUM(NSInteger, UIAlertControllerStyle) { UIAlertControllerStyleAlert };
@interface UIAlertAction : NSObject
@property(nonatomic, copy) void (^handler)(UIAlertAction *);
+ (instancetype)actionWithTitle:(NSString *)title style:(UIAlertActionStyle)style handler:(void (^)(UIAlertAction *))handler;
@end
@implementation UIAlertAction
+ (instancetype)actionWithTitle:(NSString *)title style:(UIAlertActionStyle)style handler:(void (^)(UIAlertAction *))handler {
    (void)title; (void)style; UIAlertAction *action = [self new]; action.handler = handler; return action;
}
@end
@interface UIAlertController : NSObject
@property(nonatomic, strong) NSMutableArray *actions;
+ (instancetype)alertControllerWithTitle:(NSString *)title message:(NSString *)message preferredStyle:(UIAlertControllerStyle)style;
- (void)addAction:(UIAlertAction *)action;
@end
@implementation UIAlertController
+ (instancetype)alertControllerWithTitle:(NSString *)title message:(NSString *)message preferredStyle:(UIAlertControllerStyle)style {
    (void)title; (void)message; (void)style; UIAlertController *alert = [self new]; alert.actions = [NSMutableArray array]; return alert;
}
- (void)addAction:(UIAlertAction *)action { [self.actions addObject:action]; }
@end
@interface DXPLinkActionEditorController : PSViewController
@property(nonatomic, strong) NSMutableDictionary *entry;
@property(nonatomic, copy) void (^completion)(NSDictionary *);
+ (NSString *)displayNameForType:(NSString *)type;
+ (NSString *)defaultIconForType:(NSString *)type;
@end
@implementation DXPLinkActionEditorController
+ (NSString *)displayNameForType:(NSString *)type { return type; }
+ (NSString *)defaultIconForType:(NSString *)type { (void)type; return @"link"; }
@end
@interface DXHelper : NSObject
+ (NSString *)localizedStringForActionNamed:(NSString *)selector shortName:(BOOL)shortName bundle:(NSBundle *)bundle;
+ (id)imageForIconConfig:(id)config defaultSymbolName:(NSString *)symbol;
@end
@implementation DXHelper
+ (NSString *)localizedStringForActionNamed:(NSString *)selector shortName:(BOOL)shortName bundle:(NSBundle *)bundle { (void)shortName; (void)bundle; return selector; }
+ (id)imageForIconConfig:(id)config defaultSymbolName:(NSString *)symbol { (void)config; return symbol; }
@end
@interface DXPrefsManager : NSObject
@property(nonatomic, copy) NSDictionary *preferences;
@property(nonatomic) BOOL ignoreWrites;
@property(nonatomic) NSUInteger writes;
+ (instancetype)sharedInstance;
- (NSDictionary *)readPrefs;
- (void)writePrefs:(NSDictionary *)preferences;
- (void)setValue:(id)value forKey:(NSString *)key;
@end
@implementation DXPrefsManager
+ (instancetype)sharedInstance { static DXPrefsManager *manager; if (!manager) manager = [self new]; return manager; }
- (NSDictionary *)readPrefs { return self.preferences; }
- (void)writePrefs:(NSDictionary *)preferences { self.writes++; if (!self.ignoreWrites) self.preferences = preferences; }
- (void)setValue:(id)value forKey:(NSString *)key { NSMutableDictionary *prefs = [self.preferences mutableCopy]; prefs[key] = value; [self writePrefs:prefs]; }
@end
