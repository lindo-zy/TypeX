#import "common.h"
#import "DXShared.h"
#import "DXCollectionView.h"
#import "DXHelper.h"

#import <objc/runtime.h>
#import <objc/message.h>

static const NSInteger DXCustomActionToastTag = 0x54584341;
static const NSInteger DXSubActionPanelOverlayTag = 0x54585341;
static __weak DXCollectionView *DXActiveSubActionPanelOwner;

@interface DXSubActionPanelItem : UIControl
@property (nonatomic, strong) UIImageView *iconView;
@property (nonatomic, strong) UILabel *nameLabel;
@property (nonatomic, copy) NSString *actionSelector;
@property (nonatomic, assign) CGFloat panelScale;
- (void)configureWithTitle:(NSString *)title image:(UIImage *)image;
@end

@implementation DXSubActionPanelItem

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (!self) return nil;

    self.iconView = [[UIImageView alloc] initWithFrame:CGRectZero];
    self.iconView.contentMode = UIViewContentModeScaleAspectFit;
    self.iconView.tintColor = UIColor.labelColor;
    [self addSubview:self.iconView];

    self.nameLabel = [[UILabel alloc] initWithFrame:CGRectZero];
    self.nameLabel.font = [UIFont systemFontOfSize:13 weight:UIFontWeightRegular];
    self.nameLabel.textColor = UIColor.labelColor;
    self.nameLabel.textAlignment = NSTextAlignmentCenter;
    self.nameLabel.numberOfLines = 2;
    self.nameLabel.adjustsFontSizeToFitWidth = YES;
    self.nameLabel.minimumScaleFactor = 0.8;
    [self addSubview:self.nameLabel];

    self.isAccessibilityElement = YES;
    self.accessibilityTraits = UIAccessibilityTraitButton;
    return self;
}

- (void)configureWithTitle:(NSString *)title image:(UIImage *)image {
    self.nameLabel.text = title;
    self.iconView.image = [image imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate];
    self.accessibilityLabel = title;
}

- (void)layoutSubviews {
    [super layoutSubviews];
    CGFloat scale = self.panelScale > 0 ? self.panelScale : 1.0;
    CGFloat iconSide = MIN(CGRectGetWidth(self.bounds) - 12.0, 38.0 * scale);
    CGFloat iconTop = 10.0 * scale;
    self.iconView.frame = CGRectMake((CGRectGetWidth(self.bounds) - iconSide) / 2.0, iconTop,
                                     iconSide, iconSide);
    CGFloat labelY = CGRectGetMaxY(self.iconView.frame) + 7.0 * scale;
    self.nameLabel.frame = CGRectMake(4.0, labelY, CGRectGetWidth(self.bounds) - 8.0,
                                      MAX(0.0, CGRectGetHeight(self.bounds) - labelY - 4.0));
}

- (void)setHighlighted:(BOOL)highlighted {
    [super setHighlighted:highlighted];
    [UIView animateWithDuration:0.08 animations:^{
        self.alpha = highlighted ? 0.45 : 1.0;
        self.transform = highlighted ? CGAffineTransformMakeScale(0.94, 0.94) : CGAffineTransformIdentity;
    }];
}

@end

static BOOL DXIsHiddenShortcutSelector(NSString *selector) {
    return ![DXShortcutsGenerator isVisibleShortcutSelector:selector];
}

@interface DXCollectionView ()
@property (nonatomic, assign, readwrite) BOOL shortcutConfigurationAvailable;
@property (nonatomic, strong) UIControl *subActionPanelOverlay;
@property (nonatomic, strong) UIButton *subActionPanelSourceButton;
@end

// Shortcut order is a user-authored, physical left-to-right order. Keyboard
// accessory views can temporarily inherit a different semantic direction while
// UIKit moves them into its private keyboard hierarchy. UICollectionViewFlowLayout
// otherwise mirrors horizontal item positions when that direction changes,
// producing a reversed first frame followed by the configured order.
@interface DXTopShortcutFlowLayout : UICollectionViewFlowLayout
@end

@implementation DXTopShortcutFlowLayout

- (BOOL)flipsHorizontallyInOppositeLayoutDirection {
    return NO;
}

@end

@implementation DXCollectionView

// Resolves one configured shortcut entry into the parallel toolbar arrays.  The
// iOS 13 image slot takes the custom SF Symbol when it validates, and custom
// names are keyed by selector for short-label mode. iOS 12 has no SF Symbols,
// so images12 always keeps its default value.
-(void)integrateShortcutItem:(NSDictionary *)item
              intoImages12:(NSMutableArray *)images12
               images13:(NSMutableArray *)images13
               selectors:(NSMutableArray *)selectors
                    names:(NSMutableDictionary *)names {
    NSString *selector = item[@"selector"];
    [images12 addObject:item[@"images12"]];
    [images13 addObject:[DXHelper resolvedIconNameForShortcutItem:item defaultName:item[@"images13"]]];
    [selectors addObject:selector];

    NSString *customName = [DXHelper customNameForShortcutItem:item];
    if (customName) names[selector] = customName;
}

- (NSString *)scopedPreferenceKey:(NSString *)key {
    return DXScopedPreferenceKey(key, self.configuration ?: @"bottom");
}

- (int)shortcutsPerSection {
    // Button count is code-controlled, not a preference: the toolbar renders
    // every configured button clamped to [0, maxshortcutpersection].  The cap
    // equals the page size, so the toolbar always fits on a single section.
    return maxshortcutpersection;
}

// Button chrome is per toolbar: every value lives under the configuration-
// scoped key ("top"-prefixed on top of the keyboard, unprefixed below), so
// adjusting one toolbar never moves the other. Call after `prefs` reflects the
// current preference snapshot.
-(void)reloadButtonChrome {
    BOOL isTop = [self.configuration isEqualToString:@"top"];
    CGFloat heightFallback = isTop ? 33.33
        : (currentBackgroundTintColor ? cellsHeightDefault + 5 : cellsHeightDefault);
    self.buttonHeight = preferencesFloat([self scopedPreferenceKey:kCellHeightkey], heightFallback);
    self.buttonRadius = preferencesFloat([self scopedPreferenceKey:kCellRadiuskey], cellsRadiusDefault);
    self.buttonSpacing = preferencesFloat([self scopedPreferenceKey:kCellSpacingkey], spacingBetweenCellsDefault);
    self.borderEnabled = preferencesBool([self scopedPreferenceKey:kCellBorderEnabledkey], NO);
    self.borderWidth = preferencesFloat([self scopedPreferenceKey:kCellBorderWidthkey], buttonBorderWidthDefault);
    self.widthScale = preferencesFloat([self scopedPreferenceKey:kButtonWidthScalekey], buttonWidthScaleDefault);
    self.useShortLabel = preferencesBool([self scopedPreferenceKey:kShortLabelEnabledKey], NO);
}

