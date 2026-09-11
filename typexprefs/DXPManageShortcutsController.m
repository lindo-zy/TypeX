#import "DXPManageShortcutsController.h"
#import "../DXShortcutsGenerator.h"
#import "../DXHelper.h"
#import "DXPGesturePickerController.h"

static UISearchController *searchController;
static NSBundle *tweakBundle;

static BOOL DXIsHiddenShortcutSelector(NSString *selector) {
    return ![DXShortcutsGenerator isVisibleShortcutSelector:selector];
}

static void DXAppendUniqueShortcuts(NSArray *shortcuts,
                                    NSMutableArray *destination,
                                    NSMutableSet *seenSelectors,
                                    NSUInteger limit) {
    for (id object in shortcuts) {
        if (destination.count >= limit) break;
        if (![object isKindOfClass:[NSDictionary class]]) continue;

        NSDictionary *shortcut = (NSDictionary *)object;
        NSString *selector = shortcut[@"selector"];
        if (![selector isKindOfClass:[NSString class]] ||
            DXIsHiddenShortcutSelector(selector) ||
            [seenSelectors containsObject:selector]) {
            continue;
        }

        [destination addObject:shortcut];
        [seenSelectors addObject:selector];
    }
}


@implementation DXPManageShortcutsController

- (NSString *)scopedKey:(NSString *)bottomKey topKey:(NSString *)topKey {
    return self.topConfiguration ? topKey : bottomKey;
}

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    return 2;
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    switch (section) {
        case 0:
            return LOCALIZED(@"ENABLED_SHORTCUTS");
        case 1:
            return LOCALIZED(@"DISABLED_SHORTCUTS");
        default:
            return nil;
    }
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    switch (section) {
        case 0:
            return [self.currentOrder[0] count];
        case 1:
            return [self.currentOrder[1] count];
        default:
            return 0;
    }
}

- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section{
    switch (section) {
        case 0:
            return LOCALIZED(@"FOOTER_TEXT_FOR_ENABLED_SHORTCUTS");
        case 1:
            return @"";
        default:
            return @"";
            
    }
}

