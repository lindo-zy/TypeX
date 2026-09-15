#import "DXPAppInfo.h"
#import "../common.h"

#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"

@interface LSApplicationProxy : NSObject
@property (nonatomic, readonly, copy) NSString *applicationIdentifier;
@property (nonatomic, readonly, copy) NSString *bundleIdentifier;
@property (nonatomic, readonly, copy) NSString *localizedName;
@property (nonatomic, readonly, strong) NSURL *bundleURL;
@property (nonatomic, readonly, strong) NSURL *dataContainerURL;
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

// Extracts one app's static quick actions — the UIApplicationShortcutItems
// array declared in its Info.plist. Static titles are keys into the app's
// InfoPlist.strings, resolved here so the list shows real menu labels.
+ (NSArray<DXPAppShortcutItem *> *)staticShortcutItemsForProxy:(LSApplicationProxy *)proxy {
    NSDictionary *info = [self infoDictionaryForProxy:proxy];
    if (info.count == 0) {
        NSLog(@"[TypeX] shortcuts: no Info.plist readable for %@", proxy.bundleIdentifier ?: @"");
        return @[];
    }
    NSArray *items = info[@"UIApplicationShortcutItems"];
    if (![items isKindOfClass:[NSArray class]]) return @[];

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

        NSString *subtitleKey = [item[@"UIApplicationShortcutItemSubtitle"] isKindOfClass:[NSString class]] ? item[@"UIApplicationShortcutItemSubtitle"] : nil;
        NSString *subtitle = nil;
        if (subtitleKey.length > 0 && stringsBundle) {
            subtitle = [stringsBundle localizedStringForKey:subtitleKey value:subtitleKey table:@"InfoPlist"];
            if (subtitle.length == 0) subtitle = subtitleKey;
        }

        DXPAppShortcutItem *entry = [[DXPAppShortcutItem alloc] init];
        entry.type = type;
        entry.title = title.length > 0 ? title : (titleKey.length > 0 ? titleKey : type);
        entry.subtitle = subtitle;
        entry.source = DXPAppShortcutSourceStatic;

        NSString *fingerprint = [NSString stringWithFormat:@"%@|%@|%@", type, titleKey ?: @"", subtitleKey ?: @""];
        if ([seen containsObject:fingerprint]) continue;
        [seen addObject:fingerprint];
        [results addObject:entry];
    }
    return results;
}

// Decodes archived UIApplicationShortcutItem payloads, should UIKit persist
// encoded objects instead of plain dictionaries. Secure decoding validates the
// whole object graph, so the class set must also cover the plist-safe types an
// item's userInfo can contain. Returns nil on any mismatch.
+ (id)decodedShortcutItemsFromData:(NSData *)data {
    NSSet *classes = [NSSet setWithArray:@[
        [NSArray class], [NSDictionary class], [NSString class], [NSNumber class],
        [NSURL class], [NSData class], [NSDate class], [UIApplicationShortcutItem class],
    ]];
    return [NSKeyedUnarchiver unarchivedObjectOfClasses:classes fromData:data error:nil];
}

