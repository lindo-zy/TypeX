#import "common.h"
#import "DXShared.h"
#import "DXCollectionView.h"
#import "DXToastWindowController.h"
#import "DXHelper.h"
#import "DXUIShortTapGestureRecognizer.h"
#import "DXLoremIpsum.h"

#import <objc/runtime.h>
#import <objc/message.h>

static BOOL DXIsHiddenShortcutSelector(NSString *selector) {
    return ![DXShortcutsGenerator isVisibleShortcutSelector:selector];
}

static BOOL DXShortcutCacheContainsHiddenSelectors(NSDictionary *cache) {
    NSArray *fullGroups = cache[@"fullshortcuts"];
    if (![fullGroups isKindOfClass:[NSArray class]] || fullGroups.count < 3 ||
        ![fullGroups[2] isEqual:[[DXShortcutsGenerator sharedInstance] selectorNames]]) return YES;
    NSArray *shortcutGroups = cache[@"shortcuts"];
    if (![shortcutGroups isKindOfClass:[NSArray class]] || shortcutGroups.count < 3) {
        return NO;
    }
    for (NSString *selector in shortcutGroups[2]) {
        if (DXIsHiddenShortcutSelector(selector)) {
            return YES;
        }
    }
    return NO;
}

@implementation DXCollectionView

- (NSString *)scopedPreferenceKey:(NSString *)key {
    return DXScopedPreferenceKey(key, self.configuration ?: @"bottom");
}

- (int)shortcutsPerSection {
    NSString *key = [self scopedPreferenceKey:kShortcutsPerSection];
    // Top and bottom are fully decoupled: each scope uses its own key and falls
    // back only to maxshortcutpersection (6).  The bottom key is never read
    // when the top key is missing, so an unconfigured top toolbar defaults to 6
    // regardless of the bottom toolbar's setting.
    int fallback = maxshortcutpersection;
    int configured = preferencesInt(key, fallback);
    return MAX(1, MIN(configured, maxshortcutpersection));
}

- (instancetype)initWithConfiguration:(NSString *)configuration{
    
    UICollectionViewFlowLayout *flowLayout = [[UICollectionViewFlowLayout alloc] init];
    flowLayout.scrollDirection = UICollectionViewScrollDirectionHorizontal;
    flowLayout.minimumInteritemSpacing = currentBackgroundTintColor?buttonSpacing:0;
    flowLayout.minimumLineSpacing = 0;
    
    
    if (self = [super initWithFrame:CGRectZero collectionViewLayout:flowLayout]) {
        self.configuration = configuration ?: @"bottom";
        //HBLogDebug(@"DXCollectionView initWithConfiguration: %@, shortcutsPerSection: %d", self.configuration, [self shortcutsPerSection]);
        self.shortcutsGenerator = [DXShortcutsGenerator sharedInstance];
        if (!prefs){
            prefs = [[[DXPrefsManager sharedInstance] readPrefsFromSandbox:[DXPrefsManager isRunningInSandbox]] mutableCopy];
        }
        
        
        
        // A cache is only safe when the user has never customized the
        // shortcut order.  On iOS 17 the collection view can
        // outlive the Settings controller, so a stale cache otherwise masks the
        // newly written configuration.
        NSString *shortcutsKey = [self scopedPreferenceKey:kShortcutskey];
        NSString *cacheKey = [self scopedPreferenceKey:kCachekey];
        if (prefs[cacheKey] && !DXShortcutCacheContainsHiddenSelectors(prefs[cacheKey]) &&
            [prefs[cacheKey][@"shortcuts"][kbuttonsImages12] count] <= [self shortcutsPerSection] &&
            !prefs[shortcutsKey]){
            NSDictionary *cache = prefs[cacheKey];
            self.shortcuts = cache[@"shortcuts"];
            self.fullshortcuts = cache[@"fullshortcuts"];
            //HBLogDebug(@"Utilized cache");
        }else{
            //HBLogDebug(@"Update cache");
            
            NSMutableDictionary *cache = [[NSMutableDictionary alloc] init];
            
            
            NSMutableArray *currentOrderDefault12 = [[self.shortcutsGenerator imageNameArrayForiOS:0] mutableCopy];
            NSMutableArray *currentOrderDefault13 =  [[self.shortcutsGenerator imageNameArrayForiOS:1] mutableCopy];
            NSMutableArray *selectorsDefault = [[self.shortcutsGenerator selectorNames] mutableCopy];
            //NSMutableArray *shortLabelDefault = [[self.shortcutsGenerator shortenedlabelName] mutableCopy];
            
            NSMutableArray *currentOrder12 = [[NSMutableArray alloc] init];
            NSMutableArray *currentOrder13 = [[NSMutableArray alloc] init];
            NSMutableArray *selectors = [[NSMutableArray alloc] init];
            //NSMutableArray *shortLabel = [[NSMutableArray alloc] init];
            
            if (prefs[shortcutsKey]){
                
                for (NSDictionary *item in prefs[shortcutsKey][0]){
                    if (currentOrder12.count >= [self shortcutsPerSection]) break;
                    if (DXIsHiddenShortcutSelector(item[@"selector"])){ 
                        continue;
                    }
                    [currentOrder12 addObject:item[@"images12"]];
                    [currentOrder13 addObject:item[@"images13"]];
                    [selectors addObject:item[@"selector"]];
                    //if (item[@"slabel"]){
                    //[shortLabel addObject:item[@"slabel"]];
                    //}else{
                    //useShortenedLabel = NO;
                    //}
                }
            }else{
                for (int i = 0; i < [self shortcutsPerSection]; i++ ){
                    [currentOrder12 addObject:[currentOrderDefault12 objectAtIndex:i]];
                    [currentOrder13 addObject:[currentOrderDefault13 objectAtIndex:i]];
                    [selectors addObject:[selectorsDefault objectAtIndex:i]];
                    //[shortLabel addObject:[shortLabelDefault objectAtIndex:i]];
                }
                //currentOrder12 = [[currentOrderDefault12 subarrayWithRange:NSMakeRange(0, 6)] mutableCopy];
                //currentOrder12 = [[currentOrderDefault13 subarrayWithRange:NSMakeRange(0, 6)] mutableCopy];
                //selectors = [[selectorsDefault subarrayWithRange:NSMakeRange(0, 6)] mutableCopy];
            }
            
            //self.buttonsImages12 = currentOrder12;
            //self.buttonsImages13 = currentOrder13;
            //self.buttonSelectors = selectors;
            self.shortcuts = @[currentOrder12, currentOrder13, selectors];
            self.fullshortcuts = @[currentOrderDefault12, currentOrderDefault13, selectorsDefault];
            cache[@"shortcuts"] = self.shortcuts;
            cache[@"fullshortcuts"] = self.fullshortcuts;
            
            
            dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
                [[DXPrefsManager sharedInstance] setValue:cache forKey:cacheKey fromSandbox:[DXPrefsManager isRunningInSandbox]];
                prefs = [[[DXPrefsManager sharedInstance] readPrefsFromSandbox:[DXPrefsManager isRunningInSandbox]] mutableCopy];
            });
        }
        
        self.hapticType = 1;
        self.refreshView = YES;
        self.firstCellVisible = YES;
        
        self.commandTitle = @"";
        self.insertTextActionType = 0;
        self.isWordSender = NO;
        self.moveCursorWithSelect = NO;
        //self.autoCorrectionEnabled = [self isAutoCorrectionEnabled];    //self.firstInit = YES;
        
        
        self.backgroundColor = [UIColor clearColor];
        self.delegate = self;
        self.dataSource = self;
        self.showsVerticalScrollIndicator = NO;
        self.showsHorizontalScrollIndicator = NO;
        self.pagingEnabled = preferencesBool([self scopedPreferenceKey:kPagingkey], preferencesBool(kPagingkey, YES));
        [self registerClass:NSClassFromString(@"DXCell") forCellWithReuseIdentifier:@"kTypeXCellID"];
        dispatch_async(dispatch_get_main_queue(), ^{
            [self keyboardRotated:nil];
        });
        
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(typeXLayoutChanged:) name:@"typeXLayoutChanged" object:nil];
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(keyboardRotated:) name:UIDeviceOrientationDidChangeNotification object:nil];
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(scrollBackward:) name:@"scrollBackward" object:nil];
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(scrollForward:) name:@"scrollForward" object:nil];
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(updateAutoCorrection:) name:@"updateAutoCorrection" object:nil];
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(updateAutoCapitalization:) name:@"updateAutoCapitalization" object:nil];
        
    }
    
    //HBLogDebug(@"TypeX Init");
    //if (!prefs[@"prevState"]){
    
    /*
     //}
     //dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
     if (@available(iOS 11.0, *)){
     [[DXPrefsManager sharedInstance] setValue:[NSKeyedArchiver archivedDataWithRootObject:self requiringSecureCoding:YES error:nil] forKey:@"prevState" fromSandbox:[DXPrefsManager isRunningInSandbox]];
     }
     //});
     */
    return self;
}


- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self name:@"typeXLayoutChanged" object:nil];
    [[NSNotificationCenter defaultCenter] removeObserver:self name:UIDeviceOrientationDidChangeNotification object:nil];
    [[NSNotificationCenter defaultCenter] removeObserver:self name:@"scrollBackward" object:nil];
    [[NSNotificationCenter defaultCenter] removeObserver:self name:@"scrollForward" object:nil];
    [[NSNotificationCenter defaultCenter] removeObserver:self name:@"updateAutoCorrection" object:nil];
    [[NSNotificationCenter defaultCenter] removeObserver:self name:@"updateAutoCapitalization" object:nil];
    //[[NSNotificationCenter defaultCenter] removeObserver:self name:UITextFieldTextDidBeginEditingNotification object:nil];
    
}

- (void)collectionView:(UICollectionView *)collectionView willDisplayCell:(UICollectionViewCell *)cell forItemAtIndexPath:(NSIndexPath *)indexPath{
    //HBLogDebug(@"willDisplayCell: %@", indexPath);
    if (indexPath.section == 0 && indexPath.row == 0){
        self.firstCellVisible = YES;
    }
}

- (void)collectionView:(UICollectionView *)collectionView didEndDisplayingCell:(UICollectionViewCell *)cell forItemAtIndexPath:(NSIndexPath *)indexPath{
    //HBLogDebug(@"didEndDisplayingCell: %@", indexPath);
    if (indexPath.section == 0 && indexPath.row == 0){
        self.firstCellVisible = NO;
    }
}


-(NSArray *)synthesizeIndexingForIndexOrOffset:(BOOL)index descendingOffset:(BOOL)reverse numberOfItems:(int)itemsCount{
    NSMutableArray *indexArray = [[NSMutableArray alloc] init];
    for (int j = 0; j < 2; j ++){
        for (int i = 0; i < itemsCount; i++){
            if (index){
                [indexArray addObject:[NSNumber numberWithInt:i]];
            }else{
                [indexArray addObject:reverse ? [NSNumber numberWithInt:1 - j] : [NSNumber numberWithInt:j]];
            }
        }
    }
    return indexArray;
}

-(void)scrollBackward:(NSNotification*)notification{
    //HBLogDebug(@"scrollBackward");
    
    NSArray *indexPaths = [self indexPathsForVisibleItems];
    //NSSortDescriptor *sort = [NSSortDescriptor sortDescriptorWithKey:@"row" ascending:YES];
    //NSArray *orderedIndexPaths = [indexPaths sortedArrayUsingDescriptors:@[sort]];
    
    
    
    //NSInteger centerIndex = ceil((float)self.visibleCells.count/2.0f);
    NSMutableArray *universalIndexArray = [[NSMutableArray alloc] init];
    for (NSIndexPath *ip in indexPaths){
        [universalIndexArray addObject:[NSNumber numberWithLong:[self shortcutsPerSection]*ip.section + ip.row]];
    }
    
    
    NSSortDescriptor *sort = [NSSortDescriptor sortDescriptorWithKey:nil ascending:YES];
    NSArray *orderedIndexPaths = [indexPaths sortedArrayUsingDescriptors:@[sort]];
    
    
    //HBLogDebug(@"scrollBackward SORTED: %@", orderedIndexPaths);
    
    NSIndexPath *firstCellIndexPath = [orderedIndexPaths firstObject];
    
    //NSIndexPath *scrollToIndexPath;
    //HBLogDebug(@"scrollBackwardINDEX: %@", firstCellIndexPath);
    
    /*
     if (self.touchEnded){
     self.touchEnded = NO;
     double delayInSeconds = 1;
     dispatch_time_t popTime = dispatch_time(DISPATCH_TIME_NOW, delayInSeconds * NSEC_PER_SEC);
     dispatch_after(popTime, dispatch_get_main_queue(), ^(void){
     self.touchEnded = YES;
     });
     */
    //if (self.firstCellVisible || self.firstInit){
    if (self.firstCellVisible){
        //self.firstInit = NO;
        [[[UIImpactFeedbackGenerator alloc] initWithStyle:UIImpactFeedbackStyleLight] impactOccurred];
        return;
    }
    //}
    
    
    int x = firstCellIndexPath.section;
    int y = firstCellIndexPath.row;
    int G = preferencesInt(kGranularity, granularity) -1;
    //int ymax = [self numberOfItemsInSection:firstCellIndexPath.section] -1;
    int allowedMaxY = [self shortcutsPerSection];
    //HBLogDebug(@"G: %d, y: %d", G, allowedMaxY);
    G = G+1-allowedMaxY>0?allowedMaxY-1:G;
    G = G==0?1:G;
    //HBLogDebug(@"After G: %d, y: %d", G, allowedMaxY);
    
    //NSArray *indexArray = @[@0, @1, @2, @3, @4, @5, @0, @1, @2, @3, @4, @5];
    //NSArray *sectionOffsetArray = @[@1, @1, @1, @1, @1, @1, @0, @0, @0, @0, @0, @0];
    if (!self.indexArray){
        self.indexArray = [NSArray array];
        self.indexArray = [self synthesizeIndexingForIndexOrOffset:YES descendingOffset:YES numberOfItems:[self shortcutsPerSection]];
    }
    if (!self.sectionOffsetBackwardArray){
        self.sectionOffsetBackwardArray = [NSArray array];
        self.sectionOffsetBackwardArray = [self synthesizeIndexingForIndexOrOffset:NO descendingOffset:YES numberOfItems:[self shortcutsPerSection]];
    }
    //HBLogDebug(@"index: %@", indexArray);
    //HBLogDebug(@"offset: %@", sectionOffsetArray);
    
    NSIndexPath *newIndexPath = [NSIndexPath indexPathForRow:[self.indexArray[y+allowedMaxY-(G+1)] intValue]  inSection:x - [self.sectionOffsetBackwardArray[y+allowedMaxY-(G+1)] intValue]];
    [self scrollToItemAtIndexPath:newIndexPath atScrollPosition:UICollectionViewScrollPositionLeft animated:YES];
    //int firstCellGlobalIndex = preferencesInt(kShortcutsPerSection, maxshortcutpersection)*firstCellIndexPath.section + firstCellIndexPath.row;
    //int newRowIndex =  [fullIndexArray[rowIndex - G] intValue];
    
}

