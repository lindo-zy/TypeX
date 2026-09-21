#import "DXPLinkActionEditorController.h"
#import "DXPAppInfo.h"
#import "DXPOpenAppPickerController.h"
#import "../DXHelper.h"
#import "../common.h"

static NSBundle *tweakBundle;

// Typed rows. 0-2 are shared by every type (类型 / 名称 / 图标); the payload
// row depends on the entry's type:
// - urlscheme: section 1 = full-width 文本框 (multi-line payload box), then
//              the 剪切替换 switch (the box types that support @@@)
// - text:      section 1 = full-width 文本框 (multi-line payload box)
// - url:       3 = URL 设置 (field), 4 = APP内打开 switch, 5 = 剪切替换 switch
// - openapp:   3 = installed-app picker, 4 = PullOver-X switch when installed
// 剪切替换 appears wherever the payload supports @@@ (legacy / url /
// urlscheme): ON clears the input field after its text is passed in (cut),
// OFF keeps the field's content (copy, the default).
// The box types use two sections: section 0 holds the shared rows, section 1
// the payload box with the type label as its header and hint as its footer.
// Entries without a type keep the legacy layout (动作链接) plus the 剪切替换
// row, so existing definitions keep editing almost exactly as before.
static NSInteger const DXActionRowType = 0;
static NSInteger const DXActionRowName = 1;
static NSInteger const DXActionRowIcon = 2;
static NSInteger const DXActionRowPayload = 3;
static NSInteger const DXActionRowInApp = 4;

static NSInteger const DXLegacyRowName = 0;
static NSInteger const DXLegacyRowIcon = 1;
static NSInteger const DXLegacyRowLink = 2;

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
// 图标 row accessory: preview thumbnail (left) + edit field (right) in one
// container, mirroring KayokoX's icon row. The preview lives in the accessory
// so its position never depends on how UIKit sizes textLabel's frame.
@property (nonatomic, strong) UIView *iconAccessoryContainer;
@property (nonatomic, strong) UIImageView *iconPreviewImageView;
@property (nonatomic, strong) UITextField *linkField;
@property (nonatomic, strong) UISwitch *inAppSwitch;
@property (nonatomic, strong) UISwitch *pullOverSwitch;
@property (nonatomic, strong) UISwitch *cutReplaceSwitch;
@property (nonatomic, copy) NSString *selectedAppName;
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
    if ([type isEqualToString:kCustomActionTypeURL]) return LOCALIZED(@"ACTION_TYPE_URL");
    if ([type isEqualToString:kCustomActionTypeOpenApp]) return LOCALIZED(@"ACTION_TYPE_OPEN_APP");
    return type;
}

+ (NSString *)defaultIconForType:(NSString *)type {
    if ([type isEqualToString:kCustomActionTypeText]) return @"doc.text";
    if ([type isEqualToString:kCustomActionTypeURL]) return @"globe";
    if ([type isEqualToString:kCustomActionTypeOpenApp]) return @"app";
    return @"link";
}