// Extracts one app's dynamic quick actions. When the app calls setShortcutItems:,
// UIKit persists them under the same UIApplicationShortcutItems key in the app's
// own data-container preferences, which a mobile-uid process (Settings) can read
// across containers on a jailbroken device. Dynamic items carry real localized
// strings, so no InfoPlist lookup applies.
+ (NSArray<DXPAppShortcutItem *> *)dynamicShortcutItemsForProxy:(LSApplicationProxy *)proxy
                                                       bundleID:(NSString *)bundleID {
    if (![proxy respondsToSelector:@selector(dataContainerURL)]) return @[];
    NSURL *containerURL = proxy.dataContainerURL;
    if (![containerURL isKindOfClass:[NSURL class]]) return @[];

    NSString *prefsPath = [[containerURL URLByAppendingPathComponent:@"Library/Preferences"]
        URLByAppendingPathComponent:[NSString stringWithFormat:@"%@.plist", bundleID]].path;
    NSDictionary *prefs = [NSDictionary dictionaryWithContentsOfFile:prefsPath];
    if (![prefs isKindOfClass:[NSDictionary class]]) return @[];
    id payload = prefs[@"UIApplicationShortcutItems"];
    if (!payload) return @[];

    // Accept the payload in every shape UIKit has used: a plain array of
    // dictionaries, a single encoded blob, or an array mixing both. Anything
    // undecodable is dropped rather than failing the whole app.
    void (^collect)(id, NSMutableArray *) = ^(id entry, NSMutableArray *outItems) {
        if ([entry isKindOfClass:[NSDictionary class]] ||
            [entry isKindOfClass:[UIApplicationShortcutItem class]]) [outItems addObject:entry];
    };
    NSMutableArray *entries = [NSMutableArray array];
    if ([payload isKindOfClass:[NSArray class]]) {
        for (id entry in payload) {
            if ([entry isKindOfClass:[NSData class]]) {
                id decoded = [self decodedShortcutItemsFromData:entry];
                if ([decoded isKindOfClass:[NSArray class]]) for (id sub in decoded) collect(sub, entries);
                else collect(decoded, entries);
            } else {
                collect(entry, entries);
            }
        }
    } else if ([payload isKindOfClass:[NSData class]]) {
        id decoded = [self decodedShortcutItemsFromData:payload];
        if ([decoded isKindOfClass:[NSArray class]]) for (id sub in decoded) collect(sub, entries);
        else collect(decoded, entries);
    }
    if (entries.count == 0) return @[];

    NSMutableArray<DXPAppShortcutItem *> *results = [NSMutableArray array];
    NSMutableSet<NSString *> *seen = [NSMutableSet set];
    for (id item in entries) {
        NSString *type = nil, *title = nil, *subtitle = nil;
        if ([item isKindOfClass:[NSDictionary class]]) {
            NSDictionary *entry = item;
            type = [entry[@"UIApplicationShortcutItemType"] isKindOfClass:[NSString class]] ? entry[@"UIApplicationShortcutItemType"] : nil;
            title = [entry[@"UIApplicationShortcutItemTitle"] isKindOfClass:[NSString class]] ? entry[@"UIApplicationShortcutItemTitle"] : nil;
            subtitle = [entry[@"UIApplicationShortcutItemSubtitle"] isKindOfClass:[NSString class]] ? entry[@"UIApplicationShortcutItemSubtitle"] : nil;
        } else {
            UIApplicationShortcutItem *entry = item;
            type = entry.type;
            title = entry.localizedTitle;
            subtitle = entry.localizedSubtitle;
        }
        if (type.length == 0) continue;
        if ([seen containsObject:type]) continue;
        [seen addObject:type];

        DXPAppShortcutItem *result = [[DXPAppShortcutItem alloc] init];
        result.type = type;
        result.title = title.length > 0 ? title : type;
        result.subtitle = subtitle;
        result.source = DXPAppShortcutSourceDynamic;
        [results addObject:result];
    }
    return results;
}

// App Shortcuts (iOS 16+) live in the bundle as build-time metadata:
// appintentsmetadataprocessor compiles the AppShortcutsProvider into
// <bundle>/Metadata.appintents/extract.actionsdata, whose autoShortcuts array
// is exactly what fills the icon context menu, Spotlight and the Shortcuts
// app. Titles in that file are localization keys; on iOS 15/16 NSBundle does
// not resolve .loctable resources, so they are looked up manually too.
// Extensions (PlugIns/*.appex) can declare their own shortcuts (e.g. Weather);
// the system shows those under the parent app, so they are folded in here.
+ (NSArray<NSDictionary *> *)readableLoctablesForBundle:(NSBundle *)bundle {
    NSMutableArray<NSDictionary *> *tables = [NSMutableArray array];
    if (!bundle) return tables;
    for (NSURL *url in [bundle URLsForResourcesWithExtension:@"loctable" subdirectory:nil]) {
        NSDictionary *table = [NSDictionary dictionaryWithContentsOfURL:url];
        if (![table isKindOfClass:[NSDictionary class]]) continue;
        for (NSString *key in table) {
            if ([table[key] isKindOfClass:[NSDictionary class]]) {
                [tables addObject:table];
                break;
            }
        }
    }
    return tables;
}

