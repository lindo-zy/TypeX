# TypeX JavaScript 自定义动作

在“自定义动作”添加 JavaScript，填写名称、图标和源码，再绑定到原有顶部/底部按钮、手势或子动作。既有动作类型、标识、存储和打开应用通道保持不变。新动作仍保存在 `linkactions`，用 `type=javascript`、`script`、`jsInput`、`jsOutput` 描述；不对源码执行 `@@@` 或文本模板替换。

## 支持范围

入口为 `async function main(str)`；同步返回也能处理。每次触发创建独立 JavaScriptCore 上下文，菜单调用 `function` 时保留该上下文。没有 DOM、Node.js、fetch 或 setTimeout；网络请使用 `$http`。

| 接口 | 行为 |
| --- | --- |
| `$http.get/post/put/patch/delete({url, headers?, body?})` | 返回 Promise，成功值为 UTF-8 响应正文字符串。JSON 自行 `JSON.parse`；body 必须是字符串，可用 `JSON.stringify`。只接受 HTTP(S)。非 2xx、传输错误、超时、非法参数和非 UTF-8 响应会 reject。 |
| `$url.open(url)` | 复用 TypeX 普通 URL/Scheme 通道；敏感 Scheme 复用既有 SpringBoard 通道。无返回值。 |
| `$url.openInApp(url)` | HTTP(S) 复用应用内浏览器，其余 Scheme 走外部打开。无返回值。 |
| `$app.open(bundleID)` | 复用现有应用启动通道。无返回值。 |
| `console.log/error(...)` | 测试页内存日志；不把输入、源码、响应、令牌写入设备日志文件或 syslog。 |

首版不实现图片/二进制响应、上传、流式响应、文件、`$pb`、`$kb`、`$md5`、`$base64`、`$util` 和旧式 `type: 'js'`。因此这是 SE 接口的明确子集，不承诺全部 SE 脚本兼容。HTTP 运行于当前宿主进程，受其网络环境/ATS 等限制；不继承宿主的 Cookie、凭据存储或 URL 缓存。

## 输入与输出

- 选区优先：有选区取选区，否则取全文；全文：始终取全文；剪贴板：读取一次剪贴板文字。
- 替换：替换脚本输入对应的选区/全文；剪贴板模式替换当前选区，空选区则在光标处插入。
- 插入：按当前选区写入，空选区即光标处插入；复制：只写剪贴板。
- 密码框、未完成的输入法组合文本、不提供完整 UITextInput 能力的输入代理不执行脚本；不会降级为清空全文。
- 脚本返回有效字符串前不修改原文；空字符串是有效替换结果，`null/undefined` 表示不写入。
- 原 responder、文本、选区、工具栏窗口和 Scene 必须仍有效。键盘隐藏、App 失活、方向变化、目标编辑通知、快照变化、重复动作会取消旧会话；网络传输随会话取消。网页代理的变化还使用定时快照核对，无法保证观察到两次采样间发生又撤回的所有编辑。
- 首个有效导航为终点，关闭脚本会话后派发一次。`$url.open(...)` 后的结果不会再写入；不支持同一脚本连续打开多个 App。不会因目标插件吞掉 completion 而重试。

## 返回值

- 字符串 → `txt`。
- `{type, content, title?, args?}`：`content` 必须为字符串；`title` 默认使用内容。`type` 支持 `txt/url/urlInApp/app/function`。
- 字符串数组或上述字典数组：0 项无操作，1 项直接执行，多项打开不抢键盘焦点的候选菜单；混合的有效字符串/字典也支持。整个返回数组验证通过后才处理。
- `function`：`content` 指向脚本全局函数名，`args` 为可 JSON 序列化数组；支持异步及上述所有返回值，最多后续调用 16 次。
- 对象、数字等其他返回值报错。不会隐式写入 `[object Object]`。

## 使用示例

```js
async function main(str) {
    return str.replace(/\s+/g, ' ').trim();
}
```

```js
async function main(str) {
    return [
        {type: 'txt', title: '大写', content: str.toUpperCase()},
        {type: 'url', title: '搜索', content: 'https://www.bing.com/search?q=' + encodeURIComponent(str)},
        {type: 'function', title: '查询公网 IP', content: 'lookup'}
    ];
}
async function lookup() {
    const raw = await $http.get({url: 'https://httpbin.org/get'});
    return JSON.parse(raw).origin;
}
```

```js
// 示意接口：替换成自己的服务。请求真实发送，测试页也一样。
async function main(str) {
    const raw = await $http.post({
        url: 'https://api.example.com/resolve',
        headers: {'Content-Type': 'application/json'},
        body: JSON.stringify({text: str})
    });
    const result = JSON.parse(raw);
    return {type: 'url', content: result.url};
}
```

