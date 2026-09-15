#import "DXPLinkActionEditorController.h"
#import "DXPAppPickerController.h"
#import "DXPAppShortcutPickerController.h"
#import "../DXHelper.h"
#import "../common.h"

static NSBundle *tweakBundle;

// Typed rows. 0-2 are shared by every type (类型 / 名称 / 图标); the payload
// row and its neighbors depend on the entry's type:
// - urlscheme: section 1 = full-width 文本框 (multi-line payload box)
// - text:      section 1 = full-width 文本框 (multi-line payload box)
// - openapp:   3 = 打开应用 (picker row)
// - url:       3 = URL 设置 (field), 4 = APP内打开 switch
// - shortcut:  3 = 快捷方式 (picker row)
// The box types use two sections: section 0 holds the shared rows, section 1
// the payload box with the type label as its header and hint as its footer.
// Entries without a type keep the legacy layout (动作链接 + the two old
// helper rows) so existing definitions keep editing exactly as before.
static NSInteger const DXActionRowType = 0;
static NSInteger const DXActionRowName = 1;
static NSInteger const DXActionRowIcon = 2;
static NSInteger const DXActionRowPayload = 3;
static NSInteger const DXActionRowInApp = 4;

static NSInteger const DXLegacyRowName = 0;
static NSInteger const DXLegacyRowIcon = 1;
static NSInteger const DXLegacyRowLink = 2;
static NSInteger const DXLegacyRowOpenApp = 3;
static NSInteger const DXLegacyRowShortcutPreview = 4;

// Label left, current value right: the type row and the payload picker rows.
@interface DXPLinkActionValueCell : UITableViewCell
@end

@implementation DXPLinkActionValueCell
- (instancetype)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)reuseIdentifier {
    return [super initWithStyle:UITableViewCellStyleValue1 reuseIdentifier:reuseIdentifier];
}
@end

// Full-width multi-line text box (a UITextView filling the cell) used for the
// url scheme / text payloads instead of a small accessory field.
@interface DXPLinkActionTextCell : UITableViewCell
@property (nonatomic, strong) UITextView *textView;
@property (nonatomic, strong) UILabel *placeholderLabel;
@end

@implementation DXPLinkActionTextCell
- (instancetype)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)reuseIdentifier {
    if ((self = [super initWithStyle:style reuseIdentifier:reuseIdentifier])) {
        self.selectionStyle = UITableViewCellSelectionStyleNone;

        self.textView = [[UITextView alloc] init];
        self.textView.font = [UIFont systemFontOfSize:17];
        self.textView.backgroundColor = UIColor.clearColor;
        self.textView.textContainerInset = UIEdgeInsetsZero;
        self.textView.textContainer.lineFragmentPadding = 0;
        self.textView.translatesAutoresizingMaskIntoConstraints = NO;
        [self.contentView addSubview:self.textView];

        self.placeholderLabel = [[UILabel alloc] init];
        self.placeholderLabel.font = self.textView.font;
        self.placeholderLabel.textColor = [UIColor placeholderTextColor];
        self.placeholderLabel.numberOfLines = 0;
        self.placeholderLabel.translatesAutoresizingMaskIntoConstraints = NO;
        [self.contentView addSubview:self.placeholderLabel];

        [NSLayoutConstraint activateConstraints:@[
            [self.textView.topAnchor constraintEqualToAnchor:self.contentView.topAnchor constant:12],
            [self.textView.bottomAnchor constraintEqualToAnchor:self.contentView.bottomAnchor constant:-12],
            [self.textView.leadingAnchor constraintEqualToAnchor:self.contentView.layoutMarginsGuide.leadingAnchor],
            [self.textView.trailingAnchor constraintEqualToAnchor:self.contentView.layoutMarginsGuide.trailingAnchor],

            [self.placeholderLabel.topAnchor constraintEqualToAnchor:self.textView.topAnchor],
            [self.placeholderLabel.leadingAnchor constraintEqualToAnchor:self.textView.leadingAnchor],
            [self.placeholderLabel.trailingAnchor constraintEqualToAnchor:self.textView.trailingAnchor],
        ]];
    }
    return self;
}
@end

