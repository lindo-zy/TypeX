# 面板顶部默认系统控件

问题：用户要求每个面板顶部默认提供参考图中的五个开关和两条滑条。
现状：此前内容仅引用有效自定义动作，没有固定控制区和跨进程状态回读。
涉及文件：DXKeyboardPanel、DXPanelSystemControlsView、DXPanelControlState/Layout/Session、
DXSystemOpenBroker、DXSystemActionExecutor、设置预览/说明与相关测试。
修改边界：左/右/通用面板共用新顶部控件；下方仍只允许添加自定义动作。
不修改其他插件、URL 打开协议、工具栏手势或退出类系统动作。

## 行为

- 第一排固定为勿扰模式、无线网络、静音、蓝牙、方向锁定，圆形按钮、中文名称，开启蓝色，关闭暗色。
- 第二排为亮度与媒体音量胶囊滑条，白色填充随值变化，带太阳/扬声器图标，支持无障碍增减。
- 控件与自定义网格在同一个纵向滚动区内；横屏或低高度可继续滚动。顶部标题/关闭入口保留。
- 默认控件不写入自定义动作列表，不需要用户先创建系统动作。已有三套配置保留。
- 控件操作保持面板与输入焦点，不主动收起或恢复键盘。关闭/切输入框/Scene 失活按既有路径清理。
- 设置预览使用同一个控件实现，显示示意状态且不可执行系统操作；说明明确区分示意和真实状态。

## 执行、状态与生命周期

普通 App/远程键盘发送固定 `panel-control` 请求，通过既有 Darwin 通道路由到 SpringBoard 主线程。
白名单仅允许五个开关、亮度、媒体音量和状态查询；不接受任意 selector 或电源动作。
检查参数类型、有限的 0–1 范围、来源工具栏开启状态、UUID、请求年龄不超过 1.5 秒。

每次请求由客户端持有随机 UUID 状态槽，初值为 pending；服务端在执行前校验槽仍有效。
回复通过该槽返回五个状态/可用位和两个 16 位滑条值，既有结果回复枚举不变。
缺少接口或读取失败的状态不伪造成关闭，实际控件显示不可用。状态读取发生在打开时、操作后和空闲期间。
新会话使用新的视图、状态槽和 session；旧/重复回复不能更新当前会话。

滑条每次最多一个在途请求，未发送的同类中间值合并为最新值，发送间隔至少 100ms。
回复不会覆盖正在拖动/排队的值；超时、失效或不可用时清空未发送请求，不自动重试。
关闭时同步作废状态槽，再取消 NSProgress，避免 Foundation 的异步 cancellationHandler 导致旧请求被接受。
注册 token 清理幂等；已执行的系统操作不会被撤销，关闭不会重新发送操作。

