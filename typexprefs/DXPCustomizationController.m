#import "DXPCustomizationController.h"
#import "../common.h"
#import "../DXHelper.h"

static UISearchController *searchController;
static NSBundle *tweakBundle;

@interface DXPCustomizationController ()
@property(nonatomic, strong) UIView *topToolbarPreview;
@end


@implementation DXPCustomizationController

- (NSArray *)specifiers {
    if (!_specifiers) {
        _specifiers = [self loadSpecifiersFromPlistName:@"Customization" target:self];
        
        NSArray *dynamicCell = @[@"pyslider", @"timerslider",@"shortcutstintpicker",@"toasttintpicker",@"toastbackgroundtintpicker", @"granularityslider", @"displaytypeselection", @"gesturetypeselection", @"gesturebuttonselection",@"shortcutstintselection", @"toasttintselection", @"toastbackgroundtintselection", @"shortcutsbackgroundtintpicker", @"shortcutsbackgroundtintselection", @"toptoolbarbackgroundtintpicker", @"toptoolbarbackgroundselection"];
        self.dynamicSpecifiers = (!self.dynamicSpecifiers) ? [[NSMutableDictionary alloc] init] : self.dynamicSpecifiers;
        for(PSSpecifier *specifier in _specifiers) {
            if([dynamicCell containsObject:[specifier propertyForKey:@"id"]]) {
                [self.dynamicSpecifiers setObject:specifier forKey:[specifier propertyForKey:@"id"]];
            }
        }
    }
    
    
    return _specifiers;
}

-(void)viewDidLoad  {
    tweakBundle = [NSBundle bundleWithPath:bundlePath];
    [tweakBundle load];
    [super viewDidLoad];

    [self buildTopToolbarPreview];
    
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
    
    NSDictionary *preferences = [[DXPrefsManager sharedInstance] readPrefs];
    if(![preferences[@"colorBOOL"] boolValue]){
        [(PSSpecifier *)self.dynamicSpecifiers[@"shortcutstintpicker"] setProperty:@NO forKey:@"enabled"];
        [(PSSpecifier *)self.dynamicSpecifiers[@"toasttintpicker"] setProperty:@NO forKey:@"enabled"];
        [(PSSpecifier *)self.dynamicSpecifiers[@"toastbackgroundtintpicker"] setProperty:@NO forKey:@"enabled"];
        [(PSSpecifier *)self.dynamicSpecifiers[@"shortcutsbackgroundtintpicker"] setProperty:@NO forKey:@"enabled"];

        [(PSSpecifier *)self.dynamicSpecifiers[@"shortcutstintselection"] setProperty:@NO forKey:@"enabled"];
        [(PSSpecifier *)self.dynamicSpecifiers[@"toasttintselection"] setProperty:@NO forKey:@"enabled"];
        [(PSSpecifier *)self.dynamicSpecifiers[@"toastbackgroundtintselection"] setProperty:@NO forKey:@"enabled"];
        [(PSSpecifier *)self.dynamicSpecifiers[@"shortcutsbackgroundtintselection"] setProperty:@NO forKey:@"enabled"];
        [(PSSpecifier *)self.dynamicSpecifiers[@"toptoolbarbackgroundtintpicker"] setProperty:@NO forKey:@"enabled"];
        [(PSSpecifier *)self.dynamicSpecifiers[@"toptoolbarbackgroundselection"] setProperty:@NO forKey:@"enabled"];
        
        [self reloadSpecifier:(PSSpecifier *)self.dynamicSpecifiers[@"shortcutstintpicker"] animated:NO];
        [self reloadSpecifier:(PSSpecifier *)self.dynamicSpecifiers[@"toasttintpicker"] animated:NO];
        [self reloadSpecifier:(PSSpecifier *)self.dynamicSpecifiers[@"toastbackgroundtintpicker"] animated:NO];
        [self reloadSpecifier:(PSSpecifier *)self.dynamicSpecifiers[@"shortcutsbackgroundtintpicker"] animated:NO];

        [self reloadSpecifier:(PSSpecifier *)self.dynamicSpecifiers[@"shortcutstintselection"] animated:NO];
        [self reloadSpecifier:(PSSpecifier *)self.dynamicSpecifiers[@"toasttintselection"] animated:NO];
        [self reloadSpecifier:(PSSpecifier *)self.dynamicSpecifiers[@"toastbackgroundtintselection"] animated:NO];
        [self reloadSpecifier:(PSSpecifier *)self.dynamicSpecifiers[@"shortcutsbackgroundtintselection"] animated:NO];
        [self reloadSpecifier:(PSSpecifier *)self.dynamicSpecifiers[@"toptoolbarbackgroundtintpicker"] animated:NO];
        [self reloadSpecifier:(PSSpecifier *)self.dynamicSpecifiers[@"toptoolbarbackgroundselection"] animated:NO];
    }
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [self updateTopToolbarPreview];
}

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    UIView *header = self.table.tableHeaderView;
    if (!header) return;
    CGFloat width = CGRectGetWidth(self.table.bounds);
    if (fabs(CGRectGetWidth(header.frame) - width) > 0.5) {
        header.frame = CGRectMake(0.0, 0.0, width, 136.0);
        self.table.tableHeaderView = header;
    }
    self.topToolbarPreview.frame = CGRectMake(16.0, 30.0, MAX(0.0, width - 32.0), 30.0);
    self.previewTextField.frame = CGRectMake(16.0, 93.0, MAX(0.0, width - 32.0), 36.0);
    [self updateTopToolbarPreview];
}