@interface DXPLinkActionEditorController ()
@property (nonatomic, strong) UITableView *tableView;
@property (nonatomic, strong) UITextField *nameField;
@property (nonatomic, strong) UITextField *iconField;
@property (nonatomic, strong) UITextField *linkField;
@property (nonatomic, strong) UISwitch *inAppSwitch;
// The one payload box cell for the box types (url scheme / text); kept as a
// property so its text survives cell reuse while scrolling.
@property (nonatomic, strong) DXPLinkActionTextCell *payloadBoxCell;
@end

@implementation DXPLinkActionEditorController {
    NSString *_displayedType;
}

#pragma mark - Type helpers

+ (void)loadTweakBundle {
    if (!tweakBundle) {
        tweakBundle = [NSBundle bundleWithPath:bundlePath];
        [tweakBundle load];
    }
}

+ (NSString *)displayNameForType:(NSString *)type {
    [self loadTweakBundle];
    if ([type isEqualToString:kCustomActionTypeURLScheme]) return LOCALIZED(@"ACTION_TYPE_URL_SCHEME");
    if ([type isEqualToString:kCustomActionTypeText]) return LOCALIZED(@"ACTION_TYPE_TEXT");
    if ([type isEqualToString:kCustomActionTypeOpenApp]) return LOCALIZED(@"OPEN_APP");
    if ([type isEqualToString:kCustomActionTypeURL]) return LOCALIZED(@"ACTION_TYPE_URL");
    if ([type isEqualToString:kCustomActionTypeShortcut]) return LOCALIZED(@"SHORTCUTS");
    return type;
}

+ (NSString *)defaultIconForType:(NSString *)type {
    if ([type isEqualToString:kCustomActionTypeText]) return @"doc.text";
    if ([type isEqualToString:kCustomActionTypeOpenApp]) return @"apps.iphone";
    if ([type isEqualToString:kCustomActionTypeURL]) return @"globe";
    if ([type isEqualToString:kCustomActionTypeShortcut]) return @"square.grid.2x2";
    return @"link";
}

// Used by the management page's 添加 flow: the type is chosen here and is
// then fixed for the entry's life — the editor's 类型 row only displays it.
// The order places URL Scheme first because it is the default for new
// actions; sub-action-only types carry a suffix so the restriction is
// visible before the choice is made.
+ (void)presentTypeChooserFromController:(UIViewController *)controller
                             currentType:(NSString *)currentType
                              completion:(void (^)(NSString *type))completion {
    [self loadTweakBundle];
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:LOCALIZED(@"CHOOSE_ACTION_TYPE")
                                                                   message:nil
                                                            preferredStyle:UIAlertControllerStyleAlert];
    NSArray<NSString *> *types = @[
        kCustomActionTypeURLScheme,
        kCustomActionTypeText,
        kCustomActionTypeURL,
        kCustomActionTypeOpenApp,
        kCustomActionTypeShortcut,
    ];
    for (NSString *type in types) {
        NSString *title = [self displayNameForType:type];
        if (DXIsSubActionOnlyCustomActionType(type)) {
            title = [title stringByAppendingString:LOCALIZED(@"SUB_ACTION_ONLY_SUFFIX")];
        }
        [alert addAction:[UIAlertAction actionWithTitle:title
                                                  style:UIAlertActionStyleDefault
                                                handler:^(__unused UIAlertAction *action) {
            if (completion) completion(type);
        }]];
    }
    [alert addAction:[UIAlertAction actionWithTitle:LOCALIZED(@"ANSWER_CANCEL")
                                              style:UIAlertActionStyleCancel
                                            handler:nil]];
    [controller presentViewController:alert animated:YES completion:nil];
}

#pragma mark - Layout

- (BOOL)isLegacyEntry {
    return _displayedType.length == 0;
}

- (NSInteger)rowCount {
    if (self.isLegacyEntry) return 5;
    BOOL hasSwitch = [_displayedType isEqualToString:kCustomActionTypeURL];
    return DXActionRowPayload + 1 + (hasSwitch ? 1 : 0);
}

