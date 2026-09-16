#import "common.h"
#import "TypeX.h"
#import "DXShared.h"
#import "DXHelper.h"
#import <objc/runtime.h>
#import <objc/message.h>
#import <dlfcn.h>
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

static void DXSBOpenApplicationShortcut(NSString *bundleIdentifier, NSString *shortcutType);
static void DXSBRefreshShortcutSnapshots(NSArray<NSString *> *bundleIdentifiers);
static NSArray<NSString *> *DXSBAllInstalledBundleIdentifiers(void);

static void DXSBWriteShortcutRefreshStatus(NSString *phase, NSDictionary *details) {
    if (phase.length == 0) return;
    NSMutableDictionary *status = [NSMutableDictionary dictionaryWithDictionary:details ?: @{}];
    status[@"phase"] = phase;
    status[@"updated"] = @([NSDate timeIntervalSinceReferenceDate]);
    [status writeToFile:TypeXShortcutRefreshStatusPath atomically:YES];
}

static void shortcutRefreshRequestCallback(CFNotificationCenterRef center,
                                           void *observer,
                                           CFStringRef name,
                                           const void *object,
                                           CFDictionaryRef userInfo) {
    NSDictionary *request = [NSDictionary dictionaryWithContentsOfFile:TypeXShortcutRefreshRequestPath];
    DXSBWriteShortcutRefreshStatus(@"request-received", nil);
    NSArray *rawBundles = [request[@"bundles"] isKindOfClass:[NSArray class]] ? request[@"bundles"] : nil;
    if (rawBundles.count > 2048) rawBundles = nil;
    // Consume the request whatever it contained; an unrecognized one is inert.
    [[NSFileManager defaultManager] removeItemAtPath:TypeXShortcutRefreshRequestPath error:nil];

    NSMutableOrderedSet<NSString *> *bundleIdentifiers = [NSMutableOrderedSet orderedSet];
    for (id value in rawBundles) {
        if (DXIsValidBundleIdentifier(value)) [bundleIdentifiers addObject:value];
    }
    // The catalogue pipeline is the same on every OS version, so an empty
    // bundle list (the picker can no longer enumerate on some iOS versions)
    // is always filled from SpringBoard's own Launch Services.
    if (bundleIdentifiers.count == 0) {
        [bundleIdentifiers addObjectsFromArray:DXSBAllInstalledBundleIdentifiers()];
    }
    if (bundleIdentifiers.count == 0) {
        NSLog(@"[TypeX] sbshortcuts: refresh request with no enumerable applications");
        return;
    }
    DXSBRefreshShortcutSnapshots(bundleIdentifiers.array);
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
// main thread (catalogue refreshes, Home Screen work) must not delay or
// blackhole panel actions. openurl/openapp are pure service XPC and act right
// here; openshortcut touches icon views and hops to main for that part.
static dispatch_queue_t DXSBPendingActionQueue(void) {
    static dispatch_queue_t queue;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        queue = dispatch_queue_create("com.lindo.typex.pendingaction", DISPATCH_QUEUE_SERIAL);
    });
    return queue;
}

// Executes one already-consumed request. Pure service XPC runs right here on
// the serial queue; openshortcut touches icon views and hops to main.
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
        dispatch_async(dispatch_get_main_queue(), ^{
            DXSBOpenApplicationShortcut(bundle, shortcutType);
        });
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
    // are pure service XPC and act right here; openshortcut hops to main for
    // the icon-view part.
    dispatch_async(DXSBPendingActionQueue(), ^{
        DXSBDrainPendingActionRequests();
    });
}

// ===========================================================================
// Icon-menu quick-action capture (SpringBoard only)
// ---------------------------------------------------------------------------
// The Settings-side picker enumerates quick actions from bundle metadata
// (static), app-container preferences (dynamic) and App Intents metadata,
// but the menu the user actually long-presses is merged inside SpringBoard
// from those sources plus system-only entries (suggestions), and only
// SpringBoard sees the final list.  Two hooks observe the menu's real data
// source at the moment the menu is being built for one specific icon —
// SBIconView.effectiveApplicationShortcutItems (the final model list the
// menu renders) and SBIconController's
// iconManager:applicationShortcutItemsForIconView: (the delegate the icon
// manager asks) — and persist the normalized items, keyed by bundle ID,
// into the shared snapshot (TypeXSBShortcutsPath) for the Settings picker.
//
// The setApplicationShortcutItems: setter is deliberately NOT hooked:
// SBIconView instances are recycled across icons in the grid, so a setter
// call cannot be attributed to a bundle ID with certainty, while both
// chosen hooks fire with the menu's icon fixed.  Hooks resolve at runtime
// and degrade to no-ops on systems where a symbol is missing.

// Reads one property through a respondsToSelector-guarded objc_msgSend —
// items arrive as SBSApplicationShortcutItem but stay decodable even if the
// class changes, and a missing property must read as nil, never throw.
static NSString *DXSBReadStringProperty(id object, NSString *propertyName) {
    SEL selector = NSSelectorFromString(propertyName);
    if (![object respondsToSelector:selector]) return nil;
    NSString *value = ((NSString *(*)(id, SEL))objc_msgSend)(object, selector);
    return [value isKindOfClass:[NSString class]] ? value : nil;
}

static BOOL DXSBReadBoolProperty(id object, NSString *propertyName) {
    SEL selector = NSSelectorFromString(propertyName);
    if (![object respondsToSelector:selector]) return NO;
    return ((BOOL (*)(id, SEL))objc_msgSend)(object, selector);
}

static id DXSBReadObjectProperty(id object, NSString *propertyName) {
    SEL selector = NSSelectorFromString(propertyName);
    if (!object || ![object respondsToSelector:selector]) return nil;
    return ((id (*)(id, SEL))objc_msgSend)(object, selector);
}

static NSString *DXSBBundleIdentifierForIconView(id iconView);
static id DXSBSBApplicationForBundleIdentifier(NSString *bundleIdentifier);
static NSString *DXSBDisplayNameForBundleIdentifier(NSString *bundleIdentifier);
static NSArray *DXSBSBApplicationShortcutItems(NSString *bundleIdentifier);

// The complete objects from the most recent real icon-menu build are kept in
// SpringBoard memory as a fallback for systems where the catalogue service's
// synchronous fetch selector is unavailable. The persistent Settings snapshot
// remains plist-only; runtime payloads are never flattened and reconstructed
// when the original object is still available.
static NSMutableDictionary<NSString *, NSArray *> *DXSBLiveShortcutObjectsByBundleID;
static NSMapTable<NSString *, id> *DXSBLiveIconViewsByBundleID;

