#import "common.h"
#import "TypeX.h"
#import "DXShared.h"
#import "DXToastWindowController.h"
#import "DXHelper.h"


id delegate;
UIKeyboardImpl *kbImpl;
UIColor *currentTintColor;
UIColor *toastTintColor;
UIColor *toastBackgroundTintColor;
UIColor *currentBackgroundTintColor;
BOOL isLandscape = NO;
NSMutableDictionary *prefs;
BOOL isDictating = NO;
BOOL toggledOn = YES;
UIKeyboardDockView *dockView;
//BOOL isSandboxed = NO;
CGPoint startPosition;
CGPoint endPosition;
NSDate *prevTime = nil;
BOOL singleTapDictationEnabled = NO;
BOOL singleTapGlobeEnabled = NO;
BOOL isTrackPadMode = NO;
BOOL isSpringBoard = YES;
BOOL isApplication = NO;
BOOL isSafari = NO;
KeyboardController *kbController;
BOOL shouldUpdateTrueKBType = NO;
BOOL shouldPerformBatchUpdate = YES;
//BOOL shouldSendScrollExecution = YES;
NSString *key;
BOOL isDraggedGesture = NO;
UIKeyboardDockView *dockV;
BOOL isPagingEnabled = YES;
BOOL useShortenedLabel = NO;
NSBundle *tweakBundle;
BOOL firstInit = YES;
DXStudlyCapsType spongebobEntropy;

float topInset = topInsetDefault;
float bottomInset = bottomInsetDefault;
float leftInset = leftInsetDefault;
float rightInset = rightInsetDefault;

float buttonRadius = cellsRadiusDefault;
float buttonHeight = cellsHeightDefault;
float buttonSpacing = spacingBetweenCellsDefault;

CGFloat leadingOffset = leadingOffsetDefault;
CGFloat trailingOffset = trailingOffsetDefault;
CGFloat heightOffset = heightOffsetDefault;
CGFloat bottomOffset = bottomOffsetDefault;

CGFloat leadingHBRightOffset = leadingOffsetHandBiasRightDefault;
CGFloat trailingHBRightOffset = trailingOffsetHandBiasRightDefault;

CGFloat leadingHBLeftOffset = leadingOffsetHandBiasLeftDefault;
CGFloat trailingHBLeftOffset = trailingOffsetHandBiasLeftDefault;

#pragma mark hook
%group TypeX
%hook UIKeyboardDockView
//%property (retain, nonatomic) UIKeyboardDockItemButton *leftDockButton;
//%property (retain, nonatomic) UIKeyboardDockItemButton *rightDockButton;
%property (retain, nonatomic) DXCollectionView *typex;

- (instancetype)initWithFrame:(CGRect)frame {
    dockView = %orig;
    if (preferencesBool(kEnabledkey,YES) && dockView) {
        self.typex = [[DXCollectionView alloc] init];
        
        //self.typex = [[DXCollectionView alloc] init];
        
        self.typex.translatesAutoresizingMaskIntoConstraints = NO;
        //self.typex.transform = CGAffineTransformMakeScale(-1, 1);
        
        [dockView addSubview:self.typex];
        
        float leading = leadingOffset;
        float trailing = trailingOffset;
        
        HBLogDebug(@"BEFORE leading: %f, trailing: %f",leading, trailing );
        
        switch (preferencesInt(kDockModekey, 0)){
            case 1:
                if (fabs(leading - leadingOffsetDefault) > 0.5f) break;
                leading = 5.0f;
                break;
            case 2:
                if (fabs(trailing - trailingOffsetDefault) > 0.5f) break;
                trailing = -5.0f;
                break;
            case 3:
                if (fabs(leading - leadingOffsetDefault) > 0.5f){
                }else{
                    leading = 5.0f;
                }
                if (fabs(trailing - trailingOffsetDefault) > 0.5f){
                }else{
                    trailing = -5.0f;
                }
                break;
        }
        if ([dockView respondsToSelector:@selector(barmoji)] && leading < leadingOffsetDefault) {
            leading = leadingOffsetDefault;
        }
        
        
        HBLogDebug(@"AFTER leading: %f, trailing: %f",leading, trailing );
        
        NSLayoutConstraint *leadingConstraint = [NSLayoutConstraint constraintWithItem:self.typex attribute:NSLayoutAttributeLeading relatedBy:NSLayoutRelationEqual toItem:dockView attribute:NSLayoutAttributeLeading multiplier:1.0 constant:leading];
        leadingConstraint.identifier = @"TypeX";
        [dockView addConstraint:leadingConstraint];
        
        NSLayoutConstraint *trailingConstraint = [NSLayoutConstraint constraintWithItem:self.typex attribute:NSLayoutAttributeTrailing relatedBy:NSLayoutRelationEqual toItem:dockView attribute:NSLayoutAttributeTrailing multiplier:1.0 constant:trailing];
        trailingConstraint.identifier = @"TypeX";
        [dockView addConstraint:trailingConstraint];
        
        NSLayoutConstraint *heightConstraint = [NSLayoutConstraint constraintWithItem:self.typex attribute:NSLayoutAttributeHeight relatedBy:NSLayoutRelationEqual toItem:nil attribute:NSLayoutAttributeNotAnAttribute multiplier:1.0 constant:heightOffset];
        heightConstraint.identifier = @"TypeX";
        [dockView addConstraint:heightConstraint];
        
        NSLayoutConstraint *bottomConstraint = [NSLayoutConstraint constraintWithItem:self.typex attribute:NSLayoutAttributeBottom relatedBy:NSLayoutRelationEqual toItem:dockView attribute:NSLayoutAttributeBottom multiplier:1.0 constant:bottomOffset];
        bottomConstraint.identifier = @"TypeX";
        [dockView addConstraint:bottomConstraint];
        
        dispatch_async(dispatch_get_main_queue(), ^{
            
            kbImpl = [objc_getClass("UIKeyboardImpl") activeInstance];
            delegate = DXKeyboardInputDelegate(kbImpl);
            if ([delegate respondsToSelector:@selector(keyboardType)]){
                if (shouldUpdateTrueKBType){
                    self.typex.trueKBType = [[NSNumber numberWithInt:[delegate keyboardType]] intValue];
                    shouldUpdateTrueKBType = NO;
                }
                NSUInteger index = [self.typex.kbType indexOfObject:[NSNumber numberWithInt:[delegate keyboardType]]];
                //HBLogDebug(@"indexXXXXX: %lu", index);
                if (index == NSNotFound){
                    //HBLogDebug(@"INDEXOF: %@", [NSNumber numberWithInt:[delegate keyboardType]]);
                    NSMutableArray *kbTypeMutable = [self.typex.kbType mutableCopy];
                    NSMutableArray *kbTypeLabelMutable = [self.typex.kbTypeLabel mutableCopy];
                    
                    NSUInteger indexInArray = [self.typex.keyboardTypeDataFull indexOfObject:[NSNumber numberWithInt:[delegate keyboardType]]];
                    if (index == NSNotFound){
                        if ([delegate keyboardType] > 12){
                            self.typex.trueKBType = 0;
                            shouldUpdateTrueKBType = NO;
                        }else{
                            [kbTypeMutable insertObject:[NSNumber numberWithInt:[delegate keyboardType]] atIndex:0];
                            if (indexInArray != NSNotFound){
                                [kbTypeLabelMutable insertObject:self.typex.keyboardTypeLabelFull[indexInArray] atIndex:0];
                            }else{
                                [kbTypeLabelMutable insertObject:LOCALIZED(@"TOAST_KEYBOARD_TYPE_GENERIC") atIndex:0];
                            }
                        }
                    }else{
                        [kbTypeMutable insertObject:self.typex.keyboardTypeDataFull[indexInArray] atIndex:0];
                        [kbTypeLabelMutable insertObject:self.typex.keyboardTypeLabelFull[indexInArray] atIndex:0];
                    }
                    self.typex.kbTypeLabel = kbTypeLabelMutable;
                    self.typex.kbType = kbTypeMutable;
                    
                }else{
                    self.typex.trueKBType = 0;
                    shouldUpdateTrueKBType = NO;
                }
            }else{
                UIImage *image;
                NSMutableAttributedString *imageOfName = [[NSMutableAttributedString alloc] initWithString:@""];
                
                NSMutableAttributedString *attributeString = [[NSMutableAttributedString alloc] initWithString:@"Input"];
                NSMutableAttributedString *strikedAttributeString = [attributeString mutableCopy];
                [strikedAttributeString addAttribute:NSStrikethroughStyleAttributeName value:@2 range:NSMakeRange(0, [attributeString length])];
                
                if (@available(iOS 13.0, *)){
                    imageOfName = useShortenedLabel ? [delegate respondsToSelector:@selector(keyboardType)]?attributeString:strikedAttributeString : [delegate respondsToSelector:@selector(keyboardType)]?[@"number.circle.fill" attributedString]:[@"number.circle" attributedString];
                    if (!useShortenedLabel) image = [DXHelper imageForName:imageOfName.string  withSystemColor:NO completion:nil];
                }else{
                    imageOfName =  useShortenedLabel ? [delegate respondsToSelector:@selector(keyboardType)]?attributeString:strikedAttributeString : [delegate respondsToSelector:@selector(keyboardType)]?[@"reachable_full" attributedString]:[@"dictation_keyboard_dark" attributedString];
                    if (!useShortenedLabel) image = [DXHelper imageForName:imageOfName.string  withSystemColor:NO completion:nil];
                }
                if (useShortenedLabel){
                    [self.typex.keyboardInputTypeCell.btn setImage:nil forState:UIControlStateNormal];
                    [self.typex.keyboardInputTypeCell.btn setAttributedTitle:imageOfName forState:UIControlStateNormal];
                }else{
                    [self.typex.keyboardInputTypeCell.btn setAttributedTitle:nil forState:UIControlStateNormal];
                    [self.typex.keyboardInputTypeCell.btn setImage:image forState:UIControlStateNormal];
                }
            }
            
            
            [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(handBiasChanged) name:@"handBiasChanged" object:nil];
            [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(toggleTypeX:) name:@"toggleTypeX" object:nil];
            
            [self handBiasChanged];
        });
        
    }
    if (![self respondsToSelector:@selector(barmoji)]){
        self.typex.hidden = YES;
        toggledOn = YES;
    }else{
        if (toggledOn){
            self.typex.hidden = NO;
        }else{
            self.typex.hidden = YES;
        }
    }
    
    
    return dockV = dockView;
}

