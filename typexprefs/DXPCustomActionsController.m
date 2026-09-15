#import "DXPCustomActionsController.h"
#import "../common.h"

static NSBundle *tweakBundle;

@implementation DXPCustomActionsController

- (void)viewDidLoad {
    tweakBundle = [NSBundle bundleWithPath:bundlePath];
    [tweakBundle load];

    self.customActionsOnly = YES;
    // No selection on this page; also suppresses the base's 默认 reset button.
    self.selectionManagedExternally = YES;

    [super viewDidLoad];
    self.title = LOCALIZED(@"CUSTOM_ACTIONS");
}

@end