// Picks the loctable locale ("zh_CN", "en", "pt_BR") closest to the device's
// preferred languages ("zh-Hans-CN", "zh-Hans", "zh"). Apple loctables tag
// regions rather than scripts, so Chinese scripts fold onto CN/TW.
+ (NSString *)bestLocaleForTable:(NSDictionary *)table {
    if (table.count == 0) return nil;
    NSMutableDictionary *byLowercase = [NSMutableDictionary dictionary];
    for (NSString *key in table) byLowercase[key.lowercaseString] = key;

    for (NSString *language in [NSLocale preferredLanguages]) {
        NSArray *parts = [[language stringByReplacingOccurrencesOfString:@"-" withString:@"_"]
            componentsSeparatedByString:@"_"];
        if (parts.count == 0) continue;
        NSString *base = ((NSString *)parts[0]).lowercaseString;

        NSMutableArray *candidates = [NSMutableArray array];
        if (parts.count >= 3) {
            NSString *script = ((NSString *)parts[1]).lowercaseString;
            NSString *region = [script isEqualToString:@"hans"] ? @"cn" : ([script isEqualToString:@"hant"] ? @"tw" : nil);
            if (region) [candidates addObject:[NSString stringWithFormat:@"%@_%@", base, region]];
        }
        if (parts.count >= 2) [candidates addObject:[NSString stringWithFormat:@"%@_%@", base, ((NSString *)parts[1]).lowercaseString]];
        [candidates addObject:base];

        for (NSString *candidate in candidates) {
            NSString *match = byLowercase[candidate];
            if (match) return match;
        }
    }
    return byLowercase[@"en"] ?: byLowercase[@"en_us"];
}

+ (NSString *)localizedAppIntentTitleForKey:(NSString *)key
                                   inBundle:(NSBundle *)bundle
                                  loctables:(NSArray<NSDictionary *> *)loctables {
    if (key.length == 0) return nil;
    for (id tableRef in @[[NSNull null], @"AppIntents", @"Localizable"]) {
        NSString *value = [bundle localizedStringForKey:key value:nil
                                                  table:[tableRef isKindOfClass:[NSString class]] ? tableRef : nil];
        if ([value isKindOfClass:[NSString class]] && value.length > 0 && ![value isEqualToString:key]) return value;
    }
    for (NSDictionary *table in loctables) {
        NSString *locale = [self bestLocaleForTable:table];
        if (!locale) continue;
        NSString *value = table[locale][key];
        if ([value isKindOfClass:[NSString class]] && value.length > 0) return value;
    }
    return key;
}