-(void)scrollForward:(NSNotification*)notification{
    //HBLogDebug(@"scrollForward");
    NSArray *indexPaths = [self indexPathsForVisibleItems];
    //NSSortDescriptor *sort = [NSSortDescriptor sortDescriptorWithKey:@"row" ascending:YES];
    //NSArray *orderedIndexPaths = [indexPaths sortedArrayUsingDescriptors:@[sort]];
    
    
    
    //NSInteger centerIndex = ceil((float)self.visibleCells.count/2.0f);
    NSMutableArray *universalIndexArray = [[NSMutableArray alloc] init];
    for (NSIndexPath *ip in indexPaths){
        [universalIndexArray addObject:[NSNumber numberWithLong:[self shortcutsPerSection]*ip.section + ip.row]];
    }
    
    NSSortDescriptor *sort = [NSSortDescriptor sortDescriptorWithKey:nil ascending:YES];
    NSArray *orderedIndexPaths = [indexPaths sortedArrayUsingDescriptors:@[sort]];
    
    
    
    //NSInteger centerIndex = ceil((float)self.visibleCells.count/2.0f);
    NSIndexPath *firstCellIndexPath = [orderedIndexPaths firstObject];
    NSIndexPath *lastCellIndexPath = [orderedIndexPaths lastObject];
    //HBLogDebug(@"LAST INDEX: %@", firstCellIndexPath);
    ////HBLogDebug(@"%ld, %ld", self.numberOfSections -1, [self numberOfItemsInSection:lastCellIndexPath.section]);
    //HBLogDebug(@"SORTED: %@", orderedIndexPaths);
    //NSIndexPath *scrollToIndexPath;
    
    
    if ( (lastCellIndexPath.section == self.numberOfSections -1) && (lastCellIndexPath.row == [self numberOfItemsInSection:lastCellIndexPath.section]-1) ){
        [[[UIImpactFeedbackGenerator alloc] initWithStyle:UIImpactFeedbackStyleLight] impactOccurred];
        return;
    }
    
    int x = firstCellIndexPath.section;
    int y = firstCellIndexPath.row;
    int G = preferencesInt(kGranularity, granularity) -1;
    int allowedMaxY = [self shortcutsPerSection];
    //HBLogDebug(@"G: %d, y: %d", G, y);
    G = G+1-allowedMaxY>0?allowedMaxY-1:G;
    G = G==0?1:G;
    //HBLogDebug(@"After G: %d, y: %d", G, allowedMaxY);
    
    //int ymax = [self numberOfItemsInSection:firstCellIndexPath.section] -1;
    //int allowedMaxY = preferencesInt(kShortcutsPerSection, maxshortcutpersection);
    //NSArray *indexArray = @[@0, @1, @2, @3, @4, @5, @0, @1, @2, @3, @4, @5];
    //NSArray *sectionOffsetArray = @[@0, @0, @0, @0, @0, @0, @1, @1, @1, @1, @1, @1];
    if (!self.indexArray){
        self.indexArray = [NSArray array];
        self.indexArray = [self synthesizeIndexingForIndexOrOffset:YES descendingOffset:NO numberOfItems:[self shortcutsPerSection]];
    }
    if (!self.sectionOffsetForwardArray){
        self.sectionOffsetForwardArray = [NSArray array];
        self.sectionOffsetForwardArray = [self synthesizeIndexingForIndexOrOffset:NO descendingOffset:NO numberOfItems:[self shortcutsPerSection]];
    }
    NSIndexPath *newIndexPath = [NSIndexPath indexPathForRow:[self.indexArray[y+G+1] intValue] inSection:x + [self.sectionOffsetForwardArray[y+G+1] intValue]];
    //HBLogDebug(@"index: %@", indexArray);
    //HBLogDebug(@"offset: %@", sectionOffsetArray);
    
    [self scrollToItemAtIndexPath:newIndexPath atScrollPosition:UICollectionViewScrollPositionLeft animated:YES];
    
    //HBLogDebug(@"x: %d, y: %d, ymax: %d, G: %d, allowedMaxY: %d", x, y, ymax, G, allowedMaxY);
    /*
     if (G-y == 0 && G+1==allowedMaxY){
     newIndexPath = [NSIndexPath indexPathForRow:0 inSection:x+1];
     //HBLogDebug(@"Case 1");
     }else if (G+y > ymax){
     newIndexPath = [NSIndexPath indexPathForRow:[indexArray[y+G+1] intValue] inSection:x+1];
     //HBLogDebug(@"Case 2");
     }else if (G+y < ymax){
     newIndexPath = [NSIndexPath indexPathForRow:[indexArray[y+G+1] intValue] inSection:x];
     //HBLogDebug(@"Case 3");
     }else{
     newIndexPath = [NSIndexPath indexPathForRow:0 inSection:x+1];
     //HBLogDebug(@"Case 4");
     }
     [self scrollToItemAtIndexPath:newIndexPath atScrollPosition:UICollectionViewScrollPositionLeft animated:YES];
     */
    /*
     //if (firstCellIndexPath.section != 0){
     if (firstCellIndexPath.row ==  [self numberOfItemsInSection:firstCellIndexPath.section] -1){
     scrollToIndexPath =  [NSIndexPath indexPathForRow:preferencesInt(kGranularity, granularity) - 1 inSection:firstCellIndexPath.section + 1];
     //HBLogDebug(@"1");
     }else if (preferencesInt(kGranularity, granularity) == [self shortcutsPerSection]){
     scrollToIndexPath =  [NSIndexPath indexPathForRow:0 inSection:firstCellIndexPath.section + 1];
     //HBLogDebug(@"3");
     }else if (firstCellIndexPath.row + preferencesInt(kGranularity, granularity) > [self numberOfItemsInSection:firstCellIndexPath.section] -1){
     scrollToIndexPath =  [NSIndexPath indexPathForRow:preferencesInt(kGranularity, granularity) - ([self numberOfItemsInSection:firstCellIndexPath.section] - 1 - firstCellIndexPath.row) inSection:firstCellIndexPath.section + 1];
     //HBLogDebug(@"2, %@ - %@",preferencesInt(kGranularity, granularity),([self numberOfItemsInSection:firstCellIndexPath.section] - 1 - firstCellIndexPath.row));
     }else{
     scrollToIndexPath =  [NSIndexPath indexPathForRow:firstCellIndexPath.row + preferencesInt(kGranularity, granularity) inSection:firstCellIndexPath.section];
     //HBLogDebug(@"4");
     }
     //}
     */
    //[self scrollToItemAtIndexPath:newIndexPath atScrollPosition:UICollectionViewScrollPositionLeft animated:YES];
    
}

-(UITextRange *)selectedWordTextRangeWithDelegate:(id<UITextInput>)delegate{
    BOOL hasRightText = [delegate.tokenizer isPosition:delegate.selectedTextRange.start withinTextUnit:UITextGranularityWord inDirection:UITextLayoutDirectionRight];
    UITextStorageDirection direction = hasRightText ? UITextStorageDirectionForward : UITextStorageDirectionBackward;
    UITextRange *range = [delegate.tokenizer rangeEnclosingPosition:delegate.selectedTextRange.start
                                                    withGranularity:UITextGranularityWord
                                                        inDirection:direction];
    if (!range) {
        UITextPosition *p = [delegate.tokenizer positionFromPosition:delegate.selectedTextRange.start toBoundary:UITextGranularityWord inDirection:UITextStorageDirectionBackward];
        range = [delegate.tokenizer rangeEnclosingPosition:p withGranularity:UITextGranularityWord inDirection:UITextStorageDirectionBackward];
    }
    return range;
}

-(UITextRange *)selectedWordTextRangeWithDelegate:(id<UITextInput>)delegate direction:(UITextStorageDirection)direction{
    UITextRange *range = [delegate.tokenizer rangeEnclosingPosition:delegate.selectedTextRange.start
                                                    withGranularity:UITextGranularityWord
                                                        inDirection:direction];
    if (!range) {
        if (direction == UITextStorageDirectionBackward) {
            UITextPosition *p = [delegate.tokenizer positionFromPosition:delegate.selectedTextRange.start toBoundary:UITextGranularityWord inDirection:UITextStorageDirectionBackward];
            if (!p)
                p = [delegate.tokenizer positionFromPosition:delegate.selectedTextRange.start toBoundary:UITextGranularityLine inDirection:UITextLayoutDirectionUp];
            range = [delegate.tokenizer rangeEnclosingPosition:p withGranularity:UITextGranularityWord inDirection:UITextStorageDirectionBackward];
        } else {
            UITextPosition *p = [delegate.tokenizer positionFromPosition:delegate.selectedTextRange.start toBoundary:UITextGranularityWord inDirection:UITextStorageDirectionForward];
            if (!p)
                p = [delegate.tokenizer positionFromPosition:delegate.selectedTextRange.end toBoundary:UITextGranularityLine inDirection:UITextLayoutDirectionDown];
            range = [delegate.tokenizer rangeEnclosingPosition:p withGranularity:UITextGranularityWord inDirection:UITextStorageDirectionForward];
        }
    }
    return range;
}

-(void)moveCursorVerticalWithDelegate:(id<UITextInput>)delegate direction:(UITextLayoutDirection)direction{
    UITextPosition *position = [delegate positionFromPosition:delegate.selectedTextRange.start inDirection:direction offset:1];
    if (!position) return;
    UITextRange *range = [delegate textRangeFromPosition:position toPosition:position];
    delegate.selectedTextRange = range;
    //RevealSelection(delegate);
}

-(UITextRange *)autoDirectionWordSelectedTextRangeWithDelegate:(id<UITextInput> )delegate{
    BOOL hasRightText = [delegate.tokenizer isPosition:delegate.selectedTextRange.start withinTextUnit:UITextGranularityWord inDirection:UITextLayoutDirectionRight];
    UITextStorageDirection direction = hasRightText ? UITextStorageDirectionForward : UITextStorageDirectionBackward;
    return [self selectedWordTextRangeWithDelegate:delegate direction:direction];
}


-(UITextRange *)singleWordTextRangeWithDelegate:(id<UITextInput>)delegate direction:(UITextStorageDirection)direction{
    UITextRange *range = [self selectedWordTextRangeWithDelegate:delegate direction:direction];
    if (direction == UITextStorageDirectionForward)
        return [delegate textRangeFromPosition:range.end toPosition:range.end];
    else
        return [delegate textRangeFromPosition:range.start toPosition:range.start];
}

-(UITextRange *)lineExtremityTextRangeWithDelegate:(id<UITextInput>)delegate direction:(UITextLayoutDirection)direction{
    id<UITextInputTokenizer> tokenizer = delegate.tokenizer;
    UITextPosition *lineEdgePosition = [tokenizer positionFromPosition:delegate.selectedTextRange.end toBoundary:UITextGranularityLine inDirection:direction];
    // for until iOS 6 component.
    if ([lineEdgePosition isMemberOfClass:objc_getClass("UITextPositionImpl")])
        return [delegate textRangeFromPosition:lineEdgePosition toPosition:lineEdgePosition];
    // for iOS 7 buggy _UITextKitTextPosition workaround.
    for (int i=1; i<1000; i++) {
        lineEdgePosition = [delegate positionFromPosition:delegate.selectedTextRange.start inDirection:direction offset:i];
        NSComparisonResult result = [delegate comparePosition:lineEdgePosition
                                                   toPosition:(direction == UITextLayoutDirectionLeft) ? delegate.beginningOfDocument : delegate.endOfDocument];
        if (!lineEdgePosition || result == NSOrderedSame)
            return [delegate textRangeFromPosition:lineEdgePosition toPosition:lineEdgePosition];
        UITextRange *range = [delegate textRangeFromPosition:delegate.selectedTextRange.start toPosition:lineEdgePosition];
        NSString *text = [delegate textInRange:range];
        if ([text hasPrefix:@"\n"] || [text hasSuffix:@"\n"]) {
            lineEdgePosition = [delegate positionFromPosition:delegate.selectedTextRange.start inDirection:direction offset:i-1];
            return [delegate textRangeFromPosition:lineEdgePosition toPosition:lineEdgePosition];
        }
    }
    return nil;
}

-(void)moveCursorSingleWordWithDelegate:(id <UITextInput, UITextInputTokenizer>)delegate direction:(UITextStorageDirection)direction{
    if (delegate) {
        BOOL isRTL  = [self isRTLForDelegate:delegate];
        if (isRTL){
            if (direction == UITextStorageDirectionForward){
                direction = UITextStorageDirectionBackward;
            }else{
                direction = UITextStorageDirectionForward;
            }
        }
        UITextRange *textRange = [self singleWordTextRangeWithDelegate:delegate direction:direction];
        if (!textRange) return;
        [delegate setSelectedTextRange:textRange];
    }
}

-(void)moveCursorToLineExtremityWithDelegate:(id <UITextInput, UITextInputTokenizer>)delegate direction:(UITextLayoutDirection)direction{
    if (delegate) {
        BOOL isRTL  = [self isRTLForDelegate:delegate];
        if (isRTL){
            if (direction == UITextLayoutDirectionLeft){
                direction = UITextLayoutDirectionRight;
            }else{
                direction = UITextLayoutDirectionLeft;
            }
        }
        UITextRange *textRange = [self lineExtremityTextRangeWithDelegate:delegate direction:direction];
        if (!textRange) return;
        [delegate setSelectedTextRange:textRange];
    }
}

-(BOOL)isRTLForDelegate:(UIResponder *)delegate {
    UIKeyboardExtensionInputMode *inputMode = delegate.textInputMode;
    return [inputMode isDefaultRightToLeft];
    
}

- (NSInteger)currentCursorPosition:(id <UITextInput, UITextInputTokenizer>)delegate{
    UITextRange *selectedRange = delegate.selectedTextRange;
    UITextPosition *textPosition = selectedRange.start;
    return [delegate offsetFromPosition:delegate.beginningOfDocument toPosition:textPosition];
}


