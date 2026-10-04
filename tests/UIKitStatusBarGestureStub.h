#import "UIKitDockGestureStub.h"
typedef NS_ENUM(NSInteger, UIApplicationState) { UIApplicationStateActive, UIApplicationStateInactive, UIApplicationStateBackground };
typedef NS_ENUM(NSInteger, UIInterfaceOrientation) { UIInterfaceOrientationUnknown, UIInterfaceOrientationPortrait, UIInterfaceOrientationLandscapeLeft, UIInterfaceOrientationLandscapeRight };
static inline BOOL UIInterfaceOrientationIsLandscape(UIInterfaceOrientation value) { return value == UIInterfaceOrientationLandscapeLeft || value == UIInterfaceOrientationLandscapeRight; }
@interface UIApplication : NSObject
@property(nonatomic) UIApplicationState applicationState;
@property(nonatomic, copy) NSArray<UIWindow *> *windows;
@property(nonatomic, copy) NSSet *connectedScenes;
+ (instancetype)sharedApplication;
@end
typedef NSObject UIScene;
@interface UIWindowScene (StatusBarTests)
@property(nonatomic) UIInterfaceOrientation interfaceOrientation;
@property(nonatomic, copy) NSArray<UIWindow *> *windows;
@end
@interface UITouch (StatusBarTests)
@property(nonatomic) NSUInteger tapCount;
@end
@interface UIGestureRecognizer (StatusBarTests)
@property(nonatomic) BOOL delaysTouchesEnded;
- (void)requireGestureRecognizerToFail:(UIGestureRecognizer *)gesture;
@end
@interface UITapGestureRecognizer : UIGestureRecognizer
@property(nonatomic) NSUInteger numberOfTapsRequired;
@property(nonatomic) NSUInteger numberOfTouchesRequired;
@end
@interface UILongPressGestureRecognizer : UIGestureRecognizer
@property(nonatomic) NSTimeInterval minimumPressDuration;
@property(nonatomic) CGFloat allowableMovement;
@end
// Real status-bar action recognizers are not UITapGestureRecognizer subclasses.
@interface _UIStatusBarActionGestureRecognizer : UIGestureRecognizer @end
@interface STUIStatusBarActionGestureRecognizer : UIGestureRecognizer @end
typedef NS_ENUM(NSInteger, UIImpactFeedbackStyle) { UIImpactFeedbackStyleLight };
@interface UIImpactFeedbackGenerator : NSObject
- (instancetype)initWithStyle:(UIImpactFeedbackStyle)style;
- (void)impactOccurred;
@end
@interface UIView (StatusBarLifecycleTests)
- (void)didMoveToWindow;
@end
@interface UIStatusBar_Base : UIView @end
@interface UIStatusBar : UIStatusBar_Base @end
@interface UIStatusBar_Modern : UIStatusBar_Base @end
@interface _UIStatusBar : UIView @end
// Registered at test time to exercise classes appearing after initial setup.
@interface STUIStatusBar_Wrapper : UIStatusBar_Base @end
@interface STUIStatusBar : UIView @end
@interface SBSystemApertureContainerView : UIView @end