+ (NSArray<DXPAppShortcutItem *> *)appIntentShortcutItemsForProxy:(LSApplicationProxy *)proxy {
    NSURL *appURL = proxy.bundleURL;
    if (![appURL isKindOfClass:[NSURL class]]) return @[];

    // Metadata.appintents exists wherever the AppShortcutsProvider is
    // compiled, not only in the app root: extensions (PlugIns/*.appex, e.g.
    // Weather) AND embedded frameworks (Frameworks/*.framework — Photos'
    // menu items live in PhotosUICore.framework, not the app bundle root).
    // The icon long-press menu merges them all, so every container is read.
    NSMutableArray<NSURL *> *bundleURLs = [NSMutableArray arrayWithObject:appURL];
    NSFileManager *fileManager = [NSFileManager defaultManager];
    for (NSString *subdirectory in @[@"PlugIns", @"Frameworks"]) {
        NSURL *directoryURL = [appURL URLByAppendingPathComponent:subdirectory];
        for (NSURL *childURL in [fileManager contentsOfDirectoryAtURL:directoryURL
                                               includingPropertiesForKeys:nil
                                                                  options:NSDirectoryEnumerationSkipsHiddenFiles
                                                                    error:nil]) {
            NSString *extension = childURL.pathExtension.lowercaseString;
            if ([extension isEqualToString:@"appex"] || [extension isEqualToString:@"framework"] ||
                [extension isEqualToString:@"bundle"]) {
                [bundleURLs addObject:childURL];
            }
        }
    }

    NSMutableArray<DXPAppShortcutItem *> *results = [NSMutableArray array];
    NSMutableSet<NSString *> *seen = [NSMutableSet set];
    for (NSURL *containerURL in bundleURLs) {
        NSURL *actionsURL = [[containerURL URLByAppendingPathComponent:@"Metadata.appintents"]
            URLByAppendingPathComponent:@"extract.actionsdata"];
        NSData *data = [NSData dataWithContentsOfFile:actionsURL.path];
        if (!data) continue;
        id document = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
        if (![document isKindOfClass:[NSDictionary class]]) continue;
        id shortcuts = document[@"autoShortcuts"];
        if (![shortcuts isKindOfClass:[NSArray class]]) shortcuts = document[@"appShortcuts"];
        if (![shortcuts isKindOfClass:[NSArray class]]) {
            NSLog(@"[TypeX] shortcuts: Metadata.appintents without shortcuts array in %@", containerURL.path ?: @"");
            continue;
        }

        NSBundle *bundle = [NSBundle bundleWithURL:containerURL];
        NSArray<NSDictionary *> *loctables = [self readableLoctablesForBundle:bundle];
        for (NSDictionary *shortcut in shortcuts) {
            if (![shortcut isKindOfClass:[NSDictionary class]]) continue;
            NSString *action = [shortcut[@"actionIdentifier"] isKindOfClass:[NSString class]] ? shortcut[@"actionIdentifier"] : nil;
            if (action.length == 0) action = [shortcut[@"intentIdentifier"] isKindOfClass:[NSString class]] ? shortcut[@"intentIdentifier"] : nil;
            if (action.length == 0 || [seen containsObject:action]) continue;
            [seen addObject:action];

            id shortTitle = shortcut[@"shortTitle"];
            NSString *titleKey = nil;
            if ([shortTitle isKindOfClass:[NSDictionary class]] && [shortTitle[@"key"] isKindOfClass:[NSString class]]) {
                titleKey = shortTitle[@"key"];
            } else if ([shortTitle isKindOfClass:[NSString class]]) {
                titleKey = shortTitle;
            }

            DXPAppShortcutItem *entry = [[DXPAppShortcutItem alloc] init];
            entry.type = action;
            entry.title = [self localizedAppIntentTitleForKey:titleKey.length > 0 ? titleKey : action
                                                     inBundle:bundle loctables:loctables] ?: action;
            entry.source = DXPAppShortcutSourceAppIntent;
            [results addObject:entry];
        }
    }
    return results;
}

// Merges one app's quick actions from all three sources into a group
// dictionary, or nil when the app declares none. A type found in several
// sources is kept once, in priority order (static, dynamic, App Shortcuts),
// so the list never shows the same menu action twice.
+ (NSDictionary *)shortcutGroupForProxy:(LSApplicationProxy *)proxy
                               bundleID:(NSString *)bundleID
                                   name:(NSString *)name {
    // Reading another app's metadata goes through private lookup, bundle
    // localization and container files; an exception there must only skip
    // that app instead of crashing Settings when the page is opened.
    NSArray<DXPAppShortcutItem *> *sourceItems[3];
    @try {
        sourceItems[0] = [self staticShortcutItemsForProxy:proxy] ?: @[];
        sourceItems[1] = [self dynamicShortcutItemsForProxy:proxy bundleID:bundleID] ?: @[];
        sourceItems[2] = [self appIntentShortcutItemsForProxy:proxy] ?: @[];
    } @catch (NSException *exception) {
        NSLog(@"[TypeX] shortcuts: skipped %@ (%@)", bundleID, exception);
        return nil;
    }
    if (sourceItems[0].count == 0 && sourceItems[1].count == 0 && sourceItems[2].count == 0) return nil;

    NSMutableSet<NSString *> *seenTypes = [NSMutableSet set];
    NSMutableArray<DXPAppShortcutItem *> *items = [NSMutableArray array];
    for (NSUInteger index = 0; index < 3; index++) {
        for (DXPAppShortcutItem *item in sourceItems[index]) {
            if ([seenTypes containsObject:item.type]) continue;
            [seenTypes addObject:item.type];
            [items addObject:item];
        }
    }
    return @{@"name": name, @"bundleID": bundleID, @"items": [items copy]};
}

