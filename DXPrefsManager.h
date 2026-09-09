#import <Foundation/Foundation.h>

@interface DXPrefsManager : NSObject{
    CPDistributedMessagingCenter * _messagingCenter;
}
@property(nonatomic, strong) NSDictionary *prefs;
+ (instancetype)sharedInstance;
+ (BOOL)isRunningInSandbox;
-(NSDictionary *)readPrefs;
-(NSDictionary *)readPrefsFromSandbox:(BOOL)isSandbox;
-(void)writePrefs:(NSDictionary *)dictionary;
-(void)writePrefs:(NSDictionary *)dictionary fromSandbox:(BOOL)isSandbox;
-(void)setValue:(id)value forKey:(NSString *)key fromSandbox:(BOOL)isSandbox;
-(void)setValue:(id)value forKey:(NSString *)key;
-(id)getValueForKey:(NSString *)key fromSandbox:(BOOL)isSandbox;
-(id)getValueForKey:(NSString *)key;
-(void)removeKey:(NSString *)key fromSandbox:(BOOL)isSandbox;
-(void)removeKey:(NSString *)key;
/// Removes a key and optionally broadcasts the cross-process preferences notification.
/// Internal cache maintenance must use notify:NO to avoid re-entering the reload callback.
-(void)removeKey:(NSString *)key notify:(BOOL)notify;
-(void)reload;
-(void)postChangedNotification;
@end
