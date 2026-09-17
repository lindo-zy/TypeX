#import "DXAIPanel.h"
#import "DXAIEngine.h"
#import "common.h"
#import "DXShared.h"
#import <PhotosUI/PhotosUI.h>
#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>

@class DXAIHostWindow;
@class DXAIBallWindow;
@class DXAIChatPanelController;

// 全局强引用只养活"当前正被使用"的窗口。关闭路径（X / 场景销毁）立即清空引用
// 并 hidden——ShellX 集成时验证过的教训：残留的全屏僵尸窗口会继续参与
// hitTest 吞掉宿主触摸，必须同步收尾、异步释放。
static DXAIHostWindow *g_aiPanelWindow;
static DXAIBallWindow *g_aiBallWindow;

// 最近一次键盘 endFrame（屏幕坐标）。通知流维护；打开首帧用活体探测兜底。
static CGRect g_dxKeyboardFrame;

@interface DXAIPanel ()
+ (DXAIChatPanelController *)ensurePanelController;
+ (void)openFromKeyboardWithSeedText:(NSString *)seedText;
+ (void)hidePanelAndShowBallIfNeeded;
+ (void)closeAndDestroyPanel;
+ (void)ballWasTapped;
+ (void)showBall;
+ (void)storeBallPosition:(CGPoint)center inBounds:(CGRect)bounds;
@end

#pragma mark - 工具

static inline UIColor *DXAIAccent(void) {
    return [UIColor systemBlueColor];
}

static inline UIColor *DXAICircleChrome(void) {
    return [DXAIAccent() colorWithAlphaComponent:0.12];
}

static NSString *DXAILocalized(NSString *key) {
    return [tweakBundle localizedStringForKey:key value:key table:nil];
}

static UIImage *DXAISymbol(NSString *name, CGFloat pointSize, UIImageSymbolWeight weight) {
    UIFont *font = [UIFont systemFontOfSize:pointSize weight:weight];
    UIImageSymbolConfiguration *configuration = [UIImageSymbolConfiguration configurationWithFont:font];
    return [UIImage systemImageNamed:name withConfiguration:configuration];
}

// 视觉请求上限 1280px / JPEG 0.55：兼顾视觉模型识别率与 base64 体积。
static UIImage *DXAIDownscaleForUpload(UIImage *image) {
    const CGFloat maxDimension = 1280.0;
    CGFloat larger = MAX(image.size.width, image.size.height);
    if (larger <= maxDimension || larger <= 0.0) return image;
    CGFloat scale = maxDimension / larger;
    CGSize target = CGSizeMake(floor(image.size.width * scale), floor(image.size.height * scale));
    UIGraphicsImageRendererFormat *format = [[UIGraphicsImageRendererFormat alloc] init];
    format.scale = 1.0;
    UIGraphicsImageRenderer *renderer = [[UIGraphicsImageRenderer alloc] initWithSize:target format:format];
    return [renderer imageWithActions:^(UIGraphicsImageRendererContext *context) {
        [image drawInRect:CGRectMake(0, 0, target.width, target.height)];
    }];
}

static NSString *DXAIDataURLForImage(UIImage *image) {
    NSData *jpeg = UIImageJPEGRepresentation(DXAIDownscaleForUpload(image), 0.55);
    if (!jpeg) return nil;
    return [NSString stringWithFormat:@"data:image/jpeg;base64,%@", [jpeg base64EncodedStringWithOptions:0]];
}

// 打开首帧的通知尚未到达时，从活跃键盘实例探测当前键盘 frame（屏幕坐标）。
static CGRect DXAIProbeKeyboardFrame(void) {
    UIKeyboardImpl *keyboard = [objc_getClass("UIKeyboardImpl") activeInstance];
    if (keyboard && keyboard.window && !keyboard.hidden && CGRectGetHeight(keyboard.frame) > 10.0) {
        return [keyboard.window convertRect:keyboard.frame toWindow:nil];
    }
    return CGRectZero;
}

#pragma mark - 宿主窗口

@interface DXAIHostWindow : UIWindow
@end

@implementation DXAIHostWindow

- (BOOL)canBecomeKeyWindow {
    return YES; // 面板输入框需要 key 才能聚焦
}

// 卡片之外的触摸一律穿透回宿主：面板打开但未聚焦时，宿主文字区域仍可直接
// 点击继续输入（键盘属于宿主第一响应者，不受影响）。
- (UIView *)hitTest:(CGPoint)point withEvent:(UIEvent *)event {
    UIViewController *root = self.rootViewController;
    if (!root || self.hidden) return nil;
    CGPoint local = [root.view convertPoint:point fromView:self];
    if (![root.view pointInside:local withEvent:event]) return nil;
    return [root.view hitTest:local withEvent:event];
}

@end

#pragma mark - 悬浮球

@interface DXAIBallWindow : UIWindow
@property (nonatomic, strong) UIButton *ballButton;
@end

@implementation DXAIBallWindow

- (instancetype)init {
    if ((self = [super init])) {
        self.backgroundColor = UIColor.clearColor;

        UIButton *button = [UIButton buttonWithType:UIButtonTypeCustom];
        button.frame = CGRectMake(0, 0, 54, 54);
        button.backgroundColor = [DXAIAccent() colorWithAlphaComponent:0.92];
        button.layer.cornerRadius = 27.0;
        button.tintColor = UIColor.whiteColor;
        [button setImage:DXAISymbol(@"sparkles", 24, UIImageSymbolWeightMedium) forState:UIControlStateNormal];
        button.layer.shadowColor = [UIColor blackColor].CGColor;
        button.layer.shadowOpacity = 0.25;
        button.layer.shadowOffset = CGSizeMake(0, 3);
        button.layer.shadowRadius = 8.0;
        [button addTarget:self action:@selector(ballTapped) forControlEvents:UIControlEventTouchUpInside];
        self.ballButton = button;
        [self addSubview:button];

        UIPanGestureRecognizer *pan = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(ballPan:)];
        [button addGestureRecognizer:pan];
    }
    return self;
}

- (BOOL)canBecomeKeyWindow {
    return NO;
}

- (UIView *)hitTest:(CGPoint)point withEvent:(UIEvent *)event {
    CGPoint local = [self.ballButton convertPoint:point fromView:self];
    return [self.ballButton pointInside:local withEvent:event] ? self.ballButton : nil;
}

- (void)ballTapped {
    [DXAIPanel ballWasTapped];
}

- (void)ballPan:(UIPanGestureRecognizer *)pan {
    UIView *container = self;
    CGPoint translation = [pan translationInView:container];
    CGPoint center = self.ballButton.center;
    center.x += translation.x;
    center.y += translation.y;
    [pan setTranslation:CGPointZero inView:container];

    CGFloat margin = 30.0;
    center.x = MIN(MAX(center.x, margin), CGRectGetWidth(container.bounds) - margin);
    center.y = MIN(MAX(center.y, margin + 20.0), CGRectGetHeight(container.bounds) - margin - 20.0);
    self.ballButton.center = center;

    if (pan.state == UIGestureRecognizerStateEnded) {
        // 吸附到较近的屏幕边缘；开启半隐藏时压低存在感。
        CGFloat leftDistance = center.x;
        CGFloat rightDistance = CGRectGetWidth(container.bounds) - center.x;
        center.x = (leftDistance < rightDistance) ? margin : CGRectGetWidth(container.bounds) - margin;
        [UIView animateWithDuration:0.25 animations:^{
            self.ballButton.center = center;
            self.ballButton.alpha = [DXAIEngine ballHalfHide] ? 0.45 : 1.0;
        }];
        [DXAIPanel storeBallPosition:center inBounds:container.bounds];
    }
}