- (void)buildTopToolbarPreview {
    CGFloat width = CGRectGetWidth(self.table.bounds);
    UIView *header = [[UIView alloc] initWithFrame:CGRectMake(0.0, 0.0, width, 136.0)];
    header.autoresizingMask = UIViewAutoresizingFlexibleWidth;
    UILabel *title = [[UILabel alloc] initWithFrame:CGRectMake(16.0, 7.0, width - 32.0, 18.0)];
    title.text = LOCALIZED(@"TOP_TOOLBAR_PREVIEW");
    title.font = [UIFont systemFontOfSize:13.0 weight:UIFontWeightSemibold];
    title.textColor = [UIColor secondaryLabelColor];
    [header addSubview:title];

    self.topToolbarPreview = [[UIView alloc] initWithFrame:CGRectMake(16.0, 30.0, MAX(0.0, width - 32.0), 30.0)];
    self.topToolbarPreview.layer.cornerRadius = 6.0;
    self.topToolbarPreview.clipsToBounds = YES;
    [header addSubview:self.topToolbarPreview];
    for (NSUInteger index = 0; index < 6; index++) {
        UIView *button = [[UIView alloc] initWithFrame:CGRectZero];
        button.tag = 100 + index;
        button.backgroundColor = [UIColor colorWithWhite:1.0 alpha:0.22];
        button.layer.cornerRadius = 4.0;
        [self.topToolbarPreview addSubview:button];
    }

    // ── Test input field ──
    UILabel *fieldTitle = [[UILabel alloc] initWithFrame:CGRectMake(16.0, 70.0, width - 32.0, 18.0)];
    fieldTitle.text = LOCALIZED(@"TEST_INPUT_HINT") ?: @"测试输入框（点击弹出键盘预览）";
    fieldTitle.font = [UIFont systemFontOfSize:13.0 weight:UIFontWeightSemibold];
    fieldTitle.textColor = [UIColor secondaryLabelColor];
    [header addSubview:fieldTitle];

    self.previewTextField = [[UITextField alloc] initWithFrame:CGRectMake(16.0, 93.0, MAX(0.0, width - 32.0), 36.0)];
    self.previewTextField.placeholder = LOCALIZED(@"TEST_INPUT_PLACEHOLDER") ?: @"点击此处弹出键盘…";
    self.previewTextField.font = [UIFont systemFontOfSize:15.0];
    self.previewTextField.borderStyle = UITextBorderStyleRoundedRect;
    self.previewTextField.delegate = self;
    self.previewTextField.returnKeyType = UIReturnKeyDone;
    self.previewTextField.clearButtonMode = UITextFieldViewModeWhileEditing;
    [header addSubview:self.previewTextField];

    self.table.tableHeaderView = header;
}

- (void)updateTopToolbarPreview {
    NSDictionary *preferences = [[DXPrefsManager sharedInstance] readPrefs];
    UIColor *background = DXColorFromHex(preferences[@"toptoolbarbackgroundtint"], @"#5B5B5B");
    self.topToolbarPreview.backgroundColor = background;
    CGFloat width = CGRectGetWidth(self.topToolbarPreview.bounds);
    CGFloat gap = 4.0;
    CGFloat buttonWidth = (width - gap * 7.0) / 6.0;
    [self.topToolbarPreview.subviews enumerateObjectsUsingBlock:^(UIView *button, NSUInteger index, BOOL *stop) {
        button.frame = CGRectMake(gap + index * (buttonWidth + gap), 5.0, buttonWidth, 20.0);
    }];
}

