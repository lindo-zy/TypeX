#import "DXPGesturePickerController.h"
#import "DXPCustomActionViewController.h"
#import "../common.h"

static NSBundle *tweakBundle;


@implementation DXPGesturePickerController

- (NSArray *)specifiers {
    if (!_specifiers) {
        NSMutableArray *snippetEntrySpecifiers = [[NSMutableArray alloc] init];
        
        PSSpecifier *gestureTypeGroup = [PSSpecifier preferenceSpecifierNamed:LOCALIZED(@"GESTURES") target:nil set:nil get:nil detail:nil cell:PSGroupCell edit:nil];
        [snippetEntrySpecifiers addObject:gestureTypeGroup];

        PSSpecifier *longPressSpec = [PSSpecifier preferenceSpecifierNamed:LOCALIZED(@"LONG_PRESS") target:nil set:nil get:nil detail:NSClassFromString(@"DXPGesturePickerController") cell:PSLinkListCell edit:nil];
        [longPressSpec setProperty:LOCALIZED(@"LONG_PRESS") forKey:@"label"];
        [snippetEntrySpecifiers addObject:longPressSpec];
        
        PSSpecifier *doubleTapSpec = [PSSpecifier preferenceSpecifierNamed:LOCALIZED(@"DOUBLE_TAP") target:nil set:nil get:nil detail:NSClassFromString(@"DXPGesturePickerController") cell:PSLinkListCell edit:nil];
        [doubleTapSpec setProperty:LOCALIZED(@"DOUBLE_TAP") forKey:@"label"];
        [snippetEntrySpecifiers addObject:doubleTapSpec];
        
        _specifiers = snippetEntrySpecifiers;
        
    }
    
    return _specifiers;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath{
    
    UITableViewCell *cell = [tableView cellForRowAtIndexPath:indexPath];
    
    DXPCustomActionViewController *actionViewController = [[DXPCustomActionViewController alloc] init];

    actionViewController.fullOrder = self.fullOrder;
    actionViewController.identifier = self.identifier;
    actionViewController.configuration = self.configuration;
    
    switch (indexPath.row) {
        case 0:
            actionViewController.keyID = [self.configuration isEqualToString:@"top"] ? kTopCustomActionskey : kCustomActionskey;
            break;
        case 1:
            actionViewController.keyID = [self.configuration isEqualToString:@"top"] ? kTopCustomActionsDTkey : kCustomActionsDTkey;
            break;
        default:
            actionViewController.keyID = [self.configuration isEqualToString:@"top"] ? kTopCustomActionskey : kCustomActionskey;
            break;
    }
    
    actionViewController.title = cell.textLabel.text;
    
    [actionViewController setRootController: [self rootController]];
    [actionViewController setParentController: [self parentController]];
    [self pushController:actionViewController];
    
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    

}

- (void)viewDidLoad {
    tweakBundle = [NSBundle bundleWithPath:bundlePath];
    [tweakBundle load];
    [super viewDidLoad];
}
@end