static NSArray *DXSBLaunchableShortcutItems(NSArray *items) {
    if (![items isKindOfClass:[NSArray class]]) return @[];
    NSMutableArray *result = [NSMutableArray array];
    NSMutableSet<NSString *> *seen = [NSMutableSet set];
    for (id item in items) {
        NSString *type = DXSBReadStringProperty(item, @"type");
        if (type.length == 0 || [seen containsObject:type]) continue;
        if (DXSBReadBoolProperty(item, @"sbh_isDestructive")) continue;
        if ([type hasPrefix:@"com.apple.springboard."]) continue;
        [seen addObject:type];
        [result addObject:item];
    }
    return result;
}

static void DXSBRememberLiveShortcutItems(NSArray *items, NSString *bundleIdentifier) {
    if (bundleIdentifier.length == 0) return;
    NSArray *launchable = DXSBLaunchableShortcutItems(items);
    if (launchable.count == 0) return;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        DXSBLiveShortcutObjectsByBundleID = [NSMutableDictionary dictionary];
    });
    DXSBLiveShortcutObjectsByBundleID[bundleIdentifier] = [launchable copy];
}

static void DXSBRememberIconView(id iconView, NSString *bundleIdentifier) {
    if (!iconView || bundleIdentifier.length == 0) return;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        DXSBLiveIconViewsByBundleID = [NSMapTable strongToWeakObjectsMapTable];
    });
    [DXSBLiveIconViewsByBundleID setObject:iconView forKey:bundleIdentifier];
}

// Finds the same SBIconView SpringBoard uses for a Home Screen icon. The map
// covers icons on other pages as well; when an app is App-Library-only the
// result can be nil, which the confirmed activation entry accepts.
static id DXSBIconViewForBundleIdentifier(NSString *bundleIdentifier) {
    id cached = [DXSBLiveIconViewsByBundleID objectForKey:bundleIdentifier];
    if ([DXSBBundleIdentifierForIconView(cached) isEqualToString:bundleIdentifier]) return cached;

    Class controllerClass = NSClassFromString(@"SBIconController");
    SEL sharedSelector = NSSelectorFromString(@"sharedInstance");
    id controller = [controllerClass respondsToSelector:sharedSelector]
        ? ((id (*)(id, SEL))objc_msgSend)(controllerClass, sharedSelector) : nil;
    id model = DXSBReadObjectProperty(controller, @"model")
        ?: DXSBReadObjectProperty(controller, @"iconModel");
    SEL iconSelector = NSSelectorFromString(@"applicationIconForBundleIdentifier:");
    id icon = [model respondsToSelector:iconSelector]
        ? ((id (*)(id, SEL, id))objc_msgSend)(model, iconSelector, bundleIdentifier) : nil;
    if (!icon) return nil;

    id viewMap = DXSBReadObjectProperty(controller, @"homescreenIconViewMap")
        ?: DXSBReadObjectProperty(controller, @"iconViewMap");
    id iconView = nil;
    for (NSString *selectorName in @[@"iconViewForIcon:", @"_iconViewForIcon:"]) {
        SEL selector = NSSelectorFromString(selectorName);
        if (![viewMap respondsToSelector:selector]) continue;
        iconView = ((id (*)(id, SEL, id))objc_msgSend)(viewMap, selector, icon);
        if (iconView) break;
    }
    if (iconView) DXSBRememberIconView(iconView, bundleIdentifier);
    return iconView;
}

// Reads an icon view's current rendered menu and optionally asks SpringBoard
// to populate it. iOS 16 exposes the returning fetch selector while newer
// builds use the asynchronous "IfAppropriate" form, so both are invoked only
// when present and all results are read back through the public object graph.
static NSArray *DXSBShortcutItemsFromIconView(id iconView, BOOL requestFetch) {
    if (!iconView) return @[];
    for (NSString *property in @[@"effectiveApplicationShortcutItems", @"applicationShortcutItems"]) {
        NSArray *items = DXSBLaunchableShortcutItems(DXSBReadObjectProperty(iconView, property));
        if (items.count > 0) return items;
    }
    if (!requestFetch) return @[];

    SEL returningFetch = NSSelectorFromString(@"_fetchApplicationShortcutItems");
    if ([iconView respondsToSelector:returningFetch]) {
        @try {
            id fetched = ((id (*)(id, SEL))objc_msgSend)(iconView, returningFetch);
            NSArray *items = DXSBLaunchableShortcutItems(fetched);
            if (items.count > 0) return items;
        } @catch (__unused NSException *exception) {}
    }
    SEL asynchronousFetch = NSSelectorFromString(@"_fetchApplicationShortcutItemsIfAppropriate");
    if ([iconView respondsToSelector:asynchronousFetch]) {
        @try {
            ((void (*)(id, SEL))objc_msgSend)(iconView, asynchronousFetch);
        } @catch (__unused NSException *exception) {}
    }
    return @[];
}

static SBSApplicationShortcutItem *DXSBShortcutItemWithType(NSArray *items, NSString *shortcutType) {
    for (id item in items) {
        NSString *type = DXSBReadStringProperty(item, @"type");
        if ([type isEqualToString:shortcutType]) return item;
    }
    return nil;
}

// Use the exact SpringBoard entry invoked by a real long-press menu tap. It
// routes both UIApplicationShortcutItem and App Intents-backed actions;
// merely placing an item in FrontBoard launch options does not perform this
// activation on iOS 16/17. Which receiver carries the method shifted across
// iOS builds (the icon view instance, the shortcut item itself, or a class
// helper), so all three are probed — a missing symbol must degrade to
// "not activated", never crash.
static BOOL DXSBActivateApplicationShortcut(NSString *bundleIdentifier,
                                            SBSApplicationShortcutItem *item,
                                            id iconView) {
    if (!item || bundleIdentifier.length == 0) return NO;
    if ([item respondsToSelector:@selector(setBundleIdentifierToLaunch:)]) {
        item.bundleIdentifierToLaunch = bundleIdentifier;
    }
    SEL selector = NSSelectorFromString(@"activateShortcut:withBundleIdentifier:forIconView:");

    if (iconView && [iconView respondsToSelector:selector]) {
        @try {
            ((void (*)(id, SEL, id, id, id))objc_msgSend)(
                iconView, selector, item, bundleIdentifier, iconView);
            return YES;
        } @catch (NSException *exception) {
            NSLog(@"[TypeX] shortcut: iconView activation failed for %@/%@ (%@)",
                  bundleIdentifier, item.type ?: @"", exception);
        }
    }
    if ([item respondsToSelector:selector]) {
        @try {
            ((void (*)(id, SEL, id, id, id))objc_msgSend)(
                item, selector, item, bundleIdentifier, iconView);
            return YES;
        } @catch (NSException *exception) {
            NSLog(@"[TypeX] shortcut: item activation failed for %@/%@ (%@)",
                  bundleIdentifier, item.type ?: @"", exception);
        }
    }
    Class iconViewClass = NSClassFromString(@"SBIconView");
    if (iconViewClass && [iconViewClass respondsToSelector:selector]) {
        @try {
            ((void (*)(id, SEL, id, id, id))objc_msgSend)(
                iconViewClass, selector, item, bundleIdentifier, iconView);
            return YES;
        } @catch (NSException *exception) {
            NSLog(@"[TypeX] shortcut: class activation failed for %@/%@ (%@)",
                  bundleIdentifier, item.type ?: @"", exception);
        }
    }
    return NO;
}