%new
- (void)performTypeXToggling:(UILongPressGestureRecognizer*)gesture{
    if (gesture.state == UIGestureRecognizerStateBegan){
        [[NSNotificationCenter defaultCenter] postNotificationName:@"toggleTypeX" object:nil];
    }
}

%new
- (void)performTypeXTogglingTap:(UITapGestureRecognizer*)gesture{
    //if (gesture.state == UIGestureRecognizerStateBegan){
    [[NSNotificationCenter defaultCenter] postNotificationName:@"toggleTypeX" object:nil];
    //}
}


- (void)setLeftDockItem:(UIKeyboardDockItem *)dockItem {
    if (preferencesBool(kEnabledkey,YES)){
        if (!preferencesBool(kColorEnabledkey,NO) || (preferencesBool(kColorEnabledkey,NO)  && !preferencesBool(kShortcutsTintEnabled,YES))){
            currentTintColor = dockItem.button.tintColor;
        }
        if (preferencesInt(kDedicatedGestureButtonkey, 0) == 1 || preferencesInt(kDedicatedGestureButtonkey, 0) == 3){
            if (preferencesInt(kDockModekey, 0) != 1 && preferencesInt(kDockModekey, 0) != 3) {
                %orig;
            }
            if ([dockView respondsToSelector:@selector(barmoji)] && preferencesInt(kDockModekey, 0) != 1 && preferencesInt(kDockModekey, 0) != 3){
                if (preferencesInt(kGestureTypekey,0) == 1){
                    singleTapGlobeEnabled = NO;
                    UILongPressGestureRecognizer *longPress = [[UILongPressGestureRecognizer alloc] initWithTarget:self action:@selector(performTypeXToggling:)];
                    longPress.minimumPressDuration = 0.3;
                    [dockItem.button addGestureRecognizer:longPress];
                }else{
                    singleTapGlobeEnabled = YES;
                    [dockItem.button removeTarget:nil action:NULL forControlEvents:UIControlEventAllEvents];
                    UITapGestureRecognizer *singleTap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(performTypeXTogglingTap:)];
                    singleTap.numberOfTapsRequired = 1;
                    [dockItem.button addGestureRecognizer:singleTap];
                }
                return;
            }
        }
    }
    %orig;
    //self.leftDockButton = dockItem.button;
    /*
     UILongPressGestureRecognizer *longPress = [[UILongPressGestureRecognizer alloc] initWithTarget:self action:@selector(performOriginalLeftDockAction:)];
     longPress.minimumPressDuration = 0.5;
     
     //UITapGestureRecognizer *singleTap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(performTypeXToggling:)];
     //singleTap.numberOfTapsRequired = 1;
     
     [dockItem.button addGestureRecognizer:longPress];
     //[dockItem.button addGestureRecognizer:singleTap];
     %orig;
     [dockItem.button removeTarget:nil action:NULL forControlEvents:UIControlEventAllEvents];
     [dockItem.button addTarget:self action:@selector(performTypeXToggling:) forControlEvents:UIControlEventTouchUpInside];
     */
}
- (void)setRightDockItem:(UIKeyboardDockItem *)dockItem {
    if (preferencesBool(kEnabledkey,YES)){
        if (!preferencesBool(kColorEnabledkey,NO) || (preferencesBool(kColorEnabledkey,NO)  && !preferencesBool(kShortcutsTintEnabled,YES))){
            currentTintColor = dockItem.button.tintColor;
        }
        if (preferencesInt(kDockModekey, 0) == 2 || preferencesInt(kDockModekey, 0) == 3) return;
        if (preferencesInt(kDedicatedGestureButtonkey, 0) == 2 || preferencesInt(kDedicatedGestureButtonkey, 0) == 3){
            %orig;
            if ([dockView respondsToSelector:@selector(barmoji)]){
                if (preferencesInt(kGestureTypekey,0) == 1){
                    singleTapDictationEnabled = NO;
                    UILongPressGestureRecognizer *longPress = [[UILongPressGestureRecognizer alloc] initWithTarget:self action:@selector(performTypeXToggling:)];
                    longPress.minimumPressDuration = 0.3;
                    [dockItem.button addGestureRecognizer:longPress];
                }else{
                    singleTapDictationEnabled = YES;
                    [dockItem.button removeTarget:nil action:NULL forControlEvents:UIControlEventAllEvents];
                    UITapGestureRecognizer *singleTap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(performTypeXTogglingTap:)];
                    singleTap.numberOfTapsRequired = 1;
                    [dockItem.button addGestureRecognizer:singleTap];
                }
            }
            return;
        }
    }
    %orig;
    /*
     NSData *archivedData = [NSKeyedArchiver archivedDataWithRootObject: dockItem.button];
     self.rightDockButton = [NSKeyedUnarchiver unarchiveObjectWithData: archivedData];
     
     UILongPressGestureRecognizer *longPress = [[UILongPressGestureRecognizer alloc] initWithTarget:self action:@selector(performOriginalRightDockAction:)];
     longPress.minimumPressDuration = 0.5;
     
     UITapGestureRecognizer *singleTap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(performTypeXToggling:)];
     singleTap.numberOfTapsRequired = 1;
     
     [dockItem.button addGestureRecognizer:longPress];
     [dockItem.button addGestureRecognizer:singleTap];
     %orig;
     
     [dockItem.button removeTarget:nil action:NULL forControlEvents:UIControlEventAllEvents];
     */
}