@end

#pragma mark - 菜单行（图标 + 文本；UIButton 的 inset 属性 iOS 15 已弃用，改用自绘行）

@interface DXAIMenuRow : UIControl
@property (nonatomic, strong) UIImageView *iconView;
@property (nonatomic, strong) UILabel *label;
@end

@implementation DXAIMenuRow

- (instancetype)initWithFrame:(CGRect)frame {
    if ((self = [super initWithFrame:frame])) {
        self.iconView = [[UIImageView alloc] init];
        self.iconView.contentMode = UIViewContentModeCenter;
        self.iconView.tintColor = DXAIAccent();
        [self addSubview:self.iconView];

        self.label = [[UILabel alloc] init];
        self.label.font = [UIFont systemFontOfSize:16.0];
        self.label.textColor = [UIColor labelColor];
        [self addSubview:self.label];
    }
    return self;
}

- (void)setHighlighted:(BOOL)highlighted {
    [super setHighlighted:highlighted];
    self.backgroundColor = highlighted ? [UIColor tertiarySystemFillColor] : UIColor.clearColor;
}

- (void)layoutSubviews {
    [super layoutSubviews];
    CGFloat height = CGRectGetHeight(self.bounds);
    self.iconView.frame = CGRectMake(16, 0, 24, height);
    self.label.frame = CGRectMake(52, 0, CGRectGetWidth(self.bounds) - 64, height);
}

@end

#pragma mark - 消息模型

@interface DXAIMessage : NSObject
@property (nonatomic, copy) NSString *text;
@property (nonatomic, strong) UIImage *image;
@property (nonatomic, copy) NSString *imageDataURL; // 首次发送时编码并缓存，多轮不重复编码
@property (nonatomic, assign) BOOL isUser;
@property (nonatomic, assign) BOOL isError;
@property (nonatomic, assign) BOOL streaming;
@end

@implementation DXAIMessage
@end

#pragma mark - 用户气泡

@interface DXAIUserBubbleCell : UITableViewCell
@property (nonatomic, strong) UIView *bubble;
@property (nonatomic, strong) UIImageView *photoView;
@property (nonatomic, strong) UILabel *messageLabel;
@property (nonatomic, strong) NSLayoutConstraint *photoHeight;
@property (nonatomic, strong) NSLayoutConstraint *textBelowPhoto;
@property (nonatomic, strong) NSLayoutConstraint *textTopInBubble;
@end

@implementation DXAIUserBubbleCell

- (instancetype)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)reuseIdentifier {
    if ((self = [super initWithStyle:style reuseIdentifier:reuseIdentifier])) {
        self.selectionStyle = UITableViewCellSelectionStyleNone;
        self.backgroundColor = UIColor.clearColor;
        self.contentView.backgroundColor = UIColor.clearColor;

        self.bubble = [[UIView alloc] init];
        self.bubble.backgroundColor = DXAIAccent();
        self.bubble.layer.cornerRadius = 18.0;
        self.bubble.translatesAutoresizingMaskIntoConstraints = NO;
        [self.contentView addSubview:self.bubble];

        self.photoView = [[UIImageView alloc] init];
        self.photoView.contentMode = UIViewContentModeScaleAspectFill;
        self.photoView.clipsToBounds = YES;
        self.photoView.layer.cornerRadius = 12.0;
        self.photoView.translatesAutoresizingMaskIntoConstraints = NO;
        [self.bubble addSubview:self.photoView];

        self.messageLabel = [[UILabel alloc] init];
        self.messageLabel.font = [UIFont systemFontOfSize:16.0];
        self.messageLabel.textColor = UIColor.whiteColor;
        self.messageLabel.numberOfLines = 0;
        self.messageLabel.translatesAutoresizingMaskIntoConstraints = NO;
        [self.bubble addSubview:self.messageLabel];

        self.photoHeight = [self.photoView.heightAnchor constraintEqualToConstant:150.0];
        self.textBelowPhoto = [self.messageLabel.topAnchor constraintEqualToAnchor:self.photoView.bottomAnchor constant:6.0];
        self.textTopInBubble = [self.messageLabel.topAnchor constraintEqualToAnchor:self.bubble.topAnchor constant:12.0];

        [NSLayoutConstraint activateConstraints:@[
            [self.bubble.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor constant:-14.0],
            [self.bubble.topAnchor constraintEqualToAnchor:self.contentView.topAnchor constant:6.0],
            [self.bubble.bottomAnchor constraintEqualToAnchor:self.contentView.bottomAnchor constant:-6.0],
            [self.bubble.widthAnchor constraintLessThanOrEqualToAnchor:self.contentView.widthAnchor multiplier:0.78 constant:0.0],
            [self.photoView.leadingAnchor constraintEqualToAnchor:self.bubble.leadingAnchor constant:10.0],
            [self.photoView.trailingAnchor constraintEqualToAnchor:self.bubble.trailingAnchor constant:-10.0],
            [self.photoView.topAnchor constraintEqualToAnchor:self.bubble.topAnchor constant:10.0],
            [self.messageLabel.leadingAnchor constraintEqualToAnchor:self.bubble.leadingAnchor constant:14.0],
            [self.messageLabel.trailingAnchor constraintEqualToAnchor:self.bubble.trailingAnchor constant:-14.0],
            [self.messageLabel.bottomAnchor constraintEqualToAnchor:self.bubble.bottomAnchor constant:-12.0],
        ]];
    }
    return self;
}

- (void)configureWithMessage:(DXAIMessage *)message {
    self.messageLabel.text = message.text ?: @"";
    BOOL hasImage = message.image != nil;
    self.photoView.image = message.image;
    if (hasImage) {
        self.textTopInBubble.active = NO;
        self.photoHeight.active = YES;
        self.textBelowPhoto.active = YES;
    } else {
        self.photoHeight.active = NO;
        self.textBelowPhoto.active = NO;
        self.textTopInBubble.active = YES;
    }
}

@end

#pragma mark - 助手气泡

@interface DXAIAssistantBubbleCell : UITableViewCell
@property (nonatomic, strong) UITextView *textView;
@end

@implementation DXAIAssistantBubbleCell

- (instancetype)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)reuseIdentifier {
    if ((self = [super initWithStyle:style reuseIdentifier:reuseIdentifier])) {
        self.selectionStyle = UITableViewCellSelectionStyleNone;
        self.backgroundColor = UIColor.clearColor;
        self.contentView.backgroundColor = UIColor.clearColor;

        self.textView = [[UITextView alloc] init];
        self.textView.editable = NO;
        self.textView.selectable = YES; // 长按选择复制
        self.textView.scrollEnabled = NO;
        self.textView.backgroundColor = UIColor.clearColor;
        self.textView.font = [UIFont systemFontOfSize:16.0];
        self.textView.textContainerInset = UIEdgeInsetsZero;
        self.textView.translatesAutoresizingMaskIntoConstraints = NO;
        [self.contentView addSubview:self.textView];

        [NSLayoutConstraint activateConstraints:@[
            [self.textView.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor constant:18.0],
            [self.textView.topAnchor constraintEqualToAnchor:self.contentView.topAnchor constant:10.0],
            [self.textView.bottomAnchor constraintEqualToAnchor:self.contentView.bottomAnchor constant:-10.0],
            [self.textView.widthAnchor constraintLessThanOrEqualToAnchor:self.contentView.widthAnchor multiplier:0.82 constant:0.0],
        ]];
    }
    return self;
}

