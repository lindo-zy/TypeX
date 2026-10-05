# 状态栏核心视图构造与挂载修复

问题：4.3.2 桌面状态栏所有手势不生效，Dock 正常且明确要求不修改。

起始状态：TypeX 的集成分支 `dev`，HEAD `a209f9b`，用户已有未跟踪 `.zcodeignore`。隔离分支 `codex/statusbar-core-lifecycle` 从该基线开发。

## 分析及证据边界

已确认的源码问题：旧入口必须等 `anchor.window` 非空才安装识别器；发现内层核心视图时，会沿父链选中外层 Wrapper，并主动删除核心视图原有的识别器。因此它没有实现 squid 的“构造完成立即把手势装到核心视图”路径。外层包装容器的几何也会被当作手势区域的依据。

本地参考 `/Users/xiao/Downloads/squid/main.arm64` 和 `main_disasm.txt`：

- `0x448e0–0x449f4` 将 `0xd470a` 的 13 字节解密到 `0xd4717`，得到 `_UIStatusBar\0`。第 4 字节按 OR/ORN/AND/NOT 指令求值得到 `t`；不是凭类名长度猜测。
- `0x4d9bc` 的 objc_getClass 使用该结果；`0x4d9ec–0x4da04` 安装 `initWithStyle:` hook，入口为 `0x629a4`。
- `0x630d8` 调用原构造函数；`0x63120–0x63440` 直接给该核心视图 addGestureRecognizer，不等待 window，也不迁到 Wrapper。
- `statusBarGesture:` 的 hook（`0x62988`）仍转调原实现，不能据此推断 squid 全面禁用了系统动作。

签名交叉核对：[_UIStatusBar 的 RuntimeBrowser 导出](https://raw.githubusercontent.com/nst/iOS-Runtime-Headers/master/PrivateFrameworks/UIKitCore.framework/_UIStatusBar.h) 与 [iOS 17 STUIStatusBar 导出](https://raw.githubusercontent.com/MTACS/iOS-17-Runtime-Headers/main/PrivateFrameworks/SystemStatusUI.framework/STUIStatusBar.h) 均声明 `initWithStyle:(long long)`，返回对象。导出头文件不是目标设备运行时证明，注册仍逐次检查实际方法 ABI。

本次尝试读取 USB 日志时仅收到连接标记，没有 TypeX 触发记录；收到用户“不能链接设备”后已停止所有设备抓取，未安装包、未注销、未操作设备界面。不能确认实际桌面触摸命中链，因此不将“核心与 Wrapper 差异”描述成已实测的唯一故障根因。此前报告的“架构必然导致第一次后失效”“天然免疫”等说法不能作为本轮运行时证据。

## 修改边界与实现

涉及文件：`DXStatusBarGestureHooks.xm`、状态栏处理器测试、状态栏 UIKit 替身头、本记录；构建后另由脚本自动更新 `control`。

1. `_UIStatusBar` / `STUIStatusBar` 增加独立构造 hook，仅在 UIView 子类、返回对象、单个 signed 64-bit style 参数完全匹配时注册。缺类、缺方法、ABI 不符跳过；后续窗口/Scene 通知继续重试。
2. 核心视图自身持有四个识别器，覆盖单击、双击、长按、左右滑五种手势。允许尚无窗口时安装，触摸时仍执行窗口、可见性、锁屏、面板、偏好、Scene 和方向门控。
3. Wrapper 仅在没有核心视图时作为兼容入口；核心进入父链后退役该 Wrapper 的识别器、委托与旧会话，防止双发。核心更换窗口或实例后旧会话不得执行。
4. 主线程调用启动入口时立即注册，减少首次构造之前的异步空隙；非主线程启动仍转到主队列。
5. 保留现有 `construction hook` / `installed` / `touch` / `rejected` / `trigger` / `result` syslog，不写设备日志文件。

不修改：Dock 源码及测试实现、TypeX.xm、配置格式、设置入口、动作执行器、跨进程协议、键盘、其他插件；灵动岛仍保留原窗口级安装规则。

运行时风险：私有核心类/构造方法若在目标系统中不同，会退回现有生命周期扫描；UIKit 的真实命中测试、系统手势仲裁和第三方状态栏美化插件仍需设备验证。

## 本地验证

- 状态栏配置/区域/动作：174 项通过。
- 生产状态栏处理器（UIKit 替身）：795 项通过，包含构造时无窗口、核心优先、Wrapper 旧会话取消、跨窗口重挂、晚加载与错误 ABI、空 Wrapper 几何、每个槽位连续五轮面板开关后的单次执行。
- 生产状态栏 broker/sender（平台替身）：22 项通过。
- 状态栏设置：1556 项通过。
- Dock 处理器：61 项通过；Dock 策略测试通过。
- 全局面板策略/几何：79 项；Dock 触摸策略：22 项通过。
- 替身测试不执行 SpringBoard 注入或真实 UIKit hit-test，不是设备复现。

## 设备验收步骤（未执行）

1. iOS 16/17 安装对应包后注销，直接停留桌面，不先进入设置；分别验证已配置的左、中、右区五种手势。
2. 每个槽位连续触发至少五次；每次面板关闭后再次触发，应每次执行一次。App 返回桌面、锁屏解锁后复测。
3. 日志应先有核心类的 `construction hook`，后有 `installed ... view=_UIStatusBar/STUIStatusBar`；每次操作有 `touch → trigger → result`，拒绝时记录 `gate`。
4. 单击/双击不双发；纵向下拉通知中心、控制中心和未配置槽位保留系统行为。Dock 上划、左划、右划保持原状。
5. 冷启动、热启动、横屏开关、禁用/清空绑定、安装/卸载分别验证。

## 交付验证

待集成后执行 `./build.sh`、核验两套 DEB、由脚本自动推进版本，再本地提交、归档 iCloud、校验 SHA-256 并运行 `python3 webdav-sync.py TypeX`。设备核心功能、冷/热启动、安装/卸载均未验证。
