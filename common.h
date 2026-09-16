#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#if defined(THEOS_PACKAGE_SCHEME_ROOTHIDE)
#import <roothide.h>
#define DX_ROOT_PATH_NS(path) jbroot(path)
#else
#import <rootless.h>
#define DX_ROOT_PATH_NS(path) ROOT_PATH_NS(path)
#endif
#import <spawn.h>

@class CPDistributedMessagingCenter;

#import "DXPrefsManager.h"

#define bundlePath DX_ROOT_PATH_NS(@"/Library/PreferenceBundles/TypeXPrefs.bundle")
//#define typexBundlePath @"/Library/Application Support/TypeX.bundle"
#define LOCALIZED(str) [tweakBundle localizedStringForKey:str value:@"" table:nil]

#define kIdentifier @"com.lindo.typex"
#define kIPCCenterPrefsManager @"com.lindo.typex.prefsmanager"
#define kIPCCenterTypeX @"com.lindo.typex"
#define kPrefsChangedIdentifier @"com.lindo.typex/prefschanged"
#define kPrefsPath @"/var/mobile/Library/Preferences/com.lindo.typex.plist"

#define kEnabledkey @"enabledBOOL"
#define kEnabledHaptickey @"hapticBOOL"
#define kShortcutskey @"shortcuts"
#define kTopShortcutskey @"topshortcuts"
#define kColorEnabledkey @"colorBOOL"
#define kSpaceBarScrollingBOOL @"enabledSpaceBarScrollingBOOL"
#define kGranularity @"granularityvalue"
#define kToggledOnkey @"toggledOnBOOL"
#define kDockModekey @"dockmode"
#define kDedicatedGestureButtonkey @"gesturebutton"
#define kGestureTypekey @"gesturetype"
#define kCustomActionskey @"customactions"
#define kTopCustomActionskey @"topcustomactions"
#define kTapCustomActionskey @"tapactions"
#define kSwipeUpCustomActionskey @"swipeupactions"
#define kSwipeDownCustomActionskey @"swipedownactions"
#define kSwipeLeftCustomActionskey @"swipeleftactions"
#define kSwipeRightCustomActionskey @"swiperightactions"
// User-defined URL actions shown below the built-in actions in every gesture
// picker. Definitions are global so the same ordered list is available to the
// top and bottom toolbar configurations.
#define kLinkActionskey @"linkactions"
#define kLinkActionSelectorPrefix @"__typex_link_action_"

// Custom action types, stored on each linkactions entry under "type".  An
// entry without a type is a legacy definition and keeps the old behavior of
// auto-detecting web URL / URL scheme / bundle identifier from its link.
// "url" additionally stores the APP内打开 choice under "inapp" (default YES).
#define kCustomActionTypeKey @"type"
#define kCustomActionInAppKey @"inapp"
// 快捷方式 entries: "link" stores the owning app's bundle identifier and this
// field the UIApplicationShortcutItemType of the chosen long-press menu item.
// Entries without it predate the quick-action payload and keep the legacy
// Shortcuts-app name behavior.
#define kCustomActionShortcutTypeKey @"shortcuttype"
#define kCustomActionTypeURLScheme @"urlscheme"
#define kCustomActionTypeText @"text"
#define kCustomActionTypeOpenApp @"openapp"
#define kCustomActionTypeURL @"url"
#define kCustomActionTypeShortcut @"shortcut"

// 打开应用 and 快捷方式 are only selectable as sub-actions; every other type
// (and every legacy entry) is universal and may also drive a button gesture.
static inline BOOL DXIsSubActionOnlyCustomActionType(NSString *type) {
    return [type isKindOfClass:[NSString class]] &&
        ([type isEqualToString:kCustomActionTypeOpenApp] || [type isEqualToString:kCustomActionTypeShortcut]);
}
// Per-entry field on a shortcut dictionary: set to @YES when the button's tap
// should run its sub-action chain (long-press behavior) instead of the tap
// action configured for it.
#define kTapSubActionsEntryKey @"tapsubactions"

