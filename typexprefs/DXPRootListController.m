#import "DXPRootListController.h"
#import <spawn.h>
#import "../common.h"
#import "../DXHelper.h"

static UISearchController *searchController;
static NSBundle *tweakBundle;


@implementation DXPRootListController

- (NSArray *)specifiers {
    if (!_specifiers) {
        _specifiers = [self loadSpecifiersFromPlistName:@"Root" target:self];
        
        self.dynamicSpecifiers = (!self.dynamicSpecifiers) ? [[NSMutableDictionary alloc] init] : self.dynamicSpecifiers;
    }
    
    
    return _specifiers;
}
/*
 -(void)reloadSpecifiers {
 [super reloadSpecifiers];
 
    NSDictionary *preferences = [[DXPrefsManager sharedInstance] readPrefs];
 if(![preferences[@"toastBOOL"] boolValue]) {
 [self removeContiguousSpecifiers:@[self.dynamicSpecifiers[@"pyslider"]] animated:YES];
 [self removeContiguousSpecifiers:@[self.dynamicSpecifiers[@"timerslider"]] animated:YES];
 }
 }
 
 
 */

-(void)viewDidLoad  {
    tweakBundle = [NSBundle bundleWithPath:bundlePath];
    [tweakBundle load];
    [super viewDidLoad];
    
    //search bar
    
    searchController = [[UISearchController alloc] initWithSearchResultsController:nil];
    searchController.definesPresentationContext = YES;
    searchController.hidesNavigationBarDuringPresentation = YES;
    //searchController.searchBar.delegate = self;
    searchController.searchBar.placeholder = LOCALIZED(@"SEARCHBAR_PLACEHOLDER");
    [searchController.searchBar setImage:[DXHelper imageForTypeXWithPlaceholder:YES] forSearchBarIcon:UISearchBarIconSearch state:UIControlStateNormal];
    
    searchController.obscuresBackgroundDuringPresentation = NO;
    
    if (@available(iOS 11.0, *)){
        self.navigationItem.searchController = searchController;
        self.navigationItem.hidesSearchBarWhenScrolling = YES;
    }
    //search bar
    
    
    CGRect frame = CGRectMake(0,0,self.table.bounds.size.width,170);
    CGRect Imageframe = CGRectMake(0,10,self.table.bounds.size.width,80);
    
    
    UIView *headerView = [[UIView alloc] initWithFrame:frame];
    headerView.backgroundColor = [UIColor colorWithRed: 0.20 green: 0.20 blue: 0.20 alpha: 1.00];

    //UIImage *headerImage = [UIImage systemImageNamed:@"doc.on.doc"];
    
    
    UIImage *headerImage = [[UIImage alloc]
                            initWithContentsOfFile:[[NSBundle bundleWithPath:bundlePath] pathForResource:@"TypeX512" ofType:@"png"]];
    UIImageView *imageView = [[UIImageView alloc] initWithFrame:Imageframe];
    [imageView setImage:headerImage];
    [imageView setContentMode:UIViewContentModeScaleAspectFit];
    [imageView setAutoresizingMask:UIViewAutoresizingFlexibleWidth];
    [headerView addSubview:imageView];
    
    CGRect labelFrame = CGRectMake(0,imageView.frame.origin.y + 90 ,self.table.bounds.size.width,80);
    UIFont *font = [UIFont fontWithName:@"HelveticaNeue-Light" size:40];
    UILabel *headerLabel = [[UILabel alloc] initWithFrame:labelFrame];
    [headerLabel setText:@"TypeX"];
    [headerLabel setFont:font];
    [headerLabel setTextColor:[UIColor colorWithRed: 0.60 green: 0.60 blue: 0.60 alpha: 1.00]];
    headerLabel.textAlignment = NSTextAlignmentCenter;
    [headerLabel setContentMode:UIViewContentModeScaleAspectFit];
    [headerLabel setAutoresizingMask:UIViewAutoresizingFlexibleWidth];
    [headerView addSubview:headerLabel];
    
    
    self.table.tableHeaderView = headerView;
    
    self.respringBtn = [[UIBarButtonItem alloc] initWithTitle:LOCALIZED(@"RESPRING") style:UIBarButtonItemStylePlain target:self action:@selector(respring)];
    //self.addSnippetBtn.tintColor = [UIColor blackColor];
    self.navigationItem.rightBarButtonItem = self.respringBtn;
    
}