// Buttons get visible chrome (per-button spacing, corner radius, spacing-aware
// insets) when either the shared background tint or this toolbar's border is on.
- (BOOL)buttonChromeActive {
    return currentBackgroundTintColor != nil || self.borderEnabled;
}

- (instancetype)initWithConfiguration:(NSString *)configuration{
    
    BOOL isTopConfiguration = [configuration isEqualToString:@"top"];
    UICollectionViewFlowLayout *flowLayout = isTopConfiguration
        ? [[DXTopShortcutFlowLayout alloc] init]
        : [[UICollectionViewFlowLayout alloc] init];
    flowLayout.scrollDirection = UICollectionViewScrollDirectionHorizontal;
    flowLayout.minimumLineSpacing = 0;


    if (self = [super initWithFrame:CGRectZero collectionViewLayout:flowLayout]) {
        // Keep the configured array order stable before and after the view is
        // attached to the keyboard's accessory hierarchy.
        if (isTopConfiguration) {
            self.semanticContentAttribute = UISemanticContentAttributeForceLeftToRight;
        }
        self.configuration = configuration ?: @"bottom";
        self.shortcutsGenerator = [DXShortcutsGenerator sharedInstance];
        // Build the data source exactly once, directly from the complete
        // preference snapshot.  There is no default/cache view that is later
        // covered by a second user-configured view.
        [self reloadShortcutConfiguration];
        flowLayout.minimumInteritemSpacing = [self buttonChromeActive] ? self.buttonSpacing : 0;
        
        self.hapticType = 1;
        self.refreshView = YES;
        self.firstCellVisible = YES;
        
        self.isWordSender = NO;
        self.moveCursorWithSelect = NO;
        
        
        self.backgroundColor = [UIColor clearColor];
        self.delegate = self;
        self.dataSource = self;
        self.showsVerticalScrollIndicator = NO;
        self.showsHorizontalScrollIndicator = NO;
        self.pagingEnabled = YES;
        [self registerClass:NSClassFromString(@"DXCell") forCellWithReuseIdentifier:@"kTypeXCellID"];
        dispatch_async(dispatch_get_main_queue(), ^{
            [self keyboardRotated:nil];
        });
        
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(typeXLayoutChanged:) name:@"typeXLayoutChanged" object:nil];
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(keyboardRotated:) name:UIDeviceOrientationDidChangeNotification object:nil];
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(keyboardWillHideForSubActionPanel:) name:UIKeyboardWillHideNotification object:nil];
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(scrollBackward:) name:@"scrollBackward" object:nil];
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(scrollForward:) name:@"scrollForward" object:nil];
        
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
    [self.subActionPanelOverlay removeFromSuperview];
    if (DXActiveSubActionPanelOwner == self) DXActiveSubActionPanelOwner = nil;
    [[NSNotificationCenter defaultCenter] removeObserver:self name:@"typeXLayoutChanged" object:nil];
    [[NSNotificationCenter defaultCenter] removeObserver:self name:UIDeviceOrientationDidChangeNotification object:nil];
    [[NSNotificationCenter defaultCenter] removeObserver:self name:UIKeyboardWillHideNotification object:nil];
    [[NSNotificationCenter defaultCenter] removeObserver:self name:@"scrollBackward" object:nil];
    [[NSNotificationCenter defaultCenter] removeObserver:self name:@"scrollForward" object:nil];
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
    //int firstCellGlobalIndex = [self shortcutsPerSection]*firstCellIndexPath.section + firstCellIndexPath.row;
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
    //int allowedMaxY = [self shortcutsPerSection];
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

