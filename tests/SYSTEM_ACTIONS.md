# 自定义系统动作

入口：TypeX 设置 → 自定义动作 → 添加 → 系统动作 → 选择系统动作 → 保存。
也可从面板的添加自定义动作入口就地创建。系统动作保存为 `type=system` 和
固定 `systemaction` ID，可用作工具栏按钮/手势、子动作和左右/通用面板项目。
基础动作目录没有新增系统项目，面板仍只选择有效自定义动作。

## 分析与修改边界

问题：自定义动作没有系统控制类型；独立面板窗口在 SpringBoard 与远程键盘重叠。
根因：原类型和执行器未包含系统动作；3.9.2 通过 UIWindow level 提升独立窗口，
源码不能保证远程合成键盘的遮挡关系，模糊背景也不能保证采样远程按键。
方案：共用固定目录的设置选择器和 SpringBoard 执行器；通过既有 Darwin 请求通道
一次发送请求。面板进入已存在键盘窗口的视图层级，使用不透明底层。
不修改其他插件、旧 URL/PullOver-X 协议或现有基础动作，不恢复翻页或控制条。

## 动作目录与实现

| 分组 | 动作 | 执行入口 |
| --- | --- | --- |
| 媒体 | 上一首、下一首、播放/暂停 | SBMediaController |
| 设备 | 返回桌面、打开后台 | SpringBoard Home 模拟、Switcher 控制器 |
| 设备 | 注销 | SBSRelaunchAction + FBSSystemService |
| 设备 | 注销（SB） | 仅退出本进程 SpringBoard |
| 设备 | 安全模式 | 已加载 SafeMode/MobileSafety 处理器时触发 SB 信号；否则不可用 |
| 设备 | 关机、重启设备 | FBSSystemService |
| 设备 | 重启用户空间 | reboot3 指定 userspace 标志；不降级为整机重启 |
| 控制中心 | 打开控制中心、方向锁定 | SBControlCenterController、SBOrientationLockManager |
| 控制中心 | 录屏、开麦录屏 | SpringBoard 的 ReplayKit sharedRecorder 系统录屏接口，异步回复 |
| 控制中心 | 手电筒、Wi-Fi、蓝牙、飞行、蜂窝 | AVFlashlight、SBWiFiManager、BluetoothManager、SBAirplaneModeController、CoreTelephony |
| 控制中心 | 勿扰、深色模式 | DNDStateService + DNDToggleManager、UIUserInterfaceStyleArbiter |
| 控制中心 | 亮度增减、音量增减 | UIScreen 每次 0.1（钳制 0–1）、SBVolumeControl 每次一档 |

共 26 项。控制开关反转当前状态，Wi-Fi/蓝牙对应系统开关，不承诺与控制中心
临时断连语义完全相同。勿扰只切换系统勿扰标识，不新增/管理其他专注模式。

运行时检测类、selector、参数数量和 ABI；NSInvocation 按实际标量类型传参，
拒绝结构体和不支持的指针签名；缺失接口或明确失败返回错误，记录 syslog。
普通 App 不直接调用系统控制器。SB 端校验固定目录、TTL、权威偏好可用、
动作确实属于保存的有效自定义定义；不接受任意 selector 或 shell 命令。
配置有效仅限制请求范围，Darwin 通道不提供进程身份认证。

注销、安全模式、关机、重启在 SpringBoard 显示确认框；60 秒失效，新请求取消旧确认。
取消、窗口失效、操作过期不执行。传输成功对退出类只表示确认框已展示；需要当前
用户确认才执行，客户端不能提供跳过确认标记。常规动作的 void setter 成功仅表示
已提交调用，radio 等异步状态需要设备观察，不能视为设备效果已确认。
userspace reboot 需要当前越狱授予 syscall 权限；没有 root helper 或提权回退。
安全模式行为依赖越狱处理器，版本/环境差异需要真机检查。

