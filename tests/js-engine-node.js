#!/usr/bin/env node
/**
 * TypeX JavaScript 动作 Node 调试器
 *
 * 在 Node 里复刻 TypeX JavaScript 引擎的运行契约，让 JS 动作脚本不进键盘就能调试：
 *
 *   node tests/js-engine-node.js <脚本.js> [输入文本]
 *
 * 复刻的行为：
 *   · 入口 main(str)，返回值语义与引擎一致（字符串 / 对象 / 数组，null/undefined 不动作）
 *   · $http.get/post/put/patch/delete({url, headers?, body?}) → Promise<UTF-8 文本>，
 *     非 2xx 报 "HTTP <code>"，body 必须是字符串（基于 Node 内置 fetch，请求真实发送）
 *   · $url.open / $url.openInApp / $app.open → 只打印预览，不真跳（首个导航为终点）
 *   · 数组返回 → 交互式候选菜单（键入序号回车，直接回车取消）；function 动画 → 函数链续调（上限 16 次）
 *   · 严格校验返回值（类型白名单、非 txt 的 content 必填、候选 ≤ 100）
 *
 * 与真机的已知差异：没有 0.5s CPU 限制与 30s 会话超时，请求/结果大小不设上限，
 * 网络走 Node 的 fetch（不经过 iOS ATS）；txt 写回在这里只是打印（真机按输出模式写输入框/剪贴板）。
 */
'use strict';

const fs = require('fs');
const path = require('path');
const vm = require('vm');
const readline = require('readline');

const scriptPath = process.argv[2];
if (!scriptPath) {
  console.error('用法: node tests/js-engine-node.js <脚本.js> [输入文本]');
  console.error('示例: node tests/js-engine-node.js my-action.js "1+1"   （输入留空则进入候选菜单）');
  process.exit(2);
}
const input = process.argv[3] !== undefined ? process.argv[3] : '';
const source = fs.readFileSync(scriptPath, 'utf8');

// ── $http：按引擎契约包装 Node fetch ──
async function httpRequest(method, options) {
  if (!options || typeof options !== 'object') throw new Error('HTTP options must be an object');
  const url = new URL(options.url);
  if (!/^https?:$/.test(url.protocol) || url.username || url.password) throw new Error('Invalid HTTP(S) URL');
  const init = { method, headers: options.headers || {} };
  if (options.body !== undefined && options.body !== null) {
    if (typeof options.body !== 'string') throw new Error('body must be a string; use JSON.stringify for JSON');
    init.body = options.body;
  }
  const response = await fetch(url, init);
  if (!response.ok) throw new Error('HTTP ' + response.status);
  return await response.text();
}
const $http = Object.fromEntries(
  ['get', 'post', 'put', 'patch', 'delete'].map(method => [method, options => httpRequest(method.toUpperCase(), options)])
);

// ── 直开动作：记录并预览，首个导航为终点 ──
let navigated = null;
const preview = kind => content => {
  navigated = { kind, content };
  console.log(`[跳转预览 · ${kind}] ${content}（真机上这里会实际打开并结束会话）`);
};
const $url = { open: preview('url'), openInApp: preview('urlInApp') };
const $app = { open: preview('app') };

// ── 独立全局环境执行脚本（无 fetch/setTimeout/DOM，与键盘扩展一致）──
const context = vm.createContext({ $http, $url, $app, console });
vm.runInContext(source, context, { filename: path.basename(scriptPath) });

function validate(result) {
  if (result === null || result === undefined) return [];
  const values = Array.isArray(result) ? result : [result];
  if (values.length > 100) throw new Error('At most 100 choices are supported');
  return values.map(value => {
    const item = typeof value === 'string' ? { type: 'txt', content: value } : value;
    if (!item || typeof item !== 'object' || Array.isArray(item)) {
      throw new Error('Unsupported result. Use text or {type, content, title?, args?}');
    }
    const type = item.type;
    const content = item.content;
    if (typeof type !== 'string' || !['txt', 'url', 'urlInApp', 'app', 'function'].includes(type) ||
        typeof content !== 'string' || (type !== 'txt' && !content.length)) {
      throw new Error('Unsupported result action: ' + JSON.stringify(item));
    }
    return { type, content, title: typeof item.title === 'string' && item.title.length ? item.title : content,
             args: Array.isArray(item.args) ? item.args : [] };
  });
}

function askMenu(actions) {
  console.log('── 候选菜单（输入序号回车选择，直接回车取消）──');
  actions.forEach((action, index) => console.log(`  ${index + 1}. [${action.type}] ${action.title}`));
  console.log('  0. 取消');
  const rl = readline.createInterface({ input: process.stdin, output: process.stdout });
  return new Promise(resolve => rl.question('> ', answer => {
    rl.close();
    const chosen = parseInt(answer, 10);
    resolve(Number.isInteger(chosen) && chosen >= 1 && chosen <= actions.length ? chosen - 1 : -1);
  }));
}

async function dispatch(action) {
  if (action.type === 'function') {
    const fn = context[action.content];
    if (typeof fn !== 'function') throw new Error('Missing function: ' + action.content);
    return run(fn, action.args);
  }
  if (action.type === 'txt') {
    console.log(`[txt 写回${navigated ? '（导航已发生，真机不会再写回）' : ''}]\n${action.content}`);
    return;
  }
  console.log(`[跳转预览 · ${action.type}] ${action.content}\n（真机上这里会实际打开并结束会话）`);
}

let chain = 0;
async function run(fn, args) {
  if (++chain > 16) throw new Error('Function chain exceeds 16 calls');
  const raw = await Promise.resolve().then(() => fn(...args));
  if (navigated) { console.log('（导航已发生，会话结束，后续结果不再处理）'); return; }
  const actions = validate(raw);
  if (!actions.length) { console.log('（null / undefined · 无动作）'); return; }
  if (actions.length === 1) return dispatch(actions[0]);
  const chosen = await askMenu(actions);
  if (chosen === -1) { console.log('（已取消）'); return; }
  return dispatch(actions[chosen]);
}

(async () => {
  try {
    if (typeof context.main !== 'function') throw new Error('脚本缺少 main(str) 入口');
    await run(context.main, [input]);
  } catch (error) {
    console.error('❌ ' + (error && error.message ? error.message : String(error)));
    process.exitCode = 1;
  }
})();