- (NSString *)typeFooter {
    if (self.isLegacyEntry) return LOCALIZED(@"CUSTOM_LINK_ACTION_FOOTER");
    if ([_displayedType isEqualToString:kCustomActionTypeURLScheme]) return LOCALIZED(@"TYPE_FOOTER_URL_SCHEME");
    if ([_displayedType isEqualToString:kCustomActionTypeText]) return LOCALIZED(@"TYPE_FOOTER_TEXT");
    if ([_displayedType isEqualToString:kCustomActionTypeOpenApp]) return LOCALIZED(@"TYPE_FOOTER_OPEN_APP");
    if ([_displayedType isEqualToString:kCustomActionTypeURL]) return LOCALIZED(@"TYPE_FOOTER_URL");
    if ([_displayedType isEqualToString:kCustomActionTypeShortcut]) return LOCALIZED(@"TYPE_FOOTER_SHORTCUT");
    return nil;
}

- (UITextField *)fieldForRow:(NSInteger)row {
    if (self.isLegacyEntry) {
        if (row == DXLegacyRowName) return self.nameField;
        if (row == DXLegacyRowIcon) return self.iconField;
        if (row == DXLegacyRowLink) return self.linkField;
        return nil;
    }
    if (row == DXActionRowName) return self.nameField;
    if (row == DXActionRowIcon) return self.iconField;
    if (row == DXActionRowPayload && !DXIsSubActionOnlyCustomActionType(_displayedType)) return self.linkField;
    return nil;
}

- (NSString *)labelForRow:(NSInteger)row {
    if (self.isLegacyEntry) {
        if (row == DXLegacyRowName) return LOCALIZED(@"NAME");
        if (row == DXLegacyRowIcon) return LOCALIZED(@"ICON");
        if (row == DXLegacyRowLink) return LOCALIZED(@"ACTION_LINK");
        if (row == DXLegacyRowOpenApp) return LOCALIZED(@"OPEN_APP");
        return LOCALIZED(@"SHORTCUTS");
    }
    if (row == DXActionRowType) return LOCALIZED(@"ACTION_TYPE");
    if (row == DXActionRowName) return LOCALIZED(@"NAME");
    if (row == DXActionRowIcon) return LOCALIZED(@"ICON");
    if (row == DXActionRowPayload) {
        if ([_displayedType isEqualToString:kCustomActionTypeURLScheme]) return LOCALIZED(@"URL_SCHEME_SETTINGS");
        if ([_displayedType isEqualToString:kCustomActionTypeText]) return LOCALIZED(@"TEXT_SETTINGS");
        if ([_displayedType isEqualToString:kCustomActionTypeURL]) return LOCALIZED(@"URL_SETTINGS");
        if ([_displayedType isEqualToString:kCustomActionTypeOpenApp]) return LOCALIZED(@"OPEN_APP");
        if ([_displayedType isEqualToString:kCustomActionTypeShortcut]) return LOCALIZED(@"SHORTCUTS");
    }
    if (row == DXActionRowInApp) return LOCALIZED(@"OPEN_IN_APP");
    return @"";
}

// Adjust keyboard and placeholder so the payload field matches the type.
- (void)applyTypeToPayloadField {
    if (!self.linkField) return;
    NSString *placeholder = @"";
    if ([_displayedType isEqualToString:kCustomActionTypeURLScheme]) placeholder = @"example://open";
    else if ([_displayedType isEqualToString:kCustomActionTypeURL]) placeholder = @"https://";
    self.linkField.placeholder = placeholder;
    self.linkField.keyboardType = ([_displayedType isEqualToString:kCustomActionTypeText])
        ? UIKeyboardTypeDefault : UIKeyboardTypeURL;
}

#pragma mark - Payload layout

// The url scheme and text payloads use the full-width multi-line text box
// (two-section layout) instead of a small accessory field.
- (BOOL)usesLargePayloadBox {
    return !self.isLegacyEntry &&
        ([_displayedType isEqualToString:kCustomActionTypeURLScheme] ||
         [_displayedType isEqualToString:kCustomActionTypeText]);
}

// The payload value lives in the box for box types, in the small field
// elsewhere; both trim the same way on save.
- (NSString *)payloadCurrentValue {
    if (self.usesLargePayloadBox) return [self trimmedValue:self.payloadBoxCell.textView.text];
    return [self trimmedValue:self.linkField.text];
}