-(void)moveCursorWithDelegate:(id <UITextInput, UITextInputTokenizer>)delegate offset:(int)offset{
    if (delegate) {
        BOOL isRTL  = [self isRTLForDelegate:delegate];
        UITextPosition *textPosition;
        if (isRTL){
            textPosition = [delegate positionFromPosition:delegate.beginningOfDocument offset:([self currentCursorPosition:delegate]-offset)];
        }else{
            textPosition = [delegate positionFromPosition:delegate.beginningOfDocument offset:([self currentCursorPosition:delegate]+offset)];
        }
        
        [delegate setSelectedTextRange:[delegate textRangeFromPosition:textPosition toPosition:textPosition]];
    }
}

-(void)setAutoPaginationControlEnabled{
    self.pagingEnabled = YES;
}

-(void)autoPaginationControl{
    if (isPagingEnabled && self.pagingEnabled){
        self.pagingEnabled = NO;
    }else if (isPagingEnabled && !self.pagingEnabled){
        if (!self.autoPaginationDispatchBlock){
            self.autoPaginationDispatchBlock = dispatch_block_create(0, ^{
                self.pagingEnabled = YES;
                self.autoPaginationDispatchBlock = nil;
            });
            
        }
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.1 * NSEC_PER_SEC)), dispatch_get_main_queue(), self.autoPaginationDispatchBlock);
    }
}

-(void)reloadShortcutConfiguration{
    NSDictionary *currentPrefs = [[DXPrefsManager sharedInstance] readPrefsFromSandbox:[DXPrefsManager isRunningInSandbox]];
    if (![currentPrefs isKindOfClass:[NSDictionary class]]) currentPrefs = @{};
    prefs = [currentPrefs mutableCopy];
    //HBLogDebug(@"reloadShortcutConfiguration configuration=%@ shortcutsPerSection=%d scopedKey=%@", self.configuration, [self shortcutsPerSection], [self scopedPreferenceKey:kShortcutskey]);
    NSMutableArray *defaultImages12 = [[self.shortcutsGenerator imageNameArrayForiOS:0] mutableCopy];
    NSMutableArray *defaultImages13 = [[self.shortcutsGenerator imageNameArrayForiOS:1] mutableCopy];
    NSMutableArray *defaultSelectors = [[self.shortcutsGenerator selectorNames] mutableCopy];

    NSMutableArray *images12 = [NSMutableArray array];
    NSMutableArray *images13 = [NSMutableArray array];
    NSMutableArray *selectors = [NSMutableArray array];
    NSString *shortcutsKey = [self scopedPreferenceKey:kShortcutskey];
    NSArray *configuredShortcuts = currentPrefs[shortcutsKey];

    // Top and bottom shortcuts are fully decoupled.  When a scoped key has no
    // persisted value (e.g. user never opened "顶部设置"), the else-branch
    // below uses the default set (first N actions from DXShortcutsGenerator).
    // The bottom configuration is never inherited by the top toolbar.

    if ([configuredShortcuts isKindOfClass:[NSArray class]] && configuredShortcuts.count > 0) {
        for (NSDictionary *item in configuredShortcuts[0]) {
            if (images12.count >= [self shortcutsPerSection]) break;
            if (![item isKindOfClass:[NSDictionary class]]) continue;
            NSString *selector = item[@"selector"];
            if (DXIsHiddenShortcutSelector(selector)) continue;
            if (item[@"images12"] && item[@"images13"] && selector) {
                [images12 addObject:item[@"images12"]];
                [images13 addObject:item[@"images13"]];
                [selectors addObject:selector];
            }
        }
    } else {
        NSUInteger count = MIN((NSUInteger)[self shortcutsPerSection],
                               MIN(defaultImages12.count,
                                   MIN(defaultImages13.count, defaultSelectors.count)));
        for (NSUInteger index = 0; index < count; index++) {
            [images12 addObject:defaultImages12[index]];
            [images13 addObject:defaultImages13[index]];
            [selectors addObject:defaultSelectors[index]];
        }
    }

    self.shortcuts = @[images12, images13, selectors];
    //HBLogDebug(@"reloadShortcutConfiguration built shortcuts count=%lu for scope=%@", (unsigned long)images12.count, self.configuration);
    self.fullshortcuts = @[defaultImages12, defaultImages13, defaultSelectors];
    self.pagingEnabled = preferencesBool([self scopedPreferenceKey:kPagingkey], preferencesBool(kPagingkey, YES));
    self.indexArray = nil;
    self.sectionOffsetForwardArray = nil;
    self.sectionOffsetBackwardArray = nil;
}


-(void)typeXLayoutChanged:(NSNotification*)notification{
    //self.hidden = isLandscape||isDictating?YES:NO;
    //[self reloadData];
    if (toggledOn){
        if (self.refreshView){
            //HBLogDebug(@"&&&&&&&&&& typeXLayoutChanged shouldPerformBatchUpdate: %d", shouldPerformBatchUpdate?1:0);
            [UIView performWithoutAnimation:^{
                //[self reloadItemsAtIndexPaths:[self indexPathsForVisibleItems]];
                if (shouldPerformBatchUpdate){
                    [self performBatchUpdates:^{
                        [self reloadData];
                    } completion:^(BOOL finished) {}];
                }else{
                    [self reloadData];
                    [self performBatchUpdates:^{} completion:^(BOOL finished) {
                        shouldPerformBatchUpdate = YES;
                    }];
                }
                
            }];
        }
        
        /*
         
         NSDictionary* userInfo = notification.userInfo;
         @try {
         if (self.refreshView)
         [UIView performWithoutAnimation:^{
         if ([userInfo[@"fullreload"] boolValue]){
         //HBLogDebug(@"BEFORE SHORTCUTS: %@", self.shortcuts);
         //[self reloadData];
         [self performBatchUpdates:^{
         [self reloadData];
         } completion:^(BOOL finished) {}];
         
         //HBLogDebug(@"AFTER SHORTCUTS: %@", self.shortcuts);
         }else{
         //HBLogDebug(@"BEFORE SHORTCUTS: %@", self.shortcuts);
         //[self reloadData];
         //HBLogDebug(@"VISIBLECELLS: %@", [self indexPathsForVisibleItems]);
         [self performBatchUpdates:^{
         [self reloadData];
         } completion:^(BOOL finished) {}];
         
         //[self reloadItemsAtIndexPaths:[self indexPathsForVisibleItems]];
         //HBLogDebug(@"AFTER SHORTCUTS: %@", self.shortcuts);
         
         }
         }];
         } @catch (NSException *exception) {
         if (self.refreshView)
         [UIView performWithoutAnimation:^{
         //HBLogDebug(@"BEFORE SHORTCUTS: %@", self.shortcuts);
         //[self reloadData];
         [self performBatchUpdates:^{
         [self reloadData];
         } completion:^(BOOL finished) {}];
         
         //HBLogDebug(@"AFTER SHORTCUTS: %@", self.shortcuts);                }];
         } @finally {
         
         }
         */
    }
    //[self reloadItemsAtIndexPaths:[self indexPathsForVisibleItems]] ;
}

- (void)keyboardRotated:(NSNotification *)notification {
    
    if (toggledOn){
        UIInterfaceOrientation orientation = DXCurrentInterfaceOrientation();
        isLandscape = UIInterfaceOrientationIsLandscape(orientation);
        if (self.refreshView){
            //HBLogDebug(@"&&&&&&&&&& keyboardRotated shouldPerformBatchUpdate: %d", shouldPerformBatchUpdate?1:0);
            [UIView performWithoutAnimation:^{
                //[self reloadItemsAtIndexPaths:[self indexPathsForVisibleItems]];
                if (shouldPerformBatchUpdate){
                    [self performBatchUpdates:^{
                        [self reloadData];
                    } completion:^(BOOL finished) {}];
                }else{
                    [self reloadData];
                    [self performBatchUpdates:^{} completion:^(BOOL finished) {
                        shouldPerformBatchUpdate = YES;
                    }];
                }
                
            }];
        }
    }
    
    
    
    /*
     //self.hidden = isLandscape||isDictating ? YES : NO;
     @try {
     if (self.refreshView)
     [UIView performWithoutAnimation:^{
     //[self reloadItemsAtIndexPaths:[self indexPathsForVisibleItems]];
     [self performBatchUpdates:^{
     [self reloadData];
     } completion:^(BOOL finished) {}];
     
     }];
     } @catch (NSException *exception) {
     if (self.refreshView)
     [UIView performWithoutAnimation:^{
     //[self reloadData];
     [self performBatchUpdates:^{
     [self reloadData];
     } completion:^(BOOL finished) {}];
     
     }];
     } @finally {
     
     }
     }
     */
}


-(void)shakeButton:(UIButton *)sender{
    if (preferencesBool(kShakeShortcutkey,YES)){
        self.refreshView = NO;
        CABasicAnimation *shake = [CABasicAnimation animationWithKeyPath:@"position"];
        [shake setDuration:0.05];
        [shake setRepeatCount:2];
        [shake setAutoreverses:YES];
        [shake setFromValue:[NSValue valueWithCGPoint:
                             CGPointMake(sender.center.x - 5,sender.center.y)]];
        [shake setToValue:[NSValue valueWithCGPoint:
                           CGPointMake(sender.center.x + 5, sender.center.y)]];
        [sender.layer removeAllAnimations];
        [sender.layer addAnimation:shake forKey:@"position"];
        double delayInSeconds = 1;
        dispatch_time_t popTime = dispatch_time(DISPATCH_TIME_NOW, delayInSeconds * NSEC_PER_SEC);
        dispatch_after(popTime, dispatch_get_main_queue(), ^(void){
            self.refreshView = YES;
        });
    }
    //HBLogDebug(@"shakeButton: %@", sender);
    
}

-(void)shakeView:(UIView *)sender{
    if (preferencesBool(kShakeShortcutkey,YES)){
        self.refreshView = NO;
        CABasicAnimation *shake = [CABasicAnimation animationWithKeyPath:@"position"];
        [shake setDuration:0.05];
        [shake setRepeatCount:2];
        [shake setAutoreverses:YES];
        [shake setFromValue:[NSValue valueWithCGPoint:
                             CGPointMake(sender.center.x - 5,sender.center.y)]];
        [shake setToValue:[NSValue valueWithCGPoint:
                           CGPointMake(sender.center.x + 5, sender.center.y)]];
        [sender.layer removeAllAnimations];
        [sender.layer addAnimation:shake forKey:@"position"];
        double delayInSeconds = 1;
        dispatch_time_t popTime = dispatch_time(DISPATCH_TIME_NOW, delayInSeconds * NSEC_PER_SEC);
        dispatch_after(popTime, dispatch_get_main_queue(), ^(void){
            self.refreshView = YES;
        });
    }
}

-(NSString *)convertColorToString:(UIColor *)colorname{
    if(colorname==[UIColor whiteColor] ){
        colorname= [UIColor colorWithRed:1 green:1 blue:1 alpha:1];
    }
    else if(colorname==[UIColor blackColor]){
        colorname= [UIColor colorWithRed:0 green:0 blue:0 alpha:1];
    }
    CGColorRef colorRef = colorname.CGColor;
    NSString *colorString = [CIColor colorWithCGColor:colorRef].stringRepresentation;
    return colorString;
}

-(NSString *)getImageNameForActionName:(NSString *)actionname{
    
    //actionname = [actionname stringByReplacingOccurrencesOfString:@"LP:" withString:@":"];
    
    if ([actionname isEqualToString:@"autoCorrectionAction:"]){
        if (@available(iOS 13.0, *)){
            return  !self.autoCorrectionEnabled?@"checkmark.circle.fill":@"checkmark.circle";
        }else{
            return  !self.autoCorrectionEnabled?@"UIAccessoryButtonCheckmark":@"UIAccessoryButtonX";
        }
    }else if ([actionname isEqualToString:@"autoCapitalizationAction:"]){
        if (@available(iOS 13.0, *)){
            return  !self.autoCapitalizationEnabled?@"shift.fill":@"shift";
        }else{
            return  !self.autoCapitalizationEnabled?@"shift_on_portrait":@"shift_portrait";
        }
    }
    
    
    NSPredicate *predicate = [NSPredicate predicateWithFormat:@"SELF contains[cd] %@", actionname];
    NSUInteger idx = [self.fullshortcuts[2]  indexOfObjectPassingTest:^(id obj, NSUInteger idx, BOOL *stop) {
        return [predicate evaluateWithObject:obj];
    }];
    
    if (@available(iOS 13.0, *)){
        return self.fullshortcuts[1][idx];
    }else{
        return self.fullshortcuts[0][idx];
    }
    
}

-(void)sendShowToastRequestWithMessage:(NSString *)message imagePath:(NSString *)imagepath imageTint:(UIColor *)imagetint width:(int)width height:(int)height position:(float)position duration:(double)duration alpha:(float)alpha radius:(float)radius textColor:(UIColor *)textColor backgroundColor:(UIColor *)backgroundColor displayType:(int)displayType{
    
    //HBLogDebug(@"%@",NSStringFromClass([[UIApplication sharedApplication] class]));
    NSDictionary *userInfo = [NSDictionary dictionaryWithObjectsAndKeys:
                              message, @"message",
                              imagepath, @"imagepath",
                              [NSNumber numberWithInt:width], @"width",
                              [NSNumber numberWithInt:height], @"height",
                              [NSNumber numberWithFloat:position], @"position",
                              [NSNumber numberWithDouble:duration], @"duration",
                              [NSNumber numberWithDouble:alpha], @"alpha",
                              [NSNumber numberWithDouble:radius], @"radius",
                              [self convertColorToString:textColor], @"textColor",
                              [self convertColorToString:backgroundColor], @"backgroundColor",
                              [self convertColorToString:imagetint], @"imagetint",
                              [NSNumber numberWithInt:displayType], @"displayType",
                              nil];
    
    //if (![NSStringFromClass([[UIApplication sharedApplication] class]) isEqualToString:@"SpringBoard"]){
    [[DXToastWindowController sharedInstance] showToastRequest:@"showToastRequest" withUserInfo:userInfo];
    
    
    
}

- (CGFloat)widthOfString:(NSString *)string withFont:(UIFont *)font {
	if (!string) return .0f;
    NSDictionary *attributes = [NSDictionary dictionaryWithObjectsAndKeys:font, NSFontAttributeName, nil];
    return [[[NSAttributedString alloc] initWithString:string attributes:attributes] size].width;
}

