#import "UIKitDockGestureStub.h"
typedef NS_ENUM(NSInteger, UIApplicationState) { UIApplicationStateActive, UIApplicationStateInactive, UIApplicationStateBackground };
typedef NS_ENUM(NSInteger, UIInterfaceOrientation) { UIInterfaceOrientationUnknown, UIInterfaceOrientationPortrait, UIInterfaceOrientationLandscapeLeft, UIInterfaceOrientationLandscapeRight };
static inline BOOL UIInterfaceOrientationIsLandscape(UIInterfaceOrientation value) { return value == UIInterfaceOrientationLandscapeLeft || value == UIInterfaceOrientationLandscapeRight; }
@interface UIApplication : NSObject
@property(nonatomic) UIApplicationState applicationState;
+ (instancetype)sharedApplication;
@end
@interface UIWindowScene (StatusBarTests)
@property(nonatomic) UIInterfaceOrientation interfaceOrientation;
@end
@interface UITouch (StatusBarTests)
@property(nonatomic) NSUInteger tapCount;
@end
@interface UIGestureRecognizer (StatusBarTests)
- (void)requireGestureRecognizerToFail:(UIGestureRecognizer *)gesture;
@end
@interface UITapGestureRecognizer : UIGestureRecognizer
@property(nonatomic) NSUInteger numberOfTapsRequired;
@end
@interface UILongPressGestureRecognizer : UIGestureRecognizer
@property(nonatomic) NSTimeInterval minimumPressDuration;
@property(nonatomic) CGFloat allowableMovement;
@end
typedef NS_ENUM(NSInteger, UIImpactFeedbackStyle) { UIImpactFeedbackStyleLight };
@interface UIImpactFeedbackGenerator : NSObject
- (instancetype)initWithStyle:(UIImpactFeedbackStyle)style;
- (void)impactOccurred;
@end
@interface UIStatusBar : UIView @end
@interface _UIStatusBar : UIView @end