-(void)setCompatibiltyWarning{
    CGRect frame = CGRectMake(0,0,self.tableView.bounds.size.width,50);
    UIView *headerView = [[UIView alloc] initWithFrame:frame];
    UIFont *font = [UIFont fontWithName:@"HelveticaNeue-Bold" size:15];
    UILabel *headerLabel = [[UILabel alloc] initWithFrame:frame];
    [headerLabel setText:@"Due to compatibility issue, please \"Reset\".\nInteraction with table below is temporary disabled."];
    [headerLabel setFont:font];
    [headerLabel setTextColor:[UIColor redColor]];
    headerLabel.textAlignment = NSTextAlignmentCenter;
    [headerLabel setContentMode:UIViewContentModeScaleAspectFit];
    [headerLabel setAutoresizingMask:UIViewAutoresizingFlexibleWidth];
    [headerLabel setNumberOfLines:0];
    [headerLabel setLineBreakMode:NSLineBreakByWordWrapping];
    [headerView addSubview:headerLabel];
    self.tableView.tableHeaderView = headerView;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"TypeXItemCell" forIndexPath:indexPath];
    
    if (cell == nil)
        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:@"TypeXItemCell"];
    
    UIImage *image;
    NSString *label;
    
    dispatch_semaphore_t smp = dispatch_semaphore_create(0);
    __block BOOL isCustomImagePath = NO;
    __block BOOL isThirteen = NO;
    
    switch(indexPath.section) {
        case 0: {
            if (self.currentOrder[0] == nil || [self.currentOrder[0] count] <= indexPath.row)
                return nil;
            if (indexPath.row >= [self.currentOrder[0] count]){
                [self setCompatibiltyWarning];
                cell.textLabel.text = LOCALIZED(@"INCOMPATIBLE_RESET");
                cell.imageView.image = nil;
                self.tableView.userInteractionEnabled = NO;
                return cell;
            }
            label = [DXHelper localizedStringForActionNamed:[DXHelper actionNameFromArray:self.currentOrder[0] atIndex:indexPath.row] shortName:NO bundle:tweakBundle];
            //label = [DXHelper labelFromArray:self.currentOrder[0] atIndex:indexPath.row];
            image = [DXHelper imageFromArray:self.currentOrder[0] atIndex:indexPath.row withSystemColor:YES completion:^(BOOL thirteen, BOOL customPath){
                isThirteen = thirteen;
                isCustomImagePath = customPath;
                dispatch_semaphore_signal(smp);
            }];
            dispatch_semaphore_wait(smp, DISPATCH_TIME_FOREVER);
            if (!isThirteen && isCustomImagePath){
                [cell.imageView setTintColor:[UIColor blackColor]];
            }
            break;
        }
        case 1: {
            if (self.currentOrder[1] == nil || [self.currentOrder[1] count] <= indexPath.row)
                return nil;
            if (indexPath.row >= [self.currentOrder[1] count]){
                [self setCompatibiltyWarning];
                cell.textLabel.text = LOCALIZED(@"INCOMPATIBLE_RESET");
                cell.imageView.image = nil;
                self.tableView.userInteractionEnabled = NO;
                return cell;
            }
            label = [DXHelper localizedStringForActionNamed:[DXHelper actionNameFromArray:self.currentOrder[1] atIndex:indexPath.row] shortName:NO bundle:tweakBundle];
            
            //label = [DXHelper labelFromArray:self.currentOrder[1] atIndex:indexPath.row];
            image = [DXHelper imageFromArray:self.currentOrder[1] atIndex:indexPath.row withSystemColor:YES completion:^(BOOL thirteen, BOOL customPath){
                isThirteen = thirteen;
                isCustomImagePath = customPath;
                dispatch_semaphore_signal(smp);
            }];
            dispatch_semaphore_wait(smp, DISPATCH_TIME_FOREVER);
            if (!isThirteen && isCustomImagePath){
                [cell.imageView setTintColor:[UIColor blackColor]];
            }
            break;
        }
    }
    cell.textLabel.text = label;
    cell.imageView.image = image;
    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath{
    DXPGesturePickerController *gesturePickerController = [[DXPGesturePickerController alloc] init];

    gesturePickerController.fullOrder = self.fullOrder;
    gesturePickerController.identifier = self.currentOrder[indexPath.section][indexPath.row][@"selector"];
    gesturePickerController.configuration = self.topConfiguration ? @"top" : @"bottom";
    gesturePickerController.title = [DXHelper localizedStringForActionNamed:self.currentOrder[indexPath.section][indexPath.row][@"selector"] shortName:NO bundle:tweakBundle];

    [gesturePickerController setRootController: [self rootController]];
    [gesturePickerController setParentController: [self parentController]];
    [self pushController:gesturePickerController];

    [tableView deselectRowAtIndexPath:indexPath animated:YES];
}

- (void)tableView:(UITableView *)tableView moveRowAtIndexPath:(NSIndexPath *)sourceIndexPath toIndexPath:(NSIndexPath *)destinationIndexPath {
    if (self.tableView == nil)
        return;
    
    if (self.currentOrder[0] == nil)
        [self updateOrder:NO];
    
    NSString *objectToMove = [self.currentOrder[0] objectAtIndex:sourceIndexPath.row];
    [self.currentOrder[0] removeObjectAtIndex:sourceIndexPath.row];
    [self.currentOrder[0] insertObject:objectToMove atIndex:destinationIndexPath.row];
    [self.tableView reloadData];
    [self writeToFile];
    
}