static void DXSBOpenApplicationShortcut(NSString *bundleIdentifier, NSString *shortcutType) {
    id iconView = DXSBIconViewForBundleIdentifier(bundleIdentifier);
    NSArray *viewItems = DXSBShortcutItemsFromIconView(iconView, YES);
    SBSApplicationShortcutItem *viewItem = DXSBShortcutItemWithType(viewItems, shortcutType);
    if (!viewItem) {
        viewItem = DXSBShortcutItemWithType(DXSBLiveShortcutObjectsByBundleID[bundleIdentifier], shortcutType);
    }
    // The resolved application object is the same source the catalogue is
    // built from; its items dispatch identically through the activation entry.
    if (!viewItem) {
        viewItem = DXSBShortcutItemWithType(DXSBSBApplicationShortcutItems(bundleIdentifier), shortcutType);
    }
    if (viewItem) {
        DXSBActivateApplicationShortcut(bundleIdentifier, viewItem, iconView);
        return;
    }

    // The app declares no such item any more; still launch through the same
    // entry with its stored type so an entry keeps working until the next
    // catalogue refresh drops or renames it.
    dispatch_async(dispatch_get_main_queue(), ^{
        Class itemClass = NSClassFromString(@"SBSApplicationShortcutItem");
        SBSApplicationShortcutItem *item = [[itemClass alloc] init];
        item.type = shortcutType;
        item.localizedTitle = shortcutType;
        item.bundleIdentifierToLaunch = bundleIdentifier;
        if (!DXSBActivateApplicationShortcut(bundleIdentifier, item, iconView)) {
            NSLog(@"[TypeX] shortcut: SBIconView activation entry unavailable for %@/%@",
                  bundleIdentifier, shortcutType);
        }
    });
}

// Bundle ID of the app whose menu is being built.  Prefers the view's own
// shortcut-scoped accessor, then falls back to its icon (SBIcon).
static NSString *DXSBBundleIdentifierForIconView(id iconView) {
    if (!iconView) return nil;
    NSString *bundleID = DXSBReadStringProperty(iconView, @"applicationBundleIdentifierForShortcuts");
    if (bundleID.length > 0) return bundleID;

    SEL iconSelector = NSSelectorFromString(@"icon");
    if ([iconView respondsToSelector:iconSelector]) {
        id icon = ((id (*)(id, SEL))objc_msgSend)(iconView, iconSelector);
        if (icon) {
            bundleID = DXSBReadStringProperty(icon, @"applicationBundleID");
            if (bundleID.length > 0) return bundleID;
        }
    }
    return nil;
}

// Normalizes one captured menu list into storable dictionaries.  System
// chrome rows (移除应用/分享应用/编辑主屏幕) are dropped three ways: they carry
// no dispatch type, mark themselves destructive through the SBH addition,
// or use a SpringBoard-owned type prefix — only real app shortcut items,
// which dispatch through application:performActionForShortcutItem:, stay.
static NSArray *DXSBNormalizedShortcutItems(NSArray *items) {
    if (![items isKindOfClass:[NSArray class]]) return nil;
    NSMutableArray *normalized = [NSMutableArray array];
    NSMutableSet<NSString *> *seen = [NSMutableSet set];
    for (id item in items) {
        NSString *type = DXSBReadStringProperty(item, @"type");
        if (type.length == 0) continue;
        if (DXSBReadBoolProperty(item, @"sbh_isDestructive")) continue;
        if ([type hasPrefix:@"com.apple.springboard."]) continue;
        if ([seen containsObject:type]) continue;
        [seen addObject:type];

        NSString *title = DXSBReadStringProperty(item, @"localizedTitle")
            ?: DXSBReadStringProperty(item, @"title");
        NSString *subtitle = DXSBReadStringProperty(item, @"localizedSubtitle")
            ?: DXSBReadStringProperty(item, @"subtitle");
        NSMutableDictionary *entry = [NSMutableDictionary dictionary];
        entry[@"type"] = type;
        entry[@"title"] = title.length > 0 ? title : type;
        if (subtitle.length > 0) entry[@"subtitle"] = subtitle;
        [normalized addObject:entry];
    }
    return normalized.count > 0 ? normalized : nil;
}

// Persists one capture.  Hooks fire on the main thread with the menu on
// screen, so writes stay tiny, atomic, content-deduplicated per bundle and
// rate-limited — an unchanged list never rewrites the file.
static void DXSBCaptureShortcutItems(NSArray *items, NSString *bundleID) {
    if (bundleID.length == 0) return;
    DXSBRememberLiveShortcutItems(items, bundleID);
    NSArray *normalized = DXSBNormalizedShortcutItems(items);
    if (!normalized) return;

    static NSMutableDictionary<NSString *, NSDictionary *> *captureState;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        captureState = [NSMutableDictionary dictionary];
    });

    NSString *signature = [normalized description];
    NSDictionary *previous = captureState[bundleID];
    NSTimeInterval now = [NSDate timeIntervalSinceReferenceDate];
    if (previous) {
        BOOL unchanged = [previous[@"signature"] isEqualToString:signature];
        BOOL recent = now - [previous[@"time"] doubleValue] < 2.0;
        if (unchanged || recent) return;
    }
    captureState[bundleID] = @{@"signature": signature, @"time": @(now)};

    @try {
        NSMutableDictionary *root = [[NSDictionary dictionaryWithContentsOfFile:TypeXSBShortcutsPath] mutableCopy]
            ?: [NSMutableDictionary dictionary];
        NSMutableDictionary *apps = [root[@"apps"] mutableCopy] ?: [NSMutableDictionary dictionary];
        NSMutableDictionary *entry = [NSMutableDictionary dictionary];
        entry[@"items"] = normalized;
        entry[@"updated"] = @(now);
        NSString *displayName = DXSBDisplayNameForBundleIdentifier(bundleID);
        if (displayName.length > 0) entry[@"name"] = displayName;
        apps[bundleID] = entry;
        root[@"apps"] = apps;
        root[@"format"] = @2;
        if ([root writeToFile:TypeXSBShortcutsPath atomically:YES]) {
            CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(),
                                                 (__bridge CFStringRef)kShortcutSnapshotChangedIdentifier,
                                                 NULL, NULL, YES);
        }
    } @catch (NSException *exception) {
        NSLog(@"[TypeX] sbshortcuts: write failed for %@ (%@)", bundleID, exception);
    }
}

