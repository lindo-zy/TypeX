#import "DXPSFSymbolPickerController.h"
#import "DXPSFSymbolCatalog.h"
#import "../common.h"

static NSBundle *tweakBundle;
// Successful catalogs only, confined to the main thread; failed loads retry.
static NSArray<DXPSFSymbolCategory *> *DXPAvailableSymbolCategories;

static NSString *DXPSymbolCategoryTitle(DXPSFSymbolCategory *category) {
    NSString *key = [@"SF_SYMBOL_CATEGORY_" stringByAppendingString:category.identifier];
    return [tweakBundle localizedStringForKey:key value:(category.title ?: category.identifier.capitalizedString) table:nil];
}

@interface DXPSFSymbolPickerController () <UITableViewDataSource, UITableViewDelegate, UISearchBarDelegate>
@property (nonatomic, strong) UITableView *table;
@property (nonatomic, strong) UISearchBar *searchBar;
@property (nonatomic, copy) NSArray<DXPSFSymbolCategory *> *categories;
// A category child shares the library's selection callback and closes both
// levels when selected. Cancelling the child returns to the category list.
@property (nonatomic, strong) DXPSFSymbolCategory *category;
@property (nonatomic, weak) DXPSFSymbolPickerController *libraryController;
// Search always starts from the complete, validated local catalog.
@property (nonatomic, copy) NSArray<NSString *> *allSymbols;
@property (nonatomic, copy) NSArray<NSString *> *symbols;
@property (nonatomic, assign) NSUInteger loadGeneration;
@property (nonatomic, assign) BOOL loading;
@property (nonatomic, assign) BOOL selectionFinished;
@property (nonatomic, assign) BOOL pushingCategory;
@property (nonatomic, assign) NSTimeInterval loadStarted;
@end

@implementation DXPSFSymbolPickerController

- (void)viewDidLoad {
    [super viewDidLoad];
    tweakBundle = [NSBundle bundleWithPath:bundlePath];
    [tweakBundle load];
    self.title = self.category ? DXPSymbolCategoryTitle(self.category) : LOCALIZED(@"SF_SYMBOL_PICKER_TITLE");
    self.categories = self.category ? @[] : (DXPAvailableSymbolCategories ?: @[]);
    self.allSymbols = self.category ? self.category.symbolNames : (self.categories.firstObject.symbolNames ?: @[]);
    self.symbols = self.allSymbols;
    self.table = [[UITableView alloc] initWithFrame:self.view.bounds style:UITableViewStylePlain];
    self.table.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    self.table.dataSource = self;
    self.table.delegate = self;
    if (self.category) {
        self.searchBar = [[UISearchBar alloc] initWithFrame:CGRectMake(0, 0, self.view.bounds.size.width, 44)];
        self.searchBar.autoresizingMask = UIViewAutoresizingFlexibleWidth;
        self.searchBar.placeholder = LOCALIZED(@"SF_SYMBOL_SEARCH");
        self.searchBar.delegate = self;
        self.searchBar.autocorrectionType = UITextAutocorrectionTypeNo;
        self.searchBar.autocapitalizationType = UITextAutocapitalizationTypeNone;
        self.table.tableHeaderView = self.searchBar;
    } else {
        self.table.rowHeight = 56;
    }
    self.view = self.table;
    [self refreshBackground];
    NSLog(@"[TypeX][SFSymbol] picker open category=%@ rows=%lu", self.category.identifier ?: @"library",
          (unsigned long)(self.category ? self.symbols.count : self.categories.count));
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    self.selectionFinished = NO;
    self.pushingCategory = NO;
    if (!self.category && !self.categories.count && !self.loading) [self loadSymbolCatalog];
    else [self refreshBackground];
}

- (void)viewWillDisappear:(BOOL)animated {
    [super viewWillDisappear:animated];
    [self.searchBar resignFirstResponder];
    self.loadGeneration++;
    self.loading = NO;
}

- (void)loadSymbolCatalog {
    if (self.category || self.loading) return;
    self.loading = YES;
    self.loadStarted = [NSDate timeIntervalSinceReferenceDate];
    NSUInteger generation = ++self.loadGeneration;
    self.navigationItem.rightBarButtonItem.enabled = NO;
    [self.table reloadData];
    [self refreshBackground];
    __weak typeof(self) weakSelf = self;
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        @autoreleasepool {
            NSArray<NSString *> *sources = nil;
            NSArray<NSString *> *candidates = [DXPSFSymbolCatalog
                namesFromResourceDirectories:[DXPSFSymbolCatalog systemResourceDirectories] sourcePaths:&sources];
            dispatch_async(dispatch_get_main_queue(), ^{
                typeof(weakSelf) owner = weakSelf;
                if (!owner || !owner.loading || generation != owner.loadGeneration) return;
                NSLog(@"[TypeX][SFSymbol] catalog sources=%@ candidates=%lu", sources,
                      (unsigned long)candidates.count);
                [owner validateCandidates:candidates offset:0 available:[NSMutableArray array] generation:generation];
            });
        }
    });
}