- (BOOL)tableView:(UITableView *)tableView canMoveRowAtIndexPath:(NSIndexPath *)indexPath {
    switch (indexPath.section) {
        case 0:
            return [self.currentOrder[0] count] == 1?NO:YES;
        case 1:
            return NO;
        default:
            return NO;
    }
}

- (BOOL)tableView:(UITableView *)tableView canEditRowAtIndexPath:(NSIndexPath *)indexPath{
    switch (indexPath.section) {
        case 0: {
            return YES;
            break;
        }
        case 1: {
            return YES;
            break;
        }
        default:
            return NO;
    }
}

- (void)tableView:(UITableView *)tableView commitEditingStyle:(UITableViewCellEditingStyle)editingStyle forRowAtIndexPath:(NSIndexPath *)indexPath {
    switch (indexPath.section) {
        case 0: {
            if (editingStyle == UITableViewCellEditingStyleDelete) {
                // Delete the row from the data source
                [tableView beginUpdates];
                [self.currentOrder[1] addObject:self.currentOrder[0][indexPath.row]];
                [self.currentOrder[0] removeObjectAtIndex:indexPath.row];
                [tableView deleteRowsAtIndexPaths:@[indexPath] withRowAnimation:UITableViewRowAnimationFade];
                //[tableView endUpdates];
                
                //[tableView beginUpdates];
                NSIndexPath *indexPath = [NSIndexPath indexPathForRow:[self.currentOrder[1] count] - 1 inSection:1];
                [tableView insertRowsAtIndexPaths:@[indexPath] withRowAnimation:UITableViewRowAnimationRight];
                [tableView endUpdates];
                [self writeToFile];
                
            }
        }
            break;
        case 1: {
            if (editingStyle == UITableViewCellEditingStyleInsert) {
                if ([self.currentOrder[0] count] >= maxshortcutpersection) {
                    return;
                }
                [tableView beginUpdates];
                [self.currentOrder[0] addObject:self.currentOrder[1][indexPath.row]];
                [self.currentOrder[1] removeObjectAtIndex:indexPath.row];
                [tableView deleteRowsAtIndexPaths:@[indexPath] withRowAnimation:UITableViewRowAnimationFade];
                NSIndexPath *indexPath = [NSIndexPath indexPathForRow:[self.currentOrder[0] count] - 1  inSection:0];
                [tableView insertRowsAtIndexPaths:@[indexPath] withRowAnimation:UITableViewRowAnimationRight];
                [tableView endUpdates];
                [self writeToFile];
                
                
            }
            
        }
    }
}

- (UITableViewCellEditingStyle)tableView:(UITableView *)tableView editingStyleForRowAtIndexPath:(NSIndexPath *)indexPath {
    switch (indexPath.section) {
        case 0:
            return [self.currentOrder[0] count] == 1?UITableViewCellEditingStyleNone:UITableViewCellEditingStyleDelete;
        case 1:
            return [self.currentOrder[0] count] >= maxshortcutpersection ? UITableViewCellEditingStyleNone : UITableViewCellEditingStyleInsert;
            //return [self.currentOrder[0] count] == maxShortcuts?UITableViewCellEditingStyleNone:UITableViewCellEditingStyleInsert;
        default:
            return UITableViewCellEditingStyleNone;
    }
}

- (BOOL)tableView:(UITableView *)tableView shouldIndentWhileEditingRowAtIndexPath:(NSIndexPath *)indexPath {
    return NO;
}


- (void)writeToFile{
    [[DXPrefsManager sharedInstance] setValue:self.currentOrder forKey:self.shortcutsPreferenceKey ?: kShortcutskey];
}

