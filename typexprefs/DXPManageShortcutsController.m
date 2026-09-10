#import "DXPManageShortcutsController.h"
#import "DXPCustomActionViewController.h"
#import "DXPInsertTextEntryController.h"
#import "DXPCursorMoveAndSelectEntryController.h"
#import "../DXShortcutsGenerator.h"
#import "../DXHelper.h"
#import "DXPGesturePickerController.h"
#import "DXPDeleteOptions.h"
#import "DXPPasteOptions.h"

static UISearchController *searchController;
static NSBundle *tweakBundle;

static BOOL DXIsHiddenShortcutSelector(NSString *selector) {
    return ![DXShortcutsGenerator isAvailableShortcutSelector:selector];
}


@implementation DXPManageShortcutsController

- (NSString *)scopedKey:(NSString *)bottomKey topKey:(NSString *)topKey {
    return self.topConfiguration ? topKey : bottomKey;
}

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    return 3;
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    switch (section) {
        case 0:
            return LOCALIZED(@"ENABLED_SHORTCUTS");
        case 1:
            return LOCALIZED(@"DISABLED_SHORTCUTS");
        default:
            return LOCALIZED(@"EXTRAS");
    }
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    switch (section) {
        case 0:
            return [self.currentOrder[0] count];
        case 1:
            return [self.currentOrder[1] count];
        case 2:
            return [self.extrasOptions count];
        default:
            return 0;
    }
}

- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section{
    NSString *footerTextForSectionOne = @"";
    switch (section) {
        case 0:
            return LOCALIZED(@"FOOTER_TEXT_FOR_ENABLED_SHORTCUTS");
        case 1:
            return @"";
        case 2:
            footerTextForSectionOne = LOCALIZED(@"FOOTER_TEXT_FOR_EXTRAS");
            footerTextForSectionOne = [footerTextForSectionOne stringByAppendingString:@"\n\n"];
            footerTextForSectionOne = [footerTextForSectionOne stringByAppendingString:LOCALIZED(@"FOOTER_TEXT_FOR_DEFAULT_LONG_PRESS_GESTURES")];
            return footerTextForSectionOne;
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
        case 2: {
            if (self.extrasOptions == nil || [self.extrasOptions count] <= indexPath.row)
                return nil;
            if (indexPath.row >= [self.extrasOptions count]){
                [self setCompatibiltyWarning];
                cell.textLabel.text = LOCALIZED(@"INCOMPATIBLE_RESET");
                cell.imageView.image = nil;
                self.tableView.userInteractionEnabled = NO;
                return cell;
            }
            label = [DXHelper labelFromArray:self.extrasOptions atIndex:indexPath.row];
            image = [DXHelper imageFromArray:self.extrasOptions atIndex:indexPath.row withSystemColor:YES completion:^(BOOL thirteen, BOOL customPath){
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
    
    if (indexPath.section < 2){
        
        DXPGesturePickerController *gesturePickerController = [[DXPGesturePickerController alloc] init];
        
        gesturePickerController.fullOrder = @[self.firstOrder, self.fullOrder];
        gesturePickerController.identifier = self.currentOrder[indexPath.section][indexPath.row][@"selector"];
        gesturePickerController.configuration = self.topConfiguration ? @"top" : @"bottom";
        gesturePickerController.title = [DXHelper localizedStringForActionNamed:self.currentOrder[indexPath.section][indexPath.row][@"selector"] shortName:NO bundle:tweakBundle];
        
        [gesturePickerController setRootController: [self rootController]];
        [gesturePickerController setParentController: [self parentController]];
        [self pushController:gesturePickerController];
        
    }else{
        if ([self.extrasOptions[indexPath.row][@"identifier"] isEqualToString:@"insertText"]){
            DXPInsertTextEntryController *insertTextController = [[DXPInsertTextEntryController alloc] init];
            insertTextController.entryID = @"insertTextAction:";
            insertTextController.configuration = self.topConfiguration ? @"top" : @"bottom";
            [insertTextController setRootController: [self rootController]];
            [insertTextController setParentController: [self parentController]];
            [self pushController:insertTextController];
        }else if ([self.extrasOptions[indexPath.row][@"identifier"] isEqualToString:@"prevWord"]){
            DXPCursorMoveAndSelectEntryController *cursorMoveAndSelectController = [[DXPCursorMoveAndSelectEntryController alloc] init];
            cursorMoveAndSelectController.entryID = @"moveCursorPreviousWordAction:";
            cursorMoveAndSelectController.configuration = self.topConfiguration ? @"top" : @"bottom";
            [cursorMoveAndSelectController setRootController: [self rootController]];
            [cursorMoveAndSelectController setParentController: [self parentController]];
            [self pushController:cursorMoveAndSelectController];
        }else if ([self.extrasOptions[indexPath.row][@"identifier"] isEqualToString:@"nextWord"]){
            DXPCursorMoveAndSelectEntryController *cursorMoveAndSelectController = [[DXPCursorMoveAndSelectEntryController alloc] init];
            cursorMoveAndSelectController.entryID = @"moveCursorNextWordAction:";
            cursorMoveAndSelectController.configuration = self.topConfiguration ? @"top" : @"bottom";
            [cursorMoveAndSelectController setRootController: [self rootController]];
            [cursorMoveAndSelectController setParentController: [self parentController]];
            [self pushController:cursorMoveAndSelectController];
        }else if ([self.extrasOptions[indexPath.row][@"identifier"] isEqualToString:@"lineStart"]){
            DXPCursorMoveAndSelectEntryController *cursorMoveAndSelectController = [[DXPCursorMoveAndSelectEntryController alloc] init];
            cursorMoveAndSelectController.entryID = @"moveCursorStartOfLineAction:";
            cursorMoveAndSelectController.configuration = self.topConfiguration ? @"top" : @"bottom";
            [cursorMoveAndSelectController setRootController: [self rootController]];
            [cursorMoveAndSelectController setParentController: [self parentController]];
            [self pushController:cursorMoveAndSelectController];
        }else if ([self.extrasOptions[indexPath.row][@"identifier"] isEqualToString:@"lineEnd"]){
            DXPCursorMoveAndSelectEntryController *cursorMoveAndSelectController = [[DXPCursorMoveAndSelectEntryController alloc] init];
            cursorMoveAndSelectController.entryID = @"moveCursorEndOfLineAction:";
            cursorMoveAndSelectController.configuration = self.topConfiguration ? @"top" : @"bottom";
            [cursorMoveAndSelectController setRootController: [self rootController]];
            [cursorMoveAndSelectController setParentController: [self parentController]];
            [self pushController:cursorMoveAndSelectController];
        }else if ([self.extrasOptions[indexPath.row][@"identifier"] isEqualToString:@"startOfParagraph"]){
            DXPCursorMoveAndSelectEntryController *cursorMoveAndSelectController = [[DXPCursorMoveAndSelectEntryController alloc] init];
            cursorMoveAndSelectController.entryID = @"moveCursorStartOfParagraphAction:";
            cursorMoveAndSelectController.configuration = self.topConfiguration ? @"top" : @"bottom";
            [cursorMoveAndSelectController setRootController: [self rootController]];
            [cursorMoveAndSelectController setParentController: [self parentController]];
            [self pushController:cursorMoveAndSelectController];
        }else if ([self.extrasOptions[indexPath.row][@"identifier"] isEqualToString:@"endOfParagraph"]){
            DXPCursorMoveAndSelectEntryController *cursorMoveAndSelectController = [[DXPCursorMoveAndSelectEntryController alloc] init];
            cursorMoveAndSelectController.entryID = @"moveCursorEndOfParagraphAction:";
            cursorMoveAndSelectController.configuration = self.topConfiguration ? @"top" : @"bottom";
            [cursorMoveAndSelectController setRootController: [self rootController]];
            [cursorMoveAndSelectController setParentController: [self parentController]];
            [self pushController:cursorMoveAndSelectController];
        }else if ([self.extrasOptions[indexPath.row][@"identifier"] isEqualToString:@"startOfSentence"]){
            DXPCursorMoveAndSelectEntryController *cursorMoveAndSelectController = [[DXPCursorMoveAndSelectEntryController alloc] init];
            cursorMoveAndSelectController.entryID = @"moveCursorStartOfSentenceAction:";
            cursorMoveAndSelectController.configuration = self.topConfiguration ? @"top" : @"bottom";
            [cursorMoveAndSelectController setRootController: [self rootController]];
            [cursorMoveAndSelectController setParentController: [self parentController]];
            [self pushController:cursorMoveAndSelectController];
        }else if ([self.extrasOptions[indexPath.row][@"identifier"] isEqualToString:@"endOfSentence"]){
            DXPCursorMoveAndSelectEntryController *cursorMoveAndSelectController = [[DXPCursorMoveAndSelectEntryController alloc] init];
            cursorMoveAndSelectController.entryID = @"moveCursorEndOfSentenceAction:";
            cursorMoveAndSelectController.configuration = self.topConfiguration ? @"top" : @"bottom";
            [cursorMoveAndSelectController setRootController: [self rootController]];
            [cursorMoveAndSelectController setParentController: [self parentController]];
            [self pushController:cursorMoveAndSelectController];
        }else if ([self.extrasOptions[indexPath.row][@"identifier"] isEqualToString:@"delete"]){
            DXPDeleteOptions *deleteOptions = [[DXPDeleteOptions alloc] init];
            deleteOptions.entryID = @"deleteAction::";
            deleteOptions.configuration = self.topConfiguration ? @"top" : @"bottom";
            [deleteOptions setRootController: [self rootController]];
            [deleteOptions setParentController: [self parentController]];
            [self pushController:deleteOptions];
        }else if ([self.extrasOptions[indexPath.row][@"identifier"] isEqualToString:@"deleteForward"]){
            DXPDeleteOptions *deleteOptions = [[DXPDeleteOptions alloc] init];
            deleteOptions.entryID = @"deleteForwardAction::";
            deleteOptions.configuration = self.topConfiguration ? @"top" : @"bottom";
            [deleteOptions setRootController: [self rootController]];
            [deleteOptions setParentController: [self parentController]];
            [self pushController:deleteOptions];
        }else if ([self.extrasOptions[indexPath.row][@"identifier"] isEqualToString:@"paste"]){
            DXPPasteOptions *pasteOptions = [[DXPPasteOptions alloc] init];
            pasteOptions.configuration = self.topConfiguration ? @"top" : @"bottom";
            [pasteOptions setRootController: [self rootController]];
            [pasteOptions setParentController: [self parentController]];
            [self pushController:pasteOptions];
        }
    }
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
    NSString *customActionsSTKey = [self scopedKey:kCustomActionsSTkey topKey:kTopCustomActionsSTkey];
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
    NSMutableArray *defaultOrderSelector = [[shortcutsGenerator selectorNameForLongPress:NO] mutableCopy];
    NSMutableArray *defaultOrderSelectorLP = [[shortcutsGenerator selectorNameForLongPress:YES] mutableCopy];
    NSMutableArray *defaultOrder12 = [[shortcutsGenerator imageNameArrayForiOS:0] mutableCopy];
    NSMutableArray *defaultOrder13 = [[shortcutsGenerator imageNameArrayForiOS:1] mutableCopy];
    //NSMutableArray *shortLabel = [[shortcutsGenerator shortenedlabelName] mutableCopy];
    

    //self.fullOrder = @[defaultOrderLabel, defaultOrderSelector, defaultOrderSelectorLP, defaultOrder12, defaultOrder13];
    
    
    NSMutableArray *fullOrderDict = [[NSMutableArray alloc] init];
    NSMutableArray *firstOrderDict = [[NSMutableArray alloc] init];
    
    for (int i = 0; i < [defaultOrderLabel count]; i++){
        if (DXIsHiddenShortcutSelector(defaultOrderSelector[i])) {
            continue;
        }
        if ([@[@"selectAllAction:", @"selectAction:", @"selectLineAction:", @"selectParagraphAction:", @"selectSentenceAction:"] containsObject:defaultOrderSelector[i]]){
            [firstOrderDict addObject: @{
                @"label" : defaultOrderLabel[i],
                @"images12" : defaultOrder12[i],
                @"images13" : defaultOrder13[i],
                @"selector" : defaultOrderSelector[i],
                @"selectorlp" : defaultOrderSelectorLP[i]
                //@"slabel" : shortLabel[i]
            }];
        }
        [fullOrderDict addObject: @{
            @"label" : defaultOrderLabel[i],
            @"images12" : defaultOrder12[i],
            @"images13" : defaultOrder13[i],
            @"selector" : defaultOrderSelector[i],
            @"selectorlp" : defaultOrderSelectorLP[i]
            //@"slabel" : shortLabel[i]
        }];
    }
    
    self.firstOrder = firstOrderDict;
    self.fullOrder = fullOrderDict;
    
    
    //reset custom long press actions
    if (reset){
        prefs[customActionsKey] = @[];
        prefs[customActionsDTKey] = @[];
        prefs[customActionsSTKey] = @[];
        [prefs removeObjectForKey:cacheKey];
        //[prefs removeObjectForKey:kCustomActionskey];
        [[DXPrefsManager sharedInstance] writePrefs:prefs];
        
        //Remove all caches
        NSFileManager *fm = [NSFileManager defaultManager];
        for (NSString *cacheFile in [fm contentsOfDirectoryAtPath:TypeXCachePath error:nil]) {
            [fm removeItemAtPath:[NSString stringWithFormat:@"%@/%@", TypeXCachePath, cacheFile] error:nil];
        }
    }
    
    //NSArray *defaultOrder = @[@"Select All", @"Copy", @"Paste", @"Cut", @"Undo", @"Redo"];
    BOOL newShortcutsAvailable = YES;
    self.currentOrder = [NSMutableArray array];
    self.currentOrder[0] = [NSMutableArray array];
    self.currentOrder[1] = [NSMutableArray array];
    if (prefs[shortcutsKey][0]  && ([prefs[shortcutsKey][0] firstObject] != nil) && !reset){
        NSMutableArray *currentOrderDefault = [prefs[shortcutsKey][0] mutableCopy];
        for (NSInteger i = 0; i < [currentOrderDefault count] && [self.currentOrder[0] count] < maxshortcutpersection; i++){
            if (DXIsHiddenShortcutSelector(currentOrderDefault[i][@"selector"])) continue;
            [self.currentOrder[0] addObject:[currentOrderDefault objectAtIndex:i]];
        }
    }else{
        self.currentOrder[0] = [NSMutableArray array];
        NSMutableArray *defaultOrderDict = [[NSMutableArray alloc] init];
        
        for (int i = 0 ; i < maxdefaultshortcuts ; i++) {
            if (DXIsHiddenShortcutSelector(defaultOrderSelector[i])) continue;
            [defaultOrderDict addObject: @{
                @"label" : defaultOrderLabel[i],
                @"images12" : defaultOrder12[i],
                @"images13" : defaultOrder13[i],
                @"selector" : defaultOrderSelector[i],
                @"selectorlp" : defaultOrderSelectorLP[i]
                //@"slabel" : shortLabel[i]
            }];
        }
        self.currentOrder[0] = defaultOrderDict;
    }
    if (prefs[shortcutsKey][1]  && ([prefs[shortcutsKey][1] firstObject] != nil) && !reset){
        NSMutableArray *currentOrderDefault = [prefs[shortcutsKey][1] mutableCopy];
        for (NSInteger i = 0; i < [currentOrderDefault count]; i++){
            if (DXIsHiddenShortcutSelector(currentOrderDefault[i][@"selector"])) continue;
            [self.currentOrder[1] addObject:[currentOrderDefault objectAtIndex:i]];
        }
        if (newShortcutsAvailable){
            NSMutableArray *fullOrderDict = [[NSMutableArray alloc] init];
            for (int i = 0 ; i < [defaultOrderLabel count] ; i++) {
                if (DXIsHiddenShortcutSelector(defaultOrderSelector[i])) continue;
                [fullOrderDict addObject: @{
                    @"label" : defaultOrderLabel[i],
                    @"images12" : defaultOrder12[i],
                    @"images13" : defaultOrder13[i],
                    @"selector" : defaultOrderSelector[i],
                    @"selectorlp" : defaultOrderSelectorLP[i]
                    //@"slabel" : shortLabel[i]
                }];
            }
            NSMutableArray *newShortcuts = [NSMutableArray arrayWithArray:fullOrderDict];
            [newShortcuts removeObjectsInArray:self.currentOrder[0]];
            [newShortcuts removeObjectsInArray:self.currentOrder[1]];
            for (NSInteger i = 0; i < [newShortcuts count]; i++){
                [self.currentOrder[1] addObject:[newShortcuts objectAtIndex:i]];
            }
            [[DXPrefsManager sharedInstance] writePrefs:prefs];
            
            /*
             //[prefs writeToFile:kPrefsPath atomically:NO];
             if ([NSHomeDirectory() isEqualToString:@"/var/mobile"]) {
             CFPreferencesSetMultiple((__bridge CFDictionaryRef)prefs, nil, (CFStringRef)kIdentifier, kCFPreferencesCurrentUser, kCFPreferencesAnyHost);
             CFPreferencesSynchronize((CFStringRef)kIdentifier, kCFPreferencesCurrentUser, kCFPreferencesAnyHost);
             } else {
             [prefs writeToFile:kPrefsPath atomically:NO];
             }
             */
        }
    }else if ([prefs[shortcutsKey][0] count] != defaultOrderLabel.count || reset){
        self.currentOrder[1] = [NSMutableArray array];
        NSMutableArray *defaultOrderDict = [[NSMutableArray alloc] init];
        
        for (int i = maxdefaultshortcuts ; i < [defaultOrderLabel count] ; i++) {
            if (DXIsHiddenShortcutSelector(defaultOrderSelector[i])) continue;
            [defaultOrderDict addObject: @{
                @"label" : defaultOrderLabel[i],
                @"images12" : defaultOrder12[i],
                @"images13" : defaultOrder13[i],
                @"selector" : defaultOrderSelector[i],
                @"selectorlp" : defaultOrderSelectorLP[i]
                //@"slabel" : shortLabel[i]
            }];
        }
        self.currentOrder[1] = defaultOrderDict;
    }
    
    NSArray *extrasOptionsLabel = @[ LOCALIZED(@"EXTRAS_INSERT_TEXT_CONTENT"), LOCALIZED(@"EXTRAS_PREVIOUS_WORD_BEHAVIOUR"), LOCALIZED(@"EXTRAS_NEXT_WORD_BEHAVIOUR"), LOCALIZED(@"EXTRAS_LINE_START_BEHAVIOUR"), LOCALIZED(@"EXTRAS_LINE_END_BEHAVIOUR"), LOCALIZED(@"EXTRAS_START_OF_PARAGRAPH_BEHAVIOUR"), LOCALIZED(@"EXTRAS_END_OF_PARAGRAPH_BEHAVIOUR"), LOCALIZED(@"EXTRAS_START_OF_SENTENCE_BEHAVIOUR"), LOCALIZED(@"EXTRAS_END_OF_SENTENCE_BEHAVIOUR"), LOCALIZED(@"EXTRAS_DELETE_BEHAVIOUR"), LOCALIZED(@"EXTRAS_DELETE_FORWARD_BEHAVIOUR"), LOCALIZED(@"EXTRAS_PASTE_BEHAVIOUR")];
    NSArray *extrasOptionsID = @[ @"insertText", @"prevWord", @"nextWord", @"lineStart", @"lineEnd", @"startOfParagraph", @"endOfParagraph", @"startOfSentence", @"endOfSentence", @"delete", @"deleteForward", @"paste"];
    NSArray *extrasOptions12 = @[ @"messages_writeboard", @"UICalloutBarPreviousArrow", @"UICalloutBarNextArrow", @"KeyGlyph-rtlTab-larg", @"KeyGlyph-tab-large", @"KeyGlyph-return-large", @"KeyGlyph-rtlReturn-large", @"UIMovieScrubberEditingGlassLeft", @"UIMovieScrubberEditingGlassRight", @"delete_portrait", @"delete_portrait", @"UIButtonBarKeyboardPaste"];
    NSArray *extrasOptions13 = @[ @"text.bubble", @"arrow.left.circle.fill", @"arrow.right.circle.fill", @"arrow.left.to.line", @"arrow.right.to.line", @"text.insert", @"text.append", @"decrease.quotelevel", @"increase.quotelevel", @"delete.left", @"delete.right", @"doc.on.clipboard"];
    
    NSMutableArray *extrasOptionsDict = [[NSMutableArray alloc] init];
    
    for (int i = 0; i < [extrasOptionsLabel count]; i++){
        [extrasOptionsDict addObject: @{
            @"label" : extrasOptionsLabel[i],
            @"images12" : extrasOptions12[i],
            @"images13" : extrasOptions13[i],
            @"identifier" : extrasOptionsID[i],
        }];
    }
    self.extrasOptions = extrasOptionsDict;
    
}

-(void)reset{
    
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"TypeX" message:LOCALIZED(@"RESET_MESSAGE") preferredStyle:UIAlertControllerStyleAlert];
    
    UIAlertAction *resetAction = [UIAlertAction actionWithTitle:LOCALIZED(@"RESET_YES") style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        [self updateOrder:YES];
        [self.tableView.tableHeaderView removeFromSuperview];
        self.tableView.tableHeaderView = nil;
        self.tableView.userInteractionEnabled = YES;
        [self.tableView reloadData];
        [self writeToFile];
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
