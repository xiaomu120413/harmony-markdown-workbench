// 捕获脚本执行期错误（写入 DOM 供原生读取）
window.addEventListener('error', function (e) {
  try {
    var d = document.createElement('div');
    d.id = 'js-err';
    d.textContent = 'ERR:' + (e.message || 'unknown') + '@' + (e.filename || '') + ':' + (e.lineno || 0);
    document.body.appendChild(d);
  } catch (ignore) {}
});
/**
 * 编辑运行时 Web 侧入口（CodeMirror 6，本地打包离线可用）。
 * 桥协议（M2-02 正式化）：Web→原生统一发送 JSON 信封
 *   { version: 1, id, type, payload }
 * 原生侧 send(raw) 单参数接收（BridgeProtocol.parseEvent 解析；
 * 修复记录：此前双参数调用与原生签名不匹配，edit 事件从未到达原生侧）。
 * 原生→Web 命令经 runJavaScript 调用 __editorApi（返回值通道）。
 */
import { inspectMarkdown, renderMarkdown } from './markdown';
import { inspectHtml, bundleHtml } from './html-embed';
import { basicSetup } from 'codemirror';
import { EditorView, placeholder, keymap } from '@codemirror/view';
import { EditorState, Compartment } from '@codemirror/state';
import { markdown } from '@codemirror/lang-markdown';
import { undo, redo } from '@codemirror/commands';

// 文件交给原生 UDMF 授权入口；禁止 Web 默认导航/读取文件覆盖当前编辑状态。
for (const type of ['dragover', 'drop']) {
  document.addEventListener(type, event => {
    const transfer = event.dataTransfer;
    if (transfer && (Array.from(transfer.types || []).includes('Files') || transfer.files.length > 0)) {
      event.preventDefault();
      event.stopImmediatePropagation();
    }
  }, true);
}

var notifySeq = 0;
function genId() {
  notifySeq++;
  return Date.now() + '-' + notifySeq;
}

function notify(type, payload) {
  var bridge = window.__nativeBridge;
  if (bridge && typeof bridge.send === 'function') {
    try {
      bridge.send(JSON.stringify({ version: 1, id: genId(), type: type, payload: payload }));
    } catch (e) {
      console.log('MUMARK_BRIDGE_SEND_ERR type=' + type + ' err=' + e);
    }
  }
}

const themeDark = EditorView.theme({
  '&': { backgroundColor: '#1e1e1e', color: '#d4d4d4' },
  '.cm-content': { caretColor: '#fff' },
  '.cm-gutters': { backgroundColor: '#1e1e1e', color: '#6b7078', border: 'none' },
  '.cm-activeLine': { backgroundColor: '#26262a' },
  '.cm-activeLineGutter': { backgroundColor: '#2a2a2f', color: '#d4d4d4' },
  // 深色下选区需要明显高于正文底色；同时显式指定选中文字颜色，避免系统高亮前景不可见。
  '&.cm-focused .cm-selectionBackground, .cm-selectionBackground, .cm-content ::selection': {
    backgroundColor: '#3b5fa8',
  },
  '.cm-content ::selection': { color: '#ffffff' },
  '.cm-cursor': { borderLeftColor: '#fff' },
  '.cm-selectionMatch': { backgroundColor: '#3a5a3a' },
}, { dark: true });

// 设置（M5-03）：主题/字号/自动换行/行号以 Compartment 动态切换（reconfigure 不重载文档）
const editableC = new Compartment();
const themeC = new Compartment();
const fontC = new Compartment();
const wrapC = new Compartment();
const gutterHidden = EditorView.theme({
  '& .cm-gutters': { display: 'none' },
});
const gutterShown = EditorView.theme({
  '& .cm-gutters': { display: 'block' },
});
const gutterC = new Compartment();

const myTheme = EditorView.baseTheme({
  '&': { height: '100%' },
  '.cm-scroller': { fontFamily: 'monospace', overflow: 'auto' },
});

// 桌面/平板上编辑内容限宽居中（手机上视口 < 860px 时自然全宽）
const contentWide = EditorView.theme({
  '.cm-content': { maxWidth: '860px', margin: '0 auto' },
});

// ---- 编辑会话与版本（A1 快照契约）----
// editVersion：每次正文变更（输入/撤销重做/工具栏变换）单调递增；
// sessionId：加载其他文档时重新生成——旧会话的异步回包不得污染新文档。
function genSession() {
  return 's-' + Date.now() + '-' + Math.random().toString(36).slice(2, 8);
}
let sessionId = genSession();
let editVersion = 0;

// ---- 编辑事件（自动保存 + 预览同步 + 状态栏）：用户输入 → native 'edit'
// （程序化 setDocument/loadDocument 抑制通知，但版本照常递增）；光标移动 → native 'cursor'
let suppressEdit = false;
const editExt = EditorView.updateListener.of(function (u) {
  if (u.docChanged) {
    editVersion++;
    if (!suppressEdit) {
      const head = u.state.selection.main.head;
      const line = u.state.doc.lineAt(head);
      notify('edit', { len: u.state.doc.length, line: line.number, col: head - line.from + 1, v: editVersion, s: sessionId });
    }
    return;
  }
  if (suppressEdit) {
    suppressEdit = false;
    return;
  }
  if (u.selectionSet) {
    const head = u.state.selection.main.head;
    const line = u.state.doc.lineAt(head);
    notify('cursor', { line: line.number, col: head - line.from + 1 });
  }
});

