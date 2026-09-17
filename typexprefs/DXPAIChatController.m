#import "DXPAIChatController.h"
#import "../common.h"
#import "../DXHelper.h"
#import "../DXAIEngine.h"

static NSBundle *tweakBundle;

#pragma mark - 偏好读写

static id DXAIPrefValue(NSString *key) {
    return [[DXPrefsManager sharedInstance] getValueForKey:key];
}

static void DXAIPrefSetValue(id value, NSString *key) {
    [[DXPrefsManager sharedInstance] setValue:value forKey:key];
}

static NSString *DXAIKeyPath(NSString *prefix, NSString *engineID) {
    return [prefix stringByAppendingString:engineID ?: @""];
}

#pragma mark - 文本输入行（label + 右侧输入框）

@interface DXPAITextFieldCell : UITableViewCell <UITextFieldDelegate>
@property (nonatomic, strong) UILabel *label;
@property (nonatomic, strong) UITextField *textField;
@property (nonatomic, copy) void (^onCommit)(NSString *text);
@end

@implementation DXPAITextFieldCell

- (instancetype)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)reuseIdentifier {
    if ((self = [super initWithStyle:style reuseIdentifier:reuseIdentifier])) {
        self.selectionStyle = UITableViewCellSelectionStyleNone;

        self.label = [[UILabel alloc] init];
        self.label.font = [UIFont systemFontOfSize:17.0];
        self.label.textColor = [UIColor labelColor];
        [self.contentView addSubview:self.label];

        self.textField = [[UITextField alloc] init];
        self.textField.font = [UIFont systemFontOfSize:17.0];
        self.textField.textAlignment = NSTextAlignmentRight;
        self.textField.textColor = [UIColor secondaryLabelColor];
        self.textField.clearButtonMode = UITextFieldViewModeWhileEditing;
        self.textField.autocorrectionType = UITextAutocorrectionTypeNo;
        self.textField.autocapitalizationType = UITextAutocapitalizationTypeNone;
        self.textField.keyboardType = UIKeyboardTypeURL;
        self.textField.delegate = self;
        [self.contentView addSubview:self.textField];

        self.label.translatesAutoresizingMaskIntoConstraints = NO;
        self.textField.translatesAutoresizingMaskIntoConstraints = NO;
        [NSLayoutConstraint activateConstraints:@[
            [self.label.leadingAnchor constraintEqualToAnchor:self.contentView.layoutMarginsGuide.leadingAnchor],
            [self.label.centerYAnchor constraintEqualToAnchor:self.contentView.centerYAnchor],
            [self.label.trailingAnchor constraintLessThanOrEqualToAnchor:self.textField.leadingAnchor constant:-8.0],
            [self.textField.trailingAnchor constraintEqualToAnchor:self.contentView.layoutMarginsGuide.trailingAnchor],
            [self.textField.centerYAnchor constraintEqualToAnchor:self.contentView.centerYAnchor],
            [self.textField.widthAnchor constraintGreaterThanOrEqualToAnchor:self.contentView.widthAnchor multiplier:0.42 constant:0.0],
        ]];
    }
    return self;
}

- (void)textFieldDidEndEditing:(UITextField *)textField {
    if (self.onCommit) self.onCommit(textField.text ?: @"");
}

@end

#pragma mark - 模型列表行（label + 内嵌多行文本区）

@interface DXPAIModelsCell : UITableViewCell <UITextViewDelegate>
@property (nonatomic, strong) UILabel *label;
@property (nonatomic, strong) UIView *fieldContainer;
@property (nonatomic, strong) UITextView *textView;
@property (nonatomic, copy) void (^onCommit)(NSString *text);
@end

@implementation DXPAIModelsCell

