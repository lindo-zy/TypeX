#if defined(THEOS_PACKAGE_SCHEME_ROOTHIDE)
#import <roothide.h>
#define DX_ROOT_PATH_NS(path) jbroot(path)
#else
#import <rootless.h>
#define DX_ROOT_PATH_NS(path) ROOT_PATH_NS(path)
#endif

@interface DXShortcutsGenerator : NSObject
+(void)load;
+(BOOL)isAvailableShortcutSelector:(NSString *)selector;
+(BOOL)isVisibleShortcutSelector:(NSString *)selector;
+(instancetype)sharedInstance;
-(instancetype)init;
-(NSArray *)imageNameArrayForiOS:(NSInteger)iosVersion;
-(NSArray *)selectorNames;
-(NSArray *)labelName;
-(NSArray *)shortenedlabelName;
@end
