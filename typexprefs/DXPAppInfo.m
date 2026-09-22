#import "DXPAppInfo.h"
#import "../common.h"
#import <dlfcn.h>
#import <objc/message.h>

#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"

@interface LSApplicationRecord : NSObject
@property (nonatomic, readonly) NSArray *appTags;
@property (getter=isLaunchProhibited, readonly) BOOL launchProhibited;
@end

@interface LSApplicationProxy : NSObject
@property (nonatomic, readonly, copy) NSString *applicationIdentifier;
@property (nonatomic, readonly, copy) NSString *bundleIdentifier;
@property (nonatomic, readonly, copy) NSString *localizedName;
@property (nonatomic, readonly, copy) NSString *applicationType;
@property (nonatomic, readonly) NSArray *appTags;
@property (nonatomic, readonly) NSURL *bundleURL;
@property (getter=isLaunchProhibited, nonatomic, readonly) BOOL launchProhibited;
- (LSApplicationRecord *)correspondingApplicationRecord;
@end

@interface LSApplicationWorkspace : NSObject
+ (instancetype)defaultWorkspace;
// The reference implementation performs these two synchronous passes. Avoid
// allInstalledApplications: it can block while LaunchServices is cold.
- (void)enumerateApplicationsOfType:(NSUInteger)type block:(void (^)(LSApplicationProxy *proxy))block;
@end

@interface UIImage (TypeXAppIcon)
+ (UIImage *)_applicationIconImageForBundleIdentifier:(NSString *)bundleIdentifier format:(NSInteger)format;
@end

#pragma clang diagnostic pop

// Visibility filter ported from PullOver-X QSFavoritesPickerController: an
// entry is hidden when any of the three appTags collections (proxy, its
// LaunchServices record, the bundle Info.plist SBAppTags) contains a "hidden"
// tag, when it is launch-prohibited, or when it is a com.apple.webapp web
// clip. Every probe is defensive — private-class behavior differences must
// never take down the enumeration.
static BOOL DXAppTagsContainHidden(NSArray *tags) {
    if (![tags isKindOfClass:[NSArray class]]) {
        return NO;
    }
    for (id tag in tags) {
        if ([tag isKindOfClass:[NSString class]] &&
            [(NSString *)tag rangeOfString:@"hidden" options:0].location != NSNotFound) {
            return YES;
        }
    }
    return NO;
}

static BOOL DXAppProxyIsHidden(LSApplicationProxy *proxy) {
    NSArray *appTags = nil;
    NSArray *recordAppTags = nil;
    NSArray *sbAppTags = nil;
    BOOL launchProhibited = NO;

    @try {
        if ([proxy respondsToSelector:@selector(correspondingApplicationRecord)]) {
            id record = [proxy correspondingApplicationRecord];
            if ([record respondsToSelector:@selector(appTags)]) recordAppTags = [record appTags];
            if ([record respondsToSelector:@selector(isLaunchProhibited)]) launchProhibited = [record isLaunchProhibited];
        }
        if ([proxy respondsToSelector:@selector(appTags)]) appTags = [proxy appTags];
        if (!launchProhibited && [proxy respondsToSelector:@selector(isLaunchProhibited)]) {
            launchProhibited = [proxy isLaunchProhibited];
        }

        NSURL *bundleURL = [proxy respondsToSelector:@selector(bundleURL)] ? proxy.bundleURL : nil;
        if (bundleURL && [bundleURL checkResourceIsReachableAndReturnError:nil]) {
            NSBundle *bundle = [NSBundle bundleWithURL:bundleURL];
            sbAppTags = [bundle objectForInfoDictionaryKey:@"SBAppTags"];
        }
    } @catch (NSException *exception) {
        (void)exception;
    }

    NSString *identifier = [proxy respondsToSelector:@selector(applicationIdentifier)]
        ? proxy.applicationIdentifier : nil;
    BOOL isWebApplication = [identifier rangeOfString:@"com.apple.webapp"
                                               options:NSCaseInsensitiveSearch].location != NSNotFound;

    return DXAppTagsContainHidden(appTags)
        || DXAppTagsContainHidden(recordAppTags)
        || DXAppTagsContainHidden(sbAppTags)
        || isWebApplication
        || launchProhibited;
}