- (void)validateCandidates:(NSArray<NSString *> *)candidates offset:(NSUInteger)offset
                 available:(NSMutableArray<NSString *> *)available generation:(NSUInteger)generation {
    if (!self.loading || generation != self.loadGeneration) return;
    // Yield between batches so catalog validation does not block navigation.
    NSTimeInterval started = [NSDate timeIntervalSinceReferenceDate];
    NSUInteger limit = MIN(offset + 32, candidates.count);
    while (offset < limit) {
        @autoreleasepool {
            NSString *name = candidates[offset++];
            if ([UIImage systemImageNamed:name]) [available addObject:name];
        }
        if ([NSDate timeIntervalSinceReferenceDate] - started >= 0.004) break;
    }
    if (offset == candidates.count) {
        self.allSymbols = available;
        NSArray<NSString *> *validNames = self.allSymbols;
        __weak typeof(self) weakSelf = self;
        dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
            @autoreleasepool {
                NSArray<NSString *> *sources = nil;
                NSArray<DXPSFSymbolCategory *> *categories = [DXPSFSymbolCatalog
                    categoriesFromResourceDirectories:[DXPSFSymbolCatalog systemResourceDirectories]
                    availableNames:validNames sourcePaths:&sources];
                dispatch_async(dispatch_get_main_queue(), ^{
                    typeof(weakSelf) owner = weakSelf;
                    if (!owner || !owner.loading || generation != owner.loadGeneration) return;
                    owner.loading = NO;
                    owner.categories = categories;
                    // An All-only result stays usable but must not cache a
                    // failed category read for the lifetime of Preferences.
                    DXPAvailableSymbolCategories = categories.count > 1 ? categories : nil;
                    [owner.table reloadData];
                    [owner refreshBackground];
                    NSLog(@"[TypeX][SFSymbol] catalog ready available=%lu candidates=%lu categories=%lu sources=%@ elapsed=%.3f",
                          (unsigned long)validNames.count, (unsigned long)candidates.count,
                          (unsigned long)categories.count, sources,
                          [NSDate timeIntervalSinceReferenceDate] - owner.loadStarted);
                });
            }
        });
        return;
    }
    __weak typeof(self) weakSelf = self;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, NSEC_PER_MSEC), dispatch_get_main_queue(), ^{
        [weakSelf validateCandidates:candidates offset:offset available:available generation:generation];
    });
}

- (void)refreshBackground {
    if (!self.category) {
        self.navigationItem.rightBarButtonItem = (!self.loading && self.allSymbols.count && self.categories.count == 1)
            ? [[UIBarButtonItem alloc] initWithTitle:LOCALIZED(@"SF_SYMBOL_RETRY") style:UIBarButtonItemStylePlain
                target:self action:@selector(loadSymbolCatalog)] : nil;
    }
    if (self.category ? self.symbols.count : self.categories.count) {
        self.table.backgroundView = nil;
        return;
    }
    UIView *background = [[UIView alloc] initWithFrame:self.table.bounds];
    UIStackView *stack = [[UIStackView alloc] init];
    stack.axis = UILayoutConstraintAxisVertical;
    stack.alignment = UIStackViewAlignmentCenter;
    stack.spacing = 12;
    stack.translatesAutoresizingMaskIntoConstraints = NO;
    [background addSubview:stack];
    [NSLayoutConstraint activateConstraints:@[
        [stack.centerXAnchor constraintEqualToAnchor:background.centerXAnchor],
        [stack.centerYAnchor constraintEqualToAnchor:background.centerYAnchor],
        [stack.widthAnchor constraintLessThanOrEqualToAnchor:background.widthAnchor constant:-40],
    ]];
    if (self.loading) {
        UIActivityIndicatorView *spinner = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleMedium];
        [spinner startAnimating];
        [stack addArrangedSubview:spinner];
    }
    UILabel *message = [[UILabel alloc] init];
    message.font = [UIFont systemFontOfSize:15];
    message.textColor = UIColor.secondaryLabelColor;
    message.textAlignment = NSTextAlignmentCenter;
    message.numberOfLines = 0;
    message.text = self.loading ? LOCALIZED(@"SF_SYMBOL_LOADING") :
        (self.category ? LOCALIZED(@"SF_SYMBOL_NO_RESULTS") : LOCALIZED(@"SF_SYMBOL_LOAD_FAILED"));
    [stack addArrangedSubview:message];
    if (!self.category && !self.loading && !self.allSymbols.count) {
        UIButton *retry = [UIButton buttonWithType:UIButtonTypeSystem];
        [retry setTitle:LOCALIZED(@"SF_SYMBOL_RETRY") forState:UIControlStateNormal];
        [retry addTarget:self action:@selector(loadSymbolCatalog) forControlEvents:UIControlEventTouchUpInside];
        [stack addArrangedSubview:retry];
    }
    self.table.backgroundView = background;
}

