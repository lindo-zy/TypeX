# 状态栏手势验收

设置 → TypeX → 手势设置 → 状态栏手势。左／中／右各有单击、双击、长按、左滑、右滑五个独立条目。
总开关、横屏开关及每个手势默认关闭。每条绑定一个动作；可选择已有手势面板。
没有动作流。状态栏执行不使用其他进程的输入框，文字、JavaScript、带 @@@ 的动作不列入候选。
触发区域使用实际状态栏视图范围三等分，不增加覆盖窗口。刘海切口不可触摸；灵动岛单击使用“中间区域 → 单击”的绑定，未配置时保留系统操作。普通状态栏的原生控件仍不接管。

本地：`python3 tests/run-statusbar-gestures.py` 检查 15 个配置槽位隔离、边界、失效数据、动作能力和删除引用。
这些检查不验证 SpringBoard 的 UIKit 触摸分发或私有类存在性。

动作选择修复（2026-10-03）：

- 问题表现：用户确认点击动作后返回，但仍显示未分配。
- 根因（源码／替身复现）：选择页在 `viewDidLoad` 缓存 `statusBarSlot`。如果导航 specifier 稍后绑定，缓存仍为空，保存函数直接返回，选择页却无条件退出。对同一晚绑定场景调用修复前的生产方法，结果是 `returns=1 binding=unassigned`；修复后是 `returns=1 binding=__typex_statusbar_panel_left`。设备上 Preferences 的实际初始化时序尚未验证。
- 修复：设置行 `action` 并在 table delegate 中显式传入对应 specifier；实时读取槽位，校验合法槽位和动作，读回确认写入后再退出。新增动作保存需匹配当前导航页面和原始槽位。
- 本地：`python3 tests/run-statusbar-settings.py` 编译生产设置控制器，以 Preferences／导航替身验证 15 个槽位的面板和自定义动作选择、清空、添加／取消、写入失败、删除后选择和过期编辑回调。替身测试不代表原生 Preferences 点击已验证。
- 设备验收：在 iOS 16／17 进入左区单击，分别选择面板和已有动作，返回后名称立即更新，退出设置再进入仍保留；添加系统动作保存后回到手势页，取消添加不改绑定，清空后显示未分配。重复测试其他区域和手势，确认不会串槽位；关闭手势开关后选动作不应自动开启。syslog 的 `[TypeX][StatusBarSettings] save slot=... field=selector success=1` 应只对应操作的槽位。
- 边界：状态栏识别 Hook、动作执行器、键盘和 Dock 协议沿用现有实现。Dock 设置也使用 `buttonAction`，是否存在相同设备故障尚未确认，另行定位。
- 已知测试问题：`run-gesture-actions.py` 在修复前的 `e575ecd` 也因生成的测试头未导入 Dock 策略而无法编译（`DXDockGestureRemoveActionReferences` 未声明）；本次未修改该通用测试脚本。状态栏配置／动作选择及设置资源测试独立通过。
- 交付验证：生产设置控制器替身测试 823 项、状态栏配置 59 项、设置搜索／布局 4508 项及中文资源检查通过。修复合入 `dev` 后经 `./build.sh` 生成 4.1.10 两套包，验证 arm64／arm64e、iOS 最低版本、DEB 元数据、资源和安装／卸载脚本；iCloud 两端 SHA-256 一致，坚果云上传 2 个包并对账全部一致。实际安装／卸载、原生设置点击、手势执行及冷／热启动未验证。

动作记录及执行链路修复（2026-10-03，后续修复）：

