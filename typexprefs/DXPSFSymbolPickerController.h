#import <Preferences/PSViewController.h>

// SF Symbols 浏览选择器：仅解析本机系统资源目录，过滤本机可渲染的条目，
// 支持按名称搜索。选中回传 SF Symbol 名（写入动作的 icon 字段即生效）。
@interface DXPSFSymbolPickerController : PSViewController
@property (nonatomic, copy) NSString *selectedSymbolName;
@property (nonatomic, copy) void (^completion)(NSString *symbolName);
@end
