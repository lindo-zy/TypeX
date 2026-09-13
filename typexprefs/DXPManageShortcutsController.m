#import "DXPManageShortcutsController.h"
#import "DXPGesturePickerController.h"
#import "../DXShortcutsGenerator.h"
#import "../DXHelper.h"
#import <objc/runtime.h>

static NSBundle *tweakBundle;

// Height of the section header hosting the test field above the
// button-settings rows: field title + field + section title + padding.
#define kTestFieldSectionHeaderHeight 110.0

static BOOL DXIsHiddenShortcutSelector(NSString *selector) {
    return ![DXShortcutsGenerator isVisibleShortcutSelector:selector];
}

// One row of the toolbar-scoped settings sections. Sliders snap to `step` and
// fall back to `defaultValue` while the preference key is unset.
@interface DXSettingsRow : NSObject
@property (nonatomic, copy) NSString *key;
@property (nonatomic, copy) NSString *label;
@property (nonatomic, assign) BOOL isSwitch;
@property (nonatomic, assign) BOOL isSegment;
@property (nonatomic, copy) NSArray<NSString *> *segmentTitles;
@property (nonatomic, assign) float minValue;
@property (nonatomic, assign) float maxValue;
@property (nonatomic, assign) float step;
@property (nonatomic, assign) float defaultValue;
@property (nonatomic, copy) NSString *valueSuffix;
@end

@implementation DXSettingsRow
+ (DXSettingsRow *)switchRowWithKey:(NSString *)key label:(NSString *)label defaultValue:(BOOL)defaultValue {
    DXSettingsRow *row = [[DXSettingsRow alloc] init];
    row.key = key;
    row.label = label;
    row.isSwitch = YES;
    row.defaultValue = defaultValue ? 1.0 : 0.0;
    return row;
}

// Index-valued row rendered as a segmented control; the selected segment index
// is the stored value.
+ (DXSettingsRow *)segmentRowWithKey:(NSString *)key label:(NSString *)label titles:(NSArray<NSString *> *)titles defaultValue:(float)defaultValue {
    DXSettingsRow *row = [[DXSettingsRow alloc] init];
    row.key = key;
    row.label = label;
    row.isSegment = YES;
    row.segmentTitles = titles;
    row.defaultValue = defaultValue;
    return row;
}

+ (DXSettingsRow *)sliderRowWithKey:(NSString *)key label:(NSString *)label minValue:(float)minValue maxValue:(float)maxValue step:(float)step defaultValue:(float)defaultValue {
    DXSettingsRow *row = [[DXSettingsRow alloc] init];
    row.key = key;
    row.label = label;
    row.minValue = minValue;
    row.maxValue = maxValue;
    row.step = step > 0 ? step : 1.0;
    row.defaultValue = defaultValue;
    return row;
}
@end

static void DXAppendUniqueShortcuts(NSArray *shortcuts,
                                    NSMutableArray *destination,
                                    NSMutableSet *seenSelectors,
                                    NSUInteger limit) {
    for (id object in shortcuts) {
        if (destination.count >= limit) break;
        if (![object isKindOfClass:[NSDictionary class]]) continue;

        NSDictionary *shortcut = (NSDictionary *)object;
        NSString *selector = shortcut[@"selector"];
        // Draft buttons (saved without a tap action) carry a synthetic
        // selector and must survive normalization untouched.
        if (!DXIsDraftActionSelector(selector)) {
            if (![selector isKindOfClass:[NSString class]] ||
                DXIsHiddenShortcutSelector(selector) ||
                [seenSelectors containsObject:selector]) {
                continue;
            }
            [seenSelectors addObject:selector];
        }

        [destination addObject:shortcut];
    }
}


@implementation DXPManageShortcutsController

- (NSString *)scopedKey:(NSString *)bottomKey topKey:(NSString *)topKey {
    return self.topConfiguration ? topKey : bottomKey;
}

#pragma mark - Table view: configured buttons only

// Section 0 lists buttons, section 1 controls button appearance, and section 2
// controls the sub-action panel. The bottom page additionally carries the
// toolbar-height section at index 3.
- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    return self.topConfiguration ? 3 : 4;
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    if (section == 1) return LOCALIZED(@"BUTTON_SETTINGS");
    if (section == 2) return LOCALIZED(@"PANEL_SETTINGS");
    if (section == 3) return LOCALIZED(@"OFFSETS");
    return nil;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    switch (section) {
        case 1: return self.appearanceRows.count;
        case 2: return self.panelRows.count;
        case 3: return self.offsetRows.count;
        default: return [self.currentOrder[0] count];
    }
}

- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section {
    if (section == 0)
        return [NSString stringWithFormat:LOCALIZED(@"FOOTER_TOOLBAR_BUTTONS"), (int)maxshortcutpersection];
    if (section == 1) return LOCALIZED(@"FOOTER_BUTTON_SETTINGS");
    if (section == 2) return LOCALIZED(@"FOOTER_PANEL_SETTINGS");
    return nil;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    if (indexPath.section > 0) return [self settingsCellForRowAtIndexPath:indexPath];

    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"TypeXItemCell" forIndexPath:indexPath];

    if (cell == nil)
        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:@"TypeXItemCell"];

    if (self.currentOrder[0] == nil || indexPath.row >= [self.currentOrder[0] count])
        return cell;

    UIImage *image;
    NSString *label;

    dispatch_semaphore_t smp = dispatch_semaphore_create(0);
    __block BOOL isCustomImagePath = NO;
    __block BOOL isThirteen = NO;

    label = [DXHelper localizedStringForActionNamed:[DXHelper actionNameFromArray:self.currentOrder[0] atIndex:indexPath.row] shortName:NO bundle:tweakBundle];
    image = [DXHelper imageFromArray:self.currentOrder[0] atIndex:indexPath.row withSystemColor:YES completion:^(BOOL thirteen, BOOL customPath){
        isThirteen = thirteen;
        isCustomImagePath = customPath;
        dispatch_semaphore_signal(smp);
    }];
    dispatch_semaphore_wait(smp, DISPATCH_TIME_FOREVER);
    if (!isThirteen && isCustomImagePath){
        [cell.imageView setTintColor:[UIColor blackColor]];
    }

    NSDictionary *shortcutItem = self.currentOrder[indexPath.section][indexPath.row];

    // Per-shortcut overrides set in the button's own settings page: a custom
    // name replaces the localized label and a valid SF Symbol replaces the icon.
    NSString *customName = [DXHelper customNameForShortcutItem:shortcutItem];
    if (customName) label = customName;
    else if ([shortcutItem[@"label"] isKindOfClass:[NSString class]] && [(NSString *)shortcutItem[@"label"] length])
        label = shortcutItem[@"label"];
    NSString *customIcon = [DXHelper customIconForShortcutItem:shortcutItem];
    if (customIcon) image = [DXHelper imageForName:customIcon withSystemColor:YES completion:nil];

    // Enable switch: off keeps the button stored but hides it from the
    // toolbar. The table lives in editing mode permanently, so the switch is
    // mounted as the editing accessory view (the one actually displayed).
    UISwitch *toggle = (UISwitch *)cell.editingAccessoryView;
    if (![toggle isKindOfClass:[UISwitch class]]) {
        toggle = [[UISwitch alloc] init];
        [toggle addTarget:self action:@selector(buttonEnabledToggleChanged:) forControlEvents:UIControlEventValueChanged];
    }
    cell.accessoryView = nil;
    cell.editingAccessoryView = toggle;
    BOOL buttonDisabled = [shortcutItem[@"disabled"] boolValue];
    toggle.on = !buttonDisabled;

    cell.textLabel.text = label;
    cell.textLabel.textColor = buttonDisabled ? [UIColor secondaryLabelColor] : [UIColor labelColor];
    cell.imageView.image = image;
    return cell;
}

// Number of stored buttons that are currently switched on.
- (NSInteger)enabledButtonCount {
    NSInteger count = 0;
    for (NSDictionary *item in self.currentOrder[0]) {
        if ([item isKindOfClass:[NSDictionary class]] && ![item[@"disabled"] boolValue]) count++;
    }
    return count;
}

// Row recovered from the switch's cell: rows move and delete, so a cached
// index would go stale.
- (void)buttonEnabledToggleChanged:(UISwitch *)sender {
    UIView *view = sender;
    while (view && ![view isKindOfClass:[UITableViewCell class]]) view = view.superview;
    NSIndexPath *indexPath = [self.tableView indexPathForCell:(UITableViewCell *)view];
    if (!indexPath || indexPath.section != 0 || indexPath.row >= (NSInteger)[self.currentOrder[0] count]) return;

    if (sender.on && [self enabledButtonCount] >= maxshortcutpersection) {
        sender.on = NO;
        UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"TypeX"
                                                                       message:[NSString stringWithFormat:LOCALIZED(@"MAX_ENABLED_REACHED"), (int)maxshortcutpersection]
                                                                preferredStyle:UIAlertControllerStyleAlert];
        [alert addAction:[UIAlertAction actionWithTitle:LOCALIZED(@"ANSWER_OK") style:UIAlertActionStyleCancel handler:nil]];
        [self presentViewController:alert animated:YES completion:nil];
        return;
    }

    NSMutableDictionary *entry = [self.currentOrder[0][indexPath.row] mutableCopy];
    if (sender.on) [entry removeObjectForKey:@"disabled"];
    else entry[@"disabled"] = @YES;
    self.currentOrder[0][indexPath.row] = entry;
    UITableViewCell *cell = [self.tableView cellForRowAtIndexPath:indexPath];
    cell.textLabel.textColor = sender.on ? [UIColor labelColor] : [UIColor secondaryLabelColor];
    [self writeToFile];
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath{
    if (indexPath.section != 0) return;
    DXPGesturePickerController *gesturePickerController = [[DXPGesturePickerController alloc] init];

    gesturePickerController.fullOrder = self.fullOrder;
    gesturePickerController.identifier = self.currentOrder[indexPath.section][indexPath.row][@"selector"];
    gesturePickerController.configuration = self.topConfiguration ? @"top" : @"bottom";
    NSDictionary *shortcutItem = self.currentOrder[indexPath.section][indexPath.row];
    // Draft buttons have a synthetic selector, so prefer the stored label.
    gesturePickerController.title = [DXHelper customNameForShortcutItem:shortcutItem]
        ?: [shortcutItem[@"label"] isKindOfClass:[NSString class]] && [(NSString *)shortcutItem[@"label"] length] ? shortcutItem[@"label"]
        : [DXHelper localizedStringForActionNamed:shortcutItem[@"selector"] shortName:NO bundle:tweakBundle];

    [gesturePickerController setRootController: [self rootController]];
    [gesturePickerController setParentController: [self parentController]];
    [self pushController:gesturePickerController];

    [tableView deselectRowAtIndexPath:indexPath animated:YES];
}

