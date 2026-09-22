#import "DXPRootListController.h"
#import <spawn.h>
#import "../common.h"
#import "../DXHelper.h"
#import "../DXShortcutsGenerator.h"

static UISearchController *searchController;
static NSBundle *tweakBundle;


@implementation DXPRootListController

- (NSArray *)specifiers {
    if (!_specifiers) {
        NSMutableArray *loadedSpecifiers = [[self loadSpecifiersFromPlistName:@"Root" target:self] mutableCopy];
        if ([DXShortcutsGenerator isShellXScreenshotAvailable]) {
            _specifiers = loadedSpecifiers;
        } else {
            NSMutableArray *filteredSpecifiers = [NSMutableArray arrayWithCapacity:loadedSpecifiers.count];
            for (PSSpecifier *specifier in loadedSpecifiers) {
                NSString *identifier = [specifier propertyForKey:@"id"];
                NSString *preferenceKey = [specifier propertyForKey:@"key"];
                BOOL isShellXScreenshotSetting =
                    [identifier isEqualToString:@"shellxScreenshotKeyboardGroup"] ||
                    [preferenceKey isEqualToString:kShellXScreenshotHideKeyboardKey];
                if (!isShellXScreenshotSetting) [filteredSpecifiers addObject:specifier];
            }
            _specifiers = filteredSpecifiers;
        }
        
        self.dynamicSpecifiers = (!self.dynamicSpecifiers) ? [[NSMutableDictionary alloc] init] : self.dynamicSpecifiers;
    }
    
    
    return _specifiers;
}

#pragma mark - 生效应用（AltList 多选页 get/set）

// 历史版本把 pasteimagechipapps 存成 bundleID→@YES 字典，AltList 多选页存
// 已开启 bundleID 数组。读取侧统一规整成数组（只在内存转换，不回写，首次
// 拨动开关时自然落盘为新格式）；tweak 侧（DXPasteChip）两种格式都认。
- (id)dxp_pasteChipAppsRead:(PSSpecifier *)specifier {
    id value = [self readPreferenceValue:specifier];
    if ([value isKindOfClass:[NSArray class]]) return value;
    if (![value isKindOfClass:[NSDictionary class]]) return @[];

    NSMutableArray<NSString *> *enabled = [NSMutableArray array];
    for (NSString *bundleID in value) {
        NSNumber *flag = value[bundleID];
        if ([bundleID isKindOfClass:[NSString class]] &&
            [flag isKindOfClass:[NSNumber class]] && flag.boolValue) {
            [enabled addObject:bundleID];
        }
    }
    return enabled;
}

// setPreferenceValue:specifier: 负责域写入；这里显式补发 prefschanged，
// 保证键盘进程立刻感知（与各开关的 PostNotification 等效，双发无害）。
- (void)dxp_pasteChipAppsWrite:(id)value specifier:(PSSpecifier *)specifier {
    [self setPreferenceValue:value specifier:specifier];

    CFStringRef notificationName = (__bridge CFStringRef)kPrefsChangedIdentifier;
    if (notificationName) {
        CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(), notificationName, NULL, NULL, YES);
    }
}

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
    
    
    CGFloat headerWidth = self.table.bounds.size.width;
    CGRect frame = CGRectMake(0, 0, headerWidth, 250);

    UIView *headerView = [[UIView alloc] initWithFrame:frame];
    headerView.backgroundColor = UIColor.clearColor;

    UIImage *headerImage = [[UIImage alloc]
                            initWithContentsOfFile:[[NSBundle bundleWithPath:bundlePath] pathForResource:@"TypeX512" ofType:@"png"]];

    // shadow container + rounded inner view so the corners clip without cutting the shadow
    CGFloat iconSize = 120;
    UIView *iconContainer = [[UIView alloc] initWithFrame:CGRectMake((headerWidth - iconSize) / 2.0, 28, iconSize, iconSize)];
    iconContainer.backgroundColor = UIColor.clearColor;
    iconContainer.layer.shadowColor = [UIColor blackColor].CGColor;
    iconContainer.layer.shadowOpacity = 0.35;
    iconContainer.layer.shadowRadius = 12;
    iconContainer.layer.shadowOffset = CGSizeMake(0, 6);
    iconContainer.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin | UIViewAutoresizingFlexibleRightMargin;

    UIImageView *imageView = [[UIImageView alloc] initWithFrame:iconContainer.bounds];
    [imageView setImage:headerImage];
    [imageView setContentMode:UIViewContentModeScaleAspectFit];
    imageView.layer.cornerRadius = iconSize * 0.225;
    imageView.layer.masksToBounds = YES;
    [iconContainer addSubview:imageView];
    [headerView addSubview:iconContainer];

    CGRect labelFrame = CGRectMake(0, iconContainer.frame.origin.y + iconSize + 14, headerWidth, 52);
    UIFont *font = nil;
    if (@available(iOS 13.0, *)) {
        UIFontDescriptor *desc = [[UIFontDescriptor preferredFontDescriptorWithTextStyle:UIFontTextStyleLargeTitle]
                                  fontDescriptorWithDesign:UIFontDescriptorSystemDesignRounded];
        font = [UIFont fontWithDescriptor:desc size:36];
    }
    if (!font) font = [UIFont systemFontOfSize:36 weight:UIFontWeightBold];

    UILabel *headerLabel = [[UILabel alloc] initWithFrame:labelFrame];
    [headerLabel setText:@"TypeX"];
    [headerLabel setFont:font];
    if (@available(iOS 13.0, *)) {
        [headerLabel setTextColor:[UIColor colorWithDynamicProvider:^UIColor *(UITraitCollection *traitCollection) {
            return traitCollection.userInterfaceStyle == UIUserInterfaceStyleDark
                ? [UIColor colorWithRed:1.0 green:1.0 blue:1.0 alpha:0.92]
                : [UIColor colorWithRed:0.10 green:0.10 blue:0.12 alpha:1.00];
        }]];
    } else {
        [headerLabel setTextColor:[UIColor darkGrayColor]];
    }
    headerLabel.textAlignment = NSTextAlignmentCenter;
    headerLabel.adjustsFontSizeToFitWidth = YES;
    headerLabel.minimumScaleFactor = 0.7;
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
