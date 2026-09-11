#import "DXPCustomActionViewController.h"
#import "../DXHelper.h"
#import "../common.h"

static NSBundle *tweakBundle;

@implementation DXPCustomActionViewController

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    return 1;
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    return LOCALIZED(@"ACTION");
}

- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section
{
    return @"";
}


- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return self.fullOrder.count;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"TypeXLPItemCell" forIndexPath:indexPath];
    
    if (cell == nil)
        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:@"TypeXLPItemCell"];
    
    UIImage *image;
    NSString *label;
    
    dispatch_semaphore_t smp = dispatch_semaphore_create(0);
    __block BOOL isCustomImagePath = NO;
    __block BOOL isThirteen = NO;
    
    cell.accessoryType = UITableViewCellAccessoryNone;
    if (indexPath.row >= self.fullOrder.count) return nil;
    label = [DXHelper localizedStringForActionNamed:[DXHelper actionNameFromArray:self.fullOrder atIndex:indexPath.row] shortName:NO bundle:tweakBundle];
    image = [DXHelper imageFromArray:self.fullOrder atIndex:indexPath.row withSystemColor:YES completion:^(BOOL thirteen, BOOL customPath){
        isThirteen = thirteen;
        isCustomImagePath = customPath;
        dispatch_semaphore_signal(smp);
    }];
    dispatch_semaphore_wait(smp, DISPATCH_TIME_FOREVER);
    if (!isThirteen && isCustomImagePath) {
        [cell.imageView setTintColor:[UIColor blackColor]];
    }
    if ([self.selectedIndexPath compare:indexPath] == NSOrderedSame && self.selectedIndexPath != nil) {
        cell.accessoryType = UITableViewCellAccessoryCheckmark;
    }
    cell.textLabel.text = label;
    cell.imageView.image = image;
    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath{
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    
    NSMutableArray *customActionsArray = [[NSMutableArray alloc] init];
    NSMutableDictionary *customActionsEntry = [[NSMutableDictionary alloc] init];
    NSUInteger index = 0;
    BOOL exist = NO;
    if (self.prefs[self.keyID] && [self.prefs[self.keyID] firstObject] != nil){
        customActionsArray = [self.prefs[self.keyID] mutableCopy];
        NSArray *arrayWithListenerID = [self.prefs[self.keyID] valueForKey:@"identifier"];
        index = [arrayWithListenerID indexOfObject:self.identifier];
        customActionsEntry = index != NSNotFound ? [[customActionsArray objectAtIndex:index] mutableCopy] : customActionsEntry;
        if ([customActionsEntry count] > 0){
            exist = YES;
        }
    }
    customActionsEntry[@"identifier"] = self.identifier;
    
    UITableViewCell *currentCell =  [tableView cellForRowAtIndexPath:indexPath];
    
    UITableViewCell *oldCell;
    
    oldCell = [tableView cellForRowAtIndexPath:self.selectedIndexPath];
    if (currentCell.accessoryType == UITableViewCellAccessoryNone) {
        currentCell.accessoryType = UITableViewCellAccessoryCheckmark;
        customActionsEntry[@"selector"] = self.fullOrder[indexPath.row][@"selector"];
    } else {
        currentCell.accessoryType = UITableViewCellAccessoryNone;
        customActionsEntry[@"selector"] = @"";
    }
    // Selecting or clearing an action upgrades an old two-action entry to the
    // current single-action schema.
    [customActionsEntry removeObjectForKey:@"selector2"];
    if ([self.selectedIndexPath compare:indexPath] != NSOrderedSame && self.selectedIndexPath != nil && oldCell.accessoryType == UITableViewCellAccessoryCheckmark) {
        oldCell.accessoryType = UITableViewCellAccessoryNone;
    }
    self.selectedIndexPath = indexPath;
    
    if (exist) {
        [customActionsArray replaceObjectAtIndex:index withObject:customActionsEntry];
    }else{
        
        [customActionsArray addObject:customActionsEntry];
    }
    [self.prefs setObject:customActionsArray forKey:self.keyID];
    
    [[DXPrefsManager sharedInstance] writePrefs:self.prefs];
    //[self.prefs writeToFile:kPrefsPath atomically:YES];
    
    
    CFStringRef notificationName = (__bridge CFStringRef)kPrefsChangedIdentifier;
    if (notificationName) {
        CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(), notificationName, NULL, NULL, YES);
    }
}

