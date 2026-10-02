#import <UIKit/UIKit.h>

@interface DXGlobalPanel : NSObject
+ (instancetype)sharedInstance;
+ (BOOL)deviceUnlocked;
- (BOOL)isVisible;
- (void)presentSide:(NSString *)side fromWindow:(UIWindow *)window origin:(NSString *)origin;
- (void)dismiss;
@end

// Call once from TypeX's existing SpringBoard initialization path.
FOUNDATION_EXPORT void DXStartGlobalPanel(void);