- (void)configureWithMessage:(DXAIMessage *)message {
    NSString *text = message.text;
    if (message.streaming && text.length == 0) text = @"…";
    if (message.isError) text = [@"⚠️ " stringByAppendingString:text ?: @""];
    self.textView.text = text ?: @"";
    self.textView.textColor = message.isError ? [UIColor secondaryLabelColor] : [UIColor labelColor];
}

@end

#pragma mark - 聊天面板控制器

@interface DXAIChatPanelController : UIViewController <UITableViewDataSource, UITableViewDelegate, UITextViewDelegate, PHPickerViewControllerDelegate, UIImagePickerControllerDelegate, UINavigationControllerDelegate, UIDocumentPickerDelegate>
@property (nonatomic, strong) UIView *headerView;
@property (nonatomic, strong) UILabel *titleLabel;
@property (nonatomic, strong) UIButton *modelButton;
@property (nonatomic, strong) UIButton *keyboardButton;
@property (nonatomic, strong) UIButton *minimizeButton;
@property (nonatomic, strong) UIButton *closeButton;
@property (nonatomic, strong) UIView *headerDivider;
@property (nonatomic, strong) UITableView *table;
@property (nonatomic, strong) UIView *inputBar;
@property (nonatomic, strong) UIView *chipContainer;
@property (nonatomic, strong) UIImageView *chipThumb;
@property (nonatomic, strong) UILabel *chipNameLabel;
@property (nonatomic, strong) UIButton *chipRemoveButton;
@property (nonatomic, strong) UIView *fieldContainer;
@property (nonatomic, strong) UITextView *inputField;
@property (nonatomic, strong) UILabel *placeholderLabel;
@property (nonatomic, strong) UIButton *plusButton;
@property (nonatomic, strong) UIButton *sendButton;
@property (nonatomic, strong) UIControl *popoverCatcher;

@property (nonatomic, strong) NSMutableArray<DXAIMessage *> *messages;
@property (nonatomic, strong) UIImage *attachedImage;
@property (nonatomic, copy) NSString *pendingFileText;
@property (nonatomic, copy) NSString *pendingFileName;
@property (nonatomic, copy) NSString *seedText;
@property (nonatomic, assign) BOOL sessionSeeded;
@property (nonatomic, assign) BOOL streaming;
@property (nonatomic, assign) BOOL flushScheduled;
@property (nonatomic, strong) DXAIChatRequest *currentRequest;
@property (nonatomic, weak) UIWindow *hostKeyWindow;
@property (nonatomic, strong) id keyboardObserver;

- (void)applySeedIfFreshSession;
- (void)refreshModelButton;
- (void)refreshChip;
- (void)updateAttachedImage:(UIImage *)image;
- (void)inputFieldTextChanged;
- (void)repositionAnimated:(BOOL)animated;
- (void)applyTheme;
- (void)cancelRunningRequest;
@end

@implementation DXAIChatPanelController

- (instancetype)init {
    if ((self = [super init])) {
        self.messages = [NSMutableArray array];
    }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];

    self.view.backgroundColor = [UIColor systemBackgroundColor];
    self.view.layer.cornerRadius = 20.0;
    self.view.layer.maskedCorners = kCALayerMinXMinYCorner | kCALayerMaxXMinYCorner;
    self.view.layer.shadowColor = [UIColor blackColor].CGColor;
    self.view.layer.shadowOpacity = 0.14;
    self.view.layer.shadowRadius = 20.0;
    self.view.layer.shadowOffset = CGSizeMake(0, -3);

    // ── header ──
    self.headerView = [[UIView alloc] init];
    [self.view addSubview:self.headerView];

    self.titleLabel = [[UILabel alloc] init];
    self.titleLabel.text = DXAILocalized(@"AI_CARD_TITLE");
    self.titleLabel.font = [UIFont systemFontOfSize:20.0 weight:UIFontWeightSemibold];
    self.titleLabel.textColor = [UIColor labelColor];
    [self.headerView addSubview:self.titleLabel];

    self.modelButton = [UIButton buttonWithType:UIButtonTypeCustom];
    self.modelButton.contentHorizontalAlignment = UIControlContentHorizontalAlignmentLeft;
    self.modelButton.titleLabel.font = [UIFont systemFontOfSize:15.0 weight:UIFontWeightMedium];
    [self.modelButton setTitleColor:DXAIAccent() forState:UIControlStateNormal];
    [self.modelButton addTarget:self action:@selector(modelTapped) forControlEvents:UIControlEventTouchUpInside];
    [self.headerView addSubview:self.modelButton];

    self.keyboardButton = [DXAIChatPanelController circleButtonWithSymbol:@"keyboard" action:@selector(keyboardToggleTapped) target:self];
    self.minimizeButton = [DXAIChatPanelController circleButtonWithSymbol:@"minus" action:@selector(minimizeTapped) target:self];
    self.closeButton = [DXAIChatPanelController circleButtonWithSymbol:@"xmark" action:@selector(closeTapped) target:self];
    [self.headerView addSubview:self.keyboardButton];
    [self.headerView addSubview:self.minimizeButton];
    [self.headerView addSubview:self.closeButton];

    self.headerDivider = [[UIView alloc] init];
    self.headerDivider.backgroundColor = [UIColor separatorColor];
    [self.view addSubview:self.headerDivider];

    // ── 会话流 ──
    self.table = [[UITableView alloc] initWithFrame:CGRectZero style:UITableViewStylePlain];
    self.table.dataSource = self;
    self.table.delegate = self;
    self.table.separatorStyle = UITableViewCellSeparatorStyleNone;
    self.table.backgroundColor = UIColor.clearColor;
    self.table.hidden = YES;
    self.table.estimatedRowHeight = 80.0;
    self.table.rowHeight = UITableViewAutomaticDimension;
    self.table.keyboardDismissMode = UIScrollViewKeyboardDismissModeNone;
    [self.table registerClass:[DXAIUserBubbleCell class] forCellReuseIdentifier:@"user"];
    [self.table registerClass:[DXAIAssistantBubbleCell class] forCellReuseIdentifier:@"assistant"];
    [self.view addSubview:self.table];

    // ── 输入栏 ──
    self.inputBar = [[UIView alloc] init];
    [self.view addSubview:self.inputBar];

    self.chipContainer = [[UIView alloc] init];
    self.chipContainer.backgroundColor = [UIColor tertiarySystemFillColor];
    self.chipContainer.layer.cornerRadius = 12.0;
    self.chipContainer.hidden = YES;
    [self.inputBar addSubview:self.chipContainer];

    self.chipThumb = [[UIImageView alloc] init];
    self.chipThumb.contentMode = UIViewContentModeScaleAspectFill;
    self.chipThumb.clipsToBounds = YES;
    self.chipThumb.layer.cornerRadius = 8.0;
    self.chipThumb.tintColor = DXAIAccent();
    [self.chipContainer addSubview:self.chipThumb];

    self.chipNameLabel = [[UILabel alloc] init];
    self.chipNameLabel.font = [UIFont systemFontOfSize:14.0];
    self.chipNameLabel.textColor = [UIColor labelColor];
    [self.chipContainer addSubview:self.chipNameLabel];

    self.chipRemoveButton = [UIButton buttonWithType:UIButtonTypeCustom];
    [self.chipRemoveButton setImage:DXAISymbol(@"xmark.circle.fill", 20, UIImageSymbolWeightRegular) forState:UIControlStateNormal];
    self.chipRemoveButton.tintColor = [UIColor secondaryLabelColor];
    [self.chipRemoveButton addTarget:self action:@selector(chipRemoveTapped) forControlEvents:UIControlEventTouchUpInside];
    [self.chipContainer addSubview:self.chipRemoveButton];

    self.fieldContainer = [[UIView alloc] init];
    self.fieldContainer.backgroundColor = [UIColor tertiarySystemFillColor];
    self.fieldContainer.layer.cornerRadius = 20.0;
    [self.inputBar addSubview:self.fieldContainer];

    self.inputField = [[UITextView alloc] init];
    self.inputField.backgroundColor = UIColor.clearColor;
    self.inputField.font = [UIFont systemFontOfSize:16.0];
    self.inputField.textColor = [UIColor labelColor];
    self.inputField.tintColor = DXAIAccent();
    self.inputField.textContainerInset = UIEdgeInsetsZero;
    self.inputField.scrollIndicatorInsets = UIEdgeInsetsZero;
    self.inputField.delegate = self;
    [self.fieldContainer addSubview:self.inputField];

    self.placeholderLabel = [[UILabel alloc] init];
    self.placeholderLabel.text = DXAILocalized(@"AI_CARD_PLACEHOLDER");
    self.placeholderLabel.font = [UIFont systemFontOfSize:16.0];
    self.placeholderLabel.textColor = [UIColor placeholderTextColor];
    self.placeholderLabel.userInteractionEnabled = NO;
    [self.fieldContainer addSubview:self.placeholderLabel];

    self.plusButton = [UIButton buttonWithType:UIButtonTypeCustom];
    self.plusButton.backgroundColor = DXAIAccent();
    self.plusButton.layer.cornerRadius = 23.0;
    self.plusButton.tintColor = UIColor.whiteColor;
    [self.plusButton setImage:DXAISymbol(@"plus", 20, UIImageSymbolWeightSemibold) forState:UIControlStateNormal];
    [self.plusButton addTarget:self action:@selector(plusTapped) forControlEvents:UIControlEventTouchUpInside];
    [self.inputBar addSubview:self.plusButton];

    self.sendButton = [UIButton buttonWithType:UIButtonTypeCustom];
    self.sendButton.backgroundColor = DXAIAccent();
    self.sendButton.layer.cornerRadius = 23.0;
    self.sendButton.titleLabel.font = [UIFont systemFontOfSize:16.0 weight:UIFontWeightSemibold];
    [self.sendButton setTitle:DXAILocalized(@"AI_CARD_SEND") forState:UIControlStateNormal];
    [self.sendButton setTitleColor:UIColor.whiteColor forState:UIControlStateNormal];
    [self.sendButton addTarget:self action:@selector(sendTapped) forControlEvents:UIControlEventTouchUpInside];
    [self.inputBar addSubview:self.sendButton];

    [[NSNotificationCenter defaultCenter] addObserverForName:UIKeyboardWillChangeFrameNotification
                                                      object:nil
                                                       queue:[NSOperationQueue mainQueue]
                                                  usingBlock:^(NSNotification *note) {
        __weak typeof(self) weakSelf = self;
        NSValue *value = note.userInfo[UIKeyboardFrameEndUserInfoKey];
        if ([value isKindOfClass:[NSValue class]]) g_dxKeyboardFrame = value.CGRectValue;

        NSTimeInterval duration = 0.25;
        NSNumber *durationNumber = note.userInfo[UIKeyboardAnimationDurationUserInfoKey];
        if ([durationNumber isKindOfClass:[NSNumber class]]) duration = durationNumber.doubleValue;
        NSInteger curve = 7; // UIViewAnimationCurveKeyValue 非公开常量的等价值
        NSNumber *curveNumber = note.userInfo[UIKeyboardAnimationCurveUserInfoKey];
        if ([curveNumber isKindOfClass:[NSNumber class]]) curve = curveNumber.integerValue;

        [UIView animateWithDuration:duration delay:0.0 options:(curve << 16) animations:^{
            [weakSelf repositionAnimated:NO];
        } completion:nil];
    }];

    [self applySeedIfFreshSession];
    [self refreshModelButton];
    [self refreshChip];
    [self updatePlaceholder];
    [self updateSendState];
}