- 问题：用户反馈所有手势选择页缺少勾选和记录；状态栏操作无效。本轮已获继续实现授权，用户明确当前无设备连接。
- 根因（源码确认）：状态栏／Dock 选择页没有渲染已选标记；PSLinkCell 动作记录依赖 Preferences 私有渲染；工具栏六个手势入口没有记录且按 `cell.textLabel.text` 判断行，受私有标签影响。状态栏启动函数仅在 SpringBoard 调用且内部再次限制进程，App 自己的 UIKit 状态栏没有识别器；原全局动作执行器及锁屏检查只能在 SpringBoard 工作。桌面无效的具体设备门禁原因未确认。
- 涉及文件／边界：三个设置控制器和共用标准 cell；`TypeX.xm`、状态栏识别器及策略；既有 `DXSystemOpenBroker` 的单一请求类型。配置键及全局动作执行器沿用现有实现，键盘、其他插件和 Dock 触摸识别逻辑不变。
- 实现：状态栏／Dock 按保存的 selector 显示勾选及动作名称，关闭槽位仍可查看记录；工具栏按稳定元数据进入正确手势编辑器并显示有序动作摘要。App 安装状态栏识别器，以现有 Darwin 通道传槽位、观察到的 selector 与横屏标记，由 SpringBoard 主线程重新读取权威配置、校验总开关／槽位／横屏／锁屏／面板和 1.5 秒有效期后执行。转向、配置刷新、App 或 Scene 失活均清除待执行会话。
- 失败／取消／重复路径：未读到配置、未配置动作、隐藏状态栏、非活动 App／Scene、原生控件触摸拒绝；选择写入读回失败留在选择页；已过期或绑定已改变的请求不执行；沿用通道的去重、超时不重试及主线程回复。新增动作回调限制当前页面／方向并防止重复保存。
- 本地验证：`run-statusbar-settings.py` 的生产状态栏／Dock 控制器及工具栏摘要替身测试 1370 项通过；`run-statusbar-gestures.py` 配置／请求策略 176 项、生产处理器 93 项、生产转发及发送代码 22 项通过。`run-darwin-open-channel.py` 使用真实通道在 macOS 独立进程验证 `statusbar-gesture` 载荷、回复、去重、损坏数据、过期、超时和清理。Dock 策略／生产处理器 54／61 项、通用动作 141 项、键盘几何 12 项、工具栏识别器 25 项、设置搜索／布局 4508 项及中文资源检查通过。前轮通用动作测试缺 Dock 策略导入的测试入口问题本轮修复。
- 集成交付：从 `dev` 的 `139bbca` 创建隔离分支 `codex/gesture-selection-runtime`，源码提交 `cf94190` 后快进合入 `dev`。保留原先未提交的 `control` 版本改动，由唯一入口 `./build.sh` 将 4.1.10 推进到 4.2.0；两目标成功，Bark 已发送。DEB 元数据／过滤器／资源／安装卸载脚本内容及语法检查通过，tweak 和 Preferences 二进制均有 arm64／arm64e；iOS 16 包 minOS 16.0，iOS 17 包按项目脚本 minOS 15.0。iCloud 已 cp 归档两套包且 SHA-256 与构建产物一致，旧 4.1.10 保留；坚果云上传 2 个、跳过 121 个，对账全部一致。包 SHA-256：iOS 16 `ed1b976e64f8111ab0d2301655791b5ca68c6d65a9b3f1b57b270b1e7eeb17e3`；iOS 17 `2aa45dee80b746ae77703cfb6c792671f8e5b6c415ab0995cedc28b9cd8532d6`。
- 运行时风险／证据边界：上述 UIKit、Preferences、锁屏和面板用替身；真实 iOS 私有状态栏类、Scene、系统手势仲裁、沙盒 Darwin 权限、面板显示及动作执行需 iOS 16／17 真机验证。未获取本轮设备触发日志；冷／热启动和安装／卸载未实测。
- 设备日志：设置看 `[TypeX][StatusBarSettings] save`／`[TypeX][DockSettings] save`；识别看 `[TypeX][StatusBarGesture] installed host=...`、`config host=...`、`rejected host=... gate=...`、`trigger host=... slot=...`；转发看 SpringBoard 的 `dispatch slot=...` 或 `dispatch rejected`，以及客户端 `result host=... status=...`。日志只写 syslog，不记录动作载荷。