// Live icon-menu captures written by the SpringBoard side of the tweak
// (TypeXSBShortcutsPath). A capture is a snapshot of one long-press, so
// entries older than DXSBShortcutCaptureMaxAge are dropped rather than
// outliving the app's own shortcut changes. The file lives under the shared
// snapshot directory, which Settings reads like every other TypeX shared
// preference.
+ (NSDictionary<NSString *, NSArray<DXPAppShortcutItem *> *> *)springBoardCapturedShortcutsByBundleID {
    @try {
        NSDictionary *root = [NSDictionary dictionaryWithContentsOfFile:TypeXSBShortcutsPath];
        NSDictionary *apps = [root[@"apps"] isKindOfClass:[NSDictionary class]] ? root[@"apps"] : nil;
        if (apps.count == 0) return @{};

        NSTimeInterval cutoff = [NSDate timeIntervalSinceReferenceDate] - DXSBShortcutCaptureMaxAge;
        NSMutableDictionary<NSString *, NSArray<DXPAppShortcutItem *> *> *result = [NSMutableDictionary dictionary];
        for (NSString *bundleID in apps.allKeys) {
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
            if (items.count > 0) result[bundleID] = items;
        }
        return result;
    } @catch (NSException *exception) {
        NSLog(@"[TypeX] shortcuts: unreadable SpringBoard capture file (%@)", exception);
        return @{};
    }
}

// Merges one app's live captures into its metadata-scanned group. Captures
// reflect the menu the user actually saw, so they lead the list and win type
// deduplication; an app whose metadata scan found nothing still gets a
// group from captures alone.
+ (NSDictionary *)groupByPrependingCapturedItems:(NSArray<DXPAppShortcutItem *> *)capturedItems
                                            group:(NSDictionary *)group
                                         bundleID:(NSString *)bundleID
                                             name:(NSString *)name {
    NSMutableArray<DXPAppShortcutItem *> *items = [NSMutableArray arrayWithArray:capturedItems];
    NSMutableSet<NSString *> *seenTypes = [NSMutableSet setWithArray:[capturedItems valueForKey:@"type"]];
    for (DXPAppShortcutItem *item in group[@"items"]) {
        if ([seenTypes containsObject:item.type]) continue;
        [seenTypes addObject:item.type];
        [items addObject:item];
    }
    return @{@"name": name, @"bundleID": bundleID, @"items": [items copy]};
}

+ (NSArray<NSDictionary *> *)appShortcutGroups {
    @try {
        NSDictionary<NSString *, NSArray<DXPAppShortcutItem *> *> *captured = [self springBoardCapturedShortcutsByBundleID];
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
            // Live captures outrank every metadata source; they also give a
            // group to apps whose metadata scan came up empty.
            NSArray<DXPAppShortcutItem *> *capturedItems = captured[bundleID];
            if (capturedItems.count > 0) {
                group = [self groupByPrependingCapturedItems:capturedItems group:group bundleID:bundleID name:name];
            }
            if (group) {
                readable++;
                [groups addObject:group];
            }
        }
        DXLastShortcutScanApplicationCount = scanned;
        NSInteger sourceCounts[4] = {0, 0, 0, 0};
        for (NSDictionary *group in groups) {
            for (DXPAppShortcutItem *item in group[@"items"]) {
                if ([item isKindOfClass:[DXPAppShortcutItem class]] &&
                    item.source >= DXPAppShortcutSourceStatic && item.source <= DXPAppShortcutSourceSpringBoard) {
                    sourceCounts[item.source]++;
                }
            }
        }
        NSLog(@"[TypeX] shortcuts scan: %ld apps, %ld with quick actions (static %ld, dynamic %ld, app intents %ld, live %ld)",
              (long)scanned, (long)readable, (long)sourceCounts[0], (long)sourceCounts[1], (long)sourceCounts[2], (long)sourceCounts[3]);
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
