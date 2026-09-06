#import "DXPPasteOptions.h"
#import "../DXHelper.h"
#import "../common.h"


static NSBundle *tweakBundle;

@implementation DXPPasteOptions

- (NSArray *)specifiers {
    if (!_specifiers) {
        NSMutableArray *snippetEntrySpecifiers = [[NSMutableArray alloc] init];
        
        PSSpecifier *safariSpecGroup = [PSSpecifier preferenceSpecifierNamed:LOCALIZED(@"SAFARI") target:nil set:nil get:nil detail:nil cell:PSGroupCell edit:nil];
        [safariSpecGroup setProperty:LOCALIZED(@"FOOTER_SAFARI") forKey:@"footerText"];
        [snippetEntrySpecifiers addObject:safariSpecGroup];
        
        
        PSSpecifier *pasteAndGoTypeSpec = [PSSpecifier preferenceSpecifierNamed:LOCALIZED(@"PASTE_AND_GO") target:self set:@selector(setPreferenceValue:specifier:) get:@selector(readPreferenceValue:) detail:nil cell:PSSegmentCell edit:nil];
        [pasteAndGoTypeSpec setValues:@[@(0), @(1), @(2)] titles:@[LOCALIZED(@"PASTE_AND_GO_DISABLED"), LOCALIZED(@"PASTE_AND_GO_URL_ONLY"), LOCALIZED(@"PASTE_AND_GO_EVERYTHING")]];
        [pasteAndGoTypeSpec setProperty:@2 forKey:@"default"];
        [pasteAndGoTypeSpec setProperty:DXScopedPreferenceKey(kPasteAndGoEnabledkey, self.configuration) forKey:@"key"];
        [pasteAndGoTypeSpec setProperty:kIdentifier forKey:@"defaults"];
        [pasteAndGoTypeSpec setProperty:kPrefsChangedIdentifier forKey:@"PostNotification"];
        [snippetEntrySpecifiers addObject:pasteAndGoTypeSpec];
        
        _specifiers = snippetEntrySpecifiers;
        
    }
    
    return _specifiers;
}

- (void)viewDidLoad {
    tweakBundle = [NSBundle bundleWithPath:bundlePath];
    [tweakBundle load];
    [super viewDidLoad];
}

@end
