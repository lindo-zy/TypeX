#import "DXJavaScriptHost.h"
#import "DXJavaScriptEngine.h"
#import "common.h"

@interface DXJavaScriptChoiceWindow : UIWindow
@end
@implementation DXJavaScriptChoiceWindow
- (BOOL)canBecomeKeyWindow { return NO; }
@end

@interface DXJavaScriptHost ()
@property (nonatomic, strong) DXJavaScriptEngine *engine;
@property (nonatomic, weak) UIView *sourceView;
@property (nonatomic, weak) UIWindow *sourceWindow;
@property (nonatomic, weak) UIWindowScene *scene;
@property (nonatomic, weak) id<UITextInput> input;
@property (nonatomic, copy) id (^provider)(void);
@property (nonatomic, copy) void (^open)(NSString *, NSString *);
@property (nonatomic, copy) void (^error)(NSString *);
@property (nonatomic, copy) NSString *text;
@property (nonatomic, assign) NSRange selection;
@property (nonatomic, assign) NSRange replacement;
@property (nonatomic, copy) NSString *output;
@property (nonatomic, strong) NSTimer *timer;
@property (nonatomic, strong) UIWindow *menuWindow;
@property (nonatomic, strong) NSArray *choices;
@property (nonatomic, strong) NSDate *started;
@property (nonatomic, assign) BOOL cancelled;
@property (nonatomic, assign) BOOL clipboardInput;
@property (nonatomic, assign) NSInteger clipboardChange;
@end

static DXJavaScriptHost *DXActiveJavaScriptHost;

