// Scene-layer hosting and foreground assertions follow the mechanisms in
// PullOver-X (c1d3rDev / PullOver-X contributors, GPL-3.0). TypeX owns this
// session, requester identity, UI and routing; no PullOver-X binary is used.
#import "DXFloatingApp.h"
#import "DXFloatingAppSession.h"
#import "DXGlobalPanel.h"
#import "common.h"
#import <UIKit/UIKit.h>
#import <objc/message.h>
#import <objc/runtime.h>
#import <dlfcn.h>
#import <notify.h>
#include <math.h>
#include <limits.h>

static NSString * const DXFloatRequester = @"com.lindo.typex.floating-app";
static void *DXFloatLayerObservation = &DXFloatLayerObservation;
static NSBundle *tweakBundle;
static BOOL DXFloatHooksReady;

static id DXFloatObject(id object, NSString *name) {
    SEL selector = NSSelectorFromString(name);
    NSMethodSignature *signature = [object methodSignatureForSelector:selector];
    if (![object respondsToSelector:selector] || signature.numberOfArguments != 2 ||
        (strcmp(signature.methodReturnType, "@") && strcmp(signature.methodReturnType, "#"))) return nil;
    @try { return ((id (*)(id, SEL))objc_msgSend)(object, selector); }
    @catch (__unused NSException *exception) { return nil; }
}

static id DXFloatObjectArgument(id object, NSString *name, id argument) {
    SEL selector = NSSelectorFromString(name);
    NSMethodSignature *signature = [object methodSignatureForSelector:selector];
    if (![object respondsToSelector:selector] || signature.numberOfArguments != 3 ||
        strcmp(signature.methodReturnType, "@") || strcmp([signature getArgumentTypeAtIndex:2], "@")) return nil;
    @try { return ((id (*)(id, SEL, id))objc_msgSend)(object, selector, argument); }
    @catch (__unused NSException *exception) { return nil; }
}

static NSInteger DXFloatInteger(id object, NSString *name, NSInteger fallback) {
    SEL selector = NSSelectorFromString(name);
    NSMethodSignature *signature = [object methodSignatureForSelector:selector];
    if (![object respondsToSelector:selector] || signature.numberOfArguments != 2) return fallback;
    const char *type = signature.methodReturnType;
    if (!type || !strchr("cCsSiIlLqQB", type[0]) || type[1]) return fallback;
    @try {
        NSInvocation *invocation = [NSInvocation invocationWithMethodSignature:signature];
        invocation.target = object; invocation.selector = selector;
        [invocation invoke];
        // Sign-extension matters for -1 failure/PID values.
        if (signature.methodReturnLength == 1) { int8_t value = 0; [invocation getReturnValue:&value]; return value; }
        if (signature.methodReturnLength == 2) { int16_t value = 0; [invocation getReturnValue:&value]; return value; }
        if (signature.methodReturnLength == 4) { int32_t value = 0; [invocation getReturnValue:&value]; return value; }
        if (signature.methodReturnLength == 8) { int64_t value = 0; [invocation getReturnValue:&value]; return (NSInteger)value; }
    } @catch (__unused NSException *exception) {}
    return fallback;
}

static void DXFloatSetBool(id object, NSString *name, BOOL value) {
    SEL selector = NSSelectorFromString(name);
    NSMethodSignature *signature = [object methodSignatureForSelector:selector];
    if (![object respondsToSelector:selector] || signature.numberOfArguments != 3 ||
        strcmp(signature.methodReturnType, "v")) return;
    const char *argument = [signature getArgumentTypeAtIndex:2];
    if (strcmp(argument, @encode(BOOL)) && strcmp(argument, "c")) return;
    ((void (*)(id, SEL, BOOL))objc_msgSend)(object, selector, value);
}

static NSString *DXFloatIdentifier(id application) {
    if ([application isKindOfClass:NSString.class]) return application;
    id identifier = DXFloatObject(application, @"bundleIdentifier") ?: DXFloatObject(application, @"applicationIdentifier")
        ?: DXFloatObject(application, @"displayIdentifier");
    return [identifier isKindOfClass:NSString.class] ? identifier : nil;
}

static id DXFloatApplication(NSString *identifier) {
    id controller = DXFloatObject(NSClassFromString(@"SBApplicationController"), @"sharedInstance");
    return DXFloatObjectArgument(controller, @"applicationWithBundleIdentifier:", identifier)
        ?: DXFloatObjectArgument(controller, @"applicationWithDisplayIdentifier:", identifier);
}

static NSString *DXFloatFrontmostIdentifier(void) {
    return DXFloatIdentifier(DXFloatObject(UIApplication.sharedApplication, @"_accessibilityFrontMostApplication"));
}

static BOOL DXFloatSceneMatches(id scene, NSString *bundleIdentifier) {
    id value = DXFloatObject(scene, @"identifier");
    if (![value isKindOfClass:NSString.class] || !bundleIdentifier.length) return NO;
    NSString *identifier = value;
    return [identifier isEqual:bundleIdentifier] || [identifier hasPrefix:[bundleIdentifier stringByAppendingString:@"-"]]
        || [identifier hasPrefix:[@"sceneID:" stringByAppendingFormat:@"%@-", bundleIdentifier]];
}

static id DXFloatFindScene(NSString *identifier) {
    id manager = DXFloatObject(NSClassFromString(@"FBSceneManager"), @"sharedInstance");
    SEL enumerate = NSSelectorFromString(@"enumerateScenesWithBlock:");
    __block id bestScene;
    __block NSInteger bestScore = -1;
    if ([manager respondsToSelector:enumerate]) {
        @try {
            ((void (*)(id, SEL, id))objc_msgSend)(manager, enumerate, ^(id scene, __unused BOOL *stop) {
                if (!DXFloatSceneMatches(scene, identifier) || !DXFloatInteger(scene, @"isValid", YES)) return;
                NSString *sceneIdentifier = DXFloatObject(scene, @"identifier");
                NSInteger score = [sceneIdentifier hasSuffix:@"-default"] ? 100 : 10;
                if (DXFloatInteger(scene, @"isActive", NO)) score += 1;
                if (score > bestScore) { bestScene = scene; bestScore = score; }
            });
        } @catch (__unused NSException *exception) {}
    }
    if (bestScene) return bestScene;
    id application = DXFloatApplication(identifier);
    for (NSString *name in @[@"mainScene", @"_mainScene", @"scene"]) {
        id scene = DXFloatObject(application, name);
        if (scene && DXFloatInteger(scene, @"isValid", YES) && DXFloatSceneMatches(scene, identifier)) return scene;
    }
    return nil;
}

