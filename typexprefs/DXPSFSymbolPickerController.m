#import "DXPSFSymbolPickerController.h"
#import "../common.h"

static NSBundle *tweakBundle;

// 无公开接口枚举 SF Symbols，内置一份跨 iOS 13–17 稳定存在的常用符号名
// 目录；viewDidLoad 用 systemImageNamed 过滤出本机实际可渲染的子集。
static NSArray<NSString *> *DXSFSymbolCatalog(void) {
    static NSArray *catalog;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        NSArray<NSString *> *names = @[
            // 文档与剪贴板
            @"doc", @"doc.fill", @"doc.text", @"doc.on.doc", @"doc.on.clipboard", @"doc.badge.plus",
            @"clipboard", @"note.text", @"square.and.pencil", @"pencil", @"pencil.circle", @"highlighter",
            @"eraser", @"square.and.arrow.up", @"square.and.arrow.up.fill", @"square.and.arrow.down",
            @"square.and.arrow.down.fill", @"tray", @"tray.fill", @"archivebox", @"paperclip",
            // 链接与分享
            @"link", @"link.circle", @"bookmark", @"bookmark.fill", @"flag", @"flag.fill", @"tag", @"tag.fill",
            @"paperplane", @"paperplane.fill", @"envelope", @"envelope.fill", @"message", @"message.fill",
            @"bubble.left", @"bubble.right", @"phone", @"phone.fill", @"phone.arrow.up.right",
            // 删除与编辑操作
            @"delete.left", @"delete.left.fill", @"delete.right", @"delete.right.fill", @"clear", @"trash",
            @"trash.fill", @"plus", @"plus.circle", @"plus.circle.fill", @"minus", @"minus.circle",
            @"minus.circle.fill", @"xmark", @"xmark.circle", @"xmark.circle.fill", @"checkmark",
            @"checkmark.circle", @"checkmark.circle.fill", @"arrow.uturn.left", @"arrow.uturn.right",
            @"arrow.uturn.left.circle", @"arrow.uturn.right.circle", @"arrow.counterclockwise",
            @"arrow.clockwise", @"arrow.counterclockwise.circle", @"arrow.clockwise.circle",
            // 方向与移动
            @"arrow.left", @"arrow.right", @"arrow.up", @"arrow.down", @"arrow.left.circle", @"arrow.right.circle",
            @"arrow.up.circle", @"arrow.down.circle", @"arrow.up.arrow.down", @"arrow.left.arrow.right",
            @"arrow.2.squarepath", @"arrow.triangle.2.circlepath", @"arrow.left.to.line", @"arrow.right.to.line",
            @"arrow.up.to.line", @"arrow.down.to.line", @"arrowtriangle.left", @"arrowtriangle.right",
            @"arrowtriangle.up", @"arrowtriangle.down", @"arrowtriangle.left.fill", @"arrowtriangle.right.fill",
            @"arrowtriangle.up.fill", @"arrowtriangle.down.fill", @"chevron.left", @"chevron.right",
            @"chevron.up", @"chevron.down", @"chevron.left.circle", @"chevron.right.circle",
            @"arrow.up.left", @"arrow.up.right", @"arrow.down.left", @"arrow.down.right",
            // 文本排版
            @"text.cursor", @"text.insert", @"text.append", @"text.justify", @"text.alignleft",
            @"text.aligncenter", @"text.alignright", @"bold", @"italic", @"underline", @"strikethrough",
            @"list.bullet", @"list.number", @"list.dash", @"paragraph", @"increase.quotelevel",
            @"decrease.quotelevel", @"textformat", @"textformat.alt", @"textformat.size", @"textformat.abc",
            @"abc",
            // 键盘与输入
            @"keyboard", @"keyboard.chevron.compact", @"keyboard.chevron.compact.down", @"command", @"option",
            @"capslock", @"globe", @"globe.asia.australia", @"globe.desk",
            // 媒体
            @"play", @"play.fill", @"pause", @"pause.fill", @"stop.fill", @"play.circle", @"play.circle.fill",
            @"forward.fill", @"backward.fill", @"forward.end.fill", @"backward.end.fill", @"music.note",
            @"music.note.list", @"waveform", @"headphones", @"hifispeaker", @"tv", @"video", @"video.fill",
            @"mic", @"mic.fill", @"mic.slash", @"speaker.wave.1", @"speaker.wave.2", @"speaker.wave.3",
            @"speaker.slash", @"camera", @"camera.fill", @"camera.viewfinder", @"photo", @"photos",
            // 系统、设备与开关
            @"gear", @"gearshape", @"gearshape.fill", @"gearshape.2", @"slider.horizontal.3", @"switch.2",
            @"power", @"bolt", @"bolt.fill", @"bolt.slash", @"antenna.radiowaves.left.and.right", @"wifi",
            @"wifi.slash", @"airplane", @"cellularbars", @"personalhotspot", @"bluetooth", @"battery.100",
            @"battery.100.bolt", @"lock", @"lock.fill", @"lock.open", @"lock.open.fill", @"lock.rotation",
            @"shield", @"shield.fill", @"moon", @"moon.fill", @"moon.zzz", @"sun.max", @"sun.max.fill",
            @"sun.min", @"sun.min.fill", @"flashlight.on.fill", @"flashlight.off.fill",
            @"circle.lefthalf.filled", @"brightness", @"hand.raised", @"hand.raised.fill", @"eye", @"eye.fill",
            @"eye.slash",
            // 位置、时间与日常
            @"house", @"house.fill", @"building.2", @"map", @"map.fill", @"mappin", @"mappin.and.ellipse",
            @"location", @"location.fill", @"location.slash", @"clock", @"clock.fill", @"calendar", @"alarm",
            @"timer", @"hourglass", @"stopwatch", @"bell", @"bell.fill", @"bell.slash", @"bell.slash.fill",
            @"star", @"star.fill", @"heart", @"heart.fill", @"thumbup", @"thumbup.fill", @"thumbdown",
            @"face.smiling", @"person", @"person.fill", @"person.2", @"person.crop.circle", @"wand.and.rays",
            @"wand.and.stars", @"sparkles", @"qrcode", @"barcode", @"viewfinder", @"faceid", @"touchid",
            @"scope", @"safari", @"app", @"app.fill", @"app.gift", @"square", @"square.fill", @"circle",
            @"circle.fill", @"square.grid.2x2", @"square.grid.3x3", @"circle.grid.2x2", @"circle.grid.3x3",
            @"rectangle.grid.1x2", @"rectangle.grid.2x2", @"rectangle.grid.3x2", @"square.stack",
            @"rectangle.on.rectangle", @"folder", @"folder.fill", @"folder.badge.plus", @"internaldrive",
            @"externaldrive",
        ];
        catalog = names;
    });
    return catalog;
}

