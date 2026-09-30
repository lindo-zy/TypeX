#import "DXPSystemActionPickerController.h"
#import "../DXSystemActionCatalog.h"
#import "../common.h"

static NSBundle *tweakBundle;

@interface DXPSystemActionPickerController () <UITableViewDataSource, UITableViewDelegate>
@property (nonatomic, copy) NSArray<NSArray<NSDictionary *> *> *groups;
@end

@implementation DXPSystemActionPickerController
- (void)viewDidLoad {
    [super viewDidLoad];
    tweakBundle = [NSBundle bundleWithPath:bundlePath];
    self.title = LOCALIZED(@"SELECT_SYSTEM_ACTION");
    NSMutableArray *groups = [NSMutableArray array];
    for (NSString *group in @[@"media", @"device", @"control"]) {
        NSMutableArray *rows = [NSMutableArray array];
        for (NSDictionary *action in DXSystemActionCatalog())
            if ([action[@"group"] isEqual:group]) [rows addObject:action];
        [groups addObject:rows];
    }
    self.groups = groups;
    UITableView *table = [[UITableView alloc] initWithFrame:self.view.bounds style:UITableViewStyleInsetGrouped];
    table.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    table.dataSource = self;
    table.delegate = self;
    self.view = table;
}
- (NSInteger)numberOfSectionsInTableView:(UITableView *)table { return self.groups.count; }
- (NSInteger)tableView:(UITableView *)table numberOfRowsInSection:(NSInteger)section { return self.groups[section].count; }
- (NSString *)tableView:(UITableView *)table titleForHeaderInSection:(NSInteger)section {
    NSString *key = @[@"SYSTEM_GROUP_MEDIA", @"SYSTEM_GROUP_DEVICE", @"SYSTEM_GROUP_CONTROL"][section];
    return LOCALIZED(key);
}
- (NSString *)tableView:(UITableView *)table titleForFooterInSection:(NSInteger)section {
    return section == 1 ? LOCALIZED(@"SYSTEM_DEVICE_FOOTER") : nil;
}
- (UITableViewCell *)tableView:(UITableView *)table cellForRowAtIndexPath:(NSIndexPath *)path {
    UITableViewCell *cell = [table dequeueReusableCellWithIdentifier:@"SystemAction"];
    if (!cell) cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:@"SystemAction"];
    NSDictionary *action = self.groups[path.section][path.row];
    cell.textLabel.text = LOCALIZED(action[@"title"]);
    cell.imageView.image = [UIImage systemImageNamed:action[@"icon"]];
    cell.accessoryType = [self.selectedIdentifier isEqual:action[@"id"]] ? UITableViewCellAccessoryCheckmark : UITableViewCellAccessoryNone;
    return cell;
}
- (void)tableView:(UITableView *)table didSelectRowAtIndexPath:(NSIndexPath *)path {
    [table deselectRowAtIndexPath:path animated:YES];
    if (self.completion) self.completion(self.groups[path.section][path.row]);
    [self.navigationController popViewControllerAnimated:YES];
}
@end
