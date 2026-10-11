#import <Foundation/Foundation.h>
#import <CoreGraphics/CoreGraphics.h>
@class UIGestureRecognizer, UITouch, UIWindowScene;
@protocol UIGestureRecognizerDelegate <NSObject>
@end
typedef NS_ENUM(NSInteger, UIGestureRecognizerState) {
    UIGestureRecognizerStatePossible, UIGestureRecognizerStateBegan, UIGestureRecognizerStateChanged,
    UIGestureRecognizerStateEnded, UIGestureRecognizerStateCancelled, UIGestureRecognizerStateFailed
};
@interface UIGestureRecognizer : NSObject
@property(nonatomic) UIGestureRecognizerState state;
@property(nonatomic, weak) id delegate;
- (instancetype)initWithTarget:(id)target action:(SEL)action;
@end
@interface UIPinchGestureRecognizer : UIGestureRecognizer
@property(nonatomic) CGFloat scale;
@end
@interface UIWindow : NSObject
@property(nonatomic) BOOL hidden;
@property(nonatomic, strong) UIWindowScene *windowScene;
@property(nonatomic, strong) NSMutableArray *recognizers;
- (void)addGestureRecognizer:(UIGestureRecognizer *)gesture;
- (void)removeGestureRecognizer:(UIGestureRecognizer *)gesture;
@end
@interface UITouch : NSObject
@property(nonatomic, strong) UIWindow *window;
@end
@interface UISceneSession : NSObject
@property(nonatomic, copy) NSString *role;
@end
@interface UIScene : NSObject
@property(nonatomic, strong) UISceneSession *session;
@end
@interface UIWindowScene : UIScene
@property(nonatomic, copy) NSArray<UIWindow *> *windows;
@property(nonatomic, copy) NSString *testIdentifier;
- (NSString *)_sceneIdentifier;
@end
@interface UIApplication : NSObject
@property(nonatomic, copy) NSSet<UIScene *> *connectedScenes;
+ (instancetype)sharedApplication;
@end
static NSString * const UIWindowSceneSessionRoleApplication = @"application";
static NSString * const UIWindowDidBecomeVisibleNotification = @"window-visible";
static NSString * const UISceneDidActivateNotification = @"scene-active";