- (instancetype)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)reuseIdentifier {
    if ((self = [super initWithStyle:style reuseIdentifier:reuseIdentifier])) {
        self.selectionStyle = UITableViewCellSelectionStyleNone;

        self.label = [[UILabel alloc] init];
        self.label.font = [UIFont systemFontOfSize:17.0];
        self.label.textColor = [UIColor labelColor];
        [self.contentView addSubview:self.label];

        self.fieldContainer = [[UIView alloc] init];
        self.fieldContainer.backgroundColor = [UIColor tertiarySystemFillColor];
        self.fieldContainer.layer.cornerRadius = 12.0;
        [self.contentView addSubview:self.fieldContainer];

        self.textView = [[UITextView alloc] init];
        self.textView.font = [UIFont systemFontOfSize:16.0];
        self.textView.textColor = [UIColor labelColor];
        self.textView.backgroundColor = UIColor.clearColor;
        self.textView.autocorrectionType = UITextAutocorrectionTypeNo;
        self.textView.autocapitalizationType = UITextAutocapitalizationTypeNone;
        self.textView.keyboardType = UIKeyboardTypeURL;
        self.textView.delegate = self;
        [self.fieldContainer addSubview:self.textView];

        self.label.translatesAutoresizingMaskIntoConstraints = NO;
        self.fieldContainer.translatesAutoresizingMaskIntoConstraints = NO;
        self.textView.translatesAutoresizingMaskIntoConstraints = NO;
        [NSLayoutConstraint activateConstraints:@[
            [self.label.topAnchor constraintEqualToAnchor:self.contentView.topAnchor constant:12.0],
            [self.label.leadingAnchor constraintEqualToAnchor:self.contentView.layoutMarginsGuide.leadingAnchor],
            [self.fieldContainer.topAnchor constraintEqualToAnchor:self.label.bottomAnchor constant:10.0],
            [self.fieldContainer.leadingAnchor constraintEqualToAnchor:self.contentView.layoutMarginsGuide.leadingAnchor],
            [self.fieldContainer.trailingAnchor constraintEqualToAnchor:self.contentView.layoutMarginsGuide.trailingAnchor],
            [self.fieldContainer.bottomAnchor constraintEqualToAnchor:self.contentView.bottomAnchor constant:-12.0],
            [self.textView.topAnchor constraintEqualToAnchor:self.fieldContainer.topAnchor constant:10.0],
            [self.textView.leadingAnchor constraintEqualToAnchor:self.fieldContainer.leadingAnchor constant:12.0],
            [self.textView.trailingAnchor constraintEqualToAnchor:self.fieldContainer.trailingAnchor constant:-12.0],
            [self.textView.bottomAnchor constraintEqualToAnchor:self.fieldContainer.bottomAnchor constant:-10.0],
        ]];
    }
    return self;
}

- (void)textViewDidEndEditing:(UITextView *)textView {
    if (self.onCommit) self.onCommit(textView.text ?: @"");
}

@end

#pragma mark - AI 问答主页

@interface DXPAIChatController ()
@property (nonatomic, assign) BOOL fetching;
@end

@implementation DXPAIChatController

- (void)viewDidLoad {
    tweakBundle = [NSBundle bundleWithPath:bundlePath];
    [tweakBundle load];

    [super viewDidLoad];
    self.title = LOCALIZED(@"AI_SETTINGS_TITLE");

    self.tableView = [[UITableView alloc] initWithFrame:self.view.bounds style:UITableViewStyleInsetGrouped];
    self.tableView.delegate = self;
    self.tableView.dataSource = self;
    self.tableView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    [self.view addSubview:self.tableView];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    // 引擎选择页可能改写了当前引擎，整页配置组随之刷新。
    [self.tableView reloadData];
}

- (void)viewWillDisappear:(BOOL)animated {
    [super viewWillDisappear:animated];
    [self.view endEditing:YES]; // 触发各输入行的 onCommit 落盘
}

- (DXAIEngineInfo *)currentEngine {
    return [DXAIEngine currentEngine];
}

#pragma mark Sections

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    return 3;
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    if (section == 0) return LOCALIZED(@"AI_ENGINE");
    if (section == 1) return [self currentEngine].displayName;
    return LOCALIZED(@"AI_PERSONA_SECTION");
}

- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section {
    if (section == 1) {
        NSString *hintKey = [NSString stringWithFormat:@"AI_HINT_%@", [self currentEngine].identifier.uppercaseString];
        return LOCALIZED(hintKey);
    }
    return nil;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    if (section == 0) return 1;
    if (section == 2) return 4;
    // API Key (+ 自定义引擎的接口地址/显示名称) + 模型 + 抓取 (+ 获取网址)
    NSInteger rows = [self isCustomEngine] ? 5 : 3;
    if ([self currentEngine].keysURL.length > 0) rows += 1;
    return rows;
}