开关复用已有系统动作执行器；铃声静音经 SBRingerControl，优先旧 setter，使用存在性/ABI 检查的
新版 setter 兼容入口。新版 clientType 参数使用 0，目标版本的具体分类语义仍需真机验证。
音量选择原生媒体音量 getter/setter，而非将媒体音量归零来冒充静音；亮度经 UIScreen。
源码接口参考本地 Theos，并参考 [SBRingerControl 头文件](https://raw.githubusercontent.com/userlandkernel/ios17-dyld-headers/master/SpringBoard/SBRingerControl.h)、
[SBVolumeControl 头文件](https://raw.githubusercontent.com/userlandkernel/ios17-dyld-headers/master/SpringBoard/SBVolumeControl.h)
及 [SingleMute 的 iOS 16/17 铃声接口](https://github.com/OwnGoalStudio/SingleMute/blob/main/SingleMute.x)。
第三方头文件实际版本为 iOS 18.2；它们提供接口证据，不能证明目标版本中确实存在或权限允许。

诊断 syslog 为 `[TypeX][PanelControl] action=… result=…`，缺失 API 和原生错误沿用 SystemAction 日志。
只记录固定动作和状态结果，不记录输入文字，不在设备写日志文件。

## 验证

`python3 tests/run-panel-controls.py` 测试生产参数/状态/布局辅助逻辑和请求 session；
编译实际客户端入口，使用真实 notify 状态槽与替身服务验证回读、取消、清理和坏回复。
`run-system-actions.py`、`run-settings-ui.py`、`run-gesture-actions.py`、`run-text-actions.py` 回归既有逻辑。
`run-darwin-open-channel.py` 回归实际跨进程传输。唯一项目构建入口为 `./build.sh`。

设备验收（iOS 16/17 RootHide，各含冷/热启动）：

1. 从普通 App、Spotlight 的顶部/底部打开左、右和通用面板，均出现七项控件，键盘不透出，触摸不穿透。
2. 对照系统状态逐个切换五个开关，确认静音影响铃声、保持媒体音量；缺失接口显示不可用而非假状态。
3. 亮度和媒体音量从 0 到 1 连续拖动、快速往返、松手，系统停在最终值；改变物理音量后状态更新。
4. 拖动/在途回复时关闭、换输入框、旋转、收起键盘再打开，确认无旧值写入或旧提示出现在新会话。
5. 横屏/低高度滚动可访问顶部和全部自定义项；设置预览样式同步，自定义项增加/排序/大小修改仍立即更新。
6. 系统忙、缺少接口或无服务时失败可诊断，不崩溃、不无限发送/自动重试；勿扰跟随系统专注模式状态，蓝牙反映真实电源状态。

源码、自动测试和包结构检查均不能代替上述设备验收。

## 本次结果（3.9.6）

源码 diff 审查与 `git diff --check` 通过。6226 项顶部控制检查、62 项系统/面板辅助逻辑、
4508 项设置搜索/共享布局，以及静态中文资源覆盖、187 项既有手势/几何/文本回归通过。
实际跨进程 Darwin 传输回归通过，未修改原通道协议。测试中发现并修正了 NSProgress 异步取消
导致 pending 槽未及时撤销的问题；实际客户端入口与真实 notify 槽验证取消后不再接受请求。

`./build.sh` 成功产出 iOS 16/17 两套 3.9.6 包，均含 arm64/arm64e；检查元数据、
两个二进制中的控制区/滑条类、执行器导出、中文资源、plist 以及安装/卸载脚本语法通过。
构建沿用 ios16 deployment=16.0、ios17 deployment=15.0，control 的 firmware>=14.0 依赖未变；
这不代表这些较旧系统的运行时已验证。

核心功能未真机验证：本次未安装新包，也未执行真实系统开关或滑条操作；
冷/热启动、系统权限、新版铃声 clientType 的具体语义、媒体路由/音量范围、
控件触摸/无障碍与 SpringBoard 远程键盘的显示及命中均需按上方步骤检查。

## 顶部图标闪烁与浅色滑条轮廓

问题：面板打开后五个图标持续闪烁；浅色背景上的白色滑条填充边界不明显。
根因：DXPanelControlSession 每秒的状态查询发送 busy=YES UI 标记，按钮进入禁用
图像状态，查询回复又恢复可用，持续在两个图像状态之间切换。滑条只设置填充和
底色，没有浅色胶囊边框，填满时与浅色面板接近。
涉及文件：DXPanelControlSession.m、DXPanelSystemControlsView.m、生产 session 回归测试。
修改边界：后台状态读取仍保持单次请求/生命周期保护，但不发送禁用 UI 标记；
真实写入仍禁止重复点击。按钮可用状态不变时不重复设置 enabled。两个滑条在
浅色模式显示 1pt 灰色外轮廓，0–100% 均保留，深色样式与滑动数值逻辑不变。
实际面板和设置预览共用视图，样式同步。没有修改系统执行器或跨进程协议。
运行时风险：真实 UIKit 的禁用态绘制与胶囊边框、动态系统状态变化需设备验证。
验证步骤：session 回归确认首次/后续状态查询不产生 busy UI 标记，查询途中真实
开关操作仍串行并进入写入保护；同时回归既有合并、取消、重复/迟到回复路径。

设备验收：iOS 16/17 RootHide 的普通 App 和 SpringBoard 冷/热启动后打开三套面板，
不操作保持 10 秒，五个图标不再每秒变暗/恢复；外部改变真实状态时更新正常。
状态查询途中点击开关只执行一次，滑条快速拖动最终值正确，关闭不产生旧回调。
浅色模式检查亮度/音量在 0%、中间值和 100% 都能看到完整外轮廓；检查设置预览，
再切回深色模式确认原样式、滑动和滚动访问正常。

## 默认开关换为勿扰与蓝牙（3.9.9）

问题：默认五开关中的手电筒、深色模式需替换为勿扰模式、蓝牙。
根因：DXPanelToggleIdentifiers() 固定五元组同时充当请求白名单、notify 位编码序
与视图按钮序；执行器已有蓝牙/勿扰切换实现，但面板状态查询与转发白名单未含两者。
涉及文件：DXPanelControlState.h、DXPanelSystemControlsView.m、DXSystemActionExecutor.m。
修改边界：仅固定控件默认集；自定义动作目录中的手电筒/深色模式动作与既有配置不动。
实现方案：标识表换为勿扰/无线网络/静音/蓝牙/方向锁定；视图换名称、图标与预览示意；
执行器状态查询补 BluetoothManager powered 与 DNDStateService 只读查询（镜像
DXSystemToggleDND 的 Control Center 客户端标识路由），转发白名单改为直通
DXPerformSystemAction。额外键在编码时被忽略，通道协议与位宽不变。
不修改的部分：DXSystemActionCatalog、自定义动作执行路径、跨进程通道与滑条逻辑。
运行时风险：勿扰/蓝牙私有接口在真机的查询语义；安装后未 respring 前新旧 dylib
按位序解码会瞬时错位，重启后恢复。
验证步骤：session 回归覆盖新白名单与编解码往返；设备按上方步骤验收勿扰/蓝牙的
状态显示、切换与不可用降级。