// Launch Services is not linked into SpringBoard — the LSApplication* classes
// only exist after the framework is pulled in (iOS 16 SB never loads it on
// its own; Settings needs the same dlopen). Without this, both LS
// enumeration fallbacks silently find no class and the catalogue stays empty.
static void DXSBEnsureLaunchServicesLoaded(void) {
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        for (NSString *path in @[
            @"/System/Library/Frameworks/MobileCoreServices.framework/MobileCoreServices",
            @"/System/Library/Frameworks/CoreServices.framework/CoreServices",
            @"/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/LaunchServices",
        ]) {
            dlopen(path.fileSystemRepresentation, RTLD_LAZY | RTLD_LOCAL);
            if (NSClassFromString(@"LSApplicationWorkspace")) break;
        }
    });
}

// Every installed application from SpringBoard's own Launch Services — the
// authoritative enumeration when Settings could not provide a bundle list.
// Primary is the reference tweak's two-pass enumeration: enumerateApplicationsOfType:
// asked once for system (0) and once for user (1) apps, merged. The block
// runs synchronously, so results are complete when the call returns, and it
// answers on every iOS version — the whole-array fetch below answers only
// where Launch Services is already warm (iOS 17) and blocks indefinitely
// where it is not (iOS 16), so it is kept purely as a fallback.  The last
// resort is SBApplicationController.allApplications (verified in the iOS
// 14.5 SpringBoard dump; the icon model's collection selector was a guess
// that does not exist there).
static NSArray<NSString *> *DXSBAllInstalledBundleIdentifiers(void) {
    NSMutableOrderedSet<NSString *> *result = [NSMutableOrderedSet orderedSet];
    DXSBEnsureLaunchServicesLoaded();
    Class workspaceClass = NSClassFromString(@"LSApplicationWorkspace");
    SEL workspaceSelector = NSSelectorFromString(@"defaultWorkspace");
    if (workspaceClass && [workspaceClass respondsToSelector:workspaceSelector]) {
        @try {
            id workspace = ((id (*)(id, SEL))objc_msgSend)(workspaceClass, workspaceSelector);
            SEL enumerateSelector = NSSelectorFromString(@"enumerateApplicationsOfType:block:");
            if (workspace && [workspace respondsToSelector:enumerateSelector]) {
                for (NSUInteger type = 0; type <= 1 && result.count < 2048; type++) {
                    ((void (*)(id, SEL, NSUInteger, void (^)(id)))objc_msgSend)(
                        workspace, enumerateSelector, type, ^(id proxy) {
                            if (result.count >= 2048) return;
                            NSString *bundleID = DXSBReadStringProperty(proxy, @"applicationIdentifier")
                                ?: DXSBReadStringProperty(proxy, @"bundleIdentifier");
                            if (bundleID.length > 0) [result addObject:bundleID];
                        });
                }
            }
        } @catch (NSException *exception) {
            NSLog(@"[TypeX] sbshortcuts: typed application enumeration failed (%@)", exception);
        }
    }
    if (result.count == 0) {
        SEL appsSelector = NSSelectorFromString(@"allInstalledApplications");
        @try {
            id workspace = workspaceClass && [workspaceClass respondsToSelector:workspaceSelector]
                ? ((id (*)(id, SEL))objc_msgSend)(workspaceClass, workspaceSelector) : nil;
            NSArray *proxies = (workspace && [workspace respondsToSelector:appsSelector])
                ? ((id (*)(id, SEL))objc_msgSend)(workspace, appsSelector) : nil;
            for (id proxy in proxies) {
                NSString *bundleID = DXSBReadStringProperty(proxy, @"applicationIdentifier")
                    ?: DXSBReadStringProperty(proxy, @"bundleIdentifier");
                if (bundleID.length == 0) continue;
                [result addObject:bundleID];
                if (result.count >= 2048) break;
            }
        } @catch (NSException *exception) {
            NSLog(@"[TypeX] sbshortcuts: application enumeration failed (%@)", exception);
        }
    }
    if (result.count == 0) {
        // SBApplicationController.allApplications — SpringBoard's own app
        // registry, present since iOS 14 (verified in the 14.5 dump).
        Class controllerClass = NSClassFromString(@"SBApplicationController");
        SEL sharedSelector = NSSelectorFromString(@"sharedInstance");
        id controller = [controllerClass respondsToSelector:sharedSelector]
            ? ((id (*)(id, SEL))objc_msgSend)(controllerClass, sharedSelector) : nil;
        SEL appsSelector = NSSelectorFromString(@"allApplications");
        NSArray *applications = (controller && [controller respondsToSelector:appsSelector])
            ? ((id (*)(id, SEL))objc_msgSend)(controller, appsSelector) : nil;
        for (id application in [applications isKindOfClass:[NSArray class]] ? applications : @[]) {
            NSString *bundleID = DXSBReadStringProperty(application, @"bundleIdentifier")
                ?: DXSBReadStringProperty(application, @"applicationIdentifier");
            if (bundleID.length == 0) continue;
            [result addObject:bundleID];
            if (result.count >= 2048) break;
        }
    }
    return result.array;
}

// The Home Screen menu's own data source — the approach the reference
// gesture tweak uses: SBApplicationController hands out the system-resolved
// SBApplication for a bundle identifier, whose info carries the static items
// (Info.plist, localized through SBApplicationInfo) alongside the runtime
// dynamic cache. Available since iOS 14, synchronous, already localized, and
// it needs neither a menu fetch round-trip nor any Launch Services work in
// the Settings process. This is the catalogue's primary metadata source.
static id DXSBSBApplicationController(void) {
    static id applicationController;
    if (!applicationController) {
        @synchronized([NSProcessInfo class]) {
            if (!applicationController) {
                Class controllerClass = NSClassFromString(@"SBApplicationController");
                SEL sharedSelector = NSSelectorFromString(@"sharedInstance");
                id resolvedController = [controllerClass respondsToSelector:sharedSelector]
                    ? ((id (*)(id, SEL))objc_msgSend)(controllerClass, sharedSelector) : nil;
                // Do not permanently cache an early nil. SpringBoardHome can
                // still be loading when TypeX's constructor runs on iOS 16;
                // the next Settings refresh must resolve the controller again.
                if (resolvedController) applicationController = resolvedController;
            }
        }
    }
    return applicationController;
}