-(void)triggerImpactAndAnimationWithButton:(UIButton *)sender selectorName:(NSString *)selname toastWidthOffset:(int)woffset toastHeightOffset:(int)hoffset{
    //haptic, 0=none, 1=once, 2==success(twice)
    if ( preferencesBool(kEnabledHaptickey,YES) && self.hapticType != 0){
        
        if (self.hapticType == 1){
            [[[UIImpactFeedbackGenerator alloc] initWithStyle:UIImpactFeedbackStyleLight] impactOccurred];
        }else{
            [[[UINotificationFeedbackGenerator alloc] init] notificationOccurred:UINotificationFeedbackTypeSuccess];
            self.hapticType = 1;
        }
    }
    if ( preferencesBool(kToastkey,YES) ){
        int th = toastHeight;
        int tw = toastWidth;
        if (preferencesInt(kDisplayTypekey, 0) == 1){
            th = 30;
            //tw = 100;
        }
        //NSString *actionName = selname;
        
        NSString *actionName = [DXHelper localizedStringOfToastForActionNamed:selname bundle:tweakBundle];
        
        //HBLogDebug(@"^^^^^^^^^actionName: %@", actionName);
        if ([selname containsString:@"runCommandAction"]){
            actionName = self.commandTitle;
            //if (preferencesInt(kDisplayTypekey, 0) == 1){
            //tw = tw + 15;
            //}
            selname = @"runCommandAction:";
        }else if ([selname isEqualToString:@"autoCorrectionAction:"]){
            actionName = !self.autoCorrectionEnabled?LOCALIZED(@"TOAST_ON"):LOCALIZED(@"TOAST_OFF");
        }else if ([selname isEqualToString:@"autoCapitalizationAction:"]){
            actionName = !self.autoCapitalizationEnabled?LOCALIZED(@"TOAST_ON"):LOCALIZED(@"TOAST_OFF");
        }
        /*
         else if ([selname isEqualToString:@"insertTextAction:"]){
         actionName = @"Insert";
         }else if ([selname isEqualToString:@"deleteForwardAction:"]){
         actionName = @"Delete";
         }else{
         actionName = [selname stringByReplacingOccurrencesOfString:@"Action:" withString:@""];
         
         if ([selname isEqualToString:@"moveCursorPreviousWordAction:"] || [selname isEqualToString:@"selectSentenceAction:"]){
         if (preferencesInt(kDisplayTypekey, 0) == 1){
         tw = tw + 30;
         }
         }
         
         if ([selname isEqualToString:@"moveCursorStartOfParagraphAction:"] || [selname isEqualToString:@"moveCursorEndOfParagraphAction:"] || [selname isEqualToString:@"moveCursorStartOfSentenceAction:"] || [selname isEqualToString:@"moveCursorEndOfSentenceAction:"] || [selname isEqualToString:@"selectParagraphAction:"]){
         if (preferencesInt(kDisplayTypekey, 0) == 1){
         tw = tw + 60;
         }
         }
         
         actionName = [actionName stringByReplacingOccurrencesOfString:@"Keyboard" withString:@""];
         actionName = [actionName stringByReplacingOccurrencesOfString:@"moveCursor" withString:@""];
         actionName = [actionName stringByReplacingOccurrencesOfString:@"autoCorrection" withString:!self.autoCorrectionEnabled?@"On":@"Off"];
         actionName = [actionName stringByReplacingOccurrencesOfString:@"autoCapitalization" withString:!self.autoCapitalizationEnabled?@"On":@"Off"];
         NSRegularExpression *regexp = [NSRegularExpression
         regularExpressionWithPattern:@"([a-z])([A-Z])"
         options:0
         error:NULL];
         actionName = [regexp
         stringByReplacingMatchesInString:actionName
         options:0
         range:NSMakeRange(0, actionName.length)
         withTemplate:@"$1 $2"];
         actionName = [actionName capitalizedString];
         }
         */
        
        if (preferencesInt(kDisplayTypekey, 0) == 1){
            tw = (int)([self widthOfString:actionName withFont:[UIFont systemFontOfSize:18]] + 0.5f) + 25;
            //tw = 10*[actionName length] - 20;
        }
        float normalizedToastY = preferencesFloat(kToastPy, toastPosition);
        normalizedToastY = normalizedToastY > 0.95 ? 0.95 : normalizedToastY ;
        normalizedToastY = normalizedToastY < 0.05 ? 0.05 : normalizedToastY;
        [self sendShowToastRequestWithMessage:actionName imagePath:[self getImageNameForActionName:selname] imageTint:toastTintColor width:tw+woffset height:th+hoffset position:normalizedToastY duration:preferencesFloat(kToastDurationkey, toastDuration) alpha:toastAlpha radius:toastRadius textColor:toastTextColor backgroundColor:toastBackgroundTintColor displayType:preferencesInt(kDisplayTypekey, 0)];
    }
    [self shakeButton:sender];
}

-(void)beginUpdateDelegate{
    kbImpl = [objc_getClass("UIKeyboardImpl") activeInstance];
    delegate = DXKeyboardInputDelegate(kbImpl);
}

-(void)beginImpactAnimationAndUpdateDelegate:(SEL)action sender:(UIButton *)sender toastWidthOffset:(int)toastWidthOffset toastHeightOffset:(int)toastHeightOffset{
    [self triggerImpactAndAnimationWithButton:sender selectorName:NSStringFromSelector(action) toastWidthOffset:toastWidthOffset toastHeightOffset:toastHeightOffset];
    [self beginUpdateDelegate];
}

#pragma mark actions
-(void)selectAllAction:(UIButton*)sender{
    [self autoPaginationControl];
    [self beginImpactAnimationAndUpdateDelegate:_cmd sender:sender toastWidthOffset:0  toastHeightOffset:0];
    
    if ([delegate respondsToSelector:@selector(selectAll:)]) {
        [delegate selectAll:nil];
    }else if ([delegate respondsToSelector:@selector(selectAll)]) {
        [delegate selectAll];
        
        [kbImpl clearTransientState];
        [kbImpl clearAnimations];
        [kbImpl setCaretBlinks:YES];
    }
    [self autoPaginationControl];
}

-(void)selectLineAction:(UIButton*)sender{
    [self autoPaginationControl];
    [self beginImpactAnimationAndUpdateDelegate:_cmd sender:sender toastWidthOffset:0  toastHeightOffset:0];
    
    [delegate _moveToStartOfLine:NO withHistory:nil];
    [delegate _moveToEndOfLine:YES withHistory:nil];
    [self autoPaginationControl];
}

-(void)selectParagraphAction:(UIButton*)sender{
    [self autoPaginationControl];
    [self beginImpactAnimationAndUpdateDelegate:_cmd sender:sender toastWidthOffset:0  toastHeightOffset:0];
    
    [delegate _moveToStartOfParagraph:NO withHistory:nil];
    [delegate _moveToEndOfParagraph:YES withHistory:nil];;
    [self autoPaginationControl];
}

-(void)selectSentenceAction:(UIButton*)sender{
    [self autoPaginationControl];
    [self beginImpactAnimationAndUpdateDelegate:_cmd sender:sender toastWidthOffset:0  toastHeightOffset:0];
    UIResponder <UITextInput> *tempDelegate = (UIResponder <UITextInput, UITextInputTokenizer> *)delegate;
    
    UITextPosition *startPositionTemp = tempDelegate.selectedTextRange.start;
    UITextPosition *startPositionSentence = ((UITextRange * )[tempDelegate _rangeOfSentenceEnclosingPosition:startPositionTemp]).start;
    UITextPosition *endPositionSentence = ((UITextRange * )[tempDelegate _rangeOfSentenceEnclosingPosition:startPositionTemp]).end;
    
    BOOL isWKContentView = [tempDelegate isKindOfClass:objc_getClass("WKContentView")];
    
    if (isWKContentView){
        
    }else{
        UITextRange *textRange = [tempDelegate textRangeFromPosition:startPositionSentence toPosition:endPositionSentence];
        [tempDelegate setSelectedTextRange:textRange];
    }
    [self autoPaginationControl];
}


-(void)copyAction:(UIButton*)sender{
    [self autoPaginationControl];
    [self beginImpactAnimationAndUpdateDelegate:_cmd sender:sender toastWidthOffset:0  toastHeightOffset:0];
    
    if ([delegate respondsToSelector:@selector(copy:)]) {
        [delegate copy:nil]; //UIResponderStandardEditActions.h
    }else{
        if ([delegate respondsToSelector:@selector(selectedTextRange)]) {
            UITextRange *range = [delegate selectedTextRange];
            NSString *textRange = [delegate textInRange:range];
            UIPasteboard *pasteboard = [UIPasteboard generalPasteboard];
            
            [pasteboard setString:textRange];
            
            [kbImpl clearTransientState];
            [kbImpl clearAnimations];
            [kbImpl setCaretBlinks:YES];
        }
    }
    [self autoPaginationControl];
}

-(BOOL)isValidURL:(NSString *)urlString{
    NSURL *url = [NSURL URLWithString:urlString];
    BOOL isUrl = NO;
    if (url && url.scheme && url.host) isUrl = YES;
    return isUrl;
}

-(void)pasteAction:(UIButton*)sender{
    [self autoPaginationControl];
    [self beginImpactAnimationAndUpdateDelegate:_cmd sender:sender toastWidthOffset:0  toastHeightOffset:0];
    
    BOOL isUnifiedField = [delegate isKindOfClass:objc_getClass("UnifiedField")];
    int pasteAndGoType = preferencesInt(kPasteAndGoEnabledkey, 2);
    if (pasteAndGoType > 0 && isSafari && isUnifiedField){
        if (pasteAndGoType == 1 && [self isValidURL:[[UIPasteboard generalPasteboard] string]]){
            if ([((UnifiedField *)delegate).delegate respondsToSelector:@selector(unifiedFieldShouldPasteAndNavigate:)]){
                [((UnifiedField *)delegate).delegate unifiedFieldShouldPasteAndNavigate:nil];
                return;
            }
        }else if (pasteAndGoType == 2){
            if ([((UnifiedField *)delegate).delegate respondsToSelector:@selector(unifiedFieldShouldPasteAndNavigate:)]){
                [((UnifiedField *)delegate).delegate unifiedFieldShouldPasteAndNavigate:nil];
                return;
            }
        }
    }
    
    if ([delegate respondsToSelector:@selector(paste:)]) {
        [delegate paste:nil]; //UIResponderStandardEditActions.h
    }else{
        if ([delegate respondsToSelector:@selector(selectedTextRange)]) {
            UIPasteboard *pasteboard = [UIPasteboard generalPasteboard];
            
            NSString *copiedtext = [pasteboard string];
            
            if (copiedtext) {
                [kbImpl insertText:copiedtext];
            }
            
            [kbImpl clearTransientState];
            [kbImpl clearAnimations];
            [kbImpl setCaretBlinks:YES];
            
        }
    }
    [self autoPaginationControl];
}

-(void)cutAction:(UIButton*)sender{
    [self autoPaginationControl];
    [self beginImpactAnimationAndUpdateDelegate:_cmd sender:sender toastWidthOffset:10  toastHeightOffset:0];
    
    if ([delegate respondsToSelector:@selector(cut:)]) {
        [delegate cut:nil]; //UIResponderStandardEditActions.h
    }else if ([delegate respondsToSelector:@selector(selectedTextRange)]) {
        UITextRange *range = [delegate selectedTextRange];
        NSString *textRange = [delegate textInRange:range];
        UIPasteboard *pasteboard = [UIPasteboard generalPasteboard];
        
        [pasteboard setString:textRange];
        
        [kbImpl deleteFromInput];
        [kbImpl clearTransientState];
        [kbImpl clearAnimations];
        [kbImpl setCaretBlinks:YES];
    }
    [self autoPaginationControl];
}

-(void)undoAction:(UIButton*)sender{
    [self autoPaginationControl];
    [self beginImpactAnimationAndUpdateDelegate:_cmd sender:sender toastWidthOffset:0  toastHeightOffset:0];
    if ([[delegate undoManager] canUndo]) {
        [[delegate undoManager] undo];
        
        [kbImpl clearTransientState];
        [kbImpl clearAnimations];
        [kbImpl setCaretBlinks:YES];
    }
    [self autoPaginationControl];
}

-(void)redoAction:(UIButton*)sender{
    [self autoPaginationControl];
    [self beginImpactAnimationAndUpdateDelegate:_cmd sender:sender toastWidthOffset:0  toastHeightOffset:0];
    if ([[delegate undoManager] canRedo]) {
        [[delegate undoManager] redo];
        
        [kbImpl clearTransientState];
        [kbImpl clearAnimations];
        [kbImpl setCaretBlinks:YES];
    }
    [self autoPaginationControl];
}

-(void)selectAction:(UIButton*)sender{
    [self autoPaginationControl];
    [self beginImpactAnimationAndUpdateDelegate:_cmd sender:sender toastWidthOffset:0  toastHeightOffset:0];
    
    if ([delegate respondsToSelector:@selector(select:)]) {
        [delegate select:nil]; //UIResponderStandardEditActions.h
    }else{
        if (![kbImpl isUsingDictationLayout]){
            NSString *selectedString = [delegate textInRange:[delegate selectedTextRange]];
            if (!selectedString.length) {
                UITextRange *textRange = [self selectedWordTextRangeWithDelegate:delegate];
                
                if (!textRange)
                    return;
                UIResponder <UITextInput> *tempDelegate = (UIResponder <UITextInput> *)delegate;
                if (![((UITextField *)tempDelegate).text isEqualToString:@"\uFFFC"]){
                    tempDelegate.selectedTextRange = textRange;
                }
                [kbImpl clearTransientState];
                [kbImpl clearAnimations];
                [kbImpl setCaretBlinks:YES];
            }
        }
    }
    [self autoPaginationControl];
}

-(void)beginningAction:(UIButton*)sender{
    [self autoPaginationControl];
    [self beginImpactAnimationAndUpdateDelegate:_cmd sender:sender toastWidthOffset:0  toastHeightOffset:0];
    UIResponder <UITextInput> *tempDelegate = (UIResponder <UITextInput> *)delegate;
    
    BOOL isWKContentView = [tempDelegate isKindOfClass:objc_getClass("WKContentView")];
    if (isWKContentView){
        [(WKContentView *)tempDelegate executeEditCommandWithCallback:@"moveToBeginningOfDocument"];
    }else{
        tempDelegate.selectedTextRange = [tempDelegate textRangeFromPosition:tempDelegate.beginningOfDocument toPosition:tempDelegate.beginningOfDocument];
    }
    [kbImpl clearTransientState];
    [kbImpl clearAnimations];
    [kbImpl setCaretBlinks:YES];
    [self autoPaginationControl];
}

