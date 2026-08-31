// M0-03 诊断：捕获脚本执行期错误（写入 DOM 供原生读取）
window.addEventListener('error', function (e) {
  try {
    var d = document.createElement('div');
    d.id = 'js-err';
    d.textContent = 'ERR:' + (e.message || 'unknown') + '@' + (e.filename || '') + ':' + (e.lineno || 0);
    document.body.appendChild(d);
  } catch (ignore) {}
});
console.log('HMWB_BOOT');
/**
 * M0-03 尖峰：ArkWeb 编辑运行时 Web 侧入口（CodeMirror 6）。
 * 功能：编辑/撤销重做/语法高亮/中文输入（CM6 原生 IME）；
 * 提供最小桥接口（M2-02 将协议正式化）：
 *   - 原生侧：loadDocument / getSnapshot / setTheme / setViewMode / find / replace
 *   - Web 侧：dirtyChanged / snapshotRequested / outlineChanged
 * 资源必须全部本地打包（rawfile），离线可用（FR-PREVIEW-001 / SDD 6.3）。
 */
import { basicSetup } from 'codemirror';
import { EditorView, keymap } from '@codemirror/view';
import { EditorState } from '@codemirror/state';
import { markdown } from '@codemirror/lang-markdown';
import { defaultKeymap, historyKeymap, undo, redo } from '@codemirror/commands';

// ---- 原生侧注入的桥对象（SpikeEditorPage 通过 JavaScriptProxy 注入）----
function notify(type, payload) {
  var bridge = window.__nativeBridge;
  if (bridge && typeof bridge.send === 'function') {
    try {
      bridge.send(type, payload);
    } catch (e) {
      console.log('HMWB_BRIDGE_SEND_ERR type=' + type + ' err=' + e);
    }
  } else {
    console.log('HMWB_BRIDGE_MISSING type=' + type + ' bridge=' + (bridge ? 'no-send' : 'absent'));
  }
}

const themeDark = EditorView.theme({
  '&': { backgroundColor: '#1e1e1e', color: '#d4d4d4' },
  '.cm-content': { caretColor: '#fff' },
}, { dark: true });

const myTheme = EditorView.baseTheme({
  '&': { fontSize: '15px', height: '100%' },
  '.cm-scroller': { fontFamily: 'monospace', overflow: 'auto' },
});

// ---- 编辑事件（M4-01 自动保存）：用户输入 → native 'edit'（程序化 setDocument/loadDocument 抑制）----
let suppressEdit = false;
const editExt = EditorView.updateListener.of(function (u) {
  if (suppressEdit) {
    suppressEdit = false;
    return;
  }
  if (u.docChanged) {
    notify('edit', { len: u.state.doc.length });
  }
});

let view = null;
try {
  view = new EditorView({
    parent: document.body,
    state: EditorState.create({
      doc: '',
      extensions: [
        basicSetup,
        markdown(),
        editExt,
      ],
    }),
  });
  document.title = 'CM-OK';
} catch (e) {
  document.title = 'CM-ERR:' + (e && e.message ? e.message : String(e));
}

// ---- 原生 → Web 命令入口（经 runJavaScript 调用）----
window.__editorApi = {
  loadDocument(text) {
    suppressEdit = true;
    view.dispatch({ changes: { from: 0, to: view.state.doc.length, insert: text } });
    document.title = 'CM:len=' + view.state.doc.length + ':head=' + view.state.doc.toString().split('\n')[0];
    notify('dirtyChanged', { dirty: false });
  },
  getSnapshot() {
    return view ? view.state.doc.toString() : '';
  },
  requestSnapshot() {
    notify('snapshot', { text: view.state.doc.toString() });
  },
  requestDiagnostics() {
    const cm = document.querySelector('.cm-content');
    notify('diag', {
      api: window.__editorApi ? 'ok' : 'miss',
      cm: cm ? 'ok' : 'miss',
      len: cm ? cm.innerText.length : -1,
      head: cm ? cm.innerText.split('\n')[0] : '',
    });
  },
  insertChinese() {
    const head = view.state.selection.main.head;
    view.dispatch({ changes: { from: head, insert: '你好，鸿蒙Markdown工作台！中文输入测试。' } });
    view.focus();
    return view.state.doc.toString().length;
  },
  loadLarge(sizeKB) {
    const total = sizeKB * 1024;
    const lines = [
      '# 长文性能测试',
      '',
      '这是一段用于验证长文档性能的中文内容。CodeMirror 6 运行于 ArkWeb。列表项：',
      '- 项目一',
      '- 项目二',
      '',
      '| a | b |',
      '|---|---|',
      '| 1 | 2 |',
      '',
      '```ts',
      'const x = 1;',
      '```',
    ];
    const chunk = lines.join('\n') + '\n';
    let big = '';
    while (big.length < total) {
      big += chunk;
    }
    view.dispatch({ changes: { from: 0, to: view.state.doc.length, insert: big } });
    return view.state.doc.length;
  },
  undo() {
    undo(view);
    return view.state.doc.toString().length;
  },
  redo() {
    redo(view);
    return view.state.doc.toString().length;
  },
  copySelection() {
    const sel = view.state.selection.main;
    return view.state.doc.sliceString(sel.from, sel.to);
  },
  pasteText(text) {
    view.dispatch({ changes: { from: view.state.selection.main.head, insert: text } });
    view.focus();
    return view.state.doc.toString().length;
  },
  getSelectionRange() {
    const sel = view.state.selection.main;
    return { from: sel.from, to: sel.to };
  },
  replaceRange(from, to, text) {
    view.dispatch({ changes: { from: from, to: to, insert: text } });
    // 光标移到插入内容末尾
    const pos = from + text.length;
    view.dispatch({ selection: { anchor: pos, head: pos } });
    view.focus();
    return view.state.doc.toString().length;
  },
  getCharsAround() {
    const sel = view.state.selection.main;
    const before = view.state.doc.sliceString(Math.max(0, sel.from - 30), sel.from);
    const after = view.state.doc.sliceString(sel.to, sel.to + 30);
    return { before: before, after: after };
  },
  setDocument(text, cursorFrom, cursorTo) {
    suppressEdit = true;
    view.dispatch({ changes: { from: 0, to: view.state.doc.length, insert: text } });
    view.dispatch({ selection: { anchor: cursorFrom, head: cursorTo } });
    view.focus();
    return text.length;
  },
  setTheme(dark) {
    view.dispatch({ effects: dark ? themeDark : [] });
  },
  find(query) {
    // 尖峰：仅定位高亮首个匹配；正式 FindReplacePanel 属 M3-04。
    const text = view.state.doc.toString();
    const idx = text.indexOf(query);
    if (idx >= 0) {
      view.dispatch({ selection: { anchor: idx, head: idx + query.length } });
      view.focus();
    }
  },
};

// 通知原生：Web 就绪
console.log('HMWB_PAGE_READY bridge=' + (typeof window.__nativeBridge) + ' keys=' + (window.__nativeBridge ? Object.keys(window.__nativeBridge).join(',') : '-'));
notify('ready', { version: 1 });