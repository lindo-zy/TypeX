#import <Preferences/PSListController.h>
#import <Preferences/PSSpecifier.h>

// AI 问答设置主页（Root.plist 入口）：AI 引擎选择、引擎配置（API Key / 模型 /
// 抓取 / 获取网址）、AI 人设（人设编辑 / 悬浮球 / 窗口主题 / 流式输出）。
// 布局参照 ShellX 的 AI 问答设置页。
@interface DXPAIChatController : PSViewController <UITableViewDelegate, UITableViewDataSource>
@property (strong, nonatomic) UITableView *tableView;
@end

// 引擎选择：单选列表，选中写 aiEngine 并返回。
@interface DXPAIEnginePickerController : PSViewController <UITableViewDelegate, UITableViewDataSource>
@property (strong, nonatomic) UITableView *tableView;
@end

// 人设编辑：整页系统提示词文本编辑，消失时落盘。
@interface DXPAIPersonaController : PSViewController <UITextViewDelegate>
@property (strong, nonatomic) UITextView *textView;
@end

// 悬浮球设置：最小化出球开关 / 贴边半隐藏开关 / 重置位置。
@interface DXPAIBallController : PSViewController <UITableViewDelegate, UITableViewDataSource>
@property (strong, nonatomic) UITableView *tableView;
@end

// 窗口主题：跟随系统 / 浅色 / 深色。
@interface DXPAIThemeController : PSViewController <UITableViewDelegate, UITableViewDataSource>
@property (strong, nonatomic) UITableView *tableView;
@end