- (NSString *)payloadBoxPlaceholder {
    if ([_displayedType isEqualToString:kCustomActionTypeURLScheme]) return @"example://open";
    return LOCALIZED(@"TEXT_BOX_PLACEHOLDER");
}

#pragma mark - Table view

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    return [self usesLargePayloadBox] ? 2 : 1;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    if (![self usesLargePayloadBox]) return [self rowCount];
    // Box layout: section 0 holds the shared rows (类型/名称/图标), section 1
    // the single payload box.
    return section == 0 ? DXActionRowPayload : 1;
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    if (![self usesLargePayloadBox] || section == 0) return nil;
    return [_displayedType isEqualToString:kCustomActionTypeURLScheme]
        ? LOCALIZED(@"URL_SCHEME_SETTINGS") : LOCALIZED(@"TEXT_SETTINGS");
}

- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section {
    // The type hint describes the payload, so it follows the payload: on the
    // box section for box types, on the single section otherwise.
    if ([self usesLargePayloadBox]) return section == 1 ? [self typeFooter] : nil;
    return section == 0 ? [self typeFooter] : nil;
}

// Only the payload box gets a custom height; every other row keeps the
// system self-sizing it used before.
- (CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath {
    if ([self usesLargePayloadBox] && indexPath.section == 1) return 120.0;
    return UITableViewAutomaticDimension;
}

- (UITableViewCell *)fieldCellForRowAtIndexPath:(NSIndexPath *)indexPath {
    UITableViewCell *cell = [self.tableView dequeueReusableCellWithIdentifier:@"DXPLinkActionFieldCell" forIndexPath:indexPath];
    cell.selectionStyle = UITableViewCellSelectionStyleNone;
    cell.accessoryType = UITableViewCellAccessoryNone;
    cell.imageView.image = nil;
    cell.detailTextLabel.text = nil;
    cell.textLabel.text = [self labelForRow:indexPath.row];
    cell.textLabel.font = [UIFont systemFontOfSize:16];
    cell.accessoryView = [self fieldForRow:indexPath.row];
    return cell;
}

- (UITableViewCell *)valueCellForRowAtIndexPath:(NSIndexPath *)indexPath detail:(NSString *)detail {
    UITableViewCell *cell = [self.tableView dequeueReusableCellWithIdentifier:@"DXPLinkActionValueCell" forIndexPath:indexPath];
    cell.selectionStyle = UITableViewCellSelectionStyleDefault;
    cell.textLabel.text = [self labelForRow:indexPath.row];
    cell.textLabel.font = [UIFont systemFontOfSize:16];
    cell.detailTextLabel.text = detail;
    cell.imageView.image = nil;
    cell.accessoryView = nil;
    cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
    return cell;
}

// Legacy helper rows keep their icon-led look from before typed actions.
- (UITableViewCell *)legacyPickerCellForRowAtIndexPath:(NSIndexPath *)indexPath {
    UITableViewCell *cell = [self.tableView dequeueReusableCellWithIdentifier:@"DXPLinkActionPickCell" forIndexPath:indexPath];
    cell.textLabel.text = [self labelForRow:indexPath.row];
    cell.textLabel.font = [UIFont systemFontOfSize:16];
    cell.detailTextLabel.text = nil;
    cell.imageView.image = (indexPath.row == DXLegacyRowOpenApp
        ? ([UIImage systemImageNamed:@"apps.iphone"] ?: [UIImage systemImageNamed:@"square.grid.2x2"])
        : ([UIImage systemImageNamed:@"list.bullet.rectangle"] ?: [UIImage systemImageNamed:@"list.bullet"]));
    cell.accessoryView = nil;
    cell.accessoryType = UITableViewCellAccessoryNone;
    cell.selectionStyle = UITableViewCellSelectionStyleDefault;
    return cell;
}

// The payload box is a single fixed cell: keeping it in a property preserves
// its text across table reloads, and its placeholder tracks the text.
- (UITableViewCell *)payloadBoxCellForRowAtIndexPath:(NSIndexPath *)indexPath {
    if (!self.payloadBoxCell) {
        self.payloadBoxCell = [self.tableView dequeueReusableCellWithIdentifier:@"DXPLinkActionTextCell" forIndexPath:indexPath];
        self.payloadBoxCell.textView.delegate = self;
        self.payloadBoxCell.textView.text = [self.entry[@"link"] isKindOfClass:[NSString class]] ? self.entry[@"link"] : @"";
    }
    self.payloadBoxCell.placeholderLabel.text = [self payloadBoxPlaceholder];
    self.payloadBoxCell.placeholderLabel.hidden = self.payloadBoxCell.textView.text.length > 0;
    return self.payloadBoxCell;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    if (self.isLegacyEntry) {
        if (indexPath.row >= DXLegacyRowOpenApp) return [self legacyPickerCellForRowAtIndexPath:indexPath];
        return [self fieldCellForRowAtIndexPath:indexPath];
    }

    if ([self usesLargePayloadBox] && indexPath.section == 1) {
        return [self payloadBoxCellForRowAtIndexPath:indexPath];
    }

    // Box layout reaches here only for section 0, whose rows keep the shared
    // indices; single-section typed entries use indexPath.row directly.
    NSInteger row = indexPath.row;

    if (row == DXActionRowType) {
        // The type is fixed for the life of the entry (chosen in the 添加
        // flow's type chooser); the row only displays it and is never tappable.
        UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"DXPLinkActionValueCell" forIndexPath:indexPath];
        cell.selectionStyle = UITableViewCellSelectionStyleNone;
        cell.textLabel.text = [self labelForRow:row];
        cell.textLabel.font = [UIFont systemFontOfSize:16];
        cell.detailTextLabel.text = [DXPLinkActionEditorController displayNameForType:_displayedType];
        cell.imageView.image = nil;
        cell.accessoryView = nil;
        cell.accessoryType = UITableViewCellAccessoryNone;
        return cell;
    }
    if (row == DXActionRowInApp) {
        UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"DXPLinkActionFieldCell" forIndexPath:indexPath];
        cell.selectionStyle = UITableViewCellSelectionStyleNone;
        cell.textLabel.text = [self labelForRow:row];
        cell.textLabel.font = [UIFont systemFontOfSize:16];
        cell.imageView.image = nil;
        cell.detailTextLabel.text = nil;
        cell.accessoryType = UITableViewCellAccessoryNone;
        cell.accessoryView = self.inAppSwitch;
        return cell;
    }
    if (row == DXActionRowPayload && DXIsSubActionOnlyCustomActionType(_displayedType)) {
        return [self valueCellForRowAtIndexPath:indexPath detail:[self trimmedValue:self.linkField.text]];
    }
    return [self fieldCellForRowAtIndexPath:indexPath];
}

