# 自定义动作设置页闪退回归

## 问题与源码证据

入口：设置 → TypeX → 自定义动作，目标是 Preferences 进程中的
`DXPCustomActionsController`。UI 回调沿用 UIKit 主线程生命周期。
本次以 `dev` 的 `a86aa4c`（4.6.7）为基线，初始工作区干净。

根因：管理页继承的 `viewWillAppear:` 先读取新动作数组并立即
`reloadData`，子类随后才重建分组索引。此时旧索引可以越过新数组的边界。
搜索结果也保存全局索引，需要在数据变化时重新匹配。
本机使用真实控制器源码和同步渲染测试桩，复现了
`actionCellForRowAtIndexPath:global:table:` 的 `NSRangeException`。
这证明该源码路径会越界，尚不能证明用户本次设备闪退命中同一条栈。

另外，管理页曾在基类建表后再替换整个表，数据源在 cell 配置完成前就已连接；
普通动作行还为同一行先 dequeue 占位 cell，再 dequeue 实际 cell。
本次统一表初始化顺序，并让每个行请求只获取实际返回的 cell。

涉及文件：`DXPCustomActionViewController.h/.m`、
`DXPCustomActionsController.m` 及管理页测试。
修改边界：表初始化、偏好重载后的显示索引、搜索索引和 cell 获取。
动作执行、动作存储协议、其他插件、SpringBoard 和键盘运行时不在修改范围。

实现方案：基类在连接数据源前调用可覆写的 cell 配置入口；管理页复用这张表，
在 `reloadPreferences` 返回前重建分组和搜索映射，再由基类刷新一次。
映射读取检查当前数组边界，过期行返回占位 cell。

运行时风险：共享基类的初始化顺序会影响动作选择页，需同时回归选择器；
真实 Preferences 导航、搜索呈现与其他插件的交互仍需设备验收。
不增加 Observer、Timer、跨进程协议或设备日志文件。

## 本机验证

执行 `python3 tests/run-custom-actions-page.py`。
测试桩使用实际注册类实例化 cell，并可在连接数据源和 `reloadData` 时
同步请求所有行；它不模拟 UIKit 的绘制或系统导航。

- 已有管理页从 3 个动作重载为 0 个，再恢复，刷新时不越界。
- 初次加载已有分组和未分组动作，分区在首次渲染前准备完成。
- 搜索保持开启时重载更短数组或空数组，结果索引重新匹配。
- 动作行只获取一个 Subtitle cell；异表渲染仍有按实例注册保护。
- 共享选择器、编辑保存、添加、批量添加、分组、搜索和删除路径继续可用。

其他回归：`run-action-groups.py`、`run-batch-apps.py`、
`run-gesture-actions.py`、`run-panel-registry.py`、`run-settings-ui.py`。
最终双平台包只由项目根目录的 `./build.sh` 构建。

## 设备验收（未执行）

在 iOS 16 和 iOS 17、对应 arm64/arm64e 设备上分别验收：

1. 安装对应构建包，结束设置进程后重新打开 TypeX → 自定义动作。
   空动作、仅未分组、已有多个分组三种配置都应正常显示。
2. 返回 TypeX 首页后重复进入 10 次；打开一个动作编辑器，保存和取消后返回，
   页内动作数量、名称、分组应正确，设置不闪退。
3. 搜索一个动作，编辑名称使其不再匹配，返回后应显示更新的搜索结果。
   清空搜索恢复完整分组；删除最后一个动作后应显示占位行。
4. 回归工具栏/手势/子动作中的动作选择器，选择和添加入口应可用。

首次加载预期 syslog：`[TypeX][CustomActions] load actions=… groups=…`，
只记录数量，不记录动作名称、链接或内容。
源码测试和 DEB 检查不代替真实设备的冷启动、热启动、安装卸载及导航验收。
