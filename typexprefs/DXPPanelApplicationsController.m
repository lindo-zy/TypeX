#import "DXPPanelApplicationsController.h"
#import "../DXPrefsManager.h"
#import "../DXPanelRegistry.h"

@implementation DXPPanelApplicationsController
- (void)viewDidLoad {
    [super viewDidLoad];
    [self.table setEditing:YES animated:NO];
}
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
    [self reloadSpecifiers];
}
- (NSMutableArray *)specifiers {
    if (_specifiers) return (NSMutableArray *)_specifiers;
    NSArray *available = [super specifiers];
    NSMutableDictionary *rows = [NSMutableDictionary dictionary];
    for (PSSpecifier *row in _allSpecifiers) {
        NSString *identifier = [row propertyForKey:@"applicationIdentifier"];
        if (!DXPanelApplicationIdentifierValid(identifier)) continue;
        [row setProperty:@NO forKey:@"panelApplicationSelected"];
        rows[identifier] = row;
    }
    NSArray *applications = DXPanelApplications([DXPrefsManager.sharedInstance readPrefs], [self.specifier propertyForKey:@"panelSelector"]);
    NSMutableArray *selected = [NSMutableArray array];
    NSMutableSet *enabledIdentifiers = [NSMutableSet set];
    for (NSDictionary *application in applications) {
        NSString *identifier = application[@"bundleIdentifier"];
        [enabledIdentifiers addObject:identifier];
        PSSpecifier *row = rows[identifier];
        if (!row) {
            // Keep stored selections removable even after an app is uninstalled.
            row = [PSSpecifier preferenceSpecifierNamed:application[@"name"] target:self set:@selector(setApplicationEnabled:specifier:) get:@selector(readApplicationEnabled:) detail:nil cell:PSSwitchCell edit:nil];
            [row setProperty:identifier forKey:@"applicationIdentifier"];
            [row setProperty:_placeholderAppIcon forKey:@"iconImage"];
            [row setProperty:@YES forKey:@"enabled"];
            Class cellClass = [self customCellClassForCellType:PSSwitchCell];
            if (cellClass) [row setProperty:cellClass forKey:@"cellClass"];
        }
        [row setProperty:@YES forKey:@"panelApplicationSelected"];
        if (![self shouldHideApplicationSpecifiers] || ![self shouldHideApplicationSpecifier:row]) [selected addObject:row];
    }
    NSMutableArray *result = [NSMutableArray array];
    if (selected.count) {
        PSSpecifier *group = [PSSpecifier groupSpecifierWithName:[self localizedStringForString:@"PANEL_APPLICATIONS_SELECTED"]];
        [group setProperty:[self localizedStringForString:@"PANEL_APPLICATIONS_SELECTED_FOOTER"] forKey:@"footerText"];
        [result addObject:group]; [result addObjectsFromArray:selected];
    }
    PSSpecifier *pendingGroup = nil;
    for (PSSpecifier *row in available) {
        if (row.cellType == PSGroupCell) { pendingGroup = row; continue; }
        if ([enabledIdentifiers containsObject:[row propertyForKey:@"applicationIdentifier"]]) continue;
        if (pendingGroup) { [result addObject:pendingGroup]; pendingGroup = nil; }
        [result addObject:row];
    }
    _specifiers = result;
    return result;
}
- (BOOL)tableView:(UITableView *)tableView canMoveRowAtIndexPath:(NSIndexPath *)indexPath {
    (void)tableView;
    return ![self shouldHideApplicationSpecifiers] && [[[self specifierAtIndexPath:indexPath] propertyForKey:@"panelApplicationSelected"] boolValue];
}
- (BOOL)tableView:(UITableView *)tableView canEditRowAtIndexPath:(NSIndexPath *)indexPath {
    return [self tableView:tableView canMoveRowAtIndexPath:indexPath];
}
- (UITableViewCellEditingStyle)tableView:(UITableView *)tableView editingStyleForRowAtIndexPath:(NSIndexPath *)indexPath {
    (void)tableView; (void)indexPath; return UITableViewCellEditingStyleNone;
}
- (BOOL)tableView:(UITableView *)tableView shouldIndentWhileEditingRowAtIndexPath:(NSIndexPath *)indexPath {
    (void)tableView; (void)indexPath; return NO;
}
- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    UITableViewCell *cell = [super tableView:tableView cellForRowAtIndexPath:indexPath];
    cell.showsReorderControl = [self tableView:tableView canMoveRowAtIndexPath:indexPath];
    cell.editingAccessoryView = cell.accessoryView; // Keep the application switch usable beside the reorder handle.
    return cell;
}
- (NSIndexPath *)tableView:(UITableView *)tableView targetIndexPathForMoveFromRowAtIndexPath:(NSIndexPath *)source toProposedIndexPath:(NSIndexPath *)destination {
    return [self tableView:tableView canMoveRowAtIndexPath:source] && [self tableView:tableView canMoveRowAtIndexPath:destination] ? destination : source;
}
- (void)tableView:(UITableView *)tableView moveRowAtIndexPath:(NSIndexPath *)source toIndexPath:(NSIndexPath *)destination {
    if (![self tableView:tableView canMoveRowAtIndexPath:source] || ![self tableView:tableView canMoveRowAtIndexPath:destination] || source.section != destination.section || source.row == destination.row) return;
    NSString *identifier = [[self specifierAtIndexPath:source] propertyForKey:@"applicationIdentifier"];
    NSString *anchor = [[self specifierAtIndexPath:destination] propertyForKey:@"applicationIdentifier"];
    NSMutableDictionary *preferences = [[DXPrefsManager.sharedInstance readPrefs] mutableCopy];
    if (DXPanelMoveApplication(preferences, [self.specifier propertyForKey:@"panelSelector"], identifier, anchor, source.row < destination.row))
        [DXPrefsManager.sharedInstance writePrefs:preferences];
    [self reloadSpecifiers];
}
- (PSSpecifier *)createGroupSpecifierForApplicationSection:(ATLApplicationSection *)section {
    PSSpecifier *group = [super createGroupSpecifierForApplicationSection:section];
    [group setProperty:[self localizedStringForString:@"PANEL_APPLICATIONS_FOOTER"] forKey:@"footerText"];
    return group;
}
@end