在 iOS 16／17 对应目标设备上：

1. 注销后从桌面、Safari、设置和微信首次触发。syslog 应出现 `[TypeX][StatusBarGesture] installed`，记录实际视图与窗口类。
2. 为 15 个槽位分别绑定可识别的动作，检查区域和方向；单次手势只产生一条包含相同 host／slot 的 `trigger` 日志。
3. 同一区域启用单击和双击，双击不附带单击；只启用单击时不等待双击。跨区双击不触发另一区域。
4. 长按只触发一次，松手不附带单击；横滑跨区按起点归属，竖向下拉仍打开通知中心／控制中心。
5. 关闭、清空或删除某槽位动作后停止接管；未配置区域的原生状态栏滚动到顶部仍有效。
6. 面板打开、关闭、取消后再次触发；切换 App、旋转、锁屏、解锁或修改配置时未完成手势失效，后续新手势可用。
7. 测试刘海、灵动岛实时活动、隐藏状态栏的全屏 App 和安装的状态栏美化插件。灵动岛单击执行中区单击配置，关闭／清空后系统操作恢复；刘海切口仍不能触摸。
8. 普通链接只打开一次；应用或插件未安装时无崩溃；复查原有键盘手势、Dock 面板和手势面板动作。

没有 `installed` 或 `trigger` 日志时，先确认相关 Window／View 类、可见性及 Scene，再调整适配；构建成功不能代替上述验证。

单击竞争与灵动岛入口修复（2026-10-04）：

