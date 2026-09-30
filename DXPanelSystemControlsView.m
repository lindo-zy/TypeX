#import "DXPanelSystemControlsView.h"
#import "DXPanelControlState.h"

@interface DXPanelPillSlider : UIControl
@property(nonatomic) float value;
@property(nonatomic, strong) UIView *fill;
@property(nonatomic, strong) UIImageView *icon;
@end
@implementation DXPanelPillSlider
- (instancetype)initWithFrame:(CGRect)frame {
    if ((self = [super initWithFrame:frame])) {
        self.clipsToBounds = YES;
        self.backgroundColor = [UIColor colorWithWhite:0 alpha:0.45];
        self.fill = [UIView new]; self.fill.backgroundColor = UIColor.whiteColor;
        self.icon = [UIImageView new]; self.icon.contentMode = UIViewContentModeScaleAspectFit;
        self.fill.userInteractionEnabled = NO; self.icon.userInteractionEnabled = NO;
        [self addSubview:self.fill]; [self addSubview:self.icon];
        self.isAccessibilityElement = YES; self.accessibilityTraits = UIAccessibilityTraitAdjustable;
    }
    return self;
}
- (void)setValue:(float)value { _value = MIN(1, MAX(0, value)); [self setNeedsLayout]; }
- (void)setEnabled:(BOOL)enabled { [super setEnabled:enabled]; self.alpha = enabled ? 1 : 0.35; }
- (void)layoutSubviews {
    [super layoutSubviews];
    CGFloat width = self.bounds.size.width, height = self.bounds.size.height;
    self.layer.cornerRadius = height / 2;
    self.fill.frame = CGRectMake(0, 0, width * self.value, height);
    self.icon.frame = CGRectMake((width - 24) / 2, (height - 24) / 2, 24, 24);
    self.icon.tintColor = self.value >= 0.5 ? [UIColor colorWithWhite:0.12 alpha:1] : UIColor.whiteColor;
    self.accessibilityValue = self.enabled ? [NSString stringWithFormat:@"%ld%%", (long)lroundf(self.value * 100)] : @"不可用";
}
- (void)updateFromTouch:(UITouch *)touch {
    if (!self.enabled || self.bounds.size.width <= 0) return;
    self.value = [touch locationInView:self].x / self.bounds.size.width;
    [self sendActionsForControlEvents:UIControlEventValueChanged];
}
- (BOOL)beginTrackingWithTouch:(UITouch *)touch withEvent:(UIEvent *)event {
    (void)event; if (!self.enabled) return NO;
    [self updateFromTouch:touch]; return YES;
}
- (BOOL)continueTrackingWithTouch:(UITouch *)touch withEvent:(UIEvent *)event { (void)event; [self updateFromTouch:touch]; return YES; }
- (void)endTrackingWithTouch:(UITouch *)touch withEvent:(UIEvent *)event { (void)event; if (touch) [self updateFromTouch:touch]; }
- (void)accessibilityIncrement { if (self.enabled) { self.value += 0.05; [self sendActionsForControlEvents:UIControlEventValueChanged]; } }
- (void)accessibilityDecrement { if (self.enabled) { self.value -= 0.05; [self sendActionsForControlEvents:UIControlEventValueChanged]; } }
@end

