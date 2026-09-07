#import <Preferences/PSTableCell.h>
#import <Preferences/PSSpecifier.h>
#import <UIKit/UIKit.h>

// A custom PSTableCell that shows a color swatch and presents
// UIColorPickerViewController when tapped.
// Used in DXPCustomizationController for all color-picker rows.
@interface DXPNativeColorCell : PSTableCell
@property (nonatomic, strong) UIView *colorSwatch;
@end