const appKeymap = keymap.of([
  { key: 'Mod-s', preventDefault: true, run: () => { notify('command', { action: 'save' }); return true; } },
  { key: 'Mod-f', preventDefault: true, run: () => { notify('command', { action: 'find' }); return true; } },
  { key: 'Mod-b', preventDefault: true, run: () => { notify('command', { action: 'bold' }); return true; } },
  { key: 'Mod-i', preventDefault: true, run: () => { notify('command', { action: 'italic' }); return true; } },
  { key: 'Mod-Shift-f', preventDefault: true, run: () => { notify('command', { action: 'outline' }); return true; } },
]);

let editorOptions = { dark: false, fontSize: 15, wrap: false, lineNumbers: true };
function createEditorState(text) {
  return EditorState.create({ doc: text, extensions: [
    appKeymap, basicSetup, myTheme, markdown(), editExt, placeholder('开始输入…'),
    editableC.of(EditorView.editable.of(true)),
    themeC.of(editorOptions.dark ? themeDark : []),
    fontC.of(EditorView.theme({ '&': { fontSize: editorOptions.fontSize + 'px' } })),
    contentWide,
    wrapC.of(editorOptions.wrap ? EditorView.lineWrapping : []),
    gutterC.of(editorOptions.lineNumbers ? gutterShown : gutterHidden),
  ] });
}

let view = null;
try {
  view = new EditorView({ parent: document.body, state: createEditorState('') });
  document.title = 'CM-OK';
} catch (e) {
  document.title = 'CM-ERR:' + (e && e.message ? e.message : String(e));
}

// ---- 原生 → Web 命令入口（经 runJavaScript 调用，返回值同步回传）----
window.__editorApi = {
  loadDocument(text, nativeSession) {
    suppressEdit = true;
    // New state isolates undo history: undo must never restore the previous file.
    view.setState(createEditorState(text));
    // 新文档：新会话 + 版本归零（旧会话的异步回包不得污染新文档，A1）
    sessionId = nativeSession || genSession();
    editVersion = 0;
    suppressEdit = false;
    document.title = 'MuMark Editor';
  },
  setEditable(editable) { view.dispatch({ effects: editableC.reconfigure(EditorView.editable.of(editable)) }); return 'ok'; },
  inspectMarkdown(text) { return inspectMarkdown(text); },
  renderMarkdown(text, resources) { return renderMarkdown(text, resources); },
  inspectHtml(html, resources) { return inspectHtml(html, resources); },
  bundleHtml(html, resources) { return bundleHtml(html, resources); },
  getSnapshot() {
    return view ? view.state.doc.toString() : '';
  },
  /** A1 快照契约：会话/版本/正文一次性读取（同一次编辑器状态） */
  getSnapshotEx() {
    if (!view) {
      return JSON.stringify({ ok: false, s: sessionId, v: editVersion, c: '' });
    }
    return JSON.stringify({ ok: true, s: sessionId, v: editVersion, c: view.state.doc.toString() });
  },
  undo() {
    undo(view);
    return view.state.doc.toString().length;
  },
  redo() {
    redo(view);
    return view.state.doc.toString().length;
  },
  replaceRange(from, to, text) {
    view.dispatch({ changes: { from, to, insert: text } });
    view.focus();
  },
  getSelectionRange() {
    const sel = view.state.selection.main;
    return { from: sel.from, to: sel.to };
  },
  setDocument(text, cursorFrom, cursorTo) {
    suppressEdit = true;
    view.dispatch({ changes: { from: 0, to: view.state.doc.length, insert: text } });
    view.dispatch({ selection: { anchor: cursorFrom, head: cursorTo } });
    view.focus();
    return text.length;
  },
  /** 查找面板导航：选中 [from,to) 并滚动到可视区 */
  setSelectionRange(from, to, focus = true) {
    view.dispatch({
      selection: { anchor: from, head: to },
      effects: EditorView.scrollIntoView(from, { y: 'center' }),
    });
    if (focus) view.focus();
    return to - from;
  },
  setTheme(dark) {
    editorOptions.dark = dark;
    view.dispatch({ effects: themeC.reconfigure(dark ? themeDark : []) });
  },
  setFontSize(px) {
    editorOptions.fontSize = px;
    view.dispatch({
      effects: fontC.reconfigure(EditorView.theme({ '&': { fontSize: px + 'px' } })),
    });
  },
  setWrap(wrap) {
    editorOptions.wrap = wrap;
    view.dispatch({
      effects: wrapC.reconfigure(wrap ? EditorView.lineWrapping : []),
    });
  },
  setLineNumbers(show) {
    editorOptions.lineNumbers = show;
    view.dispatch({
      effects: gutterC.reconfigure(show ? gutterShown : gutterHidden),
    });
  },
};

// ---- D1：滚动位置上报（同步滚动数据源；顶部可视行号，防抖 100ms） ----
let scrollNotifyTimer = 0;
view.scrollDOM.addEventListener('scroll', function () {
  if (scrollNotifyTimer) {
    clearTimeout(scrollNotifyTimer);
  }
  scrollNotifyTimer = setTimeout(function () {
    scrollNotifyTimer = 0;
    const block = view.lineBlockAtHeight(view.scrollDOM.scrollTop);
    notify('editorScroll', { line: view.state.doc.lineAt(block.from).number });
  }, 100);
});

// ---- C4：应用快捷键 → 桥转发到原生统一命令（与按钮同一路径） ----
// 通知原生：Web 就绪
console.log('MUMARK_PAGE_READY bridge=' + (typeof window.__nativeBridge));
notify('ready', { version: 1 });