- (void)dealloc {
    if (self.keyboardObserver) [[NSNotificationCenter defaultCenter] removeObserver:self.keyboardObserver];
}

#pragma mark - 布局

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    CGRect bounds = self.view.bounds;
    CGFloat width = CGRectGetWidth(bounds);
    CGFloat height = CGRectGetHeight(bounds);
    if (width <= 0.0 || height <= 0.0) return;

    [self layoutHeaderWithWidth:width];
    self.headerView.frame = CGRectMake(0, 0, width, 56.0);
    self.headerDivider.frame = CGRectMake(0, 55.5, width, 0.5);

    BOOL chipVisible = self.attachedImage != nil || self.pendingFileText.length > 0;
    CGFloat sidePad = 14.0, gap = 8.0, plusSize = 46.0, sendWidth = 74.0;
    CGFloat fieldWidth = width - sidePad * 2 - plusSize - gap * 2 - sendWidth;
    CGFloat textHeight = [self.inputField sizeThatFits:CGSizeMake(fieldWidth - 24.0, CGFLOAT_MAX)].height;
    textHeight = MIN(MAX(textHeight, 30.0), 110.0);
    CGFloat fieldRowHeight = textHeight + 16.0;
    CGFloat chipBlockHeight = chipVisible ? 66.0 : 0.0;
    CGFloat inputBarHeight = chipBlockHeight + fieldRowHeight + 8.0;

    self.inputBar.frame = CGRectMake(0, height - inputBarHeight, width, inputBarHeight);
    self.table.frame = CGRectMake(0, 56.0, width, MAX(0.0, height - 56.0 - inputBarHeight));
    self.table.contentInset = UIEdgeInsetsMake(0, 0, 6, 0);

    CGFloat centerY = chipBlockHeight + fieldRowHeight / 2.0;
    if (chipVisible) self.chipContainer.frame = CGRectMake(sidePad, 4.0, width - sidePad * 2, 56.0);
    self.chipThumb.frame = CGRectMake(4, 4, 48, 48);
    self.chipNameLabel.frame = CGRectMake(60, 0, width - sidePad * 2 - 60 - 34, 56);
    self.chipRemoveButton.frame = CGRectMake(width - sidePad * 2 - 30, 17, 22, 22);
    self.fieldContainer.frame = CGRectMake(sidePad, chipBlockHeight, fieldWidth, fieldRowHeight);
    self.inputField.frame = CGRectMake(12, 8, fieldWidth - 24, fieldRowHeight - 16);
    self.placeholderLabel.frame = CGRectMake(20, 8, fieldWidth - 40, fieldRowHeight - 16);
    self.plusButton.frame = CGRectMake(sidePad + fieldWidth + gap, centerY - plusSize / 2.0, plusSize, plusSize);
    self.sendButton.frame = CGRectMake(sidePad + fieldWidth + gap + plusSize + gap, centerY - 23.0, sendWidth, 46.0);
}

- (void)layoutHeaderWithWidth:(CGFloat)width {
    CGFloat buttonSize = 34.0, gap = 10.0, rightEdge = width - 14.0;
    for (UIButton *button in @[self.closeButton, self.minimizeButton, self.keyboardButton]) {
        button.frame = CGRectMake(rightEdge - buttonSize, 11.0, buttonSize, buttonSize);
        rightEdge -= (buttonSize + gap);
    }

    CGFloat titleWidth = [self.titleLabel.text sizeWithAttributes:@{NSFontAttributeName: self.titleLabel.font}].width;
    self.titleLabel.frame = CGRectMake(20.0, 0.0, ceil(titleWidth), 56.0);

    NSString *modelTitle = self.modelButton.currentTitle ?: @"";
    CGFloat modelWidth = ceil([modelTitle sizeWithAttributes:@{NSFontAttributeName: self.modelButton.titleLabel.font}].width) + 8.0;
    self.modelButton.frame = CGRectMake(20.0 + titleWidth + 10.0, 0.0, modelWidth, 56.0);
}