-(id)readPreferenceValue:(PSSpecifier*)specifier{
    NSString *key = [specifier propertyForKey:@"key"];
    id value = [super readPreferenceValue:specifier];
    if (key.length > 0) {
        id storedValue = [[DXPrefsManager sharedInstance] getValueForKey:key];
        if (storedValue != nil) value = storedValue;
    }
    return value;
}


- (void)setPreferenceValue:(id)value specifier:(PSSpecifier *)specifier{
    NSString *key = [specifier propertyForKey:@"key"];
    if (key.length > 0) {
        // Keep PreferenceLoader UI writes on the same CFPreferences/plist path
        // used by SpringBoard and the keyboard process.
        [[DXPrefsManager sharedInstance] setValue:value forKey:key];
    } else {
        [super setPreferenceValue:value specifier:specifier];
    }
}

- (void)donation {
    [[UIApplication sharedApplication] openURL:[NSURL URLWithString:@"https://www.paypal.me/udevs"] options:@{} completionHandler:nil];
}

- (void)twitter {
    [[UIApplication sharedApplication] openURL:[NSURL URLWithString:@"https://twitter.com/udevs9"] options:@{} completionHandler:nil];
}

- (void)reddit {
    [[UIApplication sharedApplication] openURL:[NSURL URLWithString:@"https://www.reddit.com/user/h4roldj"] options:@{} completionHandler:nil];
}

- (void)respring {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"TypeX" message:LOCALIZED(@"RESPRING_MESSAGE") preferredStyle:UIAlertControllerStyleAlert];
    
    UIAlertAction *respringAction = [UIAlertAction actionWithTitle:LOCALIZED(@"ANSWER_YES") style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        
        NSURL *relaunchURL = [NSURL URLWithString:@"prefs:root=TypeX"];
        SBSRelaunchAction *restartAction = [NSClassFromString(@"SBSRelaunchAction") actionWithReason:@"RestartRenderServer" options:4 targetURL:relaunchURL];
        [[NSClassFromString(@"FBSSystemService") sharedService] sendActions:[NSSet setWithObject:restartAction] withResult:nil];
        
        /*
         pid_t pid;
         int status;
         const char *args[] = {"killall", "-9", "SpringBoard", NULL};
         posix_spawn(&pid, "/usr/bin/killall", NULL, NULL, (char * const *)args, NULL);
         waitpid(pid, &status, WEXITED);
         */
    }];
    
    UIAlertAction *cancelAction = [UIAlertAction actionWithTitle:LOCALIZED(@"ANSWER_NO") style:UIAlertActionStyleCancel handler:^(UIAlertAction *action) {
        [self dismissViewControllerAnimated:YES completion:nil];
    }];
    
    [alert addAction:respringAction];
    [alert addAction:cancelAction];
    
    [self presentViewController:alert animated:YES completion:nil];
}

-(BOOL)searchBarShouldBeginEditing:(UISearchBar *)searchBar{
    DXPrefsManager *prefsManager = [DXPrefsManager sharedInstance];
    NSUInteger tappedCount = [[prefsManager getValueForKey:@"searchedc"] longValue];
    [prefsManager setValue:@(tappedCount + 1) forKey:@"searchedc"];
    if (tappedCount + 1 == searchedCountEaster){
        [DXHelper showSearchCountEasterAlertFor:self searchController:searchController count:tappedCount+1 delay:0.5];
    }
    return YES;
}

@end
