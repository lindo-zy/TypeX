#import <UIKit/UIKit.h>

@interface DXPKeyboardPanelPreviewHeader : UIView
- (instancetype)initWithSide:(NSString *)side allowsSelection:(BOOL)allowsSelection;
- (void)refresh;
@end
