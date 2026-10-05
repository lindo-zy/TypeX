# 桌面状态栏 4.3.2：识别器改挂状态栏视图（参照 SquidGesturePro）

问题：4.3.0 设备验收桌面状态栏首次点击生效、后续失效。本轮全程未连接设备（用户明确无设备链接），依据本地 SquidGesturePro 2.7.6 反汇编实证定方案并实现。

## 根因定性（架构级）

4.3.0 桌面路径的全部闸门（key/homeVisible、锁定/面板、锚点可见性、prefs、scene、几何）都是实时求值，静态审查无闩死点；失效根源是**自管簿记架构本身**：窗口级识别器 + `DXHomeStatusAnchor` 跨窗口锚点解析 + homeVisible/弱表状态，第一次触发的面板 episode 足以搅动状态栏实例/窗口/桌面 key 状态中的任一项，第二次即倒在某个 `gate=`。修复方向不是补某个闸门，而是消灭簿记面。

## 参照实现（SquidGesturePro 2.7.6 反汇编，~/Downloads/squid/main_disasm.txt）

- %ctor 解密类名取状态栏视图类，`MSHookMessageEx statusBarGesture:`（系统自家分发点）+ guard-hook `initWithStyle:`；
- `initWithStyle:` hook 里 %orig 后给 **bar 视图自身** addGestureRecognizer 五识别器（single tap / double tap + `requireGestureRecognizerToFail:` / 左右滑 / 长按），action 为 `sg_singleTap:` 等补挂方法（0x63120–0x63440 区段逐一确认）；
- 识别器随视图生死，实例替换由系统构造路径自动重挂——**零扫描、零窗口宿主解析、零生命周期标志**，天然免疫「一次之后失效」。

## 实现及修改边界

- `DXStatusBarGestureHooks.xm`：五识别器从宿主窗口改挂**状态栏视图本身**；安装去重改「有 handler 即保留+refresh」（识别器随视图迁移，无需重装）；删除桌面 SBHomeScreenWindow fallback、`DXHomeStatusAnchor`、homeVisible/homeAppearanceKnown、`DXStatusBarHomeScreenDidAppear/WillDisappear` 及 TypeX.xm 联动；aperture 灵动岛路径保持窗口级识别器与安装期 window 语义；session 保留 window 字段维持窗口切换取消在途会话；每触摸实时闸门与原生手势优先级 delegate 原样保留。
- `tests/DXStatusBarGestureHandlerTests.m` / `UIKitStatusBarGestureStub.h`：窗口级计数断言全改视图级；桌面 fallback 用例替换为**桌面实例轮换回归**（独立显示窗口、替换实例、陈旧会话取消、SB 闸门）。

不修改部分：绑定格式、设置持久化、跨进程协议（TypeXSB）、面板执行器、Dock、键盘。

## 本地验证

- `python3 tests/run-statusbar-gestures.py`：配置 174 项、生产处理器 473 项（视图级断言+桌面轮换回归）、通道 22 项通过。
- 全部 14 个测试 runner 通过（dock/gesture-actions/global-panels/panel-controls/panel-registry/settings/statusbar-settings/system/text/javascript/sf-symbol/sensitive-url/darwin-open-channel）。
- `./build.sh` 双目标成功，4.3.1 → 4.3.2，Bark 完成通知已发送。

## 已知限制与设备验收（待执行）

1. 桌面顶部命中改为依赖状态栏视图自身 hit-test——SGP 同架构桌面可用（其状态栏手势为产品功能），风险低但属设备验收项。
2. 验收步骤：安装 4.3.2 并注销，桌面连续点状态栏 ≥5 次（每次间隔随意，中间可开关一次面板），每次都应触发；预期日志 `installed host=SpringBoard view=<状态栏类> window=<宿主窗口类>`，每次点击 `touch`/`trigger`/`result` 成对出现且**无 `rejected ... gate=`**。
3. 若出现 `gate=lock/panel` 在面板已关闭时：面板窗口 hidden 未复位的独立缺陷，另立案。
4. 平台替身不运行真实 UIKit 仲裁与 SpringBoard 注入；窗口层级、hitTest 与实例替换时序仍属设备验收。

## 交付状态

源码分析：已确认（SGP 反汇编 + TypeX 全链路静态审查）；编译：已确认；包结构：已确认（4.3.2 双 deb）；核心功能：未验证（设备验收待做）。