@interface DXPanelSystemControlsView ()
@property(nonatomic, strong) NSArray<UIButton *> *buttons;
@property(nonatomic, strong) NSArray<UILabel *> *labels;
@property(nonatomic, strong) DXPanelPillSlider *brightness;
@property(nonatomic, strong) DXPanelPillSlider *volume;
@property(nonatomic, strong) NSDictionary *state;
@property(nonatomic, strong) UILabel *message;
@property(nonatomic) BOOL dark;
@property(nonatomic) BOOL preview;
@property(nonatomic) BOOL busy;
@end
@implementation DXPanelSystemControlsView
- (instancetype)initWithFrame:(CGRect)frame {
    if ((self = [super initWithFrame:frame])) {
        NSArray *names = @[@"手电筒", @"无线网络", @"静音", @"深色模式", @"方向锁定"];
        NSArray *icons = @[@"flashlight.on.fill", @"wifi", @"bell.slash.fill", @"circle.lefthalf.filled", @"lock.rotation"];
        NSMutableArray *buttons = [NSMutableArray array], *labels = [NSMutableArray array];
        for (NSUInteger index = 0; index < names.count; index++) {
            UIButton *button = [UIButton buttonWithType:UIButtonTypeCustom]; button.tag = index;
            [button setImage:[UIImage systemImageNamed:icons[index] withConfiguration:[UIImageSymbolConfiguration configurationWithPointSize:24 weight:UIImageSymbolWeightRegular]] forState:UIControlStateNormal];
            button.accessibilityLabel = names[index];
            [button addTarget:self action:@selector(tapped:) forControlEvents:UIControlEventTouchUpInside];
            [self addSubview:button]; [buttons addObject:button];
            UILabel *label = [UILabel new]; label.text = names[index]; label.textAlignment = NSTextAlignmentCenter;
            label.font = [UIFont systemFontOfSize:11]; label.numberOfLines = 2;
            label.adjustsFontSizeToFitWidth = YES; label.minimumScaleFactor = 0.8;
            [self addSubview:label]; [labels addObject:label];
        }
        self.buttons = buttons; self.labels = labels;
        self.brightness = [DXPanelPillSlider new]; self.volume = [DXPanelPillSlider new];
        self.brightness.icon.image = [UIImage systemImageNamed:@"sun.max.fill"];
        self.volume.icon.image = [UIImage systemImageNamed:@"speaker.wave.2.fill"];
        self.brightness.accessibilityLabel = @"亮度"; self.volume.accessibilityLabel = @"媒体音量";
        for (DXPanelPillSlider *slider in @[self.brightness, self.volume]) {
            [slider addTarget:self action:@selector(adjusted:) forControlEvents:UIControlEventValueChanged]; [self addSubview:slider];
        }
        self.message = [UILabel new]; self.message.font = [UIFont systemFontOfSize:10];
        self.message.textAlignment = NSTextAlignmentCenter; self.message.adjustsFontSizeToFitWidth = YES;
        [self addSubview:self.message];
        [self configureDark:YES preview:NO];
    }
    return self;
}
- (void)configureDark:(BOOL)dark preview:(BOOL)preview {
    self.dark = dark; self.preview = preview; self.userInteractionEnabled = !preview;
    if (preview) self.state = @{@"flashlight": @NO, @"wifi": @YES, @"silent": @YES, @"dark-mode": @NO, @"orientation-lock": @YES, @"brightness": @0.62, @"volume": @0.38};
    [self applyState:self.state ?: @{} busy:NO];
}
- (void)applyState:(NSDictionary *)state busy:(BOOL)busy {
    // A nil state is an in-flight marker, not a replacement for known values.
    if (state) {
        self.state = [state copy];
    }
    self.busy = busy;
    self.message.textColor = self.dark ? UIColor.whiteColor : UIColor.labelColor;
    NSArray *ids = DXPanelToggleIdentifiers();
    for (NSUInteger index = 0; index < self.buttons.count; index++) {
        UIButton *button = self.buttons[index]; NSNumber *value = self.state[ids[index]];
        BOOL known = [value isKindOfClass:NSNumber.class], on = known && value.boolValue;
        button.backgroundColor = on ? UIColor.systemBlueColor : (self.dark ? [UIColor colorWithWhite:0 alpha:0.5] : [UIColor colorWithWhite:0.8 alpha:0.65]);
        button.tintColor = on || self.dark ? UIColor.whiteColor : UIColor.labelColor;
        button.alpha = known ? 1 : 0.35; button.enabled = known && !busy;
        button.accessibilityValue = known ? (on ? @"已开启" : @"已关闭") : @"不可用";
        self.labels[index].textColor = self.dark ? UIColor.whiteColor : UIColor.labelColor;
    }
    for (NSUInteger index = 0; index < 2; index++) {
        DXPanelPillSlider *slider = index ? self.volume : self.brightness;
        NSNumber *value = self.state[index ? @"volume" : @"brightness"];
        slider.enabled = [value isKindOfClass:NSNumber.class];
        if (slider.enabled && !slider.tracking) slider.value = value.floatValue;
    }
}
- (void)showMessage:(NSString *)message { self.message.text = message; }
- (void)tapped:(UIButton *)button { if (!self.preview && !self.busy && button.enabled && self.actionHandler) self.actionHandler(DXPanelToggleIdentifiers()[button.tag], nil); }
- (void)adjusted:(DXPanelPillSlider *)slider { if (!self.preview && self.actionHandler) self.actionHandler(slider == self.brightness ? @"brightness" : @"volume", @(slider.value)); }
- (void)layoutSubviews {
    [super layoutSubviews];
    CGFloat width = self.bounds.size.width, itemWidth = width / 5, circle = DXPanelControlCircle(width);
    for (NSUInteger index = 0; index < self.buttons.count; index++) {
        self.buttons[index].frame = CGRectMake(index * itemWidth + (itemWidth - circle) / 2, 0, circle, circle);
        self.buttons[index].layer.cornerRadius = circle / 2;
        self.labels[index].frame = CGRectMake(index * itemWidth, circle + 4, itemWidth, 24);
    }
    CGFloat sliderTop = circle + 24 + 12, half = MAX(0, (width - 12) / 2);
    self.brightness.frame = CGRectMake(0, sliderTop, half, 50);
    self.volume.frame = CGRectMake(half + 12, sliderTop, half, 50);
    self.message.frame = CGRectMake(0, sliderTop + 50, width, 14);
}
@end
