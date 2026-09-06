#import <Preferences/PSListController.h>
#import <Preferences/PSSpecifier.h>

@interface DXPDeleteOptions : PSListController <UISearchBarDelegate>
@property (nonatomic,readwrite) NSString *entryID;
@property (nonatomic, copy) NSString *configuration;
@end
