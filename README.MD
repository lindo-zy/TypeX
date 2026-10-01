# TypeX

TypeX 是一款可自定义键盘快捷操作栏的 iOS 插件。在系统键盘的底部 dock 与键盘上方各提供一排可自由编辑的工具栏，内置 35 种键盘动作，支持六向手势、子动作链、自定义动作（文本 / URL / URL Scheme / 打开应用 / 快捷方式 / JavaScript）、AI 问答面板、剪贴板悬浮粘贴，以及与 ShellX、PullOver X、Kayoko 等插件的联动。

## 功能总览

- **双工具栏**：顶部工具栏 + 底部工具栏，按钮数量不限、拖动排序，两套外观参数相互独立
- **35 种内置键盘动作**：编辑、光标移动、范围选择与插件联动动作
- **六向手势**：每个按钮可分别配置单击、长按、上滑、下滑、左滑、右滑
- **子动作链**：每个按钮可挂一条有序子动作链，长按或点按触发
- **自定义动作**：文本、URL、URL Scheme、打开应用、快捷方式、JavaScript 六类
- **JavaScript 引擎**：基于 JavaScriptCore 的脚本动作，支持 `$http`、返回候选菜单等
- **AI 问答面板**：多引擎（OpenAI 兼容协议）、流式输出、人设系统、Markdown 渲染
- **剪贴板悬浮粘贴**：剪贴板出现新内容时在光标旁弹出 3 秒悬浮条，点按即粘贴
- **跨进程系统动作**：打开应用、敏感 URL Scheme、快捷方式经 SpringBoard 通道代执行
- **第三方联动**：ShellX 截图、PullOver X「小把手」、Kayoko 剪贴板

## 详细功能

### 工具栏

- **顶部工具栏**：寄生于键盘上方（input accessory），默认单行高度 41.5pt；支持多行模式，最多两行、每行个数可调（1–8），最多同时启用 16 个按钮
- **底部工具栏**：寄生于键盘 dock 区域，按钮按每行个数横向分页浏览；支持工具栏高度与底部间距调节
- 按钮：可无限添加，拖动调整顺序，点按编辑 / 删除手势，开关控制是否显示
- 每工具栏独立的按钮设置：显示样式（图标 / 短文本）、按钮宽度、高度、圆角半径、间距、边框（开关 + 粗细）、面板大小
- 设置页内置**测试输入框**与**顶部工具栏预览**，改配置即刻可见

### 内置键盘动作（35 种）

- **文本编辑**：全选、选择、复制、粘贴、剪切、撤销、重做、删除、向后删除、删除单词、清空、收起键盘、查词
- **光标移动**：左 / 右 / 上 / 下、上一个词 / 下一个词、行首 / 行尾、段首 / 段尾、句首 / 句尾、文档开头 / 结尾
- **范围选择**：选择整行、选择整段、选择整句
- **联动动作**：AI 问答、ShellX 截图、剪贴板（唤起 Kayoko）、小把手（唤起 PullOver X）

### 手势与子动作

- 每个按钮 6 个手势槽位：**单击、长按、上滑、下滑、左滑、右滑**，各自绑定任意动作
- 单击可完全替换按钮原有功能，长按则保留原有功能
- **子动作链**：每个按钮可配置一条按顺序执行的子动作链（可添加多个，任意组合）
- 长按触发子动作：仅配置一个时直接执行，多个时弹出面板选择；「点按触发子动作」开关可让点按也直接触发子动作链
- 子动作面板大小独立设置（顶部 / 底部相互独立）；iOS 17 起面板使用独立窗口展示，不干扰键盘窗口层级

### 自定义动作（6 类）

在「自定义动作」页创建，创建后可绑定到任意工具栏按钮、手势槽位或子动作链：

| 类型 | 行为 |
| --- | --- |
| **文本** | 以记录列表管理纯文本，默认一条，可添加、编辑、删除和排序；一条直接插入，多条显示悬浮列表，点选插入并关闭，原样保留空格与换行 |
| **URL** | 打开网址，可选 APP 内打开（内置浏览器）；支持 `@@@` 传入当前输入框内容，可选「剪切替换」 |
| **URL Scheme** | 执行 URL Scheme 跳转；敏感 Scheme 自动经 SpringBoard 通道执行；支持 `@@@` 入参与「剪切替换」 |
| **打开应用** | 通过 Bundle ID 打开应用；安装 PullOver X 后可交由其接管打开 |
| **快捷方式** | 执行任意应用长按菜单中的静态 / 动态快捷项（由 SpringBoard 端枚举） |
| **JavaScript** | 见下节 |

