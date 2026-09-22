#import <Preferences/PSViewController.h>

// 生效应用 allowlist for the clipboard paste chip: every installed app with a
// switch, all off by default. Persisted as bundleID -> @YES under
// kPasteImageChipAppsKey in the shared preferences. Matches the
// DXPOpenAppPickerController shape: one background filtered enumeration,
// User/System sections plus a pinned section for allowlist entries whose app
// no longer enumerates, and a navigation-item search bar on top of the
// enabled-only toggle. Protocols and properties live in the class extension.
@interface DXPPasteChipAppsController : PSViewController
@end