#pragma mark - Row actions

- (void)openAppPicker {
    [self.view endEditing:YES];
    DXPAppPickerController *picker = [[DXPAppPickerController alloc] init];
    picker.currentLink = [self trimmedValue:self.linkField.text];
    __weak typeof(self) weakSelf = self;
    picker.completion = ^(NSString *name, NSString *bundleID) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf) return;
        strongSelf.nameField.text = name;
        strongSelf.linkField.text = bundleID;
        // Fill the icon field with the bundle ID so the button renders the
        // app's real icon (saveTapped already validates bundle-ID icons).
        strongSelf.iconField.text = bundleID;
        [strongSelf.tableView reloadRowsAtIndexPaths:@[[NSIndexPath indexPathForRow:DXActionRowPayload inSection:0]]
                                    withRowAnimation:UITableViewRowAnimationNone];
    };
    [self pushController:picker];
}

// The 快捷方式 payload is an app quick action (a long-press menu item): the
// owning app's bundle identifier goes into `link`, the item's
// UIApplicationShortcutItemType into `shortcuttype`.
- (void)openShortcutPicker {
    [self.view endEditing:YES];
    DXPAppShortcutPickerController *picker = [[DXPAppShortcutPickerController alloc] init];
    picker.currentBundleID = [self trimmedValue:self.linkField.text];
    NSString *storedType = self.entry[kCustomActionShortcutTypeKey];
    picker.currentType = [storedType isKindOfClass:[NSString class]] ? storedType : @"";
    __weak typeof(self) weakSelf = self;
    picker.completion = ^(NSString *title, NSString *bundleID, NSString *type) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf) return;
        strongSelf.linkField.text = bundleID;
        strongSelf.entry[kCustomActionShortcutTypeKey] = type;
        // Same bundle-ID icon backfill as the open-app type: the button then
        // renders the owning app's real icon.
        strongSelf.iconField.text = bundleID;
        // A freshly added action takes the menu item's own title as its label
        // until the user types one; re-picking never clobbers a custom name.
        if ([strongSelf trimmedValue:strongSelf.nameField.text].length == 0) strongSelf.nameField.text = title;
        [strongSelf.tableView reloadRowsAtIndexPaths:@[[NSIndexPath indexPathForRow:DXActionRowPayload inSection:0]]
                                    withRowAnimation:UITableViewRowAnimationNone];
    };
    [self pushController:picker];
}