-(void)endingAction:(UIButton*)sender{
    [self autoPaginationControl];
    [self beginImpactAnimationAndUpdateDelegate:_cmd sender:sender toastWidthOffset:0  toastHeightOffset:0];
    UIResponder <UITextInput> *tempDelegate = (UIResponder <UITextInput> *)delegate;
    
    BOOL isWKContentView = [tempDelegate isKindOfClass:objc_getClass("WKContentView")];
    if (isWKContentView){
        [(WKContentView *)tempDelegate executeEditCommandWithCallback:@"moveToEndOfDocument"];
    }else{
        tempDelegate.selectedTextRange = [tempDelegate textRangeFromPosition:tempDelegate.endOfDocument toPosition:tempDelegate.endOfDocument];
    }
    
    [kbImpl clearTransientState];
    [kbImpl clearAnimations];
    [kbImpl setCaretBlinks:YES];
    [self autoPaginationControl];
}




-(void)deleteAction:(UIButton*)sender{
    [self autoPaginationControl];
    [self beginImpactAnimationAndUpdateDelegate:_cmd sender:sender toastWidthOffset:10  toastHeightOffset:0];
    NSString *selectedString = [delegate textInRange:[delegate selectedTextRange]];
    BOOL smartDelete = preferencesBool(kEnabledSmartDeletekey, NO);
    if (!selectedString.length) {
        UITextRange *textRange = [self selectedWordTextRangeWithDelegate:delegate direction:UITextStorageDirectionBackward];
        
        if (!textRange) return;
        
        UIResponder <UITextInput> *tempDelegate = (UIResponder <UITextInput> *)delegate;
        
        tempDelegate.selectedTextRange = textRange;
        //[kbImpl deleteFromInput];
        [kbImpl deleteFromInput];
        if (smartDelete) [kbImpl insertText:@" "];
        //[tempDelegate  _moveRight:NO withHistory:nil];
        
        [kbImpl clearTransientState];
        [kbImpl clearAnimations];
        [kbImpl setCaretBlinks:YES];
        
    }else{
        [kbImpl deleteBackward];
        if (smartDelete) [kbImpl insertText:@" "];
        [kbImpl clearTransientState];
        [kbImpl clearAnimations];
        [kbImpl setCaretBlinks:YES];
    }
    [self autoPaginationControl];
    
}

-(void)deleteForwardAction:(UIButton*)sender{
    [self autoPaginationControl];
    [self beginImpactAnimationAndUpdateDelegate:_cmd sender:sender toastWidthOffset:10  toastHeightOffset:0];
    NSString *selectedString = [delegate textInRange:[delegate selectedTextRange]];
    BOOL smartDelete = preferencesBool(kEnabledSmartDeleteForwardkey, NO);
    if (!selectedString.length) {
        UITextRange *textRange = [self selectedWordTextRangeWithDelegate:delegate direction:UITextStorageDirectionForward];
        
        if (!textRange) return;
        
        UIResponder <UITextInput> *tempDelegate = (UIResponder <UITextInput> *)delegate;
        
        tempDelegate.selectedTextRange = textRange;
        //[kbImpl deleteFromInput];
        [kbImpl deleteFromInput];
        if (smartDelete) [kbImpl insertText:@" "];
        //[tempDelegate  _moveRight:NO withHistory:nil];
        
        [kbImpl clearTransientState];
        [kbImpl clearAnimations];
        [kbImpl setCaretBlinks:YES];
        
    }else{
        [kbImpl deleteForwardAndNotify:YES];
        if (smartDelete) [kbImpl insertText:@" "];
        [kbImpl clearTransientState];
        [kbImpl clearAnimations];
        [kbImpl setCaretBlinks:YES];
    }
    [self autoPaginationControl];
    
}

-(void)deleteAllAction:(UIButton*)sender{
    [self autoPaginationControl];
    self.hapticType = 0;
    [self selectAllAction:nil];
    self.hapticType = 2;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(secondActionDelay * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        [self triggerImpactAndAnimationWithButton:sender selectorName:@"deleteAction:" toastWidthOffset:10 toastHeightOffset:0];
        [self beginUpdateDelegate];
        [kbImpl deleteFromInput];
        [kbImpl clearTransientState];
        [kbImpl clearAnimations];
        [kbImpl setCaretBlinks:YES];
        [self autoPaginationControl];
    });
}





-(void)dismissKeyboardAction:(UIButton*)sender{
    [self autoPaginationControl];
    [self triggerImpactAndAnimationWithButton:sender selectorName:NSStringFromSelector(_cmd) toastWidthOffset:10 toastHeightOffset:0];
    kbImpl = [objc_getClass("UIKeyboardImpl") activeInstance];
    [kbImpl dismissKeyboard];
    [self autoPaginationControl];
}

-(void)moveCursorLeftAction:(UIButton*)sender{
    [self autoPaginationControl];
    [self beginImpactAnimationAndUpdateDelegate:_cmd sender:sender toastWidthOffset:0  toastHeightOffset:0];
    
    BOOL isWKContentView = [delegate isKindOfClass:objc_getClass("WKContentView")];
    if (isWKContentView){
        BOOL isRTL  = [self isRTLForDelegate:delegate];
        if (isRTL){
            [(WKContentView *)delegate executeEditCommandWithCallback:@"moveRight"];
        }else{
            [(WKContentView *)delegate executeEditCommandWithCallback:@"moveLeft"];
        }
    }else{
        [self moveCursorWithDelegate:delegate offset:-1];
    }
    [self autoPaginationControl];
}

-(void)moveCursorRightAction:(UIButton*)sender{
    [self autoPaginationControl];
    [self beginImpactAnimationAndUpdateDelegate:_cmd sender:sender toastWidthOffset:0  toastHeightOffset:0];
    
    BOOL isWKContentView = [delegate isKindOfClass:objc_getClass("WKContentView")];
    if (isWKContentView){
        BOOL isRTL  = [self isRTLForDelegate:delegate];
        if (isRTL){
            [(WKContentView *)delegate executeEditCommandWithCallback:@"moveLeft"];
        }else{
            [(WKContentView *)delegate executeEditCommandWithCallback:@"moveRight"];
        }
    }else{
        [self moveCursorWithDelegate:delegate offset:1];
    }
    [self autoPaginationControl];
}

-(void)moveCursorPreviousWordAction:(UIButton*)sender{
    [self autoPaginationControl];
    if (sender || self.isWordSender){
        [self triggerImpactAndAnimationWithButton:sender selectorName:NSStringFromSelector(_cmd) toastWidthOffset:0 toastHeightOffset:0];
    }
    [self beginUpdateDelegate];
    
    BOOL isWKContentView = [delegate isKindOfClass:objc_getClass("WKContentView")];
    BOOL isRTL  = [self isRTLForDelegate:delegate];
    if (isWKContentView){
        if (isRTL){
            [(WKContentView *)delegate _moveToEndOfWord:self.moveCursorWithSelect withHistory:nil];
        }else{
            [(WKContentView *)delegate _moveToStartOfWord:self.moveCursorWithSelect withHistory:nil];
        }
    }else{
        if ([delegate respondsToSelector:@selector(_moveToStartOfWord:withHistory:)]){
            //if (isRTL){
            //[delegate _moveToEndOfWord:NO withHistory:nil];
            //}else{
            [delegate _moveToStartOfWord:self.moveCursorWithSelect withHistory:nil];
            //}
        }else{
            [self moveCursorSingleWordWithDelegate:delegate direction:UITextStorageDirectionBackward];
        }
    }
    self.moveCursorWithSelect = NO;
    self.isWordSender = NO;
    [self autoPaginationControl];
}

-(void)moveCursorNextWordAction:(UIButton*)sender{
    [self autoPaginationControl];
    if (sender || self.isWordSender){
        [self triggerImpactAndAnimationWithButton:sender selectorName:NSStringFromSelector(_cmd) toastWidthOffset:0 toastHeightOffset:0];
    }
    [self beginUpdateDelegate];
    
    BOOL isWKContentView = [delegate isKindOfClass:objc_getClass("WKContentView")];
    BOOL isRTL  = [self isRTLForDelegate:delegate];
    if (isWKContentView){
        if (isRTL){
            [(WKContentView *)delegate _moveToStartOfWord:self.moveCursorWithSelect withHistory:nil];
        }else{
            [(WKContentView *)delegate _moveToEndOfWord:self.moveCursorWithSelect withHistory:nil];
        }
    }else{
        if ([delegate respondsToSelector:@selector(_moveToEndOfWord:withHistory:)]){
            //if (isRTL){
            //[delegate _moveToStartOfWord:NO withHistory:nil];
            //}else{
            [delegate _moveToEndOfWord:self.moveCursorWithSelect withHistory:nil];
            //}
        }else{
            [self moveCursorSingleWordWithDelegate:delegate direction:UITextStorageDirectionForward];
        }
    }
    self.moveCursorWithSelect = NO;
    self.isWordSender = NO;
    [self autoPaginationControl];
}

-(void)moveCursorStartOfLineAction:(UIButton*)sender{
    [self autoPaginationControl];
    [self beginImpactAnimationAndUpdateDelegate:_cmd sender:sender toastWidthOffset:0  toastHeightOffset:0];
    UIResponder <UITextInput> *tempDelegate = (UIResponder <UITextInput> *)delegate;
    
    UITextPosition *startPositionTemp = tempDelegate.selectedTextRange.start;
    self.moveCursorWithSelect = NO;
    [self moveCursorPreviousWordAction:nil];
    UITextPosition *startPositionMovedTemp = tempDelegate.selectedTextRange.start;
    if (((UITextRange * )[delegate _rangeOfLineEnclosingPosition:startPositionMovedTemp]).start == ((UITextRange * )[delegate _rangeOfLineEnclosingPosition:startPositionTemp]).start){
        [delegate _moveToStartOfLine:NO withHistory:nil];
        
        //[self moveCursorPreviousWordAction:nil];
        
    }
    
    BOOL isWKContentView = [delegate isKindOfClass:objc_getClass("WKContentView")];
    BOOL isRTL  = [self isRTLForDelegate:delegate];
    
    if (isWKContentView){
        if (isRTL){
            [(WKContentView *)delegate _moveToEndOfLine:self.moveCursorWithSelect withHistory:nil];
        }else{
            [(WKContentView *)delegate _moveToStartOfLine:self.moveCursorWithSelect withHistory:nil];
        }
    }else{
        if ([delegate respondsToSelector:@selector(_moveToStartOfLine:withHistory:)]){
            //if (isRTL){
            //[delegate _moveToEndOfLine:NO withHistory:nil];
            //}else{
            [delegate _moveToStartOfLine:self.moveCursorWithSelect withHistory:nil];
            //}
        }else{
            [self moveCursorToLineExtremityWithDelegate:delegate direction:UITextLayoutDirectionLeft];
        }
    }
    self.moveCursorWithSelect = NO;
    [self autoPaginationControl];
}

-(void)moveCursorEndOfLineAction:(UIButton*)sender{
    [self autoPaginationControl];
    [self beginImpactAnimationAndUpdateDelegate:_cmd sender:sender toastWidthOffset:0  toastHeightOffset:0];
    UIResponder <UITextInput> *tempDelegate = (UIResponder <UITextInput> *)delegate;
    
    UITextPosition *startPositionTemp = tempDelegate.selectedTextRange.end;
    self.moveCursorWithSelect = NO;
    
    [self moveCursorNextWordAction:nil];
    UITextPosition *startPositionMovedTemp = tempDelegate.selectedTextRange.end;
    if (((UITextRange * )[delegate _rangeOfLineEnclosingPosition:startPositionMovedTemp]).end == ((UITextRange * )[delegate _rangeOfLineEnclosingPosition:startPositionTemp]).end){
        [self moveCursorNextWordAction:nil];
        
        [delegate _moveToEndOfLine:NO withHistory:nil];
        
    }
    
    BOOL isWKContentView = [delegate isKindOfClass:objc_getClass("WKContentView")];
    BOOL isRTL  = [self isRTLForDelegate:delegate];
    
    if (isWKContentView){
        if (isRTL){
            [(WKContentView *)delegate _moveToStartOfLine:self.moveCursorWithSelect withHistory:nil];
        }else{
            [(WKContentView *)delegate _moveToEndOfLine:self.moveCursorWithSelect withHistory:nil];
        }
    }else{
        if ([delegate respondsToSelector:@selector(_moveToEndOfLine:withHistory:)]){
            //if (isRTL){
            //[delegate _moveToStartOfLine:NO withHistory:nil];
            //}else{
            [delegate _moveToEndOfLine:self.moveCursorWithSelect withHistory:nil];
            //}
        }else{
            [self moveCursorToLineExtremityWithDelegate:delegate direction:UITextLayoutDirectionRight];
        }
    }
    self.moveCursorWithSelect = NO;
    [self autoPaginationControl];
}

-(void)moveCursorStartOfParagraphAction:(UIButton*)sender{
    [self autoPaginationControl];
    [self beginImpactAnimationAndUpdateDelegate:_cmd sender:sender toastWidthOffset:0  toastHeightOffset:0];
    UIResponder <UITextInput> *tempDelegate = (UIResponder <UITextInput> *)delegate;
    
    UITextPosition *startPositionTemp = tempDelegate.selectedTextRange.start;
    if (startPositionTemp == ((UITextRange * )[delegate _rangeOfParagraphEnclosingPosition:startPositionTemp]).start){
        self.moveCursorWithSelect = NO;
        [self moveCursorPreviousWordAction:nil];
    }
    
    BOOL isWKContentView = [delegate isKindOfClass:objc_getClass("WKContentView")];
    BOOL isRTL  = [self isRTLForDelegate:delegate];
    
    if (isWKContentView){
        if (isRTL){
            [(WKContentView *)delegate _moveToEndOfParagraph:self.moveCursorWithSelect withHistory:nil];
        }else{
            [(WKContentView *)delegate _moveToStartOfParagraph:self.moveCursorWithSelect withHistory:nil];
        }
    }else{
        if ([delegate respondsToSelector:@selector(_moveToStartOfParagraph:withHistory:)]){
            //if (isRTL){
            //[delegate _moveToStartOfLine:NO withHistory:nil];
            //}else{
            [delegate _moveToStartOfParagraph:self.moveCursorWithSelect withHistory:nil];
            //}
        }
    }
    self.moveCursorWithSelect = NO;
    [self autoPaginationControl];
}

