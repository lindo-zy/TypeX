# TypeX 悬浮打开应用

自定义动作的「打开应用」与「URL Scheme」默认启用「悬浮打开应用」。无需安装或启用 PullOver-X。工具栏、键盘面板、桌面手势和全局面板都使用 TypeX 自有 SpringBoard 托管入口。

小窗中可以操作目标应用，标题栏可拖动。标题栏右侧「-」最小化按钮收起小窗并把目标挂后台驻留（不强制终止进程），紧邻的关闭按钮解除托管并终止目标应用进程。关闭时核对 PID，避免终止已切到正常前台或重新打开的目标；任务切换器可能保留系统的历史快照，是否关闭以目标进程已退出为准。双指展开或捏合可等比放大、缩小整张卡片，标题栏与应用画面同步缩放，限制在屏幕可用区域内，仅作用于当前小窗。打开另一目标会收起前一个小窗。卡片之外的区域不拦截主应用触摸。小窗的默认最大占屏比例和左右停靠在「悬浮面板」页调整，对新打开的悬浮生效；左右停靠贴到屏幕安全区域边缘，拖动后以拖动位置为准。

关闭「悬浮打开应用」开关可使用普通全屏打开。旧的 `pullover` 配置不参与新路由；未写入 `floating` 的动作默认启用 TypeX 悬浮，保存时移除旧键。原有「小把手」动作仍是独立的第三方唤醒动作。

URL Scheme 通过 LaunchServices 解析目标，向 FrontBoard 提交带原始 URL 的 suspended 请求。不对应可托管应用的系统命令需要使用普通打开。悬浮失败不补发全屏打开。当前主应用自身作为目标时返回 Busy，避免把正在操作的主应用搬进卡片。

## 实现与生命周期

- `DXSystemOpenBroker` 的 `floating-application` / `floating-url` 使用现有请求 ID、TTL 与单次回执。
- `DXFloatingAppSession` 管理代次、就绪截止时间、替换请求与单次完成。
- `DXFloatingAppRuntime` 仅在 SpringBoard 初始化。默认 Scene 图层由系统 host view 绘制，主内容、键盘、external Scene 分开接入后按原画布缩放，初始自动适配比例由 `floatingcardmaxscale`（悬浮面板设置页，30–100%）封顶；双指缩放可突破初始比例，以屏幕可用区域为上限。
- 当前 target/base Scene 的 settings 更新受会话限定的前台保护。可见目标持有 RBS 运行断言。最小化、关闭、目标进程/Scene 结束、锁屏、原生前台切换都会释放断言、图层 KVO、host requester 和窗口；最小化在释放后追加一次挂起停靠（`launchApplicationWithIdentifier:suspended:YES`），保证目标驻留后台。
- 最小化在释放 Scene 前，用实际 Scene identifier 创建 `SBDisplayItem`，通过系统 `SBMainSwitcherControllerCoordinator` 的 `addAppLayoutForDisplayItem:windowScene:completion:` 登记最近应用卡片；已有卡片不重复插入，接口缺失、Scene 未就绪或异常会在日志中标为 `switcherRequested=0`。挂起启动与任务切换器登记是两个独立步骤，不能以 `parked=1` 推断卡片可见。接口依据 [iOS 17 的运行时头文件](https://github.com/MTACS/iOS-17-Runtime-Headers/blob/main/PrivateFrameworks/SpringBoard.framework/SBMainSwitcherControllerCoordinator.h)，iOS 16/17 均在调用前检查能力与方法签名；真实卡片与恢复行为需要设备验收。
- 托管应用画面的触摸送入目标进程。`DXFloatingAppInput` 在目标 App 自己的匹配 Scene 窗口里注册双指识别器，通过 Darwin notify 的内存状态传送比例；SpringBoard 校验随机会话标识、PID、会话代次、窗口与解锁状态，再复用卡片等比缩放。消息带手势序号，通知合并后即使先收到 Changed/Ended，也只取一次起始尺寸。最小化、关闭、锁屏、切换目标及正常前台接管会撤销会话并移除 App 端识别器，不写偏好或设备日志文件；常规 App 双指手势只在该 Scene 被托管时让位。
- 内容与 URL 接收回执都就绪后才能返回成功；截止时间使用原始请求时间，等待内容不会跨过传输超时后突然打开。
- 类型和方法检查、失败路径不能替代设备 ABI、渲染和输入测试。特别需要验证目标的权限弹窗、键盘、横竖屏、受保护视频和相机。

## 设备验收

在未安装 PullOver-X 的环境分别验证 iOS 16/17。重启后从主应用的 TypeX 工具栏打开已退出的备忘录，再测试已运行目标。小窗应显示可操作内容，主应用保持前台；点击「-」最小化，小窗消失且目标保留在后台（任务切换器可见、可恢复），主应用继续响应；点击关闭后目标 PID 应消失，主应用保持运行，再次打开目标应重新启动。设置页分别选择居左、居中、居右并重新打开，确认安全区域左边缘、居中、右边缘三个位置，拖动后保留拖动位置。双指展开和捏合，标题栏与画面应同步等比缩放、不超出屏幕；达到边界后松手，再反向缩放应立即响应，单指操作应用与两个按钮仍正常。设置页调整大小比例后重新悬浮打开，小窗按新比例显示，100% 时两个按钮仍可点按。随后通过一个已安装应用的有效 URL Scheme 打开，确认目标页收到原链接，而非只显示首页。重复点击、切换目标、关闭加载中卡片、锁屏、正常全屏打开目标后，不得重新弹出旧卡片或保留透明触摸遮挡。

设备日志使用 `[TypeX][FloatingApp]` 的 `prepare`、`URL accepted`、`scene acquired`、`live`、`resize`、`close terminate`、`release`，携带必要的 Bundle ID、generation、缩放或终止结果，不记录 URL 参数或输入文本。主机可用 `idevicesyslog` 捕获，设备端不写日志文件。

应用画面内部缩放的诊断链为 SpringBoard `input relay ready` → 目标 App `input installed` / `input pinch` → SpringBoard `resize`；最小化应有 `parked=1 switcherRequested=1`，随后手动打开任务切换器确认卡片存在、点击可恢复目标。冷启动目标与已在后台的目标都要测试；反复最小化、重新悬浮、缩放、关闭后，不得留下旧消息或重复卡片。设备连接、安装及日志抓取均须用户明确授权。

本地测试 `python3 tests/run-floating-app-session.py` 覆盖会话代次与完成竞态；`python3 tests/run-floating-app-runtime.py` 覆盖实际关闭方法的释放顺序与 PID/前台/重开保护、等比缩放和停靠几何边界、实际 App 输入客户端的 Scene 过滤/消息/替换撤销，以及实际任务切换器登记方法的去重与 ABI/能力保护。窗口、卡片模型采用主机替身，不证明设备上的托管、触摸或键盘正确。项目构建唯一入口为 `./build.sh`。

## 源码来源

场景图层托管与 RBS 前台资源机制参考本地 PullOver-X `6983a65`（基于 c1d3rDev 的 PullOver Pro，GPLv3）。新的 TypeX 请求、会话、卡片与设置实现不调用 PullOver-X 的类、通知、偏好或二进制。保留其来源说明与 GPLv3 文本：`layout/Library/TypeX/licenses/PullOver-X-GPL-3.0.txt`。TypeX 的其他部分继续使用仓库的 AGPLv3 许可。
