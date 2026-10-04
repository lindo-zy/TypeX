# 桌面状态栏无操作、无反馈：4.2.8 后续修复

问题：用户最新反馈为 iOS 16 桌面状态栏左／中／右均不执行操作、没有震动；App 和其他位置正常。本次按刚交付的 4.2.8 继续定位，未连接或操作设备。

起始状态：集成分支 `dev`，HEAD `70acde4`，保留未跟踪的 `.zcodeignore`（SHA-256 `b21f2106b6adbc1a8e976ee95177e12b8e3e72f348b21cabb6d72f35d9fa0ff2`）。在独立 `codex/statusbar-home-screen` 工作树修改，合入后只用 `./build.sh` 编译。

## 根因及证据边界

源码中的震动在成功识别回调内、请求动作前执行。没有震动且没有操作，说明尚未进入该成功路径；不能仅据此断言具体哪个门失败。

4.2.8 只在状态栏渲染视图所在窗口安装识别器，并要求 `touch.window` 匹配该窗口；没有 `SBHomeScreenWindow` 入口。若桌面状态栏显示在独立窗口而触摸落到桌面窗口，旧代码没有处理这次触摸的识别器。旧测试一直把显示窗口与触摸窗口当成同一个窗口，因此遗漏了这种结构。

新增替身测试明确分离这两个窗口，旧生产安装代码在 `desktop touch window owns a status-bar gesture set` 断言失败。源码及替身已确认入口覆盖缺口；用户设备是否正好使用这条触摸路径、是否另有拒绝门，仍需真实 syslog 确认。

窗口结构参考：[SBHomeScreenWindow](https://github.com/MTACS/iOS-17-Runtime-Headers/blob/main/PrivateFrameworks/SpringBoard.framework/SBHomeScreenWindow.h)、[SBStatusBarWindow](https://github.com/MTACS/iOS-17-Runtime-Headers/blob/main/PrivateFrameworks/SpringBoard.framework/SBStatusBarWindow.h)。这些 iOS 17 转储只支持独立窗口类的结构判断，不证明 iOS 16 的实际 hitTest、key-window 角色或触摸穿透行为。

## 实现及修改边界

- 在 SpringBoard 中经过运行时类／继承检查后，为 `SBHomeScreenWindow` 安装一套窗口所有的状态栏识别器；已有桌面控制器出现回调、窗口可见／成为 key、启动与 Scene 扫描均能补装。安装时初始化弱 handler 注册表，异步启动不覆盖较早生命周期安装的条目。重复进入桌面不会增加识别器数量。
- 每次触摸从现有普通状态栏 handler 中选取同一屏幕、可见且与桌面相交的实际状态栏，按其真实 bounds 判定三分区。显示窗口与触摸窗口分别校验，不使用默认顶端高度或透明覆盖窗口。
- 桌面出现／离开回调明确标记可用性；观察到生命周期后不要求桌面必须是 key window。首次出现回调之前仅允许 key 的桌面窗口。离开桌面清除会话，即使窗口仍为 key 也不能执行旧触摸。
- 会话弱引用触摸视图和状态栏显示实例；触摸视图脱离、状态栏替换／隐藏、配置变化或 Scene 失活取消旧会话。桌面原生单击仲裁使用真实触摸视图的祖先链；系统纵向 pan 不获得点击失败优先级。
- 同窗口已有正常状态栏 handler 时，桌面备用路径不接收触摸，避免双发。图标、UIControl、灵动岛原生控件、状态栏之外的区域和未配置槽位不进入该路径；锁屏、面板、横屏和配置保护沿用。

涉及文件：`DXStatusBarGestureHooks.xm`、`DXStatusBarGestures.h`、`TypeX.xm` 的两处现有桌面生命周期回调、状态栏处理器测试／UIKit 替身与本记录。

不修改的部分：绑定格式、设置持久化、跨进程协议、动作／面板执行器、Dock、键盘和其他插件。UI 工作仍在主线程，诊断只写 syslog，不写设备日志文件。

## 本地验证

- `python3 tests/run-statusbar-gestures.py`：配置／区域／动作 174 项，生产处理器 550 项，生产转发／发送 22 项通过。
- 新增独立显示／触摸窗口下三分区五手势各执行一次、非 key 桌面可用、离开桌面取消、显示实例替换、触摸视图脱离、同窗口去重、图标／控件／未配置区域排除、锁屏／面板／Scene／其他屏幕拒绝、桌面原生 tap 仲裁及系统 pan 保护检查。
- 关联回归退出 0：状态栏设置 1556 项；Dock 策略／处理器 50／61 项；全局面板策略／触摸 79／22 项；通用手势／键盘几何／工具栏识别器 141／12／25 项。

平台替身不运行真实 UIKit 仲裁或 SpringBoard 注入。坐标转换替身也不能验证物理设备多窗口坐标、旋转和切口；这些仍属于设备验收。

## 设备验收（待执行）

1. 安装对应包并注销，先留在桌面测试已绑定的左／中／右操作，不能先打开设置。若配置开启震动，应在成功识别时有反馈，并且操作只执行一次。
2. 依次验证三个区域的单击、双击、长按、左滑、右滑；同时开启同区单击／双击时不能双发。桌面→App→桌面反复切换后继续有效；App 内现有手势保持正常。
3. 冷启动／重新越狱与热返回分别测试；锁屏、面板显示、桌面离开途中、状态栏隐藏、配置清空或禁用时不能误触发。桌面图标操作和通知中心／控制中心下拉保持正常。

预期 syslog：

```text
[TypeX][StatusBarGesture] installed host=SpringBoard view=SBHomeScreenWindow window=SBHomeScreenWindow
[TypeX][StatusBarGesture] desktop visible=1 window=SBHomeScreenWindow
[TypeX][StatusBarGesture] touch host=SpringBoard slot=... view=... receiver=... window=... display=...
[TypeX][StatusBarGesture] trigger host=SpringBoard slot=...
[TypeX][StatusBarGesture] dispatch slot=...
[TypeX][StatusBarGesture] result host=SpringBoard slot=... status=...
```

`home-inactive-window` 表示桌面未出现或已离开；`home-statusbar` 表示未找到可见实际状态栏，或已有同窗口正常入口；`home-icon` 是图标排除。其他失败继续按 `rejected ... gate=...` 和上述日志停在哪一步定位，不能凭无反馈再次改配置格式。

## 交付状态

源码分析：已确认独立桌面触摸窗口入口遗漏；设备完整运行时根因未确认。编译／包结构：待集成构建核对。核心功能、设备安装／卸载、冷／热启动：未验证。

已知限制：若实际设备触摸落到其他 SpringBoard 窗口，或真实状态栏类不在现有扫描范围，需要其 syslog 才能补齐确切入口；本轮不猜测额外窗口，也不扩大触摸区域。