static id DXSBSBApplicationForBundleIdentifier(NSString *bundleIdentifier) {
    id applicationController = DXSBSBApplicationController();
    if (!applicationController) return nil;
    SEL appSelector = NSSelectorFromString(@"applicationWithBundleIdentifier:");
    if (![applicationController respondsToSelector:appSelector]) return nil;
    return ((id (*)(id, SEL, id))objc_msgSend)(applicationController, appSelector, bundleIdentifier);
}

// Localized display name straight from the resolved application object, so
// the shared catalogue names its groups without the reader enumerating apps.
static NSString *DXSBDisplayNameForBundleIdentifier(NSString *bundleIdentifier) {
    id app = DXSBSBApplicationForBundleIdentifier(bundleIdentifier);
    if (!app) return nil;
    NSString *name = DXSBReadStringProperty(app, @"displayName")
        ?: DXSBReadStringProperty(app, @"applicationDisplayName");
    return name.length > 0 ? name : nil;
}

// Lightweight carrier for metadata-scanned entries: same selector surface
// (type / localizedTitle / localizedSubtitle) as SBSApplicationShortcutItem,
// so the launchable filter and catalogue normalization read it unchanged.
@interface DXSBMetadataShortcutItem : NSObject
@property (nonatomic, copy) NSString *type;
@property (nonatomic, copy) NSString *localizedTitle;
@property (nonatomic, copy) NSString *localizedSubtitle;
@end

@implementation DXSBMetadataShortcutItem
@end

// The bundle-metadata scanners below are the proven Settings-side sources
// (static Info.plist items, UIKit-persisted dynamic items, App Intents
// build metadata), ported to run inside SpringBoard. They are the universal
// fallback for apps whose SBApplication model answers nothing — frequent
// enough on some iOS builds (notably iOS 16) to empty the catalogue without
// it — and run on every OS version.

static id DXSBProxyForBundleIdentifier(NSString *bundleIdentifier) {
    DXSBEnsureLaunchServicesLoaded();
    Class proxyClass = NSClassFromString(@"LSApplicationProxy");
    SEL proxySelector = NSSelectorFromString(@"applicationProxyForIdentifier:");
    if (!proxyClass || ![proxyClass respondsToSelector:proxySelector]) return nil;
    return ((id (*)(id, SEL, id))objc_msgSend)(proxyClass, proxySelector, bundleIdentifier);
}

static NSArray *DXSBStaticShortcutItemsFromProxy(id proxy) {
    NSDictionary *info = DXSBReadObjectProperty(proxy, @"infoDictionary");
    if (![info isKindOfClass:[NSDictionary class]] || info.count == 0) {
        NSURL *bundleURL = DXSBReadObjectProperty(proxy, @"bundleURL");
        if (![bundleURL isKindOfClass:[NSURL class]]) return @[];
        info = [NSDictionary dictionaryWithContentsOfURL:[bundleURL URLByAppendingPathComponent:@"Info.plist"]];
    }
    NSArray *rawItems = [info isKindOfClass:[NSDictionary class]] ? info[@"UIApplicationShortcutItems"] : nil;
    if (![rawItems isKindOfClass:[NSArray class]]) return @[];

    NSURL *bundleURL = DXSBReadObjectProperty(proxy, @"bundleURL");
    NSBundle *stringsBundle = [bundleURL isKindOfClass:[NSURL class]] ? [NSBundle bundleWithURL:bundleURL] : nil;
    NSMutableArray *results = [NSMutableArray array];
    NSMutableSet<NSString *> *seen = [NSMutableSet set];
    for (NSDictionary *item in rawItems) {
        if (![item isKindOfClass:[NSDictionary class]]) continue;
        NSString *type = [item[@"UIApplicationShortcutItemType"] isKindOfClass:[NSString class]] ? item[@"UIApplicationShortcutItemType"] : nil;
        NSString *titleKey = [item[@"UIApplicationShortcutItemTitle"] isKindOfClass:[NSString class]] ? item[@"UIApplicationShortcutItemTitle"] : nil;
        if (type.length == 0 && titleKey.length == 0) continue;
        if (type.length == 0) type = titleKey;

        NSString *title = nil;
        if (titleKey.length > 0 && stringsBundle) {
            title = [stringsBundle localizedStringForKey:titleKey value:titleKey table:@"InfoPlist"];
        }
        NSString *subtitleKey = [item[@"UIApplicationShortcutItemSubtitle"] isKindOfClass:[NSString class]] ? item[@"UIApplicationShortcutItemSubtitle"] : nil;
        NSString *subtitle = nil;
        if (subtitleKey.length > 0 && stringsBundle) {
            subtitle = [stringsBundle localizedStringForKey:subtitleKey value:subtitleKey table:@"InfoPlist"];
            if (subtitle.length == 0) subtitle = subtitleKey;
        }

        NSString *fingerprint = [NSString stringWithFormat:@"%@|%@|%@", type, titleKey ?: @"", subtitleKey ?: @""];
        if ([seen containsObject:fingerprint]) continue;
        [seen addObject:fingerprint];

        DXSBMetadataShortcutItem *entry = [[DXSBMetadataShortcutItem alloc] init];
        entry.type = type;
        entry.localizedTitle = title.length > 0 ? title : (titleKey.length > 0 ? titleKey : type);
        entry.localizedSubtitle = subtitle;
        [results addObject:entry];
    }
    return results;
}