-(id)readPreferenceValue:(PSSpecifier*)specifier{
    
    NSString *key = [specifier propertyForKey:@"key"];
    id value = [super readPreferenceValue:specifier];
    if (key.length > 0) {
        id storedValue = [[DXPrefsManager sharedInstance] getValueForKey:key];
        if (storedValue != nil) value = storedValue;
    }
    if([key isEqualToString:@"colorBOOL"]){
        [(PSSpecifier *)self.dynamicSpecifiers[@"shortcutstintpicker"] setProperty:value forKey:@"enabled"];
        [(PSSpecifier *)self.dynamicSpecifiers[@"toasttintpicker"] setProperty:value forKey:@"enabled"];
        [(PSSpecifier *)self.dynamicSpecifiers[@"toastbackgroundtintpicker"] setProperty:value forKey:@"enabled"];
        [(PSSpecifier *)self.dynamicSpecifiers[@"shortcutsbackgroundtintpicker"] setProperty:value forKey:@"enabled"];
        
        [(PSSpecifier *)self.dynamicSpecifiers[@"shortcutstintselection"] setProperty:value forKey:@"enabled"];
        [(PSSpecifier *)self.dynamicSpecifiers[@"toasttintselection"] setProperty:value forKey:@"enabled"];
        [(PSSpecifier *)self.dynamicSpecifiers[@"toastbackgroundtintselection"] setProperty:value forKey:@"enabled"];
        [(PSSpecifier *)self.dynamicSpecifiers[@"shortcutsbackgroundtintselection"] setProperty:value forKey:@"enabled"];
        [(PSSpecifier *)self.dynamicSpecifiers[@"toptoolbarbackgroundtintpicker"] setProperty:value forKey:@"enabled"];
        [(PSSpecifier *)self.dynamicSpecifiers[@"toptoolbarbackgroundselection"] setProperty:value forKey:@"enabled"];

        //[self reloadSpecifier:(PSSpecifier *)self.dynamicSpecifiers[@"shortcutstintpicker"] animated:NO];
        //[self reloadSpecifier:(PSSpecifier *)self.dynamicSpecifiers[@"toasttintpicker"] animated:NO];
        //[self reloadSpecifier:(PSSpecifier *)self.dynamicSpecifiers[@"toastbackgroundtintpicker"] animated:NO];
        //[self reloadSpecifier:(PSSpecifier *)self.dynamicSpecifiers[@"shortcutsbackgroundtintpicker"] animated:NO];

        [self reloadSpecifier:(PSSpecifier *)self.dynamicSpecifiers[@"shortcutstintselection"] animated:NO];
        [self reloadSpecifier:(PSSpecifier *)self.dynamicSpecifiers[@"toasttintselection"] animated:NO];
        [self reloadSpecifier:(PSSpecifier *)self.dynamicSpecifiers[@"toastbackgroundtintselection"] animated:NO];
        [self reloadSpecifier:(PSSpecifier *)self.dynamicSpecifiers[@"shortcutsbackgroundtintselection"] animated:NO];

    }
    return value;
}