-(void)autoPaginationControl{
    if (self.pagingEnabled){
        self.pagingEnabled = NO;
    }else{
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
    DXPrefsManager *manager = [DXPrefsManager sharedInstance];
    NSDictionary *currentPrefs = manager.preferencesAvailable ? manager.prefs : nil;
    self.shortcutConfigurationAvailable = [currentPrefs isKindOfClass:[NSDictionary class]];
    if (!self.shortcutConfigurationAvailable) currentPrefs = @{};
    prefs = [currentPrefs mutableCopy];
    //HBLogDebug(@"reloadShortcutConfiguration configuration=%@ shortcutsPerSection=%d scopedKey=%@", self.configuration, [self shortcutsPerSection], [self scopedPreferenceKey:kShortcutskey]);
    NSMutableArray *defaultImages12 = [[self.shortcutsGenerator imageNameArrayForiOS:0] mutableCopy];
    NSMutableArray *defaultImages13 = [[self.shortcutsGenerator imageNameArrayForiOS:1] mutableCopy];
    NSMutableArray *defaultSelectors = [[self.shortcutsGenerator selectorNames] mutableCopy];

    NSMutableArray *images12 = [NSMutableArray array];
    NSMutableArray *images13 = [NSMutableArray array];
    NSMutableArray *selectors = [NSMutableArray array];
    NSString *shortcutsKey = [self scopedPreferenceKey:kShortcutskey];
    id configuredValue = currentPrefs[shortcutsKey];
    NSArray *configuredShortcuts = [configuredValue isKindOfClass:[NSArray class]] ? configuredValue : nil;

    // Top and bottom shortcuts are fully decoupled.  When a scoped key has no
    // persisted value (e.g. user never opened "顶部设置"), the else-branch
    // below uses the default set (first N actions from DXShortcutsGenerator).
    // The bottom configuration is never inherited by the top toolbar.

    if (self.shortcutConfigurationAvailable && configuredShortcuts.count > 0 &&
        [configuredShortcuts[0] isKindOfClass:[NSArray class]]) {
        NSMutableDictionary *customNames = [[NSMutableDictionary alloc] init];
        for (NSDictionary *item in configuredShortcuts[0]) {
            if (images12.count >= [self shortcutsPerSection]) break;
            if (![item isKindOfClass:[NSDictionary class]]) continue;
            NSString *selector = item[@"selector"];
            // Draft buttons (saved without a tap action) render inert on the
            // toolbar; everything else unknown stays filtered out.
            if (!DXIsDraftActionSelector(selector) && DXIsHiddenShortcutSelector(selector)) continue;
            // Buttons switched off on the manage page stay stored but never render.
            if ([item[@"disabled"] boolValue]) continue;
            if (item[@"images12"] && item[@"images13"] && selector) {
                [self integrateShortcutItem:item intoImages12:images12 images13:images13 selectors:selectors names:customNames];
            }
        }
        self.customNames = customNames;
    } else if (self.shortcutConfigurationAvailable && configuredValue == nil) {
        NSUInteger count = MIN((NSUInteger)[self shortcutsPerSection],
                               MIN(defaultImages12.count,
                                   MIN(defaultImages13.count, defaultSelectors.count)));
        for (NSUInteger index = 0; index < count; index++) {
            [images12 addObject:defaultImages12[index]];
            [images13 addObject:defaultImages13[index]];
            [selectors addObject:defaultSelectors[index]];
        }
        self.customNames = @{};
    } else {
        // A missing snapshot or malformed persisted shortcut value is not a
        // request for the six defaults.  Keep the toolbar empty until a valid
        // snapshot arrives.
        self.customNames = @{};
    }

    self.shortcuts = @[images12, images13, selectors];
    //HBLogDebug(@"reloadShortcutConfiguration built shortcuts count=%lu for scope=%@", (unsigned long)images12.count, self.configuration);
    [self reloadButtonChrome];
    ((UICollectionViewFlowLayout *)self.collectionViewLayout).minimumInteritemSpacing = [self buttonChromeActive] ? self.buttonSpacing : 0;
    self.pagingEnabled = YES;
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
    if (notification) [self dismissSubActionPanelAnimated:NO completion:nil];
    
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

-(void)keyboardWillHideForSubActionPanel:(NSNotification *)notification {
    (void)notification;
    [self dismissSubActionPanelAnimated:NO completion:nil];
}


-(void)triggerImpactAndAnimationWithButton:(UIButton *)sender{
    //haptic, 0=none, 1=once, 2==success(twice)
    if ( preferencesBool(kEnabledHaptickey,YES) && self.hapticType != 0){

        if (self.hapticType == 1){
            [[[UIImpactFeedbackGenerator alloc] initWithStyle:UIImpactFeedbackStyleLight] impactOccurred];
        }else{
            [[[UINotificationFeedbackGenerator alloc] init] notificationOccurred:UINotificationFeedbackTypeSuccess];
            self.hapticType = 1;
        }
    }
}

-(void)beginUpdateDelegate{
    kbImpl = [objc_getClass("UIKeyboardImpl") activeInstance];
    delegate = DXKeyboardInputDelegate(kbImpl);
}

-(void)beginImpactAnimationAndUpdateDelegateWithSender:(UIButton *)sender{
    [self triggerImpactAndAnimationWithButton:sender];
    [self beginUpdateDelegate];
}

#pragma mark actions
-(void)selectAllAction:(UIButton*)sender{
    [self autoPaginationControl];
    [self beginImpactAnimationAndUpdateDelegateWithSender:sender];
    
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
    [self beginImpactAnimationAndUpdateDelegateWithSender:sender];
    
    [delegate _moveToStartOfLine:NO withHistory:nil];
    [delegate _moveToEndOfLine:YES withHistory:nil];
    [self autoPaginationControl];
}

-(void)selectParagraphAction:(UIButton*)sender{
    [self autoPaginationControl];
    [self beginImpactAnimationAndUpdateDelegateWithSender:sender];
    
    [delegate _moveToStartOfParagraph:NO withHistory:nil];
    [delegate _moveToEndOfParagraph:YES withHistory:nil];;
    [self autoPaginationControl];
}

-(void)selectSentenceAction:(UIButton*)sender{
    [self autoPaginationControl];
    [self beginImpactAnimationAndUpdateDelegateWithSender:sender];
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
    [self beginImpactAnimationAndUpdateDelegateWithSender:sender];

    if (![delegate respondsToSelector:@selector(selectedTextRange)]) {
        [self autoPaginationControl];
        return;
    }

    // With no selection, copy the whole content instead of doing nothing.
    BOOL hadSelection = [[delegate textInRange:[delegate selectedTextRange]] length] > 0;
    if (!hadSelection) {
        if ([delegate respondsToSelector:@selector(selectAll:)]) {
            [delegate selectAll:nil];
        }else if ([delegate respondsToSelector:@selector(selectAll)]){
            [delegate selectAll];
        }
    }

    if ([delegate respondsToSelector:@selector(copy:)]) {
        [delegate copy:nil]; //UIResponderStandardEditActions.h
    }else{
        UITextRange *range = [delegate selectedTextRange];
        UIPasteboard *pasteboard = [UIPasteboard generalPasteboard];

        [pasteboard setString:[delegate textInRange:range]];
    }

    if (!hadSelection) {
        // Do not linger in the select-all state: collapse the caret to the end
        // of the copied range, where a regular copy leaves it.
        UITextRange *range = [delegate selectedTextRange];
        if (range) {
            [delegate setSelectedTextRange:[delegate textRangeFromPosition:range.end toPosition:range.end]];
        }
        [kbImpl clearTransientState];
        [kbImpl clearAnimations];
        [kbImpl setCaretBlinks:YES];
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
    [self beginImpactAnimationAndUpdateDelegateWithSender:sender];
    
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
    [self beginImpactAnimationAndUpdateDelegateWithSender:sender];

    // With no selection, cut the whole content instead of doing nothing.
    // Cutting collapses the selection back to a caret by itself.
    if ([delegate respondsToSelector:@selector(selectedTextRange)] &&
        [[delegate textInRange:[delegate selectedTextRange]] length] == 0) {
        if ([delegate respondsToSelector:@selector(selectAll:)]) {
            [delegate selectAll:nil];
        }else if ([delegate respondsToSelector:@selector(selectAll)]){
            [delegate selectAll];
        }
    }

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
    [self beginImpactAnimationAndUpdateDelegateWithSender:sender];
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
    [self beginImpactAnimationAndUpdateDelegateWithSender:sender];
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
    [self beginImpactAnimationAndUpdateDelegateWithSender:sender];
    
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
    [self beginImpactAnimationAndUpdateDelegateWithSender:sender];
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
    [self beginImpactAnimationAndUpdateDelegateWithSender:sender];
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
    [self beginImpactAnimationAndUpdateDelegateWithSender:sender];
    [kbImpl deleteBackward];
    [kbImpl clearTransientState];
    [kbImpl clearAnimations];
    [kbImpl setCaretBlinks:YES];
    [self autoPaginationControl];
}

-(void)deleteForwardAction:(UIButton*)sender{
    [self autoPaginationControl];
    [self beginImpactAnimationAndUpdateDelegateWithSender:sender];
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
    self.hapticType = 2;
    [self beginImpactAnimationAndUpdateDelegateWithSender:sender];

    // Clear in place: select the whole document directly instead of running
    // the select-all action, and delete it within the same run-loop tick so
    // no selection highlight or handles ever appear.
    if ([delegate respondsToSelector:@selector(selectedTextRange)]) {
        UIResponder <UITextInput> *tempDelegate = (UIResponder <UITextInput> *)delegate;
        UITextRange *wholeRange = [tempDelegate textRangeFromPosition:[tempDelegate beginningOfDocument]
                                                           toPosition:[tempDelegate endOfDocument]];
        if (wholeRange == nil || [[tempDelegate textInRange:wholeRange] length] == 0) {
            [self autoPaginationControl];
            return;
        }
        tempDelegate.selectedTextRange = wholeRange;
    }else if ([delegate respondsToSelector:@selector(selectAll:)]) {
        [delegate selectAll:nil];
    }else if ([delegate respondsToSelector:@selector(selectAll)]){
        [delegate selectAll];
    }

    [kbImpl deleteFromInput];
    [kbImpl clearTransientState];
    [kbImpl clearAnimations];
    [kbImpl setCaretBlinks:YES];
    [self autoPaginationControl];
}

-(void)openLinkAction:(UIButton*)sender{
    [self autoPaginationControl];
    [self beginImpactAnimationAndUpdateDelegateWithSender:sender];

    if (![delegate respondsToSelector:@selector(selectedTextRange)]) {
        [self autoPaginationControl];
        return;
    }

    // A selection is checked verbatim; otherwise scan the whole content for
    // the first link. Text with an explicit scheme (https:// or an app scheme
    // such as "myapp://...") is opened as-is — openURL routes http(s) to the
    // browser and custom schemes to their app. Scheme-less hosts such as
    // "www.example.com" fall back to NSDataDetector.
    NSString *text = [delegate textInRange:[delegate selectedTextRange]];
    if (text.length == 0) {
        text = [delegate textInRange:[delegate textRangeFromPosition:[delegate beginningOfDocument]
                                                         toPosition:[delegate endOfDocument]]];
    }

    NSURL *url = nil;
    if (text.length > 0) {
        NSString *candidate = [text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        NSRange schemeRange = [candidate rangeOfString:@"^[a-zA-Z][a-zA-Z0-9+.-]*://" options:NSRegularExpressionSearch];
        if (schemeRange.location == 0) {
            url = [NSURL URLWithString:candidate];
        }
        if (!url && [self isValidURL:candidate]) {
            url = [NSURL URLWithString:candidate];
        }
        if (!url) {
            NSDataDetector *detector = [NSDataDetector dataDetectorWithTypes:NSTextCheckingTypeLink error:nil];
            if (detector) {
                for (NSTextCheckingResult *match in [detector matchesInString:candidate options:0 range:NSMakeRange(0, candidate.length)]) {
                    url = match.URL;
                    break;
                }
            }
        }
    }

    if (url) {
        [[UIApplication sharedApplication] openURL:url options:@{} completionHandler:nil];
    }
    [self autoPaginationControl];
}





-(void)dismissKeyboardAction:(UIButton*)sender{
    [self autoPaginationControl];
    [self triggerImpactAndAnimationWithButton:sender];
    kbImpl = [objc_getClass("UIKeyboardImpl") activeInstance];
    [kbImpl dismissKeyboard];
    [self autoPaginationControl];
}

-(void)moveCursorLeftAction:(UIButton*)sender{
    [self autoPaginationControl];
    [self beginImpactAnimationAndUpdateDelegateWithSender:sender];
    
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
    [self beginImpactAnimationAndUpdateDelegateWithSender:sender];
    
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
        [self triggerImpactAndAnimationWithButton:sender];
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
        [self triggerImpactAndAnimationWithButton:sender];
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
    [self beginImpactAnimationAndUpdateDelegateWithSender:sender];
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
    [self beginImpactAnimationAndUpdateDelegateWithSender:sender];
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
    [self beginImpactAnimationAndUpdateDelegateWithSender:sender];
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
    [self beginImpactAnimationAndUpdateDelegateWithSender:sender];
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
    [self beginImpactAnimationAndUpdateDelegateWithSender:sender];
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
    [self beginImpactAnimationAndUpdateDelegateWithSender:sender];
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
    [self beginImpactAnimationAndUpdateDelegateWithSender:sender];
    
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
    [self beginImpactAnimationAndUpdateDelegateWithSender:sender];
    
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

-(void)defineAction:(UIButton*)sender{
    [self autoPaginationControl];
    [self beginImpactAnimationAndUpdateDelegateWithSender:sender];
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
    [self triggerImpactAndAnimationWithButton:sender];
    if (snippet[@"command"]){
        [self runCommand:snippet[@"command"]];
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
    [self beginImpactAnimationAndUpdateDelegateWithSender:sender];
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
    return ceil((float)(((NSArray *)_shortcuts[kbuttonsImages12]).count)/(float)[self shortcutsPerSection]);
}

-(NSInteger)collectionView:(UICollectionView *)collectionView numberOfItemsInSection:(NSInteger)section
{
    if (([self numberOfSectionsInCollectionView:collectionView] -1) == section){
        return ((NSArray *)_shortcuts[kbuttonsImages12]).count-[self shortcutsPerSection]*(section);
    }else{
        return ((NSArray *)_shortcuts[kbuttonsImages12]).count>[self shortcutsPerSection]?[self shortcutsPerSection]:((NSArray *)_shortcuts[kbuttonsImages12]).count;
    }
}

// Shared by the long-press gesture and the "点按触发子动作" tap mode: a single
// sub-action fires directly, several open a chooser, none keeps the gesture
// inert. The dedicated long-press action store is no longer consulted.
-(void)runSubActionsForButton:(UIButton *)button {
    [self autoPaginationControl];
    NSArray<NSString *> *subActions = preferencesSubActionSelectorsForIdentifier(button.accessibilityIdentifier, self.configuration);
    if (subActions.count == 0) return;

    self.hapticType = 2;

    if (subActions.count == 1) {
        [self dispatchSubActionSelector:subActions.firstObject sender:button];
        return;
    }
    [self presentSubActionChooserForButton:button selectors:subActions];
}

-(void)activateLPActions:(UIGestureRecognizer *)recognizer {
    if (recognizer.state != UIGestureRecognizerStateBegan) return;
    [self runSubActionsForButton:(UIButton *)recognizer.view];
}

// Bundle identifiers use reverse-DNS notation. Limit the prefix to common
// reverse-domain namespaces so scheme-less hosts such as "www.example.com"
// continue through the web-link path.
-(BOOL)isBundleIdentifier:(NSString *)value {
    if (value.length == 0 || [value rangeOfString:@"://"].location != NSNotFound) return NO;
    NSRegularExpression *expression = [NSRegularExpression regularExpressionWithPattern:@"^[A-Za-z][A-Za-z0-9-]*(\\.[A-Za-z0-9][A-Za-z0-9-]*){2,}$"
                                                                                options:0
                                                                                  error:nil];
    if ([expression firstMatchInString:value options:0 range:NSMakeRange(0, value.length)] == nil) return NO;
    NSString *prefix = [value componentsSeparatedByString:@"."].firstObject.lowercaseString;
    return [@[@"com", @"org", @"net", @"io", @"co", @"me", @"cn", @"app", @"dev"] containsObject:prefix];
}

-(NSString *)currentInputTextForCustomAction {
    if (![delegate respondsToSelector:@selector(beginningOfDocument)] ||
        ![delegate respondsToSelector:@selector(endOfDocument)] ||
        ![delegate respondsToSelector:@selector(textRangeFromPosition:toPosition:)] ||
        ![delegate respondsToSelector:@selector(textInRange:)]) return @"";

    @try {
        UITextPosition *beginning = [delegate beginningOfDocument];
        UITextPosition *end = [delegate endOfDocument];
        UITextRange *range = [delegate textRangeFromPosition:beginning toPosition:end];
        NSString *text = range ? [delegate textInRange:range] : nil;
        return [text isKindOfClass:[NSString class]] ? text : @"";
    } @catch (NSException *exception) {
        HBLogWarn(@"TypeX could not read the current input for a custom action: %@", exception);
        return @"";
    }
}

-(NSString *)escapedCustomActionParameter:(NSString *)value {
    NSMutableCharacterSet *allowed = [[NSCharacterSet alphanumericCharacterSet] mutableCopy];
    [allowed addCharactersInString:@"-._~"];
    return [value stringByAddingPercentEncodingWithAllowedCharacters:allowed] ?: @"";
}

-(void)showCustomActionLinkError {
    dispatch_async(dispatch_get_main_queue(), ^{
        UIView *container = self.window ?: DXKeyWindow();
        if (!container) return;

        [[container viewWithTag:DXCustomActionToastTag] removeFromSuperview];
        UILabel *toast = [[UILabel alloc] initWithFrame:CGRectZero];
        toast.tag = DXCustomActionToastTag;
        toast.text = LOCALIZED(@"CUSTOM_ACTION_LINK_ERROR");
        if (toast.text.length == 0) toast.text = @"动作链接设置错误";
        toast.textColor = UIColor.whiteColor;
        toast.backgroundColor = [UIColor colorWithWhite:0.08 alpha:0.88];
        toast.font = [UIFont systemFontOfSize:14 weight:UIFontWeightMedium];
        toast.textAlignment = NSTextAlignmentCenter;
        toast.numberOfLines = 0;
        toast.layer.cornerRadius = 9;
        toast.layer.masksToBounds = YES;

        CGFloat maxWidth = MAX(120, MIN(CGRectGetWidth(container.bounds) - 40, 320));
        CGSize textSize = [toast sizeThatFits:CGSizeMake(maxWidth - 28, CGFLOAT_MAX)];
        CGFloat width = MIN(maxWidth, MAX(160, textSize.width + 28));
        CGFloat height = MAX(42, textSize.height + 20);
        CGFloat y = MAX(20, CGRectGetMidY(container.bounds) - height / 2.0);
        toast.frame = CGRectMake((CGRectGetWidth(container.bounds) - width) / 2.0, y, width, height);
        toast.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin | UIViewAutoresizingFlexibleRightMargin |
                                 UIViewAutoresizingFlexibleTopMargin | UIViewAutoresizingFlexibleBottomMargin;
        toast.alpha = 0;
        [container addSubview:toast];

        [UIView animateWithDuration:0.18 animations:^{
            toast.alpha = 1;
        } completion:^(BOOL finished) {
            [UIView animateWithDuration:0.22 delay:1.6 options:UIViewAnimationOptionCurveEaseInOut animations:^{
                toast.alpha = 0;
            } completion:^(BOOL finished) {
                [toast removeFromSuperview];
            }];
        }];
    });
}

-(BOOL)openApplicationWithBundleIdentifier:(NSString *)bundleIdentifier {
    Class proxyClass = objc_getClass("LSApplicationProxy");
    SEL proxySelector = NSSelectorFromString(@"applicationProxyForIdentifier:");
    id proxy = proxyClass && [proxyClass respondsToSelector:proxySelector]
        ? ((id(*)(id, SEL, id))objc_msgSend)(proxyClass, proxySelector, bundleIdentifier)
        : nil;
    SEL installedSelector = NSSelectorFromString(@"isInstalled");
    BOOL installed = proxy && [proxy respondsToSelector:installedSelector] &&
        ((BOOL(*)(id, SEL))objc_msgSend)(proxy, installedSelector);
    SEL prohibitedSelector = NSSelectorFromString(@"isLaunchProhibited");
    if (!installed || ([proxy respondsToSelector:prohibitedSelector] &&
        ((BOOL(*)(id, SEL))objc_msgSend)(proxy, prohibitedSelector))) return NO;

    Class workspaceClass = objc_getClass("LSApplicationWorkspace");
    SEL defaultWorkspaceSelector = NSSelectorFromString(@"defaultWorkspace");
    id workspace = workspaceClass && [workspaceClass respondsToSelector:defaultWorkspaceSelector]
        ? ((id(*)(id, SEL))objc_msgSend)(workspaceClass, defaultWorkspaceSelector)
        : nil;
    SEL openSelector = NSSelectorFromString(@"openApplicationWithBundleID:");
    if (!workspace || ![workspace respondsToSelector:openSelector]) return NO;

    @try {
        ((void(*)(id, SEL, id))objc_msgSend)(workspace, openSelector, bundleIdentifier);
        return YES;
    } @catch (NSException *exception) {
        HBLogWarn(@"TypeX failed to open application %@: %@", bundleIdentifier, exception);
        return NO;
    }
}

// Opens a user-defined web URL, URL scheme, or installed app bundle ID. The
// @@@ placeholder receives the active input control's complete text.
-(BOOL)dispatchLinkActionSelector:(NSString *)selectorName sender:(UIButton *)sender {
    NSDictionary *entry = preferencesLinkActionForSelector(selectorName);
    if (!entry) return NO;

    NSString *link = [entry[@"link"] isKindOfClass:[NSString class]] ? entry[@"link"] : @"";
    link = [link stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    [self autoPaginationControl];
    [self beginImpactAnimationAndUpdateDelegateWithSender:sender];

    if ([link containsString:@"@@@"]) {
        NSString *parameter = [self escapedCustomActionParameter:[self currentInputTextForCustomAction]];
        link = [link stringByReplacingOccurrencesOfString:@"@@@" withString:parameter];
    }

    if (link.length == 0) {
        [self showCustomActionLinkError];
        [self autoPaginationControl];
        return YES;
    }

    if ([self isBundleIdentifier:link]) {
        if (![self openApplicationWithBundleIdentifier:link]) {
            HBLogWarn(@"TypeX failed to open custom action bundle identifier %@", link);
            [self showCustomActionLinkError];
        }
        [self autoPaginationControl];
        return YES;
    }

    NSURL *url = [NSURL URLWithString:link];
    if (url.scheme.length == 0) {
        url = [NSURL URLWithString:[@"https://" stringByAppendingString:link]];
    }
    BOOL webURLMissingHost = ([url.scheme.lowercaseString isEqualToString:@"http"] ||
                              [url.scheme.lowercaseString isEqualToString:@"https"]) && url.host.length == 0;
    if (!url || url.scheme.length == 0 || webURLMissingHost) {
        HBLogWarn(@"TypeX ignoring invalid custom action link %@", link);
        [self showCustomActionLinkError];
        [self autoPaginationControl];
        return YES;
    }

    [[UIApplication sharedApplication] openURL:url options:@{} completionHandler:^(BOOL success) {
        if (!success) {
            HBLogWarn(@"TypeX failed to open custom action URL %@", url);
            [self showCustomActionLinkError];
        }
    }];
    [self autoPaginationControl];
    return YES;
}

// Dispatches either one built-in selector or one user-defined link selector.
-(void)dispatchConfiguredActionSelector:(NSString *)selectorName sender:(UIButton *)sender {
    if ([self dispatchLinkActionSelector:selectorName sender:sender]) return;
    if (![DXShortcutsGenerator isVisibleShortcutSelector:selectorName]) {
        HBLogWarn(@"TypeX ignoring legacy/hidden selector %@", selectorName);
        return;
    }

    SEL action = NSSelectorFromString(selectorName);
    if (![self respondsToSelector:action]) {
        HBLogWarn(@"TypeX ignoring unimplemented %@ for %@", selectorName, sender.accessibilityIdentifier);
        return;
    }

    ((void(*)(id, SEL, id))objc_msgSend)(self, action, sender);
}

-(void)dispatchSubActionSelector:(NSString *)selectorName sender:(UIButton *)sender {
    [self dispatchConfiguredActionSelector:selectorName sender:sender];
}

-(NSString *)subActionPanelTitleForSelector:(NSString *)selectorName {
    NSDictionary *linkAction = preferencesLinkActionForSelector(selectorName);
    NSString *title = [linkAction[@"name"] isKindOfClass:[NSString class]] ? linkAction[@"name"] : @"";
    if (title.length == 0) {
        title = [DXHelper localizedStringForActionNamed:selectorName shortName:NO bundle:tweakBundle];
    }
    return title.length ? title : selectorName;
}

-(UIImage *)subActionPanelImageForSelector:(NSString *)selectorName {
    NSDictionary *linkAction = preferencesLinkActionForSelector(selectorName);
    if (linkAction) {
        NSString *iconName = [linkAction[@"icon"] isKindOfClass:[NSString class]] ? linkAction[@"icon"] : @"";
        UIImage *image = [UIImage systemImageNamed:(iconName.length ? iconName : @"link")];
        return image ?: [UIImage systemImageNamed:@"link"];
    }

    NSArray<NSString *> *actionSelectors = [self.shortcutsGenerator selectorNames];
    NSUInteger index = [actionSelectors indexOfObject:selectorName];
    if (index != NSNotFound) {
        NSInteger imageVersion = 0;
        if (@available(iOS 13.0, *)) imageVersion = 1;
        NSArray<NSString *> *imageNames = [self.shortcutsGenerator imageNameArrayForiOS:imageVersion];
        if (index < imageNames.count) {
            UIImage *image = [DXHelper imageForName:imageNames[index] withSystemColor:NO completion:nil];
            if (image) return image;
        }
    }
    return [UIImage systemImageNamed:@"square.grid.2x2"];
}

-(CGFloat)subActionPanelAnchorYInWindow:(UIWindow *)window {
    CGRect toolbarFrame = [self convertRect:self.bounds toView:window];
    CGFloat anchorY = CGRectGetMinY(toolbarFrame);
    CGFloat minimumUsefulY = window.safeAreaInsets.top + 40.0;
    CGFloat minimumWideWidth = CGRectGetWidth(window.bounds) * 0.72;

    // The bottom toolbar lives near the keyboard's bottom. Walk through its
    // full-width keyboard ancestors to find the keyboard's upper edge. The top
    // accessory toolbar is already at that edge, so its own frame wins.
    for (UIView *ancestor = self.superview; ancestor && ancestor != window; ancestor = ancestor.superview) {
        CGRect frame = [ancestor convertRect:ancestor.bounds toView:window];
        CGFloat candidateY = CGRectGetMinY(frame);
        if (CGRectGetWidth(frame) >= minimumWideWidth && candidateY > minimumUsefulY && candidateY < anchorY) {
            anchorY = candidateY;
        }
    }
    return anchorY;
}

-(void)dismissSubActionPanelAnimated:(BOOL)animated completion:(void (^)(void))completion {
    UIControl *overlay = self.subActionPanelOverlay;
    if (!overlay) {
        if (completion) completion();
        return;
    }

    self.subActionPanelOverlay = nil;
    self.subActionPanelSourceButton = nil;
    if (DXActiveSubActionPanelOwner == self) DXActiveSubActionPanelOwner = nil;

    void (^removePanel)(void) = ^{
        [overlay removeFromSuperview];
        if (completion) completion();
    };
    if (!animated) {
        removePanel();
        return;
    }

    UIView *panel = [overlay viewWithTag:DXSubActionPanelOverlayTag + 1];
    [UIView animateWithDuration:0.14 animations:^{
        overlay.alpha = 0.0;
        panel.transform = CGAffineTransformConcat(CGAffineTransformMakeTranslation(0, 8),
                                                   CGAffineTransformMakeScale(0.97, 0.97));
    } completion:^(__unused BOOL finished) {
        removePanel();
    }];
}

-(void)subActionPanelBackgroundTapped:(UIControl *)sender {
    (void)sender;
    [self dismissSubActionPanelAnimated:YES completion:nil];
}

-(void)subActionPanelItemTapped:(DXSubActionPanelItem *)item {
    NSString *selectorName = [item.actionSelector copy];
    UIButton *sourceButton = self.subActionPanelSourceButton;
    [self dismissSubActionPanelAnimated:YES completion:^{
        if (selectorName.length > 0) {
            [self dispatchSubActionSelector:selectorName sender:sourceButton];
        }
    }];
}

-(void)presentSubActionChooserForButton:(UIButton *)button selectors:(NSArray<NSString *> *)selectors {
    if (selectors.count == 0) return;
    UIWindow *window = button.window ?: self.window ?: [self keyWindow];
    if (!window) return;

    if (DXActiveSubActionPanelOwner && DXActiveSubActionPanelOwner != self) {
        [DXActiveSubActionPanelOwner dismissSubActionPanelAnimated:NO completion:nil];
    }
    [self dismissSubActionPanelAnimated:NO completion:nil];

    UIControl *overlay = [[UIControl alloc] initWithFrame:window.bounds];
    overlay.tag = DXSubActionPanelOverlayTag;
    overlay.backgroundColor = UIColor.clearColor;
    overlay.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    [overlay addTarget:self action:@selector(subActionPanelBackgroundTapped:) forControlEvents:UIControlEventTouchUpInside];
    [window addSubview:overlay];

    CGFloat windowWidth = CGRectGetWidth(window.bounds);
    CGFloat panelScale = preferencesFloat([self scopedPreferenceKey:kSubActionPanelScaleKey],
                                          subActionPanelScaleDefault) / 100.0;
    panelScale = MIN(1.2, MAX(0.5, panelScale));
    CGFloat horizontalMargin = 8.0;
    CGFloat defaultPanelWidth = MIN(460.0, MAX(240.0, windowWidth - 24.0));
    // The size setting scales panel content and height only. Keep the panel's
    // horizontal footprint stable so changing the slider never shifts columns
    // or makes the floating panel narrower/wider.
    CGFloat panelWidth = MIN(windowWidth - horizontalMargin * 2.0, defaultPanelWidth);
    NSInteger columns = windowWidth >= 320.0 ? 4 : 3;
    CGFloat panelPadding = 10.0 * panelScale;
    CGFloat itemHeight = 92.0 * panelScale;
    CGFloat itemWidth = (panelWidth - panelPadding * 2.0) / columns;
    NSInteger rows = (selectors.count + columns - 1) / columns;
    CGFloat contentHeight = panelPadding * 2.0 + rows * itemHeight;

    CGFloat safeTop = window.safeAreaInsets.top + 8.0;
    CGFloat anchorY = [self subActionPanelAnchorYInWindow:window];
    CGFloat availableHeight = MAX(itemHeight + panelPadding * 2.0, anchorY - safeTop - 8.0);
    CGFloat panelHeight = MIN(contentHeight, MIN(availableHeight, 300.0 * panelScale));
    CGFloat panelY = MAX(safeTop, anchorY - panelHeight - 8.0);

    UIView *panel = [[UIView alloc] initWithFrame:CGRectMake((windowWidth - panelWidth) / 2.0,
                                                             panelY, panelWidth, panelHeight)];
    panel.tag = DXSubActionPanelOverlayTag + 1;
    panel.layer.cornerRadius = 18.0 * panelScale;
    panel.layer.shadowColor = UIColor.blackColor.CGColor;
    panel.layer.shadowOpacity = 0.2;
    panel.layer.shadowRadius = 14.0 * panelScale;
    panel.layer.shadowOffset = CGSizeMake(0, 5.0 * panelScale);
    [overlay addSubview:panel];

    UIBlurEffect *effect = [UIBlurEffect effectWithStyle:UIBlurEffectStyleSystemMaterial];
    UIVisualEffectView *background = [[UIVisualEffectView alloc] initWithEffect:effect];
    background.frame = panel.bounds;
    background.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    background.layer.cornerRadius = panel.layer.cornerRadius;
    background.layer.masksToBounds = YES;
    [panel addSubview:background];

    UIScrollView *scrollView = [[UIScrollView alloc] initWithFrame:panel.bounds];
    scrollView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    scrollView.contentSize = CGSizeMake(panelWidth, contentHeight);
    scrollView.alwaysBounceVertical = contentHeight > panelHeight;
    scrollView.showsVerticalScrollIndicator = NO;
    [panel addSubview:scrollView];

    // Cover the scrollable content behind the action items so gaps, padding,
    // and the unused cells in the final row dismiss the panel as well.
    UIControl *blankArea = [[UIControl alloc] initWithFrame:CGRectMake(0, 0, panelWidth,
                                                                       MAX(contentHeight, panelHeight))];
    blankArea.backgroundColor = UIColor.clearColor;
    [blankArea addTarget:self action:@selector(subActionPanelBackgroundTapped:) forControlEvents:UIControlEventTouchUpInside];
    [scrollView addSubview:blankArea];

    [selectors enumerateObjectsUsingBlock:^(NSString *selectorName, NSUInteger index, __unused BOOL *stop) {
        NSInteger row = index / columns;
        NSInteger column = index % columns;
        DXSubActionPanelItem *item = [[DXSubActionPanelItem alloc] initWithFrame:CGRectMake(panelPadding + column * itemWidth,
                                                                                            panelPadding + row * itemHeight,
                                                                                            itemWidth, itemHeight)];
        item.actionSelector = selectorName;
        item.panelScale = panelScale;
        item.nameLabel.font = [UIFont systemFontOfSize:MAX(10.0, 13.0 * panelScale)
                                                weight:UIFontWeightRegular];
        [item configureWithTitle:[self subActionPanelTitleForSelector:selectorName]
                           image:[self subActionPanelImageForSelector:selectorName]];
        [item addTarget:self action:@selector(subActionPanelItemTapped:) forControlEvents:UIControlEventTouchUpInside];
        [scrollView addSubview:item];
    }];

    self.subActionPanelOverlay = overlay;
    self.subActionPanelSourceButton = button;
    DXActiveSubActionPanelOwner = self;

    overlay.alpha = 0.0;
    panel.transform = CGAffineTransformConcat(CGAffineTransformMakeTranslation(0, 8),
                                               CGAffineTransformMakeScale(0.97, 0.97));
    [UIView animateWithDuration:0.18 delay:0 options:UIViewAnimationOptionCurveEaseOut animations:^{
        overlay.alpha = 1.0;
        panel.transform = CGAffineTransformIdentity;
    } completion:nil];
}

- (void)activateSwipeActions:(UISwipeGestureRecognizer *)recognizer {
    if (recognizer.state != UIGestureRecognizerStateEnded) return;

    int gestureType;
    switch (recognizer.direction) {
        case UISwipeGestureRecognizerDirectionUp: gestureType = DXShortcutGestureSwipeUp; break;
        case UISwipeGestureRecognizerDirectionDown: gestureType = DXShortcutGestureSwipeDown; break;
        case UISwipeGestureRecognizerDirectionLeft: gestureType = DXShortcutGestureSwipeLeft; break;
        case UISwipeGestureRecognizerDirectionRight: gestureType = DXShortcutGestureSwipeRight; break;
        default: return;
    }

    [self autoPaginationControl];
    UIButton *button = (UIButton *)recognizer.view;
    NSString *selectorName = preferencesSelectorForIdentifierScoped(button.accessibilityIdentifier, 1, gestureType, @"", self.configuration);
    if (selectorName.length == 0) return;

    self.hapticType = 2;
    [self dispatchConfiguredActionSelector:selectorName sender:button];
}

-(void)cellButtonTouchUpInside:(UIButton *)sender {
    // "点按触发子动作" buttons: tap runs the sub-action chain exactly like a
    // long press and the configured tap action is skipped entirely.
    if (preferencesTapRunsSubActionsForIdentifier(sender.accessibilityIdentifier, self.configuration)) {
        [self runSubActionsForButton:sender];
        return;
    }

    // With the switch off, tap runs ONLY the tap action: the configured 点按
    // action, or the button's own historical TouchUpInside selector. Sub-actions
    // stay on the long press (and on tap only while the switch is on).
    NSString *selectorName = preferencesSelectorForIdentifierScoped(sender.accessibilityIdentifier, 1, DXShortcutGestureTap, @"", self.configuration);
    if (selectorName.length == 0) selectorName = sender.accessibilityIdentifier;

    // Draft buttons have no action yet: they render but taps stay inert.
    if (DXIsDraftActionSelector(selectorName)) return;
    [self dispatchConfiguredActionSelector:selectorName sender:sender];
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
    
    
    if (@available(iOS 13.0, *)){
        imageOfName = self.useShortLabel
            ? [(self.customNames[selectorName] ?: [DXHelper localizedStringForActionNamed:selectorName shortName:YES bundle:tweakBundle]) attributedString]
            : [((NSArray *)_shortcuts[kbuttonsImages13])[cellIndex] attributedString];
    }else{
        imageOfName = self.useShortLabel
            ? [(self.customNames[selectorName] ?: [DXHelper localizedStringForActionNamed:selectorName shortName:YES bundle:tweakBundle]) attributedString]
            : [((NSArray *)_shortcuts[kbuttonsImages12])[cellIndex] attributedString];
    }
    if (!self.useShortLabel) {
        image = [DXHelper imageForName:imageOfName.string withSystemColor:NO completion:nil];
    }
    if (self.useShortLabel){
        [cell.btn setImage:nil forState:UIControlStateNormal];
        [cell.btn setAttributedTitle:imageOfName forState:UIControlStateNormal];
    }else{
        [cell.btn setAttributedTitle:nil forState:UIControlStateNormal];
        [cell.btn setImage:image forState:UIControlStateNormal];
    }
    cell.btn.accessibilityIdentifier = selectorName;
    [cell.btn removeTarget:nil action:NULL forControlEvents:UIControlEventAllEvents];
    
    // Single tap is the button's own TouchUpInside event: it fires on touch-up
    // with no gesture-recognizer window, so taps can be repeated as fast as the
    // user likes. No tap recognizer is mounted; one would delay every touch-up
    // until it fails.
    [cell.btn addTarget:self action:@selector(cellButtonTouchUpInside:) forControlEvents:UIControlEventTouchUpInside];

    // Long press runs the button's sub-action configuration, so it is mounted
    // only for buttons that have sub-actions, mirroring the conditional swipe
    // recognizers below.
    NSMutableArray<UIGestureRecognizer *> *recognizers = [NSMutableArray array];
    if ([preferencesSubActionSelectorsForIdentifier(cell.btn.accessibilityIdentifier, self.configuration) count] > 0) {
        UILongPressGestureRecognizer *longPress = [[UILongPressGestureRecognizer alloc] initWithTarget:self action:@selector(activateLPActions:)];
        longPress.minimumPressDuration = 0.5;
        [recognizers addObject:longPress];
    }

    // Swipe recognizers are mounted only for directions with a configured
    // action, mirroring the conditional double-tap approach: an always-mounted
    // horizontal swipe would win over the paging pan on flicks that start on a
    // button.
    for (NSInteger gesture = DXShortcutGestureSwipeUp; gesture <= DXShortcutGestureSwipeRight; gesture++) {
        if ([preferencesSelectorForIdentifierScoped(cell.btn.accessibilityIdentifier, 1, (int)gesture, @"", self.configuration) length] == 0) continue;

        UISwipeGestureRecognizer *swipe = [[UISwipeGestureRecognizer alloc] initWithTarget:self action:@selector(activateSwipeActions:)];
        switch (gesture) {
            case DXShortcutGestureSwipeUp: swipe.direction = UISwipeGestureRecognizerDirectionUp; break;
            case DXShortcutGestureSwipeDown: swipe.direction = UISwipeGestureRecognizerDirectionDown; break;
            case DXShortcutGestureSwipeLeft: swipe.direction = UISwipeGestureRecognizerDirectionLeft; break;
            default: swipe.direction = UISwipeGestureRecognizerDirectionRight; break;
        }
        [recognizers addObject:swipe];
    }
    cell.btn.gestureRecognizers = recognizers;
    
    //cell.btn.backgroundColor = [UIColor clearColor];
    //cell.btn.layer.cornerRadius = 0; // this value vary as per your desire
    //cell.btn.clipsToBounds = NO;
    //}
    //self.layer.masksToBounds = NO;
    
    if (self.useShortLabel) cell.btn.clipsToBounds = YES; else cell.btn.clipsToBounds = NO;

    // Button chrome: corner radius and the optional outlined border. The border
    // color follows the system label color so it stays visible on both light
    // and dark keyboards.
    cell.btn.layer.cornerRadius = [self buttonChromeActive] ? self.buttonRadius : 0;
    cell.btn.layer.borderWidth = self.borderEnabled ? self.borderWidth : 0;
    cell.btn.layer.borderColor = self.borderEnabled ? [UIColor labelColor].CGColor : NULL;
    [cell applyButtonWidthMultiplier:self.widthScale / buttonWidthScaleDefault];
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
    if ([self.configuration isEqualToString:@"top"]) {
        NSInteger items = MAX(1, [self numberOfItemsInSection:indexPath.section]);
        CGFloat gaps = [self buttonChromeActive] ? self.buttonSpacing * (items - 1) : 0;
        CGFloat width = MAX(0, (collectionView.frame.size.width - gaps) / items);
        return CGSizeMake(width, self.buttonHeight);
    }

    CGFloat useableWidth = (([self buttonChromeActive] && collectionView.frame.size.width-4*self.buttonSpacing >0) ? collectionView.frame.size.width - 4*self.buttonSpacing : collectionView.frame.size.width) / ([self numberOfItemsInSection:indexPath.section] <= [self shortcutsPerSection] ? (((NSArray *)_shortcuts[kbuttonsImages12]).count <= [self shortcutsPerSection] ? ((NSArray *)_shortcuts[kbuttonsImages12]).count : [self shortcutsPerSection]) :  [self numberOfItemsInSection:indexPath.section]);

    return CGSizeMake(useableWidth, self.buttonHeight);
}

- (UIEdgeInsets)collectionView:(UICollectionView *)collectionView layout:(UICollectionViewLayout *)collectionViewLayout insetForSectionAtIndex:(NSInteger)section {
    if ([self.configuration isEqualToString:@"top"]) {
        if (![self buttonChromeActive]) return UIEdgeInsetsMake(8.0, 0.0, 0.0, 0.0);
        // Half a gap on each side keeps N slots plus N-1 gaps centered in the bar.
        CGFloat halfGap = self.buttonSpacing / 2.0;
        return UIEdgeInsetsMake(8.0, halfGap, 0.0, halfGap);
    }
    // Bottom bar insets are fixed (22pt top padding; the chrome spacing keeps
    // the tinted buttons clear of the dock's edge buttons).
    if ([self buttonChromeActive]){
        if (section == 0){
            return UIEdgeInsetsMake(22.0, 2*self.buttonSpacing, 0.0, 0.0);

        }
        return UIEdgeInsetsMake(22.0, self.buttonSpacing, 0.0, 0.0);

    }
    return UIEdgeInsetsMake(22.0, 0.0, 0.0, 0.0);
}

- (CGFloat)collectionView:(UICollectionView *)collectionView layout:(UICollectionViewLayout*)collectionViewLayout minimumLineSpacingForSectionAtIndex:(NSInteger)section{
    return [self buttonChromeActive]?self.buttonSpacing:0;
}

@end