文本动作使用新的记录格式，不读取或迁移旧的文本配置；旧文本动作需要重新填写记录。

- 图标支持 **SF Symbols 名称**（如 `doc.on.doc`）或**应用 Bundle ID**（显示对应应用图标）
- 管理页：点按行直接编辑、右滑删除，动作带类型分类展示

### JavaScript 自定义动作

入口为 `async function main(str)`，每次触发创建独立 JavaScriptCore 上下文（无 DOM / Node 环境）：

- **输入**：选区优先（无选区读全文）、全文、剪贴板三种模式
- **输出**：替换 / 插入 / 复制，或返回值驱动：
  - 字符串 → 文本写入
  - `{type, content, title?, args?}` → `txt` / `url` / `urlInApp` / `app` / `function`
  - 数组 → 弹出候选菜单（多项时不抢键盘焦点）
  - `function` → 调用脚本内全局函数，支持异步与后续调用
- **接口**：`$http.get/post/put/patch/delete({url, headers?, body?})`、`$url.open()`、`$url.openInApp()`、`$app.open()`、`console.log`
- 内置**测试脚本页**：网络请求真实发送，文本与跳转动作只预览，日志仅保留在页面内
- 密码框、未完成的输入法组合文本不会执行脚本；会话失效（键盘隐藏、App 失活等）时自动取消并回写保护

#### 脚本示例

以下 10 个示例均可直接粘贴到设置内的「测试脚本页」运行（下述网络示例的请求会真实发送；限定：无 DOM / `fetch` / `setTimeout`，`$http` 返回 UTF-8 字符串需自行 `JSON.parse`，候选菜单最多 100 项，单次 CPU 约 0.5 秒）。

**1. 文本清洗**——去掉每行首尾空白、压缩行内连续空白、删除空行（输入：选区优先；输出：替换）

```js
async function main(str) {
  return str.split('\n')
    .map(line => line.replace(/\s+/g, ' ').trim())
    .filter(Boolean)
    .join('\n');
}
```

**2. 字数统计**——中英混排统计字符 / 英文单词 / 行数（输出：替换或复制）

```js
async function main(str) {
  const chars = Array.from(str.replace(/\s/g, '')).length;
  const words = (str.match(/[A-Za-z0-9'_-]+/g) || []).length;
  const lines = str ? str.split('\n').length : 0;
  return `共 ${chars} 个字符、${words} 个英文单词、${lines} 行`;
}
```

**3. JSON 美化 / 压缩**——弹出候选菜单二选一；解析失败时返回错误说明而不是中断（输出：替换）

```js
async function main(str) {
  try {
    const value = JSON.parse(str);
    return [
      { type: 'txt', title: '格式化（2 空格缩进）', content: JSON.stringify(value, null, 2) },
      { type: 'txt', title: '压缩为单行', content: JSON.stringify(value) },
    ];
  } catch (error) {
    return 'JSON 解析失败：' + error.message;
  }
}
```

**4. 时间戳 ↔ 日期互转**——选中 10 / 13 位时间戳转为本地时间，空输入则给出当前时间与时间戳（输出：替换）

```js
async function main(str) {
  const input = str.trim();
  const pad = n => String(n).padStart(2, '0');
  const fmt = d => `${d.getFullYear()}-${pad(d.getMonth() + 1)}-${pad(d.getDate())}` +
                   ` ${pad(d.getHours())}:${pad(d.getMinutes())}:${pad(d.getSeconds())}`;
  if (/^\d{10}$/.test(input)) return fmt(new Date(Number(input) * 1000));
  if (/^\d{13}$/.test(input)) return fmt(new Date(Number(input)));
  return [
    { type: 'txt', title: '当前时间', content: fmt(new Date()) },
    { type: 'txt', title: '秒级时间戳', content: String(Math.floor(Date.now() / 1000)) },
    { type: 'txt', title: '毫秒级时间戳', content: String(Date.now()) },
  ];
}
```

**5. 编码工具箱**——URL 编解码、HTML 转义、Unicode 码点；解码失败安全兜底（输出：替换）

