#import "DXKeyboardPanel.h"
#import "DXKeyboardPanelPreferences.h"
#import "DXKeyboardPanelGeometry.h"
#import "DXCollectionView.h"
#import "DXHelper.h"
#import "DXShared.h"
#import "common.h"

@interface DXKeyboardPanelWindow : UIWindow
@property(nonatomic, assign) CGRect panelRect;
@end
@implementation DXKeyboardPanelWindow
- (UIView *)hitTest:(CGPoint)point withEvent:(UIEvent *)event {
    if (!CGRectContainsPoint(self.panelRect, point)) return nil;
    return [super hitTest:point withEvent:event];
}
@end

@interface DXKeyboardPanelButton : UIButton
@property(nonatomic, copy) NSString *actionSelector;
@property(nonatomic, strong) UIImageView *actionImage;
@property(nonatomic, strong) UILabel *actionLabel;
@end
@implementation DXKeyboardPanelButton
- (void)setHighlighted:(BOOL)highlighted {
    [super setHighlighted:highlighted];
    self.alpha = highlighted ? 0.5 : 1;
}
@end

@interface DXKeyboardPanel ()
@property(nonatomic, strong) NSHashTable<DXCollectionView *> *toolbars;
@property(nonatomic, strong) DXKeyboardPanelWindow *window;
@property(nonatomic, strong) UIView *panel;
@property(nonatomic, strong) UIScrollView *scroll;
@property(nonatomic, strong) UILabel *titleLabel;
@property(nonatomic, strong) UIButton *closeButton;
@property(nonatomic, strong) NSArray<DXKeyboardPanelButton *> *buttons;
@property(nonatomic, weak) DXCollectionView *source;
@property(nonatomic, weak) UIWindow *sourceWindow;
@property(nonatomic, weak) UIResponder *input;
@property(nonatomic, weak) UIScreen *keyboardScreen;
@property(nonatomic, assign) CGRect keyboardFrame;
@property(nonatomic, assign) BOOL hasKeyboardFrame;
@property(nonatomic, assign) BOOL dark;
@property(nonatomic, assign) CGFloat scale;
@property(nonatomic, assign) NSInteger columns;
@end

