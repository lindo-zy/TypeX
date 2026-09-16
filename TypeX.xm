#import "common.h"
#import "TypeX.h"
#import "DXShared.h"
#import "DXHelper.h"
#import "DXQuickActionProvider.h"
#import <objc/runtime.h>
#import <objc/message.h>
#import <SpringBoardServices/SpringBoardServices.h>


id delegate;
UIKeyboardImpl *kbImpl;
UIColor *currentTintColor;
UIColor *currentBackgroundTintColor;
UIColor *currentTopToolbarBackgroundColor;
BOOL isLandscape = NO;
NSMutableDictionary *prefs;
BOOL isDictating = NO;
BOOL toggledOn = YES;
UIKeyboardDockView *dockView;
//BOOL isSandboxed = NO;
BOOL singleTapDictationEnabled = NO;
BOOL singleTapGlobeEnabled = NO;
BOOL isSpringBoard = YES;
BOOL isApplication = NO;
BOOL isSafari = NO;
BOOL shouldPerformBatchUpdate = YES;
//BOOL shouldSendScrollExecution = YES;
UIKeyboardDockView *dockV;
NSBundle *tweakBundle;
BOOL firstInit = YES;
DXStudlyCapsType spongebobEntropy;

static const CGFloat kDXTopToolbarHeight = 41.5;
static char kDXTopAccessoryContainerKey;
static NSUInteger topToolbarPresentationGeneration;
static __weak UIResponder *topToolbarCurrentResponder;

@interface DXTopAccessoryContainer : UIView
@property(nonatomic, strong) DXCollectionView *toolbar;
@property(nonatomic, strong) UIView *originalAccessory;
@end

@implementation DXTopAccessoryContainer

- (CGFloat)dxOriginalAccessoryHeight {
    if (!self.originalAccessory) return 0.0;
    CGFloat height = MAX(0.0, CGRectGetHeight(self.originalAccessory.frame));
    if (height <= 0.0) {
        CGFloat intrinsicHeight = [self.originalAccessory intrinsicContentSize].height;
        if (intrinsicHeight != UIViewNoIntrinsicMetric) height = MAX(0.0, intrinsicHeight);
    }
    return height;
}

- (CGSize)intrinsicContentSize {
    CGFloat originalHeight = [self dxOriginalAccessoryHeight];
    return CGSizeMake(UIViewNoIntrinsicMetric,
                      kDXTopToolbarHeight + (originalHeight > 0.0 ? originalHeight + 1.0 : 0.0));
}

- (void)layoutSubviews {
    [super layoutSubviews];
    self.toolbar.frame = CGRectMake(0.0, 0.0, CGRectGetWidth(self.bounds), kDXTopToolbarHeight);
    if (self.originalAccessory) {
        CGFloat originalHeight = [self dxOriginalAccessoryHeight];
        self.originalAccessory.frame = CGRectMake(0.0, kDXTopToolbarHeight + 1.0,
                                                   CGRectGetWidth(self.bounds), originalHeight);
    }
    [self dxApplyBackgroundColor];
}

- (void)traitCollectionDidChange:(UITraitCollection *)previousTraitCollection {
    [super traitCollectionDidChange:previousTraitCollection];
    [self dxApplyBackgroundColor];
}

- (void)didMoveToWindow {
    [super didMoveToWindow];
    [self dxApplyBackgroundColor];
}

- (void)setBackgroundColor:(UIColor *)backgroundColor {
    if (currentTopToolbarBackgroundColor) {
        [super setBackgroundColor:currentTopToolbarBackgroundColor];
    } else if (backgroundColor && CGColorGetAlpha(backgroundColor.CGColor) > 0.01) {
        [super setBackgroundColor:backgroundColor];
    } else {
        [self dxApplyBackgroundColor];
    }
}

- (void)dxApplyBackgroundColor {
    UIColor *backgroundColor = currentTopToolbarBackgroundColor;
    UIColor *accessoryColor = self.originalAccessory.backgroundColor;
    if (!backgroundColor && accessoryColor && CGColorGetAlpha(accessoryColor.CGColor) > 0.01) {
        backgroundColor = accessoryColor;
    }
    if (!backgroundColor) {
        if (@available(iOS 13.0, *)) {
            backgroundColor = [UIColor systemBackgroundColor];
        } else {
            backgroundColor = [UIColor whiteColor];
        }
    }
    [super setBackgroundColor:backgroundColor];
}

@end

static inline BOOL DXResponderSupportsInputAccessoryView(UIResponder *responder) {
    return [responder respondsToSelector:@selector(setInputAccessoryView:)] &&
           [responder respondsToSelector:@selector(inputAccessoryView)];
}

// Messages' ChatKit input manages its own keyboard accessory (the compose bar
// stays visible with the keyboard dismissed and it validates its input session
// state). Replacing such a responder's inputAccessoryView aborts keyboard
// presentation, so the top toolbar must never take the accessory there. The
// dock toolbar is unaffected. The class-prefix check also covers ChatKit inputs
// hosted outside the Messages process (e.g. share-sheet composition).
static BOOL DXResponderHasManagedInputBar(UIResponder *responder) {
    static BOOL isMessagesProcess;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        isMessagesProcess = [NSBundle.mainBundle.bundleIdentifier isEqualToString:@"com.apple.MobileSMS"];
    });
    if (isMessagesProcess) return YES;

    Class cls = [responder class];
    for (NSInteger depth = 0; cls && depth < 4; depth++) {
        if ([NSStringFromClass(cls) hasPrefix:@"CK"]) return YES;
        cls = [cls superclass];
    }
    return NO;
}

