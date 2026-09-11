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

        // This class is linked only into TypeX targets.  Initialise it in every
        // host that loads TypeX so app extensions follow the same non-SpringBoard
        // sandbox policy as +isRunningInSandbox.
        [DXPrefsManager sharedInstance];
    }
}

+ (instancetype)sharedInstance {
    static dispatch_once_t predicate;
    static DXPrefsManager *manager;
    dispatch_once(&predicate, ^{ manager = [[self alloc] init]; });
    return manager;
}

+ (BOOL)isRunningInSandbox {
    NSArray *args = [[NSClassFromString(@"NSProcessInfo") processInfo] arguments];
    if (args.count == 0) return NO;

    // Only SpringBoard can read /var/mobile/Library/Preferences directly and is
    // the host of the DXPrefsManagerServer IPC endpoint.  Apps and keyboard
    // extensions are sandboxed and cannot access the com.lindo.typex domain, so
    // they must go through IPC; treat any non-SpringBoard process as sandboxed.
    NSString *executablePath = args[0];
    NSString *processName = executablePath.lastPathComponent;
    BOOL isSpringBoardProcess = [processName isEqualToString:@"SpringBoard"];
    return !isSpringBoardProcess;
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

#pragma mark - Shared file fallback for sandboxed processes

static NSString *DXSharedPrefsPath(void) {
    return TypeXSharedPrefsPath;
}

- (void)writeSharedPrefs:(NSDictionary *)dictionary {
    if (![dictionary isKindOfClass:[NSDictionary class]]) return;
    NSString *path = DXSharedPrefsPath();
    NSString *dir = [path stringByDeletingLastPathComponent];
    NSFileManager *fm = [NSFileManager defaultManager];
    if (![fm fileExistsAtPath:dir]) {
        [fm createDirectoryAtPath:dir withIntermediateDirectories:YES attributes:@{NSFileOwnerAccountName:@"mobile", NSFileGroupOwnerAccountName:@"mobile"} error:nil];
    }
    [dictionary writeToFile:path atomically:YES];
    NSDictionary *attrs = @{NSFileOwnerAccountName:@"mobile", NSFileGroupOwnerAccountName:@"mobile"};
    [fm setAttributes:attrs ofItemAtPath:path error:nil];
}

- (NSDictionary *)readSharedPrefs {
    return [NSDictionary dictionaryWithContentsOfFile:DXSharedPrefsPath()] ?: @{};
}

#pragma mark - Read

- (NSDictionary *)readPrefsFromSandbox:(BOOL)isSandbox {
    if (isSandbox) {
        NSDictionary *shared = [self readSharedPrefs];
        if ([shared isKindOfClass:[NSDictionary class]] && shared.count > 0) {
            return shared;
        }
        // Fallback to IPC if shared file is missing/stale.
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
        [self writeSharedPrefs:dictionary];
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
    [self writeSharedPrefs:dictionary];
    [self postChangedNotification];
}

#pragma mark - Set / Get / Remove

- (void)setValue:(id)value forKey:(NSString *)key fromSandbox:(BOOL)isSandbox {
    if (isSandbox) {
        NSDictionary *current = [self readSharedPrefs];
        NSMutableDictionary *updated = [current mutableCopy] ?: [NSMutableDictionary dictionary];
        if (value) updated[key] = value;
        else [updated removeObjectForKey:key];
        [self writeSharedPrefs:updated];
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
        return [self readSharedPrefs][key];
    }
    return [self getValueForKey:key];
}

- (id)getValueForKey:(NSString *)key {
    return [self readPrefs][key];
}

- (void)removeKey:(NSString *)key fromSandbox:(BOOL)isSandbox {
    if (isSandbox) {
        NSMutableDictionary *current = [[self readSharedPrefs] mutableCopy] ?: [NSMutableDictionary dictionary];
        [current removeObjectForKey:key];
        [self writeSharedPrefs:current];
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
    [self writeSharedPrefs:dictionary];
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
