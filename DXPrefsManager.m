#import "common.h"
#import "DXPrefsManager.h"

static NSString *const DXSharedPrefsFormatKey = @"_typexSnapshotFormat";
static NSString *const DXSharedPrefsPayloadKey = @"preferences";
static const NSInteger DXSharedPrefsFormatVersion = 1;

@interface DXPrefsManager ()
@property(nonatomic, assign, readwrite) BOOL preferencesAvailable;
@end

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

    // Only SpringBoard and the Settings host (Preferences) can reach the
    // authoritative cfprefsd domain and the preference plist.  Apps and
    // keyboard extensions are sandboxed away from /var/mobile/Library and from
    // cross-process messaging; they read and write through the shared snapshot
    // that the unsandboxed hosts seed and mirror.  Settings MUST be classified
    // as unsandboxed or its writes would never reach the domain SpringBoard
    // reads.
    NSString *executablePath = args[0];
    NSString *processName = executablePath.lastPathComponent;
    BOOL isSpringBoardProcess = [processName isEqualToString:@"SpringBoard"];
    BOOL isSettingsProcess = [processName isEqualToString:@"Preferences"];
    return !(isSpringBoardProcess || isSettingsProcess);
}

- (instancetype)init {
    self = [super init];
    if (self) {
        CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(),
                                         (__bridge const void *)self, &reloadPrefs,
                                         (CFStringRef)kPrefsChangedIdentifier, NULL, 0);
        [self reload];
        [self healSharedPrefsIfNeeded];
    }
    return self;
}

#pragma mark - Shared snapshot for sandboxed processes

static NSString *DXSharedPrefsPath(void) {
    return TypeXSharedPrefsPath;
}

- (void)writeSharedPrefs:(NSDictionary *)dictionary {
    if (![dictionary isKindOfClass:[NSDictionary class]]) return;
    NSString *path = DXSharedPrefsPath();
    NSString *dir = [path stringByDeletingLastPathComponent];
    NSFileManager *fm = [NSFileManager defaultManager];
    if (![fm fileExistsAtPath:dir]) {
        // World-writable and NOT sticky: mobile writers atomically replace the
        // root-owned seed file staged by the package, which sticky would forbid.
        [fm createDirectoryAtPath:dir withIntermediateDirectories:YES attributes:@{NSFilePosixPermissions: @0777} error:nil];
    }
    // The envelope makes an intentionally empty preference set distinguishable
    // from a missing/unreadable file.  Without that distinction an app could
    // render the six defaults while the real user configuration was simply
    // unavailable.
    NSDictionary *snapshot = @{
        DXSharedPrefsFormatKey: @(DXSharedPrefsFormatVersion),
        DXSharedPrefsPayloadKey: dictionary
    };
    [snapshot writeToFile:path atomically:YES];
    // Sandboxed app hosts read this snapshot; keep it world-readable whatever
    // the writing process' umask is.
    NSDictionary *attrs = @{
        NSFilePosixPermissions: @0644,
        NSFileProtectionKey: NSFileProtectionNone
    };
    [fm setAttributes:attrs ofItemAtPath:path error:nil];
}

- (NSDictionary *)readSharedPrefs {
    NSDictionary *snapshot = [NSDictionary dictionaryWithContentsOfFile:DXSharedPrefsPath()];
    if (![snapshot isKindOfClass:[NSDictionary class]]) return nil;

    NSNumber *format = snapshot[DXSharedPrefsFormatKey];
    NSDictionary *payload = snapshot[DXSharedPrefsPayloadKey];
    if ([format isKindOfClass:[NSNumber class]] &&
        format.integerValue == DXSharedPrefsFormatVersion &&
        [payload isKindOfClass:[NSDictionary class]]) {
        return payload;
    }

    // Migrate snapshots written by TypeX 2.7.44-2.7.65.  A non-empty legacy
    // dictionary is complete; an empty legacy file is ambiguous and is healed
    // by Settings/SpringBoard instead of being treated as a valid default set.
    return snapshot.count > 0 ? snapshot : nil;
}

- (BOOL)sharedPrefsUseCurrentFormat {
    NSDictionary *snapshot = [NSDictionary dictionaryWithContentsOfFile:DXSharedPrefsPath()];
    return [snapshot[DXSharedPrefsFormatKey] isKindOfClass:[NSNumber class]] &&
           [snapshot[DXSharedPrefsFormatKey] integerValue] == DXSharedPrefsFormatVersion &&
           [snapshot[DXSharedPrefsPayloadKey] isKindOfClass:[NSDictionary class]];
}

// Seed the shared snapshot from the authoritative domain when it is missing or
// empty (first launch after install, or an erased cache).  Never overwrite a
// live snapshot: every writer that can reach the domain also mirrors its full
// result into the snapshot, so the snapshot is never behind the domain, while
// sandboxed writers (dock toggle) reach ONLY the snapshot -- replacing it from
// the domain would silently revert their writes.
- (void)healSharedPrefsIfNeeded {
    if ([DXPrefsManager isRunningInSandbox]) return;
    if ([self sharedPrefsUseCurrentFormat]) return;

    // Always replace a legacy snapshot once.  Older sandboxed hosts could
    // overwrite it with only their local cache/toggle key, leaving a readable
    // but incomplete file that permanently produced the six defaults.
    NSDictionary *authoritative = [self readPrefs];
    if ([authoritative isKindOfClass:[NSDictionary class]]) {
        [self writeSharedPrefs:authoritative];
    }
}