- (void)tableView:(UITableView *)tableView moveRowAtIndexPath:(NSIndexPath *)sourceIndexPath toIndexPath:(NSIndexPath *)destinationIndexPath {
    if (self.tableView == nil)
        return;

    NSString *objectToMove = [self.currentOrder[0] objectAtIndex:sourceIndexPath.row];
    [self.currentOrder[0] removeObjectAtIndex:sourceIndexPath.row];
    [self.currentOrder[0] insertObject:objectToMove atIndex:destinationIndexPath.row];
    [self.tableView reloadData];
    [self writeToFile];
}

- (BOOL)tableView:(UITableView *)tableView canMoveRowAtIndexPath:(NSIndexPath *)indexPath {
    return indexPath.section == 0;
}

- (BOOL)tableView:(UITableView *)tableView canEditRowAtIndexPath:(NSIndexPath *)indexPath{
    return indexPath.section == 0;
}

- (void)tableView:(UITableView *)tableView commitEditingStyle:(UITableViewCellEditingStyle)editingStyle forRowAtIndexPath:(NSIndexPath *)indexPath {
    if (editingStyle != UITableViewCellEditingStyleDelete || indexPath.section != 0) return;

    // Deleting forgets the button entirely: the entry leaves the toolbar and
    // its per-button gesture configuration is cleared with it.
    NSString *identifier = self.currentOrder[0][indexPath.row][@"selector"];
    [tableView beginUpdates];
    [self.currentOrder[0] removeObjectAtIndex:indexPath.row];
    [tableView deleteRowsAtIndexPaths:@[indexPath] withRowAnimation:UITableViewRowAnimationFade];
    [tableView endUpdates];
    [self removeCustomActionsForIdentifier:identifier];
    [self writeToFile];
}

- (UITableViewCellEditingStyle)tableView:(UITableView *)tableView editingStyleForRowAtIndexPath:(NSIndexPath *)indexPath {
    return indexPath.section == 0 ? UITableViewCellEditingStyleDelete : UITableViewCellEditingStyleNone;
}

- (BOOL)tableView:(UITableView *)tableView shouldIndentWhileEditingRowAtIndexPath:(NSIndexPath *)indexPath {
    return NO;
}

-(NSIndexPath *)tableView:(UITableView *)tableView targetIndexPathForMoveFromRowAtIndexPath:(NSIndexPath *)sourceIndexPath toProposedIndexPath:(NSIndexPath *)proposedDestinationIndexPath
{
    if( sourceIndexPath.section != proposedDestinationIndexPath.section )
    {
        return sourceIndexPath;
    }
    else
    {
        return proposedDestinationIndexPath;
    }
}

#pragma mark - Test input field

// The test field is the header of the button-settings section, i.e. the middle
// of the page: the sliders being tuned and the field stay on screen together,
// so tapping the field summons the keyboard (with the TypeX toolbar attached)
// right below them for a live preview.
- (UIView *)tableView:(UITableView *)tableView viewForHeaderInSection:(NSInteger)section {
    if (section != 1) return nil;

    CGFloat width = CGRectGetWidth(self.tableView.bounds);
    UIView *block = [[UIView alloc] initWithFrame:CGRectMake(0, 0, width, kTestFieldSectionHeaderHeight)];
    block.autoresizingMask = UIViewAutoresizingFlexibleWidth;

    UILabel *fieldTitle = [[UILabel alloc] initWithFrame:CGRectMake(16, 10, MAX(0, width - 32), 16)];
    fieldTitle.text = LOCALIZED(@"TEST_INPUT_FIELD");
    fieldTitle.font = [UIFont systemFontOfSize:13 weight:UIFontWeightSemibold];
    fieldTitle.textColor = [UIColor secondaryLabelColor];
    fieldTitle.autoresizingMask = UIViewAutoresizingFlexibleWidth;
    [block addSubview:fieldTitle];

    self.testInputField = [[UITextField alloc] initWithFrame:CGRectMake(16, 30, MAX(0, width - 32), 36)];
    self.testInputField.placeholder = LOCALIZED(@"TEST_INPUT_FIELD_PLACEHOLDER");
    self.testInputField.font = [UIFont systemFontOfSize:15];
    self.testInputField.borderStyle = UITextBorderStyleRoundedRect;
    self.testInputField.delegate = self;
    self.testInputField.returnKeyType = UIReturnKeyDone;
    self.testInputField.clearButtonMode = UITextFieldViewModeWhileEditing;
    self.testInputField.autoresizingMask = UIViewAutoresizingFlexibleWidth;
    [block addSubview:self.testInputField];

    UILabel *sectionTitle = [[UILabel alloc] initWithFrame:CGRectMake(16, 78, MAX(0, width - 32), 18)];
    sectionTitle.text = LOCALIZED(@"BUTTON_SETTINGS");
    sectionTitle.font = [UIFont systemFontOfSize:13 weight:UIFontWeightSemibold];
    sectionTitle.textColor = [UIColor secondaryLabelColor];
    sectionTitle.autoresizingMask = UIViewAutoresizingFlexibleWidth;
    [block addSubview:sectionTitle];

    return block;
}

