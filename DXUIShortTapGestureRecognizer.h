#import <UIKit/UIGestureRecognizerSubclass.h>

#define UISHORT_TAP_MAX_DELAY 0.2

@interface DXUIShortTapGestureRecognizer : UITapGestureRecognizer
/// Window after touchesBegan within which the tap must complete before it is
/// force-failed.  Defaults to the short-tap window; raise it above the
/// double-tap window when this recognizer waits for a double tap to fail, so
/// the double tap's failure is always processed first.
@property (nonatomic, assign) NSTimeInterval forcedFailureDelay;
@end
