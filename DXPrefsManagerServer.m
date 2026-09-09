#import "common.h"
#import "DXPrefsManagerServer.h"
#import "DXPrefsManager.h"

@implementation DXPrefsManagerServer

+ (void)load {
    @autoreleasepool {
        NSArray *args = [[NSClassFromString(@"NSProcessInfo") processInfo] arguments];

        if (args.count != 0) {
            NSString *executablePath = args[0];

            if (executablePath) {
                NSString *processName = [executablePath lastPathComponent];

                BOOL isSpringBoard = [processName isEqualToString:@"SpringBoard"];

                if (isSpringBoard) {
                    [self sharedInstance];

                }
            }
        }
    }
}

+ (instancetype)sharedInstance {
    static dispatch_once_t once = 0;
    __strong static id sharedInstance = nil;
    dispatch_once(&once, ^{
        sharedInstance = [self new];
    });
    return sharedInstance;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _messagingCenter = [CPDistributedMessagingCenter centerNamed:@"com.lindo.typex.server"];
        [_messagingCenter registerForMessageName:@"typeXFetchPrefs" target:self selector:@selector(readPrefs:withUserInfo:)];
        [_messagingCenter registerForMessageName:@"typeXWritePrefs" target:self selector:@selector(writePrefs:withUserInfo:)];
        [_messagingCenter registerForMessageName:@"typeXSaveValue" target:self selector:@selector(setValue:withUserInfo:)];
        [_messagingCenter registerForMessageName:@"typeXGetValue" target:self selector:@selector(getValueForKey:withUserInfo:)];
        [_messagingCenter registerForMessageName:@"typeXRemoveKey" target:self selector:@selector(removeKey:withUserInfo:)];
        [_messagingCenter runServerOnCurrentThread];
    }

    return self;
}

-(NSDictionary *)readPrefs:(NSString *)name withUserInfo:(NSDictionary *)userInfo{
    return [[DXPrefsManager sharedInstance] readPrefs];
}

-(NSDictionary *)writePrefs:(NSString *)name withUserInfo:(NSDictionary *)userInfo{
    [[DXPrefsManager sharedInstance] writePrefs:userInfo];
    return nil;
}

-(NSDictionary *)setValue:(NSString *)name withUserInfo:(NSDictionary *)userInfo{
    NSString *key = userInfo[@"key"];
    if ([key isKindOfClass:[NSString class]]) {
        id value = userInfo[@"value"];
        if ([value isKindOfClass:[NSNull class]]) value = nil;
        [[DXPrefsManager sharedInstance] setValue:value forKey:key];
    }
    return nil;
}

-(NSDictionary *)getValueForKey:(NSString *)name withUserInfo:(NSDictionary *)userInfo{
    NSString *key = userInfo[@"key"];
    id value = [key isKindOfClass:[NSString class]] ? [[DXPrefsManager sharedInstance] getValueForKey:key] : nil;
    return value ? @{@"value": value} : @{};
}

-(NSDictionary *)removeKey:(NSString *)name withUserInfo:(NSDictionary *)userInfo{
    NSString *key = userInfo[@"key"];
    if ([key isKindOfClass:[NSString class]]) {
        [[DXPrefsManager sharedInstance] removeKey:key];
    }
    return nil;
}

-(void)postChangedNotification{
    CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(), (CFStringRef)kPrefsChangedIdentifier, NULL, NULL, YES);
}
@end