```js
async function main(str) {
  const safe = fn => { try { return fn(); } catch (e) { return `（解码失败：${e.message}）`; } };
  const html = str.replace(/[&<>"']/g, c => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]));
  const points = Array.from(str).map(ch => '\\u' + ch.codePointAt(0).toString(16).padStart(4, '0'));
  return [
    { type: 'txt', title: 'URL 编码', content: encodeURIComponent(str) },
    { type: 'txt', title: 'URL 解码', content: safe(() => decodeURIComponent(str)) },
    { type: 'txt', title: 'HTML 转义', content: html },
    { type: 'txt', title: 'Unicode 码点', content: points.join(' ') },
  ];
}
```

**6. 搜索跳转与快捷面板**——有输入直接跳转搜索（`return null` 表示不写回文本），空输入弹出三类打开方式的候选面板

```js
async function main(str) {
  const q = str.trim();
  if (q) {
    $url.open('https://www.bing.com/search?q=' + encodeURIComponent(q));
    return null; // 已跳转，本次不再写回文本
  }
  return [
    { type: 'url', title: '打开 Bing', content: 'https://www.bing.com' },
    { type: 'urlInApp', title: '应用内打开 Bing', content: 'https://www.bing.com' },
    { type: 'app', title: '打开系统设置', content: 'com.apple.Preferences' },
  ];
}
```

**7. GitHub 用户查询**——`$http.get` + 候选菜单（文本 / 浏览器打开 / 应用内打开）+ `console.log`

```js
async function main(str) {
  const name = str.trim() || 'apple';
  const raw = await $http.get({ url: 'https://api.github.com/users/' + encodeURIComponent(name) });
  const info = JSON.parse(raw);
  console.log('已获取 GitHub 用户：' + info.login);
  return [
    { type: 'txt', title: '昵称', content: String(info.name || info.login) },
    { type: 'txt', title: '粉丝数', content: String(info.followers) },
    { type: 'url', title: '浏览器打开主页', content: info.html_url },
    { type: 'urlInApp', title: '应用内打开主页', content: info.html_url },
  ];
}
```

**8. POST 提交 JSON**——自定义请求头 + `JSON.stringify` 请求体（请求会被真实发送到演示服务）

```js
async function main(str) {
  const raw = await $http.post({
    url: 'https://jsonplaceholder.typicode.com/posts',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ title: '来自 TypeX', body: str || '（空输入）', userId: 1 }),
  });
  const created = JSON.parse(raw);
  return '演示帖子已创建，服务端分配 ID：' + created.id;
}
```

**9. 实时天气（免密钥 API）**——输入「纬度，经度」查实时气温风速，留空默认上海

```js
async function main(str) {
  const [lat, lon] = (str.trim() || '31.23,121.47').split(',').map(s => s.trim());
  const url = 'https://api.open-meteo.com/v1/forecast?latitude=' + encodeURIComponent(lat) +
              '&longitude=' + encodeURIComponent(lon) + '&current=temperature_2m,wind_speed_10m';
  const now = JSON.parse(await $http.get({ url })).current;
  return `当前气温 ${now.temperature_2m}°C，风速 ${now.wind_speed_10m} km/h`;
}
```

**10. 掷骰子（函数链）**——候选菜单里点「再掷一次」会继续调用脚本内 `roll` 并再次弹菜单（`function` 类型后续调用上限 16 次，模块级状态在整个会话内保留）

```js
let sides = 6;
async function main(str) {
  sides = Math.min(100, Math.max(2, parseInt(str, 10) || 6));
  return roll();
}
async function roll() {
  const value = Math.floor(Math.random() * sides) + 1;
  return [
    { type: 'txt', title: `🎲 ${value}（${sides} 面骰）`, content: String(value) },
    { type: 'function', title: '再掷一次', content: 'roll', args: [] },
  ];
}
```

更多接口细节与限制见 [tests/JAVASCRIPT_ACTIONS.md](tests/JAVASCRIPT_ACTIONS.md)；引擎级回归可用 `python3 tests/run-javascript-engine.py` 验证。

### AI 问答