- (void)updateOrder:(BOOL)reset{
    NSMutableDictionary *prefs = [[[DXPrefsManager sharedInstance] readPrefs] mutableCopy] ?: [NSMutableDictionary dictionary];
    NSString *shortcutsKey = self.shortcutsPreferenceKey ?: kShortcutskey;
    NSString *customActionsKey = [self scopedKey:kCustomActionskey topKey:kTopCustomActionskey];
    NSString *customActionsDTKey = [self scopedKey:kCustomActionsDTkey topKey:kTopCustomActionsDTkey];
    NSString *cacheKey = [self scopedKey:kCachekey topKey:kTopCachekey];
    
    //BOOL newShortcutsAvailable = ([tweakVersion compare:prefs[@"version"] options:NSNumericSearch] == NSOrderedDescending);
    /*
     if (forceDefault){
     [prefs removeObjectForKey:@"shortcuts"];
     prefs[@"version"] = tweakVersion;
     [prefs writeToFile:kPrefsPath atomically:NO];
     }
     */
    //NSMutableDictionary *currentOrderDefault = [[NSMutableDictionary alloc] init];
    DXShortcutsGenerator *shortcutsGenerator = [DXShortcutsGenerator sharedInstance];
    NSMutableArray *defaultOrderLabel = [[shortcutsGenerator labelName] mutableCopy];
    NSMutableArray *defaultOrderSelector = [[shortcutsGenerator selectorNames] mutableCopy];
    NSMutableArray *defaultOrder12 = [[shortcutsGenerator imageNameArrayForiOS:0] mutableCopy];
    NSMutableArray *defaultOrder13 = [[shortcutsGenerator imageNameArrayForiOS:1] mutableCopy];
    //NSMutableArray *shortLabel = [[shortcutsGenerator shortenedlabelName] mutableCopy];
    

    NSMutableArray *fullOrderDict = [[NSMutableArray alloc] init];
    
    for (int i = 0; i < [defaultOrderLabel count]; i++){
        if (DXIsHiddenShortcutSelector(defaultOrderSelector[i])) {
            continue;
        }
        [fullOrderDict addObject: @{
            @"label" : defaultOrderLabel[i],
            @"images12" : defaultOrder12[i],
            @"images13" : defaultOrder13[i],
            @"selector" : defaultOrderSelector[i],
            //@"slabel" : shortLabel[i]
        }];
    }
    
    self.fullOrder = fullOrderDict;
    
    
    //reset custom long press actions
    if (reset){
        prefs[customActionsKey] = @[];
        prefs[customActionsDTKey] = @[];
        [prefs removeObjectForKey:cacheKey];

        //Remove all caches
        NSFileManager *fm = [NSFileManager defaultManager];
        for (NSString *cacheFile in [fm contentsOfDirectoryAtPath:TypeXCachePath error:nil]) {
            [fm removeItemAtPath:[NSString stringWithFormat:@"%@/%@", TypeXCachePath, cacheFile] error:nil];
        }
    }

    id storedOrder = prefs[shortcutsKey];
    BOOL hasStoredOrder = !reset && [storedOrder isKindOfClass:[NSArray class]] && [storedOrder count] >= 2;
    NSArray *storedEnabled = hasStoredOrder && [storedOrder[0] isKindOfClass:[NSArray class]] ? storedOrder[0] : @[];
    NSArray *storedDisabled = hasStoredOrder && [storedOrder[1] isKindOfClass:[NSArray class]] ? storedOrder[1] : @[];

    NSMutableArray *enabled = [NSMutableArray array];
    NSMutableArray *disabled = [NSMutableArray array];
    NSMutableSet *seenSelectors = [NSMutableSet set];

    if (hasStoredOrder) {
        DXAppendUniqueShortcuts(storedEnabled, enabled, seenSelectors, maxshortcutpersection);
    }
    if (enabled.count == 0) {
        DXAppendUniqueShortcuts(fullOrderDict, enabled, seenSelectors, maxdefaultshortcuts);
    }

    if (hasStoredOrder) {
        DXAppendUniqueShortcuts(storedDisabled, disabled, seenSelectors, NSUIntegerMax);
    }
    // Compare shortcut identity by selector.  Stored entries from older versions
    // may contain obsolete metadata (for example selectorlp), so dictionary
    // equality would incorrectly append a second copy of the same action.
    DXAppendUniqueShortcuts(fullOrderDict, disabled, seenSelectors, NSUIntegerMax);

    self.currentOrder = [NSMutableArray arrayWithObjects:enabled, disabled, nil];

    NSArray *normalizedOrder = @[[enabled copy], [disabled copy]];
    if (reset || ![storedOrder isEqual:normalizedOrder]) {
        prefs[shortcutsKey] = normalizedOrder;
        [[DXPrefsManager sharedInstance] writePrefs:prefs];
    }
    
}

