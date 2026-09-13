#import "DXPSubActionPickerController.h"
#import "../DXHelper.h"
#import "../common.h"

static NSBundle *tweakBundle;

@implementation DXPSubActionPickerController

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    return 1;
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    return LOCALIZED(@"ACTION");
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return self.fullOrder.count;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"TypeXSubActionPickerCell" forIndexPath:indexPath];

    if (cell == nil)
        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:@"TypeXSubActionPickerCell"];

    if (indexPath.row >= self.fullOrder.count) return cell;

    dispatch_semaphore_t smp = dispatch_semaphore_create(0);
    __block BOOL isCustomImagePath = NO;
    __block BOOL isThirteen = NO;

    cell.accessoryType = UITableViewCellAccessoryNone;
    NSString *selector = [DXHelper actionNameFromArray:self.fullOrder atIndex:indexPath.row];
    if (self.selectedSelector && [self.selectedSelector isEqualToString:selector]) {
        cell.accessoryType = UITableViewCellAccessoryCheckmark;
    }

    cell.textLabel.text = [DXHelper localizedStringForActionNamed:selector shortName:NO bundle:tweakBundle];
    cell.imageView.image = [DXHelper imageFromArray:self.fullOrder atIndex:indexPath.row withSystemColor:YES completion:^(BOOL thirteen, BOOL customPath){
        isThirteen = thirteen;
        isCustomImagePath = customPath;
        dispatch_semaphore_signal(smp);
    }];
    dispatch_semaphore_wait(smp, DISPATCH_TIME_FOREVER);
    if (!isThirteen && isCustomImagePath) {
        [cell.imageView setTintColor:[UIColor blackColor]];
    }
    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    if (indexPath.row >= self.fullOrder.count) return;

    NSString *selector = [DXHelper actionNameFromArray:self.fullOrder atIndex:indexPath.row];

    // Reflect the pick before leaving so a slow pop still shows the result.
    NSIndexPath *oldIndexPath = [self indexPathForSelector:self.selectedSelector];
    self.selectedSelector = selector;
    NSMutableArray *reload = [NSMutableArray arrayWithObject:indexPath];
    if (oldIndexPath && ![oldIndexPath isEqual:indexPath]) [reload addObject:oldIndexPath];
    [tableView reloadRowsAtIndexPaths:reload withRowAnimation:UITableViewRowAnimationAutomatic];

    if (self.completion) self.completion(selector);
    [self.navigationController popViewControllerAnimated:YES];
}

- (NSIndexPath *)indexPathForSelector:(NSString *)selector {
    if (![selector isKindOfClass:[NSString class]] || selector.length == 0) return nil;
    for (NSUInteger row = 0; row < self.fullOrder.count; row++) {
        NSString *candidate = [DXHelper actionNameFromArray:self.fullOrder atIndex:row];
        if ([candidate isEqualToString:selector]) return [NSIndexPath indexPathForRow:row inSection:0];
    }
    return nil;
}

- (void)viewDidLoad {
    tweakBundle = [NSBundle bundleWithPath:bundlePath];
    [tweakBundle load];
    [super viewDidLoad];

    self.tableView = [[UITableView alloc] initWithFrame:CGRectMake(0, 0, self.view.frame.size.width, self.view.frame.size.height)
                                                  style:UITableViewStyleInsetGrouped];
    self.tableView.delegate = self;
    self.tableView.dataSource = self;
    [self.tableView setAutoresizingMask:UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight];
    [self.tableView registerClass:[UITableViewCell class] forCellReuseIdentifier:@"TypeXSubActionPickerCell"];
    [self.tableView setAllowsSelection:YES];
    self.tableView.allowsMultipleSelection = NO;

    self.view = self.tableView;
}

@end