- (BOOL)isCustomEngine {
    return [[self currentEngine].identifier isEqualToString:@"custom"];
}

- (CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath {
    if (indexPath.section == 1) {
        NSString *kind = [self kindForRow:indexPath.row];
        if ([kind isEqualToString:@"models"]) return 136.0;
        if ([kind isEqualToString:@"text"]) return 48.0;
        return 44.0;
    }
    return 44.0;
}

// Section 1 的行语义：api-key[, endpoint, name](自定义) → models → fetch → keys-url
- (NSString *)kindForRow:(NSInteger)row {
    if ([self isCustomEngine]) {
        if (row == 0) return @"text";    // API Key
        if (row == 1) return @"text";    // 接口地址
        if (row == 2) return @"text";    // 显示名称
        if (row == 3) return @"models";
        if (row == 4) return @"fetch";
        return @"keysurl";
    }
    if (row == 0) return @"text";        // API Key
    if (row == 1) return @"models";
    if (row == 2) return @"fetch";
    return @"keysurl";
}

- (NSString *)textKeyForRow:(NSInteger)row {
    if ([self isCustomEngine]) {
        if (row == 0) return DXAIKeyPath(DXAIPrefKeyPrefix, [self currentEngine].identifier);
        if (row == 1) return DXAIPrefCustomEndpoint;
        return DXAIPrefCustomName;
    }
    return DXAIKeyPath(DXAIPrefKeyPrefix, [self currentEngine].identifier);
}

#pragma mark Cells

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    if (indexPath.section == 0) return [self engineCell];
    if (indexPath.section == 2) return [self personaCellForRow:indexPath.row];
    return [self configCellForRow:indexPath.row];
}

- (UITableViewCell *)engineCell {
    static NSString *identifier = @"DXPAIEngineRow";
    UITableViewCell *cell = [self.tableView dequeueReusableCellWithIdentifier:identifier];
    if (!cell) cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleValue1 reuseIdentifier:identifier];
    cell.textLabel.text = LOCALIZED(@"AI_CURRENT_ENGINE");
    cell.detailTextLabel.text = [self currentEngine].displayName;
    cell.detailTextLabel.textColor = [UIColor secondaryLabelColor];
    cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
    return cell;
}

