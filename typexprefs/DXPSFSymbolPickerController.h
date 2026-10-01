#import <Preferences/PSViewController.h>

// SF Symbols 浏览选择器：内置常用符号名目录，运行时过滤本机可用的条目，
// 支持按名称搜索。选中回传 SF Symbol 名（写入动作的 icon 字段即生效）。
@interface DXPSFSymbolPickerController : PSViewController
@property (nonatomic, copy) NSString *selectedSymbolName;
@property (nonatomic, copy) void (^completion)(NSString *symbolName);
@end