// Used by the management page's 添加 flow: the type is chosen here and is
// then fixed for the entry's life — the editor's 类型 row only displays it.
// The order places URL Scheme first because it is the default for new actions.
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
    ];
    for (NSString *type in types) {
        [alert addAction:[UIAlertAction actionWithTitle:[self displayNameForType:type]
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

- (BOOL)isOpenAppEntry {
    return [_displayedType isEqualToString:kCustomActionTypeOpenApp];
}

- (BOOL)isPullOverXInstalled {
    NSString *path = DX_ROOT_PATH_NS(@"/Library/MobileSubstrate/DynamicLibraries/PullOverX.dylib");
    return path.length > 0 && [[NSFileManager defaultManager] fileExistsAtPath:path];
}

- (NSInteger)rowCount {
    if (self.isLegacyEntry) return DXLegacyRowLink + 1 + (self.hasCutReplaceSwitch ? 1 : 0);
    BOOL hasSwitch = [_displayedType isEqualToString:kCustomActionTypeURL] ||
        (self.isOpenAppEntry && self.isPullOverXInstalled);
    NSInteger rows = DXActionRowPayload + 1 + (hasSwitch ? 1 : 0);
    if (self.hasCutReplaceSwitch) rows++;
    return rows;
}

// 剪切替换 is offered wherever the payload can pull in the field's text via
// @@@: legacy auto-detecting links, url, and url scheme. text expands its own
// {{...}} templates and openapp carries a bundle identifier, so neither ever
// reads the field through @@@ and neither gets the row.
- (BOOL)hasCutReplaceSwitch {
    if (self.isLegacyEntry) return YES;
    return [_displayedType isEqualToString:kCustomActionTypeURL] ||
        [_displayedType isEqualToString:kCustomActionTypeURLScheme];
}

// Last row of the single-section layouts (after 动作链接 or APP内打开); for
// the box layout it follows the payload box in section 1.
- (BOOL)isCutReplaceRow:(NSIndexPath *)indexPath {
    if (![self hasCutReplaceSwitch]) return NO;
    if ([self usesLargePayloadBox]) return indexPath.section == 1 && indexPath.row == 1;
    return indexPath.row == [self rowCount] - 1;
}

- (NSString *)typeFooter {
    if (self.isLegacyEntry) return LOCALIZED(@"CUSTOM_LINK_ACTION_FOOTER");
    if ([_displayedType isEqualToString:kCustomActionTypeURLScheme]) return LOCALIZED(@"TYPE_FOOTER_URL_SCHEME");
    if ([_displayedType isEqualToString:kCustomActionTypeText]) return LOCALIZED(@"TYPE_FOOTER_TEXT");
    if ([_displayedType isEqualToString:kCustomActionTypeURL]) return LOCALIZED(@"TYPE_FOOTER_URL");
    if (self.isOpenAppEntry) return LOCALIZED(@"TYPE_FOOTER_OPEN_APP");
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
    if (row == DXActionRowPayload && !self.isOpenAppEntry) return self.linkField;
    return nil;
}

- (NSString *)labelForRow:(NSInteger)row {
    if (self.isLegacyEntry) {
        if (row == DXLegacyRowName) return LOCALIZED(@"NAME");
        if (row == DXLegacyRowIcon) return LOCALIZED(@"ICON");
        return LOCALIZED(@"ACTION_LINK");
    }
    if (row == DXActionRowType) return LOCALIZED(@"ACTION_TYPE");
    if (row == DXActionRowName) return LOCALIZED(@"NAME");
    if (row == DXActionRowIcon) return LOCALIZED(@"ICON");
    if (row == DXActionRowPayload) {
        if ([_displayedType isEqualToString:kCustomActionTypeURLScheme]) return LOCALIZED(@"URL_SCHEME_SETTINGS");
        if ([_displayedType isEqualToString:kCustomActionTypeText]) return LOCALIZED(@"TEXT_SETTINGS");
        if ([_displayedType isEqualToString:kCustomActionTypeURL]) return LOCALIZED(@"URL_SETTINGS");
        if (self.isOpenAppEntry) return LOCALIZED(@"SELECT_APP");
    }
    if (row == DXActionRowInApp) {
        return self.isOpenAppEntry ? LOCALIZED(@"OPEN_WITH_PULLOVER") : LOCALIZED(@"OPEN_IN_APP");
    }
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
    // The text payload box carries no hint; the usage list lives in the
    // section footer instead.
    return @"";
}

#pragma mark - Table view

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    return [self usesLargePayloadBox] ? 2 : 1;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    if (![self usesLargePayloadBox]) return [self rowCount];
    // Box layout: section 0 holds the shared rows (类型/名称/图标), section 1
    // the payload box followed by the 剪切替换 switch when the type supports @@@.
    return section == 0 ? DXActionRowPayload : (self.hasCutReplaceSwitch ? 2 : 1);
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

// Only the payload box gets a custom height; every other row (including the
// 剪切替换 row that follows it) keeps the system self-sizing it used before.
- (CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath {
    if ([self usesLargePayloadBox] && indexPath.section == 1 && indexPath.row == 0) return 120.0;
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
    cell.accessoryView = [self fieldForRow:indexPath.row] == self.iconField
        ? [self iconAccessoryView]
        : [self fieldForRow:indexPath.row];
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
    NSString *placeholder = [self payloadBoxPlaceholder];
    self.payloadBoxCell.placeholderLabel.text = placeholder;
    self.payloadBoxCell.placeholderLabel.hidden = placeholder.length == 0 || self.payloadBoxCell.textView.text.length > 0;
    return self.payloadBoxCell;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    // The 剪切替换 row shares section 1 with the payload box on box types, so
    // it must be intercepted before the box cell short-circuit below.
    if ([self isCutReplaceRow:indexPath]) {
        UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"DXPLinkActionFieldCell" forIndexPath:indexPath];
        cell.selectionStyle = UITableViewCellSelectionStyleNone;
        cell.textLabel.text = LOCALIZED(@"CUT_REPLACE_FIELD");
        cell.textLabel.font = [UIFont systemFontOfSize:16];
        cell.imageView.image = nil;
        cell.detailTextLabel.text = nil;
        cell.accessoryType = UITableViewCellAccessoryNone;
        cell.accessoryView = self.cutReplaceSwitch;
        return cell;
    }

    if ([self usesLargePayloadBox] && indexPath.section == 1) {
        return [self payloadBoxCellForRowAtIndexPath:indexPath];
    }

    // Box layout reaches here only for section 0, whose rows keep the shared
    // indices; single-section typed entries use indexPath.row directly.
    NSInteger row = indexPath.row;

    if (row == DXActionRowType && !self.isLegacyEntry) {
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
    if (row == DXActionRowPayload && self.isOpenAppEntry) {
        UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"DXPLinkActionValueCell" forIndexPath:indexPath];
        NSString *bundleIdentifier = [self trimmedValue:self.linkField.text];
        cell.selectionStyle = UITableViewCellSelectionStyleDefault;
        cell.textLabel.text = [self labelForRow:row];
        cell.textLabel.font = [UIFont systemFontOfSize:16];
        cell.detailTextLabel.text = self.selectedAppName.length ? self.selectedAppName : LOCALIZED(@"UNSELECTED");
        cell.imageView.image = bundleIdentifier.length ? [DXPAppInfo iconForBundleID:bundleIdentifier] : nil;
        cell.accessoryView = nil;
        cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
        return cell;
    }
    if (row == DXActionRowInApp && !self.isLegacyEntry) {
        UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"DXPLinkActionFieldCell" forIndexPath:indexPath];
        cell.selectionStyle = UITableViewCellSelectionStyleNone;
        cell.textLabel.text = [self labelForRow:row];
        cell.textLabel.font = [UIFont systemFontOfSize:16];
        cell.imageView.image = nil;
        cell.detailTextLabel.text = nil;
        cell.accessoryType = UITableViewCellAccessoryNone;
        cell.accessoryView = self.isOpenAppEntry ? self.pullOverSwitch : self.inAppSwitch;
        return cell;
    }
    return [self fieldCellForRowAtIndexPath:indexPath];
}

#pragma mark - Row actions

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];

    // The payload box row handles its own taps (the text view takes focus).
    if ([self usesLargePayloadBox] && indexPath.section == 1) return;
    if (self.isOpenAppEntry && indexPath.row == DXActionRowPayload) {
        DXPOpenAppPickerController *picker = [[DXPOpenAppPickerController alloc] init];
        picker.selectedBundleIdentifier = [self trimmedValue:self.linkField.text];
        __weak typeof(self) weakSelf = self;
        picker.completion = ^(DXPAppInfo *app) {
            __strong typeof(weakSelf) strongSelf = weakSelf;
            if (!strongSelf || app.bundleID.length == 0) return;

            NSString *currentName = [strongSelf trimmedValue:strongSelf.nameField.text];
            BOOL replaceDefaultName = currentName.length == 0 ||
                [currentName isEqualToString:LOCALIZED(@"DEFAULT_BUTTON_NAME")] ||
                [currentName isEqualToString:LOCALIZED(@"OPEN_APP")];
            strongSelf.linkField.text = app.bundleID;
            strongSelf.selectedAppName = app.name.length ? app.name : app.bundleID;
            strongSelf.iconField.text = app.bundleID;
            if (replaceDefaultName) strongSelf.nameField.text = strongSelf.selectedAppName;
            [strongSelf refreshIconPreview];
            [strongSelf.tableView reloadRowsAtIndexPaths:@[[NSIndexPath indexPathForRow:DXActionRowPayload inSection:0]]
                                         withRowAnimation:UITableViewRowAnimationNone];
        };
        [picker setRootController:[self rootController]];
        [picker setParentController:[self parentController]];
        [self pushController:picker];
    }
}