## 限制与清理

脚本最多 131072 个 UTF-16 单元；输入最多 1 MiB 个 UTF-16 单元；HTTP 请求体/响应体、序列化结果各最多 1 MiB，候选最多 100 项。单会话 HTTP 最多 32 次、同时最多 8 次。每次 JS 进入 VM 的 CPU 时间限制约 0.5 秒；每轮异步调用总期限 30 秒，交互会话最多 120 秒。上下文和网络传输在结束时释放。

CPU 限制使用运行时查找的 `JSContextGroupSetExecutionTimeLimit`；接口缺失则拒绝运行。JS 计算在独立队列，UIKit 只在主线程。仍为进程内引擎，没有独立进程的硬内存隔离；不要把它当成不可信脚本的安全沙盒。超大 JS 内存分配仍可能影响宿主。

## 验证

宿主引擎测试：`python3 tests/run-javascript-engine.py`。直接编译生产引擎，使用真实 JavaScriptCore 和本地 HTTP 服务，覆盖文本、数组、函数参数、Scheme 传参、五种 HTTP 方法、请求头/JSON、HTTP 错误、非法请求、二进制/超大响应、语法/Promise 错误、死循环中断、函数递归限制、取消后的晚到结果。不会连接外部接口或打开 App。

已有打开动作回归：`python3 tests/run-darwin-open-channel.py`、`python3 tests/run-sensitive-url-executor.py`。这些验证跨进程通道/调度，不代表设备 URL 或 App 行为已经验证。

只用项目 `build-roothide-ios.sh` 打包。`TYPEX_SKIP_BUILD_NOTIFICATION=1` 可在本地验证时关闭构建通知，不修改既有通知配置；普通调用默认行为保持原样。

设备验收（iOS 16 和 iOS 17 均需逐项进行，目前未验证）：

1. 安装后冷启动 App、打开键盘，新建 JS 动作并保存；确认上下工具栏、点按、滑动、子动作均可选到它。热启动重复执行。
2. 备忘录、微信和 Safari 文本框测试全文/部分选区/空输入、中英文/emoji；替换范围正确，撤销行为符合宿主预期，键盘不先收起再弹出。
3. 多项结果菜单可滚动、选择/取消；`function` 菜单选择后再请求网络。多窗口/iPad 下使用原 Scene；旋转或隐藏键盘关闭菜单。
4. GET/POST 返回文本后正确写回；HTTP 错误、断网、无效 Scheme 保留原文并提示，不崩溃。HTTP(S)、普通 App Scheme、敏感 Scheme、应用内网页分别验证。
5. 请求期间继续打字、移动选区、切换输入框、切 App、关闭键盘、连续触发新动作，旧请求不得写入或延迟跳转。
6. 测试页展示结果/日志和函数菜单，网络真实发送，跳转仅预览；停止/离开后无晚到回调。错误脚本、无限循环、空字符串、null 行为符合说明。
7. 原文本模板、URL Scheme、网页、打开 App、App 快捷方式及 PullOver-X 路径回归；删除 JS 动作后手势/子动作引用被清理。
8. 从安装前开始捕获 syslog，筛选 `[TypeXJS]` 和既有 `[TypeX] URL scheme` / `[TypeXSB]`；只应看到会话状态/路由，不应出现输入正文、源码、响应或令牌。验证卸载后新增模块随 TypeX 主 dylib / Preferences bundle 一起移除。

源码与桌面测试、构建和包检查不能代替上述设备行为验证。

## 本次验证记录（2026-09-26）

- 源码审查与 diff 空白检查通过；原有动作分支及打开通道实现未改写。
- 实际 JavaScriptCore：25 项用例及取消后回调隔离通过，包含 30 秒未完成 Promise、顶层/async 死循环中断。
- 原有 Darwin 通道与敏感 URL 执行器回归通过。
- 项目构建脚本产出 3.6.5 两套 DEB（ios16 / ios17）；两套均含 arm64、arm64e。依照既有脚本，ios17 标签仍使用 iOS 16.5 SDK、最低部署版本 15.0。
- 两包已核对版本/架构、JavaScriptCore 链接、引擎/宿主/编辑测试控制器、双语资源和既有 postinst/postrm 的存在。安装与卸载的实际行为未验证。
- 设备验收待完成：`idevice_id -l` 没有返回设备，当前开发工具不提供 `simctl`。不将上述结果表述为 iOS 16/17 真机通过。