-(void)reset{
    
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"TypeX" message:LOCALIZED(@"RESET_MESSAGE") preferredStyle:UIAlertControllerStyleAlert];
    
    UIAlertAction *resetAction = [UIAlertAction actionWithTitle:LOCALIZED(@"RESET_YES") style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        [self updateOrder:YES];
        [self.tableView.tableHeaderView removeFromSuperview];
        self.tableView.tableHeaderView = nil;
        self.tableView.userInteractionEnabled = YES;
        [self.tableView reloadData];
    }];
    UIAlertAction *cancelAction = [UIAlertAction actionWithTitle:LOCALIZED(@"RESET_NO") style:UIAlertActionStyleCancel handler:^(UIAlertAction *action) {
        [self dismissViewControllerAnimated:YES completion:nil];
    }];
    
    [alert addAction:resetAction];
    [alert addAction:cancelAction];
    
    [self presentViewController:alert animated:YES completion:nil];
    
}

-(NSIndexPath *)tableView:(UITableView *)tableView targetIndexPathForMoveFromRowAtIndexPath:(NSIndexPath *)sourceIndexPath toProposedIndexPath:(NSIndexPath *)proposedDestinationIndexPath
{
    if( sourceIndexPath.section != proposedDestinationIndexPath.section )
    {
        return sourceIndexPath;
    }
    else
    {
        return proposedDestinationIndexPath;
    }
}

- (void)viewWillDisappear:(BOOL)animated {
    [super viewWillDisappear:animated];
    if (@available(iOS 11.0, *)){
    }else{
        CGPoint contentOffset = self.tableView.contentOffset;
        contentOffset.y += CGRectGetHeight(self.tableView.tableHeaderView.frame);
        self.tableView.contentOffset = contentOffset;
    }
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [self updateOrder:NO];
}

- (void)viewDidLoad {
    self.topConfiguration = [[self.specifier propertyForKey:@"configuration"] isEqualToString:@"top"];
    self.shortcutsPreferenceKey = self.topConfiguration ? kTopShortcutskey : kShortcutskey;
    tweakBundle = [NSBundle bundleWithPath:bundlePath];
    [tweakBundle load];
    [super viewDidLoad];
    self.tableView = [[UITableView alloc] initWithFrame:CGRectMake(0, 0, self.view.frame.size.width, self.view.frame.size.height) style:UITableViewStyleGrouped];
    self.tableView.delegate = self;
    self.tableView.dataSource = self;
    [self.tableView setAutoresizingMask:UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight];
    [self.tableView registerClass:[UITableViewCell class] forCellReuseIdentifier:@"TypeXItemCell"];
    [self.tableView setEditing:YES];
    [self.tableView setAllowsSelection:NO];
    self.tableView.allowsSelectionDuringEditing=YES;
    
    ((UIViewController *)self).title = self.topConfiguration ? @"顶部设置" : @"底部设置";
    self.view = self.tableView;
    
    self.resetBtn = [[UIBarButtonItem alloc] initWithTitle:LOCALIZED(@"RESET") style:UIBarButtonItemStylePlain target:self action:@selector(reset)];
    //self.addSnippetBtn.tintColor = [UIColor blackColor];
    self.navigationItem.rightBarButtonItem = self.resetBtn;
    
    
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

@end