-(void)moveCursorEndOfParagraphAction:(UIButton*)sender{
    [self autoPaginationControl];
    [self beginImpactAnimationAndUpdateDelegate:_cmd sender:sender toastWidthOffset:0  toastHeightOffset:0];
    UIResponder <UITextInput> *tempDelegate = (UIResponder <UITextInput> *)delegate;
    
    UITextPosition *endPositionTemp = tempDelegate.selectedTextRange.end;
    if (endPositionTemp == ((UITextRange * )[delegate _rangeOfParagraphEnclosingPosition:endPositionTemp]).end){
        self.moveCursorWithSelect = NO;
        [self moveCursorNextWordAction:nil];
    }
    BOOL isWKContentView = [delegate isKindOfClass:objc_getClass("WKContentView")];
    BOOL isRTL  = [self isRTLForDelegate:delegate];
    
    if (isWKContentView){
        if (isRTL){
            [(WKContentView *)delegate _moveToStartOfParagraph:self.moveCursorWithSelect withHistory:nil];
        }else{
            [(WKContentView *)delegate _moveToEndOfParagraph:self.moveCursorWithSelect withHistory:nil];
        }
    }else{
        if ([delegate respondsToSelector:@selector(_moveToEndOfParagraph:withHistory:)]){
            //if (isRTL){
            //[delegate _moveToStartOfLine:NO withHistory:nil];
            //}else{
            [delegate _moveToEndOfParagraph:self.moveCursorWithSelect withHistory:nil];
            //}
        }
    }
    self.moveCursorWithSelect = NO;
    [self autoPaginationControl];
}

-(void)moveCursorStartOfSentenceAction:(UIButton*)sender{
    [self autoPaginationControl];
    [self beginImpactAnimationAndUpdateDelegate:_cmd sender:sender toastWidthOffset:0  toastHeightOffset:0];
    UIResponder <UITextInput> *tempDelegate = (UIResponder <UITextInput> *)delegate;
    
    UITextPosition *startPositionTemp = tempDelegate.selectedTextRange.start;
    self.moveCursorWithSelect = NO;
    [self moveCursorPreviousWordAction:nil];
    UITextPosition *startPositionMovedTemp = tempDelegate.selectedTextRange.start;
    if (((UITextRange * )[delegate _rangeOfSentenceEnclosingPosition:startPositionMovedTemp]).start == ((UITextRange * )[delegate _rangeOfSentenceEnclosingPosition:startPositionTemp]).start){
        //[delegate _moveToStartOfLine:NO withHistory:nil];
        
        [self moveCursorPreviousWordAction:nil];
        
    }
    
    [delegate _setSelectionToPosition:((UITextRange * )[delegate _rangeOfSentenceEnclosingPosition:startPositionMovedTemp]).start];
    [self autoPaginationControl];
    
}

-(void)moveCursorEndOfSentenceAction:(UIButton*)sender{
    [self autoPaginationControl];
    [self beginImpactAnimationAndUpdateDelegate:_cmd sender:sender toastWidthOffset:0  toastHeightOffset:0];
    UIResponder <UITextInput> *tempDelegate = (UIResponder <UITextInput> *)delegate;
    
    UITextPosition *startPositionTemp = tempDelegate.selectedTextRange.end;
    self.moveCursorWithSelect = NO;
    
    [self moveCursorNextWordAction:nil];
    UITextPosition *startPositionMovedTemp = tempDelegate.selectedTextRange.end;
    if (((UITextRange * )[delegate _rangeOfSentenceEnclosingPosition:startPositionMovedTemp]).end == ((UITextRange * )[delegate _rangeOfSentenceEnclosingPosition:startPositionTemp]).end){
        [self moveCursorNextWordAction:nil];
        
        //[delegate _moveToEndOfLine:NO withHistory:nil];
        
    }
    [delegate _setSelectionToPosition:((UITextRange * )[delegate _rangeOfSentenceEnclosingPosition:startPositionMovedTemp]).end];
    [self autoPaginationControl];
    
}

-(void)moveCursorUpAction:(UIButton*)sender{
    [self autoPaginationControl];
    [self beginImpactAnimationAndUpdateDelegate:_cmd sender:sender toastWidthOffset:0  toastHeightOffset:0];
    
    BOOL isWKContentView = [delegate isKindOfClass:objc_getClass("WKContentView")];
    if (isWKContentView){
        [(WKContentView *)delegate executeEditCommandWithCallback:@"moveUp"];
    }else{
        [self moveCursorVerticalWithDelegate:delegate direction:UITextLayoutDirectionUp];
    }
    [self autoPaginationControl];
}

-(void)moveCursorDownAction:(UIButton*)sender{
    [self autoPaginationControl];
    [self beginImpactAnimationAndUpdateDelegate:_cmd sender:sender toastWidthOffset:0  toastHeightOffset:0];
    
    BOOL isWKContentView = [delegate isKindOfClass:objc_getClass("WKContentView")];
    if (isWKContentView){
        [(WKContentView *)delegate executeEditCommandWithCallback:@"moveDown"];
    }else{
        [self moveCursorVerticalWithDelegate:delegate direction:UITextLayoutDirectionDown];
    }
    [self autoPaginationControl];
}

-(void)moveCursorContinuoslyWithDelegate:(id <UITextInput, UITextInputTokenizer>)delegate offset:(int)offset{
    [self moveCursorWithDelegate:delegate offset:offset];
}

-(CPDistributedMessagingCenter *)IPCCenterNamed:(NSString *)centerName{
    return nil;
}

-(BOOL)isAutoCorrectionEnabled{
    UIKeyboardPreferencesController *preferencesController = [UIKeyboardPreferencesController sharedPreferencesController];
    [preferencesController synchronizePreferences];
    return [preferencesController boolForKey:7];
}

-(void)setAutoCorrection:(BOOL)enabled{
    UIKeyboardPreferencesController *preferencesController = [UIKeyboardPreferencesController sharedPreferencesController];
    [preferencesController setValue:[NSNumber numberWithBool:enabled] forKey:7];
    [preferencesController synchronizePreferences];
    CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(), CFSTR("AppleKeyboardsSettingsChangedNotification"), NULL, NULL, YES);
}

-(void)updateAutoCorrection:(NSNotification*)notification{
    if (!self.isSameProcess && !self.autoCorrectionCell.hidden){
        if (!self.asyncUpdated) self.autoCorrectionEnabled = [self isAutoCorrectionEnabled];
        NSMutableAttributedString *imageOfName = [[NSMutableAttributedString alloc] initWithString:@""];
        
        UIImage *image;
        
        NSMutableAttributedString *attributeString = [[NSMutableAttributedString alloc] initWithString:[DXHelper localizedStringForActionNamed:@"autoCorrectionAction:" shortName:YES bundle:tweakBundle]];
        NSMutableAttributedString *strikedAttributeString = [attributeString mutableCopy];
        [strikedAttributeString addAttribute:NSStrikethroughStyleAttributeName value:@2 range:NSMakeRange(0, [attributeString length])];
        
        if (@available(iOS 13.0, *)){
            if (useShortenedLabel){
                imageOfName = self.autoCorrectionEnabled?attributeString:strikedAttributeString;
            }else{
                image = [UIImage systemImageNamed:self.autoCorrectionEnabled?@"checkmark.circle.fill":@"checkmark.circle"];
            }
        }else{
            if (@available(iOS 13.0, *)){
                if (useShortenedLabel){
                    imageOfName = self.autoCorrectionEnabled?attributeString:strikedAttributeString;
                }else{
                    image = [UIImage imageNamed:self.autoCorrectionEnabled?@"UIAccessoryButtonCheckmark":@"UIAccessoryButtonX" inBundle:[NSBundle bundleWithPath:@"/System/Library/PrivateFrameworks/UIKitCore.framework/Artwork.bundle"] compatibleWithTraitCollection:NULL];
                }
            }
        }
        if (useShortenedLabel){
            [self.autoCorrectionCell.btn setImage:nil forState:UIControlStateNormal];
            [self.autoCorrectionCell.btn setAttributedTitle:imageOfName forState:UIControlStateNormal];
        }else{
            [self.autoCorrectionCell.btn setAttributedTitle:nil forState:UIControlStateNormal];
            [self.autoCorrectionCell.btn setImage:image forState:UIControlStateNormal];
        }
    }
    self.asyncUpdated = NO;
    self.isSameProcess = NO;
}

-(void)autoCorrectionAction:(UIButton*)sender{
    [self autoPaginationControl];
    self.autoCorrectionEnabled = [self isAutoCorrectionEnabled];
    [self setAutoCorrection:!self.autoCorrectionEnabled];
    self.isSameProcess = YES;
    [self triggerImpactAndAnimationWithButton:sender selectorName:NSStringFromSelector(_cmd) toastWidthOffset:0 toastHeightOffset:0];
    
    
    //sender.highlighted = !autoCorrectionEnabled;
    //sender.selected = !autoCorrectionEnabled;
    NSMutableAttributedString *imageOfName = [[NSMutableAttributedString alloc] initWithString:@""];
    
    UIImage *image;
    
    NSMutableAttributedString *attributeString = [[NSMutableAttributedString alloc] initWithString:[DXHelper localizedStringForActionNamed:@"autoCorrectionAction:" shortName:YES bundle:tweakBundle]];
    NSMutableAttributedString *strikedAttributeString = [attributeString mutableCopy];
    [strikedAttributeString addAttribute:NSStrikethroughStyleAttributeName value:@2 range:NSMakeRange(0, [attributeString length])];
    
    if (@available(iOS 13.0, *)){
        if (useShortenedLabel){
            imageOfName = !self.autoCorrectionEnabled?attributeString:strikedAttributeString;
        }else{
            image = [UIImage systemImageNamed:(!self.autoCorrectionEnabled)?@"checkmark.circle.fill":@"checkmark.circle"];
        }
    }else{
        if (useShortenedLabel){
            imageOfName = !self.autoCorrectionEnabled?attributeString:strikedAttributeString;
        }else{
            image = [UIImage imageNamed:(!self.autoCorrectionEnabled)?@"UIAccessoryButtonCheckmark":@"UIAccessoryButtonX" inBundle:[NSBundle bundleWithPath:@"/System/Library/PrivateFrameworks/UIKitCore.framework/Artwork.bundle"] compatibleWithTraitCollection:NULL];
        }
    }
    if (useShortenedLabel){
        [sender setImage:nil forState:UIControlStateNormal];
        [sender setAttributedTitle:imageOfName forState:UIControlStateNormal];
    }else{
        [sender setAttributedTitle:nil forState:UIControlStateNormal];
        [sender setImage:image forState:UIControlStateNormal];
    }
    CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(), (CFStringRef)kAutoCorrectionChangedIdentifier, NULL, NULL, YES);
    [self autoPaginationControl];
}

-(BOOL)isAutoCapitalizationEnabled{
    UIKeyboardPreferencesController *preferencesController = [UIKeyboardPreferencesController sharedPreferencesController];
    [preferencesController synchronizePreferences];
    return [preferencesController boolForKey:8];
}

-(void)setAutoCapitalization:(BOOL)enabled{
    UIKeyboardPreferencesController *preferencesController = [UIKeyboardPreferencesController sharedPreferencesController];
    [preferencesController setValue:[NSNumber numberWithBool:enabled] forKey:8];
    [preferencesController synchronizePreferences];
    CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(), CFSTR("AppleKeyboardsSettingsChangedNotification"), NULL, NULL, YES);
}

-(void)updateAutoCapitalization:(NSNotification*)notification{
    if (!self.isSameProcess && !self.autoCapitalizationCell.hidden){
        if (!self.asyncUpdated) self.autoCapitalizationEnabled = [self isAutoCapitalizationEnabled];
        
        NSMutableAttributedString *imageOfName = [[NSMutableAttributedString alloc] initWithString:@""];
        
        UIImage *image;
        
        NSMutableAttributedString *attributeString = [[NSMutableAttributedString alloc] initWithString:[DXHelper localizedStringForActionNamed:@"autoCapitalizationAction:" shortName:YES bundle:tweakBundle]];
        NSMutableAttributedString *strikedAttributeString = [attributeString mutableCopy];
        [strikedAttributeString addAttribute:NSStrikethroughStyleAttributeName value:@2 range:NSMakeRange(0, [attributeString length])];
        
        if (@available(iOS 13.0, *)){
            if (useShortenedLabel){
                imageOfName = self.autoCapitalizationEnabled?attributeString:strikedAttributeString;
            }else{
                image = [UIImage systemImageNamed:self.autoCapitalizationEnabled?@"shift.fill":@"shift"];
            }
        }else{
            if (useShortenedLabel){
                imageOfName = self.autoCapitalizationEnabled?attributeString:strikedAttributeString;
            }else{
                image = [UIImage imageNamed:self.autoCapitalizationEnabled?@"shift_on_portrait":@"shift_portrait" inBundle:[NSBundle bundleWithPath:@"/System/Library/PrivateFrameworks/UIKitCore.framework/Artwork.bundle"] compatibleWithTraitCollection:NULL];
            }
        }
        if (useShortenedLabel){
            [self.autoCapitalizationCell.btn setImage:nil forState:UIControlStateNormal];
            [self.autoCapitalizationCell.btn setAttributedTitle:imageOfName forState:UIControlStateNormal];
        }else{
            [self.autoCapitalizationCell.btn setAttributedTitle:nil forState:UIControlStateNormal];
            [self.autoCapitalizationCell.btn setImage:image forState:UIControlStateNormal];
        }
    }
    self.asyncUpdated = NO;
    self.isSameProcess = NO;
}

-(void)autoCapitalizationAction:(UIButton*)sender{
    [self autoPaginationControl];
    self.autoCapitalizationEnabled = [self isAutoCapitalizationEnabled];
    [self setAutoCapitalization:!self.autoCapitalizationEnabled];
    self.isSameProcess = YES;
    [self triggerImpactAndAnimationWithButton:sender selectorName:NSStringFromSelector(_cmd) toastWidthOffset:0 toastHeightOffset:0];
    
    
    //sender.highlighted = !autoCorrectionEnabled;
    //sender.selected = !autoCorrectionEnabled;
    NSMutableAttributedString *imageOfName = [[NSMutableAttributedString alloc] initWithString:@""];
    
    UIImage *image;
    
    NSMutableAttributedString *attributeString = [[NSMutableAttributedString alloc] initWithString:[DXHelper localizedStringForActionNamed:@"autoCapitalizationAction:" shortName:YES bundle:tweakBundle]];
    NSMutableAttributedString *strikedAttributeString = [attributeString mutableCopy];
    [strikedAttributeString addAttribute:NSStrikethroughStyleAttributeName value:@2 range:NSMakeRange(0, [attributeString length])];
    
    if (@available(iOS 13.0, *)){
        if (useShortenedLabel){
            imageOfName = !self.autoCapitalizationEnabled?attributeString:strikedAttributeString;
        }else{
            image = [UIImage systemImageNamed:(!self.autoCapitalizationEnabled)?@"shift.fill":@"shift"];
        }
    }else{
        if (useShortenedLabel){
            imageOfName = !self.autoCapitalizationEnabled?attributeString:strikedAttributeString;
        }else{
            image = [UIImage imageNamed:(!self.autoCapitalizationEnabled)?@"shift_on_portrait":@"shift_portrait" inBundle:[NSBundle bundleWithPath:@"/System/Library/PrivateFrameworks/UIKitCore.framework/Artwork.bundle"] compatibleWithTraitCollection:NULL];
        }
    }
    if (useShortenedLabel){
        [sender setImage:nil forState:UIControlStateNormal];
        [sender setAttributedTitle:imageOfName forState:UIControlStateNormal];
    }else{
        [sender setAttributedTitle:nil forState:UIControlStateNormal];
        [sender setImage:image forState:UIControlStateNormal];
    }
    CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(), (CFStringRef)kAutoCapitalizationChangedIdentifier, NULL, NULL, YES);
    [self autoPaginationControl];
}