static pid_t DXFloatPID(NSString *identifier) {
    id application = DXFloatApplication(identifier);
    NSInteger pid = DXFloatInteger(application, @"pid", 0);
    if (pid <= 0) pid = DXFloatInteger(DXFloatObject(application, @"processState"), @"pid", 0);
    return pid > 0 && pid <= INT_MAX ? (pid_t)pid : 0;
}

static NSString *DXFloatConstant(const char *name) {
    NSString * __unsafe_unretained *symbol = (NSString * __unsafe_unretained *)dlsym(RTLD_DEFAULT, name);
    return symbol && [*symbol isKindOfClass:NSString.class] ? *symbol : nil;
}

NSString *DXFloatingBundleIdentifierForURL(NSURL *url) {
    if (!NSThread.isMainThread || !url.scheme.length) return nil;
    id workspace = DXFloatObject(NSClassFromString(@"LSApplicationWorkspace"), @"defaultWorkspace");
    NSString *identifier = DXFloatIdentifier(DXFloatObjectArgument(workspace, @"applicationForOpeningResource:", url));
    if (DXIsValidBundleIdentifier(identifier) && DXFloatApplication(identifier)) return identifier;
    id candidates = DXFloatObjectArgument(workspace, @"applicationsAvailableForOpeningURL:", url);
    if (![candidates isKindOfClass:NSArray.class] || ![candidates count])
        candidates = DXFloatObjectArgument(workspace, @"applicationsAvailableForHandlingURLScheme:", url.scheme);
    if ([candidates isKindOfClass:NSArray.class]) {
        for (id application in candidates) {
            identifier = DXFloatIdentifier(application);
            if (DXIsValidBundleIdentifier(identifier) && DXFloatApplication(identifier)) return identifier;
        }
    }
    // Settings' private schemes aren't included in every LaunchServices list.
    if ([@[@"prefs", @"app-prefs"] containsObject:url.scheme.lowercaseString] && DXFloatApplication(@"com.apple.Preferences"))
        return @"com.apple.Preferences";
    return nil;
}

@class DXFloatingAppCoordinator;

@interface DXFloatingAppWindow : UIWindow
@property(nonatomic, weak) UIView *card;
@end
@implementation DXFloatingAppWindow
- (BOOL)canBecomeKeyWindow { return NO; }
- (bool)_shouldCreateContextAsSecure { return YES; }
- (UIView *)hitTest:(CGPoint)point withEvent:(UIEvent *)event {
    if (self.hidden || !self.card || self.card.hidden) return nil;
    CGPoint local = [self.card convertPoint:point fromView:self];
    return [self.card pointInside:local withEvent:event] ? [self.card hitTest:local withEvent:event] : nil;
}
@end

@interface DXFloatingAppCardController : UIViewController
@property(nonatomic, weak) DXFloatingAppCoordinator *owner;
@property(nonatomic, strong) UIView *card;
@property(nonatomic, strong) UIView *canvas;
@property(nonatomic, strong) UIView *content;
@property(nonatomic, strong) UILabel *titleLabel;
@property(nonatomic, strong) UIActivityIndicatorView *spinner;
@property(nonatomic) CGSize canvasSize;
@property(nonatomic) CGPoint normalizedCenter;
- (void)setTitle:(NSString *)title;
- (void)setHostViews:(NSArray<UIView *> *)views canvasSize:(CGSize)size;
@end

@interface DXFloatingAppCoordinator : NSObject
@property(nonatomic, strong) DXFloatingAppSession *session;
@property(nonatomic, strong) DXFloatingAppWindow *window;
@property(nonatomic, strong) DXFloatingAppCardController *controller;
@property(nonatomic, strong) id scene;
@property(nonatomic, strong) id baseScene;
@property(nonatomic, copy) NSString *baseIdentifier;
@property(nonatomic, strong) id originalSettings;
@property(nonatomic, strong) id layerManager;
@property(nonatomic, strong) id fallbackHostManager;
@property(nonatomic, strong) id assertion;
@property(nonatomic, strong) NSArray *publishedLayers;
@property(nonatomic, copy) NSURL *requestedURL;
@property(nonatomic) BOOL urlAccepted;
@property(nonatomic) BOOL hasContent;
@property(nonatomic) BOOL observingLayers;
@property(nonatomic) pid_t processPID;
@property(nonatomic) BOOL activeLease;
@property(nonatomic) BOOL sceneCreationAttempted;
@property(nonatomic, strong) NSArray<NSNumber *> *notifyTokens;
+ (instancetype)shared;
- (void)open:(NSString *)identifier url:(NSURL *)url deadline:(NSDate *)deadline reply:(DXSystemOpenReply)reply;
- (void)close;
- (void)cleanup:(DXSystemOpenResult)result reason:(NSString *)reason;
- (void)poll:(NSUInteger)generation;
- (void)publishLayers;
- (BOOL)protectsScene:(id)scene;
- (id)protectedSettings:(id)settings scene:(id)scene;
@end

