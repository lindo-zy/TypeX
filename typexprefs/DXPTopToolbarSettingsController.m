#import "DXPTopToolbarSettingsController.h"
#import "DXPTopToolbarNativeColorCell.h"
#import "../common.h"
#import "../DXPrefsManager.h"

// ── Helper: UIColor → hex string (with alpha) ──────────────────────────
static NSString *DXHexFromColor(UIColor *color) {
    CGFloat r = 0, g = 0, b = 0, a = 0;
    [color getRed:&r green:&g blue:&b alpha:&a];
    unsigned int ri = (unsigned int)(r * 255.0 + 0.5);
    unsigned int gi = (unsigned int)(g * 255.0 + 0.5);
    unsigned int bi = (unsigned int)(b * 255.0 + 0.5);
    unsigned int ai = (unsigned int)(a * 255.0 + 0.5);
    if (ai >= 255) {
        return [NSString stringWithFormat:@"#%02X%02X%02X", ri, gi, bi];
    }
    return [NSString stringWithFormat:@"#%02X%02X%02X%02X", ai, ri, gi, bi];
}

// Header geometry: the test input section sits at the TOP of the header and
// is collapsed by default; pulling the list down reveals it, pulling down
// again collapses it. Collapsed height keeps only the toolbar preview.
static CGFloat const DXHeaderCollapsedHeight = 66.0;
static CGFloat const DXHeaderExpandedHeight = 136.0;

@interface DXPTopToolbarSettingsController ()
@property (nonatomic, assign) BOOL testFieldExpanded;
@property (nonatomic, assign) BOOL pullConsumed;
@end

@implementation DXPTopToolbarSettingsController

- (NSArray *)specifiers {
    if (!_specifiers)
        _specifiers = [self loadSpecifiersFromPlistName:@"TopToolbarSettings" target:self];
    return _specifiers;
}

- (id)readPreferenceValue:(PSSpecifier *)specifier {
    id value = [super readPreferenceValue:specifier];
    id stored = [[DXPrefsManager sharedInstance] getValueForKey:[specifier propertyForKey:@"key"]];
    return stored ?: value;
}

- (void)setPreferenceValue:(id)value specifier:(PSSpecifier *)specifier {
    NSString *key = [specifier propertyForKey:@"key"];
    if (key.length)
        [[DXPrefsManager sharedInstance] setValue:value forKey:key];
    else
        [super setPreferenceValue:value specifier:specifier];
    [self updateTopToolbarPreview];
}

// ── View lifecycle ─────────────────────────────────────────────────────

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"顶部工具栏";
    [self buildTopToolbarPreview];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [self updateTopToolbarPreview];
}

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    UIView *header = self.table.tableHeaderView;
    CGFloat width = CGRectGetWidth(self.table.bounds);
    CGFloat height = self.testFieldExpanded ? DXHeaderExpandedHeight : DXHeaderCollapsedHeight;
    if (header && (fabs(CGRectGetWidth(header.frame) - width) > 0.5 || fabs(CGRectGetHeight(header.frame) - height) > 0.5)) {
        header.frame = CGRectMake(0, 0, width, height);
        self.table.tableHeaderView = header;
    }
    [self layoutHeaderSubviews];
    [self updateTopToolbarPreview];
}

// ── Build header: test input (top) + preview bar ───────────────────────

- (void)buildTopToolbarPreview {
    CGFloat width = CGRectGetWidth(self.table.bounds);
    UIView *header = [[UIView alloc] initWithFrame:CGRectMake(0, 0, width, DXHeaderCollapsedHeight)];
    header.autoresizingMask = UIViewAutoresizingFlexibleWidth;
    header.clipsToBounds = YES;

    // ── Section 1: test input field (top, pull-down to reveal) ──
    UILabel *fieldTitle = [[UILabel alloc] initWithFrame:CGRectMake(16, 7, width - 32, 18)];
    fieldTitle.tag = 900;
    fieldTitle.text = @"测试输入框（下拉显示，再次下拉收起）";
    fieldTitle.font = [UIFont systemFontOfSize:13 weight:UIFontWeightSemibold];
    fieldTitle.textColor = [UIColor secondaryLabelColor];
    [header addSubview:fieldTitle];

    self.previewTextField = [[UITextField alloc] initWithFrame:CGRectMake(16, 30, MAX(0, width - 32), 36)];
    self.previewTextField.placeholder = @"点击此处弹出键盘…";
    self.previewTextField.font = [UIFont systemFontOfSize:15];
    self.previewTextField.borderStyle = UITextBorderStyleRoundedRect;
    self.previewTextField.delegate = self;
    self.previewTextField.returnKeyType = UIReturnKeyDone;
    self.previewTextField.clearButtonMode = UITextFieldViewModeWhileEditing;
    [header addSubview:self.previewTextField];

    // ── Section 2: toolbar preview ──
    UILabel *previewTitle = [[UILabel alloc] initWithFrame:CGRectMake(16, 76, width - 32, 18)];
    previewTitle.tag = 901;
    previewTitle.text = @"效果预览";
    previewTitle.font = [UIFont systemFontOfSize:13 weight:UIFontWeightSemibold];
    previewTitle.textColor = [UIColor secondaryLabelColor];
    [header addSubview:previewTitle];

    self.topToolbarPreview = [[UIView alloc] initWithFrame:CGRectMake(16, 99, MAX(0, width - 32), 30)];
    self.topToolbarPreview.layer.cornerRadius = 6;
    self.topToolbarPreview.clipsToBounds = YES;
    [header addSubview:self.topToolbarPreview];

    for (NSUInteger index = 0; index < 6; index++) {
        UIView *button = [[UIView alloc] initWithFrame:CGRectZero];
        button.tag = 100 + index;
        button.backgroundColor = [UIColor colorWithWhite:1 alpha:0.22];
        button.layer.cornerRadius = 4;
        [self.topToolbarPreview addSubview:button];
    }

    self.table.tableHeaderView = header;
}

