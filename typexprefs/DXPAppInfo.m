#import "DXPAppInfo.h"

#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"

@interface LSApplicationProxy : NSObject
@property (nonatomic, readonly, copy) NSString *applicationIdentifier;
@property (nonatomic, readonly, copy) NSString *bundleIdentifier;
@property (nonatomic, readonly, copy) NSString *localizedName;
@property (nonatomic, readonly, strong) NSURL *bundleURL;
@property (nonatomic, readonly, copy) NSDictionary *infoDictionary;
@end

@interface LSApplicationWorkspace : NSObject
+ (instancetype)defaultWorkspace;
- (NSArray *)allInstalledApplications;
@end

@interface UIImage (TypeXAppIcon)
+ (UIImage *)_applicationIconImageForBundleIdentifier:(NSString *)bundleIdentifier format:(NSInteger)format;
@end

#pragma clang diagnostic pop

@implementation DXPAppShortcutItem
@end

@implementation DXPAppInfo

// MobileCoreServices is not linked into this bundle, so the class must be
// resolved at runtime instead of being referenced directly.
+ (Class)appProxyClass {
    return NSClassFromString(@"LSApplicationProxy");
}

+ (NSArray<LSApplicationProxy *> *)installedAppProxies {
    Class workspaceClass = NSClassFromString(@"LSApplicationWorkspace");
    if (!workspaceClass) return @[];
    id workspace = [workspaceClass performSelector:@selector(defaultWorkspace)];
    if (!workspace || ![workspace respondsToSelector:@selector(allInstalledApplications)]) return @[];
    NSArray *proxies = [workspace performSelector:@selector(allInstalledApplications)];
    return proxies ?: @[];
}

+ (NSString *)bundleIDForProxy:(LSApplicationProxy *)proxy {
    for (NSString *bundleID in @[proxy.applicationIdentifier, proxy.bundleIdentifier]) {
        if ([bundleID isKindOfClass:[NSString class]] && bundleID.length > 0) return bundleID;
    }
    return nil;
}