%new
-(void)toggleTypeX:(NSNotification*)notification{
    if (preferencesBool(kEnabledHaptickey,YES)){
        [[[UIImpactFeedbackGenerator alloc] initWithStyle:UIImpactFeedbackStyleLight] impactOccurred];
    }
    //self.barmoji.hidden = !self.typex.hidden;
    toggledOn = self.typex.hidden;
    [[DXPrefsManager sharedInstance] setValue:[NSNumber numberWithBool:toggledOn] forKey:kToggledOnkey fromSandbox:!isSpringBoard];
    //dockView.barmoji.hidden = !self.hidden;
    /*
     if (isApplication){
     [[DXPrefsManager sharedInstance] setValue:[NSNumber numberWithBool:toggledOn] forKey:kToggledOnkey fromSandbox:isApplication];
     CPDistributedMessagingCenter *c = [CPDistributedMessagingCenter centerNamed:@"com.lindo.typex.server"];
     [c sendMessageAndReceiveReplyName:@"typeXSaveValue" userInfo:@{@"key":kToggledOnkey, @"value":[NSNumber numberWithBool:toggledOn]}];
     }else{
     CFPreferencesSetAppValue((CFStringRef)kToggledOnkey, (CFPropertyListRef)[NSNumber numberWithBool:toggledOn], (CFStringRef)kIdentifier);
     CFPreferencesAppSynchronize((CFStringRef)kIdentifier);
     }
     */
    CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(), (CFStringRef)kPrefsChangedIdentifier, NULL, NULL, YES);
    
    if (self.typex.hidden){
        self.barmoji.hidden = YES;
        self.typex.hidden = NO;
        
        if (@available(iOS 14.0, *)){
            self.typex.alpha = 0.0f;
            [UIView animateWithDuration:0.3f animations:^{
                self.typex.alpha = 1.0f;
            } completion:^(BOOL finished) {
            }];
        }else{
            self.typex.transform = CGAffineTransformScale(CGAffineTransformIdentity, 0.001, 0.001);
            [UIView animateWithDuration:0.3/4 animations:^{
                self.typex.transform = CGAffineTransformScale(CGAffineTransformIdentity, 1.0, 1.0);
            } completion:^(BOOL finished) {
                [UIView animateWithDuration:0.3/4 animations:^{
                    self.typex.transform = CGAffineTransformScale(CGAffineTransformIdentity, 0.9, 0.9);
                } completion:^(BOOL finished) {
                    [UIView animateWithDuration:0.3/4 animations:^{
                        self.typex.transform = CGAffineTransformIdentity;
                    }];
                }];
            }];
        }
    }else{
        self.typex.hidden = YES;
        self.barmoji.hidden = NO;
        
        if (@available(iOS 14.0, *)){
            self.barmoji.alpha = 0.0f;
            [UIView animateWithDuration:0.3f animations:^{
                self.barmoji.alpha = 1.0f;
            } completion:^(BOOL finished) {
            }];
        }else{
            self.barmoji.transform = CGAffineTransformScale(CGAffineTransformIdentity, 0.001, 0.001);
            [UIView animateWithDuration:0.3/4 animations:^{
                self.barmoji.transform = CGAffineTransformScale(CGAffineTransformIdentity, 1.0, 1.0);
            } completion:^(BOOL finished) {
                [UIView animateWithDuration:0.3/4 animations:^{
                    self.barmoji.transform = CGAffineTransformScale(CGAffineTransformIdentity, 0.9, 0.9);
                } completion:^(BOOL finished) {
                    [UIView animateWithDuration:0.3/4 animations:^{
                        self.barmoji.transform = CGAffineTransformIdentity;
                    }];
                }];
            }];
        }
    }
    [self layoutSubviews];
    
}