- (void)viewWillTransitionToSize:(CGSize)size withTransitionCoordinator:(id<UIViewControllerTransitionCoordinator>)coordinator {
    [super viewWillTransitionToSize:size withTransitionCoordinator:coordinator];
    [coordinator animateAlongsideTransition:^(id<UIViewControllerTransitionCoordinatorContext> context) {
        [self repositionAnimated:NO];
    } completion:nil];
}

// 面板锚定：键盘可见时贴在键盘上方，键盘收起时落到屏幕底部。高度封顶 470，
// 避免在小屏/横屏上顶到状态栏。
- (void)repositionAnimated:(BOOL)animated {
    UIWindow *window = self.view.window;
    if (!window) return;
    CGRect screen = window.bounds;
    CGRect keyboardFrame = (!CGRectIsEmpty(g_dxKeyboardFrame) || g_dxKeyboardFrame.origin.y > 0)
        ? g_dxKeyboardFrame : DXAIProbeKeyboardFrame();
    if (CGRectIsNull(keyboardFrame)) keyboardFrame = CGRectZero;

    BOOL keyboardVisible = keyboardFrame.origin.y > 0 && keyboardFrame.origin.y < CGRectGetHeight(screen) - 10.0;
    CGFloat keyboardTop = keyboardVisible ? keyboardFrame.origin.y : CGRectGetHeight(screen);
    CGFloat topInset = window.safeAreaInsets.top + 6.0;
    CGFloat cardHeight = MAX(MIN(470.0, keyboardTop - topInset), 150.0);
    CGRect cardFrame = CGRectMake(0, keyboardTop - cardHeight, CGRectGetWidth(screen), cardHeight);

    if (animated) {
        [UIView animateWithDuration:0.22 animations:^{
            self.view.frame = cardFrame;
        }];
    } else {
        self.view.frame = cardFrame;
    }
    [self.view setNeedsLayout];
}

- (void)applyTheme {
    NSInteger style = [DXAIEngine themeStyle];
    self.view.window.overrideUserInterfaceStyle = (style == 1) ? UIUserInterfaceStyleLight
                                          : (style == 2) ? UIUserInterfaceStyleDark
                                          : UIUserInterfaceStyleUnspecified;
}

#pragma mark - 种子 / 状态刷新

- (void)applySeedIfFreshSession {
    if (self.seedText.length > 0 && !self.sessionSeeded && self.messages.count == 0 && self.inputField.text.length == 0) {
        self.sessionSeeded = YES;
        self.inputField.text = self.seedText;
    }
    self.seedText = nil;
}

- (void)refreshModelButton {
    DXAIEngineInfo *engine = [self currentEngine];
    NSString *model = [DXAIEngine selectedModelForEngine:engine];
    [self.modelButton setTitle:[NSString stringWithFormat:@"%@  ▾", model ?: @""] forState:UIControlStateNormal];
    [self.view setNeedsLayout];
}

- (void)updatePlaceholder {
    self.placeholderLabel.hidden = self.inputField.text.length > 0;
}