@implementation DXFloatingAppCardController
- (void)loadView {
    self.view = [[UIView alloc] initWithFrame:UIScreen.mainScreen.bounds];
    self.view.backgroundColor = UIColor.clearColor;
    self.normalizedCenter = CGPointMake(0.5, 0.45);
    self.card = [[UIView alloc] init];
    self.card.backgroundColor = UIColor.secondarySystemBackgroundColor;
    self.card.layer.cornerRadius = 16;
    self.card.layer.masksToBounds = YES;
    [self.view addSubview:self.card];
    UIView *header = [[UIView alloc] init]; header.tag = 41;
    [self.card addSubview:header];
    self.titleLabel = [[UILabel alloc] init]; self.titleLabel.font = [UIFont systemFontOfSize:14 weight:UIFontWeightSemibold];
    self.titleLabel.textColor = UIColor.labelColor;
    [header addSubview:self.titleLabel];
    UIButton *close = [UIButton buttonWithType:UIButtonTypeSystem]; close.tag = 42;
    [close setImage:[UIImage systemImageNamed:@"xmark.circle.fill"] forState:UIControlStateNormal];
    close.accessibilityLabel = LOCALIZED(@"FLOATING_APP_CLOSE");
    [close addTarget:self action:@selector(closeTapped) forControlEvents:UIControlEventTouchUpInside];
    [header addSubview:close];
    UIPanGestureRecognizer *drag = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(drag:)];
    [header addGestureRecognizer:drag];
    self.content = [[UIView alloc] init]; self.content.clipsToBounds = YES;
    [self.card addSubview:self.content];
    self.canvas = [[UIView alloc] init]; [self.content addSubview:self.canvas];
    self.spinner = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleMedium];
    [self.content addSubview:self.spinner]; [self.spinner startAnimating];
}
- (void)closeTapped { [self.owner close]; }
- (void)setTitle:(NSString *)title { [self loadViewIfNeeded]; self.titleLabel.text = title; }
- (void)drag:(UIPanGestureRecognizer *)gesture {
    CGPoint translation = [gesture translationInView:self.view];
    CGPoint center = self.card.center;
    center.x += translation.x; center.y += translation.y;
    self.normalizedCenter = CGPointMake(center.x / MAX(1, self.view.bounds.size.width), center.y / MAX(1, self.view.bounds.size.height));
    [gesture setTranslation:CGPointZero inView:self.view];
    [self.view setNeedsLayout]; [self.view layoutIfNeeded];
}
- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    CGRect bounds = self.view.bounds;
    UIEdgeInsets safe = self.view.safeAreaInsets;
    CGRect available = UIEdgeInsetsInsetRect(bounds, UIEdgeInsetsMake(safe.top + 8, safe.left + 8, safe.bottom + 8, safe.right + 8));
    CGSize size = self.canvasSize;
    if (size.width < 1 || size.height < 1) size = UIScreen.mainScreen.bounds.size;
    CGFloat scale = MIN(0.72, MIN(available.size.width / size.width, MAX(1, available.size.height - 44) / size.height));
    CGFloat width = size.width * scale, height = size.height * scale + 44;
    CGPoint center = CGPointMake(bounds.size.width * self.normalizedCenter.x, bounds.size.height * self.normalizedCenter.y);
    center.x = MAX(CGRectGetMinX(available) + width / 2, MIN(CGRectGetMaxX(available) - width / 2, center.x));
    center.y = MAX(CGRectGetMinY(available) + height / 2, MIN(CGRectGetMaxY(available) - height / 2, center.y));
    self.card.frame = CGRectMake(center.x - width / 2, center.y - height / 2, width, height);
    UIView *header = [self.card viewWithTag:41]; header.frame = CGRectMake(0, 0, width, 44);
    [header viewWithTag:42].frame = CGRectMake(width - 44, 0, 44, 44);
    self.titleLabel.frame = CGRectMake(12, 0, MAX(0, width - 60), 44);
    self.content.frame = CGRectMake(0, 44, width, height - 44);
    self.canvas.transform = CGAffineTransformIdentity;
    self.canvas.bounds = (CGRect){CGPointZero, size};
    self.canvas.center = CGPointMake(width / 2, (height - 44) / 2);
    self.canvas.transform = CGAffineTransformMakeScale(scale, scale);
    self.spinner.center = CGPointMake(width / 2, (height - 44) / 2);
}
- (void)setHostViews:(NSArray<UIView *> *)views canvasSize:(CGSize)size {
    self.canvasSize = size;
    for (UIView *view in [self.canvas.subviews copy]) [view removeFromSuperview];
    for (UIView *view in views) {
        view.frame = (CGRect){CGPointZero, size};
        view.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
        [self.canvas addSubview:view];
    }
    [self.spinner stopAnimating];
    [self.view setNeedsLayout]; [self.view layoutIfNeeded];
}
@end

static UIWindowScene *DXFloatWindowScene(void) {
    UIWindowScene *fallback;
    for (UIScene *scene in UIApplication.sharedApplication.connectedScenes) {
        if (![scene isKindOfClass:UIWindowScene.class]) continue;
        UIWindowScene *windowScene = (UIWindowScene *)scene;
        NSString *identity = windowScene.session.persistentIdentifier ?: @"";
        NSString *role = windowScene.session.role ?: @"";
        if ([identity isEqual:@"com.apple.springboard"]) return windowScene;
        if ([identity.lowercaseString containsString:@"keyboard"] || [identity.lowercaseString containsString:@"systemaperture"] ||
            [role.lowercaseString containsString:@"keyboard"] || [role.lowercaseString containsString:@"systemaperture"]) continue;
        if ([NSStringFromClass(windowScene.class) isEqual:@"SBWindowScene"]) fallback = windowScene;
    }
    return fallback;
}

static void DXFloatApplySettings(id scene, id settings) {
    SEL three = NSSelectorFromString(@"updateSettings:withTransitionContext:completion:");
    SEL two = NSSelectorFromString(@"updateSettings:withTransitionContext:");
    if ([scene respondsToSelector:three]) ((void (*)(id, SEL, id, id, id))objc_msgSend)(scene, three, settings, nil, nil);
    else if ([scene respondsToSelector:two]) ((void (*)(id, SEL, id, id))objc_msgSend)(scene, two, settings, nil);
}