#define kSubActionskey @"subactions"
#define kTopSubActionskey @"topsubactions"
#define kShortcutsTintEnabled @"shortcutstintBOOL"
#define kShortcutsBackgroundTintEnabled @"shortcutsbackgroundtintBOOL"
#define kTopToolbarBackgroundTintKey @"toptoolbarbackgroundtint"
#define kTopToolbarBackgroundTintEnabledKey @"toptoolbarbackgroundtintBOOL"
#define kPasteAndGoEnabledkey @"pasteandgo"
#define kHeightOffsetkey @"heightoffset"
#define kEnabledSmartDeleteForwardkey @"smartdeleteforwardBOOL"
#define kShortLabelEnabledKey @"shortLabelBOOL"
#define kCellHeightkey @"shortcutheight"
#define kCellRadiuskey @"shortcutradius"
#define kCellSpacingkey @"shortcutspacing"
#define kCellBorderEnabledkey @"shortcutborderBOOL"
#define kCellBorderWidthkey @"shortcutborderwidth"
#define kButtonWidthScalekey @"shortcutwidthscale"
#define kSubActionPanelScaleKey @"subactionpanelscale"
#define kSpongebobEntropyKey @"spongebobEntropy"

#define kbuttonsImages12 0
#define kbuttonsImages13 1
#define kselectors 2
#define kshortLabel 4

#define tweakVersion @"1.3.1"
#define maxdefaultshortcuts 6
// Button count is code-controlled, not a preference: each toolbar shows every
// configured button, clamped to [0, maxshortcutpersection].  Both the toolbar
// and the manage-shortcuts page cap at this value.
#define maxshortcutpersection 8
#define granularity 3


#define heightOffsetDefault 60.0f

#define searchedCountEaster 100

#define spacingBetweenCellsDefault 3
#define cellsHeightDefault 30
#define cellsRadiusDefault 5

#define buttonBorderWidthDefault 1.0f
#define buttonWidthScaleDefault 100.0f
#define subActionPanelScaleDefault 100.0f

// The shared snapshot must live where sandboxed app hosts can read it.  The
// jailbreak root (/var/jb on rootless, resolved by DX_ROOT_PATH_NS) is readable
// from inside app sandboxes -- this tweak already loads its bundle resources
// from /var/jb/Library -- while /var/mobile/Library/** is not.  The package
// stages the directory world-writable (no sticky bit: mobile writers must be
// able to atomically replace the root-owned seed file) so mobile processes
// (Settings, SpringBoard) can refresh the snapshot without a helper daemon.
#define TypeXCachePath DX_ROOT_PATH_NS(@"/Library/TypeX")
#define TypeXSharedPrefsPath DX_ROOT_PATH_NS(@"/Library/TypeX/shared.plist")
// 打开应用、应用长按快捷项, 面板 URL scheme and 快捷方式 (shortcuts://)
// requests ride a file + Darwin notification
// channel into SpringBoard: the writing process posts
// kPendingActionRequestIdentifier; the SpringBoard-injected dylib consumes
// the file and performs the open natively. Opens made from inside a host
// process are blocked by restricted hosts (WeChat), and identity-gated
// schemes (prefs:, App-Prefs:) only pass when the opener is SpringBoard
// itself. Three fixed action names are acted on: "openapp" with a plain bundle
// identifier, "openshortcut" with a bundle identifier plus the app-defined
// UIApplicationShortcutItemType, and "openurl" with a scheme-validated URL
// string — the channel never carries shell commands or arbitrary selectors.
// Every request lands in its OWN file (TypeXPendingActionPrefix + timestamp
// + UUID under the shared directory): the single fixed path lost every
// request but the last of a burst when two writes landed between
// SpringBoard's reads, executing the wrong action for a notification. The
// timestamp in the name is the drain order on the SpringBoard side.
// Reliability guard rails: SpringBoard purges leftover request files at dylib
// load (before the observer registers — anything present pre-launch predates
// this session, and executing it would replay a dead tap), the drain drops
// requests older than its staleness window, merges a duplicate copy of an
// action already executed in the same or a nearby drain, and paces consecutive
// launches; the writer re-posts only while its request file remains unconsumed,
// so a lost delivery cannot strand a file or execute an already-consumed tap.
#define TypeXPendingActionPath DX_ROOT_PATH_NS(@"/Library/TypeX/pendingaction.plist")
#define TypeXPendingActionPrefix @"pendingaction-"
#define kPendingActionRequestIdentifier @"com.lindo.typex/pendingaction"

