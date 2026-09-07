#import "DXPNativeColorCell.h"
#import "DXPCustomizationController.h"
#import "../common.h"
#import "../DXPrefsManager.h"

@implementation DXPNativeColorCell

- (id)initWithStyle:(UITableViewCellStyle)style
    reuseIdentifier:(NSString *)reuseIdentifier
         specifier:(PSSpecifier *)specifier {
    self = [super initWithStyle:style reuseIdentifier:reuseIdentifier specifier:specifier];
    if (self) {
        self.colorSwatch = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 29, 29)];
        self.colorSwatch.layer.cornerRadius = 14.5;
        self.colorSwatch.layer.borderColor = [UIColor separatorColor].CGColor;
        self.colorSwatch.layer.borderWidth = 0.5;
        self.colorSwatch.clipsToBounds = YES;
        self.accessoryView = self.colorSwatch;
        [self updateSwatchColor];
    }
    return self;
}

- (void)updateSwatchColor {
    NSString *key = [self.specifier propertyForKey:@"key"];
    NSString *fallback = [self.specifier propertyForKey:@"fallback"] ?: @"#5B5B5B";
    NSString *hex = [[DXPrefsManager sharedInstance] getValueForKey:key];
    self.colorSwatch.backgroundColor = DXColorFromHex(hex, fallback);
}

// Walk the responder chain to find the owning PSListController
- (UIViewController *)parentListController {
    UIResponder *responder = self;
    while ((responder = [responder nextResponder])) {
        if ([responder isKindOfClass:[UIViewController class]]) {
            return (UIViewController *)responder;
        }
    }
    return nil;
}

- (void)setSelected:(BOOL)selected animated:(BOOL)animated {
    [super setSelected:selected animated:animated];
    if (selected) {
        UIViewController *ctrl = [self parentListController];
        if ([ctrl isKindOfClass:[DXPCustomizationController class]]) {
            DXPCustomizationController *customCtrl = (DXPCustomizationController *)ctrl;
            NSString *key = [self.specifier propertyForKey:@"key"];
            [customCtrl presentSystemColorPickerForKey:key];
        }
    }
}

- (void)refreshCellContentsWithSpecifier:(PSSpecifier *)specifier {
    [super refreshCellContentsWithSpecifier:specifier];
    [self updateSwatchColor];
}

@end