%new
-(void)handBiasChanged{
    UIKeyboardPreferencesController *kbPrefsController = [%c(UIKeyboardPreferencesController) sharedPreferencesController];
    if (kbPrefsController){
        int constraintsAdjust = 0;
        long long currentHandBias = kbPrefsController.handBias;
        
        float leading = leadingOffset;
        float trailing = trailingOffset;
        HBLogDebug(@"HANDBIAS BEFORE leading: %f, trailing: %f",leading, trailing );
        HBLogDebug(@"fabs(leading - leadingOffsetDefault): %f", fabs(leading - leadingOffsetDefault));
        HBLogDebug(@"fabs(trailing - trailingOffsetDefault): %f", fabs(trailing - trailingOffsetDefault));
        if (currentHandBias == 0){
            switch (preferencesInt(kDockModekey, 0)){
                case 1:
                    if (fabs(leading - leadingOffsetDefault) > 0.5f) break;
                    leading = 5.0f;
                    break;
                case 2:
                    if (fabs(trailing - trailingOffsetDefault) > 0.5f) break;
                    trailing = -5.0f;
                    break;
                case 3:
                    if (fabs(leading - leadingOffsetDefault) > 0.5f){
                    }else{
                        leading = 5.0f;
                    }
                    if (fabs(trailing - trailingOffsetDefault) > 0.5f){
                    }else{
                        trailing = -5.0f;
                    }
                    break;
            }
        }else if (currentHandBias == 1){
            leading = leadingHBRightOffset;
            trailing = trailingHBRightOffset;
            switch (preferencesInt(kDockModekey, 0)){
                case 1:
                    leading = 50;
                    break;
                case 2:
                    trailing = -5;
                    break;
                case 3:
                    leading = 50;
                    trailing = -5;
                    break;
            }
        }else if (currentHandBias == 2){
            leading = leadingHBLeftOffset;
            trailing = trailingHBLeftOffset;
            switch (preferencesInt(kDockModekey, 0)){
                case 1:
                    leading = 5;
                    break;
                case 2:
                    trailing = -45;
                    break;
                case 3:
                    leading = 5;
                    trailing = -45;
                    break;
            }
        }
        if ([self respondsToSelector:@selector(barmoji)] && leading < leadingOffsetDefault) {
            leading = leadingOffsetDefault;
        }
        HBLogDebug(@"HANDBIAS AFTER leading: %f, trailing: %f",leading, trailing );
        
        //HBLogDebug(@"received handbiaschangednotification: %lld", currentHandBias);
        //if (currentHandBias == 0){
        for (NSLayoutConstraint *constraint in self.constraints) {
            if (constraint.firstAttribute == NSLayoutAttributeLeading && [constraint.identifier isEqualToString:@"TypeX"]) {
                [self removeConstraint:constraint];
                
                NSLayoutConstraint *leadingConstraint = [NSLayoutConstraint constraintWithItem:self.typex attribute:NSLayoutAttributeLeading relatedBy:NSLayoutRelationEqual toItem:self attribute:NSLayoutAttributeLeading multiplier:1.0 constant:leading];
                leadingConstraint.identifier = @"TypeX";
                [self addConstraint:leadingConstraint];
                constraintsAdjust = constraintsAdjust +1;
            }else if (constraint.firstAttribute == NSLayoutAttributeTrailing && [constraint.identifier isEqualToString:@"TypeX"]) {
                [self removeConstraint:constraint];
                NSLayoutConstraint *trailingConstraint = [NSLayoutConstraint constraintWithItem:self.typex attribute:NSLayoutAttributeTrailing relatedBy:NSLayoutRelationEqual toItem:self attribute:NSLayoutAttributeTrailing multiplier:1.0 constant:trailing];
                trailingConstraint.identifier = @"TypeX";
                [self addConstraint:trailingConstraint];
                constraintsAdjust = constraintsAdjust +1;
            }
            if (constraintsAdjust == 2){
                break;
            }
            //self.typex.pagingEnabled = YES;
        }
        /*
         }else if (currentHandBias == 1 ){
         for (NSLayoutConstraint *constraint in self.constraints) {
         if (constraint.firstAttribute == NSLayoutAttributeLeading && [constraint.identifier isEqualToString:@"TypeX"]) {
         [self removeConstraint:constraint];
         [self addConstraint:[NSLayoutConstraint constraintWithItem:self.typex attribute:NSLayoutAttributeLeading relatedBy:NSLayoutRelationEqual toItem:self attribute:NSLayoutAttributeLeading multiplier:1.0 constant:leading]];
         constraintsAdjust = constraintsAdjust +1;
         }else if (constraint.firstAttribute == NSLayoutAttributeTrailing && [constraint.identifier isEqualToString:@"TypeX"]) {
         [self removeConstraint:constraint];
         //[self addConstraint:[NSLayoutConstraint constraintWithItem:self.typex attribute:NSLayoutAttributeTrailing relatedBy:NSLayoutRelationEqual toItem:self attribute:NSLayoutAttributeTrailing multiplier:1.0 constant:((NSArray *)self.typex.shortcuts[kbuttonsImages12]).count>5?-19:-60]];
         [self addConstraint:[NSLayoutConstraint constraintWithItem:self.typex attribute:NSLayoutAttributeTrailing relatedBy:NSLayoutRelationEqual toItem:self attribute:NSLayoutAttributeTrailing multiplier:1.0 constant:trailing]];
         
         constraintsAdjust = constraintsAdjust +1;
         }
         if (constraintsAdjust == 2){
         break;
         }
         }}else if (currentHandBias == 2 ){
         for (NSLayoutConstraint *constraint in self.constraints) {
         if (constraint.firstAttribute == NSLayoutAttributeLeading && [constraint.identifier isEqualToString:@"TypeX"]) {
         [self removeConstraint:constraint];
         [self addConstraint:[NSLayoutConstraint constraintWithItem:self.typex attribute:NSLayoutAttributeLeading relatedBy:NSLayoutRelationEqual toItem:self attribute:NSLayoutAttributeLeading multiplier:1.0 constant:leading]];
         constraintsAdjust = constraintsAdjust +1;
         }else if (constraint.firstAttribute == NSLayoutAttributeTrailing && [constraint.identifier isEqualToString:@"TypeX"]) {
         [self removeConstraint:constraint];
         //[self addConstraint:[NSLayoutConstraint constraintWithItem:self.typex attribute:NSLayoutAttributeTrailing relatedBy:NSLayoutRelationEqual toItem:self attribute:NSLayoutAttributeTrailing multiplier:1.0 constant:((NSArray *)self.typex.shortcuts[kbuttonsImages12]).count>5?-60:-95]];
         [self addConstraint:[NSLayoutConstraint constraintWithItem:self.typex attribute:NSLayoutAttributeTrailing relatedBy:NSLayoutRelationEqual toItem:self attribute:NSLayoutAttributeTrailing multiplier:1.0 constant:trailing]];
         
         constraintsAdjust = constraintsAdjust +1;
         }
         if (constraintsAdjust == 2){
         break;
         }
         }}
         */
        
    }else{
        //self.pagingEnabled = NO;
        //return _buttons.count;
    }
    [[NSNotificationCenter defaultCenter] postNotificationName:@"typeXLayoutChanged" object:nil userInfo:@{@"fullreload":@YES}];
    //NSNotification * note = [NSNotification notificationWithName:@"typeXLayoutChanged" object:nil userInfo:@{@"fullreload":@YES}];
    //[[NSNotificationQueue defaultQueue] enqueueNotification:note postingStyle:NSPostASAP coalesceMask:NSNotificationCoalescingOnName forModes:nil];
    
    
}

/*
 %new
 -(void)updateTypeXTint{
 if (self.leftDockItem.button){
 currentTintColor = self.leftDockItem.button.tintColor;
 }else if (self.rightDockItem.button){
 currentTintColor = self.rightDockItem.button.tintColor;
 }else{
 if (@available(iOS 13.0, *)){
 if ([UITraitCollection currentTraitCollection].userInterfaceStyle == UIUserInterfaceStyleDark) {
 currentTintColor = [UIColor whiteColor];
 }else{
 currentTintColor = [UIColor blackColor];
 }
 }else{
 
 }
 }
 }
 */

