#import "../DXPanelPagedGridView.h"
#import <objc/message.h>

@interface UIView ()
@property(nonatomic, strong) NSMutableArray *children;
@property(nonatomic) BOOL needsLayout;
@end
@implementation UIView
- (instancetype)init { return [self initWithFrame:CGRectZero]; }
- (instancetype)initWithFrame:(CGRect)frame {
    if ((self = [super init])) { self.children = [NSMutableArray array]; self.frame = frame; }
    return self;
}
- (void)setFrame:(CGRect)frame { _frame = frame; _bounds.size = frame.size; self.needsLayout = YES; }
- (NSArray *)subviews { return [self.children copy]; }
- (void)addSubview:(UIView *)view { [view removeFromSuperview]; [self.children addObject:view]; view.superview = self; }
- (void)removeFromSuperview { [self.superview.children removeObject:self]; self.superview = nil; }
- (void)setNeedsLayout { self.needsLayout = YES; }
- (void)layoutIfNeeded { if (self.needsLayout) { self.needsLayout = NO; [self layoutSubviews]; } }
- (void)layoutSubviews { }
@end
@implementation UIWindow @end
@implementation UIScrollView
- (void)setContentOffset:(CGPoint)offset {
    _contentOffset = offset;
    CGRect bounds = self.bounds; bounds.origin = offset; self.bounds = bounds;
    if ([self.delegate respondsToSelector:@selector(scrollViewDidScroll:)]) [self.delegate scrollViewDidScroll:self];
    [self setNeedsLayout];
}
- (void)setContentOffset:(CGPoint)offset animated:(BOOL)animated { (void)animated; self.contentOffset = offset; }
- (BOOL)touchesShouldCancelInContentView:(UIView *)view { return ![view isKindOfClass:UIControl.class]; }
@end
@interface UIControl ()
@property(nonatomic, weak) id target;
@property(nonatomic) SEL action;
@end
@implementation UIControl
- (void)addTarget:(id)target action:(SEL)action forControlEvents:(UIControlEvents)events { (void)events; self.target = target; self.action = action; }
- (void)sendActionsForControlEvents:(UIControlEvents)events { (void)events; if (self.target) ((void (*)(id, SEL))objc_msgSend)(self.target, self.action); }
@end
@implementation UIButton @end

static NSUInteger checks;
static void check(BOOL value) { NSCAssert(value, @"paging view check %lu failed", (unsigned long)checks + 1); checks++; }
static NSArray *items(NSUInteger count) {
    NSMutableArray *result = [NSMutableArray array];
    for (NSUInteger i = 0; i < count; i++) [result addObject:[UIButton new]];
    return result;
}
int main(void) {
    @autoreleasepool {
        DXPanelPagedGridView *grid = [DXPanelPagedGridView new];
        NSArray *buttons = items(25);
        [grid configureWithItems:buttons columns:4 scale:1];
        grid.frame = CGRectMake(0, 0, 320, [grid preferredHeightForWidth:320]);
        [grid layoutIfNeeded];
        check(grid.pageCount == 3 && grid.currentPage == 0);
        check(grid.contentOffset.x == 640 && grid.contentOffset.y == 0);
        check(grid.contentSize.width == 960 && grid.contentSize.height == grid.bounds.size.height);
        check(grid.pagingEnabled && grid.directionalLockEnabled && grid.scrollEnabled);
        check(grid.canCancelContentTouches && [grid touchesShouldCancelInContentView:buttons[0]]);
        check(grid.alwaysBounceHorizontal && !grid.alwaysBounceVertical);
        check([grid.accessibilityValue isEqual:@"1 / 3"]);
        check(CGRectGetMinX([buttons[0] frame]) == 640 && CGRectGetMinX([buttons[12] frame]) == 320);
        check(CGRectGetMinY([buttons[24] frame]) == 0);
        // A rightward drag reduces offset and reveals the next logical page.
        grid.contentOffset = CGPointMake(320, 0); [grid layoutIfNeeded];
        check(grid.currentPage == 1 && grid.contentOffset.x == 320);
        check([grid.accessibilityValue isEqual:@"2 / 3"]);
        // Repeated layout and bounds-origin changes must never snap back.
        [grid setNeedsLayout]; [grid layoutIfNeeded];
        check(grid.currentPage == 1 && grid.contentOffset.x == 320);
        // UIKit can send didScroll using resized bounds before layout; retain
        // the logical page until offsets are recalculated for the new width.
        grid.frame = CGRectMake(0, 0, 500, [grid preferredHeightForWidth:500]);
        [grid.delegate scrollViewDidScroll:grid]; [grid layoutIfNeeded];
        check(grid.currentPage == 1 && grid.contentOffset.x == 500);
        grid.contentOffset = CGPointMake(0, 0); [grid layoutIfNeeded];
        check(grid.currentPage == 2);
        grid.contentOffset = CGPointMake(500, 0); [grid layoutIfNeeded];
        check(grid.currentPage == 1);
        __block NSUInteger blanks = 0;
        grid.blankAction = ^{ blanks++; };
        UIControl *blank = (UIControl *)grid.subviews.firstObject;
        check([grid touchesShouldCancelInContentView:blank]);
        [blank sendActionsForControlEvents:UIControlEventTouchUpInside]; check(blanks == 1);
        grid.blankAction = nil;
        [blank sendActionsForControlEvents:UIControlEventTouchUpInside]; check(blanks == 1);
        // Updating configuration removes old controls and resets to page 0.
        NSArray *replacement = items(10);
        [grid configureWithItems:replacement columns:3 scale:1]; [grid layoutIfNeeded];
        check(grid.pageCount == 2 && grid.currentPage == 0 && grid.contentOffset.x == 500);
        check(![buttons[0] superview] && [replacement[0] superview] == grid);
        [grid configureWithItems:items(3) columns:5 scale:0.7];
        grid.frame = CGRectMake(0, 0, 500, [grid preferredHeightForWidth:500]); [grid layoutIfNeeded];
        check(grid.pageCount == 1 && grid.contentOffset.x == 0 && !grid.scrollEnabled);
        check(!grid.alwaysBounceHorizontal && !grid.accessibilityValue);
        [grid configureWithItems:@[] columns:4 scale:1];
        grid.frame = CGRectMake(0, 0, 500, [grid preferredHeightForWidth:500]); [grid layoutIfNeeded];
        check(grid.pageCount == 0 && grid.currentPage == 0 && grid.bounds.size.height == 0);
        check(grid.subviews.count == 1 && grid.contentOffset.x == 0 && !grid.scrollEnabled);
        NSLog(@"PASS: %lu production paging view checks with UIKit doubles (reset, resize, scroll, touch cancellation, blank cleanup)", (unsigned long)checks);
    }
    return 0;
}
