# TypeX 悬浮打开应用

自定义动作的「打开应用」与「URL Scheme」默认启用「悬浮打开应用」。无需安装或启用 PullOver-X。工具栏、键盘面板、桌面手势和全局面板都使用 TypeX 自有 SpringBoard 托管入口。

小窗中可以操作目标应用，标题栏可拖动。标题栏右侧「-」最小化按钮收起小窗并把目标挂后台驻留（不强制终止进程），紧邻的关闭按钮解除托管并把目标退回正常后台状态。打开另一目标会关闭前一个小窗。卡片之外的区域不拦截主应用触摸。小窗的默认最大占屏比例在设置新增的「悬浮面板」页调整，对新打开的悬浮生效。

关闭「悬浮打开应用」开关可使用普通全屏打开。旧的 `pullover` 配置不参与新路由；未写入 `floating` 的动作默认启用 TypeX 悬浮，保存时移除旧键。原有「小把手」动作仍是独立的第三方唤醒动作。

URL Scheme 通过 LaunchServices 解析目标，向 FrontBoard 提交带原始 URL 的 suspended 请求。不对应可托管应用的系统命令需要使用普通打开。悬浮失败不补发全屏打开。当前主应用自身作为目标时返回 Busy，避免把正在操作的主应用搬进卡片。

## 实现与生命周期

- `DXSystemOpenBroker` 的 `floating-application` / `floating-url` 使用现有请求 ID、TTL 与单次回执。
- `DXFloatingAppSession` 管理代次、就绪截止时间、替换请求与单次完成。
- `DXFloatingAppRuntime` 仅在 SpringBoard 初始化。默认 Scene 图层由系统 host view 绘制，主内容、键盘、external Scene 分开接入后按原画布缩放，自动适配比例由 `floatingcardmaxscale`（悬浮面板设置页，30–100%）封顶。
- 当前 target/base Scene 的 settings 更新受会话限定的前台保护。可见目标持有 RBS 运行断言。最小化、关闭、目标进程/Scene 结束、锁屏、原生前台切换都会释放断言、图层 KVO、host requester 和窗口；最小化在释放后追加一次挂起停靠（`launchApplicationWithIdentifier:suspended:YES`），保证目标驻留后台。
- 内容与 URL 接收回执都就绪后才能返回成功；截止时间使用原始请求时间，等待内容不会跨过传输超时后突然打开。
- 类型和方法检查、失败路径不能替代设备 ABI、渲染和输入测试。特别需要验证目标的权限弹窗、键盘、横竖屏、受保护视频和相机。

## 设备验收

在未安装 PullOver-X 的环境分别验证 iOS 16/17。重启后从主应用的 TypeX 工具栏打开已退出的备忘录，再测试已运行目标。小窗应显示可操作内容，主应用保持前台；点击「-」最小化，小窗消失且目标保留在后台（任务切换器可见、可恢复），主应用继续响应；点击关闭解除托管。设置页调整大小比例后重新悬浮打开，小窗按新比例显示。随后通过一个已安装应用的有效 URL Scheme 打开，确认目标页收到原链接，而非只显示首页。重复点击、切换目标、关闭加载中卡片、锁屏、正常全屏打开目标后，不得重新弹出旧卡片或保留透明触摸遮挡。

设备日志使用 `[TypeX][FloatingApp]` 的 `prepare`、`URL accepted`、`scene acquired`、`live`、`release`，携带 Bundle ID 与 generation，不记录 URL 参数或输入文本。主机可用 `idevicesyslog` 捕获，设备端不写日志文件。

本地测试 `python3 tests/run-floating-app-session.py` 覆盖会话代次与完成竞态，不证明设备上的托管、触摸或键盘正确。项目构建唯一入口为 `./build.sh`。

## 源码来源

场景图层托管与 RBS 前台资源机制参考本地 PullOver-X `6983a65`（基于 c1d3rDev 的 PullOver Pro，GPLv3）。新的 TypeX 请求、会话、卡片与设置实现不调用 PullOver-X 的类、通知、偏好或二进制。保留其来源说明与 GPLv3 文本：`layout/Library/TypeX/licenses/PullOver-X-GPL-3.0.txt`。TypeX 的其他部分继续使用仓库的 AGPLv3 许可。