接口参考优先本地 Theos 头文件，并参考 [UIKit/SpringBoard 运行时头文件](https://github.com/userlandkernel/ios17-dyld-headers)、
[CoreTelephony 反向头文件](https://github.com/Cykey/ios-reversed-headers/blob/master/CoreTelephony/CTCellularDataPlan.h)、
[Dopamine userspace reboot 源码](https://github.com/opa334/Dopamine/blob/2.x/BaseBin/jbctl/src/main.m)。
第三方头文件仓库中的实际头文件版本可能与仓库名不同；它们用于接口参考，不是 iOS 16/17 运行时证明。

## 验证

- `python3 tests/run-system-actions.py`：实际目录、有效配置过滤、调用 ABI 与非法签名不产生执行、面板仅自定义动作、窗口优先级。
- `python3 tests/run-gesture-actions.py` / `run-text-actions.py`：手势、容量、覆盖几何和原文本动作回归。
- `python3 tests/run-darwin-open-channel.py` / `run-sensitive-url-executor.py`：通信过期、重复、超时、回复清理和既有系统打开路径回归。
- `./build.sh`：两个目标/架构编译打包；检查 DEB 元数据、资源、安装卸载脚本和新增控制器/执行器。

上述检查不执行设备系统操作。设备验收需在 iOS 16/17 各含冷/热启动：

1. 新建系统动作，保存/重进、改名称图标；未选择动作不能保存。添加到左右/通用面板，基础动作不可选。
2. 从普通 App 及 Spotlight 键盘顶部/底部触发，面板完整遮住按键和工具栏，触摸不穿透，关闭键盘不重弹。
3. 播放音乐后逐个试上一首/下一首/暂停；从面板返回桌面、开后台和控制中心。
4. 在对应系统页面观察各开关状态、亮度和音量变化；连续点击、达到上下限、相机占用手电筒及无蜂窝设备均不崩溃。
5. 在可中断设备上单独验证退出/电源动作；先取消确认、不操作超过 60 秒、重复触发确认框，均不发生旧操作。
6. 对无接口/权限的设备观察失败提示；未配置 ID、过期请求、未知 ID 不执行。切 App/输入框后旧失败提示不出现在新输入会话。

日志：`[TypeX][SystemAction]` 含固定动作 ID、结果和缺失 selector；不记录输入内容、不写设备日志文件。

## iOS 16/17 RootHide 失败修复

问题：用户报告多项动作失败，含勿扰，出现统一的不可用提示。
源码中的确定问题：DNDStateService / DNDToggleManager 使用自创客户端标识，
与 SpringBoard 公布的客户端授权列表不匹配；失败路径丢弃 NSError，无法区分缺失接口和原生拒绝。
参考 [SpringBoard entitlement dump](https://gist.github.com/networkextension/11df87e07921b59fe9f526a45c6dee1d)
中 DoNotDisturb 的 state.request / mode.assertion client-identifiers。此参考不是目标设备的运行时权限证明。

修复：使用控制中心客户端标识 `com.apple.donotdisturb.control-center.module`；
查询当前勿扰标识并切换，旧状态接口仅在无 activeModeIdentifier 时使用 isActive。
查询失败不执行切换。保留原生错误 domain/code，记录 ABI 拒绝的阶段、类和 selector。
返回桌面、后台、控制中心和方向锁加入已有接口的兼容选择；仅选一个存在的接口执行，
调用失败不重试另一个接口。音量增加 SBUIController 的原生控制器来源；蓝牙开启先启用服务。
Home / Switcher 的备用接口参考 [DVirtualHome 实现](https://github.com/DGh0st/DVirtualHome/blob/master/Tweak.xm)。
未使用枚举含义不明的 toggleToTargetState，不新增提权或 shell 回退。
失败提示区分接口不可用、原生失败、配置无效、过期和回复超时；超时结果未知，不自动重试。

涉及 DXSystemActionExecutor.m、DXSystemActionInvocation.h、DXSystemActionCompatibility.h、
DXCollectionView.m 和本地化资源。不改变系统动作目录、既有跨进程协议或退出动作的确认逻辑。

自动检查新增 native NSError、单次接口选择及实际 DND 辅助调用路径的替身测试；
替身校验客户端、开关方向、其他专注标识、旧状态、查询拒绝/切换拒绝和缺失类。
这些检查不能验证系统服务权限或真实状态。需在两个版本安装后按上方步骤逐项测试，
尤其观察勿扰状态与失败 syslog 的 domain/code；连接的 iOS 17.1.2 设备本次未安装新包、未操作系统动作。

## 本次开发结果（3.9.3）

源码审查与 `git diff --check` 通过；49 项系统/面板辅助逻辑、187 项手势/几何/文本
检查通过，Darwin 通道及既有敏感 URL 调度回归通过。`./build.sh` 完成两套包，
均包含 arm64/arm64e，设置资源、导出执行器、控制器类、plist 与安装卸载脚本语法检查通过。
control 的既有 firmware>=14.0 元数据未变；实际 Mach-O deployment 为 ios16=16.0、ios17=15.0，
沿用构建脚本的配置，并不宣称这些旧系统运行时受支持。

未安装到设备，冷/热启动、系统控制器是否存在、权限、动作实际效果、确认框可见性，
以及 Spotlight 远程键盘的显示/命中测试均未验证。源码/构建通过不代表这些项目通过。

## 本次修复结果（3.9.5）

源码审查和 `git diff --check` 通过。62 项系统/面板辅助逻辑检查、4508 项搜索/共享网格
检查及静态中文资源覆盖检查通过；既有 141 项手势配置、12 项覆盖几何、25 项识别器
状态、9 项文本动作检查通过。`./build.sh` 成功构建两个目标，版本由 3.9.4 推进至 3.9.5。
包检查确认两套均含 arm64/arm64e、预览与中文控件、正确 Root.strings 翻译、勿扰的新客户端标识、
完整系统动作与失败提示资源；plist 和安装/卸载脚本语法通过。deployment/依赖沿用上文配置。

核心功能未真机验证：本次没有安装或执行设备系统动作，也未验证 iOS 16/17 的权限、
设置页实际显示/交互、预览即时刷新、搜索弹出键盘或远程键盘覆盖。自动检查使用生产代码和替身，
不能证明这批私有 API 在两个目标版本均存在或所有动作已恢复。复测失败时需收集固定动作 ID 与对应 syslog。


## 录屏动作与面板左滑删除

问题：用户需要“录屏”“开麦录屏”，面板配置只有增加/排序入口，左滑无法删除。
根因：系统目录与执行器未包含 ReplayKit；面板内容列表永久处于排序编辑模式，
虽然存在 commitEditingStyle 删除回调，却没有正常浏览模式的滑动入口。
涉及文件：DXSystemActionCatalog.h、DXSystemActionExecutor、DXSystemOpenBroker、
DXSystemRecordingSession、面板内容控制器、系统选择器、本地化和相关测试。
修改边界：仅添加两个固定系统动作及当前面板引用删除/排序入口；保留已存在的
DXPLinkActionEditorController.m 未提交修改。不修改其他插件、基础动作、面板顶部控件、
Darwin 协议或自定义动作定义的删除规则。

实现：录屏动作经过既有配置白名单与时效校验，只有 SpringBoard 主线程加载公开
ReplayKit framework 并获取 RPScreenRecorder.sharedRecorder。未录制时使用
startSystemRecordingWithMicrophoneEnabled:handler:，传 NO / YES 区分两个动作；
已有系统录制时，两者均调用 stopSystemRecording:，采用系统停止/保存路径，不调用
返回临时 URL 的 stop，也不创建本地视频文件。普通 App 不执行 ReplayKit 权限调用。
接口存在性、void 返回类型、BOOL 参数及 block 参数 ABI 不符则返回不可用。
isRecording/systemRecording 不一致时拒绝，避免中断应用捕获/广播或未完成的切换。

异步会话单独串行：原生回调后才回复成功/失败；启动/停止期间再次触发返回忙碌。
7.5 秒无回调回复超时（结果未知）；主线程排队较久时传输可能先超时。两种超时均不重试，
保留单次执行保护直到原生完成，或下一次
用户触发时观察到目标终态。迟到/重复回调根据 generation 忽略，不更新新请求。
回调回主线程，不持有 UI/window/Scene，使用弱会话引用避免 recorder/block 互相持有。
仅记录 [TypeX][SystemRecording] 固定阶段、代次、麦克风标志与错误 domain/code；
不记录路径、输入内容或写设备日志文件。系统已接受的原生录制不会因宿主切换而被擅自停止。

参考 [ReplayKit 运行时头文件](https://raw.githubusercontent.com/userlandkernel/ios17-dyld-headers/master/ReplayKit/RPScreenRecorder.h)。
该文件实际标注 iOS 18.2，提供接口形状参考，不能证明 iOS 16/17 可用性；运行时必须检测。
同时参考 [iOS 16 ReplayKit 服务协议](https://raw.githubusercontent.com/lechium/iPhoneOS_16.0_20A5303f/master/System/Library/Frameworks/ReplayKit/RPDaemonProtocol-Protocol.h)，
其中普通系统 start/stop 回调使用 NSError，URL 返回 stop 是独立接口；服务协议不等于
RPScreenRecorder 类方法在目标设备可用的证明。
目标系统的 native completion block 参数语义、SpringBoard entitlement、麦克风授权、
系统状态初始化和自动相册保存仍需真机验证；方法存在不等同于系统允许执行。

验证步骤：

1. iOS 16/17 RootHide 冷/热启动后分别创建两个系统动作，保存并重进，加入面板/工具栏。
2. 未录制时点击“录屏”，确认录制开始且麦克风关闭；再次点击停止，检查相册视频。
3. 点击“开麦录屏”，确认麦克风开启并有声音；再次点击任一录屏动作停止，检查保存结果。
4. 先在控制中心启动录屏，再从动作停止；应用捕获/广播期间不误停或开启另一录制。
5. 启动/停止期间快速重复点击，切 App/收键盘，检查没有重复请求、旧提示或崩溃。
6. 录屏受限制、麦克风不可用/未授权、接口缺失/系统服务拒绝时，应收到对应失败而非假成功。
7. 左右/通用配置左滑删除，预览与重进结果一致；定义和其他面板引用保留，可重新添加。

自动测试实际编译 DXSystemRecordingSession.m，以原生录屏替身验证麦克风参数、
异步回复、错误、重复/过期回调、签名拒绝、忙碌和超时不重试。它不会录制设备屏幕，
也不能验证 UIKit 左滑、麦克风音轨或系统相册保存。


本次结果（3.9.7）：源码与 diff 检查通过；67 项系统/面板逻辑、39 项异步录屏
检查通过。既有设置/布局、面板控制、手势/几何、文本和 Darwin 通道回归通过。
./build.sh 成功构建 iOS 16/17 两套包，版本由 3.9.6 推进至 3.9.7。
真机未安装或录屏：麦克风授权/音轨、照片保存、外部控制中心录屏同步、冷/热启动
及左滑删除/排序真实 UIKit 交互均未验证。
