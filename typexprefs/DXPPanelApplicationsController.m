#import "DXPPanelApplicationsController.h"
#import "../DXPrefsManager.h"
#import "../DXPanelRegistry.h"

@implementation DXPPanelApplicationsController
- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [self reloadSpecifiers];
}
- (id)readApplicationEnabled:(PSSpecifier *)specifier {
    return @(DXPanelApplicationEnabled([DXPrefsManager.sharedInstance readPrefs],
        [self.specifier propertyForKey:@"panelSelector"], [specifier propertyForKey:@"applicationIdentifier"]));
}
- (void)setApplicationEnabled:(NSNumber *)enabled specifier:(PSSpecifier *)specifier {
    NSMutableDictionary *preferences = [[DXPrefsManager.sharedInstance readPrefs] mutableCopy];
    if (DXPanelSetApplicationEnabled(preferences, [self.specifier propertyForKey:@"panelSelector"],
        [specifier propertyForKey:@"applicationIdentifier"], specifier.name, enabled.boolValue)) {
        [DXPrefsManager.sharedInstance writePrefs:preferences];
    }
}
- (PSSpecifier *)createGroupSpecifierForApplicationSection:(ATLApplicationSection *)section {
    PSSpecifier *group = [super createGroupSpecifierForApplicationSection:section];
    [group setProperty:[self localizedStringForString:@"PANEL_APPLICATIONS_FOOTER"] forKey:@"footerText"];
    return group;
}
@end
