#import "DXGlobalPanel.h"
#import "DXGlobalPanelPolicy.h"
#import "DXGlobalPanelGeometry.h"
#import "DXKeyboardPanelPreferences.h"
#import "DXKeyboardPanelLayout.h"
#import "DXPanelSystemControlsView.h"
#import "DXPanelControlSession.h"
#import "DXSystemOpenBroker.h"
#import "DXShortcutsGenerator.h"
#import "DXKeyboardPanel.h"
#import "DXHelper.h"
#import "common.h"
#import <notify.h>
#import <objc/message.h>

@interface DXGlobalPanelWindow : UIWindow
@end
@implementation DXGlobalPanelWindow
- (BOOL)canBecomeKeyWindow { return NO; }
@end

@interface DXGlobalPanelItem : UIButton
@property(nonatomic, copy) NSString *actionSelector;
@property(nonatomic, strong) UIView *circle;
@property(nonatomic, strong) UIImageView *icon;
@property(nonatomic, strong) UILabel *name;
@end
@implementation DXGlobalPanelItem
- (void)setHighlighted:(BOOL)highlighted { [super setHighlighted:highlighted]; self.alpha = highlighted ? 0.5 : 1; }
@end

@interface DXGlobalPanel ()
@property(nonatomic, strong) DXGlobalPanelWindow *window;
@property(nonatomic, strong) UIView *panel;
@property(nonatomic, strong) UIScrollView *scroll;
@property(nonatomic, strong) UILabel *title;
@property(nonatomic, strong) UILabel *message;
@property(nonatomic, strong) UIButton *closeButton;
@property(nonatomic, strong) UIControl *header;
@property(nonatomic, strong) UIControl *blank;
@property(nonatomic, strong) UILabel *empty;
@property(nonatomic, strong) DXPanelSystemControlsView *controls;
@property(nonatomic, strong) DXPanelControlSession *controlSession;
@property(nonatomic, strong) NSArray<DXGlobalPanelItem *> *items;
@property(nonatomic, strong) NSDictionary *snapshot;
@property(nonatomic, assign) CGFloat scale;
@property(nonatomic, assign) NSInteger columns;
@property(nonatomic, assign) NSTimeInterval lastOpen;
- (void)layout;
- (void)showMessage:(NSString *)message;
@end

@interface DXGlobalPanelController : UIViewController
@property(nonatomic, weak) DXGlobalPanel *owner;
@end
@implementation DXGlobalPanelController
- (void)viewDidLayoutSubviews { [super viewDidLayoutSubviews]; [self.owner layout]; }
@end

static NSString *DXGlobalLocalized(NSString *key) {
    return [[NSBundle bundleWithPath:bundlePath] localizedStringForKey:key value:key table:nil];
}

