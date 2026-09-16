#import "DXPAppInfo.h"
#import "../common.h"
#import <dlfcn.h>
#import <objc/message.h>

#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"

@interface LSApplicationProxy : NSObject
@property (nonatomic, readonly, copy) NSString *applicationIdentifier;
@property (nonatomic, readonly, copy) NSString *bundleIdentifier;
@property (nonatomic, readonly, copy) NSString *localizedName;
@end

@interface LSApplicationWorkspace : NSObject
+ (instancetype)defaultWorkspace;
- (NSArray *)allInstalledApplications;
// The per-type enumeration answered reliably inside the Settings process on
// iOS 14+ for reference tweaks; allInstalledApplications (below) has blocked
// indefinitely where Launch Services never came up (iOS 16).
- (void)enumerateApplicationsOfType:(NSUInteger)type block:(void (^)(LSApplicationProxy *proxy))block;
@end

@interface UIImage (TypeXAppIcon)
+ (UIImage *)_applicationIconImageForBundleIdentifier:(NSString *)bundleIdentifier format:(NSInteger)format;
@end

#pragma clang diagnostic pop

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
    [self ensureLaunchServicesLoaded];
    Class workspaceClass = NSClassFromString(@"LSApplicationWorkspace");
    if (!workspaceClass) {
        NSLog(@"[TypeX] shortcuts: LSApplicationWorkspace unavailable");
        return @[];
    }
    @try {
        id workspace = [workspaceClass performSelector:@selector(defaultWorkspace)];
        if (!workspace) {
            NSLog(@"[TypeX] shortcuts: default workspace unavailable");
            return @[];
        }

        // Primary: enumerateApplicationsOfType:block:, asked once for system
        // (0) and once for user (1) apps and merged — the same passes the
        // reference tweaks run inside Settings. The block is invoked
        // synchronously, so results are complete when the call returns.
        SEL enumerateSelector = @selector(enumerateApplicationsOfType:block:);
        if ([workspace respondsToSelector:enumerateSelector]) {
            Class proxyClass = [self appProxyClass];
            NSMutableArray *enumerated = [NSMutableArray array];
            BOOL threw = NO;
            @try {
                for (NSUInteger type = 0; type <= 1; type++) {
                    ((void (*)(id, SEL, NSUInteger, void (^)(LSApplicationProxy *)))objc_msgSend)(
                        workspace, enumerateSelector, type, ^(LSApplicationProxy *proxy) {
                            if (!proxyClass || [proxy isKindOfClass:proxyClass]) [enumerated addObject:proxy];
                        });
                }
            } @catch (NSException *exception) {
                NSLog(@"[TypeX] shortcuts: enumerateApplicationsOfType failed (%@)", exception);
                threw = YES;
            }
            if (!threw && enumerated.count > 0) {
                NSLog(@"[TypeX] shortcuts: enumerated %lu installed applications", (unsigned long)enumerated.count);
                return enumerated;
            }
        }

        // Fallback: the whole-array fetch, fast where Launch Services is
        // already warm (iOS 17 Settings).
        if (![workspace respondsToSelector:@selector(allInstalledApplications)]) {
            NSLog(@"[TypeX] shortcuts: default workspace cannot enumerate applications");
            return @[];
        }
        NSArray *proxies = [workspace performSelector:@selector(allInstalledApplications)];
        if (![proxies isKindOfClass:[NSArray class]]) return @[];
        NSLog(@"[TypeX] shortcuts: enumerated %lu installed applications", (unsigned long)proxies.count);
        return proxies;
    } @catch (NSException *exception) {
        NSLog(@"[TypeX] shortcuts: application enumeration failed (%@)", exception);
        return @[];
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
        NSString *name = [self localizedNameForProxy:proxy];
        if (bundleID.length == 0 || name.length == 0) continue;
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

// The whole catalogue is authored inside SpringBoard (see TypeX.xm): the
// catalogue refresh writes every installed app's system-resolved static and
// dynamic quick actions — the Home Screen menu's own data source, read via
// SBApplicationController — plus each app's localized display name, and real
// long-press captures overlay the same file. The Settings side only reads
// the shared plist: no Launch Services enumeration, bundle scanning or App
// Intents metadata parsing happens here at all, because the Settings process
// cannot do those reliably on every iOS version (iOS 16 blocked Launch
// Services enumeration indefinitely). Entries older than
// DXSBShortcutCaptureMaxAge are dropped.
+ (NSArray<NSDictionary *> *)appShortcutGroups {
    @try {
        NSDictionary *root = [NSDictionary dictionaryWithContentsOfFile:TypeXSBShortcutsPath];
        NSDictionary *apps = [root[@"apps"] isKindOfClass:[NSDictionary class]] ? root[@"apps"] : nil;
        if (apps.count == 0) return @[];

        NSTimeInterval cutoff = [NSDate timeIntervalSinceReferenceDate] - DXSBShortcutCaptureMaxAge;
        NSMutableArray<NSDictionary *> *groups = [NSMutableArray array];
        for (NSString *bundleID in apps) {
            if (![bundleID isKindOfClass:[NSString class]] || bundleID.length == 0) continue;
            NSDictionary *entry = [apps[bundleID] isKindOfClass:[NSDictionary class]] ? apps[bundleID] : nil;
            NSArray *rawItems = [entry[@"items"] isKindOfClass:[NSArray class]] ? entry[@"items"] : nil;
            double updated = [entry[@"updated"] isKindOfClass:[NSNumber class]] ? [entry[@"updated"] doubleValue] : 0;
            if (rawItems.count == 0 || updated < cutoff) continue;

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
                item.source = DXPAppShortcutSourceSpringBoard;
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
