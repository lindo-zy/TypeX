// Production recognizer exercised with UIKit event/view doubles on macOS.
// This verifies our state machine, not UIKit's on-device arbitration.
#import "DXToolbarHorizontalGesture.h"

@implementation UIView
- (CGRect)convertRect:(CGRect)rect toView:(UIView *)view { (void)view; return rect; }
@end
@implementation UIWindow
@end
@implementation UIButton
@end
@implementation UITouch
- (CGPoint)locationInView:(UIView *)view { (void)view; return self.point; }
@end
@implementation UIEvent
@end
@implementation UIGestureRecognizer
- (void)touchesBegan:(NSSet *)touches withEvent:(UIEvent *)event { (void)touches; (void)event; }
- (void)touchesMoved:(NSSet *)touches withEvent:(UIEvent *)event { (void)touches; (void)event; }
- (void)touchesEnded:(NSSet *)touches withEvent:(UIEvent *)event { (void)touches; (void)event; }
- (void)touchesCancelled:(NSSet *)touches withEvent:(UIEvent *)event { (void)touches; (void)event; }
- (void)reset { self.state = UIGestureRecognizerStatePossible; }
@end

static NSUInteger checks;
static void check(BOOL condition, NSString *name) {
    if (!condition) { NSLog(@"FAIL recognizer %@", name); exit(1); }
    checks++;
}

int main(void) {
    @autoreleasepool {
        UIWindow *window = [UIWindow new];
        UIView *toolbar = [UIView new];
        toolbar.bounds = CGRectMake(0, 0, 390, 50);
        toolbar.window = window;
        UIButton *button = [UIButton new];
        button.bounds = CGRectMake(0, 0, 60, 40);
        button.window = window;
        button.superview = toolbar;
        button.accessibilityIdentifier = @"copyAction:";
        UITouch *touch = [UITouch new];
        touch.view = button;
        NSSet *touches = [NSSet setWithObject:touch];
        UIEvent *event = [UIEvent new];
        event.allTouches = touches;
        DXToolbarHorizontalGesture *gesture = [DXToolbarHorizontalGesture new];
        gesture.view = toolbar;

        for (NSNumber *distance in @[@20, @-20, @140, @-140, @70]) {
            [gesture reset];
            touch.point = CGPointMake(30, 20);
            [gesture touchesBegan:touches withEvent:event];
            check(gesture.sourceButton == button, @"captures button");
            touch.point = CGPointMake(30 + distance.doubleValue, 20);
            [gesture touchesMoved:touches withEvent:event];
            check(gesture.state == UIGestureRecognizerStateBegan && gesture.result == 0, @"claims drag without executing");
            [gesture touchesEnded:touches withEvent:event];
            NSInteger expected = distance.integerValue == 70 ? 0 : (labs(distance.integerValue) == 20 ? 1 : 2) * (distance.integerValue < 0 ? -1 : 1);
            check(gesture.state == UIGestureRecognizerStateEnded && gesture.result == expected, @"one final classification");
        }
        [gesture reset];
        touch.point = CGPointMake(30, 20);
        [gesture touchesBegan:touches withEvent:event];
        touch.point = CGPointMake(31, 21);
        [gesture touchesEnded:touches withEvent:event];
        check(gesture.state == UIGestureRecognizerStateFailed && gesture.result == 0, @"tap remains a tap");

        [gesture reset];
        touch.point = CGPointMake(30, 20);
        [gesture touchesBegan:touches withEvent:event];
        touch.point = CGPointMake(31, 40);
        [gesture touchesMoved:touches withEvent:event];
        check(gesture.state == UIGestureRecognizerStateFailed, @"vertical gestures remain available");

        [gesture reset];
        touch.point = CGPointMake(30, 20);
        [gesture touchesBegan:touches withEvent:event];
        touch.point = CGPointMake(45, 20);
        [gesture touchesMoved:touches withEvent:event];
        [gesture touchesCancelled:touches withEvent:event];
        check(gesture.state == UIGestureRecognizerStateCancelled && gesture.result == 0, @"cancellation executes nothing");

        [gesture reset];
        touch.point = CGPointMake(30, 20);
        [gesture touchesBegan:touches withEvent:event];
        UIWindow *replacement = [UIWindow new];
        toolbar.window = replacement;
        [gesture touchesMoved:touches withEvent:event];
        check(gesture.state == UIGestureRecognizerStateFailed, @"rejects moved source window");
        toolbar.window = window;

        [gesture reset];
        [gesture touchesBegan:touches withEvent:event];
        button.accessibilityIdentifier = @"pasteAction:";
        check([gesture.sourceIdentifier isEqual:@"copyAction:"], @"retains original button identity");
        button.accessibilityIdentifier = @"copyAction:";
        [gesture reset];
        check(!gesture.sourceButton && !gesture.sourceWindow && !gesture.sourceIdentifier && !gesture.result, @"cleans each session");

        UITouch *second = [UITouch new];
        event.allTouches = [NSSet setWithObjects:touch, second, nil];
        [gesture touchesBegan:touches withEvent:event];
        check(gesture.state == UIGestureRecognizerStateFailed, @"rejects multiple fingers");
        event.allTouches = touches;
        [gesture reset];
        touch.point = CGPointMake(30, 20);
        [gesture touchesBegan:touches withEvent:event];
        touch.point = CGPointMake(45, 20);
        [gesture touchesMoved:touches withEvent:event];
        event.allTouches = [NSSet setWithObjects:touch, second, nil];
        [gesture touchesBegan:[NSSet setWithObject:second] withEvent:event];
        check(gesture.state == UIGestureRecognizerStateCancelled, @"second finger cancels active drag");
        [gesture touchesEnded:touches withEvent:event];
        check(gesture.state == UIGestureRecognizerStateCancelled && gesture.result == 0, @"lift after cancellation stays terminal");
        [gesture touchesMoved:touches withEvent:event];
        check(gesture.state == UIGestureRecognizerStateCancelled, @"late moves cannot reopen a cancelled session");
        printf("PASS: %lu production recognizer state checks\n", (unsigned long)checks);
    }
    return 0;
}
