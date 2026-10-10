# 基础动作 PixPin 截图

问题：基础动作的工具分组缺少 PixPin 截图，用户需要直接绑定区域截图。
根因：现有 PixPin 接入仅作为自定义系统动作，基础动作生成器没有对应选择器。
涉及文件：DXShortcutsGenerator.h/.m、DXCollectionView.h/.m、中英文 Localizable.strings、README.MD。
修改边界：仅 TypeX 基础动作注册、可见性和执行；复用 DXPixPinIntegration.h。
实现方案：增加 pixpinScreenshotAction:，名称 PixPin 截图、SF Symbol crop，位于 ShellX 截图之后；
isVisibleShortcutSelector: 动态探测 RootHide 路径下的 PixPin.dylib，供设置、选择器、工具栏及执行路径共同过滤。
不修改的部分：PixPin 工程、其 URL/兼容通知、现有系统动作协议和截图完成/取消流程。
运行时风险：安装文件存在不代表 SpringBoard 注入成功；PixPin 关闭或忙时可忽略请求，公开通知没有完成回执。

## 执行路径

- UI 操作仅在主线程，窗口可用且未隐藏时执行。
- 调用 DXPostPixPinSystemAction(@"pixpin-area", ...)；安装再次检查后，只发送一次
  com.pixpin.screenshot/capture/area Darwin 通知，无 URL Scheme 或兼容广播。
- 现有“截图时隐藏键盘”开关默认关闭，关闭时立即发通知。
- 开启时，检查 UIKeyboardImpl activeInstance/dismissKeyboard 能力，收起后等待 0.35 秒；不恢复键盘。
- 等待期间同一工具栏重复触发被忽略；回调使用弱工具栏引用、请求代次和来源 Window/Scene 检查。
  键盘收起导致工具栏暂时离开窗口属于正常情况；宿主换窗口或场景退出则取消发送。
- 发送器 syslog：[TypeX][PixPin] request id=pixpin-area notify-status=0。
  状态 0 只表示发送成功，PixPin 实际处理见其 external request/capture request accepted 日志。
- 接收端由 PixPin 自身处理总开关、模式开关、忙碌拒绝和选区取消；TypeX 不重试、不等待完成。

## 源码依据

参考本地 PixPin cf5e007（只读）：Sources/Common/PXConstants.m、
Sources/SpringBoard/PXSpringBoardEntry.xm、Sources/Capture/PXCaptureCoordinator.m。
区域通知注册在 SpringBoard，接收后切主线程并分派 PXCaptureModeArea。
TypeX 开发基线 dev/ebfe25e，工作区干净，隔离分支 codex/pixpin-basic-screenshot。

## 宿主检查

- 临时 Foundation harness 执行生产 DXShortcutsGenerator：37 项并行数组对齐，
  新动作位置、图标、长短名称和工具分组正确；文件不存在、目录冒名、安装及卸载的动态筛选通过。
- run-system-actions.py：原生 PixPin 通知名称、安装过滤、一次发送、失败路径及现有系统动作测试通过。
- run-statusbar-settings.py：1556 项设置控制器检查通过（UIKit/Preferences 替身）。
- run-settings-ui.py：4508 项设置搜索/布局检查通过；中英文 Localizable.strings 的 plutil 检查通过。
- 这些检查不验证真实 iOS Window/Scene、隐藏键盘时机、框选界面或安装/卸载。

## 双包审查

- 本地合并至 dev/f4b0208 后运行唯一入口 ./build.sh，双平台成功，control 自动从 4.4.7 推进至 4.4.8。
- com.lindo.typex，iphoneos-arm64e；两包的 TypeX 和 TypeXPrefs 均包含 arm64/arm64e。
- 两套产物沿用脚本的 iPhoneOS16.5 SDK；ios16 部署目标 16.0，ios17 部署目标 15.0。
- 解包确认新动作选择器、区域通知名、两种语言名称、UIKit/SpringBoard 注入配置。
- postinst/postrm 与源码一致且具有可执行权限；设备安装和卸载行为未验证。
- ios16 SHA-256：4b9763d0a77d1bd21048d2c0283995b60191ae43677e8596f6a645b8558c943f。
- ios17 SHA-256：4295b407ca24d7ed4a7a3703d6f62e2fb591cbace918d5ae7758bac7a401952e。
- 构建退出码 0；Bark 已发送 typex-4.4.8-构建完成。

## 设备验收（尚未执行）

1. iOS 16/17、arm64/arm64e 安装相应 TypeX 包并重新加载 SpringBoard；冷启动目标 App 弹出键盘。
2. 安装 PixPin 时，在基础动作 → 工具看到 PixPin 截图；绑定顶部/底部按钮、手势或子动作。
3. 关闭隐藏键盘：点击后进入区域框选；确认收到上述原生区域通知，并检查选区确认及取消。
4. 开启隐藏键盘：点击后键盘收起，再出现区域框选；取消截图后键盘不会自动恢复。
5. 快速重复点击、PixPin 忙碌/关闭、切后台、关闭宿主：无重复等待、无崩溃、无延迟误触发。
6. 卸载 PixPin，重新打开设置及键盘：候选目录和已配置按钮不显示，旧引用不会发请求；重新安装后可再次选择。
7. 热启动重复步骤 2–5，并回归 ShellX 截图、AI 问答、剪贴板和小把手；安装/卸载也需实机确认。
