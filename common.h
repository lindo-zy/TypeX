#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <HBLog.h>
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
#define kIPCCenterToast @"com.lindo.typex.toast"
#define kIPCCenterTypeX @"com.lindo.typex"
#define kPrefsChangedIdentifier @"com.lindo.typex/prefschanged"
#define kAutoCorrectionChangedIdentifier @"com.lindo.typex/autocorrectionchanged"
#define kAutoCapitalizationChangedIdentifier @"com.lindo.typex/autocapitalizationchanged"
#define kPrefsPath @"/var/mobile/Library/Preferences/com.lindo.typex.plist"

#define kEnabledkey @"enabledBOOL"
#define kEnabledHaptickey @"hapticBOOL"
#define kShakeShortcutkey @"shakeBOOL"
#define kToastkey @"toastBOOL"
#define kToastPy @"toastpy"
#define kShortcutskey @"shortcuts"
#define kTopShortcutskey @"topshortcuts"
#define kToastDurationkey @"toastduration"
#define kColorEnabledkey @"colorBOOL"
#define kSpaceBarScrollingBOOL @"enabledSpaceBarScrollingBOOL"
#define kGranularity @"granularityvalue"
#define kShortcutsPerSection @"shortcutsnum"
#define kTopShortcutsPerSection @"topshortcutsnum"
#define kToggledOnkey @"toggledOnBOOL"
#define kDockModekey @"dockmode"
#define kDisplayTypekey @"displaytype"
#define kDedicatedGestureButtonkey @"gesturebutton"
#define kGestureTypekey @"gesturetype"
#define kCustomActionskey @"customactions"
#define kTopCustomActionskey @"topcustomactions"
#define kPagingkey @"pagingBOOL"
#define kShortcutsTintEnabled @"shortcutstintBOOL"
#define kShortcutsBackgroundTintEnabled @"shortcutsbackgroundtintBOOL"
#define kToastTintEnabled @"toasttintBOOL"
#define kToastBackgroundTintEnabled @"toastbackgroundtintBOOL"
#define kTopToolbarBackgroundTintKey @"toptoolbarbackgroundtint"
#define kTopToolbarBackgroundTintEnabledKey @"toptoolbarbackgroundtintBOOL"
#define kKeyboardTypekey @"keyboardtype"
#define kPasteAndGoEnabledkey @"pasteandgo"
#define kCustomActionsDTkey @"customactionsdt"
#define kCustomActionsSTkey @"customactionsst"
#define kTopCustomActionsDTkey @"topcustomactionsdt"
#define kTopCustomActionsSTkey @"topcustomactionsst"
#define kEnabledDoubleTapkey @"doubletapBOOL"
#define kTopInsetkey @"topinset"
#define kBottomInsetkey @"bottominset"
#define kLeftInsetkey @"leftinset"
#define kRightInsetkey @"rightinset"
#define kLeadinfOffsetkey @"leadingoffset"
#define kTrailingOffsetkey @"trailingoffset"
#define kHeightOffsetkey @"heightoffset"
#define kBottomOffsetkey @"bottomoffset"
#define kAttemptOffsetAutoAdjustInOneHandedkey @"rightinset"
#define kEnabledSmartDeletekey @"smartdeleteBOOL"
#define kEnabledSmartDeleteForwardkey @"smartdeleteforwardBOOL"
#define kEnabledSkipEmojikey @"skipEmojiInputBOOL"
#define kShortLabelEnabledKey @"shortLabelBOOL"
#define kCellHeightkey @"shortcutheight"
#define kCellRadiuskey @"shortcutradius"
#define kCellSpacingkey @"shortcutspacing"
#define kCachekey @"cache"
#define kTopCachekey @"topcache"
#define kSpongebobEntropyKey @"spongebobEntropy"

#define toastWidth 50
#define toastHeight 50
#define toastPosition 0.8f
#define toastDuration 0.2
#define toastAlpha 0.95
#define toastRadius 6
#define toastTextColor [UIColor whiteColor]
#define toastBackgroundColor [UIColor blackColor]
#define toastImageTintColor [UIColor whiteColor]

#define kbuttonsImages12 0
#define kbuttonsImages13 1
#define kselectors 2
#define kselectorsLP 3
#define kshortLabel 4

#define tweakVersion @"1.3.1"
#define maxdefaultshortcuts 6
#define maxshortcutpersection 6
#define maxshortcutpersection_onehanded 6
#define granularity 3

#define maxdefaultshortcutskbtype 3

#define topInsetDefault 22.0f
#define bottomInsetDefault 0.0f
#define leftInsetDefault 0.0f
#define rightInsetDefault 0.0f

#define leadingOffsetDefault 69.0f
#define trailingOffsetDefault -60.0f
#define heightOffsetDefault 60.0f
#define bottomOffsetDefault -22.0f

#define leadingOffsetHandBiasRightDefault 100.0f
#define trailingOffsetHandBiasRightDefault -65.0f

#define leadingOffsetHandBiasLeftDefault 69.0f
#define trailingOffsetHandBiasLeftDefault -100.0f

#define searchedCountEaster 100

#define spacingBetweenCellsDefault 3
#define cellsHeightDefault 30
#define cellsRadiusDefault 5

#define secondActionDelay 0.05

#define TypeXCachePath DX_ROOT_PATH_NS(@"/var/mobile/Library/Caches/com.lindo.typex")
#define TypeXSharedPrefsPath TypeXCachePath @"/shared.plist"

static inline NSString *DXScopedPreferenceKey(NSString *baseKey, NSString *configuration) {
    if ([configuration isEqualToString:@"top"]) {
        return [@"top" stringByAppendingString:baseKey];
    }
    return baseKey;
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

@interface SpringBoard : NSObject
- (NSDictionary *)showToastRequest:(NSString *)name withUserInfo:(NSDictionary *)userInfo;
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
@end

@interface UIKeyboardPreferencesController : NSObject
@property (assign) long long handBias;
+(UIKeyboardPreferencesController *)sharedPreferencesController;
+(id)valueForPreferenceKey:(id)arg1 domain:(id)arg2 ;
-(void)setHandBias:(long long)arg1 ; //0 -normal,2-left, 1-right
-(BOOL)boolForKey:(int)arg1 ;
-(void)setValue:(id)arg1 forKey:(int)arg2 ;
-(void)synchronizePreferences;
@end
