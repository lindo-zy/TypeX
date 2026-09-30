#import "DXPKeyboardPanelPreviewView.h"
#import "../DXKeyboardPanelPreferences.h"
#import "../DXKeyboardPanelLayout.h"
#import "../DXHelper.h"
#import "../common.h"

@interface DXPKeyboardPanelPreviewView ()
@property(nonatomic, strong) UILabel *titleLabel;
@property(nonatomic, strong) UILabel *emptyLabel;
@property(nonatomic, strong) UIScrollView *scroll;
@property(nonatomic, copy) NSArray<UIView *> *items;
@property(nonatomic) NSInteger columns;
@property(nonatomic) CGFloat scale;
@end
@implementation DXPKeyboardPanelPreviewView
- (instancetype)initWithFrame:(CGRect)frame {
    if ((self = [super initWithFrame:frame])) {
        self.layer.cornerRadius = 22;
        self.clipsToBounds = YES;
        self.titleLabel = [UILabel new];
        self.titleLabel.font = [UIFont systemFontOfSize:15 weight:UIFontWeightSemibold];
        [self addSubview:self.titleLabel];
        self.scroll = [UIScrollView new];
        self.scroll.showsVerticalScrollIndicator = YES;
        [self addSubview:self.scroll];
        self.emptyLabel = [UILabel new];
        self.emptyLabel.numberOfLines = 0;
        self.emptyLabel.textAlignment = NSTextAlignmentCenter;
        self.emptyLabel.font = [UIFont systemFontOfSize:14];
        [self.scroll addSubview:self.emptyLabel];
    }
    return self;
}
- (void)configureWithPreferences:(NSDictionary *)preferences side:(NSString *)side {
    if (!NSThread.isMainThread) return;
    NSBundle *bundle = [NSBundle bundleWithPath:bundlePath];
    NSString *titleKey = [side isEqual:@"right"] ? @"KEYBOARD_PANEL_RIGHT" : ([side isEqual:@"common"] ? @"KEYBOARD_PANEL_COMMON" : @"KEYBOARD_PANEL_LEFT");
    self.titleLabel.text = [bundle localizedStringForKey:titleKey value:titleKey table:nil];
    self.emptyLabel.text = [bundle localizedStringForKey:@"KEYBOARD_PANEL_EMPTY" value:@"请先添加自定义动作" table:nil];
    BOOL dark = DXKeyboardPanelBool(preferences, kDXPanelDark, YES);
    UIColor *textColor = dark ? UIColor.whiteColor : UIColor.labelColor;
    self.backgroundColor = dark ? [UIColor colorWithWhite:0.10 alpha:1] : UIColor.systemBackgroundColor;
    self.titleLabel.textColor = textColor;
    self.emptyLabel.textColor = textColor;
    self.columns = (NSInteger)DXKeyboardPanelNumber(preferences, kDXPanelColumns, 4, 3, 5);
    self.scale = DXKeyboardPanelNumber(preferences, kDXPanelScale, 100, 70, 120) / 100;
    for (UIView *item in self.items) [item removeFromSuperview];
    NSArray *entries = DXKeyboardPanelFilterCustomItems(DXKeyboardPanelItems(preferences, side), preferences[kLinkActionskey], kLinkActionSelectorPrefix);
    NSMutableDictionary *definitions = [NSMutableDictionary dictionary];
    id stored = preferences[kLinkActionskey];
    if ([stored isKindOfClass:NSArray.class]) for (id entry in stored) {
        if ([entry isKindOfClass:NSDictionary.class] && [entry[@"selector"] isKindOfClass:NSString.class]) definitions[entry[@"selector"]] = entry;
    }
    NSMutableArray *items = [NSMutableArray array];
    for (NSDictionary *entry in entries) {
        NSDictionary *definition = definitions[entry[@"selector"]];
        UIView *item = [UIView new];
        UIView *circle = [UIView new];
        circle.tag = 1;
        circle.backgroundColor = dark ? [UIColor colorWithWhite:0 alpha:0.45] : [UIColor colorWithWhite:1 alpha:0.65];
        [item addSubview:circle];
        UIImageView *icon = [UIImageView new];
        icon.tag = 2;
        icon.contentMode = UIViewContentModeScaleAspectFit;
        icon.tintColor = textColor;
        id iconConfig = [entry[@"icon"] length] ? entry[@"icon"] : definition[@"icon"];
        if (![iconConfig isKindOfClass:NSString.class]) iconConfig = @"link";
        icon.image = [DXHelper imageForIconConfig:iconConfig defaultSymbolName:@"link"];
        [item addSubview:icon];
        UILabel *label = [UILabel new];
        label.tag = 3;
        id name = [entry[@"name"] length] ? entry[@"name"] : definition[@"name"];
        label.text = [name isKindOfClass:NSString.class] ? name : @"自定义动作";
        label.textColor = textColor;
        label.font = [UIFont systemFontOfSize:12 * self.scale];
        label.numberOfLines = 2;
        label.textAlignment = NSTextAlignmentCenter;
        label.adjustsFontSizeToFitWidth = YES;
        label.minimumScaleFactor = 0.8;
        [item addSubview:label];
        item.isAccessibilityElement = YES;
        item.accessibilityLabel = label.text;
        [self.scroll addSubview:item];
        [items addObject:item];
    }
    self.items = items;
    self.emptyLabel.hidden = items.count > 0;
    self.scroll.contentOffset = CGPointZero;
    [self setNeedsLayout];
}
- (void)layoutSubviews {
    [super layoutSubviews];
    CGFloat width = self.bounds.size.width;
    self.titleLabel.frame = CGRectMake(16, 10, MAX(0, width - 32), 28);
    self.scroll.frame = CGRectMake(8, 46, MAX(0, width - 16), MAX(0, self.bounds.size.height - 54));
    CGFloat contentWidth = self.scroll.bounds.size.width;
    CGFloat circleSize = DXKeyboardPanelCircle(contentWidth, self.columns, self.scale);
    [self.items enumerateObjectsUsingBlock:^(UIView *item, NSUInteger index, BOOL *stop) {
        item.frame = DXKeyboardPanelItemFrame(index, contentWidth, self.columns, self.scale);
        CGFloat itemWidth = item.bounds.size.width;
        UIView *circle = [item viewWithTag:1];
        circle.frame = CGRectMake((itemWidth - circleSize) / 2, 4, circleSize, circleSize);
        circle.layer.cornerRadius = circleSize / 2;
        CGFloat iconSize = circleSize * 0.52;
        [item viewWithTag:2].frame = CGRectMake((itemWidth - iconSize) / 2, 4 + (circleSize - iconSize) / 2, iconSize, iconSize);
        [item viewWithTag:3].frame = CGRectMake(3, circleSize + 9, MAX(0, itemWidth - 6), 30 * self.scale);
    }];
    self.scroll.contentSize = CGSizeMake(contentWidth, MAX(self.scroll.bounds.size.height, DXKeyboardPanelContentHeight(self.items.count, contentWidth, self.columns, self.scale)));
    self.emptyLabel.frame = self.scroll.bounds;
}
@end