- (UITableViewCell *)configCellForRow:(NSInteger)row {
    NSString *kind = [self kindForRow:row];
    DXAIEngineInfo *engine = [self currentEngine];

    if ([kind isEqualToString:@"text"]) {
        static NSString *textIdentifier = @"DXPAITextField";
        DXPAITextFieldCell *cell = [self.tableView dequeueReusableCellWithIdentifier:textIdentifier];
        if (!cell) cell = [[DXPAITextFieldCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:textIdentifier];
        cell.onCommit = nil; // 复用重配期间避免旧块误触发
        if ([kind isEqualToString:@"text"] && row == 0) cell.label.text = LOCALIZED(@"AI_API_KEY");
        else if (row == 1) cell.label.text = LOCALIZED(@"AI_ENDPOINT");
        else cell.label.text = LOCALIZED(@"AI_CUSTOM_NAME");
        cell.textField.text = [DXAIPrefValue([self textKeyForRow:row]) isKindOfClass:[NSString class]]
            ? DXAIPrefValue([self textKeyForRow:row]) : @"";
        cell.textField.placeholder = [cell.label.text isEqualToString:LOCALIZED(@"AI_API_KEY")] ? @"sk-…" : @"";
        NSString *keyPath = [self textKeyForRow:row];
        __weak typeof(self) weakSelf = self;
        cell.onCommit = ^(NSString *text) {
            DXAIPrefSetValue(text ?: @"", keyPath);
            (void)weakSelf;
        };
        return cell;
    }

    if ([kind isEqualToString:@"models"]) {
        static NSString *modelsIdentifier = @"DXPAIModels";
        DXPAIModelsCell *cell = [self.tableView dequeueReusableCellWithIdentifier:modelsIdentifier];
        if (!cell) cell = [[DXPAIModelsCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:modelsIdentifier];
        cell.label.text = LOCALIZED(@"AI_MODELS_LABEL");
        cell.onCommit = nil;
        cell.textView.text = [[DXAIEngine modelsForEngine:engine] componentsJoinedByString:@", "];
        NSString *keyPath = DXAIKeyPath(DXAIPrefModelsPrefix, engine.identifier);
        cell.onCommit = ^(NSString *text) {
            DXAIPrefSetValue(text ?: @"", keyPath);
        };
        return cell;
    }

    static NSString *buttonIdentifier = @"DXPAIButton";
    UITableViewCell *cell = [self.tableView dequeueReusableCellWithIdentifier:buttonIdentifier];
    if (!cell) cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:buttonIdentifier];
    cell.selectionStyle = UITableViewCellSelectionStyleDefault;
    cell.accessoryType = UITableViewCellAccessoryNone;
    cell.textLabel.textColor = [UIColor systemBlueColor];
    cell.textLabel.font = [UIFont systemFontOfSize:17.0];
    if ([kind isEqualToString:@"fetch"]) {
        cell.textLabel.text = self.fetching ? LOCALIZED(@"AI_FETCHING_MODELS") : LOCALIZED(@"AI_FETCH_MODELS");
        cell.textLabel.textColor = self.fetching ? [UIColor secondaryLabelColor] : [UIColor systemBlueColor];
    } else {
        cell.textLabel.text = LOCALIZED(@"AI_OPEN_KEYS_URL");
    }
    return cell;
}

- (UITableViewCell *)personaCellForRow:(NSInteger)row {
    if (row == 3) { // 流式输出
        static NSString *switchIdentifier = @"DXPAISwitch";
        UITableViewCell *cell = [self.tableView dequeueReusableCellWithIdentifier:switchIdentifier];
        if (!cell) cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:switchIdentifier];
        cell.selectionStyle = UITableViewCellSelectionStyleNone;
        cell.textLabel.text = LOCALIZED(@"AI_STREAM_ROW");
        UISwitch *toggle = [[UISwitch alloc] init];
        id stored = DXAIPrefValue(DXAIPrefStream);
        toggle.on = [stored isKindOfClass:[NSNumber class]] ? [stored boolValue] : YES;
        [toggle addTarget:self action:@selector(streamToggleChanged:) forControlEvents:UIControlEventValueChanged];
        cell.accessoryView = toggle;
        return cell;
    }

    static NSString *linkIdentifier = @"DXPAILink";
    UITableViewCell *cell = [self.tableView dequeueReusableCellWithIdentifier:linkIdentifier];
    if (!cell) cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:linkIdentifier];
    cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
    cell.textLabel.textColor = [UIColor labelColor];
    cell.textLabel.text = (row == 0) ? LOCALIZED(@"AI_PERSONA_ROW")
                        : (row == 1) ? LOCALIZED(@"AI_BALL_ROW")
                        : LOCALIZED(@"AI_THEME_ROW");
    return cell;
}

#pragma mark 交互

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];

    if (indexPath.section == 0) {
        [self.navigationController pushViewController:[[DXPAIEnginePickerController alloc] init] animated:YES];
        return;
    }
    if (indexPath.section == 2) {
        if (indexPath.row == 0) [self.navigationController pushViewController:[[DXPAIPersonaController alloc] init] animated:YES];
        else if (indexPath.row == 1) [self.navigationController pushViewController:[[DXPAIBallController alloc] init] animated:YES];
        else if (indexPath.row == 2) [self.navigationController pushViewController:[[DXPAIThemeController alloc] init] animated:YES];
        return;
    }

    NSString *kind = [self kindForRow:indexPath.row];
    if ([kind isEqualToString:@"fetch"]) {
        [self fetchModelsTapped];
    } else if ([kind isEqualToString:@"keysurl"]) {
        NSURL *url = [NSURL URLWithString:[self currentEngine].keysURL];
        if (url) [[UIApplication sharedApplication] openURL:url options:@{} completionHandler:nil];
    }
}

- (void)streamToggleChanged:(UISwitch *)toggle {
    DXAIPrefSetValue(@(toggle.on), DXAIPrefStream);
}

