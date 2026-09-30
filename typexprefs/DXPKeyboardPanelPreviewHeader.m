#import "DXPKeyboardPanelPreviewHeader.h"
#import "DXPKeyboardPanelPreviewView.h"
#import "../common.h"
#import "../DXKeyboardPanelPreferences.h"

@interface DXPKeyboardPanelPreviewHeader ()
@property(nonatomic, copy) NSString *side;
@property(nonatomic, strong) UILabel *caption;
@property(nonatomic, strong) UISegmentedControl *selector;
@property(nonatomic, strong) DXPKeyboardPanelPreviewView *preview;
@end
@implementation DXPKeyboardPanelPreviewHeader
- (instancetype)initWithSide:(NSString *)side allowsSelection:(BOOL)allowsSelection {
    if ((self = [super initWithFrame:CGRectMake(0, 0, 320, allowsSelection ? 476 : 436)])) {
        self.side = side;
        self.autoresizingMask = UIViewAutoresizingFlexibleWidth;
        self.caption = [UILabel new];
        self.caption.text = @"面板预览（顶部状态为示意）";
        self.caption.textColor = UIColor.secondaryLabelColor;
        self.caption.font = [UIFont systemFontOfSize:13];
        [self addSubview:self.caption];
        if (allowsSelection) {
            self.selector = [[UISegmentedControl alloc] initWithItems:@[@"左面板", @"右面板", @"通用面板"]];
            self.selector.selectedSegmentIndex = [side isEqual:@"right"] ? 1 : ([side isEqual:@"common"] ? 2 : 0);
            [self.selector addTarget:self action:@selector(selectionChanged:) forControlEvents:UIControlEventValueChanged];
            [self addSubview:self.selector];
        }
        self.preview = [DXPKeyboardPanelPreviewView new];
        [self addSubview:self.preview];
        [self refresh];
    }
    return self;
}
- (void)selectionChanged:(UISegmentedControl *)sender {
    self.side = @[@"left", @"right", @"common"][MIN(2, MAX(0, sender.selectedSegmentIndex))];
    [self refresh];
}
- (void)refresh {
    [self.preview configureWithPreferences:[DXPrefsManager.sharedInstance readPrefs] side:self.side];
}
- (void)layoutSubviews {
    [super layoutSubviews];
    CGFloat width = MAX(0, self.bounds.size.width - 32);
    self.caption.frame = CGRectMake(20, 12, width, 20);
    CGFloat top = 40;
    if (self.selector) { self.selector.frame = CGRectMake(16, top, width, 32); top += 40; }
    self.preview.frame = CGRectMake(16, top, width, 380);
}
@end