@implementation DXPAppShortcutItem
@end

@implementation DXPAppInfo

+ (void)ensureLaunchServicesLoaded {
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        // Settings on iOS 17 normally has LaunchServices loaded already;
        // iOS 16 does not. Keep both framework locations for compatibility.
        for (NSString *path in @[
            @"/System/Library/Frameworks/MobileCoreServices.framework/MobileCoreServices",
            @"/System/Library/Frameworks/CoreServices.framework/CoreServices",
        ]) {
            if (dlopen(path.fileSystemRepresentation, RTLD_LAZY | RTLD_LOCAL)) break;
        }
    });
}

+ (Class)appProxyClass {
    [self ensureLaunchServicesLoaded];
    return NSClassFromString(@"LSApplicationProxy");
}

+ (NSArray<LSApplicationProxy *> *)installedAppProxies {
    NSMutableArray *enumerated = [NSMutableArray array];
    BOOL completed = [self enumerateInstalledProxies:^(LSApplicationProxy *proxy, BOOL userApp) {
        (void)userApp;
        [enumerated addObject:proxy];
    }];
    if (completed && enumerated.count > 0) {
        NSLog(@"[TypeX] shortcuts: enumerated %lu installed applications", (unsigned long)enumerated.count);
        return enumerated;
    }

    NSLog(@"[TypeX] shortcuts: typed application enumeration returned no applications");
    return @[];
}

// The two synchronous typed passes (0 = System, 1 = User) shared by the
// synchronous and picker enumeration paths. Avoid allInstalledApplications:
// it can block while LaunchServices is cold. The block runs synchronously,
// so results are complete when the call returns; NO means LaunchServices
// enumeration was unavailable or threw.
+ (BOOL)enumerateInstalledProxies:(void (^)(LSApplicationProxy *proxy, BOOL userApp))block {
    [self ensureLaunchServicesLoaded];
    Class workspaceClass = NSClassFromString(@"LSApplicationWorkspace");
    if (!workspaceClass) {
        NSLog(@"[TypeX] shortcuts: LSApplicationWorkspace unavailable");
        return NO;
    }
    @try {
        id workspace = [workspaceClass performSelector:@selector(defaultWorkspace)];
        if (!workspace) {
            NSLog(@"[TypeX] shortcuts: default workspace unavailable");
            return NO;
        }

        SEL enumerateSelector = @selector(enumerateApplicationsOfType:block:);
        if (![workspace respondsToSelector:enumerateSelector]) {
            NSLog(@"[TypeX] shortcuts: typed enumeration unavailable");
            return NO;
        }
        Class proxyClass = [self appProxyClass];
        for (NSUInteger type = 0; type <= 1; type++) {
            BOOL userApp = (type == 1);
            ((void (*)(id, SEL, NSUInteger, void (^)(LSApplicationProxy *)))objc_msgSend)(
                workspace, enumerateSelector, type, ^(LSApplicationProxy *proxy) {
                    if (!proxyClass || [proxy isKindOfClass:proxyClass]) block(proxy, userApp);
                });
        }
        return YES;
    } @catch (NSException *exception) {
        NSLog(@"[TypeX] shortcuts: application enumeration failed (%@)", exception);
        return NO;
    }
}

+ (NSString *)bundleIDForProxy:(LSApplicationProxy *)proxy {
    NSString *bundleID = nil;
    @try {
        if ([proxy respondsToSelector:@selector(applicationIdentifier)]) {
            bundleID = proxy.applicationIdentifier;
        }
        if (![bundleID isKindOfClass:[NSString class]] || bundleID.length == 0) {
            bundleID = [proxy respondsToSelector:@selector(bundleIdentifier)] ? proxy.bundleIdentifier : nil;
        }
    } @catch (__unused NSException *exception) {
        bundleID = nil;
    }
    if ([bundleID isKindOfClass:[NSString class]] && bundleID.length > 0) return bundleID;
    return nil;
}

