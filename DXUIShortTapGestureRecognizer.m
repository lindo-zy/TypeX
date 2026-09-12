#import "common.h"
#import "DXUIShortTapGestureRecognizer.h"

@implementation DXUIShortTapGestureRecognizer{
    NSUInteger _touchGeneration;
}

- (NSTimeInterval)forcedFailureDelay {
    return _forcedFailureDelay > 0 ? _forcedFailureDelay : UISHORT_TAP_MAX_DELAY;
}

- (void)touchesBegan:(NSSet *)touches withEvent:(UIEvent *)event
{
    [super touchesBegan:touches withEvent:event];
    // Each new touch invalidates the failure timer scheduled by the previous
    // touch.  Without this guard a rapid second tap is force-failed mid-gesture
    // by the timer left over from the first tap, forcing the user to pause
    // longer than the short-tap window between consecutive taps.
    NSUInteger generation = ++_touchGeneration;
    NSTimeInterval delay = self.forcedFailureDelay;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(delay * NSEC_PER_SEC)), dispatch_get_main_queue(), ^
    {
        if (generation != self->_touchGeneration) return;
        // Enough time has passed and the gesture was not recognized -> It has failed.
        if  (self.state != UIGestureRecognizerStateRecognized)
        {
            self.state = UIGestureRecognizerStateFailed;
        }
    });
}

@end