static UIView *DXInputAccessoryView(UIResponder *responder) {
    if (!DXResponderSupportsInputAccessoryView(responder)) return nil;
    return [responder performSelector:@selector(inputAccessoryView)];
}

static void DXSetInputAccessoryView(UIResponder *responder, UIView *view) {
    if (DXResponderSupportsInputAccessoryView(responder)) {
        [responder performSelector:@selector(setInputAccessoryView:) withObject:view];
    }
}

static BOOL DXToolbarHasShortcuts(DXCollectionView *toolbar) {
    return toolbar.shortcutConfigurationAvailable &&
           [toolbar.shortcuts[kbuttonsImages12] count] > 0;
}

static BOOL DXShouldDisplayTopAccessory(DXTopAccessoryContainer *container) {
    BOOL enabled = preferencesBool(kEnabledkey, YES);
    return enabled && toggledOn && !isLandscape && !isDictating &&
           DXToolbarHasShortcuts(container.toolbar);
}

static UIView *DXAccessoryByWrappingReplacement(UIResponder *responder, UIView *replacement) {
    DXTopAccessoryContainer *container = objc_getAssociatedObject(responder, &kDXTopAccessoryContainerKey);
    if (!container || DXResponderHasManagedInputBar(responder) ||
        replacement == container || replacement == container.toolbar ||
        !DXShouldDisplayTopAccessory(container)) {
        return replacement;
    }

    if (container.originalAccessory != replacement) {
        [container.originalAccessory removeFromSuperview];
        container.originalAccessory = replacement;
    }
    if (replacement && replacement.superview != container) {
        [container addSubview:replacement];
    }
    [container invalidateIntrinsicContentSize];
    [container dxApplyBackgroundColor];
    return container;
}

static void DXInstallTopAccessoryForResponder(UIResponder *responder, BOOL reloadConfiguration) {
    if (!responder || (!isApplication && !isSpringBoard) ||
        DXResponderHasManagedInputBar(responder) || !DXResponderSupportsInputAccessoryView(responder)) return;

    BOOL enabled = preferencesBool(kEnabledkey, YES);
    DXTopAccessoryContainer *container = objc_getAssociatedObject(responder, &kDXTopAccessoryContainerKey);
    UIView *currentAccessory = DXInputAccessoryView(responder);
    BOOL mayCreate = enabled && toggledOn && !isLandscape && !isDictating &&
                     [DXPrefsManager sharedInstance].preferencesAvailable;
    BOOL createdContainer = NO;

    if (!container && mayCreate) {
        container = [[DXTopAccessoryContainer alloc] initWithFrame:CGRectMake(0.0, 0.0, 0.0,
                                                                               kDXTopToolbarHeight)];
        container.clipsToBounds = YES;
        container.toolbar = [[DXCollectionView alloc] initWithConfiguration:@"top"];
        container.toolbar.clipsToBounds = YES;
        [container addSubview:container.toolbar];
        objc_setAssociatedObject(responder, &kDXTopAccessoryContainerKey, container, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        createdContainer = YES;
    }
    if (!container) return;

    if (reloadConfiguration && !createdContainer) {
        [container.toolbar reloadShortcutConfiguration];
        [container.toolbar.collectionViewLayout invalidateLayout];
        [container.toolbar reloadData];
    }

    BOOL shouldDisplay = DXShouldDisplayTopAccessory(container);
    if (!shouldDisplay) {
        container.toolbar.hidden = YES;
        if (currentAccessory == container) {
            [container.originalAccessory removeFromSuperview];
            DXSetInputAccessoryView(responder, container.originalAccessory);
            if (responder.isFirstResponder) [responder reloadInputViews];
        }
        return;
    }

    if (currentAccessory != container && currentAccessory != container.toolbar && currentAccessory != nil) {
        if (container.originalAccessory != currentAccessory) {
            [container.originalAccessory removeFromSuperview];
            container.originalAccessory = currentAccessory;
        }
        if (currentAccessory.superview != container) [container addSubview:currentAccessory];
        [container invalidateIntrinsicContentSize];
    }

    [container dxApplyBackgroundColor];
    container.toolbar.hidden = NO;
    if (currentAccessory != container) {
        DXSetInputAccessoryView(responder, container);
        if (responder.isFirstResponder) [responder reloadInputViews];
    }
}

static UIResponder *DXTopToolbarResponder(UIKeyboardImpl *keyboard) {
    if (topToolbarCurrentResponder.isFirstResponder &&
        DXResponderSupportsInputAccessoryView(topToolbarCurrentResponder)) {
        return topToolbarCurrentResponder;
    }

    UIResponder *active = DXKeyboardInputDelegate(keyboard);
    if (DXResponderSupportsInputAccessoryView(active)) return active;

    SEL selectableSelector = NSSelectorFromString(@"selectableInputDelegate");
    if ([keyboard respondsToSelector:selectableSelector]) {
        id (*sendObject)(id, SEL) = (id (*)(id, SEL))objc_msgSend;
        UIResponder *selectable = sendObject(keyboard, selectableSelector);
        if (DXResponderSupportsInputAccessoryView(selectable)) return selectable;
    }
    return active;
}

static void DXRefreshActiveTopToolbarWithConfiguration(BOOL reloadConfiguration) {
    UIKeyboardImpl *keyboard = [objc_getClass("UIKeyboardImpl") activeInstance];
    DXInstallTopAccessoryForResponder(DXTopToolbarResponder(keyboard), reloadConfiguration);
}

static void DXRefreshActiveTopToolbar(void) {
    DXRefreshActiveTopToolbarWithConfiguration(YES);
}

@interface DXTopToolbarLifecycleObserver : NSObject
@end

@implementation DXTopToolbarLifecycleObserver

- (void)keyboardDidShow:(NSNotification *)notification {
    (void)notification;
    NSUInteger generation = ++topToolbarPresentationGeneration;
    // The responder already loaded the current configuration before becoming
    // first responder. At this point only re-wrap the accessory UIKit finalized;
    // reloading the collection here exposes a second, visibly different layout
    // pass after the keyboard is already on screen.
    DXRefreshActiveTopToolbarWithConfiguration(NO);

    // Some keyboards install their own accessory asynchronously on their first
    // presentation. Retry after that work completes and wrap the final view.
    for (NSNumber *delay in @[@0.05, @0.20]) {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(delay.doubleValue * NSEC_PER_SEC)),
                       dispatch_get_main_queue(), ^{
            if (generation == topToolbarPresentationGeneration) {
                DXRefreshActiveTopToolbarWithConfiguration(NO);
            }
        });
    }
}