-(void)tableView:(UITableView *)tableView didDeselectRowAtIndexPath:(NSIndexPath *)indexPath
{
    //[tableView cellForRowAtIndexPath:indexPath].accessoryType = UITableViewCellAccessoryNone;
    
}

-(void)resetToDefault{
    self.selectedIndexPath = nil;
    
    NSMutableArray *customActionsArray = [[NSMutableArray alloc] init];
    NSMutableDictionary *customActionsEntry = [[NSMutableDictionary alloc] init];
    NSUInteger index = 0;
    BOOL exist = NO;
    if (self.prefs[self.keyID] && [self.prefs[self.keyID] firstObject] != nil){
        customActionsArray = [self.prefs[self.keyID] mutableCopy];
        NSArray *arrayWithListenerID = [self.prefs[self.keyID] valueForKey:@"identifier"];
        index = [arrayWithListenerID indexOfObject:self.identifier];
        customActionsEntry = index != NSNotFound ? [[customActionsArray objectAtIndex:index] mutableCopy] : customActionsEntry;
        if ([customActionsEntry count] > 0){
            exist = YES;
        }
    }
    if (exist){
        [customActionsArray removeObjectAtIndex:index];
        self.prefs[self.keyID] = customActionsArray;
        [[DXPrefsManager sharedInstance] writePrefs:self.prefs];
    }
    [self.tableView reloadData];
    
    CFStringRef notificationName = (__bridge CFStringRef)kPrefsChangedIdentifier;
    if (notificationName) {
        CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(), notificationName, NULL, NULL, YES);
    }
    
    
    
}

- (void)viewDidLoad {
    tweakBundle = [NSBundle bundleWithPath:bundlePath];
    [tweakBundle load];
    [super viewDidLoad];
    self.prefs = [[[DXPrefsManager sharedInstance] readPrefs] mutableCopy];
    
    self.tableView = [[UITableView alloc] initWithFrame:CGRectMake(0, 0, self.view.frame.size.width, self.view.frame.size.height) style:UITableViewStyleGrouped];
    self.tableView.delegate = self;
    self.tableView.dataSource = self;
    [self.tableView setAutoresizingMask:UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight];
    [self.tableView registerClass:[UITableViewCell class] forCellReuseIdentifier:@"TypeXLPItemCell"];
    //[self.tableView setEditing:YES];
    [self.tableView setAllowsSelection:YES];
    self.tableView.allowsMultipleSelection = NO;
    //self.tableView.allowsSelectionDuringEditing=YES;
    
    if ( [self.prefs[self.keyID] count] > 0 ){
        NSArray* arrayWithID = [self.prefs[self.keyID] filteredArrayUsingPredicate:[NSPredicate predicateWithFormat:@"%@ IN self.@allKeys" , @"identifier" ]];
        NSArray *IDList = [arrayWithID valueForKey:@"identifier"];
        NSUInteger index = [IDList indexOfObject:self.identifier];
        HBLogDebug(@"index of id: %ld", index);
        
        if (index != NSNotFound){
            NSDictionary *entry = self.prefs[self.keyID][index];
            NSString *selectedAction = entry[@"selector2"] ?: entry[@"selector"];
            HBLogDebug(@"selectedAction: %@", selectedAction);
            
            NSArray* arrayWithSelector = [self.fullOrder filteredArrayUsingPredicate:[NSPredicate predicateWithFormat:@"%@ IN self.@allKeys" , @"selector" ]];
            NSArray *selectorList = [arrayWithSelector valueForKey:@"selector"];
            
            NSUInteger selectorindex = [selectorList indexOfObject:selectedAction];
            
            HBLogDebug(@"selectorindex: %ld",selectorindex);
            
            if (selectorindex != NSNotFound){
                self.selectedIndexPath = [NSIndexPath indexPathForRow:selectorindex inSection:0];
            }
            
        }
    }
    self.view = self.tableView;
    
    self.defaultBtn = [[UIBarButtonItem alloc] initWithTitle:LOCALIZED(@"DEFAULT") style:UIBarButtonItemStylePlain target:self action:@selector(resetToDefault)];
    self.navigationItem.rightBarButtonItem = self.defaultBtn;
    
    //self.addcustomActionsEntryBtn.tintColor = [UIColor blackColor];
}
@end