- (void)layoutSubviews{
    %orig;
    //HBLogDebug(@"isDictating %d, isLandscape: %d", isDictating?1:0, isLandscape?1:0);
    if (preferencesBool(kEnabledkey,YES)){
        //HBLogDebug(@"toggledOn %d", toggledOn?1:0);
        if (toggledOn){
            if ([self respondsToSelector:@selector(barmoji)]) self.barmoji.hidden = YES;
            
            //NSTimeInterval timeInterval = fabs([lastReloadDate timeIntervalSinceNow]);
            //if (lastReloadDate && timeInterval < 0.5f ) lastReloadDate = [NSDate date]; return;
            //if (!self.typex) return;
            if (isDictating || isLandscape){
                //HBLogDebug(@"Should Hide");
                self.typex.hidden = YES;
                return;
                
                //if (!preferencesBool(kColorEnabledkey,NO)){
                //[self updateTypeXTint];
                //}
                //NSNotification * note = [NSNotification notificationWithName:@"typeXLayoutChanged" object:nil];
                //[[NSNotificationQueue defaultQueue] enqueueNotification:note postingStyle:NSPostASAP coalesceMask:NSNotificationCoalescingOnName forModes:nil];
            }else{
                //HBLogDebug(@"Shouldn't Hide");
                
                self.typex.hidden = NO;
                [[NSNotificationCenter defaultCenter] postNotificationName:@"typeXLayoutChanged" object:nil];
                
            }
            //lastReloadDate = [NSDate date];
        }else{
            self.typex.hidden = YES;
            self.barmoji.hidden = NO;
        }
        
        
        if (self.typex.keyboardInputTypeCell){
            //dispatch_async(dispatch_get_main_queue(), ^{
            
            //if (![[self.typex visibleCells] containsObject:self.typex.keyboardInputTypeCell]) return;
            
            kbImpl = [objc_getClass("UIKeyboardImpl") activeInstance];
            delegate = DXKeyboardInputDelegate(kbImpl);
            
            UIImage *image;
            NSMutableAttributedString *imageOfName = [[NSMutableAttributedString alloc] initWithString:@""];
            
            NSMutableAttributedString *attributeString = [[NSMutableAttributedString alloc] initWithString:@"Input"];
            NSMutableAttributedString *strikedAttributeString = [attributeString mutableCopy];
            [strikedAttributeString addAttribute:NSStrikethroughStyleAttributeName value:@2 range:NSMakeRange(0, [attributeString length])];
            
            if (@available(iOS 13.0, *)){
                imageOfName = useShortenedLabel ? ([delegate respondsToSelector:@selector(keyboardType)]?attributeString:strikedAttributeString) : ([delegate respondsToSelector:@selector(keyboardType)]?[@"number.circle.fill" attributedString]:[@"number.circle" attributedString]);
                if (!useShortenedLabel) image = [DXHelper imageForName:imageOfName.string  withSystemColor:NO completion:nil];
            }else{
                imageOfName = useShortenedLabel ? ([delegate respondsToSelector:@selector(keyboardType)]?attributeString:strikedAttributeString) : ([delegate respondsToSelector:@selector(keyboardType)]?[@"reachable_full" attributedString]:[@"dictation_keyboard_dark" attributedString]);
                if (!useShortenedLabel) image = [DXHelper imageForName:imageOfName.string  withSystemColor:NO completion:nil];
            }
            
            if (useShortenedLabel){
                [self.typex.keyboardInputTypeCell.btn setImage:nil forState:UIControlStateNormal];
                [self.typex.keyboardInputTypeCell.btn setAttributedTitle:imageOfName forState:UIControlStateNormal];
            }else{
                [self.typex.keyboardInputTypeCell.btn setAttributedTitle:nil forState:UIControlStateNormal];
                [self.typex.keyboardInputTypeCell.btn setImage:image forState:UIControlStateNormal];
                
            }
            
            //});
        }
        
    }else{
        // The dock view is not recreated when the main preference is disabled.
        // Explicitly restore the stock bar on iOS 17.
        self.typex.hidden = YES;
        if ([self respondsToSelector:@selector(barmoji)]) self.barmoji.hidden = NO;
    }
}
/*
 %new
 -(void)shouldUpdateLayoutWithDelay:(float)delay{
 
 double delayInSeconds = delay;
 dispatch_time_t popTime = dispatch_time(DISPATCH_TIME_NOW, delayInSeconds * NSEC_PER_SEC);
 dispatch_after(popTime, dispatch_get_main_queue(), ^(void){
 shouldUpdateLayout = YES;
 
 });
 }
 */
//-(void)setLeftDockItem:(UIKeyboardDockItem *)leftDock{
//%orig;
//currentTintColor = leftDock.button.tintColor;
//[[NSNotificationCenter defaultCenter] postNotificationName:@"typeXLayoutChanged" object:nil];
//}
/*
 - (void)touchesEnded:(NSSet *)touches withEvent:(UIEvent *)event{
 %orig;
 if (preferencesBool(kEnabledkey,YES) && self.typex.cursorTimer){
 [self.typex.cursorTimer invalidate];
 self.typex.cursorTimer = nil;
 }
 }
 */
%end

%hook UIKeyboardDockItem
//iOS 13+
-(void)setImageName:(NSString *)imageName{
    //HBLogDebug(@"singleTapDictationEnabled: %d, singleTapGlobeEnabled: %d", singleTapDictationEnabled?1:0, singleTapGlobeEnabled?1:0);
    if (([imageName isEqualToString:@"mic"] && singleTapDictationEnabled) || ([imageName isEqualToString:@"globe"] && singleTapGlobeEnabled)){
        %orig(@"circle");
        return;
    }
    %orig;
}

//iOS 12
-(id)initWithImageName:(id)imageName identifier:(id)identifier{
    //HBLogDebug(@"imageName: %@, identifier: %@", imageName, identifier);
    if (@available(iOS 13.0, *)){
    }else{
        if ([identifier isEqualToString:@"dictation"] && singleTapDictationEnabled){
            return %orig(@"UIDownloadProgressBorderThick", identifier);
        }else if ([identifier isEqualToString:@"globe"] && singleTapGlobeEnabled){
            return %orig(@"UIDownloadProgressBorderThick", identifier);
        }
    }
    return %orig;
}
%end

%hook UIDictationController
-(void)switchToDictationInputMode{
    %orig;
    isDictating = YES;
    //HBLogDebug(@"switchToDictationInputMode");
}

-(void)switchToDictationInputModeWithTouch:(id)arg1{
    %orig;
    isDictating = YES;
    //HBLogDebug(@"switchToDictationInputModeWithTouch");
    
}

-(void)stopDictation:(BOOL)arg1{
    %orig;
    if (arg1){
        isDictating = NO;
    }
    //HBLogDebug(@"stopDictation: %@", arg1?@"YES":@"NO");
    
}


%end

%hook UIKeyboardPreferencesController
-(void)setHandBias:(long long)arg1{ //0 -normal,2-left, 1-right
    %orig;
    if (preferencesBool(kEnabledkey,YES)){
        [[NSNotificationCenter defaultCenter] postNotificationName:@"handBiasChanged" object:nil];
    }
    
}

%end

//sstatic BOOL forceHidden = NO;


%hook _UIKeyboardTextSelectionInteraction
-(BOOL)gestureRecognizerShouldBegin:(UIGestureRecognizer *)recognizer{
    //HBLogDebug(@"GESTURE: %@", recognizer);
    if (preferencesBool(kEnabledkey,YES) && [NSStringFromClass([recognizer.view class]) isEqualToString:@"UIKeyboardDockView"]){
        return NO;
    }
    return %orig;
}
%end

%hook UIKeyboardLayoutStar
%property (retain, nonatomic) DXCollectionView *typexTop;

-(BOOL)isHandwritingPlane{
    BOOL isHWR = %orig;
    if (preferencesBool(kEnabledkey,YES) && preferencesBool(kSpaceBarScrollingBOOL,YES)){
        UISwipeGestureRecognizer *leftRecognizer = [self valueForKey:@"_leftSwipeRecognizer"];
        UISwipeGestureRecognizer *rightRecognizer = [self valueForKey:@"_rightSwipeRecognizer"];
        if (isHWR){
            leftRecognizer.enabled = NO;
            rightRecognizer.enabled = NO;
        }else{
            leftRecognizer.enabled = YES;
            rightRecognizer.enabled = YES;
        }
    }
    return isHWR;
}

