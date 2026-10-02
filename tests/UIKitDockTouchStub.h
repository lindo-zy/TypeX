// Narrow view doubles for the production touch policy; no UIKit arbitration.
#import <Foundation/Foundation.h>
#import <CoreGraphics/CoreGraphics.h>
@class UIWindow;
@interface UIView : NSObject
@property(nonatomic, weak) UIWindow *window;
@property(nonatomic, weak) UIView *superview;
@property(nonatomic, strong) NSMutableArray<UIView *> *subviews;
@property(nonatomic) CGRect bounds;
@property(nonatomic) CGPoint originInWindow;
@property(nonatomic) BOOL hidden;
@property(nonatomic) CGFloat alpha;
- (void)addSubview:(UIView *)view;
- (CGRect)convertRect:(CGRect)rect toView:(UIView *)view;
- (BOOL)isDescendantOfView:(UIView *)view;
@end
@interface UIWindow : UIView @end
@interface UIControl : UIView @end
@interface SBIconImageView : UIView @end
@interface SBIconView : UIView
@property(nonatomic, strong) UIView *image;
- (UIView *)iconImageView;
@end
