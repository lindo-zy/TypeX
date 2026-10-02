#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

// Reads symbol names from local system resources only; callers must check
// UIImage availability before presenting a name for selection.
@interface DXPSFSymbolCatalog : NSObject
+ (NSArray<NSString *> *)systemResourceDirectories;
+ (NSArray<NSString *> *)namesFromResourceDirectories:(NSArray<NSString *> *)directories
                                         sourcePaths:(NSArray<NSString *> * _Nullable * _Nullable)sourcePaths;
@end

NS_ASSUME_NONNULL_END