- (CGFloat)tableView:(UITableView *)tableView heightForHeaderInSection:(NSInteger)section {
    return section == 1 ? kTestFieldSectionHeaderHeight : UITableViewAutomaticDimension;
}

// On keyboard show the table scrolls the test field to the top and pads the
// bottom inset by the keyboard height, so the button-settings sliders stay
// above the keyboard instead of being covered by it.
- (void)handleKeyboardWillShow:(NSNotification *)notification {
    if (!self.testInputField.isFirstResponder) return;
    [self applyKeyboardInfo:notification.userInfo scrollTestFieldToTop:YES];
}

// Interactive dismissal drags fire repeated frame changes: track the keyboard
// with the inset but never re-scroll mid-drag.
- (void)handleKeyboardFrameWillChange:(NSNotification *)notification {
    if (!self.testInputField.isFirstResponder) return;
    [self applyKeyboardInfo:notification.userInfo scrollTestFieldToTop:NO];
}

- (void)handleKeyboardWillHide:(NSNotification *)notification {
    CGFloat duration = [notification.userInfo[UIKeyboardAnimationDurationUserInfoKey] floatValue];
    UIViewAnimationOptions options = [notification.userInfo[UIKeyboardAnimationCurveUserInfoKey] unsignedIntegerValue] << 16;
    [UIView animateWithDuration:duration delay:0 options:options | UIViewAnimationOptionBeginFromCurrentState animations:^{
        UIEdgeInsets inset = self.tableView.contentInset;
        inset.bottom = 0;
        self.tableView.contentInset = inset;
        self.tableView.scrollIndicatorInsets = inset;
    } completion:nil];
}

- (void)applyKeyboardInfo:(NSDictionary *)info scrollTestFieldToTop:(BOOL)scroll {
    CGRect endFrame = [info[UIKeyboardFrameEndUserInfoKey] CGRectValue];
    if (CGRectIsNull(endFrame) || CGRectGetHeight(endFrame) <= 0) return;

    CGFloat duration = [info[UIKeyboardAnimationDurationUserInfoKey] floatValue];
    UIViewAnimationOptions options = [info[UIKeyboardAnimationCurveUserInfoKey] unsignedIntegerValue] << 16;
    CGRect localFrame = [self.tableView convertRect:endFrame fromView:nil];
    CGFloat overlap = MAX(0, CGRectGetMaxY(self.tableView.bounds) - CGRectGetMinY(localFrame));

    [UIView animateWithDuration:duration delay:0 options:options | UIViewAnimationOptionBeginFromCurrentState animations:^{
        UIEdgeInsets inset = self.tableView.contentInset;
        inset.bottom = overlap;
        self.tableView.contentInset = inset;
        self.tableView.scrollIndicatorInsets = inset;

        if (scroll) {
            UIView *block = [self.tableView headerViewForSection:1];
            if (block) {
                CGFloat maxOffset = self.tableView.contentSize.height
                    + self.tableView.adjustedContentInset.bottom
                    - CGRectGetHeight(self.tableView.bounds);
                CGFloat target = MAX(-self.tableView.adjustedContentInset.top,
                                     MIN(CGRectGetMinY(block.frame) - 4.0, MAX(0.0, maxOffset)));
                [self.tableView setContentOffset:CGPointMake(0, target) animated:NO];
            }
        }
    } completion:nil];
}

- (BOOL)textFieldShouldReturn:(UITextField *)textField {
    [textField resignFirstResponder];
    return YES;
}

#pragma mark - Toolbar-scoped button settings

// Every appearance key is scoped: the top page writes "top"-prefixed keys, the
// bottom page writes the unprefixed ones. The tweak reads the same scoped keys
// per toolbar, so the two toolbars are styled independently.
- (NSString *)scopedAppearanceKey:(NSString *)baseKey {
    return self.topConfiguration ? [@"top" stringByAppendingString:baseKey] : baseKey;
}

- (BOOL)storedBoolForKey:(NSString *)key fallback:(BOOL)fallback {
    id value = [[DXPrefsManager sharedInstance] getValueForKey:key];
    return [value respondsToSelector:@selector(boolValue)] ? [value boolValue] : fallback;
}

