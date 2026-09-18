#import <UIKit/UIKit.h>

// TypeX 自带 AI 问答面板（键盘工具栏 AI 按钮入口）。两种承载：
// 1) 系统键盘（宿主 app / SpringBoard 进程，工具栏长在 UIKeyboardImpl 上）：
//    openFromKeyboardWithSeedText: 进程内独立 UIWindow（level 1e6），锚定键盘
//    上方，ShellX 同款——打开不抢宿主输入焦点（卡片 hitTest 之外触摸全部穿透），
//    点面板输入框才接管 key；X 关闭即销毁会话。
// 2) 第三方键盘扩展（进程内窗口逃不出键盘宿主区域）：工具栏写 cfprefsd+Darwin
//    通道，TypeX.xm 的 SB 端回调解析并桌面门控后调 presentInSpringBoard...，
//    SB 内 plain-init UIWindow（makeKeyAndVisible）承载。
@interface DXAIPanel : NSObject
+ (void)openFromKeyboardWithSeedText:(NSString *)seedText;
+ (void)presentInSpringBoardWithSeedText:(NSString *)seedText clipboardImage:(BOOL)clipboardImage;
@end
