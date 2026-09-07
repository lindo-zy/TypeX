#import <Preferences/PSListController.h>
#import <Preferences/PSSpecifier.h>
#import <UIKit/UIKit.h>

// A custom PSTableCell that shows a color swatch and pushes
// DXPTopToolbarColorPickerPushAction when tapped.
@interface DXPTopToolbarNativeColorCell : PSTableCell
@property (nonatomic, strong) UIView *colorSwatch;
@end