#pragma mark - Read

// No IPC: CPDistributedMessagingCenter between an app sandbox and SpringBoard
// needs RocketBootstrap, which this package deliberately does not depend on.
// Sandboxed hosts use only the shared snapshot.  A sandbox's CFPreferences call
// addresses that app's own container and can return a non-empty but unrelated
// dictionary; accepting it used to make the toolbar fall back to six defaults.
- (NSDictionary *)readPrefsFromSandbox:(BOOL)isSandbox {
    if (isSandbox) {
        NSDictionary *shared = [self readSharedPrefs];
        if ([shared isKindOfClass:[NSDictionary class]]) return shared;

        // An atomic replacement can still be momentarily unavailable on a few
        // filesystems.  Preserve the last complete snapshot rather than
        // replacing configured buttons with defaults.
        return self.preferencesAvailable ? self.prefs : nil;
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

// Writers converge on every channel they can reach.  An unsandboxed host
// (Settings, SpringBoard) replaces the authoritative domain -- replacing, not
// merging, so removed keys do not survive -- and mirrors the result into the
// snapshot.  A sandboxed host can only reach the snapshot: it MERGES there,
// because its readPrefs is empty and a blind replace would erase every other
// preference (e.g. a dock toggle writing only toggledOnBOOL).
- (void)writePrefs:(NSDictionary *)dictionary {
    if (![dictionary isKindOfClass:[NSDictionary class]]) return;

    BOOL isSandbox = [DXPrefsManager isRunningInSandbox];
    NSDictionary *snapshot = dictionary;
    if (isSandbox) {
        NSMutableDictionary *merged = [[self readSharedPrefs] mutableCopy] ?: [NSMutableDictionary dictionary];
        [merged addEntriesFromDictionary:dictionary];
        snapshot = merged;
    } else {
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
    }

    self.prefs = [snapshot copy];
    self.preferencesAvailable = YES;
    [self writeSharedPrefs:snapshot];
    [self postChangedNotification];
}

#pragma mark - Set / Get / Remove

- (void)setValue:(id)value forKey:(NSString *)key fromSandbox:(BOOL)isSandbox {
    [self setValue:value forKey:key];
}

- (void)setValue:(id)value forKey:(NSString *)key {
    if (key.length == 0) return;
    BOOL isSandbox = [DXPrefsManager isRunningInSandbox];
    NSDictionary *base = [self readPrefsFromSandbox:isSandbox];
    // Never turn a failed sandbox read into a new one-key snapshot: that would
    // erase the shortcut order for every other process.
    if (isSandbox && ![base isKindOfClass:[NSDictionary class]]) return;
    NSMutableDictionary *dictionary = [base mutableCopy] ?: [NSMutableDictionary dictionary];
    if (value) dictionary[key] = value;
    else [dictionary removeObjectForKey:key];
    [self writePrefs:dictionary];
}

- (id)getValueForKey:(NSString *)key fromSandbox:(BOOL)isSandbox {
    if (isSandbox) {
        return [self readPrefsFromSandbox:YES][key];
    }
    return [self getValueForKey:key];
}

- (id)getValueForKey:(NSString *)key {
    return [self readPrefs][key];
}

- (void)removeKey:(NSString *)key fromSandbox:(BOOL)isSandbox {
    [self removeKey:key];
}

- (void)removeKey:(NSString *)key {
    [self removeKey:key notify:YES];
}

- (void)removeKey:(NSString *)key notify:(BOOL)notify {
    if (key.length == 0) return;

    // The snapshot is a sandboxed process' only persistent channel; removing
    // the key there must not carry the empty readPrefs result over it.
    if ([DXPrefsManager isRunningInSandbox]) {
        NSDictionary *base = [self readPrefsFromSandbox:YES];
        if (![base isKindOfClass:[NSDictionary class]]) return;
        NSMutableDictionary *snapshot = [base mutableCopy];
        [snapshot removeObjectForKey:key];
        self.prefs = [snapshot copy];
        self.preferencesAvailable = YES;
        [self writeSharedPrefs:snapshot];
        if (notify) [self postChangedNotification];
        return;
    }

    CFStringRef appID = (CFStringRef)kIdentifier;
    CFPreferencesSetAppValue((__bridge CFStringRef)key, NULL, appID);
    CFPreferencesAppSynchronize(appID);

    NSMutableDictionary *dictionary = [[self readPrefs] mutableCopy] ?: [NSMutableDictionary dictionary];
    [dictionary removeObjectForKey:key];
    [dictionary writeToFile:kPrefsPath atomically:YES];
    self.prefs = [dictionary copy];
    self.preferencesAvailable = YES;
    [self writeSharedPrefs:dictionary];
    if (notify) [self postChangedNotification];
}

- (void)postChangedNotification {
    CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(),
                                          (CFStringRef)kPrefsChangedIdentifier, NULL, NULL, YES);
}

- (void)reload {
    NSDictionary *loaded = [self readPrefsFromSandbox:[DXPrefsManager isRunningInSandbox]];
    if ([loaded isKindOfClass:[NSDictionary class]]) {
        self.prefs = [loaded copy];
        self.preferencesAvailable = YES;
    }
    [self healSharedPrefsIfNeeded];
}

- (void)dealloc {
    CFNotificationCenterRemoveObserver(CFNotificationCenterGetDarwinNotifyCenter(),
                                        (__bridge const void *)self,
                                        (CFStringRef)kPrefsChangedIdentifier, NULL);
}

@end