- **引擎**：内置 OpenAI、DeepSeek、Gemini、智谱、通义、豆包、硅基流动，也可添加任意 OpenAI 兼容的自定义引擎；统一 OpenAI 兼容协议（Gemini 走其兼容端点）
- **模型抓取**：按厂商自适应端点拉取模型列表，模型可手动逗号分隔填写
- **人设系统**：自定义人设列表，可设文字问答 / 图片问答 / AI 问答默认；人设即按钮，显示在框选菜单中
- **面板**：流式输出、Markdown 渲染、深色 / 浅色 / 跟随系统主题、相机 / 相册 / 文件附件、复制回复
- 从工具栏「AI问答」动作或文本框选菜单唤起；键盘进程内直弹，扩展场景经 SpringBoard 通道兜底

### 剪贴板悬浮粘贴

- 剪贴板出现**新**图片或文本时，在键盘上方、与输入光标等高的屏幕右缘悬浮 3 秒
- 图片显示缩略图，文本显示预览；点按即粘贴到当前输入框
- 开启期间自动放行系统「允许粘贴」询问弹窗
- 按「生效应用」逐应用开关（默认全关），应用选择页支持多选与搜索

### 跨进程系统动作

键盘扩展与沙盒应用内无法直接打开敏感 URL Scheme / 应用 / 快捷方式，TypeX 将这类请求交由随包注入 SpringBoard 的伴生模块 **TypeXSB** 代为执行：

- 请求经 Darwin 通知 + 请求文件通道送达 SpringBoard，执行后返回结果回执（成功 / 失败 / 超时等）
- 单次发送、不重试；带超时与生命周期守卫
- 不引入 RocketBootstrap 或其他新依赖

### 第三方联动

| 插件 | 联动方式 |
| --- | --- |
| **ShellX** | 工具栏「ShellX 截图」动作触发 ShellX 截图（检测到已安装才出现在动作目录）；可设置截图时先隐藏键盘 |
| **PullOver X** | 「小把手」动作唤醒 PullOver X 窗口；「打开应用」动作可交由 PullOver X 接管 |
| **Kayoko / KayokoX** | 「剪贴板」动作唤起 Kayoko 剪贴板管理器（检测到已安装才出现在动作目录） |

### 外观与其他

- 按钮颜色、按钮背景颜色、顶部工具栏背景颜色：跟随系统（自动适配深浅色）或自定义颜色
- 触感反馈开关
- 空格键左右滑动滚动视图（默认开启，滚动粒度可经偏好键 `granularityvalue` 调整）
- 空格滚动、地球键 / 听写键接管等旧版高级设置已随界面精简移除，相关行为仍由偏好键驱动
- 中英双语界面

## 系统要求

- iOS 15 及以上（iOS 17+ 部分面板使用独立 API 分流），arm64 / arm64e
- RootHide 根 hiding 环境下的 rootless 越狱（deb 以 roothide 方案打包）
- 与 ActionBar（com.restiveconch.actionbar）、DockX（com.udevs.dockx / com.lindo.dockx）冲突

## 构建

依赖 [Theos](https://github.com/theos/theos)（含 iPhoneOS 16.5 SDK）。执行：

```bash
./build.sh
```

脚本会依次构建 `ios16`、`ios17` 两个变体，产物输出到 `packages/ios16/`、`packages/ios17/`，并在两次构建完成后自动推进 `control` 中的版本号（PATCH 满 10 进位到 MINOR）。测试引擎等纯逻辑模块可用 `tests/run-*.py` 本地运行。

## 项目结构

```
TypeX.xm                主注入代码（键盘 / SpringBoard hook）
DXPrefsManager          偏好读写与跨进程快照（分层读取、快照自愈）
DXCollectionView        工具栏与按钮渲染、动作分派
DXShortcutsGenerator    内置动作目录与第三方插件探测
DXSystemOpenBroker      跨进程打开动作通道（应用 / 敏感 URL / 快捷方式）
DXDarwinOpenChannel     Darwin 通知 + 请求文件通道实现
DXJavaScriptEngine      JavaScript 自定义动作引擎
DXAIEngine / DXAIPanel  AI 问答引擎与面板
DXPasteChip             剪贴板悬浮粘贴
typexprefs/             设置面板（TypeXPrefs，含 vendored AltList）
tests/                  引擎级测试与设计文档
```

## 致谢

特别感谢 **udevs**、**lclrc乌贼**、**Aransh**。

## 许可证

[AGPL-3.0](LICENSE)