- (void)updateSendState {
    NSString *question = [self.inputField.text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    BOOL hasContent = question.length > 0 || self.attachedImage != nil || self.pendingFileText.length > 0;
    BOOL enabled = hasContent || self.streaming;
    self.sendButton.enabled = enabled;
    self.sendButton.alpha = enabled ? 1.0 : 0.45;
    [self.sendButton setTitle:DXAILocalized(self.streaming ? @"AI_CARD_STOP" : @"AI_CARD_SEND")
                     forState:UIControlStateNormal];
}

- (void)refreshSendButton {
    [self updateSendState];
}

- (void)refreshChip {
    BOOL hasImage = self.attachedImage != nil;
    BOOL hasFile = self.pendingFileText.length > 0;
    self.chipContainer.hidden = !(hasImage || hasFile);
    if (hasImage) {
        self.chipThumb.image = self.attachedImage;
        self.chipThumb.contentMode = UIViewContentModeScaleAspectFill;
        self.chipNameLabel.text = DXAILocalized(@"AI_CARD_IMAGE");
    } else if (hasFile) {
        self.chipThumb.image = DXAISymbol(@"doc.text", 22, UIImageSymbolWeightMedium);
        self.chipThumb.contentMode = UIViewContentModeCenter;
        self.chipNameLabel.text = self.pendingFileName ?: DXAILocalized(@"AI_CARD_FILES");
    }
    [self.view setNeedsLayout];
    [self updateSendState];
}

- (void)updateAttachedImage:(UIImage *)image {
    self.attachedImage = image;
    if (image) { // 单附件槽：图片与文件互斥，后选替换先选
        self.pendingFileText = nil;
        self.pendingFileName = nil;
    }
    [self refreshChip];
}

- (void)chipRemoveTapped {
    self.attachedImage = nil;
    self.pendingFileText = nil;
    self.pendingFileName = nil;
    [self refreshChip];
}

- (DXAIEngineInfo *)currentEngine {
    return [DXAIEngine currentEngine];
}

#pragma mark - 输入

- (void)textViewDidChange:(UITextView *)textView {
    [self inputFieldTextChanged];
}

- (void)inputFieldTextChanged {
    [self updatePlaceholder];
    [self updateSendState];
    [self.view setNeedsLayout];
}

- (void)keyboardToggleTapped {
    // 键盘图标：切换面板输入的键盘。收起后面板随键盘 frame 落到屏幕底部。
    if (self.inputField.isFirstResponder) {
        [self.inputField resignFirstResponder];
    } else {
        [self.view.window makeKeyWindow];
        [self.inputField becomeFirstResponder];
    }
}

// 恢复宿主输入：面板窗口让出 key，再让键盘实现重新激活其输入 delegate
// （UIKeyboardImpl 自实现 becomeFirstResponder，tweak 生态通用做法）。
- (void)restoreHostFocus {
    if (!self.inputField.isFirstResponder) return;
    [self.inputField resignFirstResponder];
    UIWindow *hostWindow = self.hostKeyWindow;
    if (hostWindow && hostWindow != self.view.window) [hostWindow makeKeyWindow];
    UIKeyboardImpl *keyboard = [objc_getClass("UIKeyboardImpl") activeInstance];
    [keyboard becomeFirstResponder];
}

- (void)minimizeTapped {
    [self restoreHostFocus];
    [DXAIPanel hidePanelAndShowBallIfNeeded];
}

- (void)closeTapped {
    [self restoreHostFocus];
    [self cancelRunningRequest];
    // 同步只做 hidden + 清全局引用，控制器释放留给下一个 runloop（避免按钮
    // 动作执行途中 self 被释放）。
    dispatch_async(dispatch_get_main_queue(), ^{
        [DXAIPanel closeAndDestroyPanel];
    });
}

#pragma mark - 会话流

- (void)reloadAll {
    self.table.hidden = self.messages.count == 0;
    [self.table reloadData];
}

- (void)scrollToBottomAnimated:(BOOL)animated {
    if (self.messages.count == 0) return;
    NSIndexPath *last = [NSIndexPath indexPathForRow:self.messages.count - 1 inSection:0];
    [self.table scrollToRowAtIndexPath:last atScrollPosition:UITableViewScrollPositionBottom animated:animated];
}

- (void)sendTapped {
    [self dismissPopover];
    if (self.streaming) {
        [self cancelRunningRequest];
        return;
    }

    NSString *question = [self.inputField.text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if (question.length == 0 && self.attachedImage == nil && self.pendingFileText.length == 0) return;

    DXAIEngineInfo *engine = [self currentEngine];
    if ([DXAIEngine apiKeyForEngine:engine].length == 0) {
        [self alertWithMessage:DXAILocalized(@"AI_CARD_NO_KEY_ALERT")];
        return;
    }
    if ([DXAIEngine selectedModelForEngine:engine].length == 0) {
        [self alertWithMessage:DXAILocalized(@"AI_CARD_NO_MODEL_ALERT")];
        return;
    }

    DXAIMessage *user = [[DXAIMessage alloc] init];
    user.isUser = YES;
    if (self.attachedImage) {
        user.image = self.attachedImage;
        user.imageDataURL = DXAIDataURLForImage(self.attachedImage);
    }
    NSMutableString *content = [NSMutableString string];
    if (self.pendingFileText.length > 0) {
        [content appendFormat:@"【%@】\n%@\n\n", self.pendingFileName ?: DXAILocalized(@"AI_CARD_FILES"), self.pendingFileText];
    }
    if (question.length > 0) [content appendString:question];
    user.text = content;

    DXAIMessage *assistant = [[DXAIMessage alloc] init];
    assistant.isUser = NO;
    assistant.streaming = YES;

    [self.messages addObject:user];
    [self.messages addObject:assistant];

    self.inputField.text = @"";
    self.attachedImage = nil;
    self.pendingFileText = nil;
    self.pendingFileName = nil;

    [self updatePlaceholder];
    [self refreshChip];
    [self updateSendState];
    [self reloadAll];
    [self scrollToBottomAnimated:YES];
    [self startRequestForAssistantMessage:assistant];
}

- (void)startRequestForAssistantMessage:(DXAIMessage *)assistant {
    NSMutableArray *payload = [NSMutableArray array];
    NSString *persona = [DXAIEngine personaPrompt];
    if (persona.length == 0) persona = @"你是键盘上的 AI 问答助手：先给结论，再给细节；简洁、准确、不编造。";
    [payload addObject:@{@"role": @"system", @"content": persona}];

    // 末尾的 assistant 消息是正在生成的这条，不进入请求历史。
    NSArray *history = [self.messages subarrayWithRange:NSMakeRange(0, self.messages.count - 1)];
    if (history.count > 40) history = [history subarrayWithRange:NSMakeRange(history.count - 40, 40)];
    for (DXAIMessage *message in history) {
        if (message.imageDataURL.length > 0) {
            [payload addObject:@{@"role": @"user", @"content": @[
                @{@"type": @"text", @"text": message.text ?: @""},
                @{@"type": @"image_url", @"image_url": @{@"url": message.imageDataURL}}]}];
        } else if (message.text.length > 0) {
            [payload addObject:@{@"role": message.isUser ? @"user" : @"assistant", @"content": message.text}];
        }
    }

    self.streaming = YES;
    [self updateSendState];

    __weak typeof(self) weakSelf = self;
    self.currentRequest = [DXAIEngine sendChatWithMessages:payload
                                                    engine:[self currentEngine]
                                                  onDelta:^(NSString *piece) {
        dispatch_async(dispatch_get_main_queue(), ^{
            __strong typeof(weakSelf) strongSelf = weakSelf;
            if (!strongSelf) return;
            assistant.text = [(assistant.text ?: @"") stringByAppendingString:piece];
            [strongSelf scheduleStreamFlush];
        });
    }
                                                 onDone:^(NSString *fullText, NSError *error) {
        dispatch_async(dispatch_get_main_queue(), ^{
            __strong typeof(weakSelf) strongSelf = weakSelf;
            if (!strongSelf) return;
            [strongSelf finishStreamingForMessage:assistant fullText:fullText error:error];
        });
    }];
}

- (void)scheduleStreamFlush {
    if (self.flushScheduled) return;
    self.flushScheduled = YES;
    __weak typeof(self) weakSelf = self;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.06 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf || strongSelf.messages.count == 0) return;
        strongSelf.flushScheduled = NO;
        NSIndexPath *last = [NSIndexPath indexPathForRow:strongSelf.messages.count - 1 inSection:0];
        BOOL lastVisible = [strongSelf.table.indexPathsForVisibleRows containsObject:last];
        [strongSelf.table beginUpdates];
        [strongSelf.table reloadRowsAtIndexPaths:@[last] withRowAnimation:UITableViewRowAnimationNone];
        [strongSelf.table endUpdates];
        if (lastVisible) [strongSelf scrollToBottomAnimated:NO];
    });
}

- (void)finishStreamingForMessage:(DXAIMessage *)assistant fullText:(NSString *)fullText error:(NSError *)error {
    assistant.streaming = NO;
    self.streaming = NO;
    self.currentRequest = nil;
    if (error && error.code != NSURLErrorCancelled) {
        assistant.isError = YES;
        assistant.text = error.localizedDescription.length > 0 ? error.localizedDescription
                                                              : DXAILocalized(@"AI_CARD_REQUEST_FAILED");
    } else {
        // 成功与手动停止都保留已收到的内容。
        assistant.text = fullText ?: @"";
    }
    [self updateSendState];
    [self reloadAll];
    [self scrollToBottomAnimated:YES];
}

- (void)cancelRunningRequest {
    if (self.currentRequest) {
        [self.currentRequest cancel];
        self.currentRequest = nil;
    }
    self.streaming = NO;
    DXAIMessage *last = self.messages.lastObject;
    if (last && !last.isUser) last.streaming = NO;
    [self updateSendState];
}

#pragma mark - 表格

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return self.messages.count;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    DXAIMessage *message = self.messages[indexPath.row];
    if (message.isUser) {
        DXAIUserBubbleCell *cell = [tableView dequeueReusableCellWithIdentifier:@"user" forIndexPath:indexPath];
        [cell configureWithMessage:message];
        return cell;
    }
    DXAIAssistantBubbleCell *cell = [tableView dequeueReusableCellWithIdentifier:@"assistant" forIndexPath:indexPath];
    [cell configureWithMessage:message];
    return cell;
}

#pragma mark - 弹层（模型切换 / 附件菜单）

- (void)presentPopover:(UIView *)content {
    [self dismissPopover];
    UIControl *catcher = [[UIControl alloc] initWithFrame:self.view.bounds];
    catcher.backgroundColor = UIColor.clearColor;
    [catcher addTarget:self action:@selector(dismissPopover) forControlEvents:UIControlEventTouchUpInside];
    [catcher addSubview:content];
    [self.view addSubview:catcher];
    self.popoverCatcher = catcher;
}

- (void)dismissPopover {
    [self.popoverCatcher removeFromSuperview];
    self.popoverCatcher = nil;
}