static void DXFloatForegroundSettings(id settings, BOOL foreground) {
    DXFloatSetBool(settings, @"setForeground:", foreground);
    DXFloatSetBool(settings, @"setBackgrounded:", !foreground);
    SEL reasons = NSSelectorFromString(@"setDeactivationReasons:");
    if (foreground && [settings respondsToSelector:reasons]) ((void (*)(id, SEL, unsigned long long))objc_msgSend)(settings, reasons, 0);
}

@implementation DXFloatingAppCoordinator
+ (instancetype)shared {
    static DXFloatingAppCoordinator *coordinator;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        tweakBundle = [NSBundle bundleWithPath:bundlePath];
        coordinator = [self new]; coordinator.session = [DXFloatingAppSession new];
    });
    return coordinator;
}
- (BOOL)protectsScene:(id)scene {
    return NSThread.isMainThread && self.activeLease && self.session.state != DXFloatingAppIdle &&
        (scene == self.scene || scene == self.baseScene);
}
- (id)protectedSettings:(id)settings scene:(id)scene {
    if (![self protectsScene:scene]) return settings;
    @try {
        id mutable = DXFloatObject(settings, @"mutableCopy");
        if (!mutable) return settings;
        DXFloatForegroundSettings(mutable, YES);
        return mutable;
    } @catch (__unused NSException *exception) { return settings; }
}
- (void)close { [self cleanup:DXSystemOpenFailed reason:@"close-button"]; }
- (void)cleanup:(DXSystemOpenResult)result reason:(NSString *)reason {
    if (!NSThread.isMainThread) { dispatch_async(dispatch_get_main_queue(), ^{ [self cleanup:result reason:reason]; }); return; }
    NSString *identifier = self.session.bundleIdentifier;
    self.activeLease = NO;
    // Revoke callbacks before releasing the scene or removing the views.
    [self.session finish:result];
    if (self.observingLayers && self.layerManager) {
        @try { [self.layerManager removeObserver:self forKeyPath:@"layers" context:DXFloatLayerObservation]; }
        @catch (__unused NSException *exception) {}
    }
    self.observingLayers = NO;
    if (self.assertion && [self.assertion respondsToSelector:NSSelectorFromString(@"invalidate")]) {
        @try { ((void (*)(id, SEL))objc_msgSend)(self.assertion, NSSelectorFromString(@"invalidate")); }
        @catch (__unused NSException *exception) {}
    }
    self.assertion = nil;
    if (self.fallbackHostManager && [self.fallbackHostManager respondsToSelector:NSSelectorFromString(@"disableHostingForRequester:")]) {
        @try { ((void (*)(id, SEL, id))objc_msgSend)(self.fallbackHostManager, NSSelectorFromString(@"disableHostingForRequester:"), DXFloatRequester); }
        @catch (__unused NSException *exception) {}
    }
    @try {
        // A user-initiated full-screen takeover keeps its system foreground
        // state. Closing the card otherwise backgrounds, never kills, the app.
        if (self.scene && ![DXFloatFrontmostIdentifier() isEqual:identifier]) {
            id settings = DXFloatObject(self.originalSettings, @"mutableCopy") ?: DXFloatObject(self.scene, @"mutableSettings");
            DXFloatForegroundSettings(settings, NO);
            DXFloatApplySettings(self.scene, settings);
        }
    } @catch (__unused NSException *exception) {}
    self.window.hidden = YES; self.window.rootViewController = nil;
    self.window = nil; self.controller = nil;
    self.scene = nil; self.baseScene = nil; self.baseIdentifier = nil;
    self.originalSettings = nil; self.layerManager = nil; self.fallbackHostManager = nil;
    self.publishedLayers = nil; self.requestedURL = nil; self.urlAccepted = NO;
    self.hasContent = NO; self.processPID = 0; self.sceneCreationAttempted = NO;
    if (identifier.length) NSLog(@"[TypeX][FloatingApp] release bundleID=%@ reason=%@", identifier, reason);
}
- (BOOL)prewarm:(NSString *)identifier {
    UIApplication *application = UIApplication.sharedApplication;
    SEL launch = NSSelectorFromString(@"launchApplicationWithIdentifier:suspended:");
    NSMethodSignature *signature = [application methodSignatureForSelector:launch];
    if (![application respondsToSelector:launch] || signature.numberOfArguments != 4) return NO;
    const char *argument = [signature getArgumentTypeAtIndex:3];
    if (strcmp([signature getArgumentTypeAtIndex:2], "@") || (strcmp(argument, @encode(BOOL)) && strcmp(argument, "c"))) return NO;
    @try {
        if (!strcmp(signature.methodReturnType, "v")) {
            ((void (*)(id, SEL, id, BOOL))objc_msgSend)(application, launch, identifier, YES); return YES;
        }
        if (!strcmp(signature.methodReturnType, @encode(BOOL)) || !strcmp(signature.methodReturnType, "c"))
            return ((BOOL (*)(id, SEL, id, BOOL))objc_msgSend)(application, launch, identifier, YES);
    } @catch (__unused NSException *exception) {}
    return NO;
}
- (BOOL)deliverURL:(NSURL *)url generation:(NSUInteger)generation {
    id service = DXFloatObject(NSClassFromString(@"FBSSystemService"), @"sharedService");
    SEL open = NSSelectorFromString(@"openApplication:options:withResult:");
    NSString *suspendedKey = DXFloatConstant("FBSOpenApplicationOptionKeyActivateSuspended");
    NSString *urlKey = DXFloatConstant("FBSOpenApplicationOptionKeyPayloadURL");
    NSString *optionsKey = DXFloatConstant("FBSOpenApplicationOptionKeyPayloadOptions");
    NSMethodSignature *signature = [service methodSignatureForSelector:open];
    if (![service respondsToSelector:open] || signature.numberOfArguments != 5 || strcmp(signature.methodReturnType, "v") ||
        !suspendedKey.length || !urlKey.length || !optionsKey.length) return NO;
    NSMutableDictionary *options = [@{suspendedKey: @YES, urlKey: url,
        @"__TypeXFloatingGeneration": @(generation),
        optionsKey: @{UIApplicationLaunchOptionsSourceApplicationKey: self.baseIdentifier ?: @"com.apple.springboard"}} mutableCopy];
    NSString *validKey = DXFloatConstant("FBSOpenApplicationOptionKeyPayloadIsValid");
    if (validKey.length) options[validKey] = @YES;
    __weak typeof(self) weakSelf = self;
    @try {
        ((void (*)(id, SEL, id, id, id))objc_msgSend)(service, open, self.session.bundleIdentifier, options, ^(NSError *error) {
            dispatch_async(dispatch_get_main_queue(), ^{
                DXFloatingAppCoordinator *host = weakSelf;
                if (![host.session isCurrent:generation]) return;
                if (error) { [host cleanup:DXSystemOpenFailed reason:@"url-delivery-failed"]; return; }
                host.urlAccepted = YES;
                NSLog(@"[TypeX][FloatingApp] URL accepted bundleID=%@ generation=%lu", host.session.bundleIdentifier, (unsigned long)generation);
            });
        });
        return YES;
    } @catch (__unused NSException *exception) { return NO; }
}
- (BOOL)acquireAssertion {
    if (self.assertion) return YES;
    Class targetClass = NSClassFromString(@"RBSTarget"), attributeClass = NSClassFromString(@"RBSLegacyAttribute");
    Class assertionClass = NSClassFromString(@"RBSAssertion");
    SEL targetSelector = NSSelectorFromString(@"targetWithPid:"), attributeSelector = NSSelectorFromString(@"attributeWithReason:flags:");
    SEL initializer = NSSelectorFromString(@"initWithExplanation:target:attributes:"), acquire = NSSelectorFromString(@"acquireWithError:");
    if (![targetClass respondsToSelector:targetSelector] || ![attributeClass respondsToSelector:attributeSelector] ||
        ![assertionClass instancesRespondToSelector:initializer] || ![assertionClass instancesRespondToSelector:acquire]) return NO;
    @try {
        id target = ((id (*)(id, SEL, int))objc_msgSend)(targetClass, targetSelector, self.processPID);
        id attribute = ((id (*)(id, SEL, NSUInteger, NSUInteger))objc_msgSend)(attributeClass, attributeSelector, 7, (1U << 0) | (1U << 1) | (1U << 3) | (1U << 5));
        if (!target || !attribute) return NO;
        id assertion = ((id (*)(id, SEL, id, id, id))objc_msgSend)([assertionClass alloc], initializer,
            @"TypeX live floating application", target, @[attribute]);
        NSError *error;
        if (!((BOOL (*)(id, SEL, NSError **))objc_msgSend)(assertion, acquire, &error)) return NO;
        self.assertion = assertion;
        return YES;
    } @catch (__unused NSException *exception) { return NO; }
}
- (void)open:(NSString *)identifier url:(NSURL *)url deadline:(NSDate *)deadline reply:(DXSystemOpenReply)reply {
    if (!NSThread.isMainThread || !DXFloatHooksReady || ![DXGlobalPanel deviceUnlocked] || !DXIsValidBundleIdentifier(identifier) ||
        !DXFloatApplication(identifier) || deadline.timeIntervalSinceNow <= 0) {
        if (reply) reply(DXSystemOpenUnavailable); return;
    }
    if (!url && self.session.state == DXFloatingAppLive && [self.session.bundleIdentifier isEqual:identifier]) {
        if (reply) reply(DXSystemOpenSucceeded); return;
    }
    NSString *frontmost = DXFloatFrontmostIdentifier();
    if ([frontmost isEqual:identifier]) { if (reply) reply(DXSystemOpenBusy); return; }
    UIWindowScene *windowScene = DXFloatWindowScene();
    if (!windowScene) { if (reply) reply(DXSystemOpenUnavailable); return; }
    [self cleanup:DXSystemOpenBusy reason:@"target-switch"];
    NSUInteger generation = [self.session beginBundleIdentifier:identifier deadline:deadline reply:reply];
    self.baseIdentifier = frontmost;
    self.baseScene = frontmost.length ? DXFloatFindScene(frontmost) : nil;
    self.requestedURL = url; self.urlAccepted = !url;
    self.controller = [DXFloatingAppCardController new]; self.controller.owner = self;
    id application = DXFloatApplication(identifier);
    NSString *title = DXFloatObject(application, @"displayName") ?: identifier;
    [self.controller setTitle:title];
    self.window = [[DXFloatingAppWindow alloc] initWithWindowScene:windowScene];
    self.window.frame = windowScene.coordinateSpace.bounds;
    self.window.backgroundColor = UIColor.clearColor;
    self.window.windowLevel = 100;
    self.window.rootViewController = self.controller;
    self.window.card = self.controller.card;
    self.window.hidden = NO;
    NSLog(@"[TypeX][FloatingApp] prepare bundleID=%@ generation=%lu scheme=%@", identifier, (unsigned long)generation, url.scheme ?: @"none");
    if (url ? ![self deliverURL:url generation:generation] : ![self prewarm:identifier]) {
        [self cleanup:DXSystemOpenUnavailable reason:@"suspended-launch-unavailable"]; return;
    }
    [self poll:generation];
}
- (CGSize)canvasSize {
    id settings = DXFloatObject(self.scene, @"settings");
    SEL frame = NSSelectorFromString(@"frame");
    NSMethodSignature *signature = [settings methodSignatureForSelector:frame];
    if ([settings respondsToSelector:frame] && signature.numberOfArguments == 2 && !strcmp(signature.methodReturnType, @encode(CGRect))) {
        CGRect rect = ((CGRect (*)(id, SEL))objc_msgSend)(settings, frame);
        if (isfinite(rect.size.width) && isfinite(rect.size.height) && rect.size.width > 1 && rect.size.height > 1) return rect.size;
    }
    return UIScreen.mainScreen.bounds.size;
}
- (void)publishLayers {
    if (!NSThread.isMainThread || !self.activeLease || !self.scene || !self.controller) return;
    // A scene with an unready content state can already own layers. Don't
    // acknowledge an icon/launch placeholder as a live application.
    if (DXFloatInteger(self.scene, @"contentState", 2) != 2) return;
    @try {
        id collection = DXFloatObject(self.layerManager, @"layers");
        NSArray *layers = [collection isKindOfClass:NSArray.class] ? collection : DXFloatObject(collection, @"array");
        if ([layers isKindOfClass:NSArray.class]) {
            if ([self.publishedLayers isEqualToArray:layers] && CGSizeEqualToSize(self.controller.canvasSize, [self canvasSize])) return;
            NSMutableArray<UIView *> *main = [NSMutableArray array], *external = [NSMutableArray array];
            for (id layer in layers) {
                BOOL keyboard = DXFloatInteger(layer, @"isKeyboardLayer", NO);
                BOOL isExternal = DXFloatObject(layer, @"externalSceneID") != nil;
                NSString *className = keyboard ? @"_UIKeyboardLayerHostView" : isExternal ? @"_UIExternalSceneLayerHostView" : @"_UIContextLayerHostView";
                NSString *method = keyboard ? @"initWithKeyboardLayer:owningScene:" : isExternal ? @"initWithSceneLayer:parentScene:" : @"initWithSceneLayer:";
                Class hostClass = NSClassFromString(className);
                SEL initializer = NSSelectorFromString(method);
                if (![hostClass isSubclassOfClass:UIView.class] || ![hostClass instancesRespondToSelector:initializer]) continue;
                UIView *view = (keyboard || isExternal)
                    ? ((id (*)(id, SEL, id, id))objc_msgSend)([hostClass alloc], initializer, layer, self.scene)
                    : ((id (*)(id, SEL, id))objc_msgSend)([hostClass alloc], initializer, layer);
                if (view) {
                    NSMutableArray *destination = (keyboard || isExternal) ? external : main;
                    [destination addObject:view];
                }
            }
            if (main.count) {
                [main addObjectsFromArray:external];
                [self.controller setHostViews:main canvasSize:[self canvasSize]];
                self.publishedLayers = [layers copy]; self.hasContent = YES;
                return;
            }
        }
        if (self.hasContent) return;
        id manager = self.fallbackHostManager ?: DXFloatObject(self.scene, @"hostManager");
        SEL enable = NSSelectorFromString(@"enableHostingForRequester:orderFront:");
        SEL get = NSSelectorFromString(@"hostViewForRequester:enableAndOrderFront:");
        if (![manager respondsToSelector:enable] || ![manager respondsToSelector:get]) return;
        if (!self.fallbackHostManager) ((void (*)(id, SEL, id, BOOL))objc_msgSend)(manager, enable, DXFloatRequester, YES);
        self.fallbackHostManager = manager;
        UIView *view = ((id (*)(id, SEL, id, BOOL))objc_msgSend)(manager, get, DXFloatRequester, YES);
        if ([view isKindOfClass:UIView.class] && DXFloatInteger(view, @"isHosting", YES)) {
            [self.controller setHostViews:@[view] canvasSize:[self canvasSize]]; self.hasContent = YES;
        }
    } @catch (NSException *exception) {
        NSLog(@"[TypeX][FloatingApp] layer publication exception=%@", exception.name);
    }
}
- (id)createDefaultSceneIfNeeded:(NSString *)identifier {
    // Only prepare a missing default scene. Never invalidate an existing app
    // scene or create a second app instance to obtain a floating presentation.
    id existing = DXFloatFindScene(identifier);
    if (existing) return existing;
    id manager = DXFloatObject(NSClassFromString(@"FBSceneManager"), @"sharedInstance");
    SEL create = NSSelectorFromString(@"createSceneWithDefinition:initialParameters:");
    if (![manager respondsToSelector:create]) return nil;
    @try {
        id definition = DXFloatObject(NSClassFromString(@"FBSMutableSceneDefinition"), @"definition");
        id identity = DXFloatObjectArgument(NSClassFromString(@"FBSSceneIdentity"), @"identityForIdentifier:", [NSString stringWithFormat:@"sceneID:%@-default", identifier]);
        id client = DXFloatObjectArgument(NSClassFromString(@"FBSSceneClientIdentity"), @"identityForBundleID:", identifier);
        id specification = DXFloatObject(NSClassFromString(@"UIApplicationSceneSpecification"), @"specification");
        id parameters = DXFloatObjectArgument(NSClassFromString(@"FBSMutableSceneParameters"), @"parametersForSpecification:", specification);
        Class settingsClass = NSClassFromString(@"UIMutableApplicationSceneSettings");
        if (!definition || !identity || !client || !specification || !parameters || !settingsClass) return nil;
        id settings = [settingsClass new];
        for (NSString *method in @[@"setIdentity:", @"setClientIdentity:", @"setSpecification:"])
            if (![definition respondsToSelector:NSSelectorFromString(method)]) return nil;
        if (![parameters respondsToSelector:NSSelectorFromString(@"setSettings:")] ||
            ![settings respondsToSelector:NSSelectorFromString(@"setFrame:")]) return nil;
        ((void (*)(id, SEL, id))objc_msgSend)(definition, NSSelectorFromString(@"setIdentity:"), identity);
        ((void (*)(id, SEL, id))objc_msgSend)(definition, NSSelectorFromString(@"setClientIdentity:"), client);
        ((void (*)(id, SEL, id))objc_msgSend)(definition, NSSelectorFromString(@"setSpecification:"), specification);
        id display = DXFloatObject(UIScreen.mainScreen, @"displayConfiguration");
        if (display && [settings respondsToSelector:NSSelectorFromString(@"setDisplayConfiguration:")])
            ((void (*)(id, SEL, id))objc_msgSend)(settings, NSSelectorFromString(@"setDisplayConfiguration:"), display);
        CGRect frame = (CGRect){CGPointZero, self.window.bounds.size};
        ((void (*)(id, SEL, CGRect))objc_msgSend)(settings, NSSelectorFromString(@"setFrame:"), frame);
        DXFloatForegroundSettings(settings, YES);
        DXFloatSetBool(settings, @"setDeviceOrientationEventsEnabled:", YES);
        UIInterfaceOrientation orientation = self.window.windowScene.interfaceOrientation;
        if (orientation == UIInterfaceOrientationUnknown) orientation = UIInterfaceOrientationPortrait;
        if ([settings respondsToSelector:NSSelectorFromString(@"setInterfaceOrientation:")])
            ((void (*)(id, SEL, NSInteger))objc_msgSend)(settings, NSSelectorFromString(@"setInterfaceOrientation:"), orientation);
        ((void (*)(id, SEL, id))objc_msgSend)(parameters, NSSelectorFromString(@"setSettings:"), settings);
        id clientSettings = [NSClassFromString(@"UIMutableApplicationSceneClientSettings") new];
        if ([clientSettings respondsToSelector:NSSelectorFromString(@"setInterfaceOrientation:")] &&
            [parameters respondsToSelector:NSSelectorFromString(@"setClientSettings:")]) {
            ((void (*)(id, SEL, NSInteger))objc_msgSend)(clientSettings, NSSelectorFromString(@"setInterfaceOrientation:"), orientation);
            ((void (*)(id, SEL, id))objc_msgSend)(parameters, NSSelectorFromString(@"setClientSettings:"), clientSettings);
        }
        NSLog(@"[TypeX][FloatingApp] prepare missing default scene bundleID=%@", identifier);
        return ((id (*)(id, SEL, id, id))objc_msgSend)(manager, create, definition, parameters);
    } @catch (__unused NSException *exception) { return nil; }
}
- (void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary *)change context:(void *)context {
    if (context != DXFloatLayerObservation) { [super observeValueForKeyPath:keyPath ofObject:object change:change context:context]; return; }
    NSUInteger generation = self.session.generation;
    dispatch_async(dispatch_get_main_queue(), ^{
        if (![self.session isCurrent:generation] || object != self.layerManager) return;
        [self publishLayers];
    });
}
- (void)poll:(NSUInteger)generation {
    if (![self.session isCurrent:generation]) return;
    if (![DXGlobalPanel deviceUnlocked]) { [self cleanup:DXSystemOpenUnavailable reason:@"locked"]; return; }
    if (self.session.hasExpired) { [self cleanup:DXSystemOpenTimedOut reason:@"content-timeout"]; return; }
    NSString *frontmost = DXFloatFrontmostIdentifier();
    if (![frontmost ?: @"" isEqual:self.baseIdentifier ?: @""]) {
        [self cleanup:DXSystemOpenUnavailable reason:@"native-takeover"]; return;
    }
    NSString *identifier = self.session.bundleIdentifier;
    pid_t pid = DXFloatPID(identifier);
    if (self.processPID > 0 && pid != self.processPID) { [self cleanup:DXSystemOpenUnavailable reason:@"process-ended"]; return; }
    if (!self.scene && pid > 0) {
        id scene = DXFloatFindScene(identifier);
        if (!scene && !self.sceneCreationAttempted && self.session.deadline.timeIntervalSinceNow < DXSystemOpenRequestTTL - 1.0) {
            self.sceneCreationAttempted = YES;
            scene = [self createDefaultSceneIfNeeded:identifier];
        }
        if (scene) {
            self.scene = scene; self.processPID = pid;
            self.originalSettings = DXFloatObject(DXFloatObject(scene, @"settings"), @"copy");
            self.activeLease = YES;
            id settings = DXFloatObject(scene, @"mutableSettings") ?: DXFloatObject(self.originalSettings, @"mutableCopy");
            @try {
                DXFloatForegroundSettings(settings, YES); DXFloatApplySettings(scene, settings);
            } @catch (__unused NSException *exception) { [self cleanup:DXSystemOpenFailed reason:@"scene-activation"]; return; }
            if (![self acquireAssertion]) { [self cleanup:DXSystemOpenUnavailable reason:@"assertion-unavailable"]; return; }
            self.layerManager = DXFloatObject(scene, @"layerManager");
            if (self.layerManager) {
                @try {
                    [self.layerManager addObserver:self forKeyPath:@"layers" options:NSKeyValueObservingOptionNew context:DXFloatLayerObservation];
                    self.observingLayers = YES;
                } @catch (__unused NSException *exception) {}
            }
            NSLog(@"[TypeX][FloatingApp] scene acquired bundleID=%@ pid=%d generation=%lu", identifier, pid, (unsigned long)generation);
        }
    }
    if (self.scene && !DXFloatInteger(self.scene, @"isValid", YES)) { [self cleanup:DXSystemOpenUnavailable reason:@"scene-invalid"]; return; }
    [self publishLayers];
    if (self.hasContent && self.urlAccepted && self.session.state == DXFloatingAppPreparing) {
        NSLog(@"[TypeX][FloatingApp] live bundleID=%@ generation=%lu", identifier, (unsigned long)generation);
        [self.session publishLive:generation];
    }
    __weak typeof(self) weakSelf = self;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.2 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{ [weakSelf poll:generation]; });
}
@end