+ (NSArray<DXPAppInfo *> *)installedApps {
    NSMutableArray<DXPAppInfo *> *apps = [NSMutableArray array];
    NSMutableSet<NSString *> *seen = [NSMutableSet set];
    for (LSApplicationProxy *proxy in [self installedAppProxies]) {
        if (![proxy isKindOfClass:[self appProxyClass]]) continue;
        NSString *bundleID = [self bundleIDForProxy:proxy];
        NSString *name = proxy.localizedName;
        if (bundleID.length == 0 || ![name isKindOfClass:[NSString class]] || name.length == 0) continue;
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

// Number of app proxies seen by the most recent -appShortcutGroups scan;
// surfaced in the picker's empty state so a total failure (enumeration broke,
// no plist readable) is visible without a syslog capture.
static NSInteger DXLastShortcutScanApplicationCount = 0;
+ (NSInteger)lastShortcutScanApplicationCount {
    return DXLastShortcutScanApplicationCount;
}

// Reads an app's Info.plist dictionary. NSBundle first — the path AltList
// proved on device — then the proxy's own infoDictionary, then a raw file
// read of <bundleURL>/Info.plist. Returns nil only when none resolve.
+ (NSDictionary *)infoDictionaryForProxy:(LSApplicationProxy *)proxy {
    NSURL *bundleURL = proxy.bundleURL;
    if (!bundleURL) return nil;

    NSBundle *bundle = [NSBundle bundleWithURL:bundleURL];
    NSDictionary *info = bundle.infoDictionary;
    if (info.count > 0) return info;

    if ([proxy respondsToSelector:@selector(infoDictionary)]) info = proxy.infoDictionary;
    if (info.count > 0) return info;

    return [NSDictionary dictionaryWithContentsOfURL:[bundleURL URLByAppendingPathComponent:@"Info.plist"]];
}

// Extracts one app's static quick actions into a group dictionary, or nil
// when the app declares none. Static item titles are keys into the app's
// InfoPlist.strings, resolved here so the list shows real menu labels; the
// item's type is kept verbatim because bundleID + type is the payload the
// system actually dispatches for these entries.
+ (NSDictionary *)shortcutGroupForProxy:(LSApplicationProxy *)proxy
                               bundleID:(NSString *)bundleID
                                   name:(NSString *)name {
    NSDictionary *info = [self infoDictionaryForProxy:proxy];
    if (info.count == 0) {
        NSLog(@"[TypeX] shortcuts: no Info.plist readable for %@", bundleID);
        return nil;
    }
    NSArray *items = info[@"UIApplicationShortcutItems"];
    if (![items isKindOfClass:[NSArray class]]) return nil;

    NSURL *bundleURL = proxy.bundleURL;
    NSBundle *stringsBundle = bundleURL ? [NSBundle bundleWithURL:bundleURL] : nil;
    NSMutableArray<DXPAppShortcutItem *> *results = [NSMutableArray array];
    NSMutableSet<NSString *> *seen = [NSMutableSet set];
    for (NSDictionary *item in items) {
        if (![item isKindOfClass:[NSDictionary class]]) continue;
        NSString *type = [item[@"UIApplicationShortcutItemType"] isKindOfClass:[NSString class]] ? item[@"UIApplicationShortcutItemType"] : nil;
        NSString *titleKey = [item[@"UIApplicationShortcutItemTitle"] isKindOfClass:[NSString class]] ? item[@"UIApplicationShortcutItemTitle"] : nil;
        if (type.length == 0 && titleKey.length == 0) continue;
        if (type.length == 0) type = titleKey;

        NSString *title = nil;
        if (titleKey.length > 0 && stringsBundle) {
            title = [stringsBundle localizedStringForKey:titleKey value:titleKey table:@"InfoPlist"];
        }

        DXPAppShortcutItem *entry = [[DXPAppShortcutItem alloc] init];
        entry.type = type;
        entry.title = title.length > 0 ? title : (titleKey.length > 0 ? titleKey : type);

        NSString *subtitleKey = [item[@"UIApplicationShortcutItemSubtitle"] isKindOfClass:[NSString class]] ? item[@"UIApplicationShortcutItemSubtitle"] : nil;
        if (subtitleKey.length > 0 && stringsBundle) {
            NSString *subtitle = [stringsBundle localizedStringForKey:subtitleKey value:subtitleKey table:@"InfoPlist"];
            entry.subtitle = subtitle.length > 0 ? subtitle : subtitleKey;
        }

        NSString *fingerprint = [NSString stringWithFormat:@"%@|%@|%@", type, titleKey ?: @"", subtitleKey ?: @""];
        if ([seen containsObject:fingerprint]) continue;
        [seen addObject:fingerprint];
        [results addObject:entry];
    }
    if (results.count == 0) return nil;
    return @{@"name": name, @"bundleID": bundleID, @"items": [results copy]};
}

+ (NSArray<NSDictionary *> *)appShortcutGroups {
    @try {
        NSMutableArray<NSDictionary *> *groups = [NSMutableArray array];
        NSMutableSet<NSString *> *seen = [NSMutableSet set];
        NSInteger scanned = 0, readable = 0;
        for (LSApplicationProxy *proxy in [self installedAppProxies]) {
            if (![proxy isKindOfClass:[self appProxyClass]]) continue;
            NSString *bundleID = [self bundleIDForProxy:proxy];
            NSString *name = proxy.localizedName;
            if (bundleID.length == 0 || ![name isKindOfClass:[NSString class]] || name.length == 0) continue;
            if ([seen containsObject:bundleID]) continue;
            [seen addObject:bundleID];
            scanned++;

            // Reading another app's metadata goes through private lookup and
            // bundle localization; an exception there must only skip that app
            // instead of crashing Settings when the page is opened.
            NSDictionary *group = nil;
            @try {
                group = [self shortcutGroupForProxy:proxy bundleID:bundleID name:name];
            } @catch (NSException *exception) {
                NSLog(@"[TypeX] shortcuts: skipped %@ (%@)", bundleID, exception);
                group = nil;
            }
            if (group) {
                readable++;
                [groups addObject:group];
            }
        }
        DXLastShortcutScanApplicationCount = scanned;
        NSLog(@"[TypeX] shortcuts scan: %ld apps, %ld with static quick actions",
              (long)scanned, (long)readable);
        [groups sortUsingComparator:^NSComparisonResult(NSDictionary *left, NSDictionary *right) {
            return [left[@"name"] localizedStandardCompare:right[@"name"]];
        }];
        return groups;
    } @catch (NSException *exception) {
        NSLog(@"[TypeX] shortcuts scan failed: %@", exception);
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