// Settings and SpringBoard exchange quick-action data through an isolated
// CFPreferences domain. On RootHide iOS 16, SpringBoard can read shared files
// but its sandbox rejects direct writes under /Library/TypeX; cfprefsd provides
// the supported cross-process persistence path. Requests carry
// {format: 3, requestID, bundles}; responses replace one complete generation.
#define TypeXQuickActionDomain @"com.lindo.typex.quickactions"
#define TypeXQuickActionRequestKey @"request-v3"
#define TypeXQuickActionStatusKey @"status-v3"
#define TypeXQuickActionSnapshotKey @"snapshot-v3"
#define kShortcutRefreshRequestIdentifier @"com.lindo.typex/shortcutrefresh"
#define kShortcutSnapshotChangedIdentifier @"com.lindo.typex/shortcutschanged"

// Complete SpringBoard-authored snapshot of each app's current static and
// dynamic UIApplicationShortcutItems. The value is replaced as one generation,
// so removed apps and actions cannot survive an incremental merge:
//   {format: 3, generation: requestID, updated: time,
//    apps: {bundleID: {name, items: [{type, title, subtitle, source}]}}}

static inline id DXQuickActionSharedValue(NSString *key) {
    CFStringRef domain = (__bridge CFStringRef)TypeXQuickActionDomain;
    CFPreferencesSynchronize(domain, kCFPreferencesCurrentUser, kCFPreferencesAnyHost);
    return CFBridgingRelease(CFPreferencesCopyValue((__bridge CFStringRef)key,
                                                    domain,
                                                    kCFPreferencesCurrentUser,
                                                    kCFPreferencesAnyHost));
}

static inline BOOL DXSetQuickActionSharedValue(id value, NSString *key) {
    CFStringRef domain = (__bridge CFStringRef)TypeXQuickActionDomain;
    CFPreferencesSetValue((__bridge CFStringRef)key,
                          (__bridge CFPropertyListRef)value,
                          domain,
                          kCFPreferencesCurrentUser,
                          kCFPreferencesAnyHost);
    return CFPreferencesSynchronize(domain, kCFPreferencesCurrentUser, kCFPreferencesAnyHost);
}

// Reverse-DNS shape test shared with the SpringBoard-side request handler so
// the channel can never be coerced into acting on a non-identifier payload.
static inline BOOL DXIsValidBundleIdentifier(NSString *value) {
    if (![value isKindOfClass:[NSString class]] || value.length == 0) return NO;
    NSRegularExpression *expression = [NSRegularExpression regularExpressionWithPattern:@"^[A-Za-z0-9_](?:[A-Za-z0-9_-]*[A-Za-z0-9_])?(?:\\.[A-Za-z0-9_](?:[A-Za-z0-9_-]*[A-Za-z0-9_])?)+$"
                                                                                options:0
                                                                                  error:nil];
    return [expression firstMatchInString:value options:0 range:NSMakeRange(0, value.length)] != nil;
}

// Shared URL-shape test for the openurl channel action (and the scheme
// classification of custom-action links): a scheme-shaped URL of bounded
// length whose scheme is not an executable/document one (javascript:, data:,
// file:, about:), so the channel can never be coerced beyond "open this URL".
static inline BOOL DXIsOpenableSchemeURLString(NSString *value) {
    if (![value isKindOfClass:[NSString class]] || value.length == 0 || value.length > 2048) return NO;
    NSRange schemeRange = [value rangeOfString:@"^[A-Za-z][A-Za-z0-9+.-]*:" options:NSRegularExpressionSearch];
    if (schemeRange.location != 0) return NO;
    NSURL *url = [NSURL URLWithString:value];
    if (!url || url.scheme.length == 0) return NO;
    NSString *lowercaseScheme = url.scheme.lowercaseString;
    return ![lowercaseScheme isEqualToString:@"javascript"] &&
        ![lowercaseScheme isEqualToString:@"data"] &&
        ![lowercaseScheme isEqualToString:@"file"] &&
        ![lowercaseScheme isEqualToString:@"about"];
}

static inline NSString *DXScopedPreferenceKey(NSString *baseKey, NSString *configuration) {
    if ([configuration isEqualToString:@"top"]) {
        return [@"top" stringByAppendingString:baseKey];
    }
    return baseKey;
}

