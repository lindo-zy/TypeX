#import <Preferences/PSViewController.h>

@class DXPAppInfo;

// Single-selection installed-app picker used by the Open App custom action.
// Backed by DXPAppInfo's filtered background enumeration and split into
// pinned-current / user / system sections with a navigation search bar.
// The editor owns persistence; this controller only returns the chosen app.
@interface DXPOpenAppPickerController : PSViewController
@property (nonatomic, copy) NSString *selectedBundleIdentifier;
@property (nonatomic, copy) void (^completion)(DXPAppInfo *app);
@end
