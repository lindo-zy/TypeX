#import <Preferences/PSListController.h>
#import <Preferences/PSSpecifier.h>

@interface DXPPasteOptions : PSListController <UISearchBarDelegate>
@property (nonatomic, copy) NSString *configuration;
@end

@interface PSSpecifier (DXPPasteOptions)
-(void)setValues:(id)arg1 titles:(id)arg2;
@end