- (void)fetchModelsTapped {
    if (self.fetching) return;
    DXAIEngineInfo *engine = [self currentEngine];
    self.fetching = YES;
    [self.tableView reloadData];
    __weak typeof(self) weakSelf = self;
    [DXAIEngine fetchModelsForEngine:engine completion:^(NSArray<NSString *> *models, NSError *error) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf) return;
        strongSelf.fetching = NO;
        if (error) {
            UIAlertController *alert = [UIAlertController alertControllerWithTitle:nil
                                                                          message:error.localizedDescription
                                                                   preferredStyle:UIAlertControllerStyleAlert];
            [alert addAction:[UIAlertAction actionWithTitle:LOCALIZED(@"ANSWER_OK") style:UIAlertActionStyleDefault handler:nil]];
            [strongSelf presentViewController:alert animated:YES completion:nil];
            [strongSelf.tableView reloadData];
            return;
        }
        DXAIPrefSetValue([models componentsJoinedByString:@", "], DXAIKeyPath(DXAIPrefModelsPrefix, engine.identifier));
        [strongSelf.tableView reloadData];
    }];
}

@end

#pragma mark - 引擎选择

@implementation DXPAIEnginePickerController

- (void)viewDidLoad {
    tweakBundle = [NSBundle bundleWithPath:bundlePath];
    [tweakBundle load];

    [super viewDidLoad];
    self.title = LOCALIZED(@"AI_ENGINE");

    self.tableView = [[UITableView alloc] initWithFrame:self.view.bounds style:UITableViewStyleInsetGrouped];
    self.tableView.delegate = self;
    self.tableView.dataSource = self;
    self.tableView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    [self.view addSubview:self.tableView];
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return [DXAIEngine allEngines].count;
}

- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section {
    return LOCALIZED(@"AI_ENGINE_PICKER_FOOTER");
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    static NSString *identifier = @"DXPAIEnginePick";
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:identifier];
    if (!cell) cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:identifier];
    DXAIEngineInfo *engine = [DXAIEngine allEngines][indexPath.row];
    cell.textLabel.text = engine.displayName;
    cell.detailTextLabel.text = [DXAIEngine endpointForEngine:engine] ?: @"";
    cell.detailTextLabel.textColor = [UIColor secondaryLabelColor];
    cell.detailTextLabel.font = [UIFont systemFontOfSize:12.0];
    cell.accessoryType = [engine.identifier isEqualToString:[DXAIEngine currentEngine].identifier]
        ? UITableViewCellAccessoryCheckmark : UITableViewCellAccessoryNone;
    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    DXAIEngineInfo *engine = [DXAIEngine allEngines][indexPath.row];
    DXAIPrefSetValue(engine.identifier, DXAIPrefEngine);
    [tableView reloadData];
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.15 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        [self.navigationController popViewControllerAnimated:YES];
    });
}

@end

#pragma mark - 人设编辑

@implementation DXPAIPersonaController

- (void)viewDidLoad {
    tweakBundle = [NSBundle bundleWithPath:bundlePath];
    [tweakBundle load];

    [super viewDidLoad];
    self.title = LOCALIZED(@"AI_PERSONA_ROW");
    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithTitle:LOCALIZED(@"DONE")
                                                                              style:UIBarButtonItemStyleDone
                                                                             target:self
                                                                             action:@selector(doneTapped)];

    NSString *stored = [DXAIPrefValue(DXAIPrefPersona) isKindOfClass:[NSString class]] ? DXAIPrefValue(DXAIPrefPersona) : @"";
    self.textView = [[UITextView alloc] init];
    self.textView.font = [UIFont systemFontOfSize:16.0];
    self.textView.text = stored;
    self.textView.backgroundColor = [UIColor secondarySystemGroupedBackgroundColor];
    self.textView.layer.cornerRadius = 12.0;
    self.textView.delegate = self;
    self.textView.frame = CGRectInset(self.view.bounds, 16.0, 20.0);
    self.textView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    [self.view addSubview:self.textView];

    UILabel *footer = [[UILabel alloc] init];
    footer.text = LOCALIZED(@"AI_PERSONA_FOOTER");
    footer.font = [UIFont systemFontOfSize:12.0];
    footer.textColor = [UIColor secondaryLabelColor];
    footer.numberOfLines = 0;
    footer.frame = CGRectMake(20.0, CGRectGetMaxY(self.textView.frame) + 8.0, CGRectGetWidth(self.view.bounds) - 40.0, 60.0);
    footer.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleTopMargin;
    [self.view addSubview:footer];
}