- (void)inAppSwitchChanged:(UISwitch *)sender {
    // The value is committed on Save together with the rest of the entry.
    (void)sender;
}

- (void)showSelectAppRequiredAlert {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:LOCALIZED(@"SELECT_APP")
                                                                   message:LOCALIZED(@"SELECT_APP_REQUIRED")
                                                            preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:LOCALIZED(@"ANSWER_OK")
                                              style:UIAlertActionStyleDefault
                                            handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}

#pragma mark - Text view

- (void)textViewDidChange:(UITextView *)textView {
    self.payloadBoxCell.placeholderLabel.hidden =
        self.payloadBoxCell.placeholderLabel.text.length == 0 || textView.text.length > 0;
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
        // payload field elsewhere.
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
    if (self.isOpenAppEntry && !DXIsValidBundleIdentifier(link)) {
        [self showSelectAppRequiredAlert];
        return;
    }
    if (name.length == 0) name = LOCALIZED(@"DEFAULT_BUTTON_NAME");
    // SF Symbol names and app bundle identifiers are both accepted; anything
    // else resets to the "link" default. A bundle-ID icon is loaded once
    // here so its PNG lands in the shared snapshot for sandboxed toolbar hosts.
    NSString *defaultIcon = [DXPLinkActionEditorController defaultIconForType:_displayedType];
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
        [updated removeObjectForKey:kCustomActionUsePullOverKey];
        // Legacy payloads support @@@, so the 剪切替换 choice applies to them.
        updated[kCustomActionCutReplaceKey] = @(self.cutReplaceSwitch.on);
    } else {
        updated[kCustomActionTypeKey] = _displayedType;
        if ([_displayedType isEqualToString:kCustomActionTypeURL]) {
            updated[kCustomActionInAppKey] = @(self.inAppSwitch.on);
        } else {
            [updated removeObjectForKey:kCustomActionInAppKey];
        }
        if (self.isOpenAppEntry) {
            updated[kCustomActionUsePullOverKey] = @(self.isPullOverXInstalled && self.pullOverSwitch.on);
        } else {
            [updated removeObjectForKey:kCustomActionUsePullOverKey];
        }
        if (self.hasCutReplaceSwitch) {
            updated[kCustomActionCutReplaceKey] = @(self.cutReplaceSwitch.on);
        } else {
            // text / openapp never read the field through @@@, so the flag
            // must not linger from an earlier edit.
            [updated removeObjectForKey:kCustomActionCutReplaceKey];
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

#pragma mark - Icon preview

// The 图标 row's accessory is a preview thumbnail followed by the edit field;
// the thumbnail mirrors what the entry will actually render (SF Symbol name or
// app bundle identifier) and refreshes on every keystroke.
- (UIView *)iconAccessoryView {
    if (!self.iconAccessoryContainer) {
        UIView *container = [[UIView alloc] initWithFrame:CGRectMake(0.0, 0.0, 267.0, 36.0)];
        self.iconPreviewImageView = [[UIImageView alloc] initWithFrame:CGRectMake(0.0, 3.5, 29.0, 29.0)];
        self.iconPreviewImageView.contentMode = UIViewContentModeScaleAspectFit;
        [container addSubview:self.iconPreviewImageView];
        self.iconField.frame = CGRectMake(38.0, 0.0, 220.0, 36.0);
        [container addSubview:self.iconField];
        self.iconAccessoryContainer = container;
        [self refreshIconPreview];
    }
    return self.iconAccessoryContainer;
}

- (void)buildIconAccessory {
    [self.iconField addTarget:self action:@selector(iconTextChanged:) forControlEvents:UIControlEventEditingChanged];
}

- (void)iconTextChanged:(__unused UITextField *)sender {
    [self refreshIconPreview];
}

- (UIImage *)currentIconPreviewImage {
    NSString *icon = [self trimmedValue:self.iconField.text];
    UIImage *image = icon.length ? [DXHelper imageForIconConfig:icon defaultSymbolName:@"link"] : nil;
    if (!image) image = [UIImage systemImageNamed:@"link"];
    return image;
}

// Refresh only the one preview view; sweeping visibleCells with the property
// setter would hit plain field cells and crash on an unrecognized selector.
- (void)refreshIconPreview {
    self.iconPreviewImageView.image = [self currentIconPreviewImage];
}

- (void)viewDidLoad {
    tweakBundle = [NSBundle bundleWithPath:bundlePath];
    [tweakBundle load];
    [super viewDidLoad];

    self.title = LOCALIZED(@"CUSTOM_ACTION_SETTINGS");
    self.entry = [self.entry mutableCopy] ?: [NSMutableDictionary dictionary];
    NSString *storedType = self.entry[kCustomActionTypeKey];
    // Entries typed before removed types (or carrying garbage) keep editing
    // as legacy (auto-detecting) actions; only known types stay typed.
    _displayedType = ([storedType isKindOfClass:[NSString class]] &&
                      ([storedType isEqualToString:kCustomActionTypeURLScheme] ||
                       [storedType isEqualToString:kCustomActionTypeText] ||
                       [storedType isEqualToString:kCustomActionTypeURL] ||
                       [storedType isEqualToString:kCustomActionTypeOpenApp])) ? storedType : @"";

    NSString *defaultName = ([self trimmedValue:self.entry[@"name"]].length && [self.entry[@"name"] isKindOfClass:[NSString class]])
        ? self.entry[@"name"] : LOCALIZED(@"DEFAULT_BUTTON_NAME");
    self.nameField = [self newFieldWithText:defaultName placeholder:LOCALIZED(@"DEFAULT_BUTTON_NAME")];
    self.iconField = [self newFieldWithText:self.entry[@"icon"] placeholder:@"link"];
    [self buildIconAccessory];
    self.linkField = [self newFieldWithText:self.entry[@"link"] placeholder:@""];
    [self applyTypeToPayloadField];
    self.linkField.returnKeyType = UIReturnKeyDone;

    self.inAppSwitch = [[UISwitch alloc] init];
    id storedInApp = self.entry[kCustomActionInAppKey];
    // APP内打开 is the default: an absent flag still means in-app.
    self.inAppSwitch.on = (storedInApp == nil) || [storedInApp boolValue];
    [self.inAppSwitch addTarget:self action:@selector(inAppSwitchChanged:) forControlEvents:UIControlEventValueChanged];

    self.pullOverSwitch = [[UISwitch alloc] init];
    self.pullOverSwitch.on = [self.entry[kCustomActionUsePullOverKey] boolValue];
    [self.pullOverSwitch addTarget:self action:@selector(inAppSwitchChanged:) forControlEvents:UIControlEventValueChanged];

    // 剪切替换 defaults to off: the field keeps its content (copy semantics,
    // the historical behavior); on, the field is cleared after @@@ passes its
    // text into the payload (cut semantics).
    self.cutReplaceSwitch = [[UISwitch alloc] init];
    self.cutReplaceSwitch.on = [self.entry[kCustomActionCutReplaceKey] boolValue];
    [self.cutReplaceSwitch addTarget:self action:@selector(inAppSwitchChanged:) forControlEvents:UIControlEventValueChanged];

    if (self.isOpenAppEntry) {
        NSString *selectedBundleIdentifier = [self trimmedValue:self.linkField.text];
        for (DXPAppInfo *app in [DXPAppInfo installedApps]) {
            if (![app.bundleID isEqualToString:selectedBundleIdentifier]) continue;
            self.selectedAppName = app.name.length ? app.name : app.bundleID;
            break;
        }
        if (self.selectedAppName.length == 0 && selectedBundleIdentifier.length > 0) {
            self.selectedAppName = selectedBundleIdentifier;
        }
    }

    self.tableView = [[UITableView alloc] initWithFrame:self.view.bounds style:UITableViewStyleInsetGrouped];
    self.tableView.delegate = self;
    self.tableView.dataSource = self;
    self.tableView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    self.tableView.keyboardDismissMode = UIScrollViewKeyboardDismissModeInteractive;
    [self.tableView registerClass:[UITableViewCell class] forCellReuseIdentifier:@"DXPLinkActionFieldCell"];
    [self.tableView registerClass:[DXPLinkActionValueCell class] forCellReuseIdentifier:@"DXPLinkActionValueCell"];
    [self.tableView registerClass:[DXPLinkActionTextCell class] forCellReuseIdentifier:@"DXPLinkActionTextCell"];
    self.view = self.tableView;

    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithTitle:LOCALIZED(@"SAVE")
                                                                              style:UIBarButtonItemStyleDone
                                                                             target:self
                                                                             action:@selector(saveTapped)];
}

@end
