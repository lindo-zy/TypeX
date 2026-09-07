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
    if (header && fabs(CGRectGetWidth(header.frame) - width) > 0.5) {
        header.frame = CGRectMake(0, 0, width, CGRectGetHeight(header.frame));
        self.table.tableHeaderView = header;
    }
    [self layoutHeaderSubviews];
    [self updateTopToolbarPreview];
}

// ── Build header: preview bar + text field ─────────────────────────────

- (void)buildTopToolbarPreview {
    CGFloat width = CGRectGetWidth(self.table.bounds);
    UIView *header = [[UIView alloc] initWithFrame:CGRectMake(0, 0, width, 136)];
    header.autoresizingMask = UIViewAutoresizingFlexibleWidth;

    // ── Section 1: toolbar preview ──
    UILabel *previewTitle = [[UILabel alloc] initWithFrame:CGRectMake(16, 7, width - 32, 18)];
    previewTitle.text = @"效果预览";
    previewTitle.font = [UIFont systemFontOfSize:13 weight:UIFontWeightSemibold];
    previewTitle.textColor = [UIColor secondaryLabelColor];
    [header addSubview:previewTitle];

    self.topToolbarPreview = [[UIView alloc] initWithFrame:CGRectMake(16, 30, MAX(0, width - 32), 30)];
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

    // ── Section 2: test input field ──
    UILabel *fieldTitle = [[UILabel alloc] initWithFrame:CGRectMake(16, 70, width - 32, 18)];
    fieldTitle.text = @"测试输入框（点击弹出键盘预览）";
    fieldTitle.font = [UIFont systemFontOfSize:13 weight:UIFontWeightSemibold];
    fieldTitle.textColor = [UIColor secondaryLabelColor];
    [header addSubview:fieldTitle];

    self.previewTextField = [[UITextField alloc] initWithFrame:CGRectMake(16, 93, MAX(0, width - 32), 36)];
    self.previewTextField.placeholder = @"点击此处弹出键盘…";
    self.previewTextField.font = [UIFont systemFontOfSize:15];
    self.previewTextField.borderStyle = UITextBorderStyleRoundedRect;
    self.previewTextField.delegate = self;
    self.previewTextField.returnKeyType = UIReturnKeyDone;
    self.previewTextField.clearButtonMode = UITextFieldViewModeWhileEditing;
    [header addSubview:self.previewTextField];

    self.table.tableHeaderView = header;
}

- (void)layoutHeaderSubviews {
    CGFloat width = CGRectGetWidth(self.table.bounds);
    UIView *header = self.table.tableHeaderView;
    if (!header) return;
    header.frame = CGRectMake(0, 0, width, 136);

    self.topToolbarPreview.frame = CGRectMake(16, 30, MAX(0, width - 32), 30);
    self.previewTextField.frame = CGRectMake(16, 93, MAX(0, width - 32), 36);
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