+ (NSString *)localizedNameForProxy:(LSApplicationProxy *)proxy {
    NSString *name = nil;
    @try {
        if ([proxy respondsToSelector:@selector(localizedName)]) {
            name = proxy.localizedName;
        }
    } @catch (__unused NSException *exception) {
        name = nil;
    }
    return [name isKindOfClass:[NSString class]] && name.length > 0 ? name : nil;
}

+ (NSArray<DXPAppInfo *> *)installedApps {
    NSMutableArray<DXPAppInfo *> *apps = [NSMutableArray array];
    NSMutableSet<NSString *> *seen = [NSMutableSet set];
    Class proxyClass = [self appProxyClass];
    for (LSApplicationProxy *proxy in [self installedAppProxies]) {
        if (proxyClass && ![proxy isKindOfClass:proxyClass]) continue;
        if (![proxy respondsToSelector:@selector(applicationIdentifier)] &&
            ![proxy respondsToSelector:@selector(bundleIdentifier)]) continue;
        NSString *bundleID = [self bundleIDForProxy:proxy];
        NSString *name = [self localizedNameForProxy:proxy] ?: bundleID;
        if (bundleID.length == 0) continue;
        if ([seen containsObject:bundleID]) continue;
        [seen addObject:bundleID];

        DXPAppInfo *app = [[DXPAppInfo alloc] init];
        app.bundleID = bundleID;
        app.name = name;
        [apps addObject:app];
    }
    [apps sortUsingComparator:^NSComparisonResult(DXPAppInfo *left, DXPAppInfo *right) {
        return [left.name localizedStandardCompare:right.name];
    }];
    return apps;
}

+ (void)installedAppsWithCompletion:(void (^)(NSArray<DXPAppInfo *> *apps))completion {
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        Class proxyClass = [self appProxyClass];
        NSMutableArray<DXPAppInfo *> *userApps = [NSMutableArray array];
        NSMutableArray<DXPAppInfo *> *systemApps = [NSMutableArray array];
        NSMutableSet<NSString *> *seen = [NSMutableSet set];

        [self enumerateInstalledProxies:^(LSApplicationProxy *proxy, BOOL userApp) {
            if (proxyClass && ![proxy isKindOfClass:proxyClass]) return;
            NSString *bundleID = [self bundleIDForProxy:proxy];
            if (bundleID.length == 0 || [seen containsObject:bundleID]) return;
            if (DXAppProxyIsHidden(proxy)) return;
            [seen addObject:bundleID];

            DXPAppInfo *app = [[DXPAppInfo alloc] init];
            app.bundleID = bundleID;
            app.name = [self localizedNameForProxy:proxy] ?: bundleID;
            app.userApp = userApp;
            [(userApp ? userApps : systemApps) addObject:app];
        }];

        [userApps sortUsingComparator:^NSComparisonResult(DXPAppInfo *left, DXPAppInfo *right) {
            return [left.name localizedStandardCompare:right.name];
        }];
        [systemApps sortUsingComparator:^NSComparisonResult(DXPAppInfo *left, DXPAppInfo *right) {
            return [left.name localizedStandardCompare:right.name];
        }];
        NSMutableArray<DXPAppInfo *> *apps = [NSMutableArray arrayWithArray:userApps];
        [apps addObjectsFromArray:systemApps];

        dispatch_async(dispatch_get_main_queue(), ^{
            if (completion) completion([apps copy]);
        });
    });
}

