#import <Preferences/PSListController.h>
#import <Preferences/PSSpecifier.h>
#import <Preferences/Preferences.h>


@interface PSListController (TypeX)
-(void)setPreferenceValue:(id)value forSpecifier:(PSSpecifier*)specifier;
- (void)setCellForRowAtIndexPath:(NSIndexPath *)indexPath enabled:(BOOL)enabled;
@end

@interface DXPCustomizationController : PSListController <UISearchBarDelegate>
 @property (nonatomic, retain) NSMutableDictionary *dynamicSpecifiers;
@end