static void (*DXFloatOriginalSceneUpdate3)(id, SEL, id, id, id);
static void (*DXFloatOriginalSceneUpdate2)(id, SEL, id, id);
static void DXFloatSceneUpdate3(id scene, SEL selector, id settings, id context, id completion) {
    settings = [DXFloatingAppCoordinator.shared protectedSettings:settings scene:scene];
    DXFloatOriginalSceneUpdate3(scene, selector, settings, context, completion);
}
static void DXFloatSceneUpdate2(id scene, SEL selector, id settings, id context) {
    settings = [DXFloatingAppCoordinator.shared protectedSettings:settings scene:scene];
    DXFloatOriginalSceneUpdate2(scene, selector, settings, context);
}

// FrontBoard can enter the trusted workspace path after the FBS request. Limit
// this correction to our marked URL request; ordinary app and URL launches are
// never captured or redirected by TypeX's floating host.
static void (*DXFloatOriginalTrustedOpen)(id, SEL, id, id, id, id, id);
static void DXFloatTrustedOpen(id workspace, SEL selector, id application, id options, id activation, id origin, id result) {
    DXFloatingAppCoordinator *host = DXFloatingAppCoordinator.shared;
    NSDictionary *dictionary = [options isKindOfClass:NSDictionary.class] ? options : DXFloatObject(options, @"dictionary");
    if (NSThread.isMainThread && host.session.state == DXFloatingAppPreparing && host.requestedURL &&
        [DXFloatIdentifier(application) isEqual:host.session.bundleIdentifier] &&
        [dictionary[@"__TypeXFloatingGeneration"] unsignedIntegerValue] == host.session.generation) {
        @try {
            SEL description = NSSelectorFromString(@"keyDescriptionForSetting:");
            NSUInteger suspended = NSNotFound;
            if ([activation respondsToSelector:description]) {
                for (NSUInteger setting = 0; setting < 128; setting++) {
                    id key = ((id (*)(id, SEL, NSUInteger))objc_msgSend)(activation, description, setting);
                    if ([key isKindOfClass:NSString.class] && [key.lowercaseString isEqual:@"suspended"]) { suspended = setting; break; }
                }
            }
            SEL set = NSSelectorFromString(@"setBool:forActivationSetting:");
            if (suspended != NSNotFound && [activation respondsToSelector:set])
                ((void (*)(id, SEL, BOOL, NSUInteger))objc_msgSend)(activation, set, YES, suspended);
        } @catch (__unused NSException *exception) {}
    }
    DXFloatOriginalTrustedOpen(workspace, selector, application, options, activation, origin, result);
}