- 问题：用户反馈左／中／右单击均不生效，并要求灵动岛支持单击。功能未进行设备复现或验收；用户要求后，仅做本地验证，不再连接设备或采集设备信息、日志。
- 根因／证据边界：旧安装逻辑只遍历状态栏祖先视图上的 `UITapGestureRecognizer`，对子视图及后续新增识别器没有建立优先级；单击的默认互斥可让原生点击阻断 TypeX。旧代码另对全部 `Aperture` 触摸直接返回拒绝，且没有安装灵动岛宿主入口。前者是可导致单击失效的源码竞争缺陷，后者是灵动岛不支持的确定性代码路径；用户设备本次具体失效原因没有实机复现确认。
- 涉及文件／边界：`DXStatusBarGestureHooks.xm`、状态栏生产处理器替身测试与测试头、设置中英说明及本验收记录。绑定格式、动作执行器、面板类型规则、Dock 和键盘逻辑沿用现有实现。
- 方案／实现：在本次已接受且仍有效的触摸会话中，以 UIKit 动态失败优先级让原生单指单击等待已配置的 TypeX 单击／双击。覆盖子视图及后续安装的识别器，取消永久修改原生识别器依赖。单击仅等待同一处理器中、当前区域已配置的双击；未配置、控件拒绝、配置刷新或会话过期时没有优先级。点击延迟原生 view 的触摸回调，成功时按既有 `cancelsTouchesInView` 取消，失败时 UIKit 正常交还。
- 灵动岛入口：在 SpringBoard 主线程对 `SBSystemApertureContainerView` 做视图类型和 `didMoveToWindow` 方法 ABI 检查后 Hook，同时扫描已有窗口。每个真实容器只安装一个单击识别器，使用 `middle.tap`；其内部控件可触发该单击，普通状态栏处理器拒绝同一岛内触摸以避免双发。不建立覆盖窗口，不新增私有方法调用。容器移动、窗口变化、隐藏、锁屏、配置变化或面板已打开时拒绝过期执行；没有该类的设备保留普通状态栏路径。
- 参考：本地 UIKit 16.5 SDK 的 `UIGestureRecognizer.h` 动态优先级契约；公开 [iOS 17 容器类转储](https://github.com/MTACS/iOS-17-Runtime-Headers/blob/main/PrivateFrameworks/SpringBoard.framework/SBSystemApertureContainerView.h) 和 [视图控制器转储](https://github.com/MTACS/iOS-17-Runtime-Headers/blob/main/PrivateFrameworks/SpringBoard.framework/SBSystemApertureViewController.h)。转储证实类及其声明，不能证明当前设备运行时存在或触摸行为。
- 本地回归目标：三个区域的单击、同区单／双击竞争、子视图原生点击、后加窗口点击、未配置区域、原生多指／双击与纵向系统手势、清除／过期会话；灵动岛容器去重、内部控件、中区映射、未配置回退、锁屏、布局变化和移除。
- 回归结果：将新增竞争场景交给 `4eb1730` 的原生产处理器，子视图原生单击优先级检查失败；修复后的配置策略 174 项、生产处理器 178 项、转发／发送 22 项、生产设置 1376 项、设置搜索／布局 4508 项均通过，中英资源语法通过。UIKit／Preferences 使用平台替身，测试没有运行设备触摸。
- 实机验收（尚未执行）：iOS 16／17 冷／热启动，在桌面及 App 内分别测试三分区单击；同区双击不误发单击，未配置区正常系统点击，上下拖动正常。灵动岛中区单击应执行一次所选动作；关闭／清空中区单击后应恢复原生操作；长按展开、拖动、实时活动更新、旋转、快速重复、锁屏和容器退出不得误发。syslog 诊断为 `[TypeX][StatusBarGesture] touch`、`tap priority`、`trigger`、`dispatch`／`result`，只记录槽位与视图类型，不记录输入内容。
- 集成交付：开始时 `dev` HEAD 为 `4eb17305ad1d320bb0fca83b1284b1ce90fb44c1`，工作区干净；在独立 `codex/statusbar-single-tap` 分支实现并提交 `bc66afc`，本地快进合入 `dev`。源码审查及 `git diff --check` 通过；唯一入口 `./build.sh` 的 iOS 16／17 两目标成功，版本自动从 4.2.1 推进到 4.2.2，Bark 已发送，版本提交 `b2b2c55`。未推送代码。
- 包结构：元数据、依赖、注入过滤器、PreferenceLoader、Tweak 与 Preferences 的 arm64／arm64e、最小系统版本及更新的中英设置说明均确认。包中包含灵动岛容器 Hook 和单击优先级诊断。安装／卸载脚本可执行、语法检查通过；没有执行设备安装／卸载。iOS 16 包 minOS 16.0，iOS 17 包按既有项目脚本 minOS 15.0。

| 目标 | 4.2.2 包字节数 | SHA-256 |
| --- | ---: | --- |
| iOS 16 | 1153830 | `d3806a60d6448a3dacc471e073d3435f59b2e0a9e6646b543177af2083fd3cdb` |
| iOS 17 | 1159062 | `e65669574fe18036325c8b695fd3d8e43681a8b694035ad03130dbf01c089e54` |

- 两套包已分别 `cp` 到 iCloud 的 `Downloads/TypeX/ios16` 和 `ios17`，归档与构建产物 SHA-256 一致，旧 4.2.1 保留。`python3 webdav-sync.py TypeX` 退出 0，上传 2 个、大小一致跳过 125 个，最终所有本地归档与坚果云文件大小对账一致。
- 最终状态：源码分析、编译、包结构已确认；核心功能、冷／热启动、安装卸载及实际系统点击／长按／拖动竞争未验证。已知限制：用户本次设备单击失效的确切运行时原因仍待其自行验收反馈；容器类缺失时不会建立灵动岛入口。

灵动岛容器切换修复（2026-10-04）：

- 问题：用户实机反馈灵动岛中区手势只在打开设置时生效，其余形态（桌面、其他前台形态）不响应。
- 根因：4.2.2 的灵动岛入口把触摸归属锚定在安装那一刻的单个 `SBSystemApertureContainerView` 实例上——`shouldReceiveTouch` 用 `isDescendantOfView:anchor` 判定、坐标与 `available`／`sessionIsCurrent` 也全部围绕该 anchor。SpringBoard 会在锁屏／桌面／前台 App 之间切换岛容器实例或挂载点，切换后旧实例的手势仍占着窗口（手势挂在 window 不随视图卸下），新实例的触摸因不是旧 anchor 后代被 `return NO` 静默拒绝，且 anchor 悬空、anchor 链隐藏检查与 frame 相等校验都会随之误拦。打开设置恰是一次前台形态切换，触发容器重新挂载并为当前显示实例装上新手势，因此呈现「打开设置才生效」。
- 涉及文件／边界：`DXStatusBarGestureHooks.xm`（仅灵动岛路径）、生产处理器替身测试及本验收记录。普通状态栏五手势路径、绑定格式、动作执行器、Dock 和键盘逻辑未动。
- 方案／实现：灵动岛手势改为窗口级锚定＋触摸时动态解析——`shouldReceiveTouch` 沿触摸视图祖先链在触摸窗口内实时解析 `SBSystemApertureContainerView`，不再绑定安装时实例；`available` 对灵动岛跳过 anchor 悬空／隐藏链／几何检查（窗口身份与锁屏、面板、偏好门保留），中区固定 `middle` 不再依赖 anchor 坐标三等分，会话时效以窗口身份为准、不再做 anchor frame 相等校验；同窗口多容器实例只保留一组手势（安装时按 `aperture + window` 去重），避免窗口手势叠加双发。`touch.window` 不匹配与灵动岛归属失败两条原先静默返回的路径补 `rejected gate=window-mismatch／aperture-container` 日志，供实机定位。
- 本地回归：配置策略 174 项、生产处理器 183 项（新增容器切换、窗口手势复用、anchor 悬空可用、窗口身份会话 4 类场景）、转发／发送 22 项通过；全套 run-*.py 退出码 0。UIKit 替身测试没有运行设备触摸。
- 实机验收（尚未执行）：iOS 16／17 冷／热启动，桌面与 App 内分别触发灵动岛中区单击应各执行一次所选动作；设置→桌面→设置来回切换后仍生效；长按展开、实时活动、拖动、锁屏不误发。若仍失效，抓 syslog `[TypeX][StatusBarGesture]` 的 `installed`／`rejected gate=…`／`touch … view=类名` 序列——`touch` 的 view 类名可直接暴露桌面形态下真实接收触摸的视图类，用于判断是否存在 `SBSystemApertureContainerView` 之外的入口类需要补充。
- 入口类覆盖面核实（2026-10-04，公开 [iOS 17 SBSystemApertureViewController 转储](https://github.com/MTACS/iOS-17-Runtime-Headers/blob/main/PrivateFrameworks/SpringBoard.framework/SBSystemApertureViewController.h)）：岛控制器经 `_newContainerViewWithInterfaceElementIdentifier:` 动态创建多个 `SBSystemApertureContainerView` 实例（`_orderedContainerViews` 按 rank 管理、含 outgoing/incoming 切换），锁屏／桌面／前台 App 的岛元素全部由这一个类承载，不存在需要另行 Hook 的第二入口类；多实例并存切换即本次修复针对的形态。转储证实结构，不证明设备触摸行为。

iOS 17 系统状态栏入口补齐（2026-10-04）：

- 问题：用户反馈状态栏手势只在设置界面生效，桌面及其他界面不响应。本次覆盖普通状态栏入口；前轮灵动岛容器切换修复不足以覆盖此路径。
- 根因（源码／替身确认）：视图识别和 Hook 注册只包含 `UIStatusBar`、`UIStatusBar_Modern`、`_UIStatusBar`。公开 iOS 17 [SBStatusBarWindow 转储](https://github.com/MTACS/iOS-17-Runtime-Headers/blob/main/PrivateFrameworks/SpringBoard.framework/SBStatusBarWindow.h) 的状态栏属性为 `STUIStatusBar_Wrapper`；[Wrapper 转储](https://github.com/MTACS/iOS-17-Runtime-Headers/blob/main/PrivateFrameworks/SystemStatusUI.framework/STUIStatusBar_Wrapper.h) 继承 `UIStatusBar_Base`，内部 [STUIStatusBar 转储](https://github.com/MTACS/iOS-17-Runtime-Headers/blob/main/PrivateFrameworks/SystemStatusUI.framework/STUIStatusBar.h) 直接继承 `UIView`，两者均不是原三类的子类。按这套继承关系运行修复前生产安装代码，识别器数量为 0。转储与替身证明入口遗漏，不能证明设置与其他 App 的实际触摸归属或此次设备失效的全部原因。
- 方案／实现：补齐两个 SystemStatusUI 类的识别及独立 Hook，保留所有 UIKit 入口；注册前检查视图继承关系及 `didMoveToWindow` 方法 ABI。窗口显示时重试 Hook 注册并扫描已有／当前窗口，覆盖框架延迟加载；每个 Hook 只注册一次，嵌套 Wrapper／Core 使用原安装函数按外层锚点去重。安装、触摸及执行继续在主线程；配置、锁屏、Scene 和原生控件保护沿用。
- 涉及文件／修改边界：`DXStatusBarGestureHooks.xm`、状态栏测试入口／处理器／UIKit 替身及本记录。配置格式、跨进程协议、动作执行器、灵动岛、Dock、键盘和设置资源未修改。
- 本地验证：状态栏配置策略 174 项、生产处理器／扫描／Hook 注册决策 402 项、生产转发／发送 22 项通过。新增测试按真实继承关系延迟注册两个 SystemStatusUI 类，在 SpringBoard／Preferences／MobileSafari 替身宿主验证三分区五手势各执行一次、嵌套扫描去重、Hook 重试去重、窗口切换取消旧会话及解绑清理；同一测试对修复前 `63ecd7a` 的生产代码在 SystemStatusUI 视图识别断言失败。Logos 注册用记录替身，不代表真实注入已验证。
- 关联回归：状态栏设置 1376 项、Dock 策略／处理器 50／61 项、全局面板策略／几何及触摸 79／22 项、通用动作 141 项、键盘几何 12 项、工具栏识别器 25 项、面板注册表 41 项通过；Darwin 转发通道独立进程测试的状态栏载荷、回复、去重、损坏、超时、过期及清理通过。
- 集成／编译／包结构：从 `dev` 的 `63ecd7a` 在独立 `codex/statusbar-ios17-entry` 工作树开发，源码提交 `ee7fba4` 本地快进合入 `dev`，保留未跟踪的 `.zcodeignore`；源码 diff 审查及 `git diff --check` 通过。集成后仅通过 `./build.sh` 构建，两目标成功，版本由 4.2.4 自动推进为 4.2.5，Bark 已发送。两包元数据均为 `com.lindo.typex / 4.2.5 / iphoneos-arm64e`，依赖沿用 `firmware(>=15.0)`；TypeX 与偏好二进制均含 arm64／arm64e，iOS 16／17 包最低系统分别为 16.0／15.0；注入过滤、SystemStatusUI 类字符串、安装卸载脚本内容／权限／语法核对通过。检查未执行设备安装或卸载。
- 实机验收（尚未执行）：iOS 16／17 注销后先在桌面触发，再切换设置→桌面→Safari／微信，并分别测试冷／热启动的三分区五手势；每次只执行一次，关闭开关／清空槽位后保持系统行为。锁屏、隐藏状态栏、旋转、窗口切换、双击与单击竞争、上下拖动不能误发。iOS 17 syslog 应出现 `[TypeX][StatusBarGesture] hook ... class=STUIStatusBar_Wrapper／STUIStatusBar`、`installed ... view=STUIStatusBar_Wrapper`，继而为 `touch`→`trigger`→`dispatch`／`result`；失败时按 `rejected ... gate=...` 继续定位。日志仅记录进程、类名及槽位，设备不写日志文件。
