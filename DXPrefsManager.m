#import "common.h"
#import "DXPrefsManager.h"

static void reloadPrefs(CFNotificationCenterRef center, void *observer, CFStringRef name,
                        const void *object, CFDictionaryRef userInfo) {
    [(__bridge DXPrefsManager *)observer reload];
}

@implementation DXPrefsManager

+ (void)load {
    @autoreleasepool {
        NSArray *args = [[NSClassFromString(@"NSProcessInfo") processInfo] arguments];
        if (args.count == 0) return;

        NSString *executablePath = args[0];
        NSString *processName = executablePath.lastPathComponent;
        BOOL isSpringBoardProcess = [processName isEqualToString:@"SpringBoard"];
        BOOL isApplicationProcess = [executablePath rangeOfString:@"/Application"].location != NSNotFound;
        if (isSpringBoardProcess || isApplicationProcess) [DXPrefsManager sharedInstance];
    }
}

+ (instancetype)sharedInstance {
    static dispatch_once_t predicate;
    static DXPrefsManager *manager;
    dispatch_once(&predicate, ^{ manager = [[self alloc] init]; });
    return manager;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(),
                                         (__bridge const void *)self, &reloadPrefs,
                                         (CFStringRef)kPrefsChangedIdentifier, NULL, 0);
        self.prefs = [self readPrefs];
    }
    return self;
}

#pragma mark - IPC helpers

- (CPDistributedMessagingCenter *)messagingCenter {
    if (!_messagingCenter) {
        _messagingCenter = [CPDistributedMessagingCenter centerNamed:@"com.lindo.typex.server"];
    }
    return _messagingCenter;
}

#pragma mark - Read

- (NSDictionary *)readPrefsFromSandbox:(BOOL)isSandbox {
    if (isSandbox) {
        return [[self messagingCenter] sendMessageAndReceiveReplyName:@"typeXFetchPrefs" userInfo:nil] ?: @{};
    }
    return [self readPrefs];
}

- (NSDictionary *)readPrefs {
    CFStringRef appID = (CFStringRef)kIdentifier;
    CFPreferencesAppSynchronize(appID);

    CFArrayRef keyList = CFPreferencesCopyKeyList(appID, kCFPreferencesCurrentUser, kCFPreferencesAnyHost);
    NSDictionary *preferences = nil;
    if (keyList) {
        preferences = CFBridgingRelease(CFPreferencesCopyMultiple(keyList, appID,
                                                                   kCFPreferencesCurrentUser,
                                                                   kCFPreferencesAnyHost));
        CFRelease(keyList);
    }

    // PreferenceLoader/cfprefsd is the source of truth on iOS 17.  Keep the
    // plist fallback for old installs and for the short window before the
    // preferences daemon has materialized the domain.
    if ([preferences isKindOfClass:[NSDictionary class]] && preferences.count > 0) {
        return preferences;
    }
    return [NSDictionary dictionaryWithContentsOfFile:kPrefsPath] ?: @{};
}

#pragma mark - Write

- (void)writePrefs:(NSDictionary *)dictionary fromSandbox:(BOOL)isSandbox {
    if (isSandbox) {
        [[self messagingCenter] sendMessageName:@"typeXWritePrefs" userInfo:dictionary];
        return;
    }
    [self writePrefs:dictionary];
}

- (void)writePrefs:(NSDictionary *)dictionary {
    if (![dictionary isKindOfClass:[NSDictionary class]]) return;

    // Keep the file update and notification in one place.  In particular, callers
    // that only maintain an internal cache can suppress the notification and avoid
    // recursively entering the Darwin notification callback.
    CFStringRef appID = (CFStringRef)kIdentifier;
    CFPreferencesAppSynchronize(appID);

    // Replace the domain, rather than only setting keys.  This matters for
    // removed shortcuts: stale keys must not survive an iOS 17 cfprefsd write.
    CFArrayRef existingKeys = CFPreferencesCopyKeyList(appID, kCFPreferencesCurrentUser, kCFPreferencesAnyHost);
    NSMutableArray *keysToRemove = [NSMutableArray array];
    if (existingKeys) {
        for (NSString *existingKey in (__bridge NSArray *)existingKeys) {
            if (!dictionary[existingKey]) [keysToRemove addObject:existingKey];
        }
        CFRelease(existingKeys);
    }
    CFPreferencesSetMultiple((__bridge CFDictionaryRef)dictionary,
                             (__bridge CFArrayRef)keysToRemove,
                             appID, kCFPreferencesCurrentUser, kCFPreferencesAnyHost);
    CFPreferencesAppSynchronize(appID);

    // Keep the on-disk representation available to legacy preference cells.
    [dictionary writeToFile:kPrefsPath atomically:YES];
    self.prefs = [dictionary copy];
    [self postChangedNotification];
}

#pragma mark - Set / Get / Remove

- (void)setValue:(id)value forKey:(NSString *)key fromSandbox:(BOOL)isSandbox {
    if (isSandbox) {
        NSDictionary *userInfo = @{
            @"key": key ?: @"",
            @"value": value ?: [NSNull null]
        };
        [[self messagingCenter] sendMessageName:@"typeXSaveValue" userInfo:userInfo];
        return;
    }
    [self setValue:value forKey:key];
}

- (void)setValue:(id)value forKey:(NSString *)key {
    if (key.length == 0) return;
    NSMutableDictionary *dictionary = [[self readPrefs] mutableCopy] ?: [NSMutableDictionary dictionary];
    if (value) dictionary[key] = value;
    else [dictionary removeObjectForKey:key];
    [self writePrefs:dictionary];
}

- (id)getValueForKey:(NSString *)key fromSandbox:(BOOL)isSandbox {
    if (isSandbox) {
        NSDictionary *reply = [[self messagingCenter] sendMessageAndReceiveReplyName:@"typeXGetValue" userInfo:@{@"key": key ?: @""}];
        return reply[@"value"];
    }
    return [self getValueForKey:key];
}

- (id)getValueForKey:(NSString *)key {
    return [self readPrefs][key];
}

- (void)removeKey:(NSString *)key fromSandbox:(BOOL)isSandbox {
    if (isSandbox) {
        [[self messagingCenter] sendMessageName:@"typeXRemoveKey" userInfo:@{@"key": key ?: @""}];
        return;
    }
    [self removeKey:key];
}

- (void)removeKey:(NSString *)key {
    [self removeKey:key notify:YES];
}

- (void)removeKey:(NSString *)key notify:(BOOL)notify {
    if (key.length == 0) return;

    CFStringRef appID = (CFStringRef)kIdentifier;
    CFPreferencesSetAppValue((__bridge CFStringRef)key, NULL, appID);
    CFPreferencesAppSynchronize(appID);

    NSMutableDictionary *dictionary = [[self readPrefs] mutableCopy] ?: [NSMutableDictionary dictionary];
    [dictionary removeObjectForKey:key];
    [dictionary writeToFile:kPrefsPath atomically:YES];
    self.prefs = [dictionary copy];
    if (notify) [self postChangedNotification];
}

- (void)postChangedNotification {
    CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(),
                                          (CFStringRef)kPrefsChangedIdentifier, NULL, NULL, YES);
}

- (void)reload {
    self.prefs = [self readPrefs];
}

- (void)dealloc {
    CFNotificationCenterRemoveObserver(CFNotificationCenterGetDarwinNotifyCenter(),
                                        (__bridge const void *)self,
                                        (CFStringRef)kPrefsChangedIdentifier, NULL);
}

@end