-(id)initWithFrame:(CGRect)arg1{
    self = %orig;

    if (preferencesBool(kEnabledkey,YES) && self) {
        self.clipsToBounds = NO;
        self.typexTop = [[DXCollectionView alloc] init];
        self.typexTop.configuration = @"top";
        [self.typexTop reloadShortcutConfiguration];
        self.typexTop.translatesAutoresizingMaskIntoConstraints = NO;
        self.typexTop.clipsToBounds = NO;
        [self addSubview:self.typexTop];
        [NSLayoutConstraint activateConstraints:@[
            [self.typexTop.leadingAnchor constraintEqualToAnchor:self.leadingAnchor],
            [self.typexTop.trailingAnchor constraintEqualToAnchor:self.trailingAnchor],
            [self.typexTop.bottomAnchor constraintEqualToAnchor:self.topAnchor constant:-2.0],
            [self.typexTop.heightAnchor constraintEqualToConstant:MAX(44.0, buttonHeight + topInset + bottomInset + 4.0)]
        ]];
        self.typexTop.hidden = (self.typexTop.shortcuts.count == 0 || ((NSArray *)self.typexTop.shortcuts[kbuttonsImages12]).count == 0);
    }
    
    if (preferencesBool(kEnabledkey,YES) && preferencesBool(kSpaceBarScrollingBOOL,YES)){
        UISwipeGestureRecognizer *leftRecognizer = [[UISwipeGestureRecognizer alloc] initWithTarget:self action:@selector(leftSwipeHandle:)];
        leftRecognizer.direction = UISwipeGestureRecognizerDirectionLeft;
        [leftRecognizer setNumberOfTouchesRequired:1];
        [self setValue:leftRecognizer forKey:@"_leftSwipeRecognizer"];
        [self addGestureRecognizer:leftRecognizer];
        
        UISwipeGestureRecognizer *rightRecognizer = [[UISwipeGestureRecognizer alloc] initWithTarget:self action:@selector(rightSwipeHandle:)];
        rightRecognizer.direction = UISwipeGestureRecognizerDirectionRight;
        [rightRecognizer setNumberOfTouchesRequired:1];
        [self setValue:rightRecognizer forKey:@"_rightSwipeRecognizer"];
        [self addGestureRecognizer:rightRecognizer];
        
        //UISwipeGestureRecognizer *upRecognizer = [[UISwipeGestureRecognizer alloc] initWithTarget:self action:@selector(upSwipeHandle:)];
        //upRecognizer.direction = UISwipeGestureRecognizerDirectionUp;
        //[upRecognizer setNumberOfTouchesRequired:1];
        //[self setValue:upRecognizer forKey:@"_upSwipeRecognizer"];
        //[self addGestureRecognizer:upRecognizer];
        
    }
    return self;
}

-(void)layoutSubviews {
    %orig;
    if (self.typexTop) {
        BOOL shouldHide = !preferencesBool(kEnabledkey, YES) || !toggledOn || isLandscape || isDictating;
        if (((NSArray *)self.typexTop.shortcuts[kbuttonsImages12]).count == 0) shouldHide = YES;
        self.typexTop.hidden = shouldHide;
    }
}

%new
- (void)leftSwipeHandle:(UISwipeGestureRecognizer*)recognizer
{
    //HBLogDebug(@"leftSwipeHandle");
    //if (recognizer.state == UIGestureRecognizerStateBegan) {
    //NSString *key = [[[self keyHitTest:[recognizer locationInView:recognizer.view]] representedString] lowercaseString];
    //if ([key isEqualToString:@" "]){
    if (!dockView.typex.hidden){
        kbImpl = [%c(UIKeyboardImpl) activeInstance];
        delegate = DXKeyboardInputDelegate(kbImpl);
        [kbImpl clearInputWithCandidatesCleared:YES];
        if ([self respondsToSelector:@selector(clearContinuousPathView)]){
            [self clearContinuousPathView];
        }
        [[NSNotificationCenter defaultCenter] postNotificationName:@"scrollForward" object:nil];
    }
    //}
    //}else if (recognizer.state == UIGestureRecognizerStateEnded){
    //}
}

%new
- (void)rightSwipeHandle:(UISwipeGestureRecognizer*)recognizer
{
    //HBLogDebug(@"rightSwipeHandle");
    //if (recognizer.state == UIGestureRecognizerStateBegan) {
    //NSString *key = [[[self keyHitTest:[recognizer locationInView:recognizer.view]] representedString] lowercaseString];
    //if ([key isEqualToString:@" "]){
    if (!dockView.typex.hidden){
        kbImpl = [%c(UIKeyboardImpl) activeInstance];
        delegate = DXKeyboardInputDelegate(kbImpl);
        [kbImpl clearInputWithCandidatesCleared:YES];
        if ([self respondsToSelector:@selector(clearContinuousPathView)]){
            [self clearContinuousPathView];
        }
        [[NSNotificationCenter defaultCenter] postNotificationName:@"scrollBackward" object:nil];
    }
    //}
    //}else if (recognizer.state == UIGestureRecognizerStateEnded){
    //}
}

/*
 %new
 - (void)upSwipeHandle:(UISwipeGestureRecognizer*)recognizer
 {
 HBLogDebug(@"upSwipeHandle");
 //if (recognizer.state == UIGestureRecognizerStateBegan) {
 //NSString *key = [[[self keyHitTest:[recognizer locationInView:recognizer.view]] representedString] lowercaseString];
 //if ([key isEqualToString:@" "]){
 dockView.typex.hidden = !dockView.typex.hidden;
 
 //}
 //}else if (recognizer.state == UIGestureRecognizerStateEnded){
 //}
 }
 */


- (void)touchesBegan:(NSSet *)touches withEvent:(UIEvent *)event {
    if (preferencesBool(kEnabledkey,YES) && (preferencesInt(kSwipeSpaceBarTogglekey,0) < 1)){
        prevTime = [NSDate date] ;
        UITouch *touch = [[touches allObjects] firstObject];
        startPosition = [touch locationInView:touch.view];
        key = [[[self keyHitTest:[touch locationInView:touch.view]] representedString] lowercaseString];
        //HBLogDebug(@"touchesBegan EVENT: %ld", event.type);
        //NSString *key = [[[self hitTest:[touch locationInView:touch.view] withEvent:event] representedString] lowercaseString];
        //if ([key isEqualToString:@" "]){
        // return;
        //}
    }
    %orig;
    
}

%new
-(direction)computeDirectionFromTouches {
    NSInteger xDisplacement = endPosition.x-startPosition.x;
    NSInteger yDisplacement = endPosition.y-startPosition.y;
    
    float angle = atan2(xDisplacement, yDisplacement);
    int octant = (int)(round(8 * angle / (2 * M_PI) + 8)) % 8;
    
    return (direction) octant;
}

-(void)touchesMoved:(NSSet *)touches withEvent:(UIEvent *)event{
    %orig;
    //HBLogDebug(@"isTrackPad: %d", [self isTrackpadMode]?1:0);
    if (preferencesBool(kEnabledkey,YES)){
        if ((preferencesInt(kSwipeSpaceBarTogglekey,0) < 1)){
            isTrackPadMode = [self isTrackpadMode];
            UITouch *touch =  [[touches allObjects] lastObject];
            endPosition = [touch locationInView:touch.view];
            int dragDirection = [self computeDirectionFromTouches];
            //HBLogDebug(@"Direction: %ld", [self computeDirectionFromTouches]);
            if ([key isEqualToString:@" "] && (dragDirection == 3 || dragDirection == 4 || dragDirection == 5)){
                isDraggedGesture = YES;
            }else{
                isDraggedGesture = NO;
            }
        }
    }
}