- (void)viewWillDisappear:(BOOL)animated {
    [super viewWillDisappear:animated];
    [self persist];
}

- (void)doneTapped {
    [self persist];
    [self.navigationController popViewControllerAnimated:YES];
}

- (void)persist {
    DXAIPrefSetValue(self.textView.text ?: @"", DXAIPrefPersona);
}

- (void)textViewDidEndEditing:(UITextView *)textView {
    [self persist];
}

@end

#pragma mark - 悬浮球设置

@implementation DXPAIBallController

- (void)viewDidLoad {
    tweakBundle = [NSBundle bundleWithPath:bundlePath];
    [tweakBundle load];

    [super viewDidLoad];
    self.title = LOCALIZED(@"AI_BALL_ROW");

    self.tableView = [[UITableView alloc] initWithFrame:self.view.bounds style:UITableViewStyleInsetGrouped];
    self.tableView.delegate = self;
    self.tableView.dataSource = self;
    self.tableView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    [self.view addSubview:self.tableView];
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return 3;
}

- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section {
    return LOCALIZED(@"AI_BALL_FOOTER");
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    if (indexPath.row == 2) {
        static NSString *resetIdentifier = @"DXPAIBallReset";
        UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:resetIdentifier];
        if (!cell) cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:resetIdentifier];
        cell.textLabel.text = LOCALIZED(@"AI_BALL_RESET");
        cell.textLabel.textColor = [UIColor systemBlueColor];
        cell.accessoryType = UITableViewCellAccessoryNone;
        return cell;
    }

    BOOL isEnableRow = indexPath.row == 0;
    static NSString *switchIdentifier = @"DXPAIBallSwitch";
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:switchIdentifier];
    if (!cell) cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:switchIdentifier];
    cell.textLabel.text = LOCALIZED(isEnableRow ? @"AI_BALL_ENABLED" : @"AI_BALL_HALF");

    UISwitch *toggle = [[UISwitch alloc] init];
    NSString *key = isEnableRow ? DXAIPrefBall : DXAIPrefBallHalf;
    id stored = DXAIPrefValue(key);
    toggle.on = [stored isKindOfClass:[NSNumber class]] ? [stored boolValue] : (isEnableRow ? NO : YES);
    toggle.tag = indexPath.row;
    [toggle addTarget:self action:@selector(ballToggleChanged:) forControlEvents:UIControlEventValueChanged];
    cell.accessoryView = toggle;
    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    if (indexPath.row == 2) {
        [[DXPrefsManager sharedInstance] removeKey:DXAIPrefBallPos];
    }
}

- (void)ballToggleChanged:(UISwitch *)toggle {
    DXAIPrefSetValue(@(toggle.on), toggle.tag == 0 ? DXAIPrefBall : DXAIPrefBallHalf);
}

@end

#pragma mark - 窗口主题

@implementation DXPAIThemeController

- (void)viewDidLoad {
    tweakBundle = [NSBundle bundleWithPath:bundlePath];
    [tweakBundle load];

    [super viewDidLoad];
    self.title = LOCALIZED(@"AI_THEME_ROW");

    self.tableView = [[UITableView alloc] initWithFrame:self.view.bounds style:UITableViewStyleInsetGrouped];
    self.tableView.delegate = self;
    self.tableView.dataSource = self;
    self.tableView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    [self.view addSubview:self.tableView];
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return 3;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    static NSString *identifier = @"DXPAITheme";
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:identifier];
    if (!cell) cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:identifier];
    cell.textLabel.text = LOCALIZED(indexPath.row == 0 ? @"AI_THEME_SYSTEM" : indexPath.row == 1 ? @"AI_THEME_LIGHT" : @"AI_THEME_DARK");
    cell.accessoryType = [DXAIEngine themeStyle] == indexPath.row
        ? UITableViewCellAccessoryCheckmark : UITableViewCellAccessoryNone;
    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    DXAIPrefSetValue(@(indexPath.row), DXAIPrefTheme);
    [tableView reloadData];
}

@end
