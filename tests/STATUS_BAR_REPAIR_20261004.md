# 状态栏手势失效：本轮分析与修复

问题：用户确认 iOS 16 设备上，主屏幕及 App 内的左／中／右状态栏均无法呼出对应操作。本轮没有在这台 iOS 16 设备上复现，不能把下面的源码缺陷等同于设备失效的全部原因。

起始状态：集成分支 `dev`，HEAD `12fe3c50dc02f02d28684d9d3a3d31e89c04a72b`；保留未跟踪的 `.zcodeignore`。开发工作树为 `codex/statusbar-lifecycle-repair`，最终包必须在本地合入 `dev` 后由 `./build.sh` 生成。

## 调用链与运行边界

`TypeX.xm` 构造函数在 SpringBoard／App 中启动 `DXStartStatusBarGestures`；主队列注册已存在且 ABI 合法的状态栏类 Hook，扫描真实视图并在所属 UIWindow 安装识别器。触摸起点按实际状态栏宽度分区；配置、锁屏／活动状态、窗口／Scene、横屏和原生控件门通过后创建触摸会话。

识别回调重新校验会话，转发 `slot + observed selector + landscape`。SpringBoard 的 `DXSystemOpenBroker` 在主队列重读配置并检查绑定、锁屏、已打开面板和 1.5 秒有效期，再调用现有全局动作或手势面板执行器。App 不直接操作 SpringBoard 私有对象，也不使用其他 App 的输入框。

未配置／关闭槽位不接管原生操作；配置变化、窗口迁移、接收容器移除、App／Scene 失活时旧会话不能执行；一次会话只派发一次。私有类用 `NSClassFromString` 与继承关系检查，不新增未经检查的私有方法调用。所有 UI 工作均在主队列。

## 根因与修复

| 源码缺陷 | 旧行为及证据 | 本轮处理 |
| --- | --- | --- |
| 原生状态栏动作识别器未参与仲裁 | 只让 `UITapGestureRecognizer` 等待 TypeX；`_UIStatusBarActionGestureRecognizer`／`STUIStatusBarActionGestureRecognizer` 直接继承 `UIGestureRecognizer`，绕过这个分支。新增生产方法测试在旧代码上以 `UIKit status action waits for each configured gesture` 失败。 | 对这两个经过运行时类型检查的状态栏识别器，为当前区域已配置、有效的单击／双击／长按／横滑设置动态失败优先级；其他系统识别器不套用这条规则。 |
| 冷启动配置恢复不刷新已有识别器 | 安装时偏好暂不可用会关闭所有识别器；后续启动扫描遇到已有 handler 直接返回，启动完成路径也不刷新，使一次暂时不可用可持续表现为全部手势失效。 | 每次生命周期扫描先在偏好不可用时重读，再刷新已有 handler；加入 Scene 连接／激活触发，扫描 `connectedScenes` 的窗口和传统窗口集合。无重试定时器。 |
| 内层先安装后被包入外层留下两套识别器 | 内层先 `didMoveToWindow`，随后外层安装／重挂载时仅检查外层关联对象，没有清理内层旧 handler，造成同一状态栏的重复识别与竞争。 | 外层安装或复用前清理其后代状态栏旧 handler，包括从另一窗口移入的情况；关闭旧识别器、清除 delegate／会话并从旧窗口移除。 |
| 灵动岛 handler 生命周期仍依赖首次容器 | 按窗口去重但 handler 仍关联在首次容器上；新容器被去重跳过，首次容器脱离／释放时会拆掉唯一识别器。旧测试强持有 handler，且把拆除当成正确结果。此项与用户此次普通 iOS 16 状态栏反馈分开记录。 | 窗口持有唯一岛 handler；新触摸动态找到当前容器，原生单击仲裁也使用当前接收容器。首次容器释放不拆除窗口识别器，窗口释放时 handler 正常释放。已开始的触摸若接收容器隐藏／移除则取消。 |

