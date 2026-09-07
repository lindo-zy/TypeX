#import <Preferences/PSListController.h>
#import <Preferences/PSSpecifier.h>
#import <Preferences/Preferences.h>


@interface PSListController (TypeX)
-(void)setPreferenceValue:(id)value forSpecifier:(PSSpecifier*)specifier;
- (void)setCellForRowAtIndexPath:(NSIndexPath *)indexPath enabled:(BOOL)enabled;
@end

@interface DXPCustomizationController : PSListController <UISearchBarDelegate, UITextFieldDelegate, UIColorPickerViewControllerDelegate>
 @property (nonatomic, retain) NSMutableDictionary *dynamicSpecifiers;
@property(nonatomic, strong) UITextField *previewTextField;
@property(nonatomic, copy) NSString *pendingColorKey;
- (void)presentSystemColorPickerForKey:(NSString *)key;
@end