@interface DXPSFSymbolPickerController () <UITableViewDataSource, UITableViewDelegate, UISearchBarDelegate>
@property (nonatomic, strong) UITableView *table;
@property (nonatomic, strong) UISearchBar *searchBar;
// 全量可用符号只算一次；symbols 始终由 allSymbols 过滤而来，退格才能恢复。
@property (nonatomic, copy) NSArray<NSString *> *allSymbols;
@property (nonatomic, copy) NSArray<NSString *> *symbols;
@end

@implementation DXPSFSymbolPickerController

- (void)viewDidLoad {
    [super viewDidLoad];
    tweakBundle = [NSBundle bundleWithPath:bundlePath];
    [tweakBundle load];
    self.title = LOCALIZED(@"SF_SYMBOL_PICKER_TITLE");
    NSMutableArray<NSString *> *available = [NSMutableArray array];
    for (NSString *name in DXSFSymbolCatalog()) {
        if ([UIImage systemImageNamed:name]) [available addObject:name];
    }
    self.allSymbols = available;
    self.symbols = available;
    self.table = [[UITableView alloc] initWithFrame:self.view.bounds style:UITableViewStylePlain];
    self.table.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    self.table.dataSource = self;
    self.table.delegate = self;
    self.searchBar = [[UISearchBar alloc] initWithFrame:CGRectMake(0, 0, self.view.bounds.size.width, 44)];
    self.searchBar.autoresizingMask = UIViewAutoresizingFlexibleWidth;
    self.searchBar.placeholder = LOCALIZED(@"SF_SYMBOL_SEARCH");
    self.searchBar.delegate = self;
    self.table.tableHeaderView = self.searchBar;
    self.view = self.table;
    NSLog(@"[TypeX][SFSymbol] picker open rows=%lu catalog=%lu", (unsigned long)self.symbols.count, (unsigned long)DXSFSymbolCatalog().count);
}

- (void)viewWillDisappear:(BOOL)animated {
    [super viewWillDisappear:animated];
    [self.searchBar resignFirstResponder];
}

- (void)filterWithQuery:(NSString *)query {
    query = [query stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    self.symbols = query.length
        ? [self.allSymbols filteredArrayUsingPredicate:
              [NSPredicate predicateWithFormat:@"self CONTAINS[cd] %@", query]]
        : self.allSymbols;
    [self.table reloadData];
}

- (void)searchBar:(UISearchBar *)searchBar textDidChange:(NSString *)searchText {
    [self filterWithQuery:searchText ?: @""];
}

- (void)searchBarSearchButtonClicked:(UISearchBar *)searchBar {
    [searchBar resignFirstResponder];
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    (void)tableView; (void)section;
    return self.symbols.count;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
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
    if (indexPath.row < 0 || indexPath.row >= (NSInteger)self.symbols.count) return;
    NSString *name = self.symbols[indexPath.row];
    NSLog(@"[TypeX][SFSymbol] picked name=%@ completion=%d", name, self.completion != nil);
    if (self.completion) self.completion(name);
    [self.navigationController popViewControllerAnimated:YES];
}

@end