// SpringBoard replaces the entire format-3 snapshot after reading each
// SBApplication's current dynamic and static items. Settings only decodes the
// stable display fields; execution resolves the original item again.
+ (NSArray<NSDictionary *> *)appShortcutGroups {
    @try {
        NSDictionary *root = DXQuickActionSharedValue(TypeXQuickActionSnapshotKey);
        if (![root[@"format"] isKindOfClass:[NSNumber class]] || [root[@"format"] integerValue] != 3) {
            return @[];
        }
        NSDictionary *apps = [root[@"apps"] isKindOfClass:[NSDictionary class]] ? root[@"apps"] : nil;
        if (apps.count == 0) return @[];

        NSMutableArray<NSDictionary *> *groups = [NSMutableArray array];
        for (NSString *bundleID in apps) {
            if (![bundleID isKindOfClass:[NSString class]] || bundleID.length == 0) continue;
            NSDictionary *entry = [apps[bundleID] isKindOfClass:[NSDictionary class]] ? apps[bundleID] : nil;
            NSArray *rawItems = [entry[@"items"] isKindOfClass:[NSArray class]] ? entry[@"items"] : nil;
            if (rawItems.count == 0) continue;

            NSMutableArray<DXPAppShortcutItem *> *items = [NSMutableArray array];
            NSMutableSet<NSString *> *seenTypes = [NSMutableSet set];
            for (NSDictionary *raw in rawItems) {
                if (![raw isKindOfClass:[NSDictionary class]]) continue;
                NSString *type = [raw[@"type"] isKindOfClass:[NSString class]] ? raw[@"type"] : nil;
                if (type.length == 0 || [seenTypes containsObject:type]) continue;
                [seenTypes addObject:type];

                DXPAppShortcutItem *item = [[DXPAppShortcutItem alloc] init];
                item.type = type;
                item.title = [raw[@"title"] isKindOfClass:[NSString class]] ? raw[@"title"] : type;
                item.subtitle = [raw[@"subtitle"] isKindOfClass:[NSString class]] ? raw[@"subtitle"] : nil;
                NSString *source = [raw[@"source"] isKindOfClass:[NSString class]] ? raw[@"source"] : nil;
                item.source = [source isEqualToString:@"dynamic"]
                    ? DXPAppShortcutSourceDynamic : DXPAppShortcutSourceStatic;
                [items addObject:item];
            }
            if (items.count == 0) continue;

            NSString *entryName = [entry[@"name"] isKindOfClass:[NSString class]] ? entry[@"name"] : nil;
            NSString *name = entryName.length > 0 ? entryName : bundleID;
            [groups addObject:@{@"name": name, @"bundleID": bundleID, @"items": items}];
        }
        [groups sortUsingComparator:^NSComparisonResult(NSDictionary *left, NSDictionary *right) {
            return [left[@"name"] localizedStandardCompare:right[@"name"]];
        }];
        NSLog(@"[TypeX] shortcuts: %ld groups from the shared catalogue", (long)groups.count);
        return groups;
    } @catch (NSException *exception) {
        NSLog(@"[TypeX] shortcuts: shared catalogue unreadable (%@)", exception);
        return @[];
    }
}

+ (UIImage *)iconForBundleID:(NSString *)bundleID {
    static NSCache *cache;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        cache = [[NSCache alloc] init];
        cache.countLimit = 512;
    });
    if (bundleID.length == 0) return [UIImage systemImageNamed:@"app"];
    UIImage *cached = [cache objectForKey:bundleID];
    if (cached) return cached;

    CGFloat side = 44;
    UIImage *base = nil;
    if ([UIImage respondsToSelector:@selector(_applicationIconImageForBundleIdentifier:format:)]) {
        base = [UIImage _applicationIconImageForBundleIdentifier:bundleID format:2];
        if (!base) base = [UIImage _applicationIconImageForBundleIdentifier:bundleID format:0];
    }

    UIImage *icon;
    if (base) {
        UIGraphicsImageRendererFormat *format = [[UIGraphicsImageRendererFormat alloc] init];
        format.scale = [UIScreen mainScreen].scale;
        format.opaque = NO;
        UIGraphicsImageRenderer *renderer = [[UIGraphicsImageRenderer alloc] initWithSize:CGSizeMake(side, side) format:format];
        icon = [renderer imageWithActions:^(UIGraphicsImageRendererContext *rendererContext) {
            // Home-screen icons are square; round them like SpringBoard does.
            [[UIBezierPath bezierPathWithRoundedRect:CGRectMake(0, 0, side, side)
                                        cornerRadius:side * 0.225] addClip];
            [base drawInRect:CGRectMake(0, 0, side, side)];
        }];
    } else {
        icon = [UIImage systemImageNamed:@"app"];
    }
    if (icon) [cache setObject:icon forKey:bundleID];
    return icon;
}

@end
