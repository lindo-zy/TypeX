# 桌面状态栏 4.2.10 仍无反应：窗口宿主解析修复

问题：4.2.10 安装后桌面状态栏左/中/右仍无操作、无震动。本轮全程未连接或操作设备（用户要求纯静态分析），依据本地 UIKit 语义实证与 SquidGesturePro 2.7.6 逆向参照定位。

起始状态：集成分支 `dev`，HEAD `0e5d1ec`，保留未跟踪 `.zcodeignore`。开发工作树 `codex/statusbar-desktop-window-host`，合入后仅以 `./build.sh` 构建。

## 根因及证据边界

4.2.10 的桌面安装路径把宿主窗口读作 `anchor.window`，而桌面接收器本身就是 `SBHomeScreenWindow`。真实 UIKit 中该读数恒为 nil，安装函数在第一道门槛就返回，桌面识别器从未装上——触摸因此无 `touch`/`rejected`/震动等任何日志，与设备症状一致。

证据（本机 macOS 26 Catalyst UIKit 探针，与 iOS 同源 UIKitCore）：

1. `UIWindow` 未重写 `window`：与 `UIView` 的 `-window` 为同一 IMP。
2. `-[UIView window]` 机器码为纯 ivar 读取（nil 判空 → `adrp/ldrsw` 取 ivar 偏移 → `ldr x0,[x0,x8]`），无任何 UIWindow 特判。
3. 以 `_initWithFrame:debugName:scene:attached:`（attached=YES）完成初始化后，实例偏移 64 的 `_window` ivar 仍为 nil。
4. Apple 现行文档只写 "nil if the view has not yet been added to a window"，对 UIWindow 接收者无返回自身的表述。

测试替身把 `window` 建成普通存储属性、夹具逐一手工赋值 `window.window = window`，替身语义与真机相反，掩盖了该缺陷（旧断言 `desktop touch window owns a status-bar gesture set` 在真机语义下不会成立）。

参照（SquidGesturePro 2.7.6，`/Users/xiao/Downloads/squid`）：其状态栏三分区五手势骑在系统自身的状态栏分发点上（hook `statusBarGesture:`、`_statusBarScrollToTop:` 并向该类补挂 `sg_singleTap:` 等方法，类名经加密串运行时解密，未还原具体类），全程不依赖 view→window 反查。TypeX 的窗口级识别器方案保留，仅修掉对 `UIView.window` 的依赖。

## 实现及修改边界

- `DXInstallStatusGestures`：宿主解析改为 `hostWindow = anchor.window`，`homeScreen` 且为空时回退为 `anchor` 自身（此时 anchor 必为窗口）。门控、owner 关联对象、去重比较、`handler.window`、识别器挂载与 installed 日志统一使用 `hostWindow`。aperture（视图 anchor）与普通状态栏路径读数不变。
- 新增替身测试：不赋值 `window.window` 的 `SBHomeScreenWindow` 扫描后可安装、出现回调后可用、接受已配置触摸——把真机 UIKit 语义固化进回归。

不修改的部分：绑定格式、设置持久化、跨进程协议、动作/面板执行器、Dock、键盘、其他插件。UI 工作仍在主线程，诊断只写 syslog。

## 本地验证

- `python3 tests/run-statusbar-gestures.py`：配置/区域/动作 174 项，生产处理器 553 项（原 550 + 本轮 3 项），生产转发/发送 22 项通过。
- 关联回归退出 0：状态栏设置 1556 项；面板注册表 45 项；手势/几何/识别器 12/25 项；设置资源 4508 项；Dock 处理器 61 项；全局面板 79/22 项；Darwin 通道；敏感 URL 执行器。
- 平台替身不运行真实 UIKit 仲裁或 SpringBoard 注入；真机的窗口层级、hitTest 与窗口宿主语义仍属设备验收。

## 设备验收（待执行）

1. 安装对应包并注销，直接在桌面（勿先进设置）点状态栏左/中/右；已配置槽位应有震动并执行一次。
2. 预期日志出现 `installed host=SpringBoard view=SBHomeScreenWindow window=SBHomeScreenWindow` 与 `desktop visible=1`。
3. 若仍无反应：无任何日志 = 触摸落点窗口仍不在覆盖范围（需补窗口清单诊断）；有 `rejected ... gate=...` = 按门控名继续定位；`home-statusbar` = SB 进程内未找到可见实际状态栏锚。

## 交付状态

源码分析：已确认 `UIView.window` 对窗口自身为 nil 导致桌面安装被拦截；Catalyst 探针实证，真机 SpringBoard 最终运行时行为以安装后日志为准。