static NSArray *DXSBDynamicShortcutItemsFromProxy(id proxy, NSString *bundleIdentifier) {
    NSURL *containerURL = DXSBReadObjectProperty(proxy, @"dataContainerURL");
    if (![containerURL isKindOfClass:[NSURL class]]) return @[];

    NSString *prefsPath = [[containerURL URLByAppendingPathComponent:@"Library/Preferences"]
        URLByAppendingPathComponent:[NSString stringWithFormat:@"%@.plist", bundleIdentifier]].path;
    NSDictionary *prefs = [NSDictionary dictionaryWithContentsOfFile:prefsPath];
    if (![prefs isKindOfClass:[NSDictionary class]]) return @[];
    id payload = prefs[@"UIApplicationShortcutItems"];
    if (!payload) return @[];

    // Accept every shape UIKit has used: a plain array of dictionaries, a
    // single encoded blob, or a mix. Anything undecodable is dropped.
    NSMutableArray *entries = [NSMutableArray array];
    void (^collect)(id, NSMutableArray *) = ^(id entry, NSMutableArray *outItems) {
        if ([entry isKindOfClass:[NSDictionary class]] ||
            [entry isKindOfClass:[UIApplicationShortcutItem class]]) [outItems addObject:entry];
    };
    id (^decode)(NSData *) = ^(NSData *data) {
        NSSet *classes = [NSSet setWithArray:@[
            [NSArray class], [NSDictionary class], [NSString class], [NSNumber class],
            [NSURL class], [NSData class], [NSDate class], [UIApplicationShortcutItem class],
        ]];
        return [NSKeyedUnarchiver unarchivedObjectOfClasses:classes fromData:data error:nil];
    };
    if ([payload isKindOfClass:[NSArray class]]) {
        for (id entry in payload) {
            if ([entry isKindOfClass:[NSData class]]) {
                id decoded = decode(entry);
                if ([decoded isKindOfClass:[NSArray class]]) for (id sub in decoded) collect(sub, entries);
                else collect(decoded, entries);
            } else {
                collect(entry, entries);
            }
        }
    } else if ([payload isKindOfClass:[NSData class]]) {
        id decoded = decode(payload);
        if ([decoded isKindOfClass:[NSArray class]]) for (id sub in decoded) collect(sub, entries);
        else collect(decoded, entries);
    }
    if (entries.count == 0) return @[];

    NSMutableArray *results = [NSMutableArray array];
    NSMutableSet<NSString *> *seen = [NSMutableSet set];
    for (id item in entries) {
        NSString *type = nil, *title = nil, *subtitle = nil;
        if ([item isKindOfClass:[NSDictionary class]]) {
            NSDictionary *entry = item;
            type = [entry[@"UIApplicationShortcutItemType"] isKindOfClass:[NSString class]] ? entry[@"UIApplicationShortcutItemType"] : nil;
            title = [entry[@"UIApplicationShortcutItemTitle"] isKindOfClass:[NSString class]] ? entry[@"UIApplicationShortcutItemTitle"] : nil;
            subtitle = [entry[@"UIApplicationShortcutItemSubtitle"] isKindOfClass:[NSString class]] ? entry[@"UIApplicationShortcutItemSubtitle"] : nil;
        } else {
            UIApplicationShortcutItem *entry = item;
            type = entry.type;
            title = entry.localizedTitle;
            subtitle = entry.localizedSubtitle;
        }
        if (type.length == 0 || [seen containsObject:type]) continue;
        [seen addObject:type];

        DXSBMetadataShortcutItem *result = [[DXSBMetadataShortcutItem alloc] init];
        result.type = type;
        result.localizedTitle = title.length > 0 ? title : type;
        result.localizedSubtitle = subtitle;
        [results addObject:result];
    }
    return results;
}

// App Shortcuts build metadata (appintentsmetadataprocessor output): the
// autoShortcuts of Metadata.appintents/extract.actionsdata in the app root,
// PlugIns/*.appex and Frameworks/*.framework. Titles are localization keys;
// .loctable resources are parsed manually (NSBundle does not resolve them on
// iOS 15/16), with Chinese scripts folded onto CN/TW regions.
static NSString *DXSBBestLocaleForLoctable(NSDictionary *table) {
    if (![table isKindOfClass:[NSDictionary class]] || table.count == 0) return nil;
    NSMutableDictionary *byLowercase = [NSMutableDictionary dictionary];
    for (NSString *key in table) byLowercase[key.lowercaseString] = key;

    for (NSString *language in [NSLocale preferredLanguages]) {
        NSArray *parts = [[language stringByReplacingOccurrencesOfString:@"-" withString:@"_"]
            componentsSeparatedByString:@"_"];
        if (parts.count == 0) continue;
        NSString *base = ((NSString *)parts[0]).lowercaseString;

        NSMutableArray *candidates = [NSMutableArray array];
        if (parts.count >= 3) {
            NSString *script = ((NSString *)parts[1]).lowercaseString;
            NSString *region = [script isEqualToString:@"hans"] ? @"cn" : ([script isEqualToString:@"hant"] ? @"tw" : nil);
            if (region) [candidates addObject:[NSString stringWithFormat:@"%@_%@", base, region]];
        }
        if (parts.count >= 2) [candidates addObject:[NSString stringWithFormat:@"%@_%@", base, ((NSString *)parts[1]).lowercaseString]];
        [candidates addObject:base];

        for (NSString *candidate in candidates) {
            NSString *match = byLowercase[candidate];
            if (match) return match;
        }
    }
    return byLowercase[@"en"] ?: byLowercase[@"en_us"];
}

static NSString *DXSBLocalizedAppIntentTitle(NSString *key, NSBundle *bundle, NSArray *loctables) {
    if (key.length == 0) return nil;
    if (bundle) {
        for (NSString *tableName in @[@"AppIntents", @"Localizable"]) {
            NSString *value = [bundle localizedStringForKey:key value:nil table:tableName];
            if ([value isKindOfClass:[NSString class]] && value.length > 0 && ![value isEqualToString:key]) return value;
        }
    }
    for (NSDictionary *table in loctables) {
        NSString *locale = DXSBBestLocaleForLoctable(table);
        if (!locale) continue;
        NSString *value = [table isKindOfClass:[NSDictionary class]] ? table[locale][key] : nil;
        if ([value isKindOfClass:[NSString class]] && value.length > 0) return value;
    }
    return key;
}