- (void)touchesEnded:(NSSet *)touches withEvent:(UIEvent *)event  {
    //HBLogDebug(@"touchesEnded count: %lu",touches.count);
    //UIView *endedKey = [self hitTest:[touch locationInView:touch.view] withEvent:event];
    //CGPoint pt =[dv convertPoint:[touch locationInView:self.window] fromView:self];
    // NSIndexPath *cidx = [dv.typex indexPathForItemAtPoint:[touch locationInView:touch.window]];
    
    if (preferencesBool(kEnabledkey,YES) && (preferencesInt(kSwipeSpaceBarTogglekey,0) < 1) && [key isEqualToString:@" "] && isDraggedGesture && [dockView respondsToSelector:@selector(barmoji)] && !isTrackPadMode){
        NSTimeInterval elapsedTime = -1.0 * [prevTime timeIntervalSinceNow];
        isDraggedGesture = NO;
        //if (startPosition.y > (endPosition.y + 15)){
        //if (dockView){
        //[dockView.typex removeFromSuperview];
        //[dockView layoutSubviews];
        kbImpl = [%c(UIKeyboardImpl) activeInstance];
        delegate = DXKeyboardInputDelegate(kbImpl);
        [kbImpl clearInputWithCandidatesCleared:YES];
        
        if (elapsedTime > 0.2){
            [[NSNotificationCenter defaultCenter] postNotificationName:@"toggleTypeX" object:nil];
        }
        
        
        
        //[dockView.barmoji setNeedsLayout];
        //dockView.barmoji.layer.zPosition = 1;
        //[dockView.typex removeFromSuperview];
        //[dockView.barmoji removeFromSuperview];
        //[dockView addSubview:dockView.barmoji];
        
        if ([self respondsToSelector:@selector(clearContinuousPathView)]){
            [self clearContinuousPathView];
        }
        [self touchesCancelled:touches withEvent:event];
        return;
    }
    isDraggedGesture = NO;
    %orig;
}

%end

%hook UIKeyboardMenuView
-(void)show{
    //HBLogDebug(@"UIKeyboardMenuView: %@", [self inputView ].currentImage.description);
    //if (preferencesBool(kEnabledkey,YES) && !(preferencesInt(kDedicatedGestureButtonkey, 0) < 1)){
    // return;
    //}
    if (preferencesBool(kEnabledkey,YES) && preferencesInt(kDockModekey, 0) < 3){
        if ((preferencesInt(kDedicatedGestureButtonkey, 0) == 1 || preferencesInt(kDedicatedGestureButtonkey, 0) == 3) && [[self inputView].currentImage.description containsString:@"globe"]){
            return;
        }
        if ((preferencesInt(kDedicatedGestureButtonkey, 0) == 2 || preferencesInt(kDedicatedGestureButtonkey, 0) == 3) && [[self inputView].currentImage.description containsString:@"mic"]){
            return;
        }
    }
    
    %orig;
}


%end


%hook UISystemKeyboardDockController

-(void)updateDockItemsVisibility{
    %orig;
    if (preferencesBool(kEnabledkey,YES)){
        self.dockView.typex.hidden = self.dockView.centerDockItem ? !self.dockView.centerDockItem.view.hidden : NO;
        UIInterfaceOrientation orientation = DXCurrentInterfaceOrientation();
        
        if (UIInterfaceOrientationIsLandscape(orientation)){
            self.dockView.typex.hidden = YES;
        }
    }else if (self.dockView.typex){
        self.dockView.typex.hidden = YES;
        if ([self.dockView respondsToSelector:@selector(barmoji)]) self.dockView.barmoji.hidden = NO;
    }
}

%end

%end


static void updateAutoCorrection() {
    //HBLogDebug(@"received: %@", dockView.typex);
    [[NSNotificationCenter defaultCenter] postNotificationName:@"updateAutoCorrection" object:nil];
}

static void updateAutoCapitalization() {
    //HBLogDebug(@"received: %@", dockView.typex);
    [[NSNotificationCenter defaultCenter] postNotificationName:@"updateAutoCapitalization" object:nil];
}

