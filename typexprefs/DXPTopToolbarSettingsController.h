#import <Preferences/PSListController.h>
#import <Preferences/PSSpecifier.h>

@interface DXPTopToolbarSettingsController : PSListController <UIColorPickerViewControllerDelegate, UITextFieldDelegate>
@property(nonatomic, strong) UIView *topToolbarPreview;
@property(nonatomic, strong) UITextField *previewTextField;
@property(nonatomic, copy) NSString *pendingColorKey;
- (void)presentSystemColorPickerForKey:(NSString *)key;
@end
