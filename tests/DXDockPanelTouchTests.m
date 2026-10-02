#import "DXDockPanelTouchPolicy.h"
#import <objc/runtime.h>

@implementation UIView
- (instancetype)init {
    if ((self = [super init])) { _alpha = 1; _subviews = [NSMutableArray array]; }
    return self;
}
- (void)addSubview:(UIView *)view { [self.subviews addObject:view]; view.superview = self; view.window = self.window; }
- (CGRect)convertRect:(CGRect)rect toView:(UIView *)view {
    (void)view;
    return CGRectOffset(rect, self.originInWindow.x - self.bounds.origin.x, self.originInWindow.y - self.bounds.origin.y);
}
- (BOOL)isDescendantOfView:(UIView *)view {
    for (UIView *ancestor = self; ancestor; ancestor = ancestor.superview) if (ancestor == view) return YES;
    return NO;
}
@end
@implementation UIWindow @end
@implementation UIControl @end
@implementation SBIconImageView @end
@implementation SBIconView
- (UIView *)iconImageView { return self.image; }
@end
@interface SBMissingGetterIconView : SBIconView @end
@implementation SBMissingGetterIconView
- (BOOL)respondsToSelector:(SEL)selector {
    return selector == @selector(iconImageView) ? NO : [super respondsToSelector:selector];
}
@end

static NSUInteger checks;
static void check(BOOL condition, NSString *name) { NSCAssert(condition, @"%@", name); checks++; }
static NSInteger invalidImageGetter(id self, SEL selector) { (void)self; (void)selector; return 1; }

int main(void) {
    @autoreleasepool {
        UIWindow *window = [UIWindow new]; window.window = window;
        UIView *dock = [UIView new]; dock.bounds = CGRectMake(0, 0, 300, 96); dock.originInWindow = CGPointMake(0, 500);
        [window addSubview:dock];
        SBIconView *phone = [SBIconView new]; phone.bounds = CGRectMake(0, 0, 150, 96); phone.originInWindow = CGPointMake(20, 500);
        SBIconView *messages = [SBIconView new]; messages.bounds = phone.bounds; messages.originInWindow = CGPointMake(130, 500);
        [dock addSubview:phone]; [dock addSubview:messages];
        SBIconImageView *phoneImage = [SBIconImageView new]; phoneImage.bounds = CGRectMake(0, 0, 60, 60); phoneImage.originInWindow = CGPointMake(40, 518);
        SBIconImageView *messagesImage = [SBIconImageView new]; messagesImage.bounds = phoneImage.bounds; messagesImage.originInWindow = CGPointMake(200, 518);
        [phone addSubview:phoneImage]; [messages addSubview:messagesImage]; phone.image = phoneImage; messages.image = messagesImage;
        CGPoint gap = CGPointMake(150, 548), phoneCenter = CGPointMake(70, 548), messagesCenter = CGPointMake(230, 548);
        check(DXDockPanelTouchIsBackground(dock, dock, gap), @"middle gap on Dock background");
        check(DXDockPanelTouchIsBackground(dock, phone, gap), @"gap hit-tests to expanded phone target");
        check(DXDockPanelTouchIsBackground(dock, messages, gap), @"gap hit-tests to expanded messages target");
        check(!DXDockPanelTouchIsBackground(dock, phone, phoneCenter), @"phone image retains icon gesture");
        check(!DXDockPanelTouchIsBackground(dock, messagesImage, messagesCenter), @"messages image retains icon gesture");
        check(!DXDockPanelTouchIsBackground(dock, dock, messagesCenter), @"visible images excluded even if hit view is background");
        UIControl *iconPadding = [UIControl new]; [phone addSubview:iconPadding];
        check(DXDockPanelTouchIsBackground(dock, iconPadding, gap), @"control inside icon padding does not reject gap");
        UIControl *button = [UIControl new]; [dock addSubview:button];
        check(!DXDockPanelTouchIsBackground(dock, button, gap), @"real Dock control retains gesture");
        check(DXDockPanelTouchIsBackground(dock, window, CGPointMake(150, 615)), @"blank strip below Dock");
        phone.image = nil;
        check(DXDockPanelTouchIsBackground(dock, phone, gap), @"image hierarchy fallback");
        [phone.subviews removeObject:phoneImage];
        check(!DXDockPanelTouchIsBackground(dock, phone, gap), @"unavailable image geometry protects expanded bounds");
        [phone addSubview:phoneImage]; phone.image = dock;
        check(DXDockPanelTouchIsBackground(dock, phone, gap), @"getter result outside icon falls back to image hierarchy");
        phone.image = phoneImage; phoneImage.hidden = YES;
        check(!DXDockPanelTouchIsBackground(dock, phone, gap), @"hidden image uses conservative fallback");
        phoneImage.hidden = NO; phone.hidden = YES;
        check(DXDockPanelTouchIsBackground(dock, dock, phoneCenter), @"hidden icon does not occupy background");
        phone.hidden = NO; phone.alpha = 0;
        check(DXDockPanelTouchIsBackground(dock, dock, phoneCenter), @"transparent icon does not occupy background");
        phone.alpha = 1;
        phoneImage.originInWindow = CGPointMake(NAN, 518);
        check(!DXDockPanelTouchIsBackground(dock, dock, gap), @"invalid image frame fails closed");
        phoneImage.originInWindow = CGPointMake(40, 518);
        SBIconView *outsideIcon = [SBIconView new]; [window addSubview:outsideIcon];
        check(!DXDockPanelTouchIsBackground(dock, outsideIcon, gap), @"icon outside Dock is not eligible");
        UIWindow *otherWindow = [UIWindow new]; otherWindow.window = otherWindow;
        check(!DXDockPanelTouchIsBackground(dock, otherWindow, gap), @"wrong source window");
        check(!DXDockPanelTouchIsBackground(dock, nil, gap), @"missing hit view");
        check(!DXDockPanelTouchIsBackground(dock, dock, CGPointMake(INFINITY, 548)), @"invalid touch point");
        Class malformed = objc_allocateClassPair(SBIconView.class, "SBMalformedDockIconView", 0);
        class_addMethod(malformed, @selector(iconImageView), (IMP)invalidImageGetter, "q@:");
        objc_registerClassPair(malformed);
        UIView *badIcon = [malformed new]; [dock addSubview:badIcon];
        SBIconImageView *badImage = [SBIconImageView new]; [badIcon addSubview:badImage];
        check(DXDockPanelIconImageView(badIcon) == badImage, @"incompatible private getter ABI is not called");
        UIView *missingGetterIcon = [SBMissingGetterIconView new]; [dock addSubview:missingGetterIcon];
        SBIconImageView *fallbackImage = [SBIconImageView new]; [missingGetterIcon addSubview:fallbackImage];
        check(DXDockPanelIconImageView(missingGetterIcon) == fallbackImage, @"unavailable private getter uses image hierarchy");
        printf("PASS: %lu production Dock touch-policy checks\n", (unsigned long)checks);
    }
    return 0;
}
