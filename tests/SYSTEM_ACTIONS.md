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
| 控制中心 | 手电筒、Wi-Fi、蓝牙、飞行、蜂窝 | AVFlashlight、SBWiFiManager、BluetoothManager、SBAirplaneModeController、CoreTelephony |
| 控制中心 | 勿扰、深色模式 | DNDStateService + DNDToggleManager、UIUserInterfaceStyleArbiter |
| 控制中心 | 亮度增减、音量增减 | UIScreen 每次 0.1（钳制 0–1）、SBVolumeControl 每次一档 |

共 24 项。控制开关反转当前状态，Wi-Fi/蓝牙对应系统开关，不承诺与控制中心
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

## 本次开发结果（3.9.3）

源码审查与 `git diff --check` 通过；49 项系统/面板辅助逻辑、187 项手势/几何/文本
检查通过，Darwin 通道及既有敏感 URL 调度回归通过。`./build.sh` 完成两套包，
均包含 arm64/arm64e，设置资源、导出执行器、控制器类、plist 与安装卸载脚本语法检查通过。
control 的既有 firmware>=14.0 元数据未变；实际 Mach-O deployment 为 ios16=16.0、ios17=15.0，
沿用构建脚本的配置，并不宣称这些旧系统运行时受支持。

未安装到设备，冷/热启动、系统控制器是否存在、权限、动作实际效果、确认框可见性，
以及 Spotlight 远程键盘的显示/命中测试均未验证。源码/构建通过不代表这些项目通过。
