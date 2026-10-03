// Narrow UIKit doubles for compiling the production Dock handler on macOS.
// They exercise its callbacks, not UIKit's real recognition or arbitration.
#import "UIKitDockTouchStub.h"

typedef NS_ENUM(NSInteger, UISceneActivationState) { UISceneActivationStateForegroundActive = 0, UISceneActivationStateBackground = 2 };
typedef NS_ENUM(NSInteger, UIGestureRecognizerState) {
    UIGestureRecognizerStatePossible, UIGestureRecognizerStateBegan, UIGestureRecognizerStateChanged,
    UIGestureRecognizerStateEnded, UIGestureRecognizerStateCancelled, UIGestureRecognizerStateFailed
};
static NSString * const UIApplicationWillResignActiveNotification = @"UIApplicationWillResignActive";
static NSString * const UISceneWillDeactivateNotification = @"UISceneWillDeactivate";
static NSString * const UIDeviceOrientationDidChangeNotification = @"UIDeviceOrientationDidChange";

@interface UIWindowScene : NSObject
@property(nonatomic) UISceneActivationState activationState;
@end
@class UIGestureRecognizer;
@interface UIView (DockGestureTests)
@property(nonatomic, strong) NSMutableArray<UIGestureRecognizer *> *gestureRecognizers;
- (void)addGestureRecognizer:(UIGestureRecognizer *)gesture;
- (void)removeGestureRecognizer:(UIGestureRecognizer *)gesture;
@end
@interface UIWindow (DockGestureTests)
@property(nonatomic, strong) UIWindowScene *windowScene;
@end
@protocol UIGestureRecognizerDelegate <NSObject>
@end
@interface UIGestureRecognizer : NSObject
@property(nonatomic, weak) UIView *view;
@property(nonatomic, weak) id<UIGestureRecognizerDelegate> delegate;
@property(nonatomic) UIGestureRecognizerState state;
@property(nonatomic) BOOL enabled;
@property(nonatomic) BOOL cancelsTouchesInView;
@property(nonatomic) BOOL delaysTouchesBegan;
@property(nonatomic) NSUInteger numberOfTouches;
- (instancetype)initWithTarget:(id)target action:(SEL)action;
@end
@interface UIPanGestureRecognizer : UIGestureRecognizer
@property(nonatomic) NSUInteger minimumNumberOfTouches;
@property(nonatomic) NSUInteger maximumNumberOfTouches;
@property(nonatomic) CGPoint delta;
@property(nonatomic) CGPoint velocity;
- (CGPoint)translationInView:(UIView *)view;
- (CGPoint)velocityInView:(UIView *)view;
@end
@interface UIScreenEdgePanGestureRecognizer : UIPanGestureRecognizer @end
@interface UITouch : NSObject
@property(nonatomic, weak) UIWindow *window;
@property(nonatomic, weak) UIView *view;
@property(nonatomic) CGPoint point;
- (CGPoint)locationInView:(UIView *)view;
@end
