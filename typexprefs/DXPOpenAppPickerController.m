#import "DXPOpenAppPickerController.h"
#import "DXPAppInfo.h"
#import "AltList/ATLApplicationSection.h"
#import "AltList/LSApplicationProxy+AltList.h"
#import "../common.h"

static NSBundle *tweakBundle;

@implementation DXPOpenAppPickerController

- (instancetype)init {
    // User apps first, system apps second; both sections classify each proxy
    // by its applicationType string (never by enumeration order).
    ATLApplicationSection *user = [[ATLApplicationSection alloc] initNonCustomSectionWithType:SECTION_TYPE_USER];
    ATLApplicationSection *system = [[ATLApplicationSection alloc] initNonCustomSectionWithType:SECTION_TYPE_SYSTEM];
    return [super initWithSections:@[user, system]];
}

- (void)viewDidLoad {
    tweakBundle = [NSBundle bundleWithPath:bundlePath];
    [tweakBundle load];

    self.title = LOCALIZED(@"SELECT_APP");

    // Pushed programmatically, so there is no specifier carrying these keys;
    // set them before super so _setUpSearchBar picks them up.
    self.useSearchBar = YES;
    self.hideSearchBarWhileScrolling = NO;
    self.includeIdentifiersInSearch = YES;
    self.showIdentifiersAsSubtitle = YES;

    [super viewDidLoad];
}

// No specifier/getter exists in the programmatic flow; seed the checkmark
// anchor from the editor's current value instead.
- (void)loadPreferences {
    self.selectedApplicationID = self.selectedBundleIdentifier;
}

// The editor owns persistence: report the tapped app instead of writing
// defaults. ATLApplicationListSelectionController calls this from
// -tableView:didSelectRowAtIndexPath: right after updating the checkmark.
- (void)savePreferences {
    NSString *selected = self.selectedApplicationID;
    if (!self.completion || selected.length == 0) return;

    NSString *name = selected;
    @try {
        LSApplicationProxy *proxy = [LSApplicationProxy applicationProxyForIdentifier:selected];
        NSString *resolvedName = proxy.atl_nameToDisplay;
        if (resolvedName.length > 0) name = resolvedName;
    } @catch (__unused NSException *exception) {
        // Fall back to the raw bundle ID.
    }

    DXPAppInfo *app = [[DXPAppInfo alloc] init];
    app.bundleID = selected;
    app.name = name;
    self.completion(app);
}

// Match the old picker's flow: picking an app returns to the editor at once.
- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [super tableView:tableView didSelectRowAtIndexPath:indexPath];
    [self.navigationController popViewControllerAnimated:YES];
}

@end
