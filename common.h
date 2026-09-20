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
#define kCustomActionUsePullOverKey @"pullover"
#define kCustomActionTypeURLScheme @"urlscheme"
#define kCustomActionTypeText @"text"
#define kCustomActionTypeURL @"url"
#define kCustomActionTypeOpenApp @"openapp"
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
#define kBottomSpacingKey @"bottomspacing"
#define kCellBorderEnabledkey @"shortcutborderBOOL"
#define kCellBorderWidthkey @"shortcutborderwidth"
#define kButtonWidthScalekey @"shortcutwidthscale"
#define kSubActionPanelScaleKey @"subactionpanelscale"
// 多行模式（仅顶部工具栏设置页提供）：开启后按钮按"每行个数"换行，第一行
// 紧贴键盘、第二行向上堆叠；关闭时保持横向分页。行距只作用于两行之间。
#define kMultiRowEnabledKey @"multirowBOOL"
#define kButtonsPerRowKey @"buttonsperrow"
#define kMultiRowSpacingKey @"multirowspacing"
#define buttonsPerRowDefault 6.0f
#define multiRowSpacingDefault 4.0f
#define maxMultiRowRows 2
// The top toolbar may store any number of buttons, but at most sixteen may be
// switched on at once. Multi-row mode can impose a smaller limit when its
// configured column count cannot fit sixteen buttons into two rows.
#define maxEnabledTopButtons 16
#define maxMultiRowButtons maxEnabledTopButtons
#define kSpongebobEntropyKey @"spongebobEntropy"
// Clipboard image quick paste: floating thumbnail above the keyboard +
// auto-answering of the iOS 16+ paste-permission alert, one switch for both.
#define kPasteImageChipKey @"pasteimagechipBOOL"
// BundleID -> @YES map of apps where the paste chip may appear. A missing key
// or an entry without the host bundle ID means off: the per-app switches in
// Settings all default to off.
#define kPasteImageChipAppsKey @"pasteimagechipapps"
// Optional ShellX screenshot behavior. This uses a new key so users who had
// enabled the former "restore keyboard after screenshot" option do not
// accidentally inherit the new behavior; the default remains off.
#define kShellXScreenshotHideKeyboardKey @"shellxscreenshothidekeyboardBOOL"

#define kbuttonsImages12 0
#define kbuttonsImages13 1
#define kselectors 2
#define kshortLabel 4

#define tweakVersion @"1.3.1"
#define maxdefaultshortcuts 6
// Page size of the classic single-row horizontal paging layout: with multi-row
// mode off, buttons beyond this number wrap into additional horizontally
// paged sections. This is a page-size constant, not the sixteen-button active
// limit above.
#define maxshortcutpersection 8
#define granularity 3


#define heightOffsetDefault 60.0f

#define searchedCountEaster 100

#define spacingBetweenCellsDefault 3
#define topBottomSpacingDefault 0.0f
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

// TypeX 自带 AI 面板通道：工具栏进程只写请求（{format:2, requestID, created,
// mode: text|image|empty, origin: sb|app, text?}），SpringBoard 端收到 Darwin
// 通知后整包读取并在 SB 进程内创建 DXAIPanel 悬浮窗。面板不能在键盘进程承载：
// 窗口会被限制在键盘宿主区域内（第三方键盘扩展里完全无法悬浮）。与快捷方式
// 目录共用隔离域，避免再开共享面。
#define TypeXAIChatRequestKey @"ai-chat-request"
#define kAIChatRequestIdentifier @"com.lindo.typex/aichat"

// TypeX-owned bridge for opening an application through PullOver-X. Darwin
// notification state is global across processes, unlike CFPreferences written
// by a sandboxed host (which is redirected into that App's own container).
// The sender publishes a stable 64-bit Bundle-ID fingerprint; SpringBoard
// resolves it against its installed-app registry before invoking PullOver's
// existing PullOverWindow -> controller -> pinAppWithBundleId: entry point.
#define kPullOverOpenRequestIdentifier @"com.lindo.typex/pulloveropen"

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

static inline uint64_t DXPullOverOpenStateForBundleIdentifier(NSString *bundleIdentifier) {
    if (!DXIsValidBundleIdentifier(bundleIdentifier)) return 0;
    const unsigned char *bytes = (const unsigned char *)bundleIdentifier.UTF8String;
    if (!bytes) return 0;

    // FNV-1a keeps the transport dependency-free. SpringBoard accepts a state
    // only when it resolves to exactly one currently installed Bundle ID.
    uint64_t state = UINT64_C(14695981039346656037);
    for (const unsigned char *cursor = bytes; *cursor != '\0'; cursor++) {
        state ^= (uint64_t)*cursor;
        state *= UINT64_C(1099511628211);
    }
    return state;
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

static inline NSInteger DXMultiRowButtonsPerRowFromPreferences(NSDictionary *preferences) {
    id value = [preferences isKindOfClass:[NSDictionary class]]
        ? preferences[DXScopedPreferenceKey(kButtonsPerRowKey, @"top")] : nil;
    NSInteger perRow = [value respondsToSelector:@selector(integerValue)]
        ? [value integerValue] : (NSInteger)buttonsPerRowDefault;
    return MIN(8, MAX(1, perRow));
}

static inline BOOL DXMultiRowEnabledForPreferences(NSDictionary *preferences) {
    id value = [preferences isKindOfClass:[NSDictionary class]]
        ? preferences[DXScopedPreferenceKey(kMultiRowEnabledKey, @"top")] : nil;
    return [value respondsToSelector:@selector(boolValue)] && [value boolValue];
}

// Two rows are the hard layout limit. The configured per-row count can lower
// the active capacity, while eight columns keep the absolute ceiling at 16.
static inline NSInteger DXMultiRowCapacityForPreferences(NSDictionary *preferences) {
    return MIN(maxMultiRowButtons,
               DXMultiRowButtonsPerRowFromPreferences(preferences) * maxMultiRowRows);
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
