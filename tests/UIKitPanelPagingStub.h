// Narrow host doubles for the production paging view; UIKit gesture
// arbitration, animations and rendering remain device-only checks.
#import <Foundation/Foundation.h>
#import <CoreGraphics/CoreGraphics.h>

typedef NS_ENUM(NSInteger, UIScrollViewContentInsetAdjustmentBehavior) { UIScrollViewContentInsetAdjustmentNever = 2 };
typedef NS_ENUM(NSInteger, UISemanticContentAttribute) { UISemanticContentAttributeForceLeftToRight = 3 };
typedef NSUInteger UIControlEvents;
static const UIControlEvents UIControlEventTouchUpInside = 1 << 6;
@class UIWindow, UIScrollView;
@interface UIView : NSObject
@property(nonatomic) CGRect frame;
@property(nonatomic) CGRect bounds;
@property(nonatomic, weak) UIView *superview;
@property(nonatomic, weak) UIWindow *window;
@property(nonatomic, readonly) NSArray<UIView *> *subviews;
@property(nonatomic) UISemanticContentAttribute semanticContentAttribute;
@property(nonatomic, copy) NSString *accessibilityValue;
- (instancetype)initWithFrame:(CGRect)frame;
- (void)addSubview:(UIView *)view;
- (void)removeFromSuperview;
- (void)setNeedsLayout;
- (void)layoutIfNeeded;
- (void)layoutSubviews;
@end
@interface UIWindow : UIView @end
@protocol UIScrollViewDelegate <NSObject>
@optional
- (void)scrollViewDidScroll:(UIScrollView *)scrollView;
@end
@interface UIScrollView : UIView
@property(nonatomic, weak) id<UIScrollViewDelegate> delegate;
@property(nonatomic) BOOL pagingEnabled, directionalLockEnabled;
@property(nonatomic) BOOL showsVerticalScrollIndicator, showsHorizontalScrollIndicator;
@property(nonatomic) BOOL alwaysBounceVertical, alwaysBounceHorizontal;
@property(nonatomic) BOOL canCancelContentTouches, delaysContentTouches, scrollEnabled;
@property(nonatomic) UIScrollViewContentInsetAdjustmentBehavior contentInsetAdjustmentBehavior;
@property(nonatomic) CGSize contentSize;
@property(nonatomic) CGPoint contentOffset;
- (void)setContentOffset:(CGPoint)offset animated:(BOOL)animated;
- (BOOL)touchesShouldCancelInContentView:(UIView *)view;
@end
@interface UIControl : UIView
- (void)addTarget:(id)target action:(SEL)action forControlEvents:(UIControlEvents)events;
- (void)sendActionsForControlEvents:(UIControlEvents)events;
@end
@interface UIButton : UIControl @end