// Fields whose text was set programmatically start editing with the caret at
// the leading edge; park it past the existing text so a tap continues typing
// where the text ends. Works for UITextField and UITextView alike.
static inline void DXPlaceCaretAtEnd(id<UITextInput> field) {
    if (![field conformsToProtocol:@protocol(UITextInput)]) return;
    UITextPosition *end = field.endOfDocument;
    field.selectedTextRange = [field textRangeFromPosition:end toPosition:end];
}

// Gesture types for per-shortcut custom actions. Long press keeps the
// historical "customactions" store; each swipe direction has its own. The tap
// store holds an optional override for the button's own TouchUpInside action.
typedef NS_ENUM(NSInteger, DXShortcutGestureType) {
    DXShortcutGestureLongPress = 0,
    DXShortcutGestureSwipeUp = 1,
    DXShortcutGestureSwipeDown = 2,
    DXShortcutGestureSwipeLeft = 3,
    DXShortcutGestureSwipeRight = 4,
    DXShortcutGestureTap = 5,
};

// Temporary identifier used by the "add button" flow: the entry written into
// the tap store before the new button's action (and therefore its real
// identifier) exists. Rewritten to the real selector once the user picks one.
#define kNewButtonPendingIdentifier @"__typex_pending_new_button__"

// Buttons saved without a tap action get a synthetic identifier so gesture
// stores never collide between them. They render on the toolbar but stay
// inert until a tap action is configured for them.
#define kDraftActionPrefix @"__typexdraft_"

static inline BOOL DXIsDraftActionSelector(NSString *selector) {
    return [selector isKindOfClass:[NSString class]] && [selector hasPrefix:kDraftActionPrefix];
}

static inline BOOL DXIsLinkActionSelector(NSString *selector) {
    return [selector isKindOfClass:[NSString class]] && [selector hasPrefix:kLinkActionSelectorPrefix];
}

static inline NSString *DXCustomActionsKeyForGesture(int gestureType, NSString *configuration) {
    NSString *baseKey;
    switch (gestureType) {
        case DXShortcutGestureTap: baseKey = kTapCustomActionskey; break;
        case DXShortcutGestureSwipeUp: baseKey = kSwipeUpCustomActionskey; break;
        case DXShortcutGestureSwipeDown: baseKey = kSwipeDownCustomActionskey; break;
        case DXShortcutGestureSwipeLeft: baseKey = kSwipeLeftCustomActionskey; break;
        case DXShortcutGestureSwipeRight: baseKey = kSwipeRightCustomActionskey; break;
        default: baseKey = kCustomActionskey; break;
    }
    return DXScopedPreferenceKey(baseKey, configuration);
}

static inline UIColor *DXColorFromHex(NSString *value, NSString *fallback) {
    NSString *hex = [value isKindOfClass:[NSString class]] ? value : fallback;
    hex = [hex stringByReplacingOccurrencesOfString:@"#" withString:@""];
    unsigned int color = 0;
    NSScanner *scanner = [NSScanner scannerWithString:hex];
    if (![scanner scanHexInt:&color]) hex = [fallback stringByReplacingOccurrencesOfString:@"#" withString:@""];
    if (hex.length == 6) {
        scanner = [NSScanner scannerWithString:hex];
        [scanner scanHexInt:&color];
        return [UIColor colorWithRed:((color >> 16) & 0xff) / 255.0
                               green:((color >> 8) & 0xff) / 255.0
                                blue:(color & 0xff) / 255.0
                               alpha:1.0];
    }
    if (hex.length == 8) {
        scanner = [NSScanner scannerWithString:hex];
        [scanner scanHexInt:&color];
        return [UIColor colorWithRed:((color >> 16) & 0xff) / 255.0
                               green:((color >> 8) & 0xff) / 255.0
                                blue:(color & 0xff) / 255.0
                               alpha:((color >> 24) & 0xff) / 255.0];
    }
    return [UIColor redColor];
}

static inline void DXRunShellCommand(NSString *command) {
    if (command.length == 0) return;

    const char *shell = "/bin/bash";
    const char *arguments[] = {shell, "-c", command.UTF8String, NULL};
    pid_t pid = 0;
    extern char **environ;
    posix_spawn(&pid, shell, NULL, NULL, (char *const *)arguments, environ);
}