- (void)buildSettingsRows {
    // The runtime adds +5 to the unprefixed height fallback while the shared
    // background tint is on; mirror that so the slider shows the effective
    // default instead of silently jumping on first drag.
    BOOL backgroundTintOn = [self storedBoolForKey:kColorEnabledkey fallback:NO] &&
                            [self storedBoolForKey:kShortcutsBackgroundTintEnabled fallback:YES];
    float heightDefault = self.topConfiguration ? 33.33
        : (backgroundTintOn ? cellsHeightDefault + 5 : cellsHeightDefault);

    self.appearanceRows = @[
        [DXSettingsRow segmentRowWithKey:[self scopedAppearanceKey:kShortLabelEnabledKey]
                                  label:LOCALIZED(@"DISPLAY_STYLE")
                                 titles:@[LOCALIZED(@"ICON"), LOCALIZED(@"TEXT")]
                           defaultValue:0],
        [DXSettingsRow switchRowWithKey:[self scopedAppearanceKey:kCellBorderEnabledkey]
                                  label:LOCALIZED(@"BORDER_ENABLED") defaultValue:NO],
        [DXSettingsRow sliderRowWithKey:[self scopedAppearanceKey:kCellBorderWidthkey]
                                  label:LOCALIZED(@"BORDER_WIDTH") minValue:0.5 maxValue:10 step:0.5
                            defaultValue:buttonBorderWidthDefault],
        [DXSettingsRow sliderRowWithKey:[self scopedAppearanceKey:kButtonWidthScalekey]
                                  label:LOCALIZED(@"BUTTON_WIDTH") minValue:30 maxValue:100 step:0.5
                            defaultValue:buttonWidthScaleDefault],
        [DXSettingsRow sliderRowWithKey:[self scopedAppearanceKey:kCellHeightkey]
                                  label:LOCALIZED(@"HEIGHT") minValue:25 maxValue:50 step:0.5
                            defaultValue:heightDefault],
        [DXSettingsRow sliderRowWithKey:[self scopedAppearanceKey:kCellRadiuskey]
                                  label:LOCALIZED(@"RADIUS") minValue:0 maxValue:30 step:0.5
                            defaultValue:cellsRadiusDefault],
        [DXSettingsRow sliderRowWithKey:[self scopedAppearanceKey:kCellSpacingkey]
                                  label:LOCALIZED(@"SPACING") minValue:0 maxValue:20 step:0.5
                            defaultValue:spacingBetweenCellsDefault],
    ];

    DXSettingsRow *panelScaleRow = [DXSettingsRow sliderRowWithKey:[self scopedAppearanceKey:kSubActionPanelScaleKey]
                                                              label:LOCALIZED(@"PANEL_SIZE")
                                                           minValue:50 maxValue:120 step:5
                                                        defaultValue:subActionPanelScaleDefault];
    panelScaleRow.valueSuffix = @"%";
    self.panelRows = @[panelScaleRow];

    if (self.topConfiguration) return;

    // The toolbar height is the only remaining positioning control; the
    // leading/trailing/vertical offsets and the insets are fixed in the tweak.
    self.offsetRows = @[
        [DXSettingsRow sliderRowWithKey:kHeightOffsetkey label:LOCALIZED(@"TOOLBAR_HEIGHT") minValue:50 maxValue:80 step:1 defaultValue:heightOffsetDefault],
    ];
}

- (DXSettingsRow *)settingsRowForIndexPath:(NSIndexPath *)indexPath {
    switch (indexPath.section) {
        case 1: return self.appearanceRows[indexPath.row];
        case 2: return self.panelRows[indexPath.row];
        default: return self.offsetRows[indexPath.row];
    }
}

- (float)storedFloatForRow:(DXSettingsRow *)row {
    id value = [[DXPrefsManager sharedInstance] getValueForKey:row.key];
    return [value respondsToSelector:@selector(floatValue)] ? [value floatValue] : row.defaultValue;
}

static NSString *DXFormatSettingsValue(float value, float step, NSString *suffix) {
    NSString *number = step < 0.99f ? [NSString stringWithFormat:@"%.1f", value]
                                   : [NSString stringWithFormat:@"%.0f", value];
    return suffix.length ? [number stringByAppendingString:suffix] : number;
}

// Snap to the row's step so the stored value matches what the slider showed.
- (void)persistRowValue:(DXSettingsRow *)row rawValue:(float)rawValue {
    float stepped = row.minValue + roundf((rawValue - row.minValue) / row.step) * row.step;
    stepped = MIN(row.maxValue, MAX(row.minValue, stepped));
    [[DXPrefsManager sharedInstance] setValue:@(stepped) forKey:row.key];
}