- (void)filterWithQuery:(NSString *)query {
    query = [query stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    self.symbols = query.length
        ? [self.allSymbols filteredArrayUsingPredicate:
              [NSPredicate predicateWithFormat:@"self CONTAINS[cd] %@", query]]
        : self.allSymbols;
    [self.table reloadData];
    [self refreshBackground];
}

- (void)searchBar:(UISearchBar *)searchBar textDidChange:(NSString *)searchText {
    [self filterWithQuery:searchText ?: @""];
}

- (void)searchBarSearchButtonClicked:(UISearchBar *)searchBar {
    [searchBar resignFirstResponder];
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    (void)tableView; (void)section;
    return self.category ? self.symbols.count : self.categories.count;
}

- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section {
    (void)tableView; (void)section;
    return (!self.category && !self.loading && self.categories.count == 1)
        ? LOCALIZED(@"SF_SYMBOL_CATEGORIES_UNAVAILABLE") : nil;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    if (!self.category) {
        UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"DXPSFSymbolCategoryCell"];
        if (!cell) cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleValue1 reuseIdentifier:@"DXPSFSymbolCategoryCell"];
        DXPSFSymbolCategory *category = self.categories[indexPath.row];
        cell.textLabel.text = DXPSymbolCategoryTitle(category);
        cell.textLabel.font = [UIFont systemFontOfSize:17];
        cell.textLabel.textColor = UIColor.labelColor;
        cell.detailTextLabel.text = @(category.symbolNames.count).stringValue;
        cell.detailTextLabel.textColor = UIColor.secondaryLabelColor;
        cell.imageView.image = category.iconName.length ? [UIImage systemImageNamed:category.iconName
            withConfiguration:[UIImageSymbolConfiguration configurationWithPointSize:23 weight:UIImageSymbolWeightRegular]] : nil;
        cell.imageView.tintColor = UIColor.labelColor;
        cell.imageView.contentMode = UIViewContentModeScaleAspectFit;
        cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
        return cell;
    }
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"DXPSFSymbolCell"];
    if (!cell) cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleValue1 reuseIdentifier:@"DXPSFSymbolCell"];
    NSString *name = self.symbols[indexPath.row];
    cell.textLabel.text = name;
    cell.textLabel.font = [UIFont monospacedSystemFontOfSize:13 weight:UIFontWeightRegular];
    cell.detailTextLabel.text = nil;
    cell.imageView.image = [UIImage systemImageNamed:name];
    cell.accessoryType = [name isEqualToString:self.selectedSymbolName]
        ? UITableViewCellAccessoryCheckmark : UITableViewCellAccessoryNone;
    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    if (!self.category) {
        if (indexPath.row < 0 || indexPath.row >= (NSInteger)self.categories.count) return;
        if (self.pushingCategory) return;
        self.pushingCategory = YES;
        DXPSFSymbolPickerController *picker = [[DXPSFSymbolPickerController alloc] init];
        picker.category = self.categories[indexPath.row];
        picker.libraryController = self;
        picker.selectedSymbolName = self.selectedSymbolName;
        picker.completion = self.completion;
        [picker setRootController:[self rootController]];
        [picker setParentController:[self parentController]];
        [self pushController:picker];
        return;
    }
    if (indexPath.row < 0 || indexPath.row >= (NSInteger)self.symbols.count) return;
    DXPSFSymbolPickerController *library = self.libraryController;
    if (!library || self.selectionFinished || library.selectionFinished) return;
    NSString *name = self.symbols[indexPath.row];
    // Cached names can outlive an external symbol hook's configuration.
    if (![UIImage systemImageNamed:name]) {
        DXPAvailableSymbolCategories = nil;
        library.categories = @[];
        library.allSymbols = @[];
        NSMutableArray *remaining = [self.allSymbols mutableCopy];
        [remaining removeObject:name];
        self.allSymbols = remaining;
        [self filterWithQuery:self.searchBar.text ?: @""];
        NSLog(@"[TypeX][SFSymbol] selection unavailable name=%@", name);
        UIAlertController *alert = [UIAlertController alertControllerWithTitle:self.title
            message:LOCALIZED(@"SF_SYMBOL_UNAVAILABLE") preferredStyle:UIAlertControllerStyleAlert];
        [alert addAction:[UIAlertAction actionWithTitle:LOCALIZED(@"ANSWER_OK")
            style:UIAlertActionStyleCancel handler:nil]];
        [self presentViewController:alert animated:YES completion:nil];
        return;
    }
    self.selectionFinished = YES;
    library.selectionFinished = YES;
    library.selectedSymbolName = name;
    UINavigationController *navigation = self.navigationController;
    NSArray<UIViewController *> *controllers = navigation.viewControllers;
    NSUInteger libraryIndex = [controllers indexOfObjectIdenticalTo:library];
    UIViewController *returnController = (libraryIndex != NSNotFound && libraryIndex > 0) ? controllers[libraryIndex - 1] : nil;
    NSLog(@"[TypeX][SFSymbol] picked name=%@ completion=%d", name, self.completion != nil);
    if (self.completion) self.completion(name);
    if (returnController && [navigation.viewControllers containsObject:returnController]) {
        [navigation popToViewController:returnController animated:YES];
    } else {
        NSLog(@"[TypeX][SFSymbol] return controller unavailable");
        [navigation popViewControllerAnimated:YES];
    }
}

@end