// The legacy preview page only lists apps' long-press quick actions; it stays
// reachable from legacy entries and writes nothing back.
- (void)openLegacyShortcutPreview {
    [self.view endEditing:YES];
    [self pushController:[[DXPAppShortcutPickerController alloc] init]];
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];

    if (self.isLegacyEntry) {
        if (indexPath.row == DXLegacyRowOpenApp) [self openAppPicker];
        else if (indexPath.row == DXLegacyRowShortcutPreview) [self openLegacyShortcutPreview];
        return;
    }

    // The payload box row handles its own taps (the text view takes focus).
    if ([self usesLargePayloadBox] && indexPath.section == 1) return;

    if (indexPath.row == DXActionRowPayload && [_displayedType isEqualToString:kCustomActionTypeOpenApp]) [self openAppPicker];
    else if (indexPath.row == DXActionRowPayload && [_displayedType isEqualToString:kCustomActionTypeShortcut]) [self openShortcutPicker];
}

- (void)inAppSwitchChanged:(UISwitch *)sender {
    // The value is committed on Save together with the rest of the entry.
    (void)sender;
}

#pragma mark - Text view

- (void)textViewDidChange:(UITextView *)textView {
    self.payloadBoxCell.placeholderLabel.hidden = textView.text.length > 0;
}

#pragma mark - Text fields

// Program-filled fields would otherwise start with the caret at the very
// beginning of the text.
- (void)textFieldDidBeginEditing:(UITextField *)textField {
    DXPlaceCaretAtEnd(textField);
}

- (void)textViewDidBeginEditing:(UITextView *)textView {
    DXPlaceCaretAtEnd(textView);
}

- (BOOL)textFieldShouldReturn:(UITextField *)textField {
    if (textField == self.nameField) [self.iconField becomeFirstResponder];
    else if (textField == self.iconField) {
        // The box takes the return-key handoff for box types; the small
        // payload field elsewhere, and legacy chains into 动作链接.
        if ([self usesLargePayloadBox]) [self.payloadBoxCell.textView becomeFirstResponder];
        else {
            UITextField *payload = self.isLegacyEntry ? self.linkField : [self fieldForRow:DXActionRowPayload];
            if (payload) [payload becomeFirstResponder];
            else [textField resignFirstResponder];
        }
    }
    else [textField resignFirstResponder];
    return YES;
}