- (void)keyboardWillHide:(NSNotification *)notification {
    (void)notification;
    ++topToolbarPresentationGeneration;
}

@end

static DXTopToolbarLifecycleObserver *topToolbarLifecycleObserver;

// Button chrome (height/radius/spacing/border/width scale) is read per
// configuration inside DXCollectionView; there are no shared globals for it.

CGFloat heightOffset = heightOffsetDefault;

#pragma mark hook
%group TypeX

%hook UIKeyboardImpl

- (void)layoutSubviews {
    %orig;
    // The first keyboard presentation can finish wiring its input delegate only
    // after the responder's own becomeFirstResponder: has already returned.
    DXRefreshActiveTopToolbarWithConfiguration(NO);
}

%end

%hook UITextField

- (void)didMoveToWindow {
    %orig;
    if (self.window) DXInstallTopAccessoryForResponder(self, NO);
}

- (BOOL)becomeFirstResponder {
    // inputAccessoryView must be present before UIKit starts constructing the
    // first keyboard for this responder. Installing after %orig is too late in
    // Settings search fields and only takes effect on the next presentation.
    topToolbarCurrentResponder = self;
    DXInstallTopAccessoryForResponder(self, YES);
    BOOL result = %orig;
    if (result) {
        DXInstallTopAccessoryForResponder(self, NO);
    } else if (topToolbarCurrentResponder == self) {
        topToolbarCurrentResponder = nil;
    }
    return result;
}

- (void)setInputAccessoryView:(UIView *)inputAccessoryView {
    UIView *effectiveAccessory = DXAccessoryByWrappingReplacement(self, inputAccessoryView);
    %orig(effectiveAccessory);
}

- (void)layoutSubviews {
    %orig;
    if (self.isFirstResponder) {
        topToolbarCurrentResponder = self;
        DXInstallTopAccessoryForResponder(self, NO);
    }
}

%end

%hook UITextView

- (void)didMoveToWindow {
    %orig;
    if (self.window) DXInstallTopAccessoryForResponder(self, NO);
}

- (BOOL)becomeFirstResponder {
    topToolbarCurrentResponder = self;
    DXInstallTopAccessoryForResponder(self, YES);
    BOOL result = %orig;
    if (result) {
        DXInstallTopAccessoryForResponder(self, NO);
    } else if (topToolbarCurrentResponder == self) {
        topToolbarCurrentResponder = nil;
    }
    return result;
}

- (void)setInputAccessoryView:(UIView *)inputAccessoryView {
    UIView *effectiveAccessory = DXAccessoryByWrappingReplacement(self, inputAccessoryView);
    %orig(effectiveAccessory);
}

- (void)layoutSubviews {
    %orig;
    if (self.isFirstResponder) {
        topToolbarCurrentResponder = self;
        DXInstallTopAccessoryForResponder(self, NO);
    }
}

%end

%hook UIKeyboardDockView
//%property (retain, nonatomic) UIKeyboardDockItemButton *leftDockButton;
//%property (retain, nonatomic) UIKeyboardDockItemButton *rightDockButton;
%property (retain, nonatomic) DXCollectionView *typex;

