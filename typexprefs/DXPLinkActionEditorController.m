#import "DXPLinkActionEditorController.h"
#import "../common.h"

static NSBundle *tweakBundle;

@interface DXPLinkActionEditorController ()
@property (nonatomic, strong) UITableView *tableView;
@property (nonatomic, strong) UITextField *nameField;
@property (nonatomic, strong) UITextField *iconField;
@property (nonatomic, strong) UITextField *linkField;
@end

@implementation DXPLinkActionEditorController

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    return 1;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return 3;
}

- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section {
    return LOCALIZED(@"CUSTOM_LINK_ACTION_FOOTER");
}

- (UITextField *)fieldForRow:(NSInteger)row {
    if (row == 0) return self.nameField;
    if (row == 1) return self.iconField;
    return self.linkField;
}

- (NSString *)labelForRow:(NSInteger)row {
    if (row == 0) return LOCALIZED(@"NAME");
    if (row == 1) return LOCALIZED(@"ICON");
    return LOCALIZED(@"ACTION_LINK");
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"DXPLinkActionFieldCell" forIndexPath:indexPath];
    cell.selectionStyle = UITableViewCellSelectionStyleNone;
    cell.textLabel.text = [self labelForRow:indexPath.row];
    cell.textLabel.font = [UIFont systemFontOfSize:16];

    UITextField *field = [self fieldForRow:indexPath.row];
    cell.accessoryView = field;
    return cell;
}

- (BOOL)textFieldShouldReturn:(UITextField *)textField {
    if (textField == self.nameField) [self.iconField becomeFirstResponder];
    else if (textField == self.iconField) [self.linkField becomeFirstResponder];
    else [textField resignFirstResponder];
    return YES;
}

- (NSString *)trimmedValue:(NSString *)value {
    if (![value isKindOfClass:[NSString class]]) return @"";
    return [value stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
}

- (void)saveTapped {
    [self.view endEditing:YES];

    NSString *name = [self trimmedValue:self.nameField.text];
    NSString *icon = [self trimmedValue:self.iconField.text];
    NSString *link = [self trimmedValue:self.linkField.text];
    if (name.length == 0) name = LOCALIZED(@"DEFAULT_BUTTON_NAME");
    if (icon.length == 0 || ![UIImage systemImageNamed:icon]) icon = @"link";

    NSMutableDictionary *updated = [self.entry mutableCopy] ?: [NSMutableDictionary dictionary];
    updated[@"name"] = name;
    updated[@"icon"] = icon;
    updated[@"link"] = link;
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

    self.title = LOCALIZED(@"CUSTOM_ACTION");
    self.entry = [self.entry mutableCopy] ?: [NSMutableDictionary dictionary];
    self.nameField = [self newFieldWithText:self.entry[@"name"] placeholder:LOCALIZED(@"DEFAULT_BUTTON_NAME")];
    self.iconField = [self newFieldWithText:self.entry[@"icon"] placeholder:@"link"];
    self.linkField = [self newFieldWithText:self.entry[@"link"] placeholder:@"https://example.com"];
    self.linkField.keyboardType = UIKeyboardTypeURL;
    self.linkField.returnKeyType = UIReturnKeyDone;

    self.tableView = [[UITableView alloc] initWithFrame:self.view.bounds style:UITableViewStyleInsetGrouped];
    self.tableView.delegate = self;
    self.tableView.dataSource = self;
    self.tableView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    self.tableView.keyboardDismissMode = UIScrollViewKeyboardDismissModeInteractive;
    [self.tableView registerClass:[UITableViewCell class] forCellReuseIdentifier:@"DXPLinkActionFieldCell"];
    self.view = self.tableView;

    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithTitle:LOCALIZED(@"SAVE")
                                                                              style:UIBarButtonItemStyleDone
                                                                             target:self
                                                                             action:@selector(saveTapped)];
}

@end