static void reloadPrefs(void) {
    prefs = [[[DXPrefsManager sharedInstance] readPrefsFromSandbox:!isSpringBoard] mutableCopy];
    
    if (!firstInit){
        // Cache invalidation is an internal maintenance operation.  Do not post
        // kPrefsChangedIdentifier here: this function is itself the observer for
        // that notification, and posting synchronously causes unbounded re-entry
        // (and a SpringBoard SIGSEGV) when the user toggles the main switch.
        [[DXPrefsManager sharedInstance] removeKey:kCachekey notify:NO];
    }else{
        firstInit = NO;
    }
    toastTintColor = toastImageTintColor;
    toastBackgroundTintColor = toastBackgroundColor;
    
    
    
    //prefs = [[[DXPrefsManager sharedInstance] readPrefs] mutableCopy];
    
    //isSandboxed = ![NSHomeDirectory() isEqualToString:@"/var/mobile"];
    //CFPreferencesAppSynchronize((CFStringRef)kIdentifier);
    
    /*
     if ([NSHomeDirectory() isEqualToString:@"/var/mobile"]) {
     isSandboxed = NO;
     prefs = [[[DXPrefsManager sharedInstance] readPrefs] mutableCopy];
     } else {
     isSandboxed = YES;
     CPDistributedMessagingCenter *c = [CPDistributedMessagingCenter centerNamed:@"com.lindo.typex.server"];
     prefs = [[c sendMessageAndReceiveReplyName:@"typeXFetchPrefs" userInfo:nil] mutableCopy];
     
     }
     */
    //prefs = [NSMutableDictionary dictionary];
    //[prefs addEntriesFromDictionary:[NSDictionary dictionaryWithContentsOfFile:kPrefsPath]];
    
    
    //HBLogDebug(@"reloadPrefs: %@", prefs);
    //HBLogDebug(@"kShortcutsPerSection: %@", prefs[kShortcutsPerSection]);
    currentBackgroundTintColor = nil;
    //currentTintColor = nil;
    if (preferencesBool(kColorEnabledkey,NO)){
        
        if (preferencesBool(kShortcutsTintEnabled,YES)) currentTintColor = DXColorFromHex(prefs[@"shortcutstint"], @"#ff0000");
        if (preferencesBool(kToastTintEnabled,YES)) toastTintColor = DXColorFromHex(prefs[@"toasttint"], @"#ff0000");
        if (preferencesBool(kShortcutsBackgroundTintEnabled,YES)) currentBackgroundTintColor = DXColorFromHex(prefs[@"shortcutsbackgroundtint"], @"#5B5B5B");
        if (preferencesBool(kToastBackgroundTintEnabled,YES)) toastBackgroundTintColor = DXColorFromHex(prefs[@"toastbackgroundtint"], @"#000000");
    }
    
    toggledOn = preferencesBool(kToggledOnkey,YES);
    singleTapGlobeEnabled = (((preferencesInt(kDockModekey, 0) == 0 || preferencesInt(kDockModekey, 0) == 2)) && (preferencesInt(kDedicatedGestureButtonkey,0) == 1 || preferencesInt(kDedicatedGestureButtonkey,0) == 3) && (preferencesInt(kGestureTypekey,0) == 0)) ? YES : NO;
    singleTapDictationEnabled = (((preferencesInt(kDockModekey, 0) == 0 || preferencesInt(kDockModekey, 0) == 1)) && (preferencesInt(kDedicatedGestureButtonkey,0) == 2 || preferencesInt(kDedicatedGestureButtonkey,0) == 3) && (preferencesInt(kGestureTypekey,0) == 0)) ? YES : NO;
    
    useShortenedLabel = preferencesBool(kShortLabelEnabledKey, NO);
    
    
    topInset = preferencesFloat(kTopInsetkey, topInsetDefault);
    bottomInset = preferencesFloat(kBottomInsetkey, bottomInsetDefault);
    leftInset = preferencesFloat(kLeftInsetkey, leftInsetDefault);
    rightInset = preferencesFloat(kRightInsetkey, rightInsetDefault);
    
    leadingOffset = preferencesFloat(kLeadinfOffsetkey,leadingOffsetDefault);
    leadingOffset = currentBackgroundTintColor ? leadingOffset-9.0f : leadingOffset;
    trailingOffset = preferencesFloat(kTrailingOffsetkey, trailingOffsetDefault);
    heightOffset = preferencesFloat(kHeightOffsetkey, heightOffsetDefault);
    bottomOffset = preferencesFloat(kBottomOffsetkey, bottomOffsetDefault);
    
    buttonHeight = preferencesFloat(kCellHeightkey, currentBackgroundTintColor?cellsHeightDefault+5:cellsHeightDefault);
    buttonRadius = preferencesFloat(kCellRadiuskey, currentBackgroundTintColor?cellsRadiusDefault+10:cellsRadiusDefault);
    buttonSpacing = preferencesFloat(kCellSpacingkey, spacingBetweenCellsDefault);
    
    //attemptOneHandedOffsetAdjust = preferencesBool(kAttemptOffsetAutoAdjustInOneHandedkey, YES);
    
    isPagingEnabled =  preferencesBool(kPagingkey, YES);
    shouldPerformBatchUpdate = NO;
    spongebobEntropy = (DXStudlyCapsType)preferencesInt(kSpongebobEntropyKey, DXStudlyCapsTypeRandom);

    // Settings changes arrive while the keyboard dock is still alive.  Refresh
    // its data source and visibility explicitly; iOS 17 no longer recreates the
    // dock view for every preferences update.
    BOOL enabled = preferencesBool(kEnabledkey, YES);
    if (dockView.typex) {
        [dockView.typex reloadShortcutConfiguration];
        dockView.typex.hidden = !enabled || !toggledOn || isLandscape || isDictating;
        if ([dockView respondsToSelector:@selector(barmoji)]) {
            dockView.barmoji.hidden = enabled && toggledOn && !isLandscape && !isDictating;
        }
        [dockView.typex.collectionViewLayout invalidateLayout];
        [dockView.typex reloadData];
    }
    UIKeyboardLayoutStar *keyboardLayout = nil;
    if (dockView && [dockView respondsToSelector:@selector(_keyboardLayoutView)]) {
        keyboardLayout = (UIKeyboardLayoutStar *)[dockView _keyboardLayoutView];
    }
    if (keyboardLayout.typexTop) {
        [keyboardLayout.typexTop reloadShortcutConfiguration];
        BOOL topHasShortcuts = [keyboardLayout.typexTop.shortcuts[kbuttonsImages12] count] > 0;
        keyboardLayout.typexTop.hidden = !enabled || !toggledOn || isLandscape || isDictating || !topHasShortcuts;
        [keyboardLayout.typexTop.collectionViewLayout invalidateLayout];
        [keyboardLayout.typexTop reloadData];
    }
    /*
     if (dockView){
     [UIView performWithoutAnimation:^{
     [dockView.typex performBatchUpdates:^{
     [dockView.typex reloadData];
     [dockView.typex.collectionViewLayout invalidateLayout];
     } completion:^(BOOL finished) {}];
     
     }];
     }
     */
    /*
     if (dockV){
     dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
     [[DXPrefsManager sharedInstance] setValue:[NSKeyedArchiver archivedDataWithRootObject:dockV.typex] forKey:@"prevState" fromSandbox:!isSpringBoard];
     });
     }
     */
    
    
}

static void reloadPrefsNotificationCallback(CFNotificationCenterRef center,
                                             void *observer,
                                             CFStringRef name,
                                             const void *object,
                                             CFDictionaryRef userInfo) {
    // Darwin notifications may arrive while Settings is still unwinding the
    // preference write.  Always refresh on the process main queue so UIKit state
    // and the TypeX view are updated serially and never from the posting thread.
    dispatch_async(dispatch_get_main_queue(), ^{
        reloadPrefs();
    });
}

static void sbDidLaunch(){
    [DXToastWindowController sharedInstance];
}

%ctor {
    
    @autoreleasepool {
        
        NSArray *args = [[NSClassFromString(@"NSProcessInfo") processInfo] arguments];
        
        if (args.count != 0){
            NSString *executablePath = args[0];
            HBLogDebug(@"executablePath: %@", executablePath);
            if (executablePath){
                NSString *processName = [executablePath lastPathComponent];
                //HBLogDebug(@"INIT: %@", processName);
                isSpringBoard = [processName isEqualToString:@"SpringBoard"];
                isApplication = [executablePath rangeOfString:@"/Application"].location != NSNotFound;
				isApplication = isApplication ?: ([executablePath rangeOfString:@".appex/"].location != NSNotFound ?: isApplication);
                //isApplication = [processName isEqualToString:@"MarkupPhotoExtension"] ?: isApplication;
                isSafari = [processName isEqualToString:@"MobileSafari"];
				HBLogDebug(@"isSpringBoard: %d ** isApplication: %d ** isSafari: %d", isSpringBoard, isApplication, isSafari);
				
                if (isSpringBoard || isApplication){
                    tweakBundle = [NSBundle bundleWithPath:bundlePath];
                    [tweakBundle load];
                    firstInit = YES;
                    reloadPrefs();
                    shouldUpdateTrueKBType = YES;
                    shouldPerformBatchUpdate = YES;
                    %init(TypeX);
                    CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(), NULL, reloadPrefsNotificationCallback, (CFStringRef)kPrefsChangedIdentifier, NULL, CFNotificationSuspensionBehaviorDeliverImmediately);
                    CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(), NULL, (CFNotificationCallback)updateAutoCorrection, (CFStringRef)kAutoCorrectionChangedIdentifier, NULL, CFNotificationSuspensionBehaviorDeliverImmediately);
                    CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(), NULL, (CFNotificationCallback)updateAutoCapitalization, (CFStringRef)kAutoCapitalizationChangedIdentifier, NULL, CFNotificationSuspensionBehaviorDeliverImmediately);
                }
                if (isSpringBoard){
                    CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(), NULL, (CFNotificationCallback)sbDidLaunch, (CFStringRef)@"SBSpringBoardDidLaunchNotification", NULL, CFNotificationSuspensionBehaviorDeliverImmediately);
                }
                
            }
        }
    }
}