- (NSString *)trimmedValue:(NSString *)value {
    if (![value isKindOfClass:[NSString class]]) return @"";
    return [value stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
}

#pragma mark - Save

- (void)saveTapped {
    [self.view endEditing:YES];

    NSString *name = [self trimmedValue:self.nameField.text];
    NSString *icon = [self trimmedValue:self.iconField.text];
    NSString *link = [self payloadCurrentValue];
    if (name.length == 0) name = LOCALIZED(@"DEFAULT_BUTTON_NAME");
    // SF Symbol names and app bundle identifiers are both accepted; anything
    // else resets to the type's default icon. A bundle-ID icon is loaded once
    // here so its PNG lands in the shared snapshot for sandboxed toolbar hosts.
    NSString *defaultIcon = [DXPLinkActionEditorController defaultIconForType:_displayedType] ?: @"link";
    if (icon.length > 0) {
        NSString *bundleID = [DXHelper appIconBundleIDForShortcutItem:@{@"icon": icon}];
        if (bundleID) {
            [DXHelper appIconImageForBundleID:bundleID];
        } else if (![DXHelper customIconForShortcutItem:@{@"icon": icon}]) {
            icon = defaultIcon;
        }
    } else {
        icon = defaultIcon;
    }

    NSMutableDictionary *updated = [self.entry mutableCopy] ?: [NSMutableDictionary dictionary];
    updated[@"name"] = name;
    updated[@"icon"] = icon;
    updated[@"link"] = link;
    if (self.isLegacyEntry) {
        [updated removeObjectForKey:kCustomActionTypeKey];
        [updated removeObjectForKey:kCustomActionInAppKey];
    } else {
        updated[kCustomActionTypeKey] = _displayedType;
        if ([_displayedType isEqualToString:kCustomActionTypeURL]) {
            updated[kCustomActionInAppKey] = @(self.inAppSwitch.on);
        } else {
            [updated removeObjectForKey:kCustomActionInAppKey];
        }
    }
    if (self.completion) self.completion(updated);
    [self.navigationController popViewControllerAnimated:YES];
}

- (UITextField *)newFieldWithText:(NSString *)text placeholder:(NSString *)placeholder {
    UITextField *field = [[UITextField alloc] initWithFrame:CGRectMake(0, 0, 210, 36)];
    field.text = text;
    field.placeholder = placeholder;
    field.textAlignment = NSTextAlignmentRight;
    field.clearButtonMode = UITextFieldViewModeWhileEditing;
    field.autocorrectionType = UITextAutocorrectionTypeNo;
    field.autocapitalizationType = UITextAutocapitalizationTypeNone;
    field.delegate = self;
    return field;
}

- (void)viewDidLoad {
    tweakBundle = [NSBundle bundleWithPath:bundlePath];
    [tweakBundle load];
    [super viewDidLoad];

    // Open-app entries get their own page title; every other type keeps the
    // generic custom-action one.
    self.title = [_displayedType isEqualToString:kCustomActionTypeOpenApp]
        ? LOCALIZED(@"OPEN_APP_SETTINGS") : LOCALIZED(@"CUSTOM_ACTION_SETTINGS");
    self.entry = [self.entry mutableCopy] ?: [NSMutableDictionary dictionary];
    NSString *storedType = self.entry[kCustomActionTypeKey];
    _displayedType = [storedType isKindOfClass:[NSString class]] ? storedType : @"";

    self.nameField = [self newFieldWithText:self.entry[@"name"] placeholder:LOCALIZED(@"DEFAULT_BUTTON_NAME")];
    self.iconField = [self newFieldWithText:self.entry[@"icon"] placeholder:[DXPLinkActionEditorController defaultIconForType:_displayedType]];
    self.linkField = [self newFieldWithText:self.entry[@"link"] placeholder:@""];
    [self applyTypeToPayloadField];
    self.linkField.returnKeyType = UIReturnKeyDone;

    self.inAppSwitch = [[UISwitch alloc] init];
    id storedInApp = self.entry[kCustomActionInAppKey];
    // APP内打开 is the default: an absent flag still means in-app.
    self.inAppSwitch.on = (storedInApp == nil) || [storedInApp boolValue];
    [self.inAppSwitch addTarget:self action:@selector(inAppSwitchChanged:) forControlEvents:UIControlEventValueChanged];

    self.tableView = [[UITableView alloc] initWithFrame:self.view.bounds style:UITableViewStyleInsetGrouped];
    self.tableView.delegate = self;
    self.tableView.dataSource = self;
    self.tableView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    self.tableView.keyboardDismissMode = UIScrollViewKeyboardDismissModeInteractive;
    [self.tableView registerClass:[UITableViewCell class] forCellReuseIdentifier:@"DXPLinkActionFieldCell"];
    [self.tableView registerClass:[UITableViewCell class] forCellReuseIdentifier:@"DXPLinkActionPickCell"];
    [self.tableView registerClass:[DXPLinkActionValueCell class] forCellReuseIdentifier:@"DXPLinkActionValueCell"];
    [self.tableView registerClass:[DXPLinkActionTextCell class] forCellReuseIdentifier:@"DXPLinkActionTextCell"];
    self.view = self.tableView;

    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithTitle:LOCALIZED(@"SAVE")
                                                                              style:UIBarButtonItemStyleDone
                                                                             target:self
                                                                             action:@selector(saveTapped)];
}

@end