@implementation DXJavaScriptHost
+ (void)cancelActive { [DXActiveJavaScriptHost cancel]; }
- (void)cancel {
    if (self.cancelled) return;
    self.cancelled = YES;
    [self.timer invalidate]; self.timer = nil;
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    [self.engine cancel]; self.engine = nil;
    self.menuWindow.hidden = YES; self.menuWindow = nil; self.choices = nil;
    self.provider = nil; self.open = nil; self.error = nil;
    if (DXActiveJavaScriptHost == self) DXActiveJavaScriptHost = nil;
    NSLog(@"[TypeXJS] session closed");
}
- (void)fail:(NSString *)message {
    NSLog(@"[TypeXJS] session failed");
    void (^handler)(NSString *) = self.error;
    [self cancel];
    if (handler) handler(message);
}
- (void)interrupted:(NSNotification *)notification { (void)notification; [self cancel]; }
- (void)inputChanged:(NSNotification *)notification {
    if (notification.object == self.input) [self cancel];
}
- (BOOL)readInputText:(NSString **)text range:(NSRange *)range {
    id<UITextInput> input = self.input;
    for (NSString *name in @[@"beginningOfDocument", @"endOfDocument", @"selectedTextRange", @"textRangeFromPosition:toPosition:",
        @"textInRange:", @"offsetFromPosition:toPosition:", @"positionFromPosition:offset:", @"replaceRange:withText:"]) {
        if (![input respondsToSelector:NSSelectorFromString(name)]) return NO;
    }
    @try {
        if ([input respondsToSelector:@selector(isSecureTextEntry)] && [(id<UITextInputTraits>)input isSecureTextEntry]) return NO;
        if ([input respondsToSelector:@selector(markedTextRange)] && input.markedTextRange) return NO;
        UITextRange *selected = input.selectedTextRange;
        UITextPosition *begin = input.beginningOfDocument;
        UITextRange *whole = [input textRangeFromPosition:begin toPosition:input.endOfDocument];
        if (!selected || !whole) return NO;
        NSString *value = [input textInRange:whole];
        NSInteger start = [input offsetFromPosition:begin toPosition:selected.start];
        NSInteger end = [input offsetFromPosition:begin toPosition:selected.end];
        if (![value isKindOfClass:NSString.class] || value.length > 1024 * 1024 || start < 0 || end < start || (NSUInteger)end > value.length) return NO;
        *text = value; *range = NSMakeRange((NSUInteger)start, (NSUInteger)(end - start));
        return YES;
    } @catch (__unused NSException *exception) { return NO; }
}
- (BOOL)valid {
    if (self.cancelled || !self.sourceWindow || self.sourceWindow.hidden || !self.sourceView ||
        self.sourceView.window != self.sourceWindow || self.sourceView.hidden ||
        !self.input || self.provider() != self.input) return NO;
    for (UIView *view = self.sourceView; view; view = view.superview) {
        if (view.hidden || view.alpha <= 0.01) return NO;
    }
    if (self.scene && self.scene.activationState != UISceneActivationStateForegroundActive) return NO;
    if (self.clipboardInput && UIPasteboard.generalPasteboard.changeCount != self.clipboardChange) return NO;
    NSString *text = nil; NSRange range;
    return [self readInputText:&text range:&range] && [text isEqual:self.text] && NSEqualRanges(range, self.selection);
}
- (void)tick {
    if (![self valid] || -[self.started timeIntervalSinceNow] > 120) [self cancel];
}
+ (void)startEntry:(NSDictionary *)entry sourceView:(UIView *)view inputProvider:(id (^)(void))provider
             open:(void (^)(NSString *, NSString *))open error:(void (^)(NSString *))error {
    [self cancelActive];
    DXJavaScriptHost *host = [self new];
    host.sourceView = view; host.sourceWindow = view.window;
    host.provider = provider; host.input = provider(); host.open = open; host.error = error;
    UIView *inputView = [(id)host.input isKindOfClass:UIView.class] ? (UIView *)host.input : nil;
    host.scene = inputView.window.windowScene ?: view.window.windowScene;
    id inputMode = entry[@"jsInput"] ?: @"auto";
    id outputMode = entry[@"jsOutput"] ?: @"replace";
    if (![@[@"auto", @"all", @"clipboard"] containsObject:inputMode] ||
        ![@[@"replace", @"insert", @"copy"] containsObject:outputMode]) {
        [host fail:@"Invalid JavaScript action configuration"]; return;
    }
    host.output = outputMode;
    NSString *text = nil; NSRange range;
    if (![host readInputText:&text range:&range] || !view.window) {
        [host fail:NSLocalizedStringFromTableInBundle(@"JS_INPUT_UNAVAILABLE", nil, [NSBundle bundleWithPath:bundlePath], nil)]; return;
    }
    host.text = text; host.selection = range;
    NSString *mode = inputMode;
    host.replacement = [mode isEqual:@"all"] || !range.length ? NSMakeRange(0, text.length) : range;
    NSString *input = [text substringWithRange:host.replacement];
    if ([mode isEqual:@"clipboard"]) {
        host.clipboardInput = YES;
        input = UIPasteboard.generalPasteboard.string ?: @"";
        host.clipboardChange = UIPasteboard.generalPasteboard.changeCount;
        host.replacement = range;
    }
    host.started = [NSDate date]; host.engine = [DXJavaScriptEngine new];
    __weak DXJavaScriptHost *weakHost = host;
    host.engine.actionHandler = ^(NSDictionary *action) { [weakHost execute:action]; };
    host.engine.resultHandler = ^(NSArray *actions, NSError *failure) {
        DXJavaScriptHost *current = weakHost;
        if (!current || current.cancelled) return;
        if (![current valid]) { [current cancel]; return; }
        if (failure) { [current fail:failure.localizedDescription]; return; }
        if (!actions.count) [current cancel];
        else if (actions.count == 1) [current execute:actions.firstObject];
        else [current showChoices:actions];
    };
    DXActiveJavaScriptHost = host;
    NSNotificationCenter *center = NSNotificationCenter.defaultCenter;
    for (NSString *name in @[UIKeyboardWillHideNotification, UIApplicationWillResignActiveNotification,
        UIDeviceOrientationDidChangeNotification]) [center addObserver:host selector:@selector(interrupted:) name:name object:nil];
    for (NSString *name in @[UITextFieldTextDidChangeNotification, UITextViewTextDidChangeNotification])
        [center addObserver:host selector:@selector(inputChanged:) name:name object:nil];
    host.timer = [NSTimer timerWithTimeInterval:0.15 repeats:YES block:^(__unused NSTimer *timer) {
        DXJavaScriptHost *current = weakHost;
        [current tick];
    }];
    [NSRunLoop.mainRunLoop addTimer:host.timer forMode:NSRunLoopCommonModes];
    NSLog(@"[TypeXJS] session started");
    [host.engine runSource:[entry[@"script"] isKindOfClass:NSString.class] ? entry[@"script"] : @"" input:input];
}
- (void)execute:(NSDictionary *)action {
    // Terminal actions clear the global owner; keep the receiver alive through
    // UIKit's replacement (which can throw or synchronously post notifications).
    __attribute__((objc_precise_lifetime)) DXJavaScriptHost *keepAlive = self;
    (void)keepAlive;
    if (![self valid]) { [self cancel]; return; }
    self.menuWindow.hidden = YES; self.menuWindow = nil; self.choices = nil;
    NSString *type = action[@"type"], *content = action[@"content"];
    if ([type isEqual:@"function"]) { [self.engine callFunction:content arguments:action[@"args"]]; return; }
    if (![@[@"txt", @"url", @"urlInApp", @"app"] containsObject:type]) { [self fail:@"Unsupported action type"]; return; }
    if (![type isEqual:@"txt"]) {
        if (([type isEqual:@"app"] && !DXIsValidBundleIdentifier(content)) ||
            (![type isEqual:@"app"] && !DXIsOpenableSchemeURLString(content))) { [self fail:@"Invalid URL or application identifier"]; return; }
        void (^open)(NSString *, NSString *) = self.open;
        // Commit one navigation, close the session before it changes focus.
        // Pending returns/callbacks cannot cause a second open or insertion.
        [self cancel];
        if (open) open(type, content);
        return;
    }
    if ([self.output isEqual:@"copy"]) { [self cancel]; UIPasteboard.generalPasteboard.string = content; return; }
    id<UITextInput> input = self.input;
    void (^errorHandler)(NSString *) = self.error;
    NSRange range = [self.output isEqual:@"insert"] ? self.selection : self.replacement;
    @try {
        UITextPosition *start = [input positionFromPosition:input.beginningOfDocument offset:(NSInteger)range.location];
        UITextPosition *end = [input positionFromPosition:start offset:(NSInteger)range.length];
        UITextRange *target = start && end ? [input textRangeFromPosition:start toPosition:end] : nil;
        if (!target) { [self fail:@"Input range is no longer available"]; return; }
        [self cancel];
        [input replaceRange:target withText:content];
    } @catch (__unused NSException *exception) {
        [self cancel];
        if (errorHandler) errorHandler(@"Unable to replace input text");
    }
}
- (void)choiceTapped:(UIButton *)sender {
    if (sender.tag < 0 || (NSUInteger)sender.tag >= self.choices.count) return;
    [self execute:self.choices[(NSUInteger)sender.tag]];
}
- (void)showChoices:(NSArray *)choices {
    UIWindowScene *scene = self.scene;
    if (!scene || scene.activationState != UISceneActivationStateForegroundActive) { [self fail:@"No active scene for script choices"]; return; }
    self.choices = choices;
    DXJavaScriptChoiceWindow *window = [[DXJavaScriptChoiceWindow alloc] initWithWindowScene:scene];
    window.frame = scene.coordinateSpace.bounds;
    window.windowLevel = MAX(UIWindowLevelAlert + 1, self.sourceWindow.windowLevel + 1);
    UIViewController *controller = [UIViewController new];
    window.rootViewController = controller;
    UIControl *backdrop = [[UIControl alloc] initWithFrame:window.bounds];
    backdrop.backgroundColor = [UIColor colorWithWhite:0 alpha:0.18];
    backdrop.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    [backdrop addTarget:self action:@selector(cancel) forControlEvents:UIControlEventTouchUpInside];
    [controller.view addSubview:backdrop];
    UIScrollView *scroll = [UIScrollView new];
    scroll.backgroundColor = UIColor.secondarySystemBackgroundColor;
    scroll.layer.cornerRadius = 14;
    CGFloat width = MIN(360, CGRectGetWidth(window.bounds) - 32);
    CGFloat height = MIN((choices.count + 1) * 50.0, CGRectGetHeight(window.bounds) * 0.48);
    scroll.frame = CGRectMake((CGRectGetWidth(window.bounds) - width) / 2, MAX(50, (CGRectGetHeight(window.bounds) - height) / 3), width, height);
    [backdrop addSubview:scroll];
    NSBundle *bundle = [NSBundle bundleWithPath:bundlePath];
    for (NSUInteger index = 0; index <= choices.count; index++) {
        UIButton *button = [UIButton buttonWithType:UIButtonTypeSystem];
        button.frame = CGRectMake(12, index * 50, width - 24, 50);
        button.tag = (NSInteger)index;
        button.titleLabel.numberOfLines = 2;
        button.titleLabel.font = [UIFont systemFontOfSize:15];
        NSString *title = index == choices.count ? NSLocalizedStringFromTableInBundle(@"ANSWER_CANCEL", nil, bundle, nil) : choices[index][@"title"];
        [button setTitle:title.length ? title : @"∅" forState:UIControlStateNormal];
        [button addTarget:self action:index == choices.count ? @selector(cancel) : @selector(choiceTapped:) forControlEvents:UIControlEventTouchUpInside];
        [scroll addSubview:button];
    }
    scroll.contentSize = CGSizeMake(width, (choices.count + 1) * 50);
    self.menuWindow = window;
    window.hidden = NO; // Never make key or resign the input responder.
}
@end