-(void)defineAction:(UIButton*)sender{
    [self autoPaginationControl];
    [self beginImpactAnimationAndUpdateDelegate:_cmd sender:sender toastWidthOffset:0  toastHeightOffset:0];
    UIResponder <UITextInput> *tempDelegate = (UIResponder <UITextInput> *)delegate;
    
    BOOL isWKContentView = [tempDelegate isKindOfClass:objc_getClass("WKContentView")];
    if (isWKContentView){
        NSString *selectedString = [(WKContentView *)tempDelegate selectedText];
        [(WKContentView *)tempDelegate select:nil];
        if ([selectedString length] == 0) return;
        if ([tempDelegate respondsToSelector:@selector(_define:)]){
            //[(WKContentView *)tempDelegate selectWordBackward];
            [(WKContentView *)tempDelegate _define:selectedString];
        }
    }else{
        NSString *selectedString = [tempDelegate textInRange:[tempDelegate selectedTextRange]];
        
        if (!selectedString.length) {
            UITextRange *textRange = [self autoDirectionWordSelectedTextRangeWithDelegate:tempDelegate];
            if (!textRange) return;
            tempDelegate.selectedTextRange = textRange;
            selectedString = [tempDelegate textInRange:textRange];
        }
        if ([tempDelegate respondsToSelector:@selector(_define:)]){
            [tempDelegate _define:selectedString];
        }
    }
    [self autoPaginationControl];
}

-(NSDictionary *)getItemWithID:(NSString *)snippetID forKey:(NSString *)keyName identifierKey:(NSString *)identifier{
    NSString *scopedKey = [self scopedPreferenceKey:keyName];
    NSArray *arrayWithEventID = [prefs[scopedKey] valueForKey:identifier];
    NSUInteger index = [arrayWithEventID indexOfObject:snippetID];
    NSDictionary *snippet = index != NSNotFound ? prefs[scopedKey][index] : nil;
    return snippet;
}

-(void)runCommand:(NSString *)cmd{
    if ([cmd length] != 0){
        DXRunShellCommand(cmd);
    }
}

-(void)runCommandAction:(UIButton*)sender{
    [self autoPaginationControl];
    NSDictionary *snippet = [self getItemWithID:NSStringFromSelector(_cmd) forKey:@"snippets" identifierKey:@"entryID"];
    self.commandTitle = snippet[@"title"] ? : @"Command";
    [self triggerImpactAndAnimationWithButton:sender selectorName:NSStringFromSelector(_cmd) toastWidthOffset:0 toastHeightOffset:0];
    if (snippet[@"command"]){
        [self runCommand:snippet[@"command"]];
    }
    [self autoPaginationControl];
}

-(void)insertTextAction:(UIButton*)sender{
    [self autoPaginationControl];
    [self beginImpactAnimationAndUpdateDelegate:_cmd sender:sender toastWidthOffset:0  toastHeightOffset:0];
    
    if ([delegate respondsToSelector:@selector(insertText:)]) {
        NSDictionary *snippet = [self getItemWithID:NSStringFromSelector(_cmd) forKey:@"inserts" identifierKey:@"entryID"];
        
        
        int insertType;
        if (self.insertTextActionType == 0){
            insertType = snippet[@"type"] ? [snippet[@"type"] intValue] : 0;
        }else{
            insertType = snippet[@"typeLP"] ? [snippet[@"typeLP"] intValue] : 0;
        }
        //NSLocale* currentLocale = [NSLocale currentLocale];
        NSDate *now = [NSDate date];
        NSDateFormatter *df = [[NSDateFormatter alloc] init];
        NSString *insertStrings = @"";
        
        switch (insertType) {
            case 0:
                if (self.insertTextActionType == 0){
                    insertStrings = snippet[@"text"];
                }else{
                    insertStrings = snippet[@"textLP"];
                }
                if ([insertStrings length] == 0){
                    insertStrings = [DXLoremIpsum getQuote];
                }
                [kbImpl insertText:insertStrings];
                break;
            case 1: //“11/23/37” or “3:30 PM”
                [df setDateStyle:NSDateFormatterShortStyle];
                [kbImpl insertText:[df stringFromDate:now]];
                //[kbImpl insertText:[[NSDate date] descriptionWithLocale:currentLocale]];
                break;
            case 2: //“Nov 23, 1937” or “3:30:32 PM”
                [df setDateStyle:NSDateFormatterMediumStyle];
                [kbImpl insertText:[df stringFromDate:now]];
                break;
            case 3: //“11/23/37” or “3:30 PM”
                [df setTimeStyle:NSDateFormatterShortStyle];
                [kbImpl insertText:[df stringFromDate:now]];
                break;
            case 4: //“Nov 23, 1937” or “3:30:32 PM”
                [df setTimeStyle:NSDateFormatterMediumStyle];
                [kbImpl insertText:[df stringFromDate:now]];
                break;
            case 5: //“Nov 23, 1937” or “3:30:32 PM”
                [df setDateStyle:NSDateFormatterMediumStyle];
                [df setTimeStyle:NSDateFormatterMediumStyle];
                [kbImpl insertText:[df stringFromDate:now]];
                break;
            default:
                break;
        }
        
        [kbImpl clearTransientState];
        [kbImpl clearAnimations];
        [kbImpl setCaretBlinks:YES];
        self.insertTextActionType = 0;
        
    }
    [self autoPaginationControl];
}



-(BOOL)boolWithProbability:(double)probability{
    return rand() <  probability * ((double)RAND_MAX + 1.0);
}

-(NSString *)capitalize:(NSString *)theString probability:(double)probability{
    NSInteger theStrLen = theString.length;
    if (theStrLen == 0) return theString;
    NSMutableString *capStr = [NSMutableString stringWithCapacity:theStrLen];
    for (NSInteger i = 0; i < theStrLen; i++) {
        NSRange range = NSMakeRange(i, 1);
        NSString *character = [theString substringWithRange:range];
        character = [self boolWithProbability:probability] ? [character uppercaseString] : [character lowercaseString];
        [capStr appendString:character];
    }
    return [NSString stringWithString:capStr];
}

-(NSString *)capitalizeAlternatively:(NSString *)theString{
    NSInteger theStrLen = theString.length;
    if (theStrLen == 0) return theString;
    BOOL firstSeed = [self boolWithProbability:0.5];
    NSMutableString *capStr = [NSMutableString stringWithCapacity:theStrLen];
    for (NSInteger i = 0; i < theStrLen; i++) {
        NSRange range = NSMakeRange(i, 1);
        NSString *character = [theString substringWithRange:range];
        character = firstSeed ? [character uppercaseString] : [character lowercaseString];
        firstSeed = !firstSeed;
        [capStr appendString:character];
    }
    return [NSString stringWithString:capStr];
}

-(BOOL)isVowel:(NSString *)theString{
    NSAssert([theString length] == 1, @"Invalid character length");
    return ([@"aeiou" rangeOfString:[theString lowercaseString]].location != NSNotFound);
}

-(NSString *)capitalize:(NSString *)theString phonemes:(DXPhonemesType)type{
    NSInteger theStrLen = theString.length;
    if (theStrLen == 0) return theString;
    NSMutableString *capStr = [NSMutableString stringWithCapacity:theStrLen];
    for (NSInteger i = 0; i < theStrLen; i++) {
        NSRange range = NSMakeRange(i, 1);
        NSString *character = [theString substringWithRange:range];
        switch (type){
            case DXPhonemesTypeConsonent:{
                character = ![self isVowel:character] ? [character uppercaseString] : [character lowercaseString];
                break;
            }
            default:{
                character = [self isVowel:character] ? [character uppercaseString] : [character lowercaseString];
                break;
            }
        }
        [capStr appendString:character];
    }
    return [NSString stringWithString:capStr];
}

-(void)spongebobAction:(UIButton*)sender{
    [self autoPaginationControl];
    [self beginImpactAnimationAndUpdateDelegate:_cmd sender:sender toastWidthOffset:10  toastHeightOffset:0];
    NSString *selectedString = [delegate textInRange:[delegate selectedTextRange]];
    if (!selectedString.length) {
        
        UITextRange *textRange;
        UIResponder <UITextInput> *tempDelegate = (UIResponder <UITextInput, UITextInputTokenizer> *)delegate;
        
        UITextPosition *startPositionTemp = tempDelegate.selectedTextRange.start;
        UITextPosition *startPositionSentence = ((UITextRange * )[tempDelegate _rangeOfSentenceEnclosingPosition:startPositionTemp]).start;
        UITextPosition *endPositionSentence = ((UITextRange * )[tempDelegate _rangeOfSentenceEnclosingPosition:startPositionTemp]).end;
        
        BOOL isWKContentView = [tempDelegate isKindOfClass:objc_getClass("WKContentView")];
        
        if (isWKContentView){
            
        }else{
            textRange = [tempDelegate textRangeFromPosition:startPositionSentence toPosition:endPositionSentence];
            [tempDelegate setSelectedTextRange:textRange];
        }
        
        if (!textRange) return;
        selectedString = [delegate textInRange:[delegate selectedTextRange]];
    }
    switch (spongebobEntropy){
        case DXStudlyCapsTypeAlternate:
            [kbImpl insertText:[self capitalizeAlternatively:selectedString]];
            break;
        case DXStudlyCapsTypeVowel:
            [kbImpl insertText:[self capitalize:selectedString phonemes:DXPhonemesTypeVowel]];
            break;
        case DXStudlyCapsTypeConsonent:
            [kbImpl insertText:[self capitalize:selectedString phonemes:DXPhonemesTypeConsonent]];
            break;
        default:
            [kbImpl insertText:[self capitalize:selectedString probability:0.5]];
            break;
            
    }
    [kbImpl clearTransientState];
    [kbImpl clearAnimations];
    [kbImpl setCaretBlinks:YES];
    [self autoPaginationControl];
}

#pragma mark collectionview


-(NSInteger)numberOfSectionsInCollectionView:(UICollectionView *)collectionView
{
    
    //HBLogDebug(@"NUM SEC: %f", ceil((float)(((NSArray *)_shortcuts[kbuttonsImages12]).count)/(float)preferencesInt(kShortcutsPerSection, maxshortcutpersection)));
    return ceil((float)(((NSArray *)_shortcuts[kbuttonsImages12]).count)/(float)[self shortcutsPerSection]);
}

-(NSInteger)collectionView:(UICollectionView *)collectionView numberOfItemsInSection:(NSInteger)section
{
    UIKeyboardPreferencesController *kbPrefsController = [objc_getClass("UIKeyboardPreferencesController") sharedPreferencesController];
    if (kbPrefsController){
        long long currentHandBias = kbPrefsController.handBias;
        //HBLogDebug(@"currentHandBias: %lld",currentHandBias);
        if (currentHandBias > 0){
            //self.pagingEnabled = YES;
            //HBLogDebug(@"numberOfItemsInSection: %lu", ((NSArray *)_shortcuts[kbuttonsImages12]).count>5?5:((NSArray *)_shortcuts[kbuttonsImages12]).count);
            //return ((NSArray *)_shortcuts[kbuttonsImages12]).count>5?5:((NSArray *)_shortcuts[kbuttonsImages12]).count;
            //if (([self numberOfSectionsInCollectionView:collectionView] -1) == section){
            if (([self numberOfSectionsInCollectionView:collectionView] -1) == section){
                return ((NSArray *)_shortcuts[kbuttonsImages12]).count-[self shortcutsPerSection]*(section);
            }else{
                return ((NSArray *)_shortcuts[kbuttonsImages12]).count>[self shortcutsPerSection]?[self shortcutsPerSection]:((NSArray *)_shortcuts[kbuttonsImages12]).count;
            }
        }else{
            //if (section == ceil((float)(((NSArray *)_shortcuts[kbuttonsImages12]).count)/6.0f)){
            //return ((NSArray *)_shortcuts[kbuttonsImages12]).count - 6*(section);
            //}else{
            //self.pagingEnabled = NO;
            //return ((NSArray *)_shortcuts[kbuttonsImages12]).count>6?6:((NSArray *)_shortcuts[kbuttonsImages12]).count-6*(section);
            if (([self numberOfSectionsInCollectionView:collectionView] -1) == section){
                //HBLogDebug(@"NUM: %ld, SECTION: %ld", ((NSArray *)_shortcuts[kbuttonsImages12]).count-preferencesInt(kShortcutsPerSection, maxshortcutpersection)*(section), section );
                return ((NSArray *)_shortcuts[kbuttonsImages12]).count-[self shortcutsPerSection]*(section);
            }else{
                //HBLogDebug(@"NUM: %ld, SECTION: %ld", ((NSArray *)_shortcuts[kbuttonsImages12]).count>preferencesInt(kShortcutsPerSection, maxshortcutpersection)?preferencesInt(kShortcutsPerSection, maxshortcutpersection):((NSArray *)_shortcuts[kbuttonsImages12]).count, section );
                
                return ((NSArray *)_shortcuts[kbuttonsImages12]).count>[self shortcutsPerSection]?[self shortcutsPerSection]:((NSArray *)_shortcuts[kbuttonsImages12]).count;
            }
            //return ((NSArray *)_shortcuts[kbuttonsImages12]).count-6*(section);
            //}
            //return ((NSArray *)_shortcuts[kbuttonsImages12]).count;
            //HBLogDebug(@"numberOfItemsInSection: %lu", ((NSArray *)_shortcuts[kbuttonsImages12]).count);
            
        }}
    //HBLogDebug(@"ITEMS: %ld",((NSArray *)_shortcuts[kbuttonsImages12]).count>preferencesInt(kShortcutsPerSection, maxshortcutpersection)?preferencesInt(kShortcutsPerSection, maxshortcutpersection):((NSArray *)_shortcuts[kbuttonsImages12]).count-preferencesInt(kShortcutsPerSection, maxshortcutpersection)*(section) );
    //return ((NSArray *)_shortcuts[kbuttonsImages12]).count>6?6:((NSArray *)_shortcuts[kbuttonsImages12]).count-6*(section);
    //HBLogDebug(@"XXXX");
    
    if (([self numberOfSectionsInCollectionView:collectionView] -1 )== section){
        return ((NSArray *)_shortcuts[kbuttonsImages12]).count-[self shortcutsPerSection]*(section);
    }else{
        return ((NSArray *)_shortcuts[kbuttonsImages12]).count>[self shortcutsPerSection]?[self shortcutsPerSection]:((NSArray *)_shortcuts[kbuttonsImages12]).count;
    }
}

