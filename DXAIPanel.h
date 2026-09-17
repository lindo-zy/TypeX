#import <UIKit/UIKit.h>

// TypeX 自带 AI 问答面板（键盘工具栏 AI 按钮入口）。
// 面板以独立 UIWindow 承载（level 1e6），锚定在当前键盘上方；打开时不抢宿主
// 输入焦点（键盘保持原样，卡片 hitTest 之外的触摸全部穿透回宿主），用户点
// 面板输入框时才接管 key 并把键盘切到面板输入。− 最小化保留会话（配置了悬浮
// 球时缩成悬浮球），X 关闭销毁会话并交还宿主焦点。
@interface DXAIPanel : NSObject
+ (void)openFromKeyboardWithSeedText:(NSString *)seedText;
@end
