#import <Preferences/PSViewController.h>

@class DXPAppInfo;

// Single-app picker for the openapp custom action, in the shape of PullOver-X
// QSFavoritesPickerController: a plain table controller that never touches
// PSListController internals (programmatic ATLApplicationListSelectionController
// use without a specifier crashed in Preferences — see 3.5.2 regression).
// Acquisition follows the same method: one background `allApplications` pass
// with a loading spinner and generation guard, each proxy classified through
// the vendored AltList categories (atl_isUserApplication /
// atl_isSystemApplication read the applicationType string). The editor owns
// persistence and receives the pick through `completion`.
@interface DXPOpenAppPickerController : PSViewController
// Pre-selected app (checkmark anchor); set before pushing.
@property (nonatomic, copy) NSString *selectedBundleIdentifier;
// Fired once per row tap, before the controller pops itself.
@property (nonatomic, copy) void (^completion)(DXPAppInfo *app);
@end