私有类结构参考：[UIKit 状态栏动作识别器转储](https://github.com/MTACS/iOS-17-Runtime-Headers/blob/main/PrivateFrameworks/UIKitCore.framework/_UIStatusBarActionGestureRecognizer.h)、[SystemStatusUI 动作识别器转储](https://github.com/MTACS/iOS-17-Runtime-Headers/blob/main/PrivateFrameworks/SystemStatusUI.framework/STUIStatusBarActionGestureRecognizer.h)。这些 iOS 17 转储支持类结构判断，不证明用户的 iOS 16 设备类存在或触摸竞争；当前系统类缺失时由运行时检查跳过。

涉及文件：`DXStatusBarGestureHooks.xm`、生产处理器测试及 UIKit 替身、本分析记录和状态栏验收入口。

修改边界：状态栏识别器的仲裁、安装／解绑、窗口所有权和生命周期恢复。

不修改的部分：配置键／绑定格式、设置选择与持久化、跨进程协议、动作执行器、面板、Dock、键盘及其他插件。

## 本地验证

- `python3 tests/run-statusbar-gestures.py`：配置／区域／请求策略 174 项，生产处理器／安装／扫描 457 项，生产转发及发送 22 项通过。
- 新增普通状态栏三分区五手势与两类原生动作识别器的优先级检查；未配置区／原生控件不取优先级；延迟配置恢复、仅 Scene 持有的窗口扫描、已有外层下的重新挂载、跨窗口旧识别器清理。
- 新增灵动岛当前容器的原生单击仲裁、隐藏／脱离取消、首次容器真实释放后继续响应，以及窗口释放无 retain cycle。真实释放检查使用弱引用和 autoreleasepool，不强持有被测 handler。
- 关联回归全部退出 0：状态栏设置 1556 项；Dock 策略／处理器 50／61 项；全局面板策略／触摸 79／22 项；面板注册表 41 项；通用手势／键盘几何／工具栏识别器 141／12／25 项；面板控制 6278 项；设置资源／布局 4508 项；系统动作；Darwin 独立进程请求／回复、状态栏载荷、去重、过期、超时及清理。

上述 UIKit／Preferences 用平台替身，Logos 注册用记录替身；Darwin 通道运行在 macOS。它们不能验证真实 iOS 注入、原生仲裁时序、系统窗口命中或沙盒通知权限。

## 设备验收与预期日志（待执行）

1. 安装对应系统包，注销后先在主屏幕触发，再进入设置、Safari、微信测试；不能只在打开设置后测热路径。重启／重新越狱后的冷路径也需复测。
2. 在设置中开启 TypeX、状态栏总开关，并为 15 个槽位分别开启和绑定可辨认动作。分别测试左／中／右单击、双击、长按、左滑、右滑；每次只能执行一次。
3. 同区单击与双击同时开启时，双击不附带单击；长按不附带点击，横滑按起点归属。关闭／清空／删除动作后相应区域恢复原生操作，竖向下拉保持正常。
4. 锁屏解锁、App 切换、面板开关、旋转、配置修改或容器重挂载后新手势仍可用；中途失效的旧手势不能延迟执行。横屏必须显式开启；隐藏状态栏不能触发。
5. 若为灵动岛设备，分别测试容器切换和实时活动；未配置中区单击时原生单击仍有效。刘海切口无法触摸。

syslog 只记录模块、宿主、槽位、类名和状态，不写设备日志文件或动作载荷：

```text
[TypeX][StatusBarGesture] hook host=... class=...
[TypeX][StatusBarGesture] installed host=... view=... window=...
[TypeX][StatusBarGesture] config host=... available=1 enabled=1 slots=...
[TypeX][StatusBarGesture] touch host=... slot=...
[TypeX][StatusBarGesture] priority host=... slot=... native=...
[TypeX][StatusBarGesture] trigger host=... slot=...
[TypeX][StatusBarGesture] dispatch slot=...
[TypeX][StatusBarGesture] result host=... slot=... status=...
```

无 `hook／installed` 查进程注入与真实类／窗口；`available=0` 查共享偏好，`enabled=0／slots=0` 查总开关、槽位和绑定；只有 `touch` 没有 `trigger` 查仲裁／会话；`dispatch rejected` 或失败 `result` 查 SpringBoard 门禁／执行能力。`priority` 仅在遇到相应原生竞争者时出现。明确拒绝条件见 `rejected ... gate=...`。

运行时风险：尚未取得用户 iOS 16 故障设备的实际触发日志；原生系统状态栏竞争和触摸所在窗口必须真机确认，尤其第三方状态栏插件可能改变视图／手势结构。不得将这些源码修复描述成该设备已验收。

## 交付状态

源码分析：已确认四处源码缺陷；用户故障设备的完整运行时根因未确认。

源码提交 `7ad350e` 与 SDK 通知名称更正 `9072efe` 已本地快进合入 `dev`。首次构建因误用不存在的 `UISceneDidConnectNotification` 失败；按本地 SDK 的 `UIScene.h` 改为 `UISceneWillConnectNotification` 后，仅通过 `./build.sh` 重跑，两目标成功，版本从 4.2.7 自动推进至 4.2.8，Bark 完成通知已发送。失败构建没有推进版本。未推送代码。

编译：已确认 iOS 16／17 两目标成功。包结构：已确认 `com.lindo.typex / 4.2.8 / iphoneos-arm64e`；依赖沿用 `firmware(>=15.0)`。Tweak 和 Preferences 均含 arm64／arm64e，iOS 16 包最低系统为 16.0，iOS 17 包按既有构建脚本为 15.0。注入过滤器、PreferenceLoader 资源、修复符号及安装／卸载脚本的内容、可执行权限和语法均已核对。

| 目标 | 构建产物 | 字节数 | SHA-256 |
| --- | --- | ---: | --- |
| iOS 16 | `packages/ios16/com.lindo.typex_4.2.8_ios16_iphoneos-arm64e.deb` | 1155402 | `5b67897ed59f8c4b9ec99515e6479b36f9aa5cd84bfc3c4dea60d398e57c2275` |
| iOS 17 | `packages/ios17/com.lindo.typex_4.2.8_ios17_iphoneos-arm64e.deb` | 1163674 | `75833b1137d1fa93052640f2b96cf63685a222c58ed97cb1755d8de245a155c5` |

核心功能、安装／卸载、冷／热启动：未验证。包和本地测试成功不等于用户 iOS 16 故障设备已修复。
