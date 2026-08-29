/**
 * M0-03 尖峰：ArkWeb 编辑运行时 Web 侧入口（CodeMirror 6）。
 * 功能：编辑/撤销重做/语法高亮/中文输入（CM6 原生 IME）；
 * 提供最小桥接口（M2-02 将协议正式化）：
 *   - 原生侧：loadDocument / getSnapshot / setTheme / setViewMode / find / replace
 *   - Web 侧：dirtyChanged / snapshotRequested / outlineChanged
 * 资源必须全部本地打包（rawfile），离线可用（FR-PREVIEW-001 / SDD 6.3）。
 */
import { basicSetup } from '@codemirror/basic-setup';
import { EditorView, keymap } from '@codemirror/view';
import { EditorState } from '@codemirror/state';
import { markdown } from '@codemirror/lang-markdown';
import { defaultKeymap, historyKeymap } from '@codemirror/commands';

// ---- 原生侧注入的桥对象（SpikeEditorPage 通过 JavaScriptProxy 注入）----
function notify(type, payload) {
  if (window.__nativeBridge && typeof window.__nativeBridge.postMessage === 'function') {
    window.__nativeBridge.postMessage(type, payload);
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

const view = new EditorView({
  parent: document.body,
  state: EditorState.create({
    doc: '',
    extensions: [
      basicSetup,
      markdown(),
      historyKeymap,
      keymap.of([...defaultKeymap]),
      myTheme,
      EditorView.updateListener.of((update) => {
        if (update.docChanged) {
          notify('dirtyChanged', { dirty: true });
        }
      }),
    ],
  }),
});

// ---- 原生 → Web 命令入口（经 runJavaScript 调用）----
window.__editorApi = {
  loadDocument(text) {
    view.dispatch({ changes: { from: 0, to: view.state.doc.length, insert: text } });
    notify('dirtyChanged', { dirty: false });
  },
  getSnapshot() {
    return view.state.doc.toString();
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
notify('ready', { version: 1 });