- (void)modelTapped {
    if (self.popoverCatcher) {
        [self dismissPopover];
        return;
    }
    DXAIEngineInfo *engine = [self currentEngine];
    NSArray<NSString *> *models = [DXAIEngine modelsForEngine:engine];
    if (models.count == 0) {
        [self alertWithMessage:DXAILocalized(@"AI_CARD_NO_MODEL_ALERT")];
        return;
    }
    NSString *selected = [DXAIEngine selectedModelForEngine:engine];

    CGFloat rowHeight = 44.0;
    CGFloat menuWidth = MIN(280.0, CGRectGetWidth(self.view.bounds) - 40.0);
    CGFloat menuHeight = MIN(models.count * rowHeight + 8.0, 280.0);
    UIView *menu = [[UIView alloc] initWithFrame:CGRectMake(16.0, 62.0, menuWidth, menuHeight)];
    menu.backgroundColor = [UIColor secondarySystemGroupedBackgroundColor];
    menu.layer.cornerRadius = 14.0;
    menu.layer.shadowColor = [UIColor blackColor].CGColor;
    menu.layer.shadowOpacity = 0.18;
    menu.layer.shadowRadius = 14.0;
    menu.layer.shadowOffset = CGSizeMake(0, 4);

    UIScrollView *scroll = [[UIScrollView alloc] initWithFrame:menu.bounds];
    scroll.contentSize = CGSizeMake(menuWidth, models.count * rowHeight + 8.0);
    [menu addSubview:scroll];

    for (NSUInteger index = 0; index < models.count; index++) {
        NSString *model = models[index];
        DXAIMenuRow *row = [[DXAIMenuRow alloc] initWithFrame:CGRectMake(0, 4.0 + index * rowHeight, menuWidth, rowHeight)];
        BOOL isSelected = [model isEqualToString:selected];
        row.label.text = model;
        row.label.font = [UIFont systemFontOfSize:15.0 weight:isSelected ? UIFontWeightSemibold : UIFontWeightRegular];
        row.label.textColor = isSelected ? DXAIAccent() : [UIColor labelColor];
        row.tag = index;
        [row addTarget:self action:@selector(modelRowTapped:) forControlEvents:UIControlEventTouchUpInside];
        [scroll addSubview:row];
    }
    [self presentPopover:menu];
}

- (void)modelRowTapped:(UIButton *)sender {
    DXAIEngineInfo *engine = [self currentEngine];
    NSArray<NSString *> *models = [DXAIEngine modelsForEngine:engine];
    if (sender.tag < models.count) {
        [DXAIEngine setSelectedModelForEngine:engine model:models[sender.tag]];
        [self refreshModelButton];
    }
    [self dismissPopover];
}

- (void)plusTapped {
    if (self.popoverCatcher) {
        [self dismissPopover];
        return;
    }

    NSMutableArray<NSDictionary *> *items = [NSMutableArray array];
    [items addObject:@{@"title": DXAILocalized(@"AI_CARD_PHOTOS"),
                       @"symbol": @"photo.on.rectangle",
                       @"action": [NSValue valueWithPointer:@selector(photosRowTapped)]}];
    if ([UIImagePickerController isSourceTypeAvailable:UIImagePickerControllerSourceTypeCamera]) {
        [items addObject:@{@"title": DXAILocalized(@"AI_CARD_CAMERA"),
                           @"symbol": @"camera",
                           @"action": [NSValue valueWithPointer:@selector(cameraRowTapped)]}];
    }
    [items addObject:@{@"title": DXAILocalized(@"AI_CARD_FILES"),
                       @"symbol": @"doc",
                       @"action": [NSValue valueWithPointer:@selector(filesRowTapped)]}];

    CGFloat rowHeight = 50.0;
    CGFloat menuWidth = 168.0;
    CGFloat menuHeight = items.count * rowHeight + 8.0;
    CGFloat menuTop = CGRectGetMinY(self.inputBar.frame) - menuHeight - 10.0;
    UIView *menu = [[UIView alloc] initWithFrame:CGRectMake(14.0, menuTop, menuWidth, menuHeight)];
    menu.backgroundColor = [UIColor secondarySystemGroupedBackgroundColor];
    menu.layer.cornerRadius = 14.0;
    menu.layer.shadowColor = [UIColor blackColor].CGColor;
    menu.layer.shadowOpacity = 0.18;
    menu.layer.shadowRadius = 14.0;
    menu.layer.shadowOffset = CGSizeMake(0, 4);

    for (NSUInteger index = 0; index < items.count; index++) {
        NSDictionary *item = items[index];
        DXAIMenuRow *row = [[DXAIMenuRow alloc] initWithFrame:CGRectMake(0, 4.0 + index * rowHeight, menuWidth, rowHeight)];
        row.iconView.image = DXAISymbol(item[@"symbol"], 19, UIImageSymbolWeightMedium);
        row.label.text = item[@"title"];
        SEL action = (SEL)[item[@"action"] pointerValue];
        [row addTarget:self action:action forControlEvents:UIControlEventTouchUpInside];
        [menu addSubview:row];
    }
    [self presentPopover:menu];
}

- (void)photosRowTapped {
    [self dismissPopover];
    [self pickPhotos];
}

- (void)cameraRowTapped {
    [self dismissPopover];
    [self takePhoto];
}

- (void)filesRowTapped {
    [self dismissPopover];
    [self pickFiles];
}

#pragma mark - 附件选择

- (void)presentModalController:(UIViewController *)controller {
    if (!self.view.window) return;
    [self dismissPopover];
    [self.view.window makeKeyWindow];
    if (self.inputField.isFirstResponder) [self.inputField resignFirstResponder];
    [self presentViewController:controller animated:YES completion:nil];
}

- (void)pickPhotos {
    PHPickerConfiguration *configuration = [[PHPickerConfiguration alloc] init];
    configuration.filter = [PHPickerFilter imagesFilter];
    configuration.selectionLimit = 1;
    PHPickerViewController *picker = [[PHPickerViewController alloc] initWithConfiguration:configuration];
    picker.delegate = self;
    [self presentModalController:picker];
}

- (void)takePhoto {
    if (![UIImagePickerController isSourceTypeAvailable:UIImagePickerControllerSourceTypeCamera]) return;
    UIImagePickerController *picker = [[UIImagePickerController alloc] init];
    picker.sourceType = UIImagePickerControllerSourceTypeCamera;
    picker.delegate = self;
    picker.modalPresentationStyle = UIModalPresentationFullScreen;
    [self presentModalController:picker];
}

- (void)pickFiles {
    NSArray<UTType *> *types = @[UTTypeImage, UTTypePlainText, UTTypeUTF8PlainText];
    UIDocumentPickerViewController *picker = [[UIDocumentPickerViewController alloc] initForOpeningContentTypes:types asCopy:YES];
    picker.delegate = self;
    [self presentModalController:picker];
}

- (void)picker:(PHPickerViewController *)picker didFinishPicking:(NSArray<PHPickerResult *> *)results {
    [picker dismissViewControllerAnimated:YES completion:nil];
    PHPickerResult *result = results.firstObject;
    if (!result.itemProvider) return;
    __weak typeof(self) weakSelf = self;
    [result.itemProvider loadObjectOfClass:[UIImage class]
                         completionHandler:^(__kindof NSObject *object, NSError *error) {
        dispatch_async(dispatch_get_main_queue(), ^{
            __strong typeof(weakSelf) strongSelf = weakSelf;
            if (strongSelf && [object isKindOfClass:[UIImage class]]) {
                [strongSelf updateAttachedImage:(UIImage *)object];
            }
        });
    }];
}

- (void)imagePickerController:(UIImagePickerController *)picker didFinishPickingMediaWithInfo:(NSDictionary<UIImagePickerControllerInfoKey, id> *)info {
    UIImage *image = info[UIImagePickerControllerOriginalImage];
    [picker dismissViewControllerAnimated:YES completion:nil];
    if (image) [self updateAttachedImage:image];
}

- (void)imagePickerControllerDidCancel:(UIImagePickerController *)picker {
    [picker dismissViewControllerAnimated:YES completion:nil];
}