- (void)setPreferenceValue:(id)value specifier:(PSSpecifier *)specifier{
    NSString *key = [specifier propertyForKey:@"key"];
    if (key.length > 0) {
        [[DXPrefsManager sharedInstance] setValue:value forKey:key];
    } else {
        [super setPreferenceValue:value specifier:specifier];
    }

    // Always refresh the top-toolbar preview when any color-related key changes
    if ([key hasPrefix:@"toptoolbarbackground"] ||
        [key hasPrefix:@"shortcutstint"] ||
        [key hasPrefix:@"shortcutsbackgroundtint"] ||
        [key hasPrefix:@"toasttint"] ||
        [key hasPrefix:@"toastbackgroundtint"]) {
        [self updateTopToolbarPreview];
    }

    if([key isEqualToString:@"colorBOOL"]){
        [(PSSpecifier *)self.dynamicSpecifiers[@"shortcutstintpicker"] setProperty:value forKey:@"enabled"];
        [(PSSpecifier *)self.dynamicSpecifiers[@"toasttintpicker"] setProperty:value forKey:@"enabled"];
        [(PSSpecifier *)self.dynamicSpecifiers[@"toastbackgroundtintpicker"] setProperty:value forKey:@"enabled"];
        [(PSSpecifier *)self.dynamicSpecifiers[@"shortcutsbackgroundtintpicker"] setProperty:value forKey:@"enabled"];

        [(PSSpecifier *)self.dynamicSpecifiers[@"shortcutstintselection"] setProperty:value forKey:@"enabled"];
        [(PSSpecifier *)self.dynamicSpecifiers[@"toasttintselection"] setProperty:value forKey:@"enabled"];
        [(PSSpecifier *)self.dynamicSpecifiers[@"toastbackgroundtintselection"] setProperty:value forKey:@"enabled"];
        [(PSSpecifier *)self.dynamicSpecifiers[@"shortcutsbackgroundtintselection"] setProperty:value forKey:@"enabled"];
        [(PSSpecifier *)self.dynamicSpecifiers[@"toptoolbarbackgroundtintpicker"] setProperty:value forKey:@"enabled"];
        [(PSSpecifier *)self.dynamicSpecifiers[@"toptoolbarbackgroundselection"] setProperty:value forKey:@"enabled"];

        [self reloadSpecifier:(PSSpecifier *)self.dynamicSpecifiers[@"shortcutstintpicker"] animated:NO];
        [self reloadSpecifier:(PSSpecifier *)self.dynamicSpecifiers[@"toasttintpicker"] animated:NO];
        [self reloadSpecifier:(PSSpecifier *)self.dynamicSpecifiers[@"toastbackgroundtintpicker"] animated:NO];
        [self reloadSpecifier:(PSSpecifier *)self.dynamicSpecifiers[@"shortcutsbackgroundtintpicker"] animated:NO];

        [self reloadSpecifier:(PSSpecifier *)self.dynamicSpecifiers[@"shortcutstintselection"] animated:NO];
        [self reloadSpecifier:(PSSpecifier *)self.dynamicSpecifiers[@"toasttintselection"] animated:NO];
        [self reloadSpecifier:(PSSpecifier *)self.dynamicSpecifiers[@"toastbackgroundtintselection"] animated:NO];
        [self reloadSpecifier:(PSSpecifier *)self.dynamicSpecifiers[@"shortcutsbackgroundtintselection"] animated:NO];
        [self reloadSpecifier:(PSSpecifier *)self.dynamicSpecifiers[@"toptoolbarbackgroundtintpicker"] animated:NO];
        [self reloadSpecifier:(PSSpecifier *)self.dynamicSpecifiers[@"toptoolbarbackgroundselection"] animated:NO];

    }
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

// ── System UIColorPickerViewController ─────────────────────────────────

- (void)presentSystemColorPickerForKey:(NSString *)key {
    self.pendingColorKey = key;
    UIColorPickerViewController *vc = [[UIColorPickerViewController alloc] init];
    vc.delegate = self;
    vc.supportsAlpha = YES;

    NSString *hex = [[DXPrefsManager sharedInstance] getValueForKey:key];
    if (hex.length) {
        NSString *fallback = @"#5B5B5B";
        for (PSSpecifier *spec in self.specifiers) {
            if ([[spec propertyForKey:@"key"] isEqualToString:key]) {
                fallback = [spec propertyForKey:@"fallback"] ?: @"#5B5B5B";
                break;
            }
        }
        vc.selectedColor = DXColorFromHex(hex, fallback);
    }

    [self presentViewController:vc animated:YES completion:nil];
}

- (void)colorPickerViewControllerDidFinish:(UIColorPickerViewController *)viewController {
    // DXHexFromColor is defined in DXPNativeColorCell.m but we need it here too.
    // Inline the conversion to avoid cross-file static dependency.
    UIColor *color = viewController.selectedColor;
    CGFloat r = 0, g = 0, b = 0, a = 0;
    [color getRed:&r green:&g blue:&b alpha:&a];
    unsigned int ri = (unsigned int)(r * 255.0 + 0.5);
    unsigned int gi = (unsigned int)(g * 255.0 + 0.5);
    unsigned int bi = (unsigned int)(b * 255.0 + 0.5);
    unsigned int ai = (unsigned int)(a * 255.0 + 0.5);
    NSString *hex = (ai >= 255)
        ? [NSString stringWithFormat:@"#%02X%02X%02X", ri, gi, bi]
        : [NSString stringWithFormat:@"#%02X%02X%02X%02X", ai, ri, gi, bi];

    if (self.pendingColorKey.length) {
        [[DXPrefsManager sharedInstance] setValue:hex forKey:self.pendingColorKey];
        [self updateTopToolbarPreview];
    }
    self.pendingColorKey = nil;
}

- (void)colorPickerViewController:(UIColorPickerViewController *)viewController
       didSelectColor:(UIColor *)color
            continuously:(BOOL)continuously {
    if (!continuously) return;
    CGFloat r = 0, g = 0, b = 0, a = 0;
    [color getRed:&r green:&g blue:&b alpha:&a];
    unsigned int ri = (unsigned int)(r * 255.0 + 0.5);
    unsigned int gi = (unsigned int)(g * 255.0 + 0.5);
    unsigned int bi = (unsigned int)(b * 255.0 + 0.5);
    unsigned int ai = (unsigned int)(a * 255.0 + 0.5);
    NSString *hex = (ai >= 255)
        ? [NSString stringWithFormat:@"#%02X%02X%02X", ri, gi, bi]
        : [NSString stringWithFormat:@"#%02X%02X%02X%02X", ai, ri, gi, bi];

    if (self.pendingColorKey.length) {
        [[DXPrefsManager sharedInstance] setValue:hex forKey:self.pendingColorKey];
        [self updateTopToolbarPreview];
    }
}

#pragma mark - UITextFieldDelegate

- (BOOL)textFieldShouldReturn:(UITextField *)textField {
    [textField resignFirstResponder];
    return YES;
}

@end