static NSArray *DXSBAppIntentShortcutItemsFromProxy(id proxy) {
    NSURL *appURL = DXSBReadObjectProperty(proxy, @"bundleURL");
    if (![appURL isKindOfClass:[NSURL class]]) return @[];

    NSMutableArray<NSURL *> *bundleURLs = [NSMutableArray arrayWithObject:appURL];
    NSFileManager *fileManager = [NSFileManager defaultManager];
    for (NSString *subdirectory in @[@"PlugIns", @"Frameworks"]) {
        NSURL *directoryURL = [appURL URLByAppendingPathComponent:subdirectory];
        for (NSURL *childURL in [fileManager contentsOfDirectoryAtURL:directoryURL
                                               includingPropertiesForKeys:nil
                                                                  options:NSDirectoryEnumerationSkipsHiddenFiles
                                                                    error:nil]) {
            NSString *extension = childURL.pathExtension.lowercaseString;
            if ([extension isEqualToString:@"appex"] || [extension isEqualToString:@"framework"] ||
                [extension isEqualToString:@"bundle"]) {
                [bundleURLs addObject:childURL];
            }
        }
    }

    NSMutableArray *results = [NSMutableArray array];
    NSMutableSet<NSString *> *seen = [NSMutableSet set];
    for (NSURL *containerURL in bundleURLs) {
        NSURL *actionsURL = [[containerURL URLByAppendingPathComponent:@"Metadata.appintents"]
            URLByAppendingPathComponent:@"extract.actionsdata"];
        NSData *data = [NSData dataWithContentsOfFile:actionsURL.path];
        if (!data) continue;
        id document = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
        if (![document isKindOfClass:[NSDictionary class]]) continue;
        id shortcuts = document[@"autoShortcuts"];
        if (![shortcuts isKindOfClass:[NSArray class]]) shortcuts = document[@"appShortcuts"];
        if (![shortcuts isKindOfClass:[NSArray class]]) continue;

        NSBundle *bundle = [NSBundle bundleWithURL:containerURL];
        NSMutableArray<NSDictionary *> *loctables = [NSMutableArray array];
        if (bundle) {
            for (NSURL *url in [bundle URLsForResourcesWithExtension:@"loctable" subdirectory:nil]) {
                NSDictionary *table = [NSDictionary dictionaryWithContentsOfURL:url];
                if (![table isKindOfClass:[NSDictionary class]]) continue;
                for (NSString *key in table) {
                    if ([table[key] isKindOfClass:[NSDictionary class]]) {
                        [loctables addObject:table];
                        break;
                    }
                }
            }
        }
        for (NSDictionary *shortcut in shortcuts) {
            if (![shortcut isKindOfClass:[NSDictionary class]]) continue;
            NSString *action = [shortcut[@"actionIdentifier"] isKindOfClass:[NSString class]] ? shortcut[@"actionIdentifier"] : nil;
            if (action.length == 0) action = [shortcut[@"intentIdentifier"] isKindOfClass:[NSString class]] ? shortcut[@"intentIdentifier"] : nil;
            if (action.length == 0 || [seen containsObject:action]) continue;
            [seen addObject:action];

            id shortTitle = shortcut[@"shortTitle"];
            NSString *titleKey = nil;
            if ([shortTitle isKindOfClass:[NSDictionary class]] && [shortTitle[@"key"] isKindOfClass:[NSString class]]) {
                titleKey = shortTitle[@"key"];
            } else if ([shortTitle isKindOfClass:[NSString class]]) {
                titleKey = shortTitle;
            }

            DXSBMetadataShortcutItem *entry = [[DXSBMetadataShortcutItem alloc] init];
            entry.type = action;
            entry.localizedTitle = DXSBLocalizedAppIntentTitle(titleKey.length > 0 ? titleKey : action, bundle, loctables) ?: action;
            [results addObject:entry];
        }
    }
    return results;
}

// Merged metadata fallback for one app: static, dynamic, App Intents —
// deduplicated by type in that priority order.
static NSArray *DXSBMetadataShortcutItemsForBundleIdentifier(NSString *bundleIdentifier) {
    id proxy = DXSBProxyForBundleIdentifier(bundleIdentifier);
    if (!proxy) return @[];

    NSMutableArray *items = [NSMutableArray array];
    NSMutableSet<NSString *> *seen = [NSMutableSet set];
    for (NSArray *scanned in @[
        DXSBStaticShortcutItemsFromProxy(proxy),
        DXSBDynamicShortcutItemsFromProxy(proxy, bundleIdentifier),
        DXSBAppIntentShortcutItemsFromProxy(proxy),
    ]) {
        for (id item in scanned) {
            NSString *type = DXSBReadStringProperty(item, @"type");
            if (type.length == 0 || [seen containsObject:type]) continue;
            [seen addObject:type];
            [items addObject:item];
        }
    }
    return items;
}

static NSArray *DXSBSBApplicationShortcutItems(NSString *bundleIdentifier) {
    id app = DXSBSBApplicationForBundleIdentifier(bundleIdentifier);

    NSMutableArray *items = [NSMutableArray array];
    if (app) {
        id info = DXSBReadObjectProperty(app, @"info");
        NSArray *staticItems = DXSBReadObjectProperty(info, @"staticApplicationShortcutItems")
            ?: DXSBReadObjectProperty(app, @"staticApplicationShortcutItems");
        if ([staticItems isKindOfClass:[NSArray class]]) [items addObjectsFromArray:staticItems];
        NSArray *dynamicItems = DXSBReadObjectProperty(app, @"dynamicApplicationShortcutItems");
        if ([dynamicItems isKindOfClass:[NSArray class]]) [items addObjectsFromArray:dynamicItems];
        NSArray *launchable = DXSBLaunchableShortcutItems(items);
        if (launchable.count > 0) return launchable;
    }

    // The SBApplication model frequently answers nothing on some iOS builds
    // (notably iOS 16). The bundle-metadata scan — the same resolved static,
    // dynamic and App Intents sources the Settings side used before the
    // catalogue moved into SpringBoard — is the fallback for exactly those
    // apps, on every OS version.
    return DXSBLaunchableShortcutItems(DXSBMetadataShortcutItemsForBundleIdentifier(bundleIdentifier));
}

// Merges freshly fetched items into the shared catalogue plist and
// republishes it.  Read-modify-write: per-app entries this run did not fetch
// (real long-press captures, other refresh runs) survive untouched.
static void DXSBMergeShortcutCatalogue(NSDictionary<NSString *, NSArray *> *fetched) {
    if (fetched.count == 0) return;
    @try {
        NSMutableDictionary *root = [[NSDictionary dictionaryWithContentsOfFile:TypeXSBShortcutsPath] mutableCopy]
            ?: [NSMutableDictionary dictionary];
        NSMutableDictionary *apps = [root[@"apps"] mutableCopy] ?: [NSMutableDictionary dictionary];
        NSTimeInterval now = [NSDate timeIntervalSinceReferenceDate];
        for (NSString *bundleIdentifier in fetched) {
            NSArray *items = fetched[bundleIdentifier];
            NSArray *normalized = DXSBNormalizedShortcutItems(items);
            if (normalized.count == 0) continue;
            DXSBRememberLiveShortcutItems(items, bundleIdentifier);
            NSMutableDictionary *entry = [NSMutableDictionary dictionary];
            entry[@"items"] = normalized;
            entry[@"updated"] = @(now);
            NSString *displayName = DXSBDisplayNameForBundleIdentifier(bundleIdentifier);
            if (displayName.length > 0) entry[@"name"] = displayName;
            apps[bundleIdentifier] = entry;
        }
        root[@"apps"] = apps;
        root[@"format"] = @2;
        if ([root writeToFile:TypeXSBShortcutsPath atomically:YES]) {
            CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(),
                                                 (__bridge CFStringRef)kShortcutSnapshotChangedIdentifier,
                                                 NULL, NULL, YES);
        }
    } @catch (NSException *exception) {
        NSLog(@"[TypeX] sbshortcuts: catalogue refresh failed (%@)", exception);
    }
}

