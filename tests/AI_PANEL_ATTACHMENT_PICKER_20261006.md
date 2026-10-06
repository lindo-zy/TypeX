# AI 面板空会话下相册/文件选择器无法打开

问题：AI 面板打开后（会话为空），点「+」→ 相册/文件毫无反应；完成过一次对话后才可用。即面板打开时就应能直接使用图片和文件附件。

根因：`presentModalController:`（DXAIPanel.m）为呈现选择器主动 resign 面板输入框；这次收键盘同步触发 `UIKeyboardWillHideNotification`，`hideIfEmptyOnKeyboardHide` 在会话为空（无消息、非流式、非聚焦过渡）时执行 `closeAndDestroyPanel` 把面板窗口整体销毁，随后的 `presentViewController:` 落在已脱离窗口层级的控制器上被 UIKit 静默拒绝——选择器永远弹不出来，无崩溃无提示。完成过一次对话后 `messages.count > 0`，同一信号走 `pinnedAfterKeyboardHide` 钉扎保留分支，故表现为「必须完成一次对话附件才可用」。SB 承载路径打开即自动聚焦必现；进程内路径用户点过输入框（打字前正常动作）必现。

基线：dev，6561bf0（4.3.5），工作区干净。隔离分支 dev-ai-attachment-picker。

涉及文件：DXAIPanel.m（仅此一个文件）。

修改边界：只豁免「模态选择器呈现期间」的空会话键盘收起联动；不改空面板随键盘关闭的常态行为、附件 chip 管线、SB/进程内两条入口、模型/人设菜单。

实现方案：

1. 新增 `presentingAttachmentPicker` 标志；`presentModalController:` 在 resign 前置位（WillHide 在 resign 内同步到达，必须先置位）。
2. `hideIfEmptyOnKeyboardHide` 置位期间直接返回：自导收键盘 ≠ 用户收键盘。
3. 键盘 frame 变化观察者同步豁免：呈现转场期间不做 hide 方向重定位，避免卡片在转场画面后坠向悬空位。
4. 四个选择器 delegate 回调收尾清除标志：PHPicker 完成与取消（下滑取消走 `didFinishPicking` 空结果）、相机完成与取消、文件完成、文件取消（下滑走 `wasCancelled`）。
5. `textViewDidBeginEditing` 兜底清除：用户能重新聚焦输入框，全屏模态必然已不在，防陈旧标志导致空面板永不随键盘关闭。

不修改的部分：关闭按钮/写回宿主等销毁路径、附件管线（updateAttachedImage/pendingFileText）、相机入口隐藏策略、其他面板与协议。

运行时风险：选择器回调覆盖面基于框架文档语义（PHPicker 取消=空 results、UIDocumentPicker 下滑取消=wasCancelled），真机行为待验收；若出现无回调异常路径，后果仅是空面板不再随键盘自动关闭，关闭按钮仍可手动关。

验证：`git diff --check` 通过；既有回归全绿（global-panels、dock-gestures、panel-controls、panel-registry）；DXAIPanel 无既有替身测试，本次未新增测试框架。构建后从 ios17 包内 TypeX.dylib 提取字符串确认 `setPresentingAttachmentPicker:` 已编入产物。

发布前核验：修复以 `d0ccf16` 提交、`dedd8cb` 合入 `dev`；随后唯一入口 `./build.sh` 双目标成功，版本自动推进 4.3.5 → 4.3.7（本次核验中重复执行了一次构建脚本，版本多推进一档，两包源码一致），Bark 通知成功。两包均为 com.lindo.typex / 4.3.7 / iphoneos-arm64e，依赖 firmware >=15.0；postinst/postrm 存在，tweak 与设置二进制、过滤器、本地化资源齐全。安装/升级/卸载仅静态审查，未实机执行。编译仅有既有链接器 `-multiply_defined is obsolete` 警告。

SHA256：

- ios16：`3432c8e92eb0d1971c75f7f21d456ac64bd2017bbf0169f6507f33d9a46aa750`
- ios17：`4689c0ee30b701590a53b10c8286e43d1001e977e507eb6d6e843aaf10ebf834`

设备验收（iOS 16/17）：

1. SB 承载（第三方键盘来源）：打开 AI 面板后不输入任何文字，直接点「+」→ 相册，选择器应弹出；选图后 chip 出现，可直接发送；文件路径同样验证。
2. 进程内承载（宿主 app 内打开）：同上，特别是先点过输入框再点「+」的路径。
3. 相册/文件选择器取消（含下滑）：面板保留、状态正常，可再次打开。
4. 空会话下面板随键盘手动收起而关闭的常态行为不变；完成一次对话后的钉扎行为不变。

源码分析：上述关闭路径与修复策略已确认。编译：已确认。包结构：已确认。核心功能、冷/热启动：未验证，需执行上述设备验收。