static inline UIInterfaceOrientation DXCurrentInterfaceOrientation(void) {
    if (@available(iOS 13.0, *)) {
        for (UIScene *scene in UIApplication.sharedApplication.connectedScenes) {
            if ([scene isKindOfClass:[UIWindowScene class]]) {
                UIInterfaceOrientation orientation = ((UIWindowScene *)scene).interfaceOrientation;
                if (orientation != UIInterfaceOrientationUnknown) return orientation;
            }
        }
    }

#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
    return UIApplication.sharedApplication.statusBarOrientation;
#pragma clang diagnostic pop
}

static inline UIWindow *DXKeyWindow(void) {
    if (@available(iOS 13.0, *)) {
        for (UIScene *scene in UIApplication.sharedApplication.connectedScenes) {
            if (![scene isKindOfClass:[UIWindowScene class]]) continue;
            for (UIWindow *window in ((UIWindowScene *)scene).windows) {
                if (window.isKeyWindow) return window;
            }
        }
    }

#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
    for (UIWindow *window in UIApplication.sharedApplication.windows) {
        if (window.isKeyWindow) return window;
    }
#pragma clang diagnostic pop
    return nil;
}

typedef NS_ENUM(NSInteger, DXPhonemesType){
    DXPhonemesTypeVowel,
    DXPhonemesTypeConsonent
};

typedef NS_ENUM(NSInteger, DXStudlyCapsType){
    DXStudlyCapsTypeRandom,
    DXStudlyCapsTypeAlternate,
    DXStudlyCapsTypeVowel,
    DXStudlyCapsTypeConsonent
};

@interface CPDistributedMessagingCenter : NSObject
+ (id)centerNamed:(id)arg1;
- (void)runServerOnCurrentThread;
- (void)registerForMessageName:(id)arg1 target:(id)arg2 selector:(SEL)arg3;
- (BOOL)sendMessageName:(id)arg1 userInfo:(id)arg2;
- (NSDictionary *)sendMessageAndReceiveReplyName:(id)arg1 userInfo:(id)arg2;
@end

@interface UIKeyboardEmojiCollectionInputView : NSObject {
    unsigned long long  _currentSection;
    double  _frameInset;
    bool  _hasShownAnimojiCell;
    bool  _hasShownAnimojiFirstTimeExperience;
    bool  _inputDelegateCanSupportAnimoji;
    bool  _isDraggingInputView;
    bool  _shouldRetryFetchingAnimojiRecents;
    NSIndexPath * _tappedSkinToneEmoji;
    bool  _useWideAnimojiCell;
}
@end

@interface SBSRelaunchAction : NSObject
@property (nonatomic, readonly) unsigned long long options;
@property (nonatomic, readonly, copy) NSString *reason;
@property (nonatomic, readonly, retain) NSURL *targetURL;
+ (id)actionWithReason:(id)arg1 options:(unsigned long long)arg2 targetURL:(id)arg3;
- (id)initWithReason:(id)arg1 options:(unsigned long long)arg2 targetURL:(id)arg3;
- (unsigned long long)options;
- (id)reason;
- (id)targetURL;

@end

@interface FBSSystemService : NSObject
+ (id)sharedService;
- (void)sendActions:(id)arg1 withResult:(/*^block*/id)arg2;
- (void)openApplication:(NSString *)bundleIdentifier
                options:(NSDictionary *)options
             withResult:(void (^)(NSError *error))result;
@end

// FrontBoard open path that accepts an FBSOpenApplicationRequest; the raw
// bundle-identifier string form on FBSSystemService is rejected on current iOS.
@interface FBSOpenApplicationOptions : NSDictionary
+ (id)optionsWithDictionary:(NSDictionary *)dictionary;
@end

@interface FBSOpenApplicationRequest : NSObject
+ (id)requestWithBundleIdentifier:(NSString *)bundleIdentifier;
@end

@interface FBSOpenApplicationService : NSObject
+ (id)sharedService;
- (void)openApplication:(id)request
                options:(id)options
      withResultHandler:(void (^)(NSError *error))resultHandler;
@end