@implementation DXGlobalPanel
+ (instancetype)sharedInstance {
    static DXGlobalPanel *instance;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ instance = [self new]; });
    return instance;
}
+ (BOOL)deviceUnlocked {
    if (!NSThread.isMainThread) return NO;
    Class cls = NSClassFromString(@"SBLockScreenManager");
    SEL shared = NSSelectorFromString(@"sharedInstance"), locked = NSSelectorFromString(@"isUILocked");
    if (![cls respondsToSelector:shared]) return NO;
    @try {
        NSMethodSignature *factory = [cls methodSignatureForSelector:shared];
        if (factory.numberOfArguments != 2 || strcmp(factory.methodReturnType, "@")) return NO;
        id manager = ((id (*)(id, SEL))objc_msgSend)(cls, shared);
        NSMethodSignature *signature = [manager methodSignatureForSelector:locked];
        if (![manager respondsToSelector:locked] || signature.numberOfArguments != 2 ||
            (strcmp(signature.methodReturnType, @encode(BOOL)) && strcmp(signature.methodReturnType, "c"))) return NO;
        return !((BOOL (*)(id, SEL))objc_msgSend)(manager, locked);
    } @catch (__unused NSException *exception) { return NO; }
}
- (instancetype)init {
    if ((self = [super init])) {
        NSNotificationCenter *center = NSNotificationCenter.defaultCenter;
        for (NSString *name in @[UIApplicationWillResignActiveNotification, UISceneWillDeactivateNotification,
            UIDeviceOrientationDidChangeNotification, @"typeXLayoutChanged"])
            [center addObserver:self selector:@selector(interrupted:) name:name object:nil];
    }
    return self;
}
- (void)dealloc { [NSNotificationCenter.defaultCenter removeObserver:self]; [_controlSession invalidate]; }
- (BOOL)isVisible { return self.window && !self.window.hidden; }
- (BOOL)validSession {
    if (!NSThread.isMainThread || ![self isVisible] || ![DXGlobalPanel deviceUnlocked]) return NO;
    UIWindowScene *scene = self.window.windowScene;
    DXPrefsManager *manager = DXPrefsManager.sharedInstance;
    return (!scene || scene.activationState == UISceneActivationStateForegroundActive) &&
        manager.preferencesAvailable && DXKeyboardPanelBool(manager.prefs, kEnabledkey, YES) &&
        DXKeyboardPanelBool(manager.prefs, kDXPanelGlobalEnabled, YES) && [manager.prefs isEqual:self.snapshot];
}
- (void)interrupted:(NSNotification *)notification { (void)notification; [self dismiss]; }
- (NSDictionary *)definition:(NSString *)selector {
    id definitions = DXPrefsManager.sharedInstance.prefs[kLinkActionskey];
    if (![definitions isKindOfClass:NSArray.class]) return nil;
    for (id entry in definitions)
        if ([entry isKindOfClass:NSDictionary.class] && [entry[@"selector"] isEqual:selector]) return entry;
    return nil;
}
- (void)presentSide:(NSString *)side fromWindow:(UIWindow *)sourceWindow origin:(NSString *)origin {
    if (!NSThread.isMainThread || ![NSProcessInfo.processInfo.processName isEqual:@"SpringBoard"]) return;
    if (![@[@"left", @"right", @"common"] containsObject:side]) return;
    DXPrefsManager *manager = DXPrefsManager.sharedInstance;
    [manager reload];
    if (!manager.preferencesAvailable || !DXKeyboardPanelBool(manager.prefs, kEnabledkey, YES) ||
        !DXKeyboardPanelBool(manager.prefs, kDXPanelGlobalEnabled, YES) || ![DXGlobalPanel deviceUnlocked]) {
        NSLog(@"[TypeX][GlobalPanel] open cancelled: preferences/lock gate"); return;
    }
    NSTimeInterval now = NSProcessInfo.processInfo.systemUptime;
    if (now - self.lastOpen < 0.35) return;
    self.lastOpen = now;
    [self dismiss];
    [[DXKeyboardPanel sharedInstance] dismiss];
    NSDictionary *preferences = manager.prefs;
    self.snapshot = [preferences copy];
    NSString *profile = [origin isEqual:@"dock"] ? @"common" : side;
    NSArray *entries = DXKeyboardPanelFilterCustomItems(DXKeyboardPanelItems(preferences, profile),
        preferences[kLinkActionskey], kLinkActionSelectorPrefix);
    preferences = DXKeyboardPanelProfilePreferences(preferences, profile);
    self.scale = DXKeyboardPanelNumber(preferences, kDXPanelScale, 100, 70, 120) / 100;
    self.columns = (NSInteger)DXKeyboardPanelNumber(preferences, kDXPanelColumns, 4, 3, 5);
    BOOL dark = DXKeyboardPanelBool(preferences, kDXPanelDark, YES);
    UIColor *text = dark ? UIColor.whiteColor : UIColor.labelColor;

    // SpringBoard has scene-less windows on some supported systems. A fresh
    // owned window is used per presentation and never made key.
    UIWindowScene *scene = sourceWindow.windowScene;
    if (scene && scene.activationState != UISceneActivationStateForegroundActive) { [self dismiss]; return; }
    if (!scene) {
        for (UIScene *candidate in UIApplication.sharedApplication.connectedScenes)
            if ([candidate isKindOfClass:UIWindowScene.class] && candidate.activationState == UISceneActivationStateForegroundActive) {
                scene = (UIWindowScene *)candidate; break;
            }
    }
    self.window = scene ? [[DXGlobalPanelWindow alloc] initWithWindowScene:scene] :
        [[DXGlobalPanelWindow alloc] initWithFrame:UIScreen.mainScreen.bounds];
    self.window.frame = scene ? scene.coordinateSpace.bounds : UIScreen.mainScreen.bounds;
    self.window.backgroundColor = UIColor.clearColor;
    // Use a stable content level rather than overtaking SpringBoard's system
    // overlays, which can place the panel above the screenshot capture range.
    self.window.windowLevel = UIWindowLevelAlert + 1;
    DXGlobalPanelController *controller = [DXGlobalPanelController new];
    controller.owner = self;
    self.window.rootViewController = controller;
    UIControl *outside = [[UIControl alloc] initWithFrame:controller.view.bounds];
    outside.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    outside.backgroundColor = [UIColor colorWithWhite:0 alpha:0.15];
    [outside addTarget:self action:@selector(dismiss) forControlEvents:UIControlEventTouchUpInside];
    [controller.view addSubview:outside];
    self.panel = [UIView new];
    self.panel.backgroundColor = dark ? [UIColor colorWithWhite:0.10 alpha:1] : UIColor.systemBackgroundColor;
    self.panel.layer.cornerRadius = 22;
    self.panel.clipsToBounds = YES;
    [controller.view addSubview:self.panel];
    self.header = [UIControl new];
    [self.header addTarget:self action:@selector(dismiss) forControlEvents:UIControlEventTouchUpInside];
    UISwipeGestureRecognizer *closeSwipe = [[UISwipeGestureRecognizer alloc] initWithTarget:self action:@selector(dismiss)];
    closeSwipe.direction = UISwipeGestureRecognizerDirectionDown;
    [self.header addGestureRecognizer:closeSwipe];
    [self.panel addSubview:self.header];
    self.title = [UILabel new];
    self.title.text = DXGlobalLocalized([profile isEqual:@"common"] ? @"KEYBOARD_PANEL_COMMON" :
        ([profile isEqual:@"left"] ? @"KEYBOARD_PANEL_LEFT" : @"KEYBOARD_PANEL_RIGHT"));
    self.title.textColor = text;
    self.title.font = [UIFont systemFontOfSize:15 weight:UIFontWeightSemibold];
    [self.panel addSubview:self.title];
    self.closeButton = [UIButton buttonWithType:UIButtonTypeSystem];
    [self.closeButton setImage:[UIImage systemImageNamed:@"xmark.circle.fill"] forState:UIControlStateNormal];
    self.closeButton.tintColor = text;
    self.closeButton.accessibilityLabel = DXGlobalLocalized(@"KEYBOARD_PANEL_CLOSE");
    [self.closeButton addTarget:self action:@selector(dismiss) forControlEvents:UIControlEventTouchUpInside];
    [self.panel addSubview:self.closeButton];
    self.message = [UILabel new];
    self.message.textColor = text;
    self.message.font = [UIFont systemFontOfSize:13];
    self.message.numberOfLines = 2;
    self.message.textAlignment = NSTextAlignmentCenter;
    self.message.hidden = YES;
    [self.panel addSubview:self.message];
    self.scroll = [UIScrollView new];
    self.scroll.showsVerticalScrollIndicator = NO;
    [self.panel addSubview:self.scroll];
    self.blank = [UIControl new];
    [self.blank addTarget:self action:@selector(dismiss) forControlEvents:UIControlEventTouchUpInside];
    [self.scroll addSubview:self.blank];
    self.controls = [DXPanelSystemControlsView new];
    [self.controls configureWithPreferences:preferences preview:NO];
    [self.scroll addSubview:self.controls];
    __weak typeof(self) weakSelf = self;
    __weak DXPanelSystemControlsView *controls = self.controls;
    if (self.controls.showsToggleRow || self.controls.showsSliderRow) {
        self.controlSession = [[DXPanelControlSession alloc] initWithRequester:^NSProgress *(NSString *action, NSNumber *value, DXPanelSystemControlReply reply) {
            return DXRequestPanelSystemControl(action, value, @"global", reply);
        } validity:^BOOL {
            DXGlobalPanel *owner = weakSelf;
            return owner && owner.controls == controls && [owner validSession];
        } update:^(DXSystemOpenResult result, NSDictionary *state, BOOL busy, NSString *action) {
            (void)action;
            [controls applyState:state busy:busy];
            [controls showMessage:result == DXSystemOpenSucceeded ? nil : DXGlobalLocalized(@"SYSTEM_ACTION_UNAVAILABLE")];
        }];
        self.controls.actionHandler = ^(NSString *action, NSNumber *value) {
            DXGlobalPanel *owner = weakSelf;
            if (owner.controls != controls || ![owner validSession]) { [owner dismiss]; return; }
            [owner.controlSession enqueueAction:action value:value];
        };
    }
    NSMutableArray *buttons = [NSMutableArray array];
    for (NSDictionary *entry in entries) {
        NSDictionary *definition = [self definition:entry[@"selector"]];
        if (!definition) continue;
        DXGlobalPanelItem *button = [DXGlobalPanelItem buttonWithType:UIButtonTypeCustom];
        button.actionSelector = entry[@"selector"];
        button.circle = [UIView new];
        button.circle.backgroundColor = dark ? [UIColor colorWithWhite:0 alpha:0.45] : [UIColor colorWithWhite:1 alpha:0.65];
        button.circle.userInteractionEnabled = NO;
        [button addSubview:button.circle];
        button.icon = [UIImageView new];
        button.icon.userInteractionEnabled = NO;
        button.icon.contentMode = UIViewContentModeScaleAspectFit;
        button.icon.tintColor = text;
        NSString *icon = [entry[@"icon"] length] ? entry[@"icon"] : DXGlobalPanelString(definition[@"icon"]);
        button.icon.image = [DXHelper imageForIconConfig:icon defaultSymbolName:@"square.grid.2x2"];
        [button addSubview:button.icon];
        button.name = [UILabel new];
        button.name.text = [entry[@"name"] length] ? entry[@"name"] : DXGlobalPanelString(definition[@"name"]);
        button.name.textColor = text;
        button.name.font = [UIFont systemFontOfSize:12 * self.scale];
        button.name.numberOfLines = 2;
        button.name.textAlignment = NSTextAlignmentCenter;
        button.name.adjustsFontSizeToFitWidth = YES;
        button.name.minimumScaleFactor = 0.8;
        [button addSubview:button.name];
        button.accessibilityLabel = button.name.text;
        [button addTarget:self action:@selector(itemTapped:) forControlEvents:UIControlEventTouchUpInside];
        [self.scroll addSubview:button];
        [buttons addObject:button];
    }
    self.items = buttons;
    if (!buttons.count) {
        self.empty = [UILabel new];
        self.empty.text = DXGlobalLocalized(@"KEYBOARD_PANEL_EMPTY");
        self.empty.textColor = text;
        self.empty.textAlignment = NSTextAlignmentCenter;
        self.empty.numberOfLines = 0;
        [self.scroll addSubview:self.empty];
    }
    self.window.hidden = NO;
    [self.window layoutIfNeeded];
    [self layout];
    [self.controlSession enqueueAction:@"state" value:nil];
    NSLog(@"[TypeX][GlobalPanel] open side=%@ origin=%@ items=%lu scene=%d level=%.0f",
        profile, origin, (unsigned long)buttons.count, scene != nil, (double)self.window.windowLevel);
}
- (void)layout {
    if (!self.window || !self.panel) return;
    UIView *root = self.window.rootViewController.view;
    CGRect frame = DXGlobalPanelFrame(root.bounds, MAX(self.window.safeAreaInsets.top, root.safeAreaInsets.top),
        MAX(self.window.safeAreaInsets.bottom, root.safeAreaInsets.bottom));
    if (CGRectIsNull(frame)) { [self dismiss]; return; }
    self.panel.frame = frame;
    CGFloat width = frame.size.width, height = frame.size.height;
    self.header.frame = CGRectMake(0, 0, width, 46);
    self.title.frame = CGRectMake(16, 10, MAX(0, width - 68), 28);
    self.closeButton.frame = CGRectMake(width - 48, 2, 44, 44);
    CGFloat messageHeight = self.message.text.length ? 44 : 0;
    self.message.frame = CGRectMake(10, 46, width - 20, messageHeight);
    self.scroll.frame = CGRectMake(8, 46 + messageHeight, width - 16, MAX(0, height - 54 - messageHeight));
    CGFloat contentWidth = self.scroll.bounds.size.width;
    CGFloat controlsHeight = [self.controls preferredHeightForWidth:contentWidth];
    self.controls.frame = CGRectMake(0, 0, contentWidth, controlsHeight);
    CGFloat circle = DXKeyboardPanelCircle(contentWidth, self.columns, self.scale);
    for (NSUInteger index = 0; index < self.items.count; index++) {
        DXGlobalPanelItem *button = self.items[index];
        CGRect frame = DXKeyboardPanelItemFrame(index, contentWidth, self.columns, self.scale);
        frame.origin.y += controlsHeight;
        button.frame = frame;
        CGFloat slot = frame.size.width;
        button.circle.frame = CGRectMake((slot - circle) / 2, 4, circle, circle);
        button.circle.layer.cornerRadius = circle / 2;
        CGFloat icon = circle * 0.52;
        button.icon.frame = CGRectMake((slot - icon) / 2, 4 + (circle - icon) / 2, icon, icon);
        button.name.frame = CGRectMake(3, circle + 9, slot - 6, 30 * self.scale);
    }
    CGFloat gridHeight = self.items.count ? DXKeyboardPanelContentHeight(self.items.count, contentWidth, self.columns, self.scale) : 70;
    CGFloat total = MAX(self.scroll.bounds.size.height, controlsHeight + gridHeight);
    self.scroll.contentSize = CGSizeMake(contentWidth, total);
    self.blank.frame = CGRectMake(0, 0, contentWidth, total);
    self.empty.frame = CGRectMake(0, controlsHeight, contentWidth, 70);
}
- (void)itemTapped:(DXGlobalPanelItem *)button {
    if (![self validSession] || ![self.items containsObject:button]) { [self dismiss]; return; }
    NSDictionary *entry = [self definition:button.actionSelector];
    if (!entry) { [self dismiss]; return; }
    if (DXGlobalPanelActionNeedsInput(entry)) {
        [self showMessage:DXGlobalLocalized(@"GLOBAL_PANEL_INPUT_REQUIRED")]; return;
    }
    NSString *type = [entry[@"type"] isKindOfClass:NSString.class] ? entry[@"type"] : @"";
    NSString *payload = DXGlobalPanelNormalizedPayload(entry[@"link"]);
    NSString *systemAction = DXGlobalPanelString(entry[kCustomActionSystemIdentifierKey]);
    NSString *shortcutType = DXGlobalPanelString(entry[kCustomActionShortcutTypeKey]);
    BOOL application = [type isEqual:kCustomActionTypeOpenApp] || (!type.length && DXIsValidBundleIdentifier(payload));
    NSURL *url = nil;
    if ([type isEqual:kCustomActionTypeURL] || [type isEqual:kCustomActionTypeURLScheme] || !type.length) {
        if (DXIsOpenableSchemeURLString(payload)) url = [NSURL URLWithString:payload];
        if ([type isEqual:kCustomActionTypeURL] && (!url.host.length || ![@[@"http", @"https"] containsObject:url.scheme.lowercaseString])) url = nil;
    }
    if (!([type isEqual:kCustomActionTypeSystem] || [type isEqual:kCustomActionTypeShortcut] ||
          (application && DXIsValidBundleIdentifier(payload)) || url)) {
        [self showMessage:DXGlobalLocalized(@"CUSTOM_ACTION_LINK_ERROR")]; return;
    }
    // Close synchronously before any navigation or confirmation. No delayed
    // callback can insert text or reopen a dismissed/newer panel.
    [self dismiss];
    DXSystemOpenReply reply = ^(DXSystemOpenResult result) {
        NSLog(@"[TypeX][GlobalPanel] action result=%llu", (unsigned long long)result);
    };
    if ([type isEqual:kCustomActionTypeSystem]) { DXRunSystemAction(systemAction, reply); return; }
    if ([type isEqual:kCustomActionTypeShortcut]) { DXOpenSystemShortcut(payload, shortcutType, reply); return; }
    if (application) {
        if ([entry[kCustomActionUsePullOverKey] isKindOfClass:NSNumber.class] && [entry[kCustomActionUsePullOverKey] boolValue] && [DXShortcutsGenerator isPullOverXInstalled]) {
            int token = NOTIFY_TOKEN_INVALID;
            uint64_t state = DXPullOverOpenStateForBundleIdentifier(payload);
            BOOL published = state && notify_register_check(kPullOverOpenRequestIdentifier.UTF8String, &token) == NOTIFY_STATUS_OK &&
                notify_set_state(token, state) == NOTIFY_STATUS_OK && notify_post(kPullOverOpenRequestIdentifier.UTF8String) == NOTIFY_STATUS_OK;
            if (token != NOTIFY_TOKEN_INVALID) notify_cancel(token);
            if (published) return;
        }
        DXOpenSystemApplication(payload, reply); return;
    }
    if (DXIsSensitiveOpenScheme(url.scheme)) { DXOpenSensitiveSystemURL(url, reply); return; }
    UIApplication *app = UIApplication.sharedApplication;
    if (![app respondsToSelector:@selector(openURL:options:completionHandler:)]) { reply(DXSystemOpenUnavailable); return; }
    @try {
        // Ordinary schemes stay single-shot, including a swallowed completion.
        [app openURL:url options:@{} completionHandler:^(BOOL success) { reply(success ? DXSystemOpenSucceeded : DXSystemOpenFailed); }];
    } @catch (__unused NSException *exception) { reply(DXSystemOpenFailed); }
}
- (void)showMessage:(NSString *)message {
    self.message.text = message;
    self.message.hidden = !message.length;
    [self layout];
}
- (void)dismiss {
    if (!NSThread.isMainThread) { dispatch_async(dispatch_get_main_queue(), ^{ [self dismiss]; }); return; }
    [self.controlSession invalidate]; self.controlSession = nil;
    self.controls.actionHandler = nil; self.controls = nil;
    self.window.hidden = YES;
    self.window.rootViewController = nil; self.window = nil;
    self.panel = nil; self.scroll = nil; self.items = nil; self.snapshot = nil;
    self.title = nil; self.message = nil; self.closeButton = nil; self.header = nil; self.blank = nil; self.empty = nil;
}
@end