// Populates the Settings catalogue without requiring a manual long press for
// every app. SpringBoard's icon view is asked to build the same menu the
// Home Screen shows, with the SBApplication static/dynamic data source (and
// its bundle-metadata fallback) running in parallel for apps the icon view
// cannot answer for. One pipeline on every supported OS version.
static void DXSBRefreshShortcutSnapshots(NSArray<NSString *> *bundleIdentifiers) {
    dispatch_async(dispatch_get_main_queue(), ^{
        NSMutableDictionary<NSString *, id> *iconViews = [NSMutableDictionary dictionary];
        NSMutableDictionary<NSString *, NSArray *> *immediate = [NSMutableDictionary dictionary];
        for (NSString *bundleIdentifier in bundleIdentifiers) {
            id iconView = DXSBIconViewForBundleIdentifier(bundleIdentifier);
            if (!iconView) continue;
            iconViews[bundleIdentifier] = iconView;
            NSArray *items = DXSBShortcutItemsFromIconView(iconView, YES);
            if (items.count > 0) immediate[bundleIdentifier] = items;
        }

        dispatch_group_t readiness = dispatch_group_create();
        __block NSDictionary<NSString *, NSArray *> *serviceItems = @{};
        dispatch_group_async(readiness, dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
            NSMutableDictionary<NSString *, NSArray *> *fetched = [NSMutableDictionary dictionary];
            for (NSString *bundleIdentifier in bundleIdentifiers) {
                NSArray *items = DXSBSBApplicationShortcutItems(bundleIdentifier);
                if (items.count > 0) fetched[bundleIdentifier] = items;
            }
            serviceItems = [fetched copy];
        });
        // Newer icon views finish their fetch asynchronously. Keep each view
        // alive and give SpringBoard a short window before reading it again.
        dispatch_group_enter(readiness);
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.5 * NSEC_PER_SEC)),
                       dispatch_get_main_queue(), ^{
            dispatch_group_leave(readiness);
        });

        dispatch_group_notify(readiness, dispatch_get_main_queue(), ^{
            NSMutableDictionary<NSString *, NSArray *> *fetched = [serviceItems mutableCopy]
                ?: [NSMutableDictionary dictionary];
            [immediate enumerateKeysAndObjectsUsingBlock:^(NSString *bundleIdentifier, NSArray *items, BOOL *stop) {
                fetched[bundleIdentifier] = items;
            }];
            [iconViews enumerateKeysAndObjectsUsingBlock:^(NSString *bundleIdentifier, id iconView, BOOL *stop) {
                NSArray *items = DXSBShortcutItemsFromIconView(iconView, NO);
                if (items.count > 0) fetched[bundleIdentifier] = items;
            }];
            DXSBMergeShortcutCatalogue(fetched);
        });
    });
}

static NSArray *(*dx_SBIconView_effectiveItems_orig)(id, SEL);
static NSArray *dx_SBIconView_effectiveItems(id self, SEL _cmd) {
    NSArray *items = dx_SBIconView_effectiveItems_orig(self, _cmd);
    NSString *bundleIdentifier = DXSBBundleIdentifierForIconView(self);
    DXSBRememberIconView(self, bundleIdentifier);
    DXSBCaptureShortcutItems(items, bundleIdentifier);
    return items;
}

static NSArray *(*dx_SBIconController_itemsForIconView_orig)(id, SEL, id, id);
static NSArray *dx_SBIconController_itemsForIconView(id self, SEL _cmd, id iconManager, id iconView) {
    NSArray *items = dx_SBIconController_itemsForIconView_orig(self, _cmd, iconManager, iconView);
    NSString *bundleIdentifier = DXSBBundleIdentifierForIconView(iconView);
    DXSBRememberIconView(iconView, bundleIdentifier);
    DXSBCaptureShortcutItems(items, bundleIdentifier);
    return items;
}

static void (*dx_SBIconView_setItems_orig)(id, SEL, NSArray *);
static void dx_SBIconView_setItems(id self, SEL _cmd, NSArray *items) {
    dx_SBIconView_setItems_orig(self, _cmd, items);
    NSString *bundleIdentifier = DXSBBundleIdentifierForIconView(self);
    DXSBRememberIconView(self, bundleIdentifier);
    DXSBCaptureShortcutItems(items, bundleIdentifier);
}

// CydiaSubstrate (or its drop-in replacements) message hook.
extern void MSHookMessageEx(Class _class, SEL message, IMP hook, IMP *previous);

// Hooks one (class, selector) pair at most once; returns YES when this call
// installed it, NO when it was already hooked or the symbol is missing.
static BOOL DXSBHookClassSelector(const char *className, const char *selectorName, IMP hook, IMP *previous) {
    Class cls = objc_getClass(className);
    SEL selector = sel_registerName(selectorName);
    if (!cls || !class_getInstanceMethod(cls, selector)) return NO;
    MSHookMessageEx(cls, selector, hook, previous);
    NSLog(@"[TypeX] sbshortcuts: hooked %s %s", className, selectorName);
    return YES;
}

// SpringBoardHome may not be loaded yet when tweak constructors run; retry
// briefly on the main queue until every hook is in place.
static void DXSBInstallShortcutCaptureHooks(NSUInteger attempt) {
    static BOOL effectiveHooked = NO, delegateHooked = NO, setterHooked = NO;
    if (!effectiveHooked) {
        effectiveHooked = DXSBHookClassSelector("SBIconView",
                                                 "effectiveApplicationShortcutItems",
                                                 (IMP)dx_SBIconView_effectiveItems,
                                                 (IMP *)&dx_SBIconView_effectiveItems_orig);
    }
    if (!delegateHooked) {
        delegateHooked = DXSBHookClassSelector("SBIconController",
                                               "iconManager:applicationShortcutItemsForIconView:",
                                               (IMP)dx_SBIconController_itemsForIconView,
                                               (IMP *)&dx_SBIconController_itemsForIconView_orig);
    }
    if (!setterHooked) {
        setterHooked = DXSBHookClassSelector("SBIconView",
                                             "setApplicationShortcutItems:",
                                             (IMP)dx_SBIconView_setItems,
                                             (IMP *)&dx_SBIconView_setItems_orig);
    }
    if ((effectiveHooked && delegateHooked && setterHooked) || attempt >= 5) return;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(3.0 * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
        DXSBInstallShortcutCaptureHooks(attempt + 1);
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
                        // Capture the real icon-menu quick actions (see the
                        // capture module above) for the Settings picker. The
                        // hooks resolve at runtime, so a version without a
                        // symbol just degrades to no captures.
                        DXSBInstallShortcutCaptureHooks(0);
                    }
                }
            }
        }
    }
}