void DXStartFloatingAppHost(void) {
    if (!NSThread.isMainThread || ![NSProcessInfo.processInfo.processName isEqual:@"SpringBoard"]) return;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        // Load only in SpringBoard; don't add a private runtime dependency to
        // every keyboard host or extension which receives TypeX.dylib.
        dlopen("/System/Library/PrivateFrameworks/RunningBoardServices.framework/RunningBoardServices", RTLD_LAZY);
        typedef void (*DXHookMessage)(Class, SEL, IMP, IMP *);
        DXHookMessage hook = (DXHookMessage)dlsym(RTLD_DEFAULT, "MSHookMessageEx");
        Class sceneClass = NSClassFromString(@"FBScene");
        SEL three = NSSelectorFromString(@"updateSettings:withTransitionContext:completion:");
        SEL two = NSSelectorFromString(@"updateSettings:withTransitionContext:");
        if (hook && class_getInstanceMethod(sceneClass, three)) hook(sceneClass, three, (IMP)DXFloatSceneUpdate3, (IMP *)&DXFloatOriginalSceneUpdate3);
        if (hook && class_getInstanceMethod(sceneClass, two)) hook(sceneClass, two, (IMP)DXFloatSceneUpdate2, (IMP *)&DXFloatOriginalSceneUpdate2);
        DXFloatHooksReady = DXFloatOriginalSceneUpdate3 || DXFloatOriginalSceneUpdate2;
        Class workspaceClass = NSClassFromString(@"SBMainWorkspace");
        SEL trusted = NSSelectorFromString(@"_handleTrustedOpenRequestForApplication:options:activationSettings:origin:withResult:");
        Method trustedMethod = class_getInstanceMethod(workspaceClass, trusted);
        if (hook && trustedMethod && method_getNumberOfArguments(trustedMethod) == 7)
            hook(workspaceClass, trusted, (IMP)DXFloatTrustedOpen, (IMP *)&DXFloatOriginalTrustedOpen);
        DXFloatingAppCoordinator *host = DXFloatingAppCoordinator.shared;
        NSMutableArray *tokens = [NSMutableArray array];
        for (NSString *name in @[@"com.apple.springboard.lockstate", @"com.apple.springboard.hasBlankedScreen", @"com.apple.springboard.frontmostapplicationchanged", kPrefsChangedIdentifier]) {
            int token = NOTIFY_TOKEN_INVALID;
            if (notify_register_dispatch(name.UTF8String, &token, dispatch_get_main_queue(), ^(__unused int notificationToken) {
                if (host.session.state == DXFloatingAppIdle) return;
                if ([name isEqual:kPrefsChangedIdentifier]) [host cleanup:DXSystemOpenUnavailable reason:@"preferences-changed"];
                else if ([name isEqual:@"com.apple.springboard.hasBlankedScreen"] || ![DXGlobalPanel deviceUnlocked])
                    [host cleanup:DXSystemOpenUnavailable reason:@"screen-locked"];
                else if ([name isEqual:@"com.apple.springboard.frontmostapplicationchanged"] &&
                    ![DXFloatFrontmostIdentifier() ?: @"" isEqual:host.baseIdentifier ?: @""])
                    [host cleanup:DXSystemOpenUnavailable reason:@"foreground-changed"];
            }) == NOTIFY_STATUS_OK) [tokens addObject:@(token)];
        }
        host.notifyTokens = tokens;
        NSLog(@"[TypeX][FloatingApp] host initialized sceneHooks=%d/%d", DXFloatOriginalSceneUpdate3 != NULL, DXFloatOriginalSceneUpdate2 != NULL);
    });
}

void DXPresentFloatingApplication(NSString *bundleIdentifier, NSURL *url, NSDate *deadline, DXSystemOpenReply reply) {
    if (!NSThread.isMainThread || ![NSProcessInfo.processInfo.processName isEqual:@"SpringBoard"]) { if (reply) reply(DXSystemOpenUnavailable); return; }
    DXStartFloatingAppHost();
    [DXFloatingAppCoordinator.shared open:bundleIdentifier url:url deadline:deadline reply:reply];
}