- (instancetype)initWithFrame:(CGRect)frame {
    dockView = %orig;
    if (preferencesBool(kEnabledkey,YES) && dockView) {
        self.typex = [[DXCollectionView alloc] initWithConfiguration:@"bottom"];
        
        //self.typex = [[DXCollectionView alloc] init];
        
        self.typex.translatesAutoresizingMaskIntoConstraints = NO;
        //self.typex.transform = CGAffineTransformMakeScale(-1, 1);
        
        [dockView addSubview:self.typex];
        
        // The dock mode decides which stock dock buttons survive; the toolbar
        // insets clear the buttons that remain (69/-60 keep both stock buttons,
        // 5/-5 stretch the bar to the dock's edge).
        float leading = 69.0f;
        float trailing = -60.0f;

        switch (preferencesInt(kDockModekey, 0)){
            case 1:
                leading = 5.0f;
                break;
            case 2:
                trailing = -5.0f;
                break;
            case 3:
                leading = 5.0f;
                trailing = -5.0f;
                break;
        }

        NSLayoutConstraint *leadingConstraint = [NSLayoutConstraint constraintWithItem:self.typex attribute:NSLayoutAttributeLeading relatedBy:NSLayoutRelationEqual toItem:dockView attribute:NSLayoutAttributeLeading multiplier:1.0 constant:leading];
        leadingConstraint.identifier = @"TypeX";
        [dockView addConstraint:leadingConstraint];

        NSLayoutConstraint *trailingConstraint = [NSLayoutConstraint constraintWithItem:self.typex attribute:NSLayoutAttributeTrailing relatedBy:NSLayoutRelationEqual toItem:dockView attribute:NSLayoutAttributeTrailing multiplier:1.0 constant:trailing];
        trailingConstraint.identifier = @"TypeX";
        [dockView addConstraint:trailingConstraint];

        NSLayoutConstraint *heightConstraint = [NSLayoutConstraint constraintWithItem:self.typex attribute:NSLayoutAttributeHeight relatedBy:NSLayoutRelationEqual toItem:nil attribute:NSLayoutAttributeNotAnAttribute multiplier:1.0 constant:heightOffset];
        heightConstraint.identifier = @"TypeX";
        [dockView addConstraint:heightConstraint];

        // Fixed lift above the dock's bottom edge (the former vertical-offset default).
        NSLayoutConstraint *bottomConstraint = [NSLayoutConstraint constraintWithItem:self.typex attribute:NSLayoutAttributeBottom relatedBy:NSLayoutRelationEqual toItem:dockView attribute:NSLayoutAttributeBottom multiplier:1.0 constant:-22.0f];
        bottomConstraint.identifier = @"TypeX";
        [dockView addConstraint:bottomConstraint];

        dispatch_async(dispatch_get_main_queue(), ^{

            kbImpl = [objc_getClass("UIKeyboardImpl") activeInstance];
            delegate = DXKeyboardInputDelegate(kbImpl);
            [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(toggleTypeX:) name:@"toggleTypeX" object:nil];

            // The keyboard can finish creating its private subviews after UIKeyboardImpl's
            // first layout pass. Refresh once the dock has joined the hierarchy as well.
            DXRefreshActiveTopToolbar();
        });
        
    }
    self.typex.hidden = !preferencesBool(kEnabledkey, YES) || !toggledOn ||
                        !DXToolbarHasShortcuts(self.typex);
    
    
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
        // Only read system tint when user hasn't set a custom color
        // (when kShortcutsTintEnabled is NO, meaning "follow system")
        if (!preferencesBool(kShortcutsTintEnabled,NO)){
            currentTintColor = dockItem.button.tintColor;
        }
        if (preferencesInt(kDedicatedGestureButtonkey, 0) == 1 || preferencesInt(kDedicatedGestureButtonkey, 0) == 3){
            if (preferencesInt(kDockModekey, 0) != 1 && preferencesInt(kDockModekey, 0) != 3) {
                %orig;
            }
            if (preferencesInt(kDockModekey, 0) != 1 && preferencesInt(kDockModekey, 0) != 3){
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
        // Only read system tint when user hasn't set a custom color
        if (!preferencesBool(kShortcutsTintEnabled,NO)){
            currentTintColor = dockItem.button.tintColor;
        }
        if (preferencesInt(kDockModekey, 0) == 2 || preferencesInt(kDockModekey, 0) == 3) return;
        if (preferencesInt(kDedicatedGestureButtonkey, 0) == 2 || preferencesInt(kDedicatedGestureButtonkey, 0) == 3){
            %orig;
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
    toggledOn = self.typex.hidden;
    [[DXPrefsManager sharedInstance] setValue:[NSNumber numberWithBool:toggledOn] forKey:kToggledOnkey];
    
    self.typex.hidden = !toggledOn || !DXToolbarHasShortcuts(self.typex);
    if (self.typex.hidden) self.typex.alpha = 1.0f;
    else {
        self.typex.alpha = 0.0f;
        [UIView animateWithDuration:0.2 animations:^{ self.typex.alpha = 1.0f; }];
    }
    DXRefreshActiveTopToolbar();
    [self layoutSubviews];
    
}

%new
-(void)updateTypeXTint{
    // Only refresh tint when custom color is NOT enabled
    // (kShortcutsTintEnabled = NO means "follow system tint")
    if (preferencesBool(kShortcutsTintEnabled,NO)) return;

    UIColor *newTintColor = nil;
    if (self.leftDockItem.button){
        newTintColor = self.leftDockItem.button.tintColor;
    }else if (self.rightDockItem.button){
        newTintColor = self.rightDockItem.button.tintColor;
    }else{
        if (@available(iOS 13.0, *)){
            if (self.traitCollection.userInterfaceStyle == UIUserInterfaceStyleDark) {
                newTintColor = [UIColor whiteColor];
            }else{
                newTintColor = [UIColor blackColor];
            }
        }
    }
    // Only notify if the tint actually changed to avoid unnecessary reloadData on every layout
    if (newTintColor && ![newTintColor isEqual:currentTintColor]) {
        currentTintColor = newTintColor;
        [[NSNotificationCenter defaultCenter] postNotificationName:@"typeXLayoutChanged" object:nil];
    }
}

- (void)layoutSubviews{
    %orig;
    if (preferencesBool(kEnabledkey,YES)){
        if (toggledOn){
            //NSTimeInterval timeInterval = fabs([lastReloadDate timeIntervalSinceNow]);
            //if (lastReloadDate && timeInterval < 0.5f ) lastReloadDate = [NSDate date]; return;
            //if (!self.typex) return;
            if (isDictating || isLandscape || !DXToolbarHasShortcuts(self.typex)){
                self.typex.hidden = YES;
                return;
                //NSNotification * note = [NSNotification notificationWithName:@"typeXLayoutChanged" object:nil];
                //[[NSNotificationCenterQueue defaultQueue] enqueueNotification:note postingStyle:NSPostASAP coalesceMask:NSNotificationCoalescingOnName forModes:nil];
            }else{
                [self updateTypeXTint];
                self.typex.hidden = NO;
                
                UIKeyboardImpl *keyboard = [objc_getClass("UIKeyboardImpl") activeInstance];
                UIResponder *active = DXTopToolbarResponder(keyboard);
                DXInstallTopAccessoryForResponder(active, NO);
                
            }
            //lastReloadDate = [NSDate date];
        }else{
            self.typex.hidden = YES;
        }
        
        

        
    }else{
        // The dock view is not recreated when the main preference is disabled.
        // Explicitly restore the stock bar on iOS 17.
        self.typex.hidden = YES;
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
- (void)traitCollectionDidChange:(UITraitCollection *)previousTraitCollection {
    %orig;
    // Defer tint refresh to next runloop: the system updates dock button
    // tintColor AFTER traitCollectionDidChange returns, so a synchronous
    // read here would still get the old (pre-switch) color.
    __weak typeof(self) weakSelf = self;
    dispatch_async(dispatch_get_main_queue(), ^{
        [weakSelf updateTypeXTint];
    });
}

%end

%hook UIKeyboardDockItem
//iOS 13+
-(void)setImageName:(NSString *)imageName{
    if (([imageName isEqualToString:@"mic"] && singleTapDictationEnabled) || ([imageName isEqualToString:@"globe"] && singleTapGlobeEnabled)){
        %orig(@"circle");
        return;
    }
    %orig;
}

//iOS 12
-(id)initWithImageName:(id)imageName identifier:(id)identifier{
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
}

-(void)switchToDictationInputModeWithTouch:(id)arg1{
    %orig;
    isDictating = YES;
    
}

-(void)stopDictation:(BOOL)arg1{
    %orig;
    if (arg1){
        isDictating = NO;
    }
    
}


%end

//sstatic BOOL forceHidden = NO;


%hook _UIKeyboardTextSelectionInteraction
-(BOOL)gestureRecognizerShouldBegin:(UIGestureRecognizer *)recognizer{
    if (preferencesBool(kEnabledkey,YES) && [NSStringFromClass([recognizer.view class]) isEqualToString:@"UIKeyboardDockView"]){
        return NO;
    }
    return %orig;
}
%end

%hook UIKeyboardLayoutStar

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

%new
- (void)leftSwipeHandle:(UISwipeGestureRecognizer*)recognizer
{
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
    %orig;
}

-(void)touchesMoved:(NSSet *)touches withEvent:(UIEvent *)event{
    %orig;
}


- (void)touchesEnded:(NSSet *)touches withEvent:(UIEvent *)event  {
    %orig;
}

%end

%hook UIKeyboardMenuView
-(void)show{
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
        BOOL stockDockRequiresHiding = self.dockView.centerDockItem ?
            !self.dockView.centerDockItem.view.hidden : NO;
        self.dockView.typex.hidden = stockDockRequiresHiding ||
                                     !DXToolbarHasShortcuts(self.dockView.typex);
        UIInterfaceOrientation orientation = DXCurrentInterfaceOrientation();
        
        if (UIInterfaceOrientationIsLandscape(orientation)){
            self.dockView.typex.hidden = YES;
        }
    }else if (self.dockView.typex){
        self.dockView.typex.hidden = YES;
    }
}

%end

%end


static void reloadPrefs(void) {
    DXPrefsManager *manager = [DXPrefsManager sharedInstance];
    [manager reload];
    prefs = manager.preferencesAvailable ? [manager.prefs mutableCopy] : nil;
    
    if (firstInit){
        firstInit = NO;
    }
    currentBackgroundTintColor = nil;
    currentTopToolbarBackgroundColor = nil;
    //currentTintColor = nil;
    
    // Shortcuts tint: if enabled, use custom color; otherwise follow system (set in setLeftDockItem/updateTypeXTint)
    if (preferencesBool(kShortcutsTintEnabled,NO)) {
        currentTintColor = DXColorFromHex(prefs[@"shortcutstint"], @"#ff0000");
    }
    
    // Background tint options share the legacy colorBOOL master switch.
    if (preferencesBool(kColorEnabledkey,NO)){
        if (preferencesBool(kShortcutsBackgroundTintEnabled,YES)) currentBackgroundTintColor = DXColorFromHex(prefs[@"shortcutsbackgroundtint"], @"#5B5B5B");
        if (preferencesBool(kTopToolbarBackgroundTintEnabledKey,YES)){
            currentTopToolbarBackgroundColor = DXColorFromHex(prefs[kTopToolbarBackgroundTintKey], @"#5B5B5B");
        }
    }
    
    toggledOn = preferencesBool(kToggledOnkey,YES);
    singleTapGlobeEnabled = (((preferencesInt(kDockModekey, 0) == 0 || preferencesInt(kDockModekey, 0) == 2)) && (preferencesInt(kDedicatedGestureButtonkey,0) == 1 || preferencesInt(kDedicatedGestureButtonkey,0) == 3) && (preferencesInt(kGestureTypekey,0) == 0)) ? YES : NO;
    singleTapDictationEnabled = (((preferencesInt(kDockModekey, 0) == 0 || preferencesInt(kDockModekey, 0) == 1)) && (preferencesInt(kDedicatedGestureButtonkey,0) == 2 || preferencesInt(kDedicatedGestureButtonkey,0) == 3) && (preferencesInt(kGestureTypekey,0) == 0)) ? YES : NO;


    heightOffset = preferencesFloat(kHeightOffsetkey, heightOffsetDefault);

    // Button chrome (height/radius/spacing/border/width scale) is scoped per
    // toolbar and recomputed inside DXCollectionView's reloadShortcutConfiguration.

    shouldPerformBatchUpdate = NO;
    spongebobEntropy = (DXStudlyCapsType)preferencesInt(kSpongebobEntropyKey, DXStudlyCapsTypeRandom);

    // Settings changes arrive while the keyboard dock is still alive.  Refresh
    // its data source and visibility explicitly; iOS 17 no longer recreates the
    // dock view for every preferences update.
    BOOL enabled = preferencesBool(kEnabledkey, YES);
    if (dockView.typex) {
        [dockView.typex reloadShortcutConfiguration];
        dockView.typex.hidden = !enabled || !toggledOn || isLandscape || isDictating ||
                                !DXToolbarHasShortcuts(dockView.typex);
        [dockView.typex.collectionViewLayout invalidateLayout];
        [dockView.typex reloadData];
    }
    DXRefreshActiveTopToolbar();
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

static void shortcutRefreshRequestCallback(CFNotificationCenterRef center,
                                           void *observer,
                                           CFStringRef name,
                                           const void *object,
                                           CFDictionaryRef userInfo) {
    NSDictionary *request = DXQuickActionSharedValue(TypeXQuickActionRequestKey);
    NSArray *rawBundles = [request[@"bundles"] isKindOfClass:[NSArray class]] ? request[@"bundles"] : nil;
    NSString *requestID = [request[@"requestID"] isKindOfClass:[NSString class]] ? request[@"requestID"] : nil;
    if (rawBundles.count > 2048) rawBundles = nil;
    if (requestID.length == 0) return;

    static NSString *lastRequestID;
    @synchronized([DXQuickActionProvider class]) {
        if ([lastRequestID isEqualToString:requestID]) return;
        lastRequestID = [requestID copy];
    }

    NSMutableOrderedSet<NSString *> *bundleIdentifiers = [NSMutableOrderedSet orderedSet];
    for (id value in rawBundles) {
        if (DXIsValidBundleIdentifier(value)) [bundleIdentifiers addObject:value];
    }
    // Settings normally supplies the two-pass LaunchServices enumeration.
    // The provider falls back to SpringBoard's application registry when the
    // list is empty, so one authoritative static/dynamic pipeline covers both.
    [DXQuickActionProvider refreshSnapshotForBundleIdentifiers:bundleIdentifiers.array
                                                     requestID:requestID];
}

// SpringBoard side of the 打开应用 / 快捷方式 / openurl channel. Opens made from inside
// a host process are blocked by restricted hosts (WeChat), and identity-gated
// schemes only pass for SpringBoard itself, so requests ride a plist
// {action, ...} plus a Darwin notification and are performed here natively.
// Only the fixed "openapp" (plain bundle identifier), "openshortcut"
// (bundle identifier plus app-defined type), and "openurl" (scheme-validated
// URL string) action names are acted on — the channel never carries shell
// commands or arbitrary selectors.
//
// Consumption runs on a dedicated serial queue, never the main queue: a busy
// main thread must not delay or blackhole panel actions. openurl/openapp are
// pure service XPC and act right here; openshortcut asks the provider to
// resolve and activate the current item on SpringBoard's main queue.
static dispatch_queue_t DXSBPendingActionQueue(void) {
    static dispatch_queue_t queue;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        queue = dispatch_queue_create("com.lindo.typex.pendingaction", DISPATCH_QUEUE_SERIAL);
    });
    return queue;
}

// Executes one already-consumed request. Pure service XPC runs right here on
// the serial queue; openshortcut delegates to the SpringBoard provider.
static void DXSBExecutePendingActionRequest(NSDictionary *request) {
    NSString *action = [request isKindOfClass:[NSDictionary class]] ? request[@"action"] : nil;
    NSString *bundle = [request isKindOfClass:[NSDictionary class]] ? request[@"bundle"] : nil;
    NSString *urlString = [request isKindOfClass:[NSDictionary class]] ? request[@"url"] : nil;
    NSString *shortcutType = [request isKindOfClass:[NSDictionary class]] ? request[@"shortcuttype"] : nil;

    if ([action isEqualToString:@"openapp"]) {
        if (!DXIsValidBundleIdentifier(bundle)) return;

        FBSSystemService *service = [FBSSystemService sharedService];
        SEL openSelector = @selector(openApplication:options:withResult:);
        BOOL scheduled = NO;
        if (service && [service respondsToSelector:openSelector]) {
            @try {
                [service openApplication:bundle options:@{} withResult:^(NSError *error) {
                    // A failed launch is not reported back: the keyboard has
                    // no channel for it and the app switcher stays the retry.
                    // Syslog is the only place a refusal can be diagnosed.
                    if (error) {
                        NSLog(@"[TypeX] pendingaction: openApplication %@ failed: %@", bundle, error);
                    }
                }];
                scheduled = YES;
            } @catch (__unused NSException *exception) {
                scheduled = NO;
            }
        }
        if (!scheduled) {
            int result = SBSLaunchApplicationWithIdentifierAndLaunchOptions(bundle, @{}, @{}, NO);
            if (result != 0) {
                NSLog(@"[TypeX] pendingaction: SBS launch of %@ failed (%d)", bundle, result);
            }
        }
        return;
    }

    if ([action isEqualToString:@"openshortcut"]) {
        if (!DXIsValidBundleIdentifier(bundle) ||
            ![shortcutType isKindOfClass:[NSString class]] ||
            shortcutType.length == 0 || shortcutType.length > 512) return;
        [DXQuickActionProvider activateShortcutWithBundleIdentifier:bundle type:shortcutType];
        return;
    }

    if ([action isEqualToString:@"openurl"]) {
        if (!DXIsOpenableSchemeURLString(urlString)) return;

        // Opened by SpringBoard itself: the host app cannot intercept the
        // request, and schemes gated on the requester's identity (prefs:,
        // App-Prefs:) pass because the requester is SpringBoard. The return
        // value is the only execution feedback this channel has; a refused
        // open used to vanish silently and look like a dead tap.
        NSURL *url = [NSURL URLWithString:urlString];
        if (!SBSOpenSensitiveURLAndUnlock((__bridge CFURLRef)url, 0)) {
            NSLog(@"[TypeX] pendingaction: openurl refused by SpringBoard: %@", urlString);
        }
    }
}

// A request older than this is dropped instead of executed: the tap that
// wrote it is long over, and replaying it onto whatever the user is doing
// now is exactly the "one tap, two actions" failure.
static const NSTimeInterval DXSBPendingActionMaxAge = 30.0;
// Identical requests produced by duplicate gesture/control callbacks can land
// in separate drains, so per-drain comparison is insufficient. Keep a short
// process-wide execution window keyed by the semantic payload. A later,
// intentional tap remains possible after the window expires.
static const NSTimeInterval DXSBPendingActionDuplicateWindow = 1.0;
// Consecutive launches inside one drain are paced: each request starts an
// app-transition transaction, and two transactions racing used to wedge
// SpringBoard's UI.
static const NSTimeInterval DXSBPendingActionLaunchGap = 0.8;

static BOOL DXSBPendingActionWasRecentlyExecuted(NSDictionary *request) {
    static NSMutableDictionary<NSString *, NSNumber *> *executionTimes;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        executionTimes = [NSMutableDictionary dictionary];
    });

    NSString *key = [NSString stringWithFormat:@"%@|%@|%@|%@",
                     request[@"action"] ?: @"",
                     request[@"bundle"] ?: @"",
                     request[@"url"] ?: @"",
                     request[@"shortcuttype"] ?: @""];
    NSTimeInterval now = [NSDate timeIntervalSinceReferenceDate];
    NSNumber *previous = executionTimes[key];
    if (previous && now - previous.doubleValue < DXSBPendingActionDuplicateWindow) return YES;
    executionTimes[key] = @(now);

    // The queue is serial; cheap opportunistic pruning keeps the table bounded.
    for (NSString *storedKey in executionTimes.allKeys) {
        if (now - [executionTimes[storedKey] doubleValue] > DXSBPendingActionMaxAge) {
            [executionTimes removeObjectForKey:storedKey];
        }
    }
    return NO;
}

// Every request file currently on disk, oldest first by modification time.
// The legacy fixed-path file (pre-timestamped builds) carries no
// "pendingaction-" prefix and is collected explicitly; a name sort cannot
// order it against the timestamped files, so the ordering comes from the
// files themselves.
static NSMutableArray<NSString *> *DXSBPendingActionRequestPaths(void) {
    NSFileManager *fileManager = [NSFileManager defaultManager];
    NSString *directory = [TypeXPendingActionPath stringByDeletingLastPathComponent];
    NSMutableArray<NSString *> *paths = [NSMutableArray array];
    if ([fileManager fileExistsAtPath:TypeXPendingActionPath]) {
        [paths addObject:TypeXPendingActionPath];
    }
    for (NSString *fileName in [fileManager contentsOfDirectoryAtPath:directory error:nil]) {
        if (![fileName isKindOfClass:[NSString class]]) continue;
        if (![fileName hasPrefix:@"pendingaction-"] || ![fileName hasSuffix:@".plist"]) continue;
        [paths addObject:[directory stringByAppendingPathComponent:fileName]];
    }
    [paths sortUsingComparator:^NSComparisonResult(NSString *a, NSString *b) {
        NSDate *dateA = [fileManager attributesOfItemAtPath:a error:nil][NSFileModificationDate];
        NSDate *dateB = [fileManager attributesOfItemAtPath:b error:nil][NSFileModificationDate];
        NSComparisonResult byDate = [dateA compare:dateB];
        return byDate != NSOrderedSame ? byDate : [a compare:b];
    }];
    // Defensive cap: a runaway writer must not queue an unbounded backlog.
    // The list is oldest-first, so the oldest overflow is dropped.
    if (paths.count > 64) {
        [paths removeObjectsInRange:NSMakeRange(0, paths.count - 64)];
    }
    return paths;
}

// Session-start hygiene: a request present before the observer exists was
// written by an earlier session (keyboard processes cannot run before
// SpringBoard) or during an upgrade window where the not-yet-resprited
// SpringBoard could not consume the writer's files — such files used to ride
// the NEXT action's drain as a surprise replay. Runs BEFORE the Darwin
// observer is registered so a later notification can only drain post-sweep
// files. Never executes anything.
static void DXSBPurgePendingActionRequests(void) {
    NSMutableArray<NSString *> *paths = DXSBPendingActionRequestPaths();
    for (NSString *path in paths) {
        [[NSFileManager defaultManager] removeItemAtPath:path error:nil];
    }
    if (paths.count > 0) {
        NSLog(@"[TypeX] pendingaction: purged %lu pre-launch request(s)", (unsigned long)paths.count);
    }
}

// Drains every queued request file, oldest first. Requests each get their own
// file because the old single-slot design lost everything but the last write
// of a burst; Darwin notification coalescing is harmless because one delivery
// drains every file present. Delivery itself is the channel's only trigger,
// so a lost delivery used to strand a file until the next action replayed it;
// the guard rails around this drain (session purge at registration, the
// writer-side re-post, the staleness drop, the duplicate merge) exist to make
// that strand harmless instead of a surprise.
static void DXSBDrainPendingActionRequests(void) {
    NSFileManager *fileManager = [NSFileManager defaultManager];
    NSMutableArray<NSString *> *requestPaths = DXSBPendingActionRequestPaths();

    NSDictionary *lastExecuted = nil;
    BOOL launchedSinceGap = NO;
    for (NSString *path in requestPaths) {
        NSDictionary *attributes = [fileManager attributesOfItemAtPath:path error:nil];
        NSDictionary *request = [NSDictionary dictionaryWithContentsOfFile:path];
        // Consume before acting so a replayed notification cannot repeat
        // the open — and unconditionally, so an invalid request can never
        // linger and masquerade as a later action's payload.
        [fileManager removeItemAtPath:path error:nil];
        if (![request isKindOfClass:[NSDictionary class]]) continue;

        NSDate *modified = [attributes isKindOfClass:[NSDictionary class]] ? attributes[NSFileModificationDate] : nil;
        NSTimeInterval age = modified ? -[modified timeIntervalSinceNow] : 0.0;
        if (age > DXSBPendingActionMaxAge) {
            NSLog(@"[TypeX] pendingaction: dropped %.0fs-old stale request", age);
            continue;
        }
        if (lastExecuted && [lastExecuted isEqualToDictionary:request]) {
            // A stranded copy of an action plus the live copy of the same tap
            // land in one drain together; the second execution is redundant.
            NSLog(@"[TypeX] pendingaction: merged duplicate %@", request[@"action"] ?: @"request");
            continue;
        }
        if (DXSBPendingActionWasRecentlyExecuted(request)) {
            NSLog(@"[TypeX] pendingaction: suppressed cross-drain duplicate %@", request[@"action"] ?: @"request");
            continue;
        }

        if (launchedSinceGap) [NSThread sleepForTimeInterval:DXSBPendingActionLaunchGap];
        lastExecuted = request;
        launchedSinceGap = YES;
        DXSBExecutePendingActionRequest(request);
    }
}

static void pendingActionRequestCallback(CFNotificationCenterRef center,
                                         void *observer,
                                         CFStringRef name,
                                         const void *object,
                                         CFDictionaryRef userInfo) {
    // Never the main queue: a busy main thread (catalogue refreshes, Home
    // Screen work) must not delay or blackhole panel actions. openurl/openapp
    // are pure service XPC and act right here; openshortcut is handed to the
    // provider, which performs the SpringBoard model access on the main queue.
    dispatch_async(DXSBPendingActionQueue(), ^{
        DXSBDrainPendingActionRequests();
    });
}

%ctor {
    
    @autoreleasepool {
        
        NSArray *args = [[NSClassFromString(@"NSProcessInfo") processInfo] arguments];
        
        if (args.count != 0){
            NSString *executablePath = args[0];
            if (executablePath){
                NSString *processName = [executablePath lastPathComponent];
                isSpringBoard = [processName isEqualToString:@"SpringBoard"];
                isApplication = [executablePath rangeOfString:@"/Application"].location != NSNotFound;
				isApplication = isApplication ?: ([executablePath rangeOfString:@".appex/"].location != NSNotFound ?: isApplication);
                //isApplication = [processName isEqualToString:@"MarkupPhotoExtension"] ?: isApplication;
                isSafari = [processName isEqualToString:@"MobileSafari"];
				
                if (isSpringBoard || isApplication){
                    tweakBundle = [NSBundle bundleWithPath:bundlePath];
                    [tweakBundle load];
                    firstInit = YES;
                    reloadPrefs();
                    shouldPerformBatchUpdate = YES;
                    %init(TypeX);
                    topToolbarLifecycleObserver = [[DXTopToolbarLifecycleObserver alloc] init];
                    [[NSNotificationCenter defaultCenter] addObserver:topToolbarLifecycleObserver
                                                             selector:@selector(keyboardDidShow:)
                                                                 name:UIKeyboardDidShowNotification
                                                               object:nil];
                    [[NSNotificationCenter defaultCenter] addObserver:topToolbarLifecycleObserver
                                                             selector:@selector(keyboardWillHide:)
                                                                 name:UIKeyboardWillHideNotification
                                                               object:nil];
                    CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(), NULL, reloadPrefsNotificationCallback, (CFStringRef)kPrefsChangedIdentifier, NULL, CFNotificationSuspensionBehaviorDeliverImmediately);
                    if (isSpringBoard) {
                        // Clear requests carried over from an earlier session
                        // or an upgrade window BEFORE the observer exists (see
                        // the purge comment) — they must never execute here.
                        DXSBPurgePendingActionRequests();
                        // Only SpringBoard consumes 打开应用 requests; other
                        // processes ignore the notification entirely.
                        CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(), NULL, pendingActionRequestCallback, (CFStringRef)kPendingActionRequestIdentifier, NULL, CFNotificationSuspensionBehaviorDeliverImmediately);
                        CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(), NULL, shortcutRefreshRequestCallback, (CFStringRef)kShortcutRefreshRequestIdentifier, NULL, CFNotificationSuspensionBehaviorDeliverImmediately);
                    }
                }
            }
        }
    }
}
