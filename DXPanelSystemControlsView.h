#import <UIKit/UIKit.h>
#import "DXPanelControlLayout.h"

@interface DXPanelSystemControlsView : UIView
@property(nonatomic, copy) void (^actionHandler)(NSString *action, NSNumber *value);
- (void)configureDark:(BOOL)dark preview:(BOOL)preview;
- (void)applyState:(NSDictionary *)state busy:(BOOL)busy;
- (void)showMessage:(NSString *)message;
@end