-(void)activateCustomActions:(UIGestureRecognizer *)recognizer gestureType:(int)gestureType {
    if (recognizer.state != UIGestureRecognizerStateBegan) return;
    [self autoPaginationControl];
    UIButton *button = (UIButton *)recognizer.view;
    NSString *selectorName = preferencesSelectorForIdentifierScoped(button.accessibilityIdentifier, 1, gestureType, @"", self.configuration);
    if (selectorName.length == 0) return;

    SEL action = NSSelectorFromString(selectorName);
    if (![self respondsToSelector:action]) {
        HBLogWarn(@"TypeX ignoring unimplemented %@ for %@", selectorName, button.accessibilityIdentifier);
        return;
    }

    // Legacy selectors that have been hidden from the picker may still exist in
    // old preferences. Do not dispatch them through the generic action path.
    if (![DXShortcutsGenerator isVisibleShortcutSelector:selectorName]) {
        HBLogWarn(@"TypeX ignoring legacy/hidden selector %@", selectorName);
        return;
    }

    self.hapticType = 2;
    ((void(*)(id, SEL, id))objc_msgSend)(self, action, nil);
    [self shakeView:recognizer.view];
}

-(void)activateLPActions:(UIGestureRecognizer *)recognizer {
    [self activateCustomActions:recognizer gestureType:0];
}

-(void)activateDTActions:(UIGestureRecognizer *)recognizer {
    [self activateCustomActions:recognizer gestureType:1];
}

-(void)activateSingleTapAction:(UITapGestureRecognizer *)recognizer {
    if (recognizer.state != UIGestureRecognizerStateEnded) return;

    UIButton *button = (UIButton *)recognizer.view;
    NSString *selectorName = button.accessibilityIdentifier;
    if (![DXShortcutsGenerator isVisibleShortcutSelector:selectorName]) return;

    SEL action = NSSelectorFromString(selectorName);
    if (![self respondsToSelector:action]) {
        HBLogWarn(@"TypeX ignoring unimplemented single-tap %@", selectorName);
        return;
    }

    ((void(*)(id, SEL, id))objc_msgSend)(self, action, button);
}

-(UIWindow *)keyWindow {
    return DXKeyWindow();
}


- (UICollectionViewCell *)collectionView:(UICollectionView *)collectionView cellForItemAtIndexPath:(NSIndexPath *)indexPath {
    DXCell *cell = [collectionView dequeueReusableCellWithReuseIdentifier:@"kTypeXCellID" forIndexPath:indexPath];
    //HBLogDebug(@"SECTION %ld, ROW: %ld", indexPath.section, indexPath.row);
    //cell.transform = CGAffineTransformMakeScale(-1, 1);
    int cellIndex = [self shortcutsPerSection]*indexPath.section + indexPath.row;
    //HBLogDebug(@"cellINDEX: %d", cellIndex);
    //[cell.btn setTitle:_buttons[indexPath.row] forState:UIControlStateNormal];
    NSString* selectorName = ((NSArray *)_shortcuts[kselectors])[cellIndex];
    
    UIImage* image;
    NSAttributedString *imageOfName = [[NSMutableAttributedString alloc] initWithString:@""];
    
    
    if ([selectorName isEqualToString:@"autoCorrectionAction:"]){
        self.autoCorrectionCell = cell;
        
        dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
            self.autoCorrectionEnabled = [self isAutoCorrectionEnabled];
            dispatch_sync(dispatch_get_main_queue(), ^{
                self.isSameProcess = NO;
                self.asyncUpdated = YES;
                [self updateAutoCorrection:nil];
            });
        });
        
        
        NSMutableAttributedString *attributeString = [[NSMutableAttributedString alloc] initWithString:[DXHelper localizedStringForActionNamed:selectorName shortName:YES bundle:tweakBundle]];
        NSMutableAttributedString *strikedAttributeString = [attributeString mutableCopy];
        [strikedAttributeString addAttribute:NSStrikethroughStyleAttributeName value:@2 range:NSMakeRange(0, [attributeString length])];
        
        if (@available(iOS 13.0, *)){
            imageOfName = useShortenedLabel ? self.autoCorrectionEnabled?attributeString:strikedAttributeString : self.autoCorrectionEnabled?[@"checkmark.circle.fill" attributedString]:[@"checkmark.circle" attributedString];
        }else{
            imageOfName = useShortenedLabel ? self.autoCorrectionEnabled?attributeString:strikedAttributeString : self.autoCorrectionEnabled?[@"UIAccessoryButtonCheckmark" attributedString]:[@"UIAccessoryButtonX" attributedString];
        }
        if (!useShortenedLabel) image = [DXHelper imageForName:imageOfName.string  withSystemColor:NO completion:nil];
    }else if ([selectorName isEqualToString:@"autoCapitalizationAction:"]){
        self.autoCapitalizationCell = cell;
        
        dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
            self.autoCapitalizationEnabled = [self isAutoCapitalizationEnabled];
            dispatch_sync(dispatch_get_main_queue(), ^{
                self.isSameProcess = NO;
                self.asyncUpdated = YES;
                [self updateAutoCapitalization:nil];
            });
        });
        
        NSMutableAttributedString *attributeString = [[NSMutableAttributedString alloc] initWithString:[DXHelper localizedStringForActionNamed:selectorName shortName:YES bundle:tweakBundle]];
        NSMutableAttributedString *strikedAttributeString = [attributeString mutableCopy];
        [strikedAttributeString addAttribute:NSStrikethroughStyleAttributeName value:@2 range:NSMakeRange(0, [attributeString length])];
        
        if (@available(iOS 13.0, *)){
            imageOfName = useShortenedLabel ? self.autoCapitalizationEnabled?attributeString:strikedAttributeString : self.autoCapitalizationEnabled?[@"shift.fill" attributedString]:[@"shift" attributedString];
        }else{
            imageOfName = useShortenedLabel ? self.autoCapitalizationEnabled?attributeString:strikedAttributeString : self.autoCapitalizationEnabled?[@"shift_on_portrait" attributedString]:[@"shift_portrait" attributedString];
        }
        if (!useShortenedLabel) image = [DXHelper imageForName:imageOfName.string  withSystemColor:NO completion:nil];
    }else{
        
        if (@available(iOS 13.0, *)){
            
            imageOfName = useShortenedLabel ? [[DXHelper localizedStringForActionNamed:selectorName shortName:YES bundle:tweakBundle] attributedString] : [((NSArray *)_shortcuts[kbuttonsImages13])[cellIndex] attributedString];
            //imageOfName = useShortenedLabel ? [((NSArray *)_shortcuts[kshortLabel])[cellIndex] attributedString] : [((NSArray *)_shortcuts[kbuttonsImages13])[cellIndex] attributedString];
        }else{
            imageOfName = useShortenedLabel ? [[DXHelper localizedStringForActionNamed:selectorName shortName:YES bundle:tweakBundle] attributedString]: [((NSArray *)_shortcuts[kbuttonsImages12])[cellIndex] attributedString];
        }
        if (!useShortenedLabel) image = [DXHelper imageForName:imageOfName.string  withSystemColor:NO completion:nil];
    }
    
    
    if (useShortenedLabel){
        [cell.btn setImage:nil forState:UIControlStateNormal];
        [cell.btn setAttributedTitle:imageOfName forState:UIControlStateNormal];
    }else{
        [cell.btn setAttributedTitle:nil forState:UIControlStateNormal];
        [cell.btn setImage:image forState:UIControlStateNormal];
    }
    cell.btn.accessibilityIdentifier = selectorName;
    [cell.btn removeTarget:nil action:NULL forControlEvents:UIControlEventAllEvents];
    
    UILongPressGestureRecognizer *longPress = [[UILongPressGestureRecognizer alloc] initWithTarget:self action:@selector(activateLPActions:)];
    longPress.minimumPressDuration = 0.5;
    
    DXUIShortTapGestureRecognizer *singleTap = [[DXUIShortTapGestureRecognizer alloc] initWithTarget:self action:@selector(activateSingleTapAction:)];
    singleTap.numberOfTapsRequired = 1;
    DXUIShortTapGestureRecognizer *doubleTap = [[DXUIShortTapGestureRecognizer alloc] initWithTarget:self action:@selector(activateDTActions:)];
    doubleTap.numberOfTapsRequired = 2;
    // Only delay single-tap when the user has configured a double-tap action for
    // this shortcut. Otherwise the single-tap should fire immediately to avoid
    // holding onto a potentially stale input context while waiting for the
    // double-tap failure timeout.
    NSString *doubleTapSelector = preferencesSelectorForIdentifierScoped(selectorName, 1, 1, @"", self.configuration);
    if (doubleTapSelector.length > 0) {
        [singleTap requireGestureRecognizerToFail:doubleTap];
    }
    cell.btn.gestureRecognizers = @[longPress, doubleTap, singleTap];
    
    //cell.btn.backgroundColor = [UIColor clearColor];
    //cell.btn.layer.cornerRadius = 0; // this value vary as per your desire
    //cell.btn.clipsToBounds = NO;
    //}
    //self.layer.masksToBounds = NO;
    
    if (useShortenedLabel) cell.btn.clipsToBounds = YES; else cell.btn.clipsToBounds = NO;
    if (currentBackgroundTintColor)  cell.btn.layer.cornerRadius = 5;
    cell.btn.backgroundColor = currentBackgroundTintColor ? : [UIColor clearColor];
    cell.btn.tintColor = currentTintColor;
    [cell.btn setTitleColor:currentTintColor forState:UIControlStateNormal];
    cell.btn.hidden = isLandscape||isDictating?YES:NO;
    //cell.btn.backgroundColor = [UIColor colorWithWhite:0.5 alpha:0.7];
    //HBLogDebug(@"ITEMS: %@", ((NSArray *)_shortcuts[kselectors])[cellIndex]);
    //HBLogDebug(@"INDEX PATH: %@", indexPath);
    //HBLogDebug(@"");
    return cell;
    
    
}


- (CGSize)collectionView:(UICollectionView *)collectionView layout:(UICollectionViewLayout *)collectionViewLayout sizeForItemAtIndexPath:(NSIndexPath *)indexPath {
    //CGFloat useableWidth = collectionView.frame.size.width / ((NSArray *)_shortcuts[kbuttonsImages12]).count;
    //CGFloat useableWidth = collectionView.frame.size.width / ([self numberOfItemsInSection:indexPath.section] <= preferencesInt(kShortcutsPerSection, maxshortcutpersection) ? (((NSArray *)_shortcuts[kbuttonsImages12]).count <=preferencesInt(kShortcutsPerSection, maxshortcutpersection) ? ((NSArray *)_shortcuts[kbuttonsImages12]).count : preferencesInt(kShortcutsPerSection, maxshortcutpersection)) :  [self numberOfItemsInSection:indexPath.section]);
    if ([self.configuration isEqualToString:@"top"]) {
        CGFloat width = collectionView.frame.size.width / MAX(1, [self numberOfItemsInSection:indexPath.section]);
        return CGSizeMake(width, 33.33);
    }
    UIKeyboardPreferencesController *kbPrefsController = [objc_getClass("UIKeyboardPreferencesController") sharedPreferencesController];
    if (kbPrefsController){
        long long currentHandBias = kbPrefsController.handBias;
        //HBLogDebug(@"currentHandBias: %lld",currentHandBias);
        if (currentHandBias > 0){
            int shortcutsPerSectionOneHanded = MIN([self shortcutsPerSection], maxshortcutpersection_onehanded);
            CGFloat useableWidth = ((currentBackgroundTintColor && collectionView.frame.size.width-4*buttonSpacing >0) ? collectionView.frame.size.width - 4*buttonSpacing : collectionView.frame.size.width) / ([self numberOfItemsInSection:indexPath.section] <= maxshortcutpersection_onehanded ? (((NSArray *)_shortcuts[kbuttonsImages12]).count <= maxshortcutpersection_onehanded ? ((NSArray *)_shortcuts[kbuttonsImages12]).count : shortcutsPerSectionOneHanded) :  shortcutsPerSectionOneHanded);
            return CGSizeMake(useableWidth, buttonHeight);
            
        }
    }
    
    CGFloat useableWidth = ((currentBackgroundTintColor && collectionView.frame.size.width-4*buttonSpacing >0) ? collectionView.frame.size.width - 4*buttonSpacing : collectionView.frame.size.width) / ([self numberOfItemsInSection:indexPath.section] <= [self shortcutsPerSection] ? (((NSArray *)_shortcuts[kbuttonsImages12]).count <= [self shortcutsPerSection] ? ((NSArray *)_shortcuts[kbuttonsImages12]).count : [self shortcutsPerSection]) :  [self numberOfItemsInSection:indexPath.section]);
    
    return CGSizeMake(useableWidth, buttonHeight);
}

- (UIEdgeInsets)collectionView:(UICollectionView *)collectionView layout:(UICollectionViewLayout *)collectionViewLayout insetForSectionAtIndex:(NSInteger)section {
    if ([self.configuration isEqualToString:@"top"]) {
        return UIEdgeInsetsMake(8.0, 0.0, 0.0, 0.0);
    }
    if (currentBackgroundTintColor){
        if (section == 0){
            return UIEdgeInsetsMake(topInset, leftInset+2*buttonSpacing, bottomInset, rightInset);
            
        }
        return UIEdgeInsetsMake(topInset, leftInset+buttonSpacing, bottomInset, rightInset);
        
    }
    return UIEdgeInsetsMake(topInset, leftInset, bottomInset, rightInset);
}

- (CGFloat)collectionView:(UICollectionView *)collectionView layout:(UICollectionViewLayout*)collectionViewLayout minimumLineSpacingForSectionAtIndex:(NSInteger)section{
    return currentBackgroundTintColor?buttonSpacing:0;
}

@end