@implementation DXKeyboardPanel
+ (instancetype)sharedInstance {
    static DXKeyboardPanel *instance;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ instance = [[self alloc] init]; });
    return instance;
}
- (instancetype)init {
    if ((self = [super init])) {
        _toolbars = [NSHashTable weakObjectsHashTable];
        NSNotificationCenter *center = NSNotificationCenter.defaultCenter;
        [center addObserver:self selector:@selector(keyboardChanged:) name:UIKeyboardWillChangeFrameNotification object:nil];
        [center addObserver:self selector:@selector(keyboardChanged:) name:UIKeyboardDidShowNotification object:nil];
        [center addObserver:self selector:@selector(keyboardHidden:) name:UIKeyboardWillHideNotification object:nil];
        [center addObserver:self selector:@selector(invalidated:) name:UIApplicationWillResignActiveNotification object:nil];
        [center addObserver:self selector:@selector(invalidated:) name:UISceneWillDeactivateNotification object:nil];
        [center addObserver:self selector:@selector(invalidated:) name:UIDeviceOrientationDidChangeNotification object:nil];
        [center addObserver:self selector:@selector(invalidated:) name:@"typeXLayoutChanged" object:nil];
        [center addObserver:self selector:@selector(invalidated:) name:UITextFieldTextDidBeginEditingNotification object:nil];
        [center addObserver:self selector:@selector(invalidated:) name:UITextFieldTextDidEndEditingNotification object:nil];
        [center addObserver:self selector:@selector(invalidated:) name:UITextViewTextDidBeginEditingNotification object:nil];
        [center addObserver:self selector:@selector(invalidated:) name:UITextViewTextDidEndEditingNotification object:nil];
    }
    return self;
}
- (void)dealloc { [NSNotificationCenter.defaultCenter removeObserver:self]; }
- (UIResponder *)currentInput {
    Class cls = NSClassFromString(@"UIKeyboardImpl");
    UIKeyboardImpl *keyboard = [cls respondsToSelector:@selector(activeInstance)] ? [cls activeInstance] : nil;
    return DXKeyboardInputDelegate(keyboard);
}
- (BOOL)visibleToolbar:(DXCollectionView *)toolbar {
    if (!toolbar || !toolbar.window || toolbar.window.hidden) return NO;
    for (UIView *view = toolbar; view; view = view.superview) {
        if (view.hidden || view.alpha < 0.01) return NO;
    }
    return toolbar.shortcutConfigurationAvailable;
}
- (void)registerToolbar:(DXCollectionView *)toolbar {
    if (![NSThread isMainThread]) return;
    [self.toolbars addObject:toolbar];
    if (self.window && ![self validSession]) [self dismiss];
    else if (self.window) [self layoutPanel];
}
- (void)toolbarDetached:(DXCollectionView *)toolbar {
    [self.toolbars removeObject:toolbar];
    if (self.source == toolbar) [self dismiss];
}
- (BOOL)validSession {
    return [self visibleToolbar:self.source] && self.source.window == self.sourceWindow &&
        self.input && self.input == [self currentInput] &&
        self.window.windowScene.activationState == UISceneActivationStateForegroundActive;
}
- (void)keyboardChanged:(NSNotification *)note {
    if (![NSThread isMainThread]) {
        dispatch_async(dispatch_get_main_queue(), ^{ [self keyboardChanged:note]; });
        return;
    }
    NSValue *value = note.userInfo[UIKeyboardFrameEndUserInfoKey];
    if (![value isKindOfClass:NSValue.class]) return;
    self.keyboardFrame = value.CGRectValue;
    self.keyboardScreen = [note.object isKindOfClass:UIScreen.class] ? note.object : (self.sourceWindow.screen ?: UIScreen.mainScreen);
    self.hasKeyboardFrame = !CGRectIsEmpty(self.keyboardFrame);
    if (self.window && ![self validSession]) [self dismiss];
    else if (self.window) [self layoutPanel];
}
- (void)keyboardHidden:(NSNotification *)note {
    if (![NSThread isMainThread]) {
        dispatch_async(dispatch_get_main_queue(), ^{ [self keyboardHidden:note]; });
        return;
    }
    self.hasKeyboardFrame = NO;
    [self dismiss];
}
- (void)invalidated:(NSNotification *)note { (void)note; [self dismiss]; }
- (CGRect)coverageInWindow:(UIWindow *)window {
    CGRect rect = CGRectNull;
    UIScreen *screen = self.sourceWindow.screen;
    if (self.hasKeyboardFrame && (!self.keyboardScreen || self.keyboardScreen == screen)) {
        CGRect keyboard = [window convertRect:self.keyboardFrame fromCoordinateSpace:screen.coordinateSpace];
        rect = DXKeyboardPanelUnionCoverage(rect, keyboard, window.bounds, YES);
    }
    for (DXCollectionView *toolbar in self.toolbars) {
        if (![self visibleToolbar:toolbar] || toolbar.window.screen != screen) continue;
        // Only combine the currently attached keyboard hierarchy, never another scene's toolbar.
        if (toolbar.window != self.sourceWindow && toolbar.window.windowScene != self.sourceWindow.windowScene &&
            toolbar.window.windowScene != window.windowScene) continue;
        CGRect local = [toolbar convertRect:toolbar.bounds toView:toolbar.window];
        CGRect frame = [window convertRect:local fromWindow:toolbar.window];
        rect = DXKeyboardPanelUnionCoverage(rect, frame, window.bounds, NO);
        // Notifications may precede toolbar registration. Measure live keyboard
        // ancestors too, including the candidate row and the dock's bottom inset.
        // Do not use arbitrary app ancestors that could cover the whole screen.
        for (UIView *ancestor = toolbar.superview; ancestor && ancestor != toolbar.window; ancestor = ancestor.superview) {
            NSString *className = NSStringFromClass(ancestor.class);
            if (![className hasPrefix:@"UIInputSet"] && ![className hasPrefix:@"UIKeyboard"]) continue;
            CGRect surface = [ancestor convertRect:ancestor.bounds toView:toolbar.window];
            surface = [window convertRect:surface fromWindow:toolbar.window];
            rect = DXKeyboardPanelUnionCoverage(rect, surface, window.bounds, YES);
        }
    }
    return DXKeyboardPanelFullWidthCoverage(rect, window.bounds);
}
- (void)updateWindowLevel {
    // iOS 17's remote keyboard is not necessarily listed in the app scene's
    // windows. Use the same independent-window floor as the existing AI and
    // subaction panels, then account for any higher visible local windows.
    CGFloat level = MAX(1000000.0, self.sourceWindow.windowLevel + 1);
    for (UIWindow *existing in self.window.windowScene.windows) {
        if (existing != self.window && !existing.hidden) level = MAX(level, existing.windowLevel + 1);
    }
    self.window.windowLevel = level;
}
- (void)presentFromToolbar:(DXCollectionView *)toolbar side:(NSString *)side {
    if (![NSThread isMainThread]) return;
    DXPrefsManager *manager = DXPrefsManager.sharedInstance;
    if (!manager.preferencesAvailable || ![self visibleToolbar:toolbar]) return;
    NSDictionary *preferences = manager.prefs;
    NSString *enabledKey = [toolbar.configuration isEqualToString:@"top"] ? kDXPanelTopEnabled : kDXPanelBottomEnabled;
    if (!DXKeyboardPanelBool(preferences, enabledKey, YES)) return;
    UIResponder *input = [self currentInput];
    UIWindow *inputWindow = [input isKindOfClass:UIView.class] ? ((UIView *)input).window : nil;
    UIWindowScene *scene = inputWindow.windowScene ?: toolbar.window.windowScene;
    if (!input || !scene || scene.activationState != UISceneActivationStateForegroundActive) {
        NSLog(@"[TypeX][KeyboardPanel] open cancelled: no active source input/scene");
        return;
    }
    [self dismiss];
    [toolbar dismissKeyboardActionChooser];
    self.source = toolbar;
    self.sourceWindow = toolbar.window;
    self.input = input;
    [self.toolbars addObject:toolbar];
    NSString *profile = DXKeyboardPanelBool(preferences, kDXPanelUnified, NO) ? @"common" : side;
    NSArray *items = DXKeyboardPanelItems(preferences, profile);
    self.scale = DXKeyboardPanelNumber(preferences, kDXPanelScale, 100, 70, 120) / 100;
    self.columns = (NSInteger)DXKeyboardPanelNumber(preferences, kDXPanelColumns, 4, 3, 5);
    self.dark = DXKeyboardPanelBool(preferences, kDXPanelDark, YES);

    DXKeyboardPanelWindow *window = [[DXKeyboardPanelWindow alloc] initWithWindowScene:scene];
    window.frame = scene.coordinateSpace.bounds;
    window.backgroundColor = UIColor.clearColor;
    UIViewController *root = [[UIViewController alloc] init];
    root.view.frame = window.bounds;
    root.view.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    root.view.backgroundColor = UIColor.clearColor;
    window.rootViewController = root;
    self.window = window;
    [self updateWindowLevel];
    UIView *panel = [[UIView alloc] init];
    panel.layer.cornerRadius = 22;
    panel.clipsToBounds = YES;
    self.panel = panel;
    [root.view addSubview:panel];
    UIVisualEffectView *blur = [[UIVisualEffectView alloc] initWithEffect:[UIBlurEffect effectWithStyle:
        self.dark ? UIBlurEffectStyleSystemMaterialDark : UIBlurEffectStyleSystemMaterialLight]];
    blur.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    blur.frame = panel.bounds;
    blur.contentView.backgroundColor = self.dark ? [UIColor colorWithWhite:0.08 alpha:0.5] : [UIColor colorWithWhite:1 alpha:0.5];
    [panel addSubview:blur];
    UIColor *text = self.dark ? UIColor.whiteColor : UIColor.labelColor;
    UIControl *header = [[UIControl alloc] init];
    header.tag = 30;
    [header addTarget:self action:@selector(dismiss) forControlEvents:UIControlEventTouchUpInside];
    UISwipeGestureRecognizer *closeSwipe = [[UISwipeGestureRecognizer alloc] initWithTarget:self action:@selector(dismiss)];
    closeSwipe.direction = UISwipeGestureRecognizerDirectionDown;
    [header addGestureRecognizer:closeSwipe];
    [panel addSubview:header];
    UIView *handle = [[UIView alloc] init];
    handle.tag = 31;
    handle.backgroundColor = [text colorWithAlphaComponent:0.45];
    handle.layer.cornerRadius = 2;
    handle.userInteractionEnabled = NO;
    [header addSubview:handle];
    self.titleLabel = [[UILabel alloc] init];
    NSBundle *bundle = [NSBundle bundleWithPath:bundlePath];
    NSString *titleKey = [profile isEqualToString:@"common"] ? @"KEYBOARD_PANEL_COMMON" :
        ([profile isEqualToString:@"left"] ? @"KEYBOARD_PANEL_LEFT" : @"KEYBOARD_PANEL_RIGHT");
    self.titleLabel.text = [bundle localizedStringForKey:titleKey value:titleKey table:nil];
    self.titleLabel.textColor = text;
    self.titleLabel.font = [UIFont systemFontOfSize:15 weight:UIFontWeightSemibold];
    [panel addSubview:self.titleLabel];
    self.closeButton = [UIButton buttonWithType:UIButtonTypeSystem];
    [self.closeButton setImage:[UIImage systemImageNamed:@"xmark.circle.fill"] forState:UIControlStateNormal];
    self.closeButton.tintColor = text;
    self.closeButton.accessibilityLabel = [bundle localizedStringForKey:@"KEYBOARD_PANEL_CLOSE" value:@"Close" table:nil];
    [self.closeButton addTarget:self action:@selector(dismiss) forControlEvents:UIControlEventTouchUpInside];
    [panel addSubview:self.closeButton];

    self.scroll = [[UIScrollView alloc] init];
    self.scroll.showsVerticalScrollIndicator = NO;
    [panel addSubview:self.scroll];
    NSMutableArray *buttons = [NSMutableArray array];
    for (NSDictionary *entry in items) {
        NSString *selector = entry[@"selector"];
        if (![toolbar canExecuteKeyboardPanelSelector:selector]) continue;
        DXKeyboardPanelButton *button = [DXKeyboardPanelButton buttonWithType:UIButtonTypeCustom];
        button.actionSelector = selector;
        button.actionImage = [[UIImageView alloc] init];
        button.actionImage.contentMode = UIViewContentModeScaleAspectFit;
        button.actionImage.tintColor = text;
        NSString *icon = entry[@"icon"];
        button.actionImage.image = icon.length ? [DXHelper imageForIconConfig:icon defaultSymbolName:@"square.grid.2x2"] : [toolbar subActionPanelImageForSelector:selector];
        button.actionLabel = [[UILabel alloc] init];
        NSString *name = entry[@"name"];
        button.actionLabel.text = name.length ? name : [toolbar subActionPanelTitleForSelector:selector];
        button.actionLabel.textColor = text;
        button.actionLabel.numberOfLines = 2;
        button.actionLabel.textAlignment = NSTextAlignmentCenter;
        button.actionLabel.font = [UIFont systemFontOfSize:12 * self.scale];
        button.actionLabel.adjustsFontSizeToFitWidth = YES;
        button.actionLabel.minimumScaleFactor = 0.8;
        button.accessibilityLabel = button.actionLabel.text;
        [button addSubview:button.actionImage];
        [button addSubview:button.actionLabel];
        [button addTarget:self action:@selector(itemTapped:) forControlEvents:UIControlEventTouchUpInside];
        [self.scroll addSubview:button];
        [buttons addObject:button];
    }
    self.buttons = buttons;
    UIControl *blank = [[UIControl alloc] init];
    blank.tag = 20;
    [blank addTarget:self action:@selector(dismiss) forControlEvents:UIControlEventTouchUpInside];
    [self.scroll insertSubview:blank atIndex:0];
    if (!buttons.count) {
        UILabel *empty = [[UILabel alloc] init];
        empty.tag = 21;
        empty.text = [bundle localizedStringForKey:@"KEYBOARD_PANEL_EMPTY" value:@"Add actions in Settings" table:nil];
        empty.textColor = text;
        empty.numberOfLines = 0;
        empty.textAlignment = NSTextAlignmentCenter;
        [self.scroll addSubview:empty];
    }
    [self layoutPanel];
    if (!self.window) return;
    window.hidden = NO; // Never makeKeyWindow: the host input retains focus.
    NSLog(@"[TypeX][KeyboardPanel] open side=%@ toolbar=%@ items=%lu rect=%@ level=%.0f source=%@",
        profile, toolbar.configuration, (unsigned long)buttons.count, NSStringFromCGRect(window.panelRect),
        (double)window.windowLevel, NSStringFromClass(toolbar.window.class));
}
- (void)layoutPanel {
    if (!self.window) return;
    CGRect coverage = [self coverageInWindow:self.window];
    if (CGRectIsNull(coverage) || CGRectIsEmpty(coverage)) {
        NSLog(@"[TypeX][KeyboardPanel] open cancelled: keyboard geometry unavailable");
        [self dismiss];
        return;
    }
    [self updateWindowLevel];
    self.window.panelRect = coverage;
    self.panel.frame = coverage;
    CGFloat width = coverage.size.width, height = coverage.size.height;
    [self.panel viewWithTag:30].frame = CGRectMake(0, 0, width, 46);
    [self.panel viewWithTag:31].frame = CGRectMake((width - 38) / 2, 3, 38, 4);
    self.titleLabel.frame = CGRectMake(16, 10, MAX(0, width - 68), 28);
    self.closeButton.frame = CGRectMake(width - 48, 2, 44, 44);
    CGFloat contentTop = 46;
    self.scroll.frame = CGRectMake(8, contentTop, width - 16, MAX(0, height - contentTop - 8));
    CGFloat itemWidth = self.scroll.bounds.size.width / self.columns;
    CGFloat circle = MIN(54 * self.scale, itemWidth - 16);
    CGFloat rowHeight = circle + 42 * self.scale;
    [self.buttons enumerateObjectsUsingBlock:^(DXKeyboardPanelButton *button, NSUInteger index, BOOL *stop) {
        (void)stop;
        button.frame = CGRectMake((index % self.columns) * itemWidth, (index / self.columns) * rowHeight, itemWidth, rowHeight);
        UIView *circleView = [button viewWithTag:10];
        if (!circleView) {
            circleView = [[UIView alloc] init];
            circleView.tag = 10;
            circleView.userInteractionEnabled = NO;
            circleView.backgroundColor = self.dark ? [UIColor colorWithWhite:0 alpha:0.45] : [UIColor colorWithWhite:1 alpha:0.65];
            [button insertSubview:circleView atIndex:0];
        }
        circleView.frame = CGRectMake((itemWidth - circle) / 2, 4, circle, circle);
        circleView.layer.cornerRadius = circle / 2;
        CGFloat icon = circle * 0.52;
        button.actionImage.frame = CGRectMake((itemWidth - icon) / 2, 4 + (circle - icon) / 2, icon, icon);
        button.actionLabel.frame = CGRectMake(3, circle + 9, itemWidth - 6, 30 * self.scale);
    }];
    CGFloat contentHeight = MAX(self.scroll.bounds.size.height, ceil((double)self.buttons.count / self.columns) * rowHeight);
    self.scroll.contentSize = CGSizeMake(self.scroll.bounds.size.width, contentHeight);
    [self.scroll viewWithTag:20].frame = CGRectMake(0, 0, self.scroll.bounds.size.width, contentHeight);
    [self.scroll viewWithTag:21].frame = self.scroll.bounds;
}
- (void)itemTapped:(DXKeyboardPanelButton *)button {
    if (![self validSession] || ![self.buttons containsObject:button]) { [self dismiss]; return; }
    DXCollectionView *source = self.source;
    NSString *selector = [button.actionSelector copy];
    if (![source canExecuteKeyboardPanelSelector:selector]) { [self dismiss]; return; }
    // Synchronous dismissal leaves no animation callback that could target a new input session.
    [self dismiss];
    [source dispatchKeyboardPanelSelector:selector sender:button];
}
- (void)dismiss {
    if (![NSThread isMainThread]) {
        dispatch_async(dispatch_get_main_queue(), ^{ [self dismiss]; });
        return;
    }
    self.window.hidden = YES;
    self.window.rootViewController = nil;
    self.window = nil;
    self.panel = nil;
    self.scroll = nil;
    self.buttons = nil;
    self.titleLabel = nil;
    self.closeButton = nil;
    self.source = nil;
    self.sourceWindow = nil;
    self.input = nil;
}
@end