void DXStartGlobalPanel(void) {
    if (![NSProcessInfo.processInfo.processName isEqual:@"SpringBoard"]) return;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        // Registrations live for this SpringBoard process, not panel sessions.
        for (NSString *name in @[DXGlobalPanelLeftNotification, DXGlobalPanelRightNotification, DXGlobalPanelCommonNotification]) {
            int token = NOTIFY_TOKEN_INVALID;
            uint32_t result = notify_register_dispatch(name.UTF8String, &token, dispatch_get_main_queue(), ^(int deliveredToken) {
                (void)deliveredToken;
                [[DXGlobalPanel sharedInstance] presentSide:DXGlobalPanelSideForNotification(name) fromWindow:nil origin:@"notification"];
            });
            if (result != NOTIFY_STATUS_OK) NSLog(@"[TypeX][GlobalPanel] registration failed name=%@ result=%u", name, result);
        }
        for (NSString *name in @[@"com.apple.springboard.lockstate", @"com.apple.springboard.frontmostapplicationchanged"]) {
            int token = NOTIFY_TOKEN_INVALID;
            notify_register_dispatch(name.UTF8String, &token, dispatch_get_main_queue(), ^(int deliveredToken) {
                (void)deliveredToken;
                [[DXGlobalPanel sharedInstance] dismiss];
            });
        }
    });
}