- (void)documentPicker:(UIDocumentPickerViewController *)controller didPickDocumentsAtURLs:(NSArray<NSURL *> *)urls {
    [controller dismissViewControllerAnimated:YES completion:nil];
    NSURL *url = urls.firstObject;
    if (!url) return;
    [url startAccessingSecurityScopedResource];
    UTType *type = nil;
    [url getResourceValue:&type forKey:NSURLContentTypeKey error:nil];
    if ([type conformsToType:UTTypeImage]) {
        UIImage *image = [UIImage imageWithContentsOfFile:url.path];
        if (image) [self updateAttachedImage:image];
    } else {
        NSString *text = [NSString stringWithContentsOfURL:url encoding:NSUTF8StringEncoding error:nil];
        if (text.length == 0) {
            [self alertWithMessage:DXAILocalized(@"AI_CARD_FILE_UNREADABLE")];
        } else {
            if (text.length > 20000) text = [[text substringToIndex:20000] stringByAppendingString:@"\n…"];
            self.pendingFileText = text;
            self.pendingFileName = url.lastPathComponent;
            self.attachedImage = nil;
            [self refreshChip];
        }
    }
    [url stopAccessingSecurityScopedResource];
}

- (void)documentPickerWasCancelled:(UIDocumentPickerViewController *)controller {
    [controller dismissViewControllerAnimated:YES completion:nil];
}

- (void)alertWithMessage:(NSString *)message {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:nil
                                                                  message:message
                                                           preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:DXAILocalized(@"ANSWER_OK")
                                              style:UIAlertActionStyleDefault
                                            handler:nil]];
    [self presentModalController:alert];
}

+ (UIButton *)circleButtonWithSymbol:(NSString *)symbol action:(SEL)action target:(id)target {
    UIButton *button = [UIButton buttonWithType:UIButtonTypeCustom];
    button.backgroundColor = DXAICircleChrome();
    button.layer.cornerRadius = 17.0;
    button.tintColor = DXAIAccent();
    [button setImage:DXAISymbol(symbol, 15.0, UIImageSymbolWeightSemibold) forState:UIControlStateNormal];
    [button addTarget:target action:action forControlEvents:UIControlEventTouchUpInside];
    return button;
}

@end

#pragma mark - 入口

@implementation DXAIPanel

+ (DXAIChatPanelController *)ensurePanelController {
    if (g_aiPanelWindow && g_aiPanelWindow.rootViewController && g_aiPanelWindow.windowScene) {
        return (DXAIChatPanelController *)g_aiPanelWindow.rootViewController;
    }

    UIWindowScene *scene = nil;
    UIKeyboardImpl *keyboard = [objc_getClass("UIKeyboardImpl") activeInstance];
    scene = keyboard.window.windowScene;
    if (!scene) scene = DXKeyWindow().windowScene;
    for (UIScene *connected in [UIApplication sharedApplication].connectedScenes) {
        if ([connected isKindOfClass:[UIWindowScene class]]) {
            scene = (UIWindowScene *)connected;
            break;
        }
    }
    if (!scene) return nil;

    if (g_aiPanelWindow) { // 旧窗口脱离了场景：连同旧会话一起丢弃
        g_aiPanelWindow.hidden = YES;
        g_aiPanelWindow.rootViewController = nil;
        g_aiPanelWindow = nil;
    }

    DXAIHostWindow *window = [[DXAIHostWindow alloc] initWithWindowScene:scene];
    window.frame = scene.coordinateSpace.bounds;
    window.windowLevel = 1000000.0;
    window.backgroundColor = UIColor.clearColor;
    window.hidden = YES;

    DXAIChatPanelController *controller = [[DXAIChatPanelController alloc] init];
    window.rootViewController = controller;
    g_aiPanelWindow = window;
    return controller;
}

+ (void)openFromKeyboardWithSeedText:(NSString *)seedText {
    if (isSpringBoard) return; // 面板依赖键盘进程上下文，SpringBoard 无键盘

    DXAIChatPanelController *controller = [self ensurePanelController];
    if (!controller) return;

    controller.hostKeyWindow = DXKeyWindow();
    controller.seedText = seedText;
    [controller applySeedIfFreshSession];
    [controller applyTheme];
    [controller refreshModelButton];
    if (g_aiBallWindow) g_aiBallWindow.hidden = YES;

    g_aiPanelWindow.hidden = NO;
    [controller repositionAnimated:NO];
}

+ (void)hidePanelAndShowBallIfNeeded {
    if (g_aiPanelWindow) g_aiPanelWindow.hidden = YES;
    if ([DXAIEngine ballEnabled]) [self showBall];
}

+ (void)closeAndDestroyPanel {
    if (g_aiBallWindow) {
        g_aiBallWindow.hidden = YES;
        g_aiBallWindow = nil;
    }
    if (g_aiPanelWindow) {
        g_aiPanelWindow.hidden = YES;
        g_aiPanelWindow.rootViewController = nil; // 会话销毁，控制器随之释放
        g_aiPanelWindow = nil;
    }
}

+ (void)ballWasTapped {
    if (g_aiBallWindow) g_aiBallWindow.hidden = YES;
    [self openFromKeyboardWithSeedText:nil];
}

+ (void)showBall {
    UIWindowScene *scene = g_aiPanelWindow.windowScene;
    if (!scene) {
        UIKeyboardImpl *keyboard = [objc_getClass("UIKeyboardImpl") activeInstance];
        scene = keyboard.window.windowScene ?: DXKeyWindow().windowScene;
    }
    if (!scene) return;

    if (!g_aiBallWindow || g_aiBallWindow.windowScene != scene) {
        if (g_aiBallWindow) {
            g_aiBallWindow.hidden = YES;
            g_aiBallWindow = nil;
        }
        DXAIBallWindow *ball = [[DXAIBallWindow alloc] initWithWindowScene:scene];
        ball.frame = scene.coordinateSpace.bounds;
        g_aiBallWindow = ball;
    }

    CGRect bounds = g_aiBallWindow.bounds;
    CGPoint center = CGPointMake(CGRectGetWidth(bounds) - 30.0, CGRectGetHeight(bounds) * 0.62);
    NSString *stored = [DXAIEngine ballStoredPosition];
    NSArray<NSString *> *parts = [stored componentsSeparatedByString:@","];
    if (parts.count == 2) {
        CGPoint parsed = CGPointMake(CGRectGetWidth(bounds) * [parts[0] floatValue],
                                     CGRectGetHeight(bounds) * [parts[1] floatValue]);
        if (!isnan(parsed.x) && !isnan(parsed.y)) center = parsed;
    }
    center.x = MIN(MAX(center.x, 30.0), CGRectGetWidth(bounds) - 30.0);
    center.y = MIN(MAX(center.y, 50.0), CGRectGetHeight(bounds) - 50.0);

    g_aiBallWindow.ballButton.center = center;
    g_aiBallWindow.ballButton.alpha = [DXAIEngine ballHalfHide] ? 0.45 : 1.0;
    g_aiBallWindow.hidden = NO;
}

+ (void)storeBallPosition:(CGPoint)center inBounds:(CGRect)bounds {
    if (CGRectGetWidth(bounds) <= 0.0 || CGRectGetHeight(bounds) <= 0.0) return;
    NSString *position = [NSString stringWithFormat:@"%.4f,%.4f",
                          center.x / CGRectGetWidth(bounds), center.y / CGRectGetHeight(bounds)];
    [DXAIEngine setBallStoredPosition:position];
}

@end