- (void)layoutHeaderSubviews {
    CGFloat width = CGRectGetWidth(self.table.bounds);
    UIView *header = self.table.tableHeaderView;
    if (!header) return;
    header.frame = CGRectMake(0, 0, width, self.testFieldExpanded ? DXHeaderExpandedHeight : DXHeaderCollapsedHeight);

    UILabel *fieldTitle = (UILabel *)[header viewWithTag:900];
    UILabel *previewTitle = (UILabel *)[header viewWithTag:901];
    fieldTitle.frame = CGRectMake(16, 7, MAX(0, width - 32), 18);
    self.previewTextField.frame = CGRectMake(16, 30, MAX(0, width - 32), 36);
    previewTitle.frame = CGRectMake(16, 76, MAX(0, width - 32), 18);
    self.topToolbarPreview.frame = CGRectMake(16, 99, MAX(0, width - 32), 30);
}

// Pull-down gesture: one drag past the threshold toggles the test section;
// pullConsumed makes one drag fire exactly once.
- (void)scrollViewDidScroll:(UIScrollView *)scrollView {
    if (scrollView != self.table) return;
    CGFloat offset = scrollView.contentOffset.y;
    if (scrollView.isTracking && offset < -60.0 && !self.pullConsumed) {
        self.pullConsumed = YES;
        [UIView animateWithDuration:0.25 animations:^{
            UIView *header = self.table.tableHeaderView;
            header.frame = CGRectMake(0, 0, CGRectGetWidth(self.table.bounds),
                                      self.testFieldExpanded ? DXHeaderCollapsedHeight : DXHeaderExpandedHeight);
            self.table.tableHeaderView = header;
        }];
        self.testFieldExpanded = !self.testFieldExpanded;
    }
    if (offset > -20.0) self.pullConsumed = NO;
}

// ── Update preview ─────────────────────────────────────────────────────

- (void)updateTopToolbarPreview {
    if (!self.topToolbarPreview) return;
    UIColor *background = DXColorFromHex(
        [[DXPrefsManager sharedInstance] getValueForKey:kTopToolbarBackgroundTintKey],
        @"#5B5B5B");
    self.topToolbarPreview.backgroundColor = background;

    CGFloat width = CGRectGetWidth(self.topToolbarPreview.bounds);
    CGFloat gap = 4;
    CGFloat buttonWidth = (width - gap * 7) / 6;
    [self.topToolbarPreview.subviews enumerateObjectsUsingBlock:^(UIView *button, NSUInteger index, BOOL *stop) {
        button.frame = CGRectMake(gap + index * (buttonWidth + gap), 5, buttonWidth, 20);
    }];
}

// ── UITextFieldDelegate ────────────────────────────────────────────────

- (void)textFieldDidBeginEditing:(UITextField *)textField {
    DXPlaceCaretAtEnd(textField);
}

- (BOOL)textFieldShouldReturn:(UITextField *)textField {
    [textField resignFirstResponder];
    return YES;
}

// ── System UIColorPickerViewController ─────────────────────────────────

- (void)presentSystemColorPickerForKey:(NSString *)key {
    self.pendingColorKey = key;
    UIColorPickerViewController *vc = [[UIColorPickerViewController alloc] init];
    vc.delegate = self;
    vc.supportsAlpha = YES;

    // Seed with current value
    NSString *hex = [[DXPrefsManager sharedInstance] getValueForKey:key];
    if (hex.length) {
        vc.selectedColor = DXColorFromHex(hex, @"#5B5B5B");
    }

    [self presentViewController:vc animated:YES completion:nil];
}

// UIColorPickerViewControllerDelegate
- (void)colorPickerViewControllerDidFinish:(UIColorPickerViewController *)viewController {
    NSString *hex = DXHexFromColor(viewController.selectedColor);
    if (self.pendingColorKey.length) {
        [[DXPrefsManager sharedInstance] setValue:hex forKey:self.pendingColorKey];
        [self updateTopToolbarPreview];
    }
    self.pendingColorKey = nil;
}

- (void)colorPickerViewController:(UIColorPickerViewController *)viewController
       didSelectColor:(UIColor *)color
            continuously:(BOOL)continuously {
    // Live-update the preview as the user drags
    NSString *hex = DXHexFromColor(color);
    if (self.pendingColorKey.length) {
        [[DXPrefsManager sharedInstance] setValue:hex forKey:self.pendingColorKey];
        [self updateTopToolbarPreview];
    }
}

@end
