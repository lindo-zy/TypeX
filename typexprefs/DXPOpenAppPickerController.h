#import "AltList/ATLApplicationListSelectionController.h"

@class DXPAppInfo;

// Single-app picker for the openapp custom action, on the vendored AltList
// selection controller: User/System sections classified by
// LSApplicationProxy.applicationType (PullOver-X acquisition method), stock
// search bar and icons. Programmatic use — pushed from
// DXPLinkActionEditorController without a specifier, so all configuration is
// done in code; the editor owns persistence and receives the pick through
// `completion`.
@interface DXPOpenAppPickerController : ATLApplicationListSelectionController
// Pre-selected app (checkmark anchor); set before pushing.
@property (nonatomic, copy) NSString *selectedBundleIdentifier;
// Fired once per row tap, before the controller pops itself.
@property (nonatomic, copy) void (^completion)(DXPAppInfo *app);
@end