- (UITableViewCell *)settingsCellForRowAtIndexPath:(NSIndexPath *)indexPath {
    DXSettingsRow *row = [self settingsRowForIndexPath:indexPath];
    if (row.isSwitch) return [self switchCellForRow:row];
    if (row.isSegment) return [self segmentCellForRow:row indexPath:indexPath];

    UITableViewCell *cell = [self.tableView dequeueReusableCellWithIdentifier:@"TypeXSettingsSlider" forIndexPath:indexPath];
    cell.selectionStyle = UITableViewCellSelectionStyleNone;
    cell.textLabel.text = nil;

    UILabel *titleLabel = (UILabel *)[cell viewWithTag:1];
    UILabel *valueLabel = (UILabel *)[cell viewWithTag:2];
    UISlider *slider = (UISlider *)[cell viewWithTag:3];
    if (!titleLabel) {
        titleLabel = [[UILabel alloc] init];
        titleLabel.tag = 1;
        titleLabel.font = [UIFont systemFontOfSize:15];
        titleLabel.translatesAutoresizingMaskIntoConstraints = NO;
        [cell.contentView addSubview:titleLabel];

        valueLabel = [[UILabel alloc] init];
        valueLabel.tag = 2;
        valueLabel.font = [UIFont monospacedDigitSystemFontOfSize:14 weight:UIFontWeightRegular];
        valueLabel.textColor = [UIColor secondaryLabelColor];
        valueLabel.textAlignment = NSTextAlignmentRight;
        valueLabel.translatesAutoresizingMaskIntoConstraints = NO;
        [cell.contentView addSubview:valueLabel];

        slider = [[UISlider alloc] init];
        slider.tag = 3;
        slider.translatesAutoresizingMaskIntoConstraints = NO;
        [slider addTarget:self action:@selector(settingsSliderChanged:) forControlEvents:UIControlEventValueChanged];
        [slider addTarget:self action:@selector(settingsSliderReleased:) forControlEvents:UIControlEventTouchUpInside | UIControlEventTouchUpOutside];
        [cell.contentView addSubview:slider];

        [NSLayoutConstraint activateConstraints:@[
            [titleLabel.leadingAnchor constraintEqualToAnchor:cell.contentView.leadingAnchor constant:16],
            [titleLabel.centerYAnchor constraintEqualToAnchor:cell.contentView.centerYAnchor],
            [titleLabel.widthAnchor constraintLessThanOrEqualToConstant:110],
            [valueLabel.trailingAnchor constraintEqualToAnchor:cell.contentView.trailingAnchor constant:-16],
            [valueLabel.centerYAnchor constraintEqualToAnchor:cell.contentView.centerYAnchor],
            [valueLabel.widthAnchor constraintEqualToConstant:50],
            [slider.leadingAnchor constraintEqualToAnchor:titleLabel.trailingAnchor constant:8],
            [slider.trailingAnchor constraintEqualToAnchor:valueLabel.leadingAnchor constant:-8],
            [slider.centerYAnchor constraintEqualToAnchor:cell.contentView.centerYAnchor],
        ]];
    }

    titleLabel.text = row.label;
    slider.minimumValue = row.minValue;
    slider.maximumValue = row.maxValue;
    slider.value = MIN(row.maxValue, MAX(row.minValue, [self storedFloatForRow:row]));
    valueLabel.text = DXFormatSettingsValue(slider.value, row.step, row.valueSuffix);
    objc_setAssociatedObject(slider, @selector(key), row, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    return cell;
}

- (UITableViewCell *)switchCellForRow:(DXSettingsRow *)row {
    UITableViewCell *cell = [self.tableView dequeueReusableCellWithIdentifier:@"TypeXSettingsSwitch"];
    cell.selectionStyle = UITableViewCellSelectionStyleNone;
    cell.textLabel.text = row.label;
    cell.textLabel.font = [UIFont systemFontOfSize:15];

    UISwitch *switchView = (UISwitch *)cell.accessoryView;
    if (![switchView isKindOfClass:[UISwitch class]]) {
        switchView = [[UISwitch alloc] init];
        cell.accessoryView = switchView;
        [switchView addTarget:self action:@selector(settingsSwitchChanged:) forControlEvents:UIControlEventValueChanged];
    }
    [switchView setOn:[self storedFloatForRow:row] >= 0.5 animated:NO];
    objc_setAssociatedObject(switchView, @selector(key), row, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    return cell;
}

// Full-width segmented control row (PSSegmentCell style): the control spans
// the cell so the two options are large and obvious, no leading label.
- (UITableViewCell *)segmentCellForRow:(DXSettingsRow *)row indexPath:(NSIndexPath *)indexPath {
    UITableViewCell *cell = [self.tableView dequeueReusableCellWithIdentifier:@"TypeXSettingsSegment" forIndexPath:indexPath];
    cell.selectionStyle = UITableViewCellSelectionStyleNone;

    UISegmentedControl *segment = (UISegmentedControl *)[cell.contentView viewWithTag:4];
    if (!segment) {
        segment = [[UISegmentedControl alloc] init];
        segment.tag = 4;
        segment.translatesAutoresizingMaskIntoConstraints = NO;
        [segment addTarget:self action:@selector(settingsSegmentChanged:) forControlEvents:UIControlEventValueChanged];
        [cell.contentView addSubview:segment];
        [NSLayoutConstraint activateConstraints:@[
            [segment.leadingAnchor constraintEqualToAnchor:cell.contentView.leadingAnchor constant:16],
            [segment.trailingAnchor constraintEqualToAnchor:cell.contentView.trailingAnchor constant:-16],
            [segment.topAnchor constraintEqualToAnchor:cell.contentView.topAnchor constant:8],
            [segment.bottomAnchor constraintEqualToAnchor:cell.contentView.bottomAnchor constant:-8],
            [segment.heightAnchor constraintGreaterThanOrEqualToConstant:32],
        ]];
    }
    [segment removeAllSegments];
    [row.segmentTitles enumerateObjectsUsingBlock:^(NSString *title, NSUInteger idx, BOOL *stop) {
        [segment insertSegmentWithTitle:title atIndex:idx animated:NO];
    }];
    NSInteger selected = (NSInteger)[self storedFloatForRow:row];
    segment.selectedSegmentIndex = MAX(0, MIN((NSInteger)row.segmentTitles.count - 1, selected));
    objc_setAssociatedObject(segment, @selector(key), row, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    return cell;
}

- (void)settingsSwitchChanged:(UISwitch *)sender {
    DXSettingsRow *row = objc_getAssociatedObject(sender, @selector(key));
    [[DXPrefsManager sharedInstance] setValue:@(sender.isOn) forKey:row.key];
}

- (void)settingsSegmentChanged:(UISegmentedControl *)sender {
    DXSettingsRow *row = objc_getAssociatedObject(sender, @selector(key));
    [[DXPrefsManager sharedInstance] setValue:@(sender.selectedSegmentIndex) forKey:row.key];
}

- (void)settingsSliderChanged:(UISlider *)sender {
    // Live label feedback; the preference write itself waits for touch-up so
    // dragging does not spam the preference domain and reload notifications.
    UILabel *valueLabel = (UILabel *)[(UIView *)sender.superview viewWithTag:2];
    DXSettingsRow *row = objc_getAssociatedObject(sender, @selector(key));
    valueLabel.text = DXFormatSettingsValue(sender.value, row.step, row.valueSuffix);
}

- (void)settingsSliderReleased:(UISlider *)sender {
    DXSettingsRow *row = objc_getAssociatedObject(sender, @selector(key));
    [self persistRowValue:row rawValue:sender.value];
}

#pragma mark - Add button

- (void)addButtonTapped{
    // Adding is unlimited; only the number of switched-on buttons is capped
    // (enforced at enable time, and new buttons join switched off when 8 are
    // already on).
    DXPGesturePickerController *gesturePickerController = [[DXPGesturePickerController alloc] init];
    gesturePickerController.fullOrder = self.fullOrder;
    gesturePickerController.configuration = self.topConfiguration ? @"top" : @"bottom";
    // A new button has no action yet: its tap action (chosen in the pushed
    // page) defines it, so the identifier is left nil until the user picks.
    gesturePickerController.pendingNewEntry = YES;
    gesturePickerController.title = LOCALIZED(@"NEW_BUTTON");

    [gesturePickerController setRootController: [self rootController]];
    [gesturePickerController setParentController: [self parentController]];
    [self pushController:gesturePickerController];
}

#pragma mark - Storage

- (void)writeToFile{
    [[DXPrefsManager sharedInstance] setValue:self.currentOrder forKey:self.shortcutsPreferenceKey ?: kShortcutskey];
}

// Removes the per-gesture custom actions and the ordered sub-actions recorded
// for a deleted button so a later re-add starts clean instead of silently
// inheriting old gestures.
- (void)removeCustomActionsForIdentifier:(NSString *)identifier {
    if (![identifier isKindOfClass:[NSString class]] || identifier.length == 0) return;
    NSString *configuration = self.topConfiguration ? @"top" : @"bottom";

    NSMutableArray<NSString *> *keys = [NSMutableArray array];
    for (NSInteger gesture = DXShortcutGestureLongPress; gesture <= DXShortcutGestureTap; gesture++) {
        [keys addObject:DXCustomActionsKeyForGesture((int)gesture, configuration)];
    }
    [keys addObject:DXScopedPreferenceKey(kSubActionskey, configuration)];

    NSMutableDictionary *prefs = [[[DXPrefsManager sharedInstance] readPrefs] mutableCopy] ?: [NSMutableDictionary dictionary];
    BOOL changed = NO;
    for (NSString *key in keys) {
        NSArray *entries = prefs[key];
        if (![entries isKindOfClass:[NSArray class]]) continue;
        NSArray *filtered = [entries filteredArrayUsingPredicate:[NSPredicate predicateWithFormat:@"identifier != %@", identifier]];
        if (![filtered isEqualToArray:entries]) {
            prefs[key] = filtered;
            changed = YES;
        }
    }
    if (changed) [[DXPrefsManager sharedInstance] writePrefs:prefs];
}

- (void)updateOrder:(BOOL)reset{
    NSMutableDictionary *prefs = [[[DXPrefsManager sharedInstance] readPrefs] mutableCopy] ?: [NSMutableDictionary dictionary];
    NSString *shortcutsKey = self.shortcutsPreferenceKey ?: kShortcutskey;

    DXShortcutsGenerator *shortcutsGenerator = [DXShortcutsGenerator sharedInstance];
    NSMutableArray *defaultOrderLabel = [[shortcutsGenerator labelName] mutableCopy];
    NSMutableArray *defaultOrderSelector = [[shortcutsGenerator selectorNames] mutableCopy];
    NSMutableArray *defaultOrder12 = [[shortcutsGenerator imageNameArrayForiOS:0] mutableCopy];
    NSMutableArray *defaultOrder13 = [[shortcutsGenerator imageNameArrayForiOS:1] mutableCopy];

    NSMutableArray *fullOrderDict = [[NSMutableArray alloc] init];

    for (int i = 0; i < [defaultOrderLabel count]; i++){
        if (DXIsHiddenShortcutSelector(defaultOrderSelector[i])) {
            continue;
        }
        [fullOrderDict addObject: @{
            @"label" : defaultOrderLabel[i],
            @"images12" : defaultOrder12[i],
            @"images13" : defaultOrder13[i],
            @"selector" : defaultOrderSelector[i],
        }];
    }

    self.fullOrder = fullOrderDict;

    id storedOrder = prefs[shortcutsKey];
    BOOL hasStoredOrder = !reset && [storedOrder isKindOfClass:[NSArray class]] && [storedOrder count] >= 2;
    NSArray *storedEnabled = hasStoredOrder && [storedOrder[0] isKindOfClass:[NSArray class]] ? storedOrder[0] : @[];
    NSArray *storedDisabled = hasStoredOrder && [storedOrder[1] isKindOfClass:[NSArray class]] ? storedOrder[1] : @[];

    NSMutableArray *enabled = [NSMutableArray array];
    NSMutableArray *disabled = [NSMutableArray array];
    NSMutableSet *seenSelectors = [NSMutableSet set];

    if (hasStoredOrder) {
        // The stored list holds every added button, switched on or off; the
        // enable cap is enforced at toggle time, not by trimming the list.
        DXAppendUniqueShortcuts(storedEnabled, enabled, seenSelectors, NSUIntegerMax);
    }
    // Defaults seed only a configuration that was never stored. An explicitly
    // emptied toolbar (user deleted every button) stays empty.
    if (!hasStoredOrder) {
        DXAppendUniqueShortcuts(fullOrderDict, enabled, seenSelectors, maxdefaultshortcuts);
    }

    if (hasStoredOrder) {
        DXAppendUniqueShortcuts(storedDisabled, disabled, seenSelectors, NSUIntegerMax);
    }
    // Compare shortcut identity by selector.  Stored entries from older versions
    // may contain obsolete metadata (for example selectorlp), so dictionary
    // equality would incorrectly append a second copy of the same action.
    DXAppendUniqueShortcuts(fullOrderDict, disabled, seenSelectors, NSUIntegerMax);

    self.currentOrder = [NSMutableArray arrayWithObjects:enabled, disabled, nil];

    // The page only manages the enabled section; the disabled section is kept
    // in the stored schema so the toolbar keeps reading the two-section format.
    NSArray *normalizedOrder = @[[enabled copy], [disabled copy]];
    if (reset || ![storedOrder isEqual:normalizedOrder]) {
        prefs[shortcutsKey] = normalizedOrder;
        [[DXPrefsManager sharedInstance] writePrefs:prefs];
    }
}

- (void)viewWillDisappear:(BOOL)animated {
    [super viewWillDisappear:animated];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [self updateOrder:NO];
    [self.tableView reloadData];
}

- (void)viewDidLoad {
    self.topConfiguration = [[self.specifier propertyForKey:@"configuration"] isEqualToString:@"top"];
    self.shortcutsPreferenceKey = self.topConfiguration ? kTopShortcutskey : kShortcutskey;
    tweakBundle = [NSBundle bundleWithPath:bundlePath];
    [tweakBundle load];
    [super viewDidLoad];
    self.tableView = [[UITableView alloc] initWithFrame:CGRectMake(0, 0, self.view.frame.size.width, self.view.frame.size.height) style:UITableViewStyleGrouped];
    self.tableView.delegate = self;
    self.tableView.dataSource = self;
    [self.tableView setAutoresizingMask:UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight];
    [self.tableView registerClass:[UITableViewCell class] forCellReuseIdentifier:@"TypeXItemCell"];
    [self.tableView registerClass:[UITableViewCell class] forCellReuseIdentifier:@"TypeXSettingsSwitch"];
    [self.tableView registerClass:[UITableViewCell class] forCellReuseIdentifier:@"TypeXSettingsSegment"];
    [self.tableView registerClass:[UITableViewCell class] forCellReuseIdentifier:@"TypeXSettingsSlider"];
    [self buildSettingsRows];
    [self.tableView setEditing:YES];
    self.tableView.allowsSelectionDuringEditing=YES;

    // Keyboard avoidance for the mid-page test field: track show/frame-change/
    // hide so the button-settings sliders stay above the keyboard while it is
    // open; dragging the table can dismiss the keyboard to see the full list.
    self.tableView.keyboardDismissMode = UIScrollViewKeyboardDismissModeInteractive;
    NSNotificationCenter *center = [NSNotificationCenter defaultCenter];
    [center addObserver:self selector:@selector(handleKeyboardWillShow:) name:UIKeyboardWillShowNotification object:nil];
    [center addObserver:self selector:@selector(handleKeyboardFrameWillChange:) name:UIKeyboardWillChangeFrameNotification object:nil];
    [center addObserver:self selector:@selector(handleKeyboardWillHide:) name:UIKeyboardWillHideNotification object:nil];

    ((UIViewController *)self).title = self.topConfiguration ? @"顶部设置" : @"底部设置";
    self.view = self.tableView;

    self.addBtn = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemAdd target:self action:@selector(addButtonTapped)];
    self.navigationItem.rightBarButtonItem = self.addBtn;
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

@end